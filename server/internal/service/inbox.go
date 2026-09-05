package service

import (
	"context"
	"errors"
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
	CreatedAt time.Time
	// ReadAt is zero while the row is unread.
	ReadAt time.Time
}

// InboxPage is one keyset page of the caller's inbox.
type InboxPage struct {
	Notifications []InboxNotification
	Next          string
	// Unread counts the whole inbox, not the page: it is the bell badge.
	Unread int
}

func inboxDTO(n wdb.Notification) InboxNotification {
	out := InboxNotification{
		ID:        n.ID,
		Event:     n.Event,
		Title:     n.Title,
		Body:      n.Body,
		TargetPID: n.TargetPID,
		CreatedAt: time.Unix(0, n.CreatedNS).UTC(),
	}
	if n.ReadNS != 0 {
		out.ReadAt = time.Unix(0, n.ReadNS).UTC()
	}
	return out
}

// Notifications pages the caller's inbox newest first.
func (l *Library) Notifications(ctx context.Context, uc *UserCtx, cursor string, limit int) (InboxPage, error) {
	// Guarded here as well as at the handler: a limit under one makes
	// the page slice below a panic rather than a wrong answer.
	if limit < 1 {
		return InboxPage{}, errInvalid("limit must be at least 1")
	}
	if cursor != "" {
		if prefix, _, ok := parseAPIPID(cursor); !ok || prefix != PrefixNotification {
			return InboxPage{}, errInvalid("bad cursor")
		}
	}
	rows, err := l.db.ListNotifications(ctx, uc.ID, cursor, limit+1)
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
		page.Next = rows[len(rows)-1].ID
	}
	unread, err := l.db.UnreadNotificationCount(ctx, uc.ID)
	if err != nil {
		return InboxPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page.Unread = unread
	return page, nil
}

// MarkNotificationsRead stamps the named rows, or every unread row when
// ids is empty.
func (l *Library) MarkNotificationsRead(ctx context.Context, uc *UserCtx, ids []string) error {
	// The spec's cap, enforced here: the ids become bound parameters,
	// and SQLite's own limit would turn a long list into an internal
	// error rather than the refusal the caller can act on.
	if len(ids) > notificationReadBatch {
		return errInvalid("at most 200 notification ids per request")
	}
	for _, id := range ids {
		if prefix, _, ok := parseAPIPID(id); !ok || prefix != PrefixNotification {
			return errInvalid("bad notification id " + id)
		}
	}
	if err := l.db.MarkNotificationsRead(ctx, uc.ID, ids, time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// DeleteNotification removes one of the caller's rows.
func (l *Library) DeleteNotification(ctx context.Context, uc *UserCtx, id string) error {
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
func (l *Library) ClearNotifications(ctx context.Context, uc *UserCtx) error {
	if err := l.db.ClearNotifications(ctx, uc.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// PruneNotifications drops inbox rows past the horizon and the cap.
func (l *Library) PruneNotifications(ctx context.Context) {
	cutoff := time.Now().Add(-notificationHorizon).UnixNano()
	if n, err := l.db.PruneNotifications(ctx, cutoff, notificationPerUserCap); err != nil {
		l.log.Warn("pruning notifications", "err", err)
	} else if n > 0 {
		l.log.Info("pruned notifications", "rows", n)
	}
}

// recordNotification writes the inbox row and marks the caller's sync
// stream, so a client hears about it whether or not the account has a
// delivery target for the event.
func (l *Library) recordNotification(ctx context.Context, userID, event, title, body, targetPID string, now int64) {
	if userID == "" {
		return
	}
	id := PrefixNotification + "-" + ulid.Make().String()
	if err := l.db.InsertNotification(ctx, wdb.Notification{
		ID: id, UserID: userID, Event: event, Title: title, Body: body,
		TargetPID: targetPID, CreatedNS: now,
	}); err != nil {
		l.log.Warn("writing notification", "event", event, "user", userID, "err", err)
		return
	}
	l.emitUserEvent(ctx, userID, eventNotification, id)
}
