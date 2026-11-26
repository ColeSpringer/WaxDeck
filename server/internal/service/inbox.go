package service

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Inbox retention. Ninety days keeps a season of history; the per-account
// cap is what bounds a noisy account between sweeps.
const (
	notificationHorizon    = 90 * 24 * time.Hour
	notificationPerUserCap = 500
	// notificationReadBatch is how many ids one mark-read call takes,
	// matching the schema's maxItems.
	notificationReadBatch = 200
)

// InboxNotification is one inbox row in API shape.
type InboxNotification struct {
	ID        string
	Event     string
	Title     string
	Body      string
	TargetPID string
	// Count is how many occurrences the row folds.
	Count     int
	CreatedAt time.Time
	// UpdatedAt is the latest occurrence, which orders the listing.
	UpdatedAt time.Time
	// ReadAt is zero while the row is unread.
	ReadAt time.Time
	// ResolvedAt is zero while what the row reports is still open.
	ResolvedAt time.Time
}

// InboxPage is one keyset page of the caller's inbox.
type InboxPage struct {
	Notifications []InboxNotification
	Next          string
	// Unread counts the whole inbox, not the page: it is the bell badge.
	Unread int
}

func nsTime(ns int64) time.Time {
	if ns == 0 {
		return time.Time{}
	}
	return time.Unix(0, ns).UTC()
}

func inboxDTO(n wdb.Notification) InboxNotification {
	return InboxNotification{
		ID:         n.ID,
		Event:      n.Event,
		Title:      n.Title,
		Body:       n.Body,
		TargetPID:  n.TargetPID,
		Count:      max(n.Count, 1),
		CreatedAt:  nsTime(n.CreatedNS),
		UpdatedAt:  nsTime(cmp.Or(n.BumpedNS, n.CreatedNS)),
		ReadAt:     nsTime(n.ReadNS),
		ResolvedAt: nsTime(n.ResolvedNS),
	}
}

func encodeInboxCursor(bumpedNS int64, id string) string {
	return encodeOpaqueCursor(fmt.Sprintf("n1|%d|%s", bumpedNS, id))
}

func decodeInboxCursor(s string) (int64, string, bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return 0, "", false
	}
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 || parts[0] != "n1" {
		return 0, "", false
	}
	ns, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, "", false
	}
	if prefix, _, ok := parseAPIPID(parts[2]); !ok || prefix != PrefixNotification {
		return 0, "", false
	}
	return ns, parts[2], true
}

// Notifications pages the caller's inbox by latest occurrence, newest
// first.
func (l *Integrations) Notifications(ctx context.Context, uc *UserCtx, cursor string, limit int) (InboxPage, error) {
	// Guarded here as well as at the handler: a limit under one makes
	// the page slice below a panic rather than a wrong answer.
	if limit < 1 {
		return InboxPage{}, errInvalid("limit must be at least 1")
	}
	var (
		afterNS int64
		afterID string
	)
	if cursor != "" {
		var ok bool
		if afterNS, afterID, ok = decodeInboxCursor(cursor); !ok {
			return InboxPage{}, errInvalid("bad cursor")
		}
	}
	rows, err := l.db.ListNotifications(ctx, uc.ID, afterNS, afterID, limit+1)
	if err != nil {
		return InboxPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page := InboxPage{}
	more := len(rows) > limit
	if more {
		rows = rows[:limit]
	}
	for _, r := range rows {
		page.Notifications = append(page.Notifications, inboxDTO(r))
	}
	if more && len(rows) > 0 {
		last := rows[len(rows)-1]
		page.Next = encodeInboxCursor(cmp.Or(last.BumpedNS, last.CreatedNS), last.ID)
	}
	unread, err := l.db.UnreadNotificationCount(ctx, uc.ID)
	if err != nil {
		return InboxPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page.Unread = unread
	return page, nil
}

// InboxRead names the rows a mark-read stamps: IDs, or every unread row
// of Events (naming TargetPID, when it is set), or with neither every
// unread row.
type InboxRead struct {
	IDs       []string
	Events    []string
	TargetPID string
}

// MarkInboxRead stamps the rows r names. Ids beside events, or a target
// without events, are refused.
func (l *Integrations) MarkInboxRead(ctx context.Context, uc *UserCtx, r InboxRead) error {
	// The spec's cap, enforced here: the ids become bound parameters,
	// and SQLite's own limit would turn a long list into an internal
	// error rather than the refusal the caller can act on.
	if len(r.IDs) > notificationReadBatch {
		return errInvalid("at most 200 notification ids per request")
	}
	if len(r.Events) > notificationReadBatch {
		return errInvalid("at most 200 events per request")
	}
	switch {
	case len(r.IDs) > 0 && len(r.Events) > 0:
		return errInvalid("name rows by ids or by events, not both")
	case r.TargetPID != "" && len(r.Events) == 0:
		return errInvalid("targetPid narrows events and needs them")
	}
	for _, id := range r.IDs {
		if prefix, _, ok := parseAPIPID(id); !ok || prefix != PrefixNotification {
			return errInvalid("bad notification id " + id)
		}
	}
	now := time.Now().UnixNano()
	var err error
	if len(r.Events) > 0 {
		err = l.db.MarkNotificationEventsRead(ctx, uc.ID, r.Events, r.TargetPID, now)
	} else {
		err = l.db.MarkNotificationsRead(ctx, uc.ID, r.IDs, now)
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// DeleteNotification removes one of the caller's rows.
func (l *Integrations) DeleteNotification(ctx context.Context, uc *UserCtx, id string) error {
	if prefix, _, ok := parseAPIPID(id); !ok || prefix != PrefixNotification {
		return errNotFound("no notification with id " + id)
	}
	err := l.db.DeleteNotification(ctx, uc.ID, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return errNotFound("no notification with id " + id)
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// ClearNotifications empties the caller's inbox.
func (l *Integrations) ClearNotifications(ctx context.Context, uc *UserCtx) error {
	if err := l.db.ClearNotifications(ctx, uc.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// ClearResolvedNotifications removes the caller's resolved rows.
func (l *Integrations) ClearResolvedNotifications(ctx context.Context, uc *UserCtx) error {
	if err := l.db.ClearResolvedNotifications(ctx, uc.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// resolvingEvents are the events whose row stays open until what it
// reports is settled, which the prune never takes while it is open.
var resolvingEvents = []string{"review-ready", "signup-requested"}

// PruneNotifications drops inbox rows past the horizon and the cap.
func (l *Integrations) PruneNotifications(ctx context.Context) {
	cutoff := time.Now().Add(-notificationHorizon).UnixNano()
	if n, err := l.db.PruneNotifications(ctx, cutoff, notificationPerUserCap, resolvingEvents); err != nil {
		l.log.Warn("pruning notifications", "err", err)
	} else if n > 0 {
		l.log.Info("pruned notifications", "rows", n)
	}
}

// recordNotification writes the inbox row, or folds it into the keyed
// row the account holds, and marks the account's sync stream, so a
// client hears about it whether or not the account has a delivery target
// for the event.
func (l *Integrations) recordNotification(ctx context.Context, userID, event, title, body, targetPID string, now int64, o notifyOptions) {
	if userID == "" {
		return
	}
	row := wdb.Notification{
		ID: PrefixNotification + "-" + ulid.Make().String(), UserID: userID, Event: event,
		Title: title, Body: body, TargetPID: targetPID, DedupeKey: o.key, CreatedNS: now,
	}
	if o.key == "" {
		if err := l.db.InsertNotification(ctx, row); err != nil {
			l.log.Warn("writing notification", "event", event, "user", userID, "err", err)
			return
		}
		l.emitUserEvent(ctx, userID, eventNotification, row.ID)
		return
	}
	l.foldNotification(ctx, row, wdb.NotificationFold{Read: o.readFor != "" && o.readFor == userID})
}

// foldNotification upserts a keyed row and marks the account's stream
// when the row changed.
func (l *Integrations) foldNotification(ctx context.Context, row wdb.Notification, f wdb.NotificationFold) {
	id, changed, err := l.db.UpsertNotification(ctx, row, f)
	if err != nil {
		l.log.Warn("writing notification", "event", row.Event, "user", row.UserID, "err", err)
		return
	}
	if changed {
		l.emitUserEvent(ctx, row.UserID, eventNotification, id)
	}
}

// recountNotification sets the account's keyed row to count occurrences,
// starting one when none stands unless standing, or resolves it at zero.
// No delivery leaves the server: this is the inbox's own tally.
func (l *Integrations) recountNotification(ctx context.Context, userID, event, key, title, body string, count int, standing bool) {
	if count < 1 {
		l.resolveNotifications(ctx, wdb.NotificationResolve{UserIDs: []string{userID}, Key: key})
		return
	}
	now := time.Now().UnixNano()
	l.foldNotification(ctx, wdb.Notification{
		ID: PrefixNotification + "-" + ulid.Make().String(), UserID: userID, Event: event,
		Title: title, Body: body, DedupeKey: key, Count: count, CreatedNS: now,
	}, wdb.NotificationFold{Recount: true, Standing: standing})
}

// resolveNotifications stamps the rows r picks resolved and marks each
// touched account's stream.
func (l *Integrations) resolveNotifications(ctx context.Context, r wdb.NotificationResolve) {
	// What it settles is already done; a caller gone now changes nothing.
	ctx = context.WithoutCancel(ctx)
	rows, err := l.db.ResolveNotifications(ctx, r, time.Now().UnixNano())
	if err != nil {
		l.log.Warn("resolving notifications", "key", r.Key, "target", r.TargetPID, "err", err)
		return
	}
	for _, row := range rows {
		l.emitUserEvent(ctx, row.UserID, eventNotification, row.ID)
	}
}

// resolveNotificationsFor resolves every unresolved row naming targetPID,
// of userIDs when any are given.
func (l *Integrations) resolveNotificationsFor(ctx context.Context, targetPID string, userIDs ...string) {
	if targetPID == "" {
		return
	}
	l.resolveNotifications(ctx, wdb.NotificationResolve{TargetPID: targetPID, UserIDs: userIDs})
}
