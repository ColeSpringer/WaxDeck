package db

import (
	"context"
	"database/sql"
	"fmt"
)

// GpodderDevice is one client-declared device in the gpodder adapter's
// registry. Device ids are chosen by the client application.
type GpodderDevice struct {
	UserID      string
	DeviceID    string
	Caption     string
	Type        string
	CreatedAtNS int64
	UpdatedAtNS int64
}

// UpsertGpodderDevice creates or updates a device. Empty caption or
// type leave the stored value unchanged (the protocol updates only the
// keys the client supplies).
func (d *DB) UpsertGpodderDevice(ctx context.Context, dev GpodderDevice) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO gpodder_devices (user_id, device_id, caption, type, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, CASE WHEN ? = '' THEN 'other' ELSE ? END, ?, ?)
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			caption = CASE WHEN excluded.caption = '' THEN gpodder_devices.caption ELSE excluded.caption END,
			type = CASE WHEN ? = '' THEN gpodder_devices.type ELSE excluded.type END,
			updated_at_ns = excluded.updated_at_ns`,
		dev.UserID, dev.DeviceID, dev.Caption, dev.Type, dev.Type,
		dev.CreatedAtNS, dev.UpdatedAtNS, dev.Type)
	if err != nil {
		return fmt.Errorf("db: upserting gpodder device: %w", err)
	}
	return nil
}

// GpodderDevicesByUser lists one user's devices.
func (d *DB) GpodderDevicesByUser(ctx context.Context, userID string) ([]GpodderDevice, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT user_id, device_id, caption, type, created_at_ns, updated_at_ns
		FROM gpodder_devices WHERE user_id = ? ORDER BY device_id`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder devices: %w", err)
	}
	defer rows.Close()
	var out []GpodderDevice
	for rows.Next() {
		var dev GpodderDevice
		if err := rows.Scan(&dev.UserID, &dev.DeviceID, &dev.Caption, &dev.Type,
			&dev.CreatedAtNS, &dev.UpdatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder device: %w", err)
		}
		out = append(out, dev)
	}
	return out, rows.Err()
}

// GpodderDeviceExists reports whether the device is registered.
func (d *DB) GpodderDeviceExists(ctx context.Context, userID, deviceID string) (bool, error) {
	var n int
	err := d.r.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM gpodder_devices WHERE user_id = ? AND device_id = ?`,
		userID, deviceID).Scan(&n)
	if err != nil {
		return false, fmt.Errorf("db: checking gpodder device: %w", err)
	}
	return n > 0, nil
}

// GpodderSubEvent is one subscription change in the adapter's per-user
// change log. The protocol's cursors are epoch seconds issued by the
// server at write time.
type GpodderSubEvent struct {
	ID       int64
	UserID   string
	FeedURL  string
	Action   string
	DeviceID string
	TsSec    int64
}

// AppendGpodderSubEvent records one subscription change.
func (d *DB) AppendGpodderSubEvent(ctx context.Context, ev GpodderSubEvent) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO gpodder_sub_events (user_id, feed_url, action, device_id, ts_sec)
		VALUES (?, ?, ?, ?, ?)`,
		ev.UserID, ev.FeedURL, ev.Action, ev.DeviceID, ev.TsSec)
	if err != nil {
		return fmt.Errorf("db: appending gpodder sub event: %w", err)
	}
	return nil
}

// GpodderSubEventsSince lists one user's subscription changes strictly
// after sinceSec, oldest first.
func (d *DB) GpodderSubEventsSince(ctx context.Context, userID string, sinceSec int64) ([]GpodderSubEvent, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, feed_url, action, device_id, ts_sec
		FROM gpodder_sub_events WHERE user_id = ? AND ts_sec > ?
		ORDER BY id`, userID, sinceSec)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder sub events: %w", err)
	}
	defer rows.Close()
	var out []GpodderSubEvent
	for rows.Next() {
		var ev GpodderSubEvent
		if err := rows.Scan(&ev.ID, &ev.UserID, &ev.FeedURL, &ev.Action, &ev.DeviceID, &ev.TsSec); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder sub event: %w", err)
		}
		out = append(out, ev)
	}
	return out, rows.Err()
}

// GpodderAction is one episode action in the adapter's per-user log.
// The nullable second fields are play-action extras.
type GpodderAction struct {
	ID          int64
	UserID      string
	PodcastURL  string
	EpisodeURL  string
	DeviceID    string
	Action      string
	ActionTS    string
	StartedSec  *int64
	PositionSec *int64
	TotalSec    *int64
	UploadedSec int64
}

// AppendGpodderAction records one uploaded episode action.
func (d *DB) AppendGpodderAction(ctx context.Context, a GpodderAction) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO gpodder_actions (user_id, podcast_url, episode_url, device_id,
			action, action_ts, started_sec, position_sec, total_sec, uploaded_sec)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		a.UserID, a.PodcastURL, a.EpisodeURL, a.DeviceID, a.Action, a.ActionTS,
		a.StartedSec, a.PositionSec, a.TotalSec, a.UploadedSec)
	if err != nil {
		return fmt.Errorf("db: appending gpodder action: %w", err)
	}
	return nil
}

// GpodderActionsSince lists one user's episode actions strictly after
// sinceSec, oldest first, optionally filtered by podcast feed URL and
// device id.
func (d *DB) GpodderActionsSince(ctx context.Context, userID string, sinceSec int64, podcastURL, deviceID string) ([]GpodderAction, error) {
	q := `SELECT id, user_id, podcast_url, episode_url, device_id, action,
			action_ts, started_sec, position_sec, total_sec, uploaded_sec
		FROM gpodder_actions WHERE user_id = ? AND uploaded_sec > ?`
	args := []any{userID, sinceSec}
	if podcastURL != "" {
		q += ` AND podcast_url = ?`
		args = append(args, podcastURL)
	}
	if deviceID != "" {
		q += ` AND device_id = ?`
		args = append(args, deviceID)
	}
	q += ` ORDER BY id`
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder actions: %w", err)
	}
	defer rows.Close()
	var out []GpodderAction
	for rows.Next() {
		var a GpodderAction
		var started, position, total sql.NullInt64
		if err := rows.Scan(&a.ID, &a.UserID, &a.PodcastURL, &a.EpisodeURL, &a.DeviceID,
			&a.Action, &a.ActionTS, &started, &position, &total, &a.UploadedSec); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder action: %w", err)
		}
		if started.Valid {
			a.StartedSec = &started.Int64
		}
		if position.Valid {
			a.PositionSec = &position.Int64
		}
		if total.Valid {
			a.TotalSec = &total.Int64
		}
		out = append(out, a)
	}
	return out, rows.Err()
}
