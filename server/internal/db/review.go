package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// reviewStatusDecided is a query-only pseudo-status: it is never stored, but a
// listing filtered by it returns every entry that is not pending.
const reviewStatusDecided = "decided"

// ReviewEntry is one review queue row. Payload and Snapshot are JSON
// documents owned by the service layer: the unit's tracks and scored
// candidates, and the pre-apply field values a revert restores.
type ReviewEntry struct {
	ID             string
	Kind           string
	Status         string
	MediaType      string
	Origin         string
	LibraryPID     string
	UploadedBy     string
	Title          string
	Artist         string
	TrackCount     int
	Identifying    bool
	BestMBID       string
	BestTitle      string
	BestArtist     string
	BestYear       int
	BestSimilarity float64
	AppliedMBID    string
	Auto           bool
	Payload        string
	Snapshot       string
	CreatedAtNS    int64
	DecidedAtNS    int64
	DecidedBy      string
}

const reviewCols = `id, kind, status, media_type, origin, library_pid, uploaded_by,
	title, artist, track_count, identifying, best_mbid, best_title, best_artist,
	best_year, best_similarity, applied_mbid, auto, payload, snapshot,
	created_at_ns, decided_at_ns, decided_by`

func scanReview(row interface{ Scan(...any) error }) (ReviewEntry, error) {
	var e ReviewEntry
	err := row.Scan(&e.ID, &e.Kind, &e.Status, &e.MediaType, &e.Origin, &e.LibraryPID,
		&e.UploadedBy, &e.Title, &e.Artist, &e.TrackCount, &e.Identifying, &e.BestMBID,
		&e.BestTitle, &e.BestArtist, &e.BestYear, &e.BestSimilarity, &e.AppliedMBID,
		&e.Auto, &e.Payload, &e.Snapshot, &e.CreatedAtNS, &e.DecidedAtNS, &e.DecidedBy)
	return e, err
}

// InsertReviewEntry stores a new entry.
func (d *DB) InsertReviewEntry(ctx context.Context, e ReviewEntry) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO review_entries (`+reviewCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.Kind, e.Status, e.MediaType, e.Origin, e.LibraryPID, e.UploadedBy,
		e.Title, e.Artist, e.TrackCount, e.Identifying, e.BestMBID, e.BestTitle,
		e.BestArtist, e.BestYear, e.BestSimilarity, e.AppliedMBID, e.Auto, e.Payload,
		e.Snapshot, e.CreatedAtNS, e.DecidedAtNS, e.DecidedBy)
	if err != nil {
		return fmt.Errorf("db: inserting review entry: %w", err)
	}
	return nil
}

// ReviewEntryByID fetches one entry.
func (d *DB) ReviewEntryByID(ctx context.Context, id string) (ReviewEntry, error) {
	e, err := scanReview(d.r.QueryRowContext(ctx,
		`SELECT `+reviewCols+` FROM review_entries WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return ReviewEntry{}, ErrNotFound
	}
	if err != nil {
		return ReviewEntry{}, fmt.Errorf("db: reading review entry: %w", err)
	}
	return e, nil
}

// UpdateReviewEntry rewrites a stored entry (same id).
func (d *DB) UpdateReviewEntry(ctx context.Context, e ReviewEntry) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE review_entries SET kind = ?, status = ?, media_type = ?, origin = ?,
			library_pid = ?, uploaded_by = ?, title = ?, artist = ?, track_count = ?,
			identifying = ?, best_mbid = ?, best_title = ?, best_artist = ?,
			best_year = ?, best_similarity = ?, applied_mbid = ?, auto = ?,
			payload = ?, snapshot = ?, decided_at_ns = ?, decided_by = ?
		WHERE id = ?`,
		e.Kind, e.Status, e.MediaType, e.Origin, e.LibraryPID, e.UploadedBy, e.Title,
		e.Artist, e.TrackCount, e.Identifying, e.BestMBID, e.BestTitle, e.BestArtist,
		e.BestYear, e.BestSimilarity, e.AppliedMBID, e.Auto, e.Payload, e.Snapshot,
		e.DecidedAtNS, e.DecidedBy, e.ID)
	if err != nil {
		return fmt.Errorf("db: updating review entry: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ListReviewEntries pages entries newest first, optionally filtered by
// status and, for non-admin callers, by uploader. The cursor is the
// previous page's last (created_at_ns, id).
func (d *DB) ListReviewEntries(ctx context.Context, status, uploader string, beforeNS int64, beforeID string, limit int) ([]ReviewEntry, error) {
	q := `SELECT ` + reviewCols + ` FROM review_entries WHERE 1=1`
	args := []any{}
	switch {
	case status == reviewStatusDecided:
		// "decided" spans every terminal status; filtering server-side keeps
		// keyset pagination honest (a page of all-pending heads would
		// otherwise return empty after a client-side pending drop).
		q += ` AND status != 'pending'`
	case status != "":
		q += ` AND status = ?`
		args = append(args, status)
	}
	if uploader != "" {
		q += ` AND uploaded_by = ?`
		args = append(args, uploader)
	}
	if beforeID != "" {
		q += ` AND (created_at_ns < ? OR (created_at_ns = ? AND id < ?))`
		args = append(args, beforeNS, beforeNS, beforeID)
	}
	q += ` ORDER BY created_at_ns DESC, id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing review entries: %w", err)
	}
	defer rows.Close()
	var out []ReviewEntry
	for rows.Next() {
		e, err := scanReview(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning review entry: %w", err)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// ReviewStats aggregates entry counts by status plus the auto-apply
// calibration counters.
type ReviewStats struct {
	Pending             int
	Identifying         int
	Applied             int
	AutoApplied         int
	AsIs                int
	Unofficial          int
	Skipped             int
	Reverted            int
	RevertedAutoApplied int
}

// ReviewStatsNow computes the current statistics.
func (d *DB) ReviewStatsNow(ctx context.Context) (ReviewStats, error) {
	var s ReviewStats
	err := d.r.QueryRowContext(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE status = 'pending'),
			COUNT(*) FILTER (WHERE status = 'pending' AND identifying = 1),
			COUNT(*) FILTER (WHERE status = 'applied'),
			COUNT(*) FILTER (WHERE status = 'auto-applied'),
			COUNT(*) FILTER (WHERE status = 'as-is'),
			COUNT(*) FILTER (WHERE status = 'unofficial'),
			COUNT(*) FILTER (WHERE status = 'skipped'),
			COUNT(*) FILTER (WHERE status = 'reverted'),
			COUNT(*) FILTER (WHERE status = 'reverted' AND auto = 1)
		FROM review_entries`).Scan(
		&s.Pending, &s.Identifying, &s.Applied, &s.AutoApplied, &s.AsIs,
		&s.Unofficial, &s.Skipped, &s.Reverted, &s.RevertedAutoApplied)
	if err != nil {
		return ReviewStats{}, fmt.Errorf("db: review stats: %w", err)
	}
	return s, nil
}

// PendingReviewUnit names one entry still awaiting a decision, by the
// three columns that define the album unit it covers.
type PendingReviewUnit struct {
	LibraryPID string
	Title      string
	Artist     string
}

// PendingReviewUnits lists the units still awaiting a decision.
//
// The discovery sweeper's idempotence guard. An album unit is defined by
// its library, its album title, and its album artist, so an entry
// already waiting on those three is an entry for the same unit - which
// is what a re-read of the change log, or an album whose files straddle
// two passes, would otherwise open a second time.
//
// The values come back exactly as stored, and the caller folds case
// itself. SQLite's lower() is ASCII-only (it leaves "ÉTÉ" as "ÉtÉ")
// while Go's strings.ToLower is not, so folding here and comparing
// there would make every accented album miss its own entry and open a
// fresh one on every tick, forever. Columns only: the payload holds the
// exact file list, and parsing every pending entry's JSON on every tick
// to learn what three indexed columns answer is not worth the
// exactness.
func (d *DB) PendingReviewUnits(ctx context.Context) ([]PendingReviewUnit, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT library_pid, title, artist FROM review_entries
		WHERE status = 'pending'`)
	if err != nil {
		return nil, fmt.Errorf("db: listing pending review units: %w", err)
	}
	defer rows.Close()
	var out []PendingReviewUnit
	for rows.Next() {
		var unit PendingReviewUnit
		if err := rows.Scan(&unit.LibraryPID, &unit.Title, &unit.Artist); err != nil {
			return nil, fmt.Errorf("db: listing pending review units: %w", err)
		}
		out = append(out, unit)
	}
	return out, rows.Err()
}

// EnqueueMatch queues an entry for the identify worker. Re-queueing an
// already queued entry is a no-op.
func (d *DB) EnqueueMatch(ctx context.Context, entryID string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO match_queue (entry_id) VALUES (?)
		ON CONFLICT (entry_id) DO NOTHING`, entryID)
	if err != nil {
		return fmt.Errorf("db: queuing match: %w", err)
	}
	return nil
}

// MatchQueueRow is one queued identify job.
type MatchQueueRow struct {
	ID       int64
	EntryID  string
	Attempts int
}

// LeaseMatch claims the oldest lease-free identify job; ErrNotFound
// when the queue is idle.
func (d *DB) LeaseMatch(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (MatchQueueRow, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE match_queue SET lease_until_ns = ? + ?
		WHERE id = (
			SELECT id FROM match_queue
			WHERE lease_until_ns < ? AND next_at_ns <= ? AND attempts < ?
			ORDER BY id LIMIT 1
		)
		RETURNING id, entry_id, attempts`,
		nowNS, leaseNS, nowNS, nowNS, maxAttempts)
	var r MatchQueueRow
	if err := row.Scan(&r.ID, &r.EntryID, &r.Attempts); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return MatchQueueRow{}, ErrNotFound
		}
		return MatchQueueRow{}, fmt.Errorf("db: leasing match: %w", err)
	}
	return r, nil
}

// CompleteMatch removes a finished identify job.
func (d *DB) CompleteMatch(ctx context.Context, id int64) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM match_queue WHERE id = ?`, id); err != nil {
		return fmt.Errorf("db: completing match: %w", err)
	}
	return nil
}

// FailMatch records a failed attempt and holds the row until retryAtNS.
func (d *DB) FailMatch(ctx context.Context, id int64, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE match_queue SET attempts = attempts + 1, lease_until_ns = ?, next_at_ns = ?, last_error = ?
		WHERE id = ?`, retryAtNS, retryAtNS, msg, id)
	if err != nil {
		return fmt.Errorf("db: failing match: %w", err)
	}
	return nil
}

// DropExhaustedMatches removes jobs out of attempts, marking their
// entries as no longer identifying so they do not spin forever.
func (d *DB) DropExhaustedMatches(ctx context.Context, maxAttempts int) ([]string, error) {
	rows, err := d.w.QueryContext(ctx, `
		DELETE FROM match_queue WHERE attempts >= ? RETURNING entry_id`, maxAttempts)
	if err != nil {
		return nil, fmt.Errorf("db: dropping exhausted matches: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("db: scanning exhausted match: %w", err)
		}
		out = append(out, id)
	}
	return out, rows.Err()
}
