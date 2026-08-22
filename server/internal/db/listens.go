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

// InsertListen records one session. inserted is false when the same
// (user, sessionId) was already recorded: the replay is acknowledged
// and ignored, which is what makes ingest idempotent.
func (d *DB) InsertListen(ctx context.Context, s ListenSession) (inserted bool, err error) {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO listen_sessions
			(user_id, session_id, item_pid, media_type, started_at_ns,
			 ms_played, skipped_ms, finished, client, source, received_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, session_id) DO NOTHING`,
		s.UserID, s.SessionID, s.ItemPID, s.MediaType, s.StartedAt.UnixNano(),
		s.MsPlayed, s.SkippedMs, boolInt(s.Finished), s.Client, s.Source, time.Now().UnixNano(),
	)
	if err != nil {
		return false, fmt.Errorf("db: inserting listen: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: inserting listen: %w", err)
	}
	return n > 0, nil
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

// DeleteListen removes one session by its idempotency key. Ingest uses
// it as a compensating delete: when the played-mark that belongs with a
// freshly inserted session fails transiently, the row is removed so the
// client's retry re-runs both the insert and the mark.
func (d *DB) DeleteListen(ctx context.Context, userID, sessionID string) error {
	_, err := d.w.ExecContext(ctx,
		`DELETE FROM listen_sessions WHERE user_id = ? AND session_id = ?`,
		userID, sessionID)
	if err != nil {
		return fmt.Errorf("db: deleting listen: %w", err)
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
