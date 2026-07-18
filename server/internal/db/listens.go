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
			 ms_played, finished, client, source, received_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, session_id) DO NOTHING`,
		s.UserID, s.SessionID, s.ItemPID, s.MediaType, s.StartedAt.UnixNano(),
		s.MsPlayed, boolInt(s.Finished), s.Client, s.Source, time.Now().UnixNano(),
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

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
