package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Event is one row of the server change stream: a user-scoped state
// change on the serverSeq cursor. ItemPID is the bare catalog ULID and
// empty for kinds that are not about an item.
type Event struct {
	ID      int64
	UserID  string
	Kind    string
	ItemPID string
}

// AppendEvent records one server change and returns its stream id.
func (d *DB) AppendEvent(ctx context.Context, userID, kind, itemPID string) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO event_log (user_id, kind, item_pid, created_at_ns)
		VALUES (?, ?, ?, ?)`,
		userID, kind, itemPID, time.Now().UnixNano())
	if err != nil {
		return 0, fmt.Errorf("db: appending event: %w", err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("db: appending event: %w", err)
	}
	return id, nil
}

// EventsSince returns up to limit of one user's events after sinceID,
// ascending, and whether more remain past the returned page.
func (d *DB) EventsSince(ctx context.Context, userID string, sinceID int64, limit int) ([]Event, bool, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, kind, item_pid FROM event_log
		WHERE user_id = ? AND id > ? ORDER BY id LIMIT ?`,
		userID, sinceID, limit+1)
	if err != nil {
		return nil, false, fmt.Errorf("db: reading events: %w", err)
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.UserID, &e.Kind, &e.ItemPID); err != nil {
			return nil, false, fmt.Errorf("db: reading events: %w", err)
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("db: reading events: %w", err)
	}
	more := len(out) > limit
	if more {
		out = out[:limit]
	}
	return out, more, nil
}

// LatestEventID returns the stream's current tail (0 when empty).
func (d *DB) LatestEventID(ctx context.Context) (int64, error) {
	var id int64
	err := d.r.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(id), 0) FROM event_log`).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("db: reading event tail: %w", err)
	}
	return id, nil
}

// LatestEventIDForUser returns the newest event id belonging to one
// user (0 when they have none).
func (d *DB) LatestEventIDForUser(ctx context.Context, userID string) (int64, error) {
	var id int64
	err := d.r.QueryRowContext(ctx,
		`SELECT COALESCE(MAX(id), 0) FROM event_log WHERE user_id = ?`,
		userID).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("db: reading user event tail: %w", err)
	}
	return id, nil
}

// PruneEventLog keeps the newest keep rows and deletes the rest,
// returning how many went. Consumers whose cursor falls below the
// surviving floor get sync-reset from the sync endpoints.
func (d *DB) PruneEventLog(ctx context.Context, keep int) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM event_log WHERE id < (
			SELECT COALESCE(MIN(id), 0) FROM (
				SELECT id FROM event_log ORDER BY id DESC LIMIT ?))`,
		keep)
	if err != nil {
		return 0, fmt.Errorf("db: pruning event log: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("db: pruning event log: %w", err)
	}
	return n, nil
}

// EventFloor returns the lowest cursor the stream can still serve
// contiguously: the id just below the first surviving row (0 when the
// log is empty or intact from the start).
func (d *DB) EventFloor(ctx context.Context) (int64, error) {
	var min int64
	err := d.r.QueryRowContext(ctx,
		`SELECT COALESCE(MIN(id), 1) FROM event_log`).Scan(&min)
	if err != nil {
		return 0, fmt.Errorf("db: reading event floor: %w", err)
	}
	return min - 1, nil
}

// SyncStateGet reads one sync_state value ("" when absent).
func (d *DB) SyncStateGet(ctx context.Context, key string) (string, error) {
	var v string
	err := d.r.QueryRowContext(ctx,
		`SELECT value FROM sync_state WHERE key = ?`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("db: reading sync state %s: %w", key, err)
	}
	return v, nil
}

// SyncStateSet upserts one sync_state value.
func (d *DB) SyncStateSet(ctx context.Context, key, value string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO sync_state (key, value) VALUES (?, ?)
		ON CONFLICT (key) DO UPDATE SET value = excluded.value`,
		key, value)
	if err != nil {
		return fmt.Errorf("db: writing sync state %s: %w", key, err)
	}
	return nil
}
