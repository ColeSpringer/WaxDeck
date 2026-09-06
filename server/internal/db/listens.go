package db

import (
	"context"
	"fmt"
	"time"
)

// ListenSession is one listen record as stored. ItemPID is the bare
// catalog ULID (no API type prefix).
type ListenSession struct {
	UserID    string
	SessionID string
	ItemPID   string
	MediaType string
	StartedAt time.Time
	MsPlayed  int64
	SkippedMs int64
	Finished  bool
	Client    string
	Source    string
}

// InsertListens records a batch of sessions and reports, per input
// row, whether it was new. False is the same (user, sessionId) already
// being recorded - the replay that is acknowledged and ignored, which
// is what makes ingest idempotent. A batch carrying the same id twice
// reads the same way: the first occurrence is new and the rest are
// replays of it.
//
// One transaction rather than a row at a time because the write pool
// is a single connection: a five-hundred-session flush would otherwise
// take and release it five hundred times with every other writer
// interleaving. Nothing but the inserts is inside it, so the batch
// commits before its caller touches the catalog.
func (d *DB) InsertListens(ctx context.Context, sessions []ListenSession) ([]bool, error) {
	inserted := make([]bool, len(sessions))
	if len(sessions) == 0 {
		return inserted, nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: inserting listens: %w", err)
	}
	defer tx.Rollback()
	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO listen_sessions
			(user_id, session_id, item_pid, media_type, started_at_ns,
			 ms_played, skipped_ms, finished, client, source, received_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, session_id) DO NOTHING`)
	if err != nil {
		return nil, fmt.Errorf("db: inserting listens: %w", err)
	}
	defer stmt.Close()
	// One received-at for the batch: they arrived together, and the
	// column records arrival rather than ordering anything.
	now := time.Now().UnixNano()
	for i, s := range sessions {
		res, err := stmt.ExecContext(ctx,
			s.UserID, s.SessionID, s.ItemPID, s.MediaType, s.StartedAt.UnixNano(),
			s.MsPlayed, s.SkippedMs, boolInt(s.Finished), s.Client, s.Source, now,
		)
		if err != nil {
			return nil, fmt.Errorf("db: inserting listens: %w", err)
		}
		n, err := res.RowsAffected()
		if err != nil {
			return nil, fmt.Errorf("db: inserting listens: %w", err)
		}
		inserted[i] = n > 0
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("db: inserting listens: %w", err)
	}
	return inserted, nil
}

// UpsertRadioListen records - or extends - one radio tune-in.
//
// Insert-or-update on (user_id, session_id) rather than the plain
// insert a client-reported session gets, because the two are written
// at different moments. A client reports a listen once, when it is
// over; the stream proxy is holding the connection while it happens
// and has no way to know how long it will last, so it checkpoints as
// it goes. Every checkpoint carries the elapsed total rather than a
// delta, which is what makes a dropped one survivable: the next one
// supersedes it, and a server that restarts mid-listen leaves a row
// short rather than leaving no row at all.
//
// ItemPID carries the station's bare ULID and MediaType is `radio`. A
// station is not a catalog item, so nothing downstream may resolve it
// through the item store - the station table answers for it.
func (d *DB) UpsertRadioListen(ctx context.Context, s ListenSession) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO listen_sessions
			(user_id, session_id, item_pid, media_type, started_at_ns,
			 ms_played, skipped_ms, finished, client, source, received_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?)
		ON CONFLICT (user_id, session_id) DO UPDATE SET
			ms_played = excluded.ms_played,
			received_at_ns = excluded.received_at_ns`,
		s.UserID, s.SessionID, s.ItemPID, s.MediaType, s.StartedAt.UnixNano(),
		s.MsPlayed, s.Client, s.Source, time.Now().UnixNano(),
	)
	if err != nil {
		return fmt.Errorf("db: recording radio listen: %w", err)
	}
	return nil
}

// DeleteListens removes sessions by their idempotency keys, in one
// transaction. Ingest uses it as a compensating delete: when a
// played-mark fails transiently, the sessions it claimed but never
// marked come back out, so the client's retry re-runs both the insert
// and the mark instead of reading them as duplicates and skipping the
// mark forever.
func (d *DB) DeleteListens(ctx context.Context, userID string, sessionIDs []string) error {
	if len(sessionIDs) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: deleting listens: %w", err)
	}
	defer tx.Rollback()
	stmt, err := tx.PrepareContext(ctx,
		`DELETE FROM listen_sessions WHERE user_id = ? AND session_id = ?`)
	if err != nil {
		return fmt.Errorf("db: deleting listens: %w", err)
	}
	defer stmt.Close()
	for _, id := range sessionIDs {
		if _, err := stmt.ExecContext(ctx, userID, id); err != nil {
			return fmt.Errorf("db: deleting listens: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: deleting listens: %w", err)
	}
	return nil
}

// ListenCount reports how many sessions are recorded for one user and
// item. Used by tests and, later, stats.
func (d *DB) ListenCount(ctx context.Context, userID, itemPID string) (int, error) {
	var n int
	err := d.r.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM listen_sessions WHERE user_id = ? AND item_pid = ?`,
		userID, itemPID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("db: counting listens: %w", err)
	}
	return n, nil
}

// ListenRow is one session as the stats surface reads it: the stored
// fields plus the row id that keys the log's keyset cursor.
type ListenRow struct {
	RowID int64
	ListenSession
}

// ListensInRange streams one user's sessions with started_at inside
// [from, to) to fn, oldest first. Calendar bucketing happens in Go
// because SQLite cannot bucket in an arbitrary IANA timezone. userID
// empty streams every user's sessions (the server-wide recap).
func (d *DB) ListensInRange(ctx context.Context, userID string, from, to time.Time, fn func(ListenRow)) error {
	q := `
		SELECT id, user_id, item_pid, media_type, started_at_ns,
		       ms_played, skipped_ms, finished, client, source
		FROM listen_sessions
		WHERE started_at_ns >= ? AND started_at_ns < ?`
	args := []any{from.UnixNano(), to.UnixNano()}
	if userID != "" {
		q += ` AND user_id = ?`
		args = append(args, userID)
	}
	q += ` ORDER BY started_at_ns`
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return fmt.Errorf("db: reading listens: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var r ListenRow
		var startedNS int64
		var finished int
		if err := rows.Scan(&r.RowID, &r.UserID, &r.ItemPID, &r.MediaType,
			&startedNS, &r.MsPlayed, &r.SkippedMs, &finished, &r.Client, &r.Source); err != nil {
			return fmt.Errorf("db: reading listens: %w", err)
		}
		r.StartedAt = time.Unix(0, startedNS).UTC()
		r.Finished = finished != 0
		fn(r)
	}
	return rows.Err()
}

// ListenLog pages one user's sessions newest first, optionally filtered
// to one client label. The cursor is the previous page's last
// (started_at_ns, id) pair.
func (d *DB) ListenLog(ctx context.Context, userID, client string, beforeNS, beforeID int64, limit int) ([]ListenRow, error) {
	if beforeNS == 0 {
		beforeNS = time.Now().Add(time.Hour).UnixNano()
		beforeID = 0
	}
	q := `
		SELECT id, user_id, item_pid, media_type, started_at_ns,
		       ms_played, skipped_ms, finished, client, source
		FROM listen_sessions
		WHERE user_id = ? AND (started_at_ns < ? OR (started_at_ns = ? AND id < ?))`
	args := []any{userID, beforeNS, beforeNS, beforeID}
	if client != "" {
		q += ` AND client = ?`
		args = append(args, client)
	}
	q += ` ORDER BY started_at_ns DESC, id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: reading listen log: %w", err)
	}
	defer rows.Close()
	var out []ListenRow
	for rows.Next() {
		var r ListenRow
		var startedNS int64
		var finished int
		if err := rows.Scan(&r.RowID, &r.UserID, &r.ItemPID, &r.MediaType,
			&startedNS, &r.MsPlayed, &r.SkippedMs, &finished, &r.Client, &r.Source); err != nil {
			return nil, fmt.Errorf("db: reading listen log: %w", err)
		}
		r.StartedAt = time.Unix(0, startedNS).UTC()
		r.Finished = finished != 0
		out = append(out, r)
	}
	return out, rows.Err()
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
