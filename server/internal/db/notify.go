package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// NotifyRow is one queued notification delivery: an Apprise relay post
// (kind "apprise", empty target) or a UnifiedPush post (kind "push",
// target is the endpoint URL).
type NotifyRow struct {
	ID       int64
	Kind     string
	Event    string
	Target   string
	Title    string
	Body     string
	Attempts int
}

// EnqueueNotify queues one delivery.
func (d *DB) EnqueueNotify(ctx context.Context, r NotifyRow, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO notify_outbox (kind, event, target, title, body, enqueued_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)`,
		r.Kind, r.Event, r.Target, r.Title, r.Body, ns)
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
		RETURNING id, kind, event, target, title, body, attempts`,
		nowNS, leaseNS, nowNS, maxAttempts)
	var r NotifyRow
	if err := row.Scan(&r.ID, &r.Kind, &r.Event, &r.Target, &r.Title, &r.Body, &r.Attempts); err != nil {
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

// PushRegistration is one UnifiedPush endpoint a user registered.
type PushRegistration struct {
	ID          string
	UserID      string
	Endpoint    string
	Label       string
	CreatedAtNS int64
}

// pushRegistrationCap bounds registrations per user.
const pushRegistrationCap = 20

// UpsertPushRegistration stores a registration. Re-registering an
// endpoint the user already holds updates its label and reports the
// existing row (created false). The per-user cap is guarded inside the
// insert statement; ErrConflict means the cap is reached.
func (d *DB) UpsertPushRegistration(ctx context.Context, r PushRegistration) (stored PushRegistration, created bool, err error) {
	res, err := d.w.ExecContext(ctx, `
		UPDATE push_registrations SET label = ? WHERE user_id = ? AND endpoint = ?`,
		r.Label, r.UserID, r.Endpoint)
	if err != nil {
		return PushRegistration{}, false, fmt.Errorf("db: updating push registration: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil {
		return PushRegistration{}, false, fmt.Errorf("db: updating push registration: %w", err)
	} else if n > 0 {
		got, err := d.pushRegistrationWrite(ctx, r.UserID, r.Endpoint)
		return got, false, err
	}
	res, err = d.w.ExecContext(ctx, `
		INSERT INTO push_registrations (id, user_id, endpoint, label, created_at_ns)
		SELECT ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM push_registrations WHERE user_id = ?) < ?`,
		r.ID, r.UserID, r.Endpoint, r.Label, r.CreatedAtNS, r.UserID, pushRegistrationCap)
	if err != nil {
		return PushRegistration{}, false, fmt.Errorf("db: creating push registration: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil {
		return PushRegistration{}, false, fmt.Errorf("db: creating push registration: %w", err)
	} else if n == 0 {
		return PushRegistration{}, false, ErrConflict
	}
	return r, true, nil
}

// pushRegistrationWrite reads through the write connection so a row the
// upsert just touched is visible regardless of read-pool snapshots.
func (d *DB) pushRegistrationWrite(ctx context.Context, userID, endpoint string) (PushRegistration, error) {
	var r PushRegistration
	err := d.w.QueryRowContext(ctx, `
		SELECT id, user_id, endpoint, label, created_at_ns
		FROM push_registrations WHERE user_id = ? AND endpoint = ?`, userID, endpoint).
		Scan(&r.ID, &r.UserID, &r.Endpoint, &r.Label, &r.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return PushRegistration{}, ErrNotFound
	}
	if err != nil {
		return PushRegistration{}, fmt.Errorf("db: reading push registration: %w", err)
	}
	return r, nil
}

// PushRegistrationsFor lists one user's registrations, newest first.
func (d *DB) PushRegistrationsFor(ctx context.Context, userID string) ([]PushRegistration, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, endpoint, label, created_at_ns
		FROM push_registrations WHERE user_id = ? ORDER BY created_at_ns DESC, id`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing push registrations: %w", err)
	}
	defer rows.Close()
	var out []PushRegistration
	for rows.Next() {
		var r PushRegistration
		if err := rows.Scan(&r.ID, &r.UserID, &r.Endpoint, &r.Label, &r.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning push registration: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// AllPushRegistrations lists every user's registrations, for
// server-wide deliveries such as the admin test.
func (d *DB) AllPushRegistrations(ctx context.Context) ([]PushRegistration, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, endpoint, label, created_at_ns
		FROM push_registrations ORDER BY created_at_ns DESC, id`)
	if err != nil {
		return nil, fmt.Errorf("db: listing push registrations: %w", err)
	}
	defer rows.Close()
	var out []PushRegistration
	for rows.Next() {
		var r PushRegistration
		if err := rows.Scan(&r.ID, &r.UserID, &r.Endpoint, &r.Label, &r.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning push registration: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// DeletePushRegistration removes one registration owned by the user;
// ErrNotFound when it does not exist or belongs to someone else.
func (d *DB) DeletePushRegistration(ctx context.Context, userID, id string) error {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM push_registrations WHERE user_id = ? AND id = ?`, userID, id)
	if err != nil {
		return fmt.Errorf("db: deleting push registration: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: deleting push registration: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteAllPushRegistrations removes every registration the user holds.
func (d *DB) DeleteAllPushRegistrations(ctx context.Context, userID string) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM push_registrations WHERE user_id = ?`, userID)
	if err != nil {
		return fmt.Errorf("db: deleting push registrations: %w", err)
	}
	return nil
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
