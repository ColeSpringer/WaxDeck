package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// SilenceMap is one cached silence analysis, keyed by audio essence so
// retags and moves never invalidate it. Spans is the JSON the service
// stores (millisecond spans, ordered); the loudness numbers ride along
// because the same analysis measures them and voice-boost leveling
// reads them. Loudness pointers are nil for digital silence, which has
// no finite loudness.
type SilenceMap struct {
	EssenceHash     string
	DetectorVersion string
	ThresholdDB     float64
	MinSeconds      float64
	Spans           string
	DurationMS      int64
	IntegratedLUFS  *float64
	TruePeakDB      *float64
	CreatedAtNS     int64
}

// PutSilenceMap stores or replaces the map for one essence.
func (d *DB) PutSilenceMap(ctx context.Context, m SilenceMap) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO silence_maps (essence_hash, detector_version, threshold_db,
			min_seconds, spans, duration_ms, integrated_lufs, true_peak_db, created_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (essence_hash) DO UPDATE SET
			detector_version = excluded.detector_version,
			threshold_db = excluded.threshold_db,
			min_seconds = excluded.min_seconds,
			spans = excluded.spans,
			duration_ms = excluded.duration_ms,
			integrated_lufs = excluded.integrated_lufs,
			true_peak_db = excluded.true_peak_db,
			created_at_ns = excluded.created_at_ns`,
		m.EssenceHash, m.DetectorVersion, m.ThresholdDB, m.MinSeconds,
		m.Spans, m.DurationMS, m.IntegratedLUFS, m.TruePeakDB, m.CreatedAtNS)
	if err != nil {
		return fmt.Errorf("db: writing silence map: %w", err)
	}
	return nil
}

// SilenceMapFor reads the cached map for one essence; ErrNotFound when
// never analyzed.
func (d *DB) SilenceMapFor(ctx context.Context, essenceHash string) (SilenceMap, error) {
	var m SilenceMap
	err := d.r.QueryRowContext(ctx, `
		SELECT essence_hash, detector_version, threshold_db, min_seconds,
			spans, duration_ms, integrated_lufs, true_peak_db, created_at_ns
		FROM silence_maps WHERE essence_hash = ?`, essenceHash).
		Scan(&m.EssenceHash, &m.DetectorVersion, &m.ThresholdDB, &m.MinSeconds,
			&m.Spans, &m.DurationMS, &m.IntegratedLUFS, &m.TruePeakDB, &m.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return SilenceMap{}, ErrNotFound
	}
	if err != nil {
		return SilenceMap{}, fmt.Errorf("db: reading silence map: %w", err)
	}
	return m, nil
}

// TranscriptRow is one cached, parsed transcript. A negative row
// remembers a fetch that found nothing usable, so clients polling an
// episode without a real transcript do not hammer the upstream URL;
// negative rows expire by fetched_at_ns age (the service's call), and
// FailReason keeps why, so the answer meanwhile says the same. ReadAtNS
// is when the row was stored or last read, which eviction goes by.
type TranscriptRow struct {
	EpisodePID  string
	Format      string
	Cues        string
	Negative    bool
	FailReason  string
	FetchedAtNS int64
	ReadAtNS    int64
}

// transcriptRowOverhead is what a row costs beyond its text, so a flood of
// remembered failures counts against the bound too.
const transcriptRowOverhead = 64

// transcriptEvictBatch is how many rows one eviction step reads.
const transcriptEvictBatch = 128

// transcriptEvictQuery reads the next rows to evict: those read longest
// ago, through the read-time index, never the row just stored.
const transcriptEvictQuery = `
	SELECT episode_pid, row_bytes FROM transcript_cache
	WHERE episode_pid <> ? ORDER BY read_at_ns, episode_pid LIMIT ?`

// transcriptSumQuery counts the cache's size from its rows, through the
// covering read-time index.
const transcriptSumQuery = `SELECT COALESCE(SUM(row_bytes), 0) FROM transcript_cache`

// recountTranscriptCache sets the cache's size from its rows: once when the
// database opens, so a size row that drifted from them is not kept.
func (d *DB) recountTranscriptCache(ctx context.Context) error {
	if _, err := d.w.ExecContext(ctx, `
		INSERT INTO transcript_cache_size (id, bytes) VALUES (1, (`+transcriptSumQuery+`))
		ON CONFLICT (id) DO UPDATE SET bytes = excluded.bytes`); err != nil {
		return fmt.Errorf("db: counting transcript cache: %w", err)
	}
	return nil
}

// PutTranscriptCache stores or replaces one episode's parsed transcript,
// with no bound on the cache.
func (d *DB) PutTranscriptCache(ctx context.Context, t TranscriptRow) error {
	_, err := d.StoreTranscriptCache(ctx, t, 0)
	return err
}

// StoreTranscriptCache stores or replaces one episode's parsed transcript,
// counted as read when it was fetched, and holds the cache to maxBytes (0
// for no bound): past it the rows read longest ago go, a batch at a time.
// The cache's size is kept beside it in the same transaction, so a store
// under the bound touches its own row and the size and nothing else. It
// says how many rows it evicted.
func (d *DB) StoreTranscriptCache(ctx context.Context, t TranscriptRow, maxBytes int64) (int64, error) {
	evicted, err := d.storeTranscript(ctx, t, maxBytes)
	if err != nil {
		return 0, fmt.Errorf("db: writing transcript cache: %w", err)
	}
	return evicted, nil
}

func (d *DB) storeTranscript(ctx context.Context, t TranscriptRow, maxBytes int64) (int64, error) {
	size := int64(len(t.EpisodePID) + len(t.Format) + len(t.Cues) + len(t.FailReason) + transcriptRowOverhead)
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var was int64
	if err := tx.QueryRowContext(ctx,
		`SELECT row_bytes FROM transcript_cache WHERE episode_pid = ?`, t.EpisodePID).Scan(&was); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO transcript_cache (episode_pid, format, cues, negative, fail_reason, fetched_at_ns, read_at_ns, row_bytes)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (episode_pid) DO UPDATE SET
			format = excluded.format,
			cues = excluded.cues,
			negative = excluded.negative,
			fail_reason = excluded.fail_reason,
			fetched_at_ns = excluded.fetched_at_ns,
			read_at_ns = excluded.read_at_ns,
			row_bytes = excluded.row_bytes`,
		t.EpisodePID, t.Format, t.Cues, boolInt(t.Negative), t.FailReason, t.FetchedAtNS, t.FetchedAtNS, size); err != nil {
		return 0, err
	}
	var total int64
	if err := tx.QueryRowContext(ctx, `
		INSERT INTO transcript_cache_size (id, bytes) VALUES (1, ?)
		ON CONFLICT (id) DO UPDATE SET bytes = bytes + excluded.bytes
		RETURNING bytes`, size-was).Scan(&total); err != nil {
		return 0, err
	}
	recounted := false
	recount := func() error {
		recounted = true
		return tx.QueryRowContext(ctx, transcriptSumQuery).Scan(&total)
	}
	// Every store leaves the cache within its bound, so one that finds it
	// past the bound before its own row, or a pass that finds nothing left
	// to evict, has a size row that disagrees with the rows: they are
	// counted again rather than trusted.
	if maxBytes > 0 && total-(size-was) > maxBytes {
		if err := recount(); err != nil {
			return 0, err
		}
	}
	var evicted int64
	for maxBytes > 0 && total > maxBytes {
		d.transcriptEvictions.Add(1)
		victims, freed, err := transcriptVictims(ctx, tx, t.EpisodePID, total-maxBytes)
		if err != nil {
			return 0, err
		}
		if len(victims) == 0 {
			if recounted {
				break
			}
			if err := recount(); err != nil {
				return 0, err
			}
			continue
		}
		for _, pid := range victims {
			if _, err := tx.ExecContext(ctx, `DELETE FROM transcript_cache WHERE episode_pid = ?`, pid); err != nil {
				return 0, err
			}
		}
		total -= freed
		evicted += int64(len(victims))
	}
	if evicted > 0 || recounted {
		if _, err := tx.ExecContext(ctx, `UPDATE transcript_cache_size SET bytes = ? WHERE id = 1`, total); err != nil {
			return 0, err
		}
	}
	return evicted, tx.Commit()
}

// transcriptVictims reads, from one batch of the rows read longest ago,
// the fewest that free over bytes, and what they free.
func transcriptVictims(ctx context.Context, tx *sql.Tx, keep string, over int64) ([]string, int64, error) {
	rows, err := tx.QueryContext(ctx, transcriptEvictQuery, keep, transcriptEvictBatch)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var victims []string
	var freed int64
	for rows.Next() && freed < over {
		var pid string
		var size int64
		if err := rows.Scan(&pid, &size); err != nil {
			return nil, 0, err
		}
		victims = append(victims, pid)
		freed += size
	}
	return victims, freed, rows.Err()
}

// TranscriptCacheFor reads one episode's cached transcript; ErrNotFound
// when never fetched.
func (d *DB) TranscriptCacheFor(ctx context.Context, episodePID string) (TranscriptRow, error) {
	var t TranscriptRow
	var negative int64
	err := d.r.QueryRowContext(ctx, `
		SELECT episode_pid, format, cues, negative, fail_reason, fetched_at_ns, read_at_ns
		FROM transcript_cache WHERE episode_pid = ?`, episodePID).
		Scan(&t.EpisodePID, &t.Format, &t.Cues, &negative, &t.FailReason, &t.FetchedAtNS, &t.ReadAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return TranscriptRow{}, ErrNotFound
	}
	if err != nil {
		return TranscriptRow{}, fmt.Errorf("db: reading transcript cache: %w", err)
	}
	t.Negative = negative != 0
	return t, nil
}

// TouchTranscriptCache records a read of one episode's cached transcript.
func (d *DB) TouchTranscriptCache(ctx context.Context, episodePID string, atNS int64) error {
	if _, err := d.w.ExecContext(ctx,
		`UPDATE transcript_cache SET read_at_ns = ? WHERE episode_pid = ?`, atNS, episodePID); err != nil {
		return fmt.Errorf("db: touching transcript cache: %w", err)
	}
	return nil
}

// TranscriptCacheSize reports the transcript cache's rows and the size its
// bound is held to.
func (d *DB) TranscriptCacheSize(ctx context.Context) (rows, bytes int64, err error) {
	if err := d.r.QueryRowContext(ctx, `
		SELECT (SELECT COUNT(*) FROM transcript_cache),
			COALESCE((SELECT bytes FROM transcript_cache_size WHERE id = 1), 0)`).Scan(&rows, &bytes); err != nil {
		return 0, 0, fmt.Errorf("db: sizing transcript cache: %w", err)
	}
	return rows, bytes, nil
}
