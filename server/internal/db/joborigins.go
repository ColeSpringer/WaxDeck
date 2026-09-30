package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// JobOrigin is who started a catalog job; Rule is set for a health fix.
type JobOrigin struct {
	PID         string
	UserID      string
	Rule        string
	CreatedAtNS int64
}

// InsertJobOrigin records who started a job.
func (d *DB) InsertJobOrigin(ctx context.Context, o JobOrigin) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO job_origins (pid, user_id, rule, created_at_ns) VALUES (?, ?, ?, ?)
		ON CONFLICT (pid) DO NOTHING`,
		o.PID, o.UserID, o.Rule, o.CreatedAtNS)
	if err != nil {
		return fmt.Errorf("db: recording job origin: %w", err)
	}
	return nil
}

// ClaimJobOrigin takes a job's end in hand at nowNS and returns its
// origin, so of two callers settling the same job only one gets it. A
// claim made before heldBeforeNS, the process's start, was cut short by
// a stop and is taken over. ErrNotFound when there is none to take.
func (d *DB) ClaimJobOrigin(ctx context.Context, pid string, nowNS, heldBeforeNS int64) (JobOrigin, error) {
	var o JobOrigin
	err := d.w.QueryRowContext(ctx, `
		UPDATE job_origins SET settling_at_ns = ? WHERE pid = ? AND settling_at_ns < ?
		RETURNING pid, user_id, rule, created_at_ns`, nowNS, pid, heldBeforeNS).Scan(
		&o.PID, &o.UserID, &o.Rule, &o.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return JobOrigin{}, ErrNotFound
	}
	if err != nil {
		return JobOrigin{}, fmt.Errorf("db: claiming job origin: %w", err)
	}
	return o, nil
}

// DeleteJobOrigin drops a job's origin and answers the rule it carried;
// ErrNotFound when there was none.
func (d *DB) DeleteJobOrigin(ctx context.Context, pid string) (string, error) {
	var rule string
	err := d.w.QueryRowContext(ctx, `
		DELETE FROM job_origins WHERE pid = ? RETURNING rule`, pid).Scan(&rule)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("db: deleting job origin: %w", err)
	}
	return rule, nil
}

// HasJobOrigin reports whether anyone waits to hear a job ended.
func (d *DB) HasJobOrigin(ctx context.Context, pid string) (bool, error) {
	var n int
	if err := d.r.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM job_origins WHERE pid = ?`, pid).Scan(&n); err != nil {
		return false, fmt.Errorf("db: reading job origin: %w", err)
	}
	return n > 0, nil
}

// JobOriginRules lists the rules whose fix job runs or is being settled.
func (d *DB) JobOriginRules(ctx context.Context) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT DISTINCT rule FROM job_origins WHERE rule <> '' ORDER BY rule`)
	if err != nil {
		return nil, fmt.Errorf("db: listing fixing rules: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var rule string
		if err := rows.Scan(&rule); err != nil {
			return nil, fmt.Errorf("db: scanning fixing rule: %w", err)
		}
		out = append(out, rule)
	}
	return out, rows.Err()
}

// JobOrigins lists every origin whose job's end is still to be told.
func (d *DB) JobOrigins(ctx context.Context) ([]JobOrigin, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT pid, user_id, rule, created_at_ns FROM job_origins ORDER BY created_at_ns, pid`)
	if err != nil {
		return nil, fmt.Errorf("db: listing job origins: %w", err)
	}
	defer rows.Close()
	var out []JobOrigin
	for rows.Next() {
		var o JobOrigin
		if err := rows.Scan(&o.PID, &o.UserID, &o.Rule, &o.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning job origin: %w", err)
		}
		out = append(out, o)
	}
	return out, rows.Err()
}
