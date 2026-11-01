package db

import (
	"context"
	"database/sql"
	"errors"
)

// JobsClearedAt is the end time, in unix nanoseconds, at or before which
// the account no longer lists finished catalog jobs; 0 when it never
// cleared any.
func (d *DB) JobsClearedAt(ctx context.Context, userID string) (int64, error) {
	var ns int64
	err := d.r.QueryRowContext(ctx, `SELECT cleared_at_ns FROM job_clears WHERE user_id = ?`, userID).Scan(&ns)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return ns, err
}

// SetJobsClearedAt records the account's watermark; it never moves back, so
// clears that race land on the newest.
func (d *DB) SetJobsClearedAt(ctx context.Context, userID string, ns int64) error {
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO job_clears (user_id, cleared_at_ns) VALUES (?,?)
		 ON CONFLICT (user_id) DO UPDATE SET cleared_at_ns = MAX(job_clears.cleared_at_ns, excluded.cleared_at_ns)`,
		userID, ns)
	return err
}
