package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// ScrobbleConnection is one user's link to an outbound scrobbling
// service. The secret (a Last.fm session key or a ListenBrainz token)
// is sealed by the caller before it reaches this layer.
type ScrobbleConnection struct {
	UserID        string
	Service       string
	SealedSecret  []byte
	Username      string
	APIURL        string
	CreatedAtNS   int64
	UpdatedAtNS   int64
	LastSuccessNS int64
	LastError     string
	LastErrorNS   int64
}

// UpsertScrobbleConnection stores or replaces a user's connection to
// one service. Reconnecting resets delivery health: the new credential
// has no failures yet.
func (d *DB) UpsertScrobbleConnection(ctx context.Context, c ScrobbleConnection) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO scrobble_connections (user_id, service, sealed_secret, username, api_url, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, service) DO UPDATE SET
			sealed_secret = excluded.sealed_secret,
			username = excluded.username,
			api_url = excluded.api_url,
			updated_at_ns = excluded.updated_at_ns,
			last_success_at_ns = 0,
			last_error = '',
			last_error_at_ns = 0`,
		c.UserID, c.Service, c.SealedSecret, c.Username, c.APIURL, c.CreatedAtNS, c.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: storing scrobble connection: %w", err)
	}
	return nil
}

// MarkScrobbleDelivery records one delivery outcome on the connection:
// success clears any standing error, failure records it. A missing
// connection (disconnected mid-flight) is a no-op.
func (d *DB) MarkScrobbleDelivery(ctx context.Context, userID, service string, ok bool, errMsg string, ns int64) error {
	var err error
	if ok {
		_, err = d.w.ExecContext(ctx, `
			UPDATE scrobble_connections
			SET last_success_at_ns = ?, last_error = '', last_error_at_ns = 0
			WHERE user_id = ? AND service = ?`, ns, userID, service)
	} else {
		_, err = d.w.ExecContext(ctx, `
			UPDATE scrobble_connections
			SET last_error = ?, last_error_at_ns = ?
			WHERE user_id = ? AND service = ?`, errMsg, ns, userID, service)
	}
	if err != nil {
		return fmt.Errorf("db: marking scrobble delivery: %w", err)
	}
	return nil
}

// ScrobbleConnections lists one user's connections.
func (d *DB) ScrobbleConnections(ctx context.Context, userID string) ([]ScrobbleConnection, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT user_id, service, sealed_secret, username, api_url, created_at_ns, updated_at_ns,
			last_success_at_ns, last_error, last_error_at_ns
		FROM scrobble_connections WHERE user_id = ? ORDER BY service`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing scrobble connections: %w", err)
	}
	defer rows.Close()
	var out []ScrobbleConnection
	for rows.Next() {
		var c ScrobbleConnection
		if err := rows.Scan(&c.UserID, &c.Service, &c.SealedSecret, &c.Username, &c.APIURL, &c.CreatedAtNS, &c.UpdatedAtNS,
			&c.LastSuccessNS, &c.LastError, &c.LastErrorNS); err != nil {
			return nil, fmt.Errorf("db: scanning scrobble connection: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ScrobbleConnectionFor reads one user's connection to one service;
// ErrNotFound when the user never connected it.
func (d *DB) ScrobbleConnectionFor(ctx context.Context, userID, service string) (ScrobbleConnection, error) {
	var c ScrobbleConnection
	err := d.r.QueryRowContext(ctx, `
		SELECT user_id, service, sealed_secret, username, api_url, created_at_ns, updated_at_ns,
			last_success_at_ns, last_error, last_error_at_ns
		FROM scrobble_connections WHERE user_id = ? AND service = ?`, userID, service).
		Scan(&c.UserID, &c.Service, &c.SealedSecret, &c.Username, &c.APIURL, &c.CreatedAtNS, &c.UpdatedAtNS,
			&c.LastSuccessNS, &c.LastError, &c.LastErrorNS)
	if errors.Is(err, sql.ErrNoRows) {
		return ScrobbleConnection{}, ErrNotFound
	}
	if err != nil {
		return ScrobbleConnection{}, fmt.Errorf("db: reading scrobble connection: %w", err)
	}
	return c, nil
}

// DeleteScrobbleConnection removes a connection and every queued
// delivery it had; ErrNotFound when the connection does not exist.
// The two statements ride the single write connection back to back;
// a delivery worker leasing between them would at worst attempt one
// row whose unseal then fails, which the drain treats as terminal.
func (d *DB) DeleteScrobbleConnection(ctx context.Context, userID, service string) error {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM scrobble_connections WHERE user_id = ? AND service = ?`, userID, service)
	if err != nil {
		return fmt.Errorf("db: deleting scrobble connection: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: deleting scrobble connection: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM scrobble_outbox WHERE user_id = ? AND service = ?`, userID, service); err != nil {
		return fmt.Errorf("db: dropping queued scrobbles: %w", err)
	}
	return nil
}

// ScrobbleRow is one queued scrobble delivery.
type ScrobbleRow struct {
	ID           int64
	UserID       string
	Service      string
	ItemPID      string
	Artist       string
	Title        string
	Album        string
	DurationMS   int64
	ListenedAtNS int64
	Attempts     int
}

// EnqueueScrobble queues one delivery.
func (d *DB) EnqueueScrobble(ctx context.Context, r ScrobbleRow, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO scrobble_outbox (user_id, service, item_pid, artist, title, album, duration_ms, listened_at_ns, enqueued_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		r.UserID, r.Service, r.ItemPID, r.Artist, r.Title, r.Album, r.DurationMS, r.ListenedAtNS, ns)
	if err != nil {
		return fmt.Errorf("db: queuing scrobble: %w", err)
	}
	return nil
}

// LeaseScrobble claims the oldest lease-free delivery for leaseNS
// nanoseconds; ErrNotFound when the queue is idle. The claim writes
// the lease in the same statement that selects the row, serialized by
// the single write connection.
func (d *DB) LeaseScrobble(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (ScrobbleRow, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE scrobble_outbox SET lease_until_ns = ? + ?
		WHERE id = (
			SELECT id FROM scrobble_outbox
			WHERE lease_until_ns < ? AND attempts < ?
			ORDER BY enqueued_at_ns, id LIMIT 1
		)
		RETURNING id, user_id, service, item_pid, artist, title, album, duration_ms, listened_at_ns, attempts`,
		nowNS, leaseNS, nowNS, maxAttempts)
	var r ScrobbleRow
	if err := row.Scan(&r.ID, &r.UserID, &r.Service, &r.ItemPID, &r.Artist, &r.Title, &r.Album, &r.DurationMS, &r.ListenedAtNS, &r.Attempts); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ScrobbleRow{}, ErrNotFound
		}
		return ScrobbleRow{}, fmt.Errorf("db: leasing scrobble: %w", err)
	}
	return r, nil
}

// CompleteScrobble removes a delivered row.
func (d *DB) CompleteScrobble(ctx context.Context, id int64) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM scrobble_outbox WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: completing scrobble: %w", err)
	}
	return nil
}

// FailScrobble records a failed attempt; the row stays leased until
// retryAtNS, which is what makes the caller's backoff real.
func (d *DB) FailScrobble(ctx context.Context, id int64, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE scrobble_outbox SET attempts = attempts + 1, lease_until_ns = ?, last_error = ?
		WHERE id = ?`, retryAtNS, msg, id)
	if err != nil {
		return fmt.Errorf("db: failing scrobble: %w", err)
	}
	return nil
}

// DropScrobble removes a row whose delivery is terminally rejected
// (the service refused the scrobble itself, not the connection).
func (d *DB) DropScrobble(ctx context.Context, id int64) error {
	return d.CompleteScrobble(ctx, id)
}

// PruneScrobbleOutbox removes rows past their delivery horizon or out
// of attempts. Scrobbling services reject week-old submissions anyway,
// so undeliverable rows must not pile up forever.
func (d *DB) PruneScrobbleOutbox(ctx context.Context, olderThanNS int64, maxAttempts int) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM scrobble_outbox WHERE enqueued_at_ns < ? OR attempts >= ?`,
		olderThanNS, maxAttempts)
	if err != nil {
		return 0, fmt.Errorf("db: pruning scrobble outbox: %w", err)
	}
	return res.RowsAffected()
}
