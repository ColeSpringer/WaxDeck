package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// Notification is one inbox row: something that happened to one
// account.
//
// The wording is denormalized on purpose. A client that knows the event
// words the row itself and stays localized; the server's own title and
// body are what a client that does not know the event draws instead, so
// a newer server's event is shown rather than dropped.
type Notification struct {
	ID        string
	UserID    string
	Event     string
	Title     string
	Body      string
	TargetPID string
	CreatedNS int64
	// ReadNS is 0 while the row is unread.
	ReadNS int64
}

// InsertNotification writes one inbox row.
func (d *DB) InsertNotification(ctx context.Context, n Notification) error {
	var target any
	if n.TargetPID != "" {
		target = n.TargetPID
	}
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO notifications (id, user_id, event, title, body, target_pid, created_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		n.ID, n.UserID, n.Event, n.Title, n.Body, target, n.CreatedNS)
	if err != nil {
		return fmt.Errorf("db: writing notification: %w", err)
	}
	return nil
}

const notificationColumns = `id, user_id, event, title, body,
	COALESCE(target_pid, ''), created_at_ns, COALESCE(read_at_ns, 0)`

func scanNotification(rows interface{ Scan(...any) error }) (Notification, error) {
	var n Notification
	err := rows.Scan(&n.ID, &n.UserID, &n.Event, &n.Title, &n.Body,
		&n.TargetPID, &n.CreatedNS, &n.ReadNS)
	return n, err
}

// ListNotifications pages one account's inbox newest first. The cursor
// is the previous page's last id; empty starts at the head.
//
// The id is a ULID, so its descending order is the order things
// happened in and the keyset needs no second column to break ties.
func (d *DB) ListNotifications(ctx context.Context, userID, afterID string, limit int) ([]Notification, error) {
	q := `SELECT ` + notificationColumns + ` FROM notifications WHERE user_id = ?`
	args := []any{userID}
	if afterID != "" {
		q += ` AND id < ?`
		args = append(args, afterID)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing notifications: %w", err)
	}
	defer rows.Close()
	var out []Notification
	for rows.Next() {
		n, err := scanNotification(rows)
		if err != nil {
			return nil, fmt.Errorf("db: listing notifications: %w", err)
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// UnreadNotificationCount counts the account's unread rows.
func (d *DB) UnreadNotificationCount(ctx context.Context, userID string) (int, error) {
	var n int
	err := d.r.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at_ns IS NULL`,
		userID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("db: counting unread notifications: %w", err)
	}
	return n, nil
}

// MarkNotificationsRead stamps the named rows, or every unread row when
// ids is empty. Already-read rows keep the stamp they have: the first
// time somebody saw a thing is the useful one.
func (d *DB) MarkNotificationsRead(ctx context.Context, userID string, ids []string, ns int64) error {
	q := `UPDATE notifications SET read_at_ns = ? WHERE user_id = ? AND read_at_ns IS NULL`
	args := []any{ns, userID}
	if len(ids) > 0 {
		q += ` AND id IN (?` + strings.Repeat(", ?", len(ids)-1) + `)`
		for _, id := range ids {
			args = append(args, id)
		}
	}
	if _, err := d.w.ExecContext(ctx, q, args...); err != nil {
		return fmt.Errorf("db: marking notifications read: %w", err)
	}
	return nil
}

// DeleteNotification removes one row. ErrNotFound when the account has
// no such row, which is what makes another account's row a 404.
func (d *DB) DeleteNotification(ctx context.Context, userID, id string) error {
	res, err := d.w.ExecContext(ctx,
		`DELETE FROM notifications WHERE user_id = ? AND id = ?`, userID, id)
	if err != nil {
		return fmt.Errorf("db: deleting notification: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: deleting notification: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// ClearNotifications empties one account's inbox.
func (d *DB) ClearNotifications(ctx context.Context, userID string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM notifications WHERE user_id = ?`, userID); err != nil {
		return fmt.Errorf("db: clearing notifications: %w", err)
	}
	return nil
}

// PruneNotifications drops rows older than a cutoff and whatever is
// past the per-account cap.
//
// One statement and one scan. The obvious spelling - a correlated
// subquery asking "is this row inside its account's newest 500?" -
// re-walks that account's index once per row, which on a hundred
// thousand rows is tens of seconds of a single-writer connection
// blocking every scrobble and play-state write behind it. A window
// function numbers each account's rows in the one pass instead.
//
// The cap rides the id ordering, which is time ordering because ids are
// ULIDs; the age bound reads created_at_ns off the same one scan, so it
// needs no index of its own on a column nothing else reads.
func (d *DB) PruneNotifications(ctx context.Context, olderThanNS int64, perUserCap int) (int64, error) {
	if perUserCap <= 0 {
		perUserCap = -1 // No cap: the age bound alone decides.
	}
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM notifications WHERE id IN (
			SELECT id FROM (
				SELECT id, created_at_ns,
				       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id DESC) AS rn
				FROM notifications
			)
			WHERE created_at_ns < ? OR (? > 0 AND rn > ?)
		)`, olderThanNS, perUserCap, perUserCap)
	if err != nil {
		return 0, fmt.Errorf("db: pruning notifications: %w", err)
	}
	return res.RowsAffected()
}

// NotificationByID reads one row; ErrNotFound when it is not this
// account's.
func (d *DB) NotificationByID(ctx context.Context, userID, id string) (Notification, error) {
	row := d.r.QueryRowContext(ctx,
		`SELECT `+notificationColumns+` FROM notifications WHERE user_id = ? AND id = ?`,
		userID, id)
	n, err := scanNotification(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Notification{}, ErrNotFound
	}
	if err != nil {
		return Notification{}, fmt.Errorf("db: reading notification: %w", err)
	}
	return n, nil
}
