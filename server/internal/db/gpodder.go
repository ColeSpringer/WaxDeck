package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"sync"
)

// writesInFlight holds, by account, the second each write a gpodder read
// answers a cursor over was stamped with, from before the write waits for
// the writer until it commits: a read answers a cursor before the oldest
// of them, so a write that waited past the cursor's lag is still ahead of
// the client.
type writesInFlight struct {
	mu   sync.Mutex
	held map[string]map[int64]int
}

// hold registers a write of the account stamped in second sec, answering
// its release.
func (w *writesInFlight) hold(userID string, sec int64) func() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.held == nil {
		w.held = map[string]map[int64]int{}
	}
	if w.held[userID] == nil {
		w.held[userID] = map[int64]int{}
	}
	w.held[userID][sec]++
	return func() {
		w.mu.Lock()
		defer w.mu.Unlock()
		secs := w.held[userID]
		if secs[sec]--; secs[sec] <= 0 {
			delete(secs, sec)
		}
		if len(secs) == 0 {
			delete(w.held, userID)
		}
	}
}

// GpodderWriteInFlight answers the earliest second a write of the account
// that a gpodder read answers a cursor over (an uploaded action, a
// subscription change, a play stamp) was stamped with, of those not yet
// committed.
func (d *DB) GpodderWriteInFlight(userID string) (sec int64, ok bool) {
	d.gpodderWrites.mu.Lock()
	defer d.gpodderWrites.mu.Unlock()
	for s := range d.gpodderWrites.held[userID] {
		if !ok || s < sec {
			sec, ok = s, true
		}
	}
	return sec, ok
}

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

// GpodderEviction is the device a new one took the slot of.
type GpodderEviction struct {
	DeviceID string
	Caption  string
	// Kept counts what it held or asked for: shows it held that no other
	// device does, and feeds it alone was waiting on, now the first-party
	// holder's.
	Kept int
	// Held reports it held or asked for anything at all.
	Held bool
}

// RegisterGpodderDevice creates or updates a device. Empty caption or type
// leave the stored value unchanged (the protocol updates only the keys the
// client supplies), and every call stamps the device as seen.
//
// A new device past perUserCap takes the slot of the least recently seen
// device that holds and asks for nothing; when every one does, of the
// least recently seen of all, whose holds and asks pass to the
// first-party holder "" where no other device has them, so nothing the
// account follows changes. The count, the eviction and the insert are one
// transaction.
func (d *DB) RegisterGpodderDevice(ctx context.Context, dev GpodderDevice, perUserCap int) (*GpodderEviction, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: registering gpodder device: %w", err)
	}
	defer tx.Rollback()
	var known, devices int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*) FILTER (WHERE device_id = ?), COUNT(*) FROM gpodder_devices WHERE user_id = ?`,
		dev.DeviceID, dev.UserID).Scan(&known, &devices); err != nil {
		return nil, fmt.Errorf("db: counting gpodder devices: %w", err)
	}
	var evicted *GpodderEviction
	if known == 0 && devices >= perUserCap {
		if evicted, err = evictGpodderDevice(ctx, tx, dev.UserID); err != nil {
			return nil, err
		}
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpodder_devices (user_id, device_id, caption, type, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, CASE WHEN ? = '' THEN 'other' ELSE ? END, ?, ?)
		ON CONFLICT (user_id, device_id) DO UPDATE SET
			caption = CASE WHEN excluded.caption = '' THEN gpodder_devices.caption ELSE excluded.caption END,
			type = CASE WHEN ? = '' THEN gpodder_devices.type ELSE excluded.type END,
			updated_at_ns = excluded.updated_at_ns`,
		dev.UserID, dev.DeviceID, dev.Caption, dev.Type, dev.Type,
		dev.CreatedAtNS, dev.UpdatedAtNS, dev.Type); err != nil {
		return nil, fmt.Errorf("db: registering gpodder device: %w", err)
	}
	return evicted, tx.Commit()
}

// evictGpodderDevice frees one of the account's device slots by the rule
// RegisterGpodderDevice states.
func evictGpodderDevice(ctx context.Context, tx *sql.Tx, userID string) (*GpodderEviction, error) {
	var ev GpodderEviction
	err := tx.QueryRowContext(ctx, `
		SELECT device_id, caption FROM gpodder_devices d WHERE d.user_id = ?
			AND NOT EXISTS (SELECT 1 FROM gpodder_holds h WHERE h.user_id = d.user_id AND h.holder = d.device_id)
			AND NOT EXISTS (SELECT 1 FROM gpodder_pending p WHERE p.user_id = d.user_id AND p.device_id = d.device_id)
		ORDER BY d.updated_at_ns, d.device_id LIMIT 1`, userID).Scan(&ev.DeviceID, &ev.Caption)
	if errors.Is(err, sql.ErrNoRows) {
		ev.Held = true
		err = tx.QueryRowContext(ctx, `
			SELECT device_id, caption FROM gpodder_devices WHERE user_id = ?
			ORDER BY updated_at_ns, device_id LIMIT 1`, userID).Scan(&ev.DeviceID, &ev.Caption)
	}
	if err != nil {
		return nil, fmt.Errorf("db: choosing a gpodder device to remove: %w", err)
	}
	if ev.Held {
		for _, q := range []string{`
			INSERT INTO gpodder_holds (user_id, show_pid, holder)
			SELECT h.user_id, h.show_pid, '' FROM gpodder_holds h WHERE h.user_id = ? AND h.holder = ?
				AND NOT EXISTS (SELECT 1 FROM gpodder_holds o
					WHERE o.user_id = h.user_id AND o.show_pid = h.show_pid AND o.holder <> h.holder)
			ON CONFLICT (user_id, show_pid, holder) DO NOTHING`, `
			INSERT INTO gpodder_pending (` + gpodderPendingCols + `)
			SELECT p.user_id, p.feed_url, '', p.created_at_ns, p.attempts, p.next_try_ns, p.last_error
			FROM gpodder_pending p WHERE p.user_id = ? AND p.device_id = ?
				AND NOT EXISTS (SELECT 1 FROM gpodder_pending o
					WHERE o.user_id = p.user_id AND o.feed_url = p.feed_url AND o.device_id <> p.device_id)
			ON CONFLICT (user_id, feed_url, device_id) DO NOTHING`} {
			res, err := tx.ExecContext(ctx, q, userID, ev.DeviceID)
			if err != nil {
				return nil, fmt.Errorf("db: keeping what a removed gpodder device held: %w", err)
			}
			n, err := res.RowsAffected()
			if err != nil {
				return nil, fmt.Errorf("db: keeping what a removed gpodder device held: %w", err)
			}
			ev.Kept += int(n)
		}
	}
	for _, q := range []string{
		`DELETE FROM gpodder_holds WHERE user_id = ? AND holder = ?`,
		`DELETE FROM gpodder_pending WHERE user_id = ? AND device_id = ?`,
		`DELETE FROM gpodder_devices WHERE user_id = ? AND device_id = ?`,
	} {
		if _, err := tx.ExecContext(ctx, q, userID, ev.DeviceID); err != nil {
			return nil, fmt.Errorf("db: removing a gpodder device: %w", err)
		}
	}
	return &ev, nil
}

// SeeGpodderDevice stamps a registered device as seen at seenNS.
func (d *DB) SeeGpodderDevice(ctx context.Context, userID, deviceID string, seenNS int64) error {
	if _, err := d.w.ExecContext(ctx, `
		UPDATE gpodder_devices SET updated_at_ns = ? WHERE user_id = ? AND device_id = ?`,
		seenNS, userID, deviceID); err != nil {
		return fmt.Errorf("db: stamping gpodder device: %w", err)
	}
	return nil
}

// SetGpodderDeviceCursor records the timestamp the server answered a
// device's subscription read with, whatever the device held before. A device
// nobody registered has no row to hold it.
func (d *DB) SetGpodderDeviceCursor(ctx context.Context, userID, deviceID string, cursorSec int64) error {
	if _, err := d.w.ExecContext(ctx, `
		UPDATE gpodder_devices SET sub_cursor_sec = ? WHERE user_id = ? AND device_id = ?`,
		cursorSec, userID, deviceID); err != nil {
		return fmt.Errorf("db: storing gpodder device cursor: %w", err)
	}
	return nil
}

// GpodderDeviceCursor answers the timestamp the server last answered the
// device's subscription read with: 0 for a device that has not read, and for
// one nobody registered.
func (d *DB) GpodderDeviceCursor(ctx context.Context, userID, deviceID string) (int64, error) {
	var sec int64
	err := d.r.QueryRowContext(ctx, `
		SELECT sub_cursor_sec FROM gpodder_devices WHERE user_id = ? AND device_id = ?`,
		userID, deviceID).Scan(&sec)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("db: reading gpodder device cursor: %w", err)
	}
	return sec, nil
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

// GpodderSubEvent is one show's latest subscription change in the
// adapter's per-user change log. FeedURL is the account's URL for the
// show when the change was made. The protocol's cursors are epoch seconds
// issued by the server at write time.
type GpodderSubEvent struct {
	ID       int64
	UserID   string
	ShowPID  string
	FeedURL  string
	Action   string
	DeviceID string
	TsSec    int64
}

// The removal cap's statements, each a seek of the account's removals by
// their number.
const (
	gpodderRemovalSpan = `SELECT
		(SELECT removal FROM gpodder_sub_events WHERE user_id = ? AND action = 'remove' ORDER BY removal DESC LIMIT 1),
		(SELECT removal FROM gpodder_sub_events WHERE user_id = ? AND action = 'remove' ORDER BY removal LIMIT 1)`
	gpodderDropRemovals = `DELETE FROM gpodder_sub_events WHERE user_id = ? AND action = 'remove' AND removal <= ?`
)

// AppendGpodderSubEvent records one subscription change. A delta says a
// show's latest change after the client's cursor and nothing before it,
// so the show's earlier change goes in the same transaction. A removal
// takes the number after the account's newest; once the numbers kept span
// a tenth more than perUserRemoves, the removals older than the newest
// perUserRemoves numbers go in one range. The change is in flight from
// before it waits for the writer until it commits.
func (d *DB) AppendGpodderSubEvent(ctx context.Context, ev GpodderSubEvent, perUserRemoves int) error {
	defer d.gpodderWrites.hold(ev.UserID, ev.TsSec)()
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: appending gpodder sub event: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM gpodder_sub_events WHERE user_id = ? AND show_pid = ?`, ev.UserID, ev.ShowPID); err != nil {
		return fmt.Errorf("db: replacing gpodder sub event: %w", err)
	}
	var removal, oldest int64
	if ev.Action == "remove" {
		var newest, first sql.NullInt64
		if err := tx.QueryRowContext(ctx, gpodderRemovalSpan, ev.UserID, ev.UserID).Scan(&newest, &first); err != nil {
			return fmt.Errorf("db: numbering a gpodder removal: %w", err)
		}
		removal = newest.Int64 + 1
		oldest = removal
		if first.Valid {
			oldest = first.Int64
		}
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpodder_sub_events (user_id, show_pid, feed_url, action, device_id, ts_sec, removal)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		ev.UserID, ev.ShowPID, ev.FeedURL, ev.Action, ev.DeviceID, ev.TsSec, removal); err != nil {
		return fmt.Errorf("db: appending gpodder sub event: %w", err)
	}
	if ev.Action == "remove" && removal-oldest+1 > int64(perUserRemoves+perUserRemoves/10) {
		if _, err := tx.ExecContext(ctx, gpodderDropRemovals, ev.UserID, removal-int64(perUserRemoves)); err != nil {
			return fmt.Errorf("db: capping gpodder sub events: %w", err)
		}
	}
	return tx.Commit()
}

const gpodderSubEventCols = `id, user_id, show_pid, feed_url, action, device_id, ts_sec`

func scanGpodderSubEvent(row interface{ Scan(...any) error }) (GpodderSubEvent, error) {
	var ev GpodderSubEvent
	err := row.Scan(&ev.ID, &ev.UserID, &ev.ShowPID, &ev.FeedURL, &ev.Action, &ev.DeviceID, &ev.TsSec)
	return ev, err
}

// GpodderSubEventsSince lists one user's subscription changes strictly
// after sinceSec, oldest first.
func (d *DB) GpodderSubEventsSince(ctx context.Context, userID string, sinceSec int64) ([]GpodderSubEvent, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+gpodderSubEventCols+`
		FROM gpodder_sub_events WHERE user_id = ? AND ts_sec > ?
		ORDER BY id`, userID, sinceSec)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder sub events: %w", err)
	}
	defer rows.Close()
	var out []GpodderSubEvent
	for rows.Next() {
		ev, err := scanGpodderSubEvent(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning gpodder sub event: %w", err)
		}
		out = append(out, ev)
	}
	return out, rows.Err()
}

// GpodderShowChange reads the latest subscription change the account
// made to one show; ok is false when the log has none.
func (d *DB) GpodderShowChange(ctx context.Context, userID, showPID string) (ev GpodderSubEvent, ok bool, err error) {
	ev, err = scanGpodderSubEvent(d.r.QueryRowContext(ctx, `
		SELECT `+gpodderSubEventCols+` FROM gpodder_sub_events WHERE user_id = ? AND show_pid = ?`, userID, showPID))
	if errors.Is(err, sql.ErrNoRows) {
		return GpodderSubEvent{}, false, nil
	}
	if err != nil {
		return GpodderSubEvent{}, false, fmt.Errorf("db: reading a show's gpodder change: %w", err)
	}
	return ev, true, nil
}

// ShowURL is the feed URL one show is called by.
type ShowURL struct {
	ShowPID string
	FeedURL string
}

func scanShowURLs(rows *sql.Rows) ([]ShowURL, error) {
	defer rows.Close()
	var out []ShowURL
	for rows.Next() {
		var u ShowURL
		if err := rows.Scan(&u.ShowPID, &u.FeedURL); err != nil {
			return nil, fmt.Errorf("db: scanning a show's feed url: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// SubscriptionURLs lists the URL the account last subscribed each show
// it follows by, in show order.
func (d *DB) SubscriptionURLs(ctx context.Context, userID string) ([]ShowURL, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT show_pid, feed_url FROM podcast_subscriptions WHERE user_id = ? ORDER BY show_pid`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing subscription feed urls: %w", err)
	}
	return scanShowURLs(rows)
}

// GpodderDeviceURL is what one device calls a show. RemovedSec, once a
// read told the device the account left the show under that URL, is the
// second from which the device's reads show it took that; 0 otherwise.
type GpodderDeviceURL struct {
	ShowPID    string
	FeedURL    string
	RemovedSec int64
}

// GpodderDeviceURLs lists what one device calls each show it knows.
func (d *DB) GpodderDeviceURLs(ctx context.Context, userID, deviceID string) ([]GpodderDeviceURL, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT show_pid, feed_url, removed_sec FROM gpodder_device_urls WHERE user_id = ? AND device_id = ?
		ORDER BY show_pid`, userID, deviceID)
	if err != nil {
		return nil, fmt.Errorf("db: listing a gpodder device's feed urls: %w", err)
	}
	defer rows.Close()
	var out []GpodderDeviceURL
	for rows.Next() {
		var u GpodderDeviceURL
		if err := rows.Scan(&u.ShowPID, &u.FeedURL, &u.RemovedSec); err != nil {
			return nil, fmt.Errorf("db: scanning a gpodder device's feed url: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// GpodderShowDeviceURLs lists what the account's devices call one show.
func (d *DB) GpodderShowDeviceURLs(ctx context.Context, userID, showPID string) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT feed_url FROM gpodder_device_urls WHERE user_id = ? AND show_pid = ?`, userID, showPID)
	if err != nil {
		return nil, fmt.Errorf("db: listing a show's gpodder device urls: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			return nil, fmt.Errorf("db: scanning a show's gpodder device url: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// rememberGpodderDeviceURL is the statement that records a device's URL
// for a show, which a device nobody registered keeps none of. What the
// device sends is what it holds, whatever it was told before.
const rememberGpodderDeviceURL = `
	INSERT INTO gpodder_device_urls (user_id, device_id, show_pid, feed_url)
	SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM gpodder_devices WHERE user_id = ? AND device_id = ?)
	ON CONFLICT (user_id, device_id, show_pid) DO UPDATE SET feed_url = excluded.feed_url, removed_sec = 0`

// fillGpodderDeviceURL is rememberGpodderDeviceURL for what a read told a
// device, which leaves a URL the device has.
const fillGpodderDeviceURL = `
	INSERT INTO gpodder_device_urls (user_id, device_id, show_pid, feed_url)
	SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM gpodder_devices WHERE user_id = ? AND device_id = ?)
	ON CONFLICT (user_id, device_id, show_pid) DO NOTHING`

// RememberGpodderDeviceURLs records what one device calls each show, by
// what it sent.
func (d *DB) RememberGpodderDeviceURLs(ctx context.Context, userID, deviceID string, urls []ShowURL) error {
	return d.writeGpodderDeviceURLs(ctx, rememberGpodderDeviceURL, userID, deviceID, urls)
}

// FillGpodderDeviceURLs records what a read told one device each show is
// called, for the shows it had no URL for; a URL the device sent since the
// read began stays.
func (d *DB) FillGpodderDeviceURLs(ctx context.Context, userID, deviceID string, urls []ShowURL) error {
	return d.writeGpodderDeviceURLs(ctx, fillGpodderDeviceURL, userID, deviceID, urls)
}

func (d *DB) writeGpodderDeviceURLs(ctx context.Context, stmt, userID, deviceID string, urls []ShowURL) error {
	if len(urls) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: remembering gpodder device urls: %w", err)
	}
	defer tx.Rollback()
	for _, u := range urls {
		if _, err := tx.ExecContext(ctx, stmt,
			userID, deviceID, u.ShowPID, u.FeedURL, userID, deviceID); err != nil {
			return fmt.Errorf("db: remembering a gpodder device url: %w", err)
		}
	}
	return tx.Commit()
}

// The URLs a device keeps no more: one it was told a show's removal
// under, once it reads from the second marked on it or past, whatever the
// log now says of the show; and, when it reads a list, any it was told a
// removal under and each of a show the account no longer follows.
const (
	gpodderDeviceURLsRemoved = ` WHERE user_id = ? AND device_id = ?
		AND removed_sec > 0 AND removed_sec <= ?`
	gpodderDeviceURLsUnfollowed = ` WHERE user_id = ? AND device_id = ? AND (removed_sec > 0 OR NOT EXISTS (
		SELECT 1 FROM podcast_subscriptions s WHERE s.user_id = gpodder_device_urls.user_id
			AND s.show_pid = gpodder_device_urls.show_pid))`
)

// ForgetRemovedGpodderDeviceURLs drops what one device calls each show it
// was told the removal of, once it reads changes from sinceSec, at or past
// the second marked on the URL.
func (d *DB) ForgetRemovedGpodderDeviceURLs(ctx context.Context, userID, deviceID string, sinceSec int64) error {
	return d.forgetGpodderDeviceURLs(ctx, gpodderDeviceURLsRemoved, userID, deviceID, sinceSec)
}

// ForgetUnfollowedGpodderDeviceURLs drops what one device calls each show
// the account no longer follows, or it was told the account left, once the
// device read a list.
func (d *DB) ForgetUnfollowedGpodderDeviceURLs(ctx context.Context, userID, deviceID string) error {
	return d.forgetGpodderDeviceURLs(ctx, gpodderDeviceURLsUnfollowed, userID, deviceID)
}

// ForgetGpodderDeviceURL drops what one device calls a show it let go of.
func (d *DB) ForgetGpodderDeviceURL(ctx context.Context, userID, deviceID, showPID string) error {
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM gpodder_device_urls WHERE user_id = ? AND device_id = ? AND show_pid = ?`,
		userID, deviceID, showPID); err != nil {
		return fmt.Errorf("db: forgetting a gpodder device's url: %w", err)
	}
	return nil
}

// MarkGpodderDeviceURLsRemoved records what a read told one device under
// the URLs it calls shows by: the account left the show (RemovedSec, the
// second from which a read shows the device took it), or follows it again
// (RemovedSec 0). Each mark lands only while the device still calls the
// show by the URL the read said, marked as the read found it.
func (d *DB) MarkGpodderDeviceURLsRemoved(ctx context.Context, userID, deviceID string, marks []GpodderDeviceURL) error {
	if len(marks) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: marking gpodder device urls: %w", err)
	}
	defer tx.Rollback()
	for _, m := range marks {
		was := `removed_sec = 0`
		if m.RemovedSec == 0 {
			was = `removed_sec > 0`
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE gpodder_device_urls SET removed_sec = ?
			WHERE user_id = ? AND device_id = ? AND show_pid = ? AND feed_url = ? AND `+was,
			m.RemovedSec, userID, deviceID, m.ShowPID, m.FeedURL); err != nil {
			return fmt.Errorf("db: marking a gpodder device url: %w", err)
		}
	}
	return tx.Commit()
}

// forgetGpodderDeviceURLs deletes the rows the where clause names, asking
// the writer only when there are any.
func (d *DB) forgetGpodderDeviceURLs(ctx context.Context, where string, args ...any) error {
	var n int
	if err := d.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM gpodder_device_urls`+where, args...).Scan(&n); err != nil {
		return fmt.Errorf("db: reading a gpodder device's urls: %w", err)
	}
	if n == 0 {
		return nil
	}
	if _, err := d.w.ExecContext(ctx, `DELETE FROM gpodder_device_urls`+where, args...); err != nil {
		return fmt.Errorf("db: forgetting a gpodder device's urls: %w", err)
	}
	return nil
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
	// GUID names the episode by its feed's guid. Only an action the
	// service makes up carries one; none is stored.
	GUID string
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
	q += ` ORDER BY seq`
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

// GpodderSession is one gpodder session: the cookie a client presents,
// stored only as its hash, tied to the app password that opened it.
type GpodderSession struct {
	ID            string
	UserID        string
	AppPasswordID string
	TokenHash     []byte
	CreatedAtNS   int64
	ExpiresAtNS   int64
	// Basic marks a session a request signed with Basic credentials
	// opened, rather than a login.
	Basic bool
	// Presented marks a session whose cookie came back.
	Presented bool
}

// InsertGpodderSession records a session, then ends the app password's
// sessions of the same kind, logins or Basic-opened ones, past
// perPasswordCap, never the new one: first those whose cookies never came
// back, then the oldest. A client that logs in on every sync, or signs
// every request and keeps no cookie, holds a bounded number and turns over
// only its own.
func (d *DB) InsertGpodderSession(ctx context.Context, s GpodderSession, perPasswordCap int) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpodder_sessions (id, user_id, app_password_id, token_hash, created_at_ns, expires_at_ns, basic, presented)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.ID, s.UserID, s.AppPasswordID, s.TokenHash, s.CreatedAtNS, s.ExpiresAtNS,
		boolInt(s.Basic), boolInt(s.Presented)); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM gpodder_sessions WHERE app_password_id = ? AND basic = ? AND id <> ? AND id NOT IN (
			SELECT id FROM gpodder_sessions WHERE app_password_id = ? AND basic = ? AND id <> ?
			ORDER BY presented DESC, created_at_ns DESC, id DESC LIMIT ?)`,
		s.AppPasswordID, boolInt(s.Basic), s.ID, s.AppPasswordID, boolInt(s.Basic), s.ID, perPasswordCap-1); err != nil {
		return err
	}
	return tx.Commit()
}

// MarkGpodderSessionPresented records that a session's cookie came back.
func (d *DB) MarkGpodderSessionPresented(ctx context.Context, id string) error {
	if _, err := d.w.ExecContext(ctx, `
		UPDATE gpodder_sessions SET presented = 1 WHERE id = ? AND presented = 0`, id); err != nil {
		return fmt.Errorf("db: marking a gpodder session presented: %w", err)
	}
	return nil
}

// GpodderSessionByHash finds the session a cookie hashes to; ErrNotFound
// when none does.
func (d *DB) GpodderSessionByHash(ctx context.Context, hash []byte) (*GpodderSession, error) {
	var s GpodderSession
	err := d.r.QueryRowContext(ctx, `
		SELECT id, user_id, app_password_id, token_hash, created_at_ns, expires_at_ns, basic, presented
		FROM gpodder_sessions WHERE token_hash = ?`, hash).
		Scan(&s.ID, &s.UserID, &s.AppPasswordID, &s.TokenHash, &s.CreatedAtNS, &s.ExpiresAtNS, &s.Basic, &s.Presented)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// DeleteGpodderSessionByHash ends the session a cookie hashes to; ending
// one that is already gone is not an error.
func (d *DB) DeleteGpodderSessionByHash(ctx context.Context, hash []byte) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM gpodder_sessions WHERE token_hash = ?`, hash)
	return err
}

// DeleteGpodderSessionsForUser ends every gpodder session of the account.
func (d *DB) DeleteGpodderSessionsForUser(ctx context.Context, userID string) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM gpodder_sessions WHERE user_id = ?`, userID)
	return err
}

// The action cap's statements, each a seek of the account's actions by
// their number.
const (
	gpodderActionSpan = `SELECT
		(SELECT seq FROM gpodder_actions WHERE user_id = ? ORDER BY seq DESC LIMIT 1),
		(SELECT seq FROM gpodder_actions WHERE user_id = ? ORDER BY seq LIMIT 1)`
	gpodderDropActions = `DELETE FROM gpodder_actions WHERE user_id = ? AND seq <= ?`
	// gpodderSameAction finds an action the log holds already: the same
	// device, episode, action, time and position.
	gpodderSameAction = `SELECT id FROM gpodder_actions WHERE user_id = ? AND episode_url = ?
		AND device_id = ? AND action = ? AND action_ts = ? AND position_sec IS ?`
)

// AppendGpodderActions records one uploaded batch and answers, for each
// action, the id of the row that keeps it: one the log holds already is
// kept once, a client that sends a batch again adding nothing. Each new
// action takes the number after its account's newest; once the numbers
// kept span a tenth more than perUserCap, the actions older than the
// newest perUserCap numbers go in one range. The batch is in flight from
// before it waits for the writer until it commits.
func (d *DB) AppendGpodderActions(ctx context.Context, actions []GpodderAction, perUserCap int) ([]int64, error) {
	if len(actions) == 0 {
		return nil, nil
	}
	stamped := map[string]int64{}
	for _, a := range actions {
		if sec, ok := stamped[a.UserID]; !ok || a.UploadedSec < sec {
			stamped[a.UserID] = a.UploadedSec
		}
	}
	for user, sec := range stamped {
		defer d.gpodderWrites.hold(user, sec)()
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: appending gpodder actions: %w", err)
	}
	defer tx.Rollback()
	type span struct{ newest, oldest int64 }
	spans := map[string]*span{}
	ids := make([]int64, len(actions))
	for i, a := range actions {
		err := tx.QueryRowContext(ctx, gpodderSameAction, a.UserID, a.EpisodeURL, a.DeviceID,
			a.Action, a.ActionTS, a.PositionSec).Scan(&ids[i])
		if err == nil {
			continue
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("db: matching a gpodder action: %w", err)
		}
		s := spans[a.UserID]
		if s == nil {
			var newest, oldest sql.NullInt64
			if err := tx.QueryRowContext(ctx, gpodderActionSpan, a.UserID, a.UserID).Scan(&newest, &oldest); err != nil {
				return nil, fmt.Errorf("db: numbering a gpodder action: %w", err)
			}
			s = &span{newest: newest.Int64, oldest: newest.Int64 + 1}
			if oldest.Valid {
				s.oldest = oldest.Int64
			}
			spans[a.UserID] = s
		}
		s.newest++
		res, err := tx.ExecContext(ctx, `
			INSERT INTO gpodder_actions (user_id, seq, podcast_url, episode_url, device_id,
				action, action_ts, started_sec, position_sec, total_sec, uploaded_sec)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			a.UserID, s.newest, a.PodcastURL, a.EpisodeURL, a.DeviceID, a.Action, a.ActionTS,
			a.StartedSec, a.PositionSec, a.TotalSec, a.UploadedSec)
		if err != nil {
			return nil, fmt.Errorf("db: appending gpodder action: %w", err)
		}
		if ids[i], err = res.LastInsertId(); err != nil {
			return nil, fmt.Errorf("db: appending gpodder action: %w", err)
		}
	}
	for user, s := range spans {
		if s.newest-s.oldest+1 > int64(perUserCap+perUserCap/10) {
			if _, err := tx.ExecContext(ctx, gpodderDropActions, user, s.newest-int64(perUserCap)); err != nil {
				return nil, fmt.Errorf("db: capping gpodder actions: %w", err)
			}
		}
	}
	return ids, tx.Commit()
}

// PruneGpodderSubEvents drops removals made before the cutoff, in epoch
// seconds, and what devices call shows the account neither follows nor
// has a change left to tell of. An add stays however old: it is how a
// new device learns the show is followed.
func (d *DB) PruneGpodderSubEvents(ctx context.Context, beforeSec int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM gpodder_sub_events WHERE action = 'remove' AND ts_sec < ?`, beforeSec)
	if err != nil {
		return 0, fmt.Errorf("db: pruning gpodder sub events: %w", err)
	}
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM gpodder_device_urls WHERE NOT EXISTS (
			SELECT 1 FROM gpodder_sub_events e
			WHERE e.user_id = gpodder_device_urls.user_id AND e.show_pid = gpodder_device_urls.show_pid)
		AND NOT EXISTS (
			SELECT 1 FROM podcast_subscriptions s
			WHERE s.user_id = gpodder_device_urls.user_id AND s.show_pid = gpodder_device_urls.show_pid)`); err != nil {
		return 0, fmt.Errorf("db: pruning gpodder device urls: %w", err)
	}
	return res.RowsAffected()
}

// PruneGpodderActions drops actions uploaded before the cutoff, in epoch
// seconds.
func (d *DB) PruneGpodderActions(ctx context.Context, beforeSec int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `DELETE FROM gpodder_actions WHERE uploaded_sec < ?`, beforeSec)
	if err != nil {
		return 0, fmt.Errorf("db: pruning gpodder actions: %w", err)
	}
	return res.RowsAffected()
}

// GpodderNotice is one thing the account was told of a device's failed
// adds: of the feed with this key, or of the account itself when the key
// is empty, and why.
type GpodderNotice struct {
	DeviceID string
	FeedKey  string
	Reason   string
}

// GpodderNoticeFeeds lists the keys of the feeds the account was told of
// for the device and the reason at or after sinceNS.
func (d *DB) GpodderNoticeFeeds(ctx context.Context, userID, deviceID, reason string, sinceNS int64) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT feed_key FROM gpodder_notices WHERE user_id = ? AND device_id = ? AND reason = ? AND said_ns >= ?`,
		userID, deviceID, reason, sinceNS)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder notices: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder notice: %w", err)
		}
		out = append(out, key)
	}
	return out, rows.Err()
}

// GpodderNoticesSaid answers which of the notices the account was told at
// or after sinceNS.
func (d *DB) GpodderNoticesSaid(ctx context.Context, userID string, notices []GpodderNotice, sinceNS int64) (map[GpodderNotice]bool, error) {
	said := map[GpodderNotice]bool{}
	if len(notices) == 0 {
		return said, nil
	}
	asked := make(map[GpodderNotice]bool, len(notices))
	for _, n := range notices {
		asked[n] = true
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT device_id, feed_key, reason FROM gpodder_notices WHERE user_id = ? AND said_ns >= ?`, userID, sinceNS)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder notices: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var n GpodderNotice
		if err := rows.Scan(&n.DeviceID, &n.FeedKey, &n.Reason); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder notice: %w", err)
		}
		if asked[n] {
			said[n] = true
		}
	}
	return said, rows.Err()
}

// NoteGpodderNotices records that the account was told the notices at
// atNS.
func (d *DB) NoteGpodderNotices(ctx context.Context, userID string, notices []GpodderNotice, atNS int64) error {
	if len(notices) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: noting gpodder notices: %w", err)
	}
	defer tx.Rollback()
	for _, n := range notices {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO gpodder_notices (user_id, device_id, feed_key, reason, said_ns) VALUES (?, ?, ?, ?, ?)
			ON CONFLICT (user_id, device_id, feed_key, reason) DO UPDATE SET said_ns = excluded.said_ns`,
			userID, n.DeviceID, n.FeedKey, n.Reason, atNS); err != nil {
			return fmt.Errorf("db: noting a gpodder notice: %w", err)
		}
	}
	return tx.Commit()
}

// PruneGpodderNotices drops what was said before the cutoff, in
// nanoseconds.
func (d *DB) PruneGpodderNotices(ctx context.Context, beforeNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `DELETE FROM gpodder_notices WHERE said_ns < ?`, beforeNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning gpodder notices: %w", err)
	}
	return res.RowsAffected()
}

// GpodderHeldBy lists the shows one holder keeps for the account.
func (d *DB) GpodderHeldBy(ctx context.Context, userID, holder string) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT show_pid FROM gpodder_holds WHERE user_id = ? AND holder = ?
		ORDER BY show_pid`, userID, holder)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder holds: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var show string
		if err := rows.Scan(&show); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder hold: %w", err)
		}
		out = append(out, show)
	}
	return out, rows.Err()
}

// AttachSubscription records that holder keeps the show for the account
// and creates the subscription row when there was none, in one
// transaction, so neither stands without the other. feedURL becomes the
// account's URL for the show, and the holder's when it is a device.
// created reports a new row; an existing one keeps its settings.
func (d *DB) AttachSubscription(ctx context.Context, s Subscription, holder, feedURL string) (bool, error) {
	return d.attachSubscription(ctx, s, holder, feedURL, true)
}

// AttachKnownSubscription is AttachSubscription for a URL nothing fetched:
// it becomes the holder's, and the account's only when the account had
// none.
func (d *DB) AttachKnownSubscription(ctx context.Context, s Subscription, holder, feedURL string) (bool, error) {
	return d.attachSubscription(ctx, s, holder, feedURL, false)
}

func (d *DB) attachSubscription(ctx context.Context, s Subscription, holder, feedURL string, fetched bool) (bool, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("db: attaching subscription: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpodder_holds (user_id, show_pid, holder) VALUES (?, ?, ?)
		ON CONFLICT (user_id, show_pid, holder) DO NOTHING`, s.UserID, s.ShowPID, holder); err != nil {
		return false, fmt.Errorf("db: adding gpodder hold: %w", err)
	}
	res, err := tx.ExecContext(ctx, `
		INSERT INTO podcast_subscriptions (`+subscriptionCols+`, feed_url)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, show_pid) DO NOTHING`,
		s.UserID, s.ShowPID, s.Folder, boolInt(s.Private), s.RetentionKeep,
		boolInt(s.AutoDownload), s.Speed, nullBool(s.TrimSilence),
		nullBool(s.VoiceBoost), s.SkipIntroSec, s.SkipOutroSec,
		encodeTerms(s.AutoDLInclude), encodeTerms(s.AutoDLExclude),
		s.CreatedAtNS, s.UpdatedAtNS, feedURL)
	if err != nil {
		return false, fmt.Errorf("db: attaching subscription: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: attaching subscription: %w", err)
	}
	if n == 0 {
		respell := `UPDATE podcast_subscriptions SET feed_url = ? WHERE user_id = ? AND show_pid = ?`
		if !fetched {
			respell += ` AND feed_url = ''`
		}
		if _, err := tx.ExecContext(ctx, respell, feedURL, s.UserID, s.ShowPID); err != nil {
			return false, fmt.Errorf("db: attaching subscription: %w", err)
		}
	}
	if holder != "" {
		if _, err := tx.ExecContext(ctx, rememberGpodderDeviceURL,
			s.UserID, holder, s.ShowPID, feedURL, s.UserID, holder); err != nil {
			return false, fmt.Errorf("db: remembering a gpodder device url: %w", err)
		}
	}
	return n > 0, tx.Commit()
}

// RemoveSubscription ends the account's subscription to the show and
// every hold on it, in one transaction. existed reports a row was there,
// and feedURL is what the account called the show.
func (d *DB) RemoveSubscription(ctx context.Context, userID, showPID string) (existed bool, feedURL string, err error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return false, "", fmt.Errorf("db: removing subscription: %w", err)
	}
	defer tx.Rollback()
	err = tx.QueryRowContext(ctx, `
		DELETE FROM podcast_subscriptions WHERE user_id = ? AND show_pid = ? RETURNING feed_url`,
		userID, showPID).Scan(&feedURL)
	existed = err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, "", fmt.Errorf("db: removing subscription: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM gpodder_holds WHERE user_id = ? AND show_pid = ?`, userID, showPID); err != nil {
		return false, "", fmt.Errorf("db: clearing gpodder holds: %w", err)
	}
	return existed, feedURL, tx.Commit()
}

// ReleaseGpodderHold drops one holder's hold on the show and, when it was
// the last, the account's subscription with it, in one transaction.
// released reports the subscription went, and feedURL is what the
// account called the show.
func (d *DB) ReleaseGpodderHold(ctx context.Context, userID, showPID, holder string) (released bool, feedURL string, err error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return false, "", fmt.Errorf("db: releasing gpodder hold: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM gpodder_holds WHERE user_id = ? AND show_pid = ? AND holder = ?`,
		userID, showPID, holder); err != nil {
		return false, "", fmt.Errorf("db: releasing gpodder hold: %w", err)
	}
	err = tx.QueryRowContext(ctx, `
		DELETE FROM podcast_subscriptions WHERE user_id = ? AND show_pid = ? AND NOT EXISTS (
			SELECT 1 FROM gpodder_holds WHERE user_id = ? AND show_pid = ?)
		RETURNING feed_url`,
		userID, showPID, userID, showPID).Scan(&feedURL)
	released = err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, "", fmt.Errorf("db: releasing gpodder hold: %w", err)
	}
	return released, feedURL, tx.Commit()
}

// GpodderPending is one device's ask for a feed that could not be fetched
// yet, parked for another try.
type GpodderPending struct {
	UserID      string
	FeedURL     string
	DeviceID    string
	CreatedAtNS int64
	Attempts    int
	NextTryNS   int64
	LastError   string
}

// GpodderPark is one parked feed: the asks of every device that named it,
// sharing one schedule that runs from the first ask.
type GpodderPark struct {
	UserID string
	// Devices are the devices that asked, in the order they did.
	Devices     []string
	FeedURL     string
	CreatedAtNS int64
	Attempts    int
	NextTryNS   int64
	LastError   string
}

const gpodderPendingCols = `user_id, feed_url, device_id, created_at_ns, attempts, next_try_ns, last_error`

// scanGpodderParks groups ask rows ordered by account and feed into parks.
func scanGpodderParks(rows *sql.Rows) ([]GpodderPark, error) {
	defer rows.Close()
	var out []GpodderPark
	for rows.Next() {
		var p GpodderPending
		if err := rows.Scan(&p.UserID, &p.FeedURL, &p.DeviceID, &p.CreatedAtNS,
			&p.Attempts, &p.NextTryNS, &p.LastError); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder pending: %w", err)
		}
		if n := len(out); n > 0 && out[n-1].UserID == p.UserID && out[n-1].FeedURL == p.FeedURL {
			out[n-1].Devices = append(out[n-1].Devices, p.DeviceID)
			continue
		}
		out = append(out, GpodderPark{UserID: p.UserID, FeedURL: p.FeedURL, Devices: []string{p.DeviceID},
			CreatedAtNS: p.CreatedAtNS, Attempts: p.Attempts, NextTryNS: p.NextTryNS, LastError: p.LastError})
	}
	return out, rows.Err()
}

// ParkGpodderPending records a device's ask for a feed to be tried again.
// A feed already parked keeps its schedule and its first ask, so its
// expiry runs from then, and gains the device; past perUserCap feeds the
// account parks nothing new and the answer is false.
func (d *DB) ParkGpodderPending(ctx context.Context, p GpodderPending, perUserCap int) (bool, error) {
	return d.parkGpodderPending(ctx, p, perUserCap, false)
}

// JoinGpodderPark adds a device's ask to a feed already parked, as
// ParkGpodderPending does; false when the feed is parked no more, which
// parks nothing.
func (d *DB) JoinGpodderPark(ctx context.Context, p GpodderPending) (bool, error) {
	return d.parkGpodderPending(ctx, p, 0, true)
}

func (d *DB) parkGpodderPending(ctx context.Context, p GpodderPending, perUserCap int, joinOnly bool) (bool, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("db: parking gpodder feed: %w", err)
	}
	defer tx.Rollback()
	var created, attempts, next sql.NullInt64
	var lastErr sql.NullString
	if err := tx.QueryRowContext(ctx, `
		SELECT MIN(created_at_ns), MAX(attempts), MIN(next_try_ns), MAX(last_error)
		FROM gpodder_pending WHERE user_id = ? AND feed_url = ?`, p.UserID, p.FeedURL).
		Scan(&created, &attempts, &next, &lastErr); err != nil {
		return false, fmt.Errorf("db: reading gpodder pending: %w", err)
	}
	switch {
	case created.Valid:
		// The ask keeps its own time, so the park's first ask is its
		// earliest row; the schedule is the park's.
		p.Attempts, p.NextTryNS, p.LastError = int(attempts.Int64), next.Int64, lastErr.String
	case joinOnly:
		return false, nil
	default:
		var feeds int
		if err := tx.QueryRowContext(ctx, `
			SELECT COUNT(DISTINCT feed_url) FROM gpodder_pending WHERE user_id = ?`, p.UserID).Scan(&feeds); err != nil {
			return false, fmt.Errorf("db: counting gpodder pending: %w", err)
		}
		if feeds >= perUserCap {
			return false, nil
		}
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO gpodder_pending (`+gpodderPendingCols+`) VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, feed_url, device_id) DO NOTHING`,
		p.UserID, p.FeedURL, p.DeviceID, p.CreatedAtNS, p.Attempts, p.NextTryNS, p.LastError); err != nil {
		return false, fmt.Errorf("db: parking gpodder feed: %w", err)
	}
	return true, tx.Commit()
}

// GpodderParks lists the account's parked feeds, first asked first.
func (d *DB) GpodderParks(ctx context.Context, userID string) ([]GpodderPark, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+gpodderPendingCols+` FROM gpodder_pending WHERE user_id = ?
		ORDER BY feed_url, created_at_ns, device_id`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing gpodder pending: %w", err)
	}
	parks, err := scanGpodderParks(rows)
	if err != nil {
		return nil, err
	}
	sort.SliceStable(parks, func(i, j int) bool { return parks[i].CreatedAtNS < parks[j].CreatedAtNS })
	return parks, nil
}

// GpodderParkAsks lists the asks still standing for one parked feed,
// first asked first.
func (d *DB) GpodderParkAsks(ctx context.Context, userID, feedURL string) ([]GpodderPending, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+gpodderPendingCols+` FROM gpodder_pending WHERE user_id = ? AND feed_url = ?
		ORDER BY created_at_ns, device_id`, userID, feedURL)
	if err != nil {
		return nil, fmt.Errorf("db: listing a parked feed's asks: %w", err)
	}
	defer rows.Close()
	var out []GpodderPending
	for rows.Next() {
		var p GpodderPending
		if err := rows.Scan(&p.UserID, &p.FeedURL, &p.DeviceID, &p.CreatedAtNS,
			&p.Attempts, &p.NextTryNS, &p.LastError); err != nil {
			return nil, fmt.Errorf("db: scanning gpodder pending: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// DueGpodderParks lists the parked feeds due a try at nowNS, soonest due
// first, at most limit of them.
func (d *DB) DueGpodderParks(ctx context.Context, nowNS int64, limit int) ([]GpodderPark, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT p.user_id, p.feed_url, p.device_id, p.created_at_ns, p.attempts, p.next_try_ns, p.last_error
		FROM gpodder_pending p JOIN (
			SELECT user_id, feed_url, MIN(next_try_ns) AS due FROM gpodder_pending
			GROUP BY user_id, feed_url HAVING due <= ?
			ORDER BY due, user_id, feed_url LIMIT ?) k
		ON k.user_id = p.user_id AND k.feed_url = p.feed_url
		ORDER BY k.due, p.user_id, p.feed_url, p.created_at_ns, p.device_id`, nowNS, limit)
	if err != nil {
		return nil, fmt.Errorf("db: listing due gpodder pending: %w", err)
	}
	return scanGpodderParks(rows)
}

// RescheduleGpodderParkAsks records the tries of a parked feed and when to
// try next for these asks, each the one its device made at the time it
// carries; an ask made since keeps its own schedule.
func (d *DB) RescheduleGpodderParkAsks(ctx context.Context, userID, feedURL string, asks []GpodderPending, attempts int, nextTryNS int64, lastErr string) error {
	if len(asks) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: rescheduling gpodder asks: %w", err)
	}
	defer tx.Rollback()
	for _, a := range asks {
		if _, err := tx.ExecContext(ctx, `
			UPDATE gpodder_pending SET attempts = ?, next_try_ns = ?, last_error = ?
			WHERE user_id = ? AND feed_url = ? AND device_id = ? AND created_at_ns = ?`,
			attempts, nextTryNS, lastErr, userID, feedURL, a.DeviceID, a.CreatedAtNS); err != nil {
			return fmt.Errorf("db: rescheduling a gpodder ask: %w", err)
		}
	}
	return tx.Commit()
}

// DeleteGpodderPending drops a parked feed for every device that asked:
// it landed, it never will, or the account let go of it.
func (d *DB) DeleteGpodderPending(ctx context.Context, userID, feedURL string) error {
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM gpodder_pending WHERE user_id = ? AND feed_url = ?`, userID, feedURL); err != nil {
		return fmt.Errorf("db: deleting gpodder pending: %w", err)
	}
	return nil
}

// DropGpodderParkAsks drops these asks of a parked feed, each the one its
// device made at the time it carries; an ask made since stays.
func (d *DB) DropGpodderParkAsks(ctx context.Context, userID, feedURL string, asks []GpodderPending) error {
	if len(asks) == 0 {
		return nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: dropping gpodder asks: %w", err)
	}
	defer tx.Rollback()
	for _, a := range asks {
		if _, err := tx.ExecContext(ctx, `
			DELETE FROM gpodder_pending WHERE user_id = ? AND feed_url = ? AND device_id = ? AND created_at_ns = ?`,
			userID, feedURL, a.DeviceID, a.CreatedAtNS); err != nil {
			return fmt.Errorf("db: dropping a gpodder ask: %w", err)
		}
	}
	return tx.Commit()
}

// DropGpodderPendingFor drops one device's asks for the parked feeds its
// list no longer names; another device's ask for the same feed stays.
func (d *DB) DropGpodderPendingFor(ctx context.Context, userID, deviceID string, keep []string) error {
	kept := make(map[string]bool, len(keep))
	for _, u := range keep {
		kept[u] = true
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT feed_url FROM gpodder_pending WHERE user_id = ? AND device_id = ?`, userID, deviceID)
	if err != nil {
		return fmt.Errorf("db: listing a device's gpodder pending: %w", err)
	}
	var drop []string
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			return fmt.Errorf("db: scanning gpodder pending: %w", err)
		}
		if !kept[u] {
			drop = append(drop, u)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("db: listing a device's gpodder pending: %w", err)
	}
	for _, u := range drop {
		if _, err := d.w.ExecContext(ctx, `
			DELETE FROM gpodder_pending WHERE user_id = ? AND feed_url = ? AND device_id = ?`,
			userID, u, deviceID); err != nil {
			return fmt.Errorf("db: dropping gpodder pending: %w", err)
		}
	}
	return nil
}
