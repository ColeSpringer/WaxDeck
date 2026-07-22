package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// ErrExists marks an insert that hit a uniqueness rule (as opposed to
// ErrConflict, which marks a capacity or state conflict). Callers turn
// it into an "already exists" answer.
var ErrExists = errors.New("db: already exists")

// NotificationTarget is one delivery destination. UserID is empty for
// server-scope rows; DedupeKey is the endpoint URL on unifiedpush rows
// and empty everywhere else; EnabledEvents is a JSON array of event
// names, read and written whole.
type NotificationTarget struct {
	ID            string
	Kind          string
	Scope         string
	UserID        string
	Label         string
	SealedConfig  []byte
	EnabledEvents string
	DedupeKey     string
	LastSuccessNS int64
	LastError     string
	LastErrorNS   int64
	CreatedAtNS   int64
}

// notificationTargetCap bounds targets per (owner, kind).
const notificationTargetCap = 20

const notificationTargetCols = `id, kind, scope, user_id, label, sealed_config,
	enabled_events, dedupe_key, last_success_at_ns, last_error, last_error_at_ns, created_at_ns`

func scanNotificationTarget(row interface{ Scan(...any) error }) (NotificationTarget, error) {
	var t NotificationTarget
	var userID, dedupe sql.NullString
	err := row.Scan(&t.ID, &t.Kind, &t.Scope, &userID, &t.Label, &t.SealedConfig,
		&t.EnabledEvents, &dedupe, &t.LastSuccessNS, &t.LastError, &t.LastErrorNS, &t.CreatedAtNS)
	if err != nil {
		return NotificationTarget{}, err
	}
	t.UserID = userID.String
	t.DedupeKey = dedupe.String
	return t, nil
}

// nullable maps the empty string to NULL, matching how UserID and
// DedupeKey are stored.
func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// InsertNotificationTarget stores a target. The per-(owner, kind) cap
// is guarded inside the insert; ErrConflict means the cap is reached,
// ErrExists that a uniqueness rule (the unifiedpush endpoint dedupe)
// was hit.
func (d *DB) InsertNotificationTarget(ctx context.Context, t NotificationTarget) error {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO notification_targets
			(id, kind, scope, user_id, label, sealed_config, enabled_events, dedupe_key, created_at_ns)
		SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM notification_targets WHERE user_id IS ? AND kind = ?) < ?`,
		t.ID, t.Kind, t.Scope, nullable(t.UserID), t.Label, t.SealedConfig,
		t.EnabledEvents, nullable(t.DedupeKey), t.CreatedAtNS,
		nullable(t.UserID), t.Kind, notificationTargetCap)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint failed") {
			return ErrExists
		}
		return fmt.Errorf("db: creating notification target: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil {
		return fmt.Errorf("db: creating notification target: %w", err)
	} else if n == 0 {
		return ErrConflict
	}
	return nil
}

// NotificationTargetByID reads one target through the write connection
// so a row a mutation just touched is visible regardless of read-pool
// snapshots.
func (d *DB) NotificationTargetByID(ctx context.Context, id string) (NotificationTarget, error) {
	t, err := scanNotificationTarget(d.w.QueryRowContext(ctx,
		`SELECT `+notificationTargetCols+` FROM notification_targets WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return NotificationTarget{}, ErrNotFound
	}
	if err != nil {
		return NotificationTarget{}, fmt.Errorf("db: reading notification target: %w", err)
	}
	return t, nil
}

// ServerNotificationTargets lists the server-scope targets, newest
// first.
func (d *DB) ServerNotificationTargets(ctx context.Context) ([]NotificationTarget, error) {
	return d.listNotificationTargets(ctx, `
		SELECT `+notificationTargetCols+` FROM notification_targets
		WHERE user_id IS NULL ORDER BY created_at_ns DESC, id`)
}

// UserNotificationTargets lists one user's targets, newest first.
func (d *DB) UserNotificationTargets(ctx context.Context, userID string) ([]NotificationTarget, error) {
	return d.listNotificationTargets(ctx, `
		SELECT `+notificationTargetCols+` FROM notification_targets
		WHERE user_id = ? ORDER BY created_at_ns DESC, id`, userID)
}

func (d *DB) listNotificationTargets(ctx context.Context, query string, args ...any) ([]NotificationTarget, error) {
	rows, err := d.r.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing notification targets: %w", err)
	}
	defer rows.Close()
	var out []NotificationTarget
	for rows.Next() {
		t, err := scanNotificationTarget(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning notification target: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// UpdateNotificationTarget replaces a target's label, config, enabled
// events, and dedupe key. ErrExists when the new dedupe key collides
// with another row's.
func (d *DB) UpdateNotificationTarget(ctx context.Context, t NotificationTarget) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE notification_targets
		SET label = ?, sealed_config = ?, enabled_events = ?, dedupe_key = ?
		WHERE id = ?`,
		t.Label, t.SealedConfig, t.EnabledEvents, nullable(t.DedupeKey), t.ID)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint failed") {
			return ErrExists
		}
		return fmt.Errorf("db: updating notification target: %w", err)
	}
	if n, err := res.RowsAffected(); err != nil {
		return fmt.Errorf("db: updating notification target: %w", err)
	} else if n == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteUserNotificationTarget removes one target owned by the user;
// ErrNotFound when it does not exist or belongs to someone else.
// Queued deliveries cascade away with the row.
func (d *DB) DeleteUserNotificationTarget(ctx context.Context, userID, id string) error {
	return d.deleteNotificationTarget(ctx, `
		DELETE FROM notification_targets WHERE id = ? AND user_id = ?`, id, userID)
}

// DeleteServerNotificationTarget removes one server-scope target.
func (d *DB) DeleteServerNotificationTarget(ctx context.Context, id string) error {
	return d.deleteNotificationTarget(ctx, `
		DELETE FROM notification_targets WHERE id = ? AND user_id IS NULL`, id)
}

func (d *DB) deleteNotificationTarget(ctx context.Context, query string, args ...any) error {
	res, err := d.w.ExecContext(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("db: deleting notification target: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: deleting notification target: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// UpsertUnifiedPushTarget serves the legacy push-registration create.
// Re-registering a known endpoint refreshes label and config only and
// reports the existing row (created false), preserving the event
// selection made in the targets surface; a genuinely new endpoint
// inserts under the per-kind cap (ErrConflict when reached).
func (d *DB) UpsertUnifiedPushTarget(ctx context.Context, t NotificationTarget) (stored NotificationTarget, created bool, err error) {
	// Update-then-insert is two statements, so a concurrent
	// registration of the same endpoint can land its insert between
	// them, putting this call's insert leg onto the dedupe index.
	// That ErrExists means the row exists now, and registration is
	// idempotent by contract, so one retry of the update leg resolves
	// it instead of surfacing a conflict for an operation that
	// succeeded.
	for attempt := 0; ; attempt++ {
		res, err := d.w.ExecContext(ctx, `
			UPDATE notification_targets SET label = ?, sealed_config = ?
			WHERE user_id = ? AND kind = ? AND dedupe_key = ?`,
			t.Label, t.SealedConfig, t.UserID, t.Kind, t.DedupeKey)
		if err != nil {
			return NotificationTarget{}, false, fmt.Errorf("db: updating push registration: %w", err)
		}
		if n, err := res.RowsAffected(); err != nil {
			return NotificationTarget{}, false, fmt.Errorf("db: updating push registration: %w", err)
		} else if n > 0 {
			got, err := scanNotificationTarget(d.w.QueryRowContext(ctx,
				`SELECT `+notificationTargetCols+` FROM notification_targets
				WHERE user_id = ? AND kind = ? AND dedupe_key = ?`, t.UserID, t.Kind, t.DedupeKey))
			if err != nil {
				return NotificationTarget{}, false, fmt.Errorf("db: reading push registration: %w", err)
			}
			return got, false, nil
		}
		err = d.InsertNotificationTarget(ctx, t)
		if errors.Is(err, ErrExists) && attempt == 0 {
			continue
		}
		if err != nil {
			return NotificationTarget{}, false, err
		}
		return t, true, nil
	}
}

// DeleteUserNotificationTargetsByKind removes every target of one kind
// the user holds (the legacy delete-all-push-registrations surface).
func (d *DB) DeleteUserNotificationTargetsByKind(ctx context.Context, userID, kind string) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM notification_targets WHERE user_id = ? AND kind = ?`, userID, kind)
	if err != nil {
		return fmt.Errorf("db: deleting notification targets: %w", err)
	}
	return nil
}

// MarkNotifyTargetDelivery records a delivery outcome on the target so
// the settings surface can show why notifications are not arriving. A
// deleted-since-queuing target matches no row and records nothing.
func (d *DB) MarkNotifyTargetDelivery(ctx context.Context, id string, ok bool, msg string, ns int64) error {
	var err error
	if ok {
		_, err = d.w.ExecContext(ctx, `
			UPDATE notification_targets
			SET last_success_at_ns = ?, last_error = '', last_error_at_ns = 0
			WHERE id = ?`, ns, id)
	} else {
		_, err = d.w.ExecContext(ctx, `
			UPDATE notification_targets SET last_error = ?, last_error_at_ns = ?
			WHERE id = ?`, msg, ns, id)
	}
	if err != nil {
		return fmt.Errorf("db: marking notification delivery: %w", err)
	}
	return nil
}
