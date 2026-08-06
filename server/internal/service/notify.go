package service

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/notify"
)

// Notification event scopes.
const (
	NotifyScopeServer = "server"
	NotifyScopeUser   = "user"
)

// NotifyEvent is one catalog entry: an event the server can emit.
type NotifyEvent struct {
	Name        string
	Scope       string
	Description string
}

// notifyEventCatalog is the server's event catalog, server scope
// first. The reserved "test" event never appears here: per-target
// tests bypass event selection by construction.
var notifyEventCatalog = []NotifyEvent{
	{Name: "signup-requested", Scope: NotifyScopeServer,
		Description: "A new account request is waiting for approval."},
	{Name: "backup-completed", Scope: NotifyScopeServer,
		Description: "A backup archive finished building."},
	{Name: "backup-failed", Scope: NotifyScopeServer,
		Description: "A backup attempt failed."},
	{Name: "episode-downloaded", Scope: NotifyScopeUser,
		Description: "A new episode of a subscribed show finished downloading."},
	{Name: "feed-disabled", Scope: NotifyScopeUser,
		Description: "A subscribed feed kept failing and was disabled."},
	{Name: "review-ready", Scope: NotifyScopeUser,
		Description: "An upload or acquisition finished identification and waits in the review queue."},
	{Name: "import-completed", Scope: NotifyScopeUser,
		Description: "An upload or acquisition identified confidently enough to file itself, with no review."},
}

// NotifyEvents returns the event catalog.
func (l *Library) NotifyEvents() []NotifyEvent { return notifyEventCatalog }

func notifyEventByName(name string) (NotifyEvent, bool) {
	for _, e := range notifyEventCatalog {
		if e.Name == name {
			return e, true
		}
	}
	return NotifyEvent{}, false
}

func userScopeEventNames() []string {
	var out []string
	for _, e := range notifyEventCatalog {
		if e.Scope == NotifyScopeUser {
			out = append(out, e.Name)
		}
	}
	return out
}

// NotificationTarget is one delivery destination in the API shape.
// Config is the opened (plaintext) document, returned verbatim to the
// owner; it is sealed at rest.
type NotificationTarget struct {
	PID           string
	Kind          string
	Scope         string
	Label         string
	Config        json.RawMessage
	EnabledEvents []string
	LastSuccessAt time.Time
	LastError     string
	LastErrorAt   time.Time
	CreatedAt     time.Time
}

// NotificationTargetInput is the create and update shape.
type NotificationTargetInput struct {
	Kind          string
	Label         string
	Config        json.RawMessage
	EnabledEvents []string
}

// PushRegistration is one UnifiedPush endpoint in the legacy API
// shape: a compatibility view over a unifiedpush notification target.
type PushRegistration struct {
	PID       string
	Endpoint  string
	Label     string
	CreatedAt time.Time
}

// Notification delivery tuning.
const (
	notifyMaxAttempts   = 10
	notifyLeaseSeconds  = 60
	notifyHorizon       = 24 * time.Hour
	notifyBackoffCap    = 30 * time.Minute
	notifyLabelMax      = 100
	legacyNotifySetting = "notifications"
)

// notifyHTTP is the unguarded delivery client: server-scope targets
// (administrator-configured destinations), fixed-host and allowlisted
// kinds, and UnifiedPush endpoints (self-hosted LAN distributors are
// legitimate; delivery responses are never surfaced to any user).
var notifyHTTP = &http.Client{Timeout: 15 * time.Second}

// guardedNotifyKinds carry user-pointed URLs and ride the dial-guarded
// client for user-scope targets: ntfy, Gotify, generic webhooks, and
// Apprise. Pushover posts to its fixed host, Discord to an allowlist,
// and UnifiedPush is deliberately unguarded (the documented spec
// stance), so none of those appear here.
var guardedNotifyKinds = map[string]bool{
	notify.KindNtfy:    true,
	notify.KindGotify:  true,
	notify.KindWebhook: true,
	notify.KindApprise: true,
}

// guardedNotifyClient builds the dial-guarded delivery client once:
// private addresses refused per connection attempt after DNS
// resolution (defeats rebinding), unless the server allows LAN
// notification hosts.
func (l *Library) guardedNotifyClient() *http.Client {
	l.notifyGuardedOnce.Do(func() {
		dialer := &net.Dialer{Timeout: 10 * time.Second}
		if !l.allowPrivateNotifyHosts {
			dialer.Control = func(network, address string, _ syscall.RawConn) error {
				return refusePrivateAddr(address)
			}
		}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.DialContext = dialer.DialContext
		l.notifyGuardedHTTP = &http.Client{Transport: transport, Timeout: 15 * time.Second}
	})
	return l.notifyGuardedHTTP
}

// notifyClientFor picks the delivery client for one target: user-scope
// targets of guarded kinds dial through the private-address guard,
// everything else through the plain client.
func (l *Library) notifyClientFor(t wdb.NotificationTarget) *http.Client {
	if t.Scope == NotifyScopeUser && guardedNotifyKinds[t.Kind] && !l.allowPrivateNotifyHosts {
		return l.guardedNotifyClient()
	}
	return notifyHTTP
}

// --- target CRUD ------------------------------------------------------------------

// ListServerNotificationTargets lists the server-scope targets.
func (l *Library) ListServerNotificationTargets(ctx context.Context) ([]NotificationTarget, error) {
	rows, err := l.db.ServerNotificationTargets(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return l.notificationTargetDTOs(rows), nil
}

// ListMyNotificationTargets lists the caller's personal targets.
func (l *Library) ListMyNotificationTargets(ctx context.Context, uc *UserCtx) ([]NotificationTarget, error) {
	rows, err := l.db.UserNotificationTargets(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return l.notificationTargetDTOs(rows), nil
}

// CreateServerNotificationTarget stores a server-scope target.
func (l *Library) CreateServerNotificationTarget(ctx context.Context, in NotificationTargetInput) (NotificationTarget, error) {
	row, err := l.buildNotificationTarget(in, NotifyScopeServer, "", false)
	if err != nil {
		return NotificationTarget{}, err
	}
	return l.insertNotificationTarget(ctx, row)
}

// CreateMyNotificationTarget stores a personal target for the caller.
func (l *Library) CreateMyNotificationTarget(ctx context.Context, uc *UserCtx, in NotificationTargetInput) (NotificationTarget, error) {
	row, err := l.buildNotificationTarget(in, NotifyScopeUser, uc.ID, uc.Admin)
	if err != nil {
		return NotificationTarget{}, err
	}
	return l.insertNotificationTarget(ctx, row)
}

func (l *Library) insertNotificationTarget(ctx context.Context, row wdb.NotificationTarget) (NotificationTarget, error) {
	if err := l.db.InsertNotificationTarget(ctx, row); err != nil {
		switch {
		case errors.Is(err, wdb.ErrConflict):
			return NotificationTarget{}, &Error{Kind: KindConflict, Msg: "notification target limit reached for this kind; remove one first"}
		case errors.Is(err, wdb.ErrExists):
			return NotificationTarget{}, &Error{Kind: KindConflict, Msg: "a target for this endpoint already exists"}
		}
		return NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.notificationTargetDTO(row), nil
}

// UpdateServerNotificationTarget replaces a server-scope target's
// label, config, and enabled events.
func (l *Library) UpdateServerNotificationTarget(ctx context.Context, apiPID string, in NotificationTargetInput) (NotificationTarget, error) {
	row, err := l.notificationTargetRow(ctx, apiPID)
	if err != nil {
		return NotificationTarget{}, err
	}
	if row.Scope != NotifyScopeServer {
		return NotificationTarget{}, errNotFound("no notification target " + apiPID)
	}
	return l.updateNotificationTarget(ctx, row, in, false)
}

// UpdateMyNotificationTarget replaces one of the caller's targets.
func (l *Library) UpdateMyNotificationTarget(ctx context.Context, uc *UserCtx, apiPID string, in NotificationTargetInput) (NotificationTarget, error) {
	row, err := l.notificationTargetRow(ctx, apiPID)
	if err != nil {
		return NotificationTarget{}, err
	}
	if row.Scope != NotifyScopeUser || row.UserID != uc.ID {
		return NotificationTarget{}, errNotFound("no notification target " + apiPID)
	}
	return l.updateNotificationTarget(ctx, row, in, uc.Admin)
}

func (l *Library) updateNotificationTarget(ctx context.Context, row wdb.NotificationTarget, in NotificationTargetInput, ownerIsAdmin bool) (NotificationTarget, error) {
	// The kind is fixed at creation; the input's kind rides along only
	// on create, so rebuild against the stored one.
	in.Kind = row.Kind
	built, err := l.buildNotificationTarget(in, row.Scope, row.UserID, ownerIsAdmin)
	if err != nil {
		return NotificationTarget{}, err
	}
	row.Label = built.Label
	row.SealedConfig = built.SealedConfig
	row.EnabledEvents = built.EnabledEvents
	row.DedupeKey = built.DedupeKey
	if err := l.db.UpdateNotificationTarget(ctx, row); err != nil {
		switch {
		case errors.Is(err, wdb.ErrExists):
			return NotificationTarget{}, &Error{Kind: KindConflict, Msg: "a target for this endpoint already exists"}
		case errors.Is(err, wdb.ErrNotFound):
			return NotificationTarget{}, errNotFound("no notification target " + PrefixNotifyTarget + "-" + row.ID)
		}
		return NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.notificationTargetDTO(row), nil
}

// DeleteServerNotificationTarget removes a server-scope target.
func (l *Library) DeleteServerNotificationTarget(ctx context.Context, apiPID string) error {
	row, err := l.notificationTargetRow(ctx, apiPID)
	if err != nil {
		return err
	}
	if row.Scope != NotifyScopeServer {
		return errNotFound("no notification target " + apiPID)
	}
	if err := l.db.DeleteServerNotificationTarget(ctx, row.ID); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no notification target " + apiPID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// DeleteMyNotificationTarget removes one of the caller's targets.
func (l *Library) DeleteMyNotificationTarget(ctx context.Context, uc *UserCtx, apiPID string) error {
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok || prefix != PrefixNotifyTarget {
		return errNotFound("no notification target " + apiPID)
	}
	if err := l.db.DeleteUserNotificationTarget(ctx, uc.ID, string(pid)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no notification target " + apiPID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// TestServerNotificationTarget queues one test delivery to a
// server-scope target, bypassing event selection.
func (l *Library) TestServerNotificationTarget(ctx context.Context, apiPID string) error {
	row, err := l.notificationTargetRow(ctx, apiPID)
	if err != nil {
		return err
	}
	if row.Scope != NotifyScopeServer {
		return errNotFound("no notification target " + apiPID)
	}
	return l.enqueueNotifyTest(ctx, row.ID)
}

// TestMyNotificationTarget queues one test delivery to one of the
// caller's targets.
func (l *Library) TestMyNotificationTarget(ctx context.Context, uc *UserCtx, apiPID string) error {
	row, err := l.notificationTargetRow(ctx, apiPID)
	if err != nil {
		return err
	}
	if row.Scope != NotifyScopeUser || row.UserID != uc.ID {
		return errNotFound("no notification target " + apiPID)
	}
	return l.enqueueNotifyTest(ctx, row.ID)
}

func (l *Library) enqueueNotifyTest(ctx context.Context, targetID string) error {
	err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
		TargetID: targetID,
		Event:    "test",
		Title:    "WaxDeck test notification",
		Body:     "Delivery works. This is the per-target test.",
	}, time.Now().UnixNano())
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// notificationTargetRow resolves an API pid to its stored row.
func (l *Library) notificationTargetRow(ctx context.Context, apiPID string) (wdb.NotificationTarget, error) {
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok || prefix != PrefixNotifyTarget {
		return wdb.NotificationTarget{}, errNotFound("no notification target " + apiPID)
	}
	row, err := l.db.NotificationTargetByID(ctx, string(pid))
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return wdb.NotificationTarget{}, errNotFound("no notification target " + apiPID)
		}
		return wdb.NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
	}
	return row, nil
}

// buildNotificationTarget validates and seals one target write. The
// scope rules: server targets take server-scope events; user targets
// take user-scope events, plus server-scope events when the owner is
// an administrator.
func (l *Library) buildNotificationTarget(in NotificationTargetInput, scope, ownerID string, ownerIsAdmin bool) (wdb.NotificationTarget, error) {
	provider, ok := notify.ByKind(in.Kind)
	if !ok {
		return wdb.NotificationTarget{}, errInvalid("unknown notification kind " + in.Kind)
	}
	if len(in.Label) > notifyLabelMax {
		return wdb.NotificationTarget{}, errInvalid("the label is too long")
	}
	if len(in.Config) == 0 {
		in.Config = json.RawMessage("{}")
	}
	normalized, userHost, err := provider.ValidateConfig(in.Config)
	if err != nil {
		return wdb.NotificationTarget{}, errInvalid(err.Error())
	}
	// Write-time courtesy check with the friendly message; the
	// dial-time guard on the delivery client is the boundary.
	if scope == NotifyScopeUser && guardedNotifyKinds[in.Kind] &&
		!l.allowPrivateNotifyHosts && userHost != "" && hostResolvesPrivate(userHost) {
		return wdb.NotificationTarget{}, errInvalid("the destination resolves to a private address; the server does not allow private notification hosts")
	}
	events, err := validateEnabledEvents(in.EnabledEvents, scope, ownerIsAdmin)
	if err != nil {
		return wdb.NotificationTarget{}, err
	}
	if l.sealer == nil {
		return wdb.NotificationTarget{}, &Error{Kind: KindInternal, Msg: "no sealing key is configured"}
	}
	sealed, err := l.sealer.Seal(normalized)
	if err != nil {
		return wdb.NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
	}
	dedupe := ""
	if in.Kind == notify.KindUnifiedPush {
		endpoint, err := notify.UnifiedPushEndpoint(normalized)
		if err != nil {
			return wdb.NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
		}
		dedupe = endpoint
	}
	eventsJSON, err := json.Marshal(events)
	if err != nil {
		return wdb.NotificationTarget{}, &Error{Kind: KindInternal, Err: err}
	}
	return wdb.NotificationTarget{
		ID:            ulid.Make().String(),
		Kind:          in.Kind,
		Scope:         scope,
		UserID:        ownerID,
		Label:         in.Label,
		SealedConfig:  sealed,
		EnabledEvents: string(eventsJSON),
		DedupeKey:     dedupe,
		CreatedAtNS:   time.Now().UnixNano(),
	}, nil
}

// validateEnabledEvents checks names against the catalog and the scope
// rules, deduplicating while preserving order.
func validateEnabledEvents(names []string, scope string, ownerIsAdmin bool) ([]string, error) {
	out := make([]string, 0, len(names))
	seen := map[string]bool{}
	for _, name := range names {
		if seen[name] {
			continue
		}
		seen[name] = true
		ev, ok := notifyEventByName(name)
		if !ok {
			return nil, errInvalid("unknown notification event " + name)
		}
		switch {
		case scope == NotifyScopeServer && ev.Scope != NotifyScopeServer:
			return nil, errInvalid(name + " is a user event; server-scope targets take server events only")
		case scope == NotifyScopeUser && ev.Scope == NotifyScopeServer && !ownerIsAdmin:
			return nil, errInvalid(name + " is a server event; only administrators may subscribe personal targets to it")
		}
		out = append(out, name)
	}
	return out, nil
}

func (l *Library) notificationTargetDTOs(rows []wdb.NotificationTarget) []NotificationTarget {
	out := make([]NotificationTarget, 0, len(rows))
	for _, r := range rows {
		out = append(out, l.notificationTargetDTO(r))
	}
	return out
}

// notificationTargetDTO opens the sealed config for the owner-facing
// shape. A config this server's key cannot open (a cross-host restore)
// renders as an empty document: the secret is genuinely lost, and
// saving the target again re-enters it.
func (l *Library) notificationTargetDTO(r wdb.NotificationTarget) NotificationTarget {
	config := json.RawMessage("{}")
	if l.sealer != nil {
		if pt, err := l.sealer.Open(r.SealedConfig); err == nil {
			config = json.RawMessage(pt)
		} else {
			l.log.Warn("notification target config cannot be opened with this key", "target", r.ID)
		}
	}
	var events []string
	if err := json.Unmarshal([]byte(r.EnabledEvents), &events); err != nil || events == nil {
		events = []string{}
	}
	out := NotificationTarget{
		PID:           PrefixNotifyTarget + "-" + r.ID,
		Kind:          r.Kind,
		Scope:         r.Scope,
		Label:         r.Label,
		Config:        config,
		EnabledEvents: events,
		LastError:     r.LastError,
		CreatedAt:     time.Unix(0, r.CreatedAtNS).UTC(),
	}
	if r.LastSuccessNS > 0 {
		out.LastSuccessAt = time.Unix(0, r.LastSuccessNS).UTC()
	}
	if r.LastErrorNS > 0 {
		out.LastErrorAt = time.Unix(0, r.LastErrorNS).UTC()
	}
	return out
}

// --- emit paths -------------------------------------------------------------------

// EmitNotification queues one user-scope event to the named users'
// targets, filtered per target by its enabled events. Failures log;
// emitting a notification never fails its caller.
func (l *Library) EmitNotification(ctx context.Context, event, title, body string, userIDs []string) {
	ev, ok := notifyEventByName(event)
	if !ok || ev.Scope != NotifyScopeUser {
		l.log.Warn("emit of unknown or non-user notification event", "event", event)
		return
	}
	now := time.Now().UnixNano()
	seen := map[string]bool{}
	for _, uid := range userIDs {
		if uid == "" || seen[uid] {
			continue
		}
		seen[uid] = true
		targets, err := l.db.UserNotificationTargets(ctx, uid)
		if err != nil {
			l.log.Warn("reading notification targets", "user", uid, "err", err)
			continue
		}
		l.enqueueToEnabled(ctx, targets, event, title, body, now)
	}
}

// EmitServerNotification queues one server-scope event to the server
// targets plus admin-owned personal targets that opted in. The admin
// set is re-read at emit time, so a demoted administrator's targets
// deliver nothing.
func (l *Library) EmitServerNotification(ctx context.Context, event, title, body string) {
	ev, ok := notifyEventByName(event)
	if !ok || ev.Scope != NotifyScopeServer {
		l.log.Warn("emit of unknown or non-server notification event", "event", event)
		return
	}
	now := time.Now().UnixNano()
	if targets, err := l.db.ServerNotificationTargets(ctx); err != nil {
		l.log.Warn("reading server notification targets", "err", err)
	} else {
		l.enqueueToEnabled(ctx, targets, event, title, body, now)
	}
	admins, err := l.db.EnabledAdminIDs(ctx)
	if err != nil {
		l.log.Warn("listing admins for server notification", "err", err)
		return
	}
	for _, uid := range admins {
		targets, err := l.db.UserNotificationTargets(ctx, uid)
		if err != nil {
			l.log.Warn("reading notification targets", "user", uid, "err", err)
			continue
		}
		l.enqueueToEnabled(ctx, targets, event, title, body, now)
	}
}

func (l *Library) enqueueToEnabled(ctx context.Context, targets []wdb.NotificationTarget, event, title, body string, now int64) {
	for _, t := range targets {
		if !targetWantsEvent(t, event) {
			continue
		}
		if err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
			TargetID: t.ID, Event: event, Title: title, Body: body,
		}, now); err != nil {
			l.log.Warn("queuing notification", "event", event, "target", t.ID, "err", err)
		}
	}
}

func targetWantsEvent(t wdb.NotificationTarget, event string) bool {
	var events []string
	if err := json.Unmarshal([]byte(t.EnabledEvents), &events); err != nil {
		return false
	}
	for _, e := range events {
		if e == event {
			return true
		}
	}
	return false
}

// --- delivery ---------------------------------------------------------------------

// DrainNotifyOutbox delivers one queued notification; false when idle.
func (l *Library) DrainNotifyOutbox(ctx context.Context) bool {
	now := time.Now().UnixNano()
	row, err := l.db.LeaseNotify(ctx, now, int64(notifyLeaseSeconds)*int64(time.Second), notifyMaxAttempts)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing notification", "err", err)
		}
		return false
	}
	target, err := l.db.NotificationTargetByID(ctx, row.TargetID)
	if errors.Is(err, wdb.ErrNotFound) {
		// The target vanished since queuing; nothing to deliver to.
		if err := l.db.CompleteNotify(ctx, row.ID); err != nil {
			l.log.Warn("completing orphaned notification", "err", err)
		}
		return true
	}
	if err != nil {
		l.log.Warn("reading notification target", "err", err)
		return true
	}
	deliveryErr := l.deliverNotify(ctx, target, row)
	l.markNotifyHealth(ctx, target.ID, deliveryErr)
	switch {
	case deliveryErr == nil:
		if err := l.db.CompleteNotify(ctx, row.ID); err != nil {
			l.log.Warn("completing notification", "err", err)
		}
	case notify.IsPermanent(deliveryErr):
		// The destination said no; the same submission cannot succeed.
		l.log.Warn("notification rejected permanently", "target", target.ID, "kind", target.Kind, "err", deliveryErr)
		if err := l.db.DropNotify(ctx, row.ID); err != nil {
			l.log.Warn("dropping rejected notification", "err", err)
		}
	default:
		retryAt := time.Now().Add(queueRetryDelayCapped(row.Attempts, notifyBackoffCap)).UnixNano()
		if err := l.db.FailNotify(ctx, row.ID, deliveryErr.Error(), retryAt); err != nil {
			l.log.Warn("failing notification", "err", err)
		}
	}
	return true
}

// deliverNotify opens the target's config and hands the message to its
// provider. The config is read at delivery time, so edits between
// enqueue and drain win.
func (l *Library) deliverNotify(ctx context.Context, target wdb.NotificationTarget, row wdb.NotifyRow) error {
	provider, ok := notify.ByKind(target.Kind)
	if !ok {
		return &notify.Permanent{Err: errors.New("unknown notification kind " + target.Kind)}
	}
	if l.sealer == nil {
		return &notify.Permanent{Err: errors.New("no sealing key is configured")}
	}
	config, err := l.sealer.Open(target.SealedConfig)
	if err != nil {
		return &notify.Permanent{Err: errors.New("sealed configuration cannot be opened with this server's key")}
	}
	callCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	return provider.Deliver(callCtx, l.notifyClientFor(target), config, notify.Message{
		Event:     row.Event,
		Title:     row.Title,
		Body:      row.Body,
		Timestamp: time.Now(),
	})
}

// markNotifyHealth records a delivery outcome on the target so the
// settings surface can show why notifications are not arriving.
func (l *Library) markNotifyHealth(ctx context.Context, targetID string, deliveryErr error) {
	msg := ""
	if deliveryErr != nil {
		msg = clipHealthMessage(deliveryErr.Error())
	}
	if err := l.db.MarkNotifyTargetDelivery(ctx, targetID, deliveryErr == nil, msg, time.Now().UnixNano()); err != nil {
		l.log.Warn("marking notification delivery", "err", err)
	}
}

// clipHealthMessage bounds a delivery error for the health columns
// without splitting a multi-byte rune at the cut (a bare byte slice
// would store invalid UTF-8 that renders as a replacement character
// in the settings surface).
func clipHealthMessage(msg string) string {
	const max = 300
	if len(msg) <= max {
		return msg
	}
	msg = msg[:max]
	for i := 0; i < utf8.UTFMax-1 && len(msg) > 0; i++ {
		if r, size := utf8.DecodeLastRuneInString(msg); r != utf8.RuneError || size > 1 {
			break
		}
		msg = msg[:len(msg)-1]
	}
	return msg
}

// PruneNotifyOutbox drops stale or exhausted rows.
func (l *Library) PruneNotifyOutbox(ctx context.Context) {
	cutoff := time.Now().Add(-notifyHorizon).UnixNano()
	if n, err := l.db.PruneNotifyOutbox(ctx, cutoff, notifyMaxAttempts); err != nil {
		l.log.Warn("pruning notify outbox", "err", err)
	} else if n > 0 {
		l.log.Info("pruned notify outbox", "rows", n)
	}
}

// --- push-registration compatibility ----------------------------------------------

// PushRegistrations lists the caller's UnifiedPush registrations: the
// unifiedpush rows of the caller's targets, in the legacy shape.
func (l *Library) PushRegistrations(ctx context.Context, uc *UserCtx) ([]PushRegistration, error) {
	rows, err := l.db.UserNotificationTargets(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]PushRegistration, 0, len(rows))
	for _, r := range rows {
		if r.Kind != notify.KindUnifiedPush {
			continue
		}
		out = append(out, PushRegistration{
			PID:       PrefixNotifyTarget + "-" + r.ID,
			Endpoint:  r.DedupeKey,
			Label:     r.Label,
			CreatedAt: time.Unix(0, r.CreatedAtNS).UTC(),
		})
	}
	return out, nil
}

// RegisterPushEndpoint stores a UnifiedPush endpoint for the caller as
// a unifiedpush target. A genuinely new endpoint starts enabled for
// every user-scope event (matching what unconditional push delivered
// before targets existed); a routine re-register refreshes endpoint
// and label only, preserving the event selection made in the targets
// surface.
func (l *Library) RegisterPushEndpoint(ctx context.Context, uc *UserCtx, endpoint, label string) (PushRegistration, bool, error) {
	raw, err := json.Marshal(map[string]string{"endpoint": endpoint})
	if err != nil {
		return PushRegistration{}, false, &Error{Kind: KindInternal, Err: err}
	}
	row, err := l.buildNotificationTarget(NotificationTargetInput{
		Kind:          notify.KindUnifiedPush,
		Label:         label,
		Config:        json.RawMessage(raw),
		EnabledEvents: userScopeEventNames(),
	}, NotifyScopeUser, uc.ID, uc.Admin)
	if err != nil {
		return PushRegistration{}, false, err
	}
	stored, created, err := l.db.UpsertUnifiedPushTarget(ctx, row)
	if err != nil {
		switch {
		case errors.Is(err, wdb.ErrConflict):
			return PushRegistration{}, false, &Error{Kind: KindConflict, Msg: "push registration limit reached; remove a stale registration first"}
		case errors.Is(err, wdb.ErrExists):
			// The upsert retries its update leg when a concurrent
			// registration wins the insert race, so this is nearly
			// unreachable; answer the honest conflict rather than a
			// 500 if it ever surfaces.
			return PushRegistration{}, false, &Error{Kind: KindConflict, Msg: "a registration for this endpoint already exists"}
		}
		return PushRegistration{}, false, &Error{Kind: KindInternal, Err: err}
	}
	return PushRegistration{
		PID:       PrefixNotifyTarget + "-" + stored.ID,
		Endpoint:  stored.DedupeKey,
		Label:     stored.Label,
		CreatedAt: time.Unix(0, stored.CreatedAtNS).UTC(),
	}, created, nil
}

// DeletePushRegistration removes one of the caller's registrations.
// The legacy surface reaches unifiedpush targets only.
func (l *Library) DeletePushRegistration(ctx context.Context, uc *UserCtx, apiRegPID string) error {
	row, err := l.notificationTargetRow(ctx, apiRegPID)
	if err != nil {
		// Keep the legacy surface's vocabulary.
		var e *Error
		if errors.As(err, &e) && e.Kind == KindNotFound {
			return errNotFound("no push registration " + apiRegPID)
		}
		return err
	}
	if row.Kind != notify.KindUnifiedPush || row.UserID != uc.ID {
		return errNotFound("no push registration " + apiRegPID)
	}
	if err := l.db.DeleteUserNotificationTarget(ctx, uc.ID, row.ID); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no push registration " + apiRegPID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// DeleteAllPushRegistrations removes every UnifiedPush registration
// the caller holds (and only those; other target kinds are not part
// of the legacy surface).
func (l *Library) DeleteAllPushRegistrations(ctx context.Context, uc *UserCtx) error {
	if err := l.db.DeleteUserNotificationTargetsByKind(ctx, uc.ID, notify.KindUnifiedPush); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// dropLegacyNotifySetting removes the retired settings-blob relay
// configuration; best-effort at open, harmless when absent.
func (l *Library) dropLegacyNotifySetting(ctx context.Context) {
	if err := l.db.SettingDelete(ctx, legacyNotifySetting); err != nil {
		l.log.Warn("dropping legacy notification setting", "err", err)
	}
}
