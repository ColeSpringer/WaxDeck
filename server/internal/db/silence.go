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
// negative rows expire by fetched_at_ns age (the service's call).
type TranscriptRow struct {
	EpisodePID  string
	Format      string
	Cues        string
	Negative    bool
	FetchedAtNS int64
}

// PutTranscriptCache stores or replaces one episode's parsed transcript.
func (d *DB) PutTranscriptCache(ctx context.Context, t TranscriptRow) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO transcript_cache (episode_pid, format, cues, negative, fetched_at_ns)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT (episode_pid) DO UPDATE SET
			format = excluded.format,
			cues = excluded.cues,
			negative = excluded.negative,
			fetched_at_ns = excluded.fetched_at_ns`,
		t.EpisodePID, t.Format, t.Cues, boolInt(t.Negative), t.FetchedAtNS)
	if err != nil {
		return fmt.Errorf("db: writing transcript cache: %w", err)
	}
	return nil
}

// TranscriptCacheFor reads one episode's cached transcript; ErrNotFound
// when never fetched.
func (d *DB) TranscriptCacheFor(ctx context.Context, episodePID string) (TranscriptRow, error) {
	var t TranscriptRow
	var negative int64
	err := d.r.QueryRowContext(ctx, `
		SELECT episode_pid, format, cues, negative, fetched_at_ns
		FROM transcript_cache WHERE episode_pid = ?`, episodePID).
		Scan(&t.EpisodePID, &t.Format, &t.Cues, &negative, &t.FetchedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return TranscriptRow{}, ErrNotFound
	}
	if err != nil {
		return TranscriptRow{}, fmt.Errorf("db: reading transcript cache: %w", err)
	}
	t.Negative = negative != 0
	return t, nil
}
