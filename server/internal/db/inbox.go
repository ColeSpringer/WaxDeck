package db

import (
	"cmp"
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
	// DedupeKey folds every occurrence into the account's one unresolved
	// row for it; empty for an event that adds a row each time.
	DedupeKey string
	// Count is how many occurrences the row folds; under one writes one.
	Count     int
	CreatedNS int64
	// BumpedNS is the latest occurrence, which orders the listing; 0
	// writes CreatedNS.
	BumpedNS int64
	// ReadNS is 0 while the row is unread.
	ReadNS int64
	// ResolvedNS is 0 while what the row reports is still open.
	ResolvedNS int64
}

// zeroNull maps an unset time to NULL.
func zeroNull(ns int64) any {
	if ns == 0 {
		return nil
	}
	return ns
}

// InsertNotification writes one inbox row.
func (d *DB) InsertNotification(ctx context.Context, n Notification) error {
	if err := insertNotification(ctx, d.w, n); err != nil {
		return fmt.Errorf("db: writing notification: %w", err)
	}
	return nil
}

func insertNotification(ctx context.Context, x interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}, n Notification) error {
	_, err := x.ExecContext(ctx, `
		INSERT INTO notifications (id, user_id, event, title, body, target_pid,
			dedupe_key, count, created_at_ns, bumped_at_ns, read_at_ns, resolved_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		n.ID, n.UserID, n.Event, n.Title, n.Body, nullable(n.TargetPID),
		nullable(n.DedupeKey), max(n.Count, 1), n.CreatedNS, cmp.Or(n.BumpedNS, n.CreatedNS),
		zeroNull(n.ReadNS), zeroNull(n.ResolvedNS))
	return err
}

// NotificationFiled reports whether userID's inbox holds a row of event
// naming targetPID, resolved or not.
func (d *DB) NotificationFiled(ctx context.Context, userID, event, targetPID string) (bool, error) {
	var filed bool
	if err := d.r.QueryRowContext(ctx, `
		SELECT EXISTS (SELECT 1 FROM notifications WHERE user_id = ? AND event = ? AND target_pid = ?)`,
		userID, event, targetPID).Scan(&filed); err != nil {
		return false, fmt.Errorf("db: reading whether a notification was filed: %w", err)
	}
	return filed, nil
}

// NotificationFold says how an occurrence meets the row its key already
// holds.
type NotificationFold struct {
	// Recount takes the occurrence's Count as the whole count rather than
	// adding one to it: a rise moves the row and marks it unread, a fall
	// leaves both.
	Recount bool
	// Read files a new row read and leaves a standing row's read state
	// as it is.
	Read bool
	// Standing folds only into a row the key already holds: with none,
	// nothing is written.
	Standing bool
}

// UpsertNotification folds n into the account's unresolved row for
// n.DedupeKey, or inserts it under n.ID when none stands. It answers the
// row's id and whether anything changed. The folded row keeps its id and
// its createdAt; an occurrence takes its wording and target pid.
func (d *DB) UpsertNotification(ctx context.Context, n Notification, f NotificationFold) (string, bool, error) {
	if n.DedupeKey == "" {
		return "", false, errors.New("db: upserting a notification without a key")
	}
	at := cmp.Or(n.BumpedNS, n.CreatedNS)
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return "", false, fmt.Errorf("db: upserting notification: %w", err)
	}
	defer tx.Rollback()
	var (
		id, title, body, target string
		count                   int
	)
	err = tx.QueryRowContext(ctx, `
		SELECT id, count, title, body, COALESCE(target_pid, '') FROM notifications
		WHERE dedupe_key = ? AND user_id = ? AND resolved_at_ns IS NULL`,
		n.DedupeKey, n.UserID).Scan(&id, &count, &title, &body, &target)
	switch {
	case errors.Is(err, sql.ErrNoRows) && f.Standing:
		return "", false, nil
	case errors.Is(err, sql.ErrNoRows):
		row := n
		row.Count = 1
		if f.Recount {
			row.Count = n.Count
		}
		row.BumpedNS, row.ResolvedNS, row.ReadNS = at, 0, 0
		if f.Read {
			row.ReadNS = at
		}
		if err := insertNotification(ctx, tx, row); err != nil {
			return "", false, fmt.Errorf("db: upserting notification: %w", err)
		}
		id = n.ID
	case err != nil:
		return "", false, fmt.Errorf("db: upserting notification: %w", err)
	default:
		next := count + 1
		if f.Recount {
			next = n.Count
		}
		if next < 1 {
			return "", false, errors.New("db: a notification counts at least one occurrence")
		}
		if !f.Recount || next > count {
			_, err = tx.ExecContext(ctx, `
				UPDATE notifications SET count = ?, title = ?, body = ?, target_pid = ?,
					bumped_at_ns = ?, read_at_ns = CASE WHEN ? THEN read_at_ns END
				WHERE id = ?`,
				next, n.Title, n.Body, nullable(n.TargetPID), at, f.Read, id)
		} else {
			if next == count && title == n.Title && body == n.Body && target == n.TargetPID {
				return id, false, nil
			}
			_, err = tx.ExecContext(ctx, `
				UPDATE notifications SET count = ?, title = ?, body = ?, target_pid = ?
				WHERE id = ?`,
				next, n.Title, n.Body, nullable(n.TargetPID), id)
		}
		if err != nil {
			return "", false, fmt.Errorf("db: upserting notification: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return "", false, fmt.Errorf("db: upserting notification: %w", err)
	}
	return id, true, nil
}

// UnresolvedKeyHolders lists the accounts holding an unresolved row for
// key.
func (d *DB) UnresolvedKeyHolders(ctx context.Context, key string) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT user_id FROM notifications
		WHERE dedupe_key = ? AND resolved_at_ns IS NULL ORDER BY user_id`, key)
	if err != nil {
		return nil, fmt.Errorf("db: listing a notification key's holders: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("db: listing a notification key's holders: %w", err)
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// NotificationResolve picks the unresolved rows a resolve settles: those
// with Key, or naming TargetPID, or both, of UserIDs when it is not empty.
type NotificationResolve struct {
	UserIDs   []string
	Key       string
	TargetPID string
}

// ResolvedNotification is one row a resolve settled.
type ResolvedNotification struct {
	UserID string
	ID     string
}

// ResolveNotifications stamps the rows r picks resolved, and read when
// unread, so a resolved row never badges; their count and place stay as
// they are. It answers them.
func (d *DB) ResolveNotifications(ctx context.Context, r NotificationResolve, ns int64) ([]ResolvedNotification, error) {
	if r.Key == "" && r.TargetPID == "" {
		return nil, errors.New("db: a resolve names a key or a target")
	}
	q := `UPDATE notifications SET resolved_at_ns = ?, read_at_ns = COALESCE(read_at_ns, ?)
		WHERE resolved_at_ns IS NULL`
	args := []any{ns, ns}
	if r.Key != "" {
		q += ` AND dedupe_key = ?`
		args = append(args, r.Key)
	}
	if r.TargetPID != "" {
		q += ` AND target_pid = ?`
		args = append(args, r.TargetPID)
	}
	if len(r.UserIDs) > 0 {
		q += ` AND user_id IN (?` + strings.Repeat(", ?", len(r.UserIDs)-1) + `)`
		for _, id := range r.UserIDs {
			args = append(args, id)
		}
	}
	q += ` RETURNING user_id, id`
	rows, err := d.w.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: resolving notifications: %w", err)
	}
	defer rows.Close()
	var out []ResolvedNotification
	for rows.Next() {
		var x ResolvedNotification
		if err := rows.Scan(&x.UserID, &x.ID); err != nil {
			return nil, fmt.Errorf("db: resolving notifications: %w", err)
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

const notificationColumns = `id, user_id, event, title, body,
	COALESCE(target_pid, ''), COALESCE(dedupe_key, ''), count, created_at_ns,
	bumped_at_ns, COALESCE(read_at_ns, 0), COALESCE(resolved_at_ns, 0)`

func scanNotification(rows interface{ Scan(...any) error }) (Notification, error) {
	var n Notification
	err := rows.Scan(&n.ID, &n.UserID, &n.Event, &n.Title, &n.Body,
		&n.TargetPID, &n.DedupeKey, &n.Count, &n.CreatedNS, &n.BumpedNS,
		&n.ReadNS, &n.ResolvedNS)
	return n, err
}

// ListNotifications pages one account's inbox by latest occurrence,
// newest first. The cursor is the previous page's last (BumpedNS, ID);
// an empty id starts at the head.
//
// A fold moves its row past every cursor already handed out, so a page
// read after one neither repeats a row it did not move nor skips one.
func (d *DB) ListNotifications(ctx context.Context, userID string, afterNS int64, afterID string, limit int) ([]Notification, error) {
	q := `SELECT ` + notificationColumns + ` FROM notifications WHERE user_id = ?`
	args := []any{userID}
	if afterID != "" {
		q += ` AND (bumped_at_ns, id) < (?, ?)`
		args = append(args, afterNS, afterID)
	}
	q += ` ORDER BY bumped_at_ns DESC, id DESC LIMIT ?`
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

// MarkNotificationEventsRead stamps every unread row of the events, only
// those naming targetPID when it is not empty.
func (d *DB) MarkNotificationEventsRead(ctx context.Context, userID string, events []string, targetPID string, ns int64) error {
	if len(events) == 0 {
		return errors.New("db: marking events read names at least one event")
	}
	q := `UPDATE notifications SET read_at_ns = ? WHERE user_id = ? AND read_at_ns IS NULL
		AND event IN (?` + strings.Repeat(", ?", len(events)-1) + `)`
	args := []any{ns, userID}
	for _, e := range events {
		args = append(args, e)
	}
	if targetPID != "" {
		q += ` AND target_pid = ?`
		args = append(args, targetPID)
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

// ClearResolvedNotifications removes one account's resolved rows.
func (d *DB) ClearResolvedNotifications(ctx context.Context, userID string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM notifications WHERE user_id = ? AND resolved_at_ns IS NOT NULL`, userID); err != nil {
		return fmt.Errorf("db: clearing resolved notifications: %w", err)
	}
	return nil
}

// PruneNotifications drops rows whose latest occurrence is older than a
// cutoff and whatever is past the per-account cap, sparing the unresolved
// rows of the events in spare: what they report is still open, which
// makes them live state rather than history.
//
// One statement and one scan. The obvious spelling - a correlated
// subquery asking "is this row inside its account's newest 500?" -
// re-walks that account's index once per row, which on a hundred
// thousand rows is tens of seconds of a single-writer connection
// blocking every scrobble and play-state write behind it. A window
// function numbers each account's rows in the one pass instead.
//
// The cap rides the listing's order, so what goes is what the listing
// shows last; the age bound reads bumped_at_ns off the same one scan, so
// a row that keeps folding stays.
func (d *DB) PruneNotifications(ctx context.Context, olderThanNS int64, perUserCap int, spare []string) (int64, error) {
	if perUserCap <= 0 {
		perUserCap = -1 // No cap: the age bound alone decides.
	}
	spared, args := "", []any{olderThanNS, perUserCap, perUserCap}
	if len(spare) > 0 {
		spared = ` AND NOT (resolved_at_ns IS NULL AND event IN (?` + strings.Repeat(", ?", len(spare)-1) + `))`
		for _, e := range spare {
			args = append(args, e)
		}
	}
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM notifications WHERE id IN (
			SELECT id FROM (
				SELECT id, bumped_at_ns, event, resolved_at_ns,
				       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY bumped_at_ns DESC, id DESC) AS rn
				FROM notifications
			)
			WHERE (bumped_at_ns < ? OR (? > 0 AND rn > ?))`+spared+`
		)`, args...)
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

// CountNotificationsSince counts the account's inbox rows of event filed
// after sinceNS.
func (d *DB) CountNotificationsSince(ctx context.Context, userID, event string, sinceNS int64) (int, error) {
	var n int
	if err := d.r.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM notifications
		WHERE user_id = ? AND event = ? AND created_at_ns > ?`,
		userID, event, sinceNS).Scan(&n); err != nil {
		return 0, fmt.Errorf("db: counting inbox rows: %w", err)
	}
	return n, nil
}

// reviewWaitsForAPerson is the predicate an inbox counts a pending
// entry by: done identifying, and not in flight. A submission that
// declined identification is in flight until its own import stalls, and
// an auto-apply held for the catalog until the wait ends. The flags live
// in the service's payload: identifyDeclined, importStalled, waitingApply.
// TestADeclinedImportCountsOnlyOnceItStalls and TestAnAutoApplyWaitingForTheCatalogCountsNothing pin the keys.
const reviewWaitsForAPerson = `status = 'pending' AND identifying = 0
	AND NOT COALESCE(CASE WHEN json_valid(payload) THEN
		(COALESCE(json_extract(payload, '$.identifyDeclined'), 0) = 1
			AND COALESCE(json_extract(payload, '$.importStalled'), 0) = 0)
		OR COALESCE(json_extract(payload, '$.waitingApply'), '') != '' END, 0)`

func inOrigins(origins []string) (string, []any) {
	args := make([]any, 0, len(origins))
	for _, o := range origins {
		args = append(args, o)
	}
	return ` AND origin IN (?` + strings.Repeat(", ?", len(origins)-1) + `)`, args
}

// ReviewInboxTally counts the review entries an inbox announces: waiting
// for a person, of one of origins, and uploader's own when uploader is not
// empty. Newest is the latest of them, zero when none wait.
func (d *DB) ReviewInboxTally(ctx context.Context, uploader string, origins []string) (int, ReviewEntry, error) {
	if len(origins) == 0 {
		return 0, ReviewEntry{}, nil
	}
	in, args := inOrigins(origins)
	q := `SELECT ` + reviewCols + `, COUNT(*) OVER () FROM review_entries
		WHERE ` + reviewWaitsForAPerson + in
	if uploader != "" {
		q += ` AND uploaded_by = ?`
		args = append(args, uploader)
	}
	q += ` ORDER BY created_at_ns DESC, id DESC LIMIT 1`
	var n int
	e, err := scanReview(withCount{d.r.QueryRowContext(ctx, q, args...), &n})
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ReviewEntry{}, nil
	}
	if err != nil {
		return 0, ReviewEntry{}, fmt.Errorf("db: tallying the review inbox: %w", err)
	}
	return n, e, nil
}

// withCount scans a review row followed by one trailing count column.
type withCount struct {
	row interface{ Scan(...any) error }
	n   *int
}

func (w withCount) Scan(dest ...any) error { return w.row.Scan(append(dest, w.n)...) }

// ReviewEntryWaits reports whether the entry is one an inbox counts: it
// waits for a person and is of one of origins.
func (d *DB) ReviewEntryWaits(ctx context.Context, id string, origins []string) (bool, error) {
	if len(origins) == 0 {
		return false, nil
	}
	in, args := inOrigins(origins)
	var n int
	err := d.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM review_entries WHERE id = ? AND `+
		reviewWaitsForAPerson+in, append([]any{id}, args...)...).Scan(&n)
	if err != nil {
		return false, fmt.Errorf("db: reading whether a review entry waits: %w", err)
	}
	return n > 0, nil
}
