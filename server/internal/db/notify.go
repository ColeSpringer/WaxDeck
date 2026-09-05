package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// NotifyRow is one queued notification delivery, bound to its target;
// the target's kind and config are read at delivery time so edits and
// revocations between enqueue and drain win.
type NotifyRow struct {
	ID       int64
	TargetID string
	Event    string
	Title    string
	Body     string
	// TargetPID is what the event is about, where it names something.
	// Held on the row rather than resolved at drain time: the thing may
	// be gone by then, and the link is still where it was.
	TargetPID string
	// EnqueuedAtNS is when the row joined the queue, which is what the
	// drain measures the outbox horizon from when a paced target cannot
	// reach it in time.
	EnqueuedAtNS int64
	Attempts     int
}

// EnqueueNotify queues one delivery.
func (d *DB) EnqueueNotify(ctx context.Context, r NotifyRow, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO notify_outbox (target_id, event, title, body, target_pid, enqueued_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)`,
		r.TargetID, r.Event, r.Title, r.Body, nullable(r.TargetPID), ns)
	if err != nil {
		return fmt.Errorf("db: queuing notification: %w", err)
	}
	return nil
}

// LeaseNotify claims the oldest lease-free delivery; ErrNotFound when
// the queue is idle.
func (d *DB) LeaseNotify(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (NotifyRow, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE notify_outbox SET lease_until_ns = ? + ?
		WHERE id = (
			SELECT id FROM notify_outbox
			WHERE lease_until_ns < ? AND attempts < ?
			ORDER BY enqueued_at_ns, id LIMIT 1
		)
		RETURNING id, target_id, event, title, body, COALESCE(target_pid, ''),
			enqueued_at_ns, attempts`,
		nowNS, leaseNS, nowNS, maxAttempts)
	var r NotifyRow
	if err := row.Scan(&r.ID, &r.TargetID, &r.Event, &r.Title, &r.Body,
		&r.TargetPID, &r.EnqueuedAtNS, &r.Attempts); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return NotifyRow{}, ErrNotFound
		}
		return NotifyRow{}, fmt.Errorf("db: leasing notification: %w", err)
	}
	return r, nil
}

// CompleteNotify removes a delivered row.
func (d *DB) CompleteNotify(ctx context.Context, id int64) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM notify_outbox WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: completing notification: %w", err)
	}
	return nil
}

// FailNotify records a failed attempt; the row stays leased until
// retryAtNS so retries back off for real.
func (d *DB) FailNotify(ctx context.Context, id int64, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE notify_outbox SET attempts = attempts + 1, lease_until_ns = ?, last_error = ?
		WHERE id = ?`, retryAtNS, msg, id)
	if err != nil {
		return fmt.Errorf("db: failing notification: %w", err)
	}
	return nil
}

// RequeueNotify puts a leased row back without counting an attempt.
//
// The pacing path: a target inside its own minimum interval has not
// failed at anything, so spending one of its ten attempts on the wait
// would eventually drop the delivery for being patient.
func (d *DB) RequeueNotify(ctx context.Context, id, readyAtNS int64) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE notify_outbox SET lease_until_ns = ? WHERE id = ?`, readyAtNS, id)
	if err != nil {
		return fmt.Errorf("db: requeuing notification: %w", err)
	}
	return nil
}

// DropNotify removes a row whose delivery was rejected permanently;
// retrying cannot succeed, so it leaves the queue now.
func (d *DB) DropNotify(ctx context.Context, id int64) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM notify_outbox WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: dropping notification: %w", err)
	}
	return nil
}

// PruneNotifyOutbox removes stale or exhausted rows. Notifications are
// timely by nature; a day-old undelivered event is noise.
func (d *DB) PruneNotifyOutbox(ctx context.Context, olderThanNS int64, maxAttempts int) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM notify_outbox WHERE enqueued_at_ns < ? OR attempts >= ?`,
		olderThanNS, maxAttempts)
	if err != nil {
		return 0, fmt.Errorf("db: pruning notify outbox: %w", err)
	}
	return res.RowsAffected()
}

// SettingGet reads one settings value; ErrNotFound when unset.
func (d *DB) SettingGet(ctx context.Context, key string) (string, error) {
	var v string
	err := d.r.QueryRowContext(ctx, `SELECT value FROM settings WHERE key = ?`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("db: reading setting %s: %w", key, err)
	}
	return v, nil
}

// SettingDelete removes one settings row; a missing key is a no-op.
func (d *DB) SettingDelete(ctx context.Context, key string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM settings WHERE key = ?`, key); err != nil {
		return fmt.Errorf("db: deleting setting %s: %w", key, err)
	}
	return nil
}

// SettingSet stores one settings value.
func (d *DB) SettingSet(ctx context.Context, key, value string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO settings (key, value, updated_at_ns) VALUES (?, ?, ?)
		ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at_ns = excluded.updated_at_ns`,
		key, value, ns)
	if err != nil {
		return fmt.Errorf("db: writing setting %s: %w", key, err)
	}
	return nil
}

// SettingsWithPrefix reads every settings row whose key starts with the
// prefix, keyed by full key.
func (d *DB) SettingsWithPrefix(ctx context.Context, prefix string) (map[string]string, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT key, value FROM settings WHERE key >= ? AND key < ?`,
		prefix, prefix+"￿")
	if err != nil {
		return nil, fmt.Errorf("db: listing settings by prefix: %w", err)
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, fmt.Errorf("db: scanning setting: %w", err)
		}
		out[k] = v
	}
	return out, rows.Err()
}
