package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// NotificationConfig is the admin-facing relay configuration.
type NotificationConfig struct {
	AppriseURL    string
	Targets       string
	EnabledEvents []string
	KnownEvents   []string
}

// PushRegistration is one UnifiedPush endpoint in the API shape.
type PushRegistration struct {
	PID       string
	Endpoint  string
	Label     string
	CreatedAt time.Time
}

// knownNotifyEvents is the server's current event catalog.
var knownNotifyEvents = []string{
	"test",
	"episode-downloaded",
	"feed-disabled",
}

// Notification delivery tuning.
const (
	notifySettingKey    = "notifications"
	notifyMaxAttempts   = 10
	notifyLeaseSeconds  = 60
	notifyHorizon       = 24 * time.Hour
	notifyBackoffCap    = 30 * time.Minute
	notifyKindApprise   = "apprise"
	notifyKindPush      = "push"
	pushBodyByteBudget  = 3500
	notifyErrorBodyKeep = 256
)

// notifyHTTP is the delivery client. Deliberately unguarded: the
// Apprise relay is admin configured and self-hosted LAN distributors
// are legitimate UnifiedPush targets; delivery responses are never
// surfaced to any user.
var notifyHTTP = &http.Client{Timeout: 15 * time.Second}

// storedNotifyConfig is the settings row shape.
type storedNotifyConfig struct {
	AppriseURL    string   `json:"appriseUrl"`
	Targets       string   `json:"targets"`
	EnabledEvents []string `json:"enabledEvents"`
}

// NotificationSettings reads the relay configuration.
func (l *Library) NotificationSettings(ctx context.Context) (NotificationConfig, error) {
	st, err := l.readNotifyConfig(ctx)
	if err != nil {
		return NotificationConfig{}, err
	}
	return NotificationConfig{
		AppriseURL:    st.AppriseURL,
		Targets:       st.Targets,
		EnabledEvents: st.EnabledEvents,
		KnownEvents:   knownNotifyEvents,
	}, nil
}

// PutNotificationSettings replaces the relay configuration.
func (l *Library) PutNotificationSettings(ctx context.Context, appriseURL, targets string, enabledEvents []string) (NotificationConfig, error) {
	if appriseURL != "" {
		u, err := url.Parse(appriseURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return NotificationConfig{}, errInvalid("appriseUrl must be http or https")
		}
	}
	if enabledEvents == nil {
		enabledEvents = []string{}
	}
	raw, err := json.Marshal(storedNotifyConfig{
		AppriseURL:    appriseURL,
		Targets:       targets,
		EnabledEvents: enabledEvents,
	})
	if err != nil {
		return NotificationConfig{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, notifySettingKey, string(raw), time.Now().UnixNano()); err != nil {
		return NotificationConfig{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.NotificationSettings(ctx)
}

// TestNotifications queues a test through the relay and every push
// registration.
func (l *Library) TestNotifications(ctx context.Context) error {
	st, err := l.readNotifyConfig(ctx)
	if err != nil {
		return err
	}
	regs, err := l.db.AllPushRegistrations(ctx)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if st.AppriseURL == "" && len(regs) == 0 {
		return errInvalid("nothing to deliver to: configure an Apprise URL or register a push endpoint first")
	}
	now := time.Now().UnixNano()
	title := "WaxDeck test notification"
	body := "Delivery works. This is the admin test."
	if st.AppriseURL != "" {
		if err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
			Kind: notifyKindApprise, Event: "test", Title: title, Body: body,
		}, now); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	}
	for _, r := range regs {
		if err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
			Kind: notifyKindPush, Event: "test", Target: r.Endpoint, Title: title, Body: body,
		}, now); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	}
	return nil
}

// EmitNotification queues one event: through the Apprise relay when the
// event is enabled, and to every push registration of the named users
// (podcast events name the show's subscribers). Failures log; emitting
// a notification never fails its caller.
func (l *Library) EmitNotification(ctx context.Context, event, title, body string, userIDs []string) {
	st, err := l.readNotifyConfig(ctx)
	if err != nil {
		l.log.Warn("reading notification settings", "err", err)
		return
	}
	now := time.Now().UnixNano()
	if st.AppriseURL != "" && notifyEventEnabled(st.EnabledEvents, event) {
		if err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
			Kind: notifyKindApprise, Event: event, Title: title, Body: body,
		}, now); err != nil {
			l.log.Warn("queuing notification", "event", event, "err", err)
		}
	}
	for _, uid := range userIDs {
		regs, err := l.db.PushRegistrationsFor(ctx, uid)
		if err != nil {
			l.log.Warn("reading push registrations", "user", uid, "err", err)
			continue
		}
		for _, r := range regs {
			if err := l.db.EnqueueNotify(ctx, wdb.NotifyRow{
				Kind: notifyKindPush, Event: event, Target: r.Endpoint, Title: title, Body: body,
			}, now); err != nil {
				l.log.Warn("queuing push notification", "event", event, "err", err)
			}
		}
	}
}

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
	if err := l.deliverNotify(ctx, row); err != nil {
		retryAt := time.Now().Add(queueRetryDelayCapped(row.Attempts, notifyBackoffCap)).UnixNano()
		if err := l.db.FailNotify(ctx, row.ID, err.Error(), retryAt); err != nil {
			l.log.Warn("failing notification", "err", err)
		}
		return true
	}
	if err := l.db.CompleteNotify(ctx, row.ID); err != nil {
		l.log.Warn("completing notification", "err", err)
	}
	return true
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

func (l *Library) deliverNotify(ctx context.Context, row wdb.NotifyRow) error {
	callCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	switch row.Kind {
	case notifyKindApprise:
		st, err := l.readNotifyConfig(ctx)
		if err != nil {
			return err
		}
		if st.AppriseURL == "" {
			// Disabled since queuing; drop by treating as delivered.
			return nil
		}
		payload := map[string]any{"title": row.Title, "body": row.Body, "type": "info"}
		if st.Targets != "" {
			payload["urls"] = st.Targets
		}
		raw, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(callCtx, http.MethodPost, appriseNotifyURL(st.AppriseURL), bytes.NewReader(raw))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		return doNotify(req)
	case notifyKindPush:
		body := pushBody(row)
		req, err := http.NewRequestWithContext(callCtx, http.MethodPost, row.Target, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		return doNotify(req)
	}
	return fmt.Errorf("unknown notification kind %s", row.Kind)
}

// doNotify sends and evaluates one delivery. Response bodies are read
// and discarded, never surfaced.
func doNotify(req *http.Request) error {
	resp, err := notifyHTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, io.LimitReader(resp.Body, notifyErrorBodyKeep))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("delivery answered status %d", resp.StatusCode)
	}
	return nil
}

// pushBody renders the UnifiedPush payload within the transport's size
// budget.
func pushBody(row wdb.NotifyRow) []byte {
	body := row.Body
	for {
		raw, err := json.Marshal(map[string]string{
			"event": row.Event,
			"title": row.Title,
			"body":  body,
		})
		if err == nil && len(raw) <= pushBodyByteBudget {
			return raw
		}
		if len(body) < 64 {
			raw, _ := json.Marshal(map[string]string{"event": row.Event, "title": row.Title})
			return raw
		}
		body = body[:len(body)/2]
		// Halving can split a multi-byte rune, which the encoder would
		// deliver as a replacement character; back off to a boundary.
		for i := 0; i < utf8.UTFMax-1 && len(body) > 0 && !utf8.ValidString(body); i++ {
			body = body[:len(body)-1]
		}
	}
}

// appriseNotifyURL derives the notify endpoint from the configured
// base: a bare host gains the stateless /notify path, while a URL that
// already names a notify path (stateful keys included) is used as is.
func appriseNotifyURL(base string) string {
	trimmed := strings.TrimRight(base, "/")
	if u, err := url.Parse(trimmed); err == nil {
		if u.Path == "" || u.Path == "/" {
			return trimmed + "/notify"
		}
	}
	return trimmed
}

func notifyEventEnabled(enabled []string, event string) bool {
	for _, e := range enabled {
		if e == event {
			return true
		}
	}
	return false
}

func (l *Library) readNotifyConfig(ctx context.Context) (storedNotifyConfig, error) {
	raw, err := l.db.SettingGet(ctx, notifySettingKey)
	if errors.Is(err, wdb.ErrNotFound) {
		return storedNotifyConfig{EnabledEvents: []string{}}, nil
	}
	if err != nil {
		return storedNotifyConfig{}, &Error{Kind: KindInternal, Err: err}
	}
	var st storedNotifyConfig
	if err := json.Unmarshal([]byte(raw), &st); err != nil {
		return storedNotifyConfig{}, &Error{Kind: KindInternal, Err: err}
	}
	if st.EnabledEvents == nil {
		st.EnabledEvents = []string{}
	}
	return st, nil
}

// PushRegistrations lists the caller's registrations.
func (l *Library) PushRegistrations(ctx context.Context, uc *UserCtx) ([]PushRegistration, error) {
	rows, err := l.db.PushRegistrationsFor(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]PushRegistration, 0, len(rows))
	for _, r := range rows {
		out = append(out, pushRegistrationDTO(r))
	}
	return out, nil
}

// RegisterPushEndpoint stores a UnifiedPush endpoint for the caller.
func (l *Library) RegisterPushEndpoint(ctx context.Context, uc *UserCtx, endpoint, label string) (PushRegistration, bool, error) {
	u, err := url.Parse(endpoint)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return PushRegistration{}, false, errInvalid("the push endpoint must be an https URL")
	}
	row, created, err := l.db.UpsertPushRegistration(ctx, wdb.PushRegistration{
		ID:          ulid.Make().String(),
		UserID:      uc.ID,
		Endpoint:    endpoint,
		Label:       label,
		CreatedAtNS: time.Now().UnixNano(),
	})
	if err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return PushRegistration{}, false, &Error{Kind: KindConflict, Msg: "push registration limit reached; remove a stale registration first"}
		}
		return PushRegistration{}, false, &Error{Kind: KindInternal, Err: err}
	}
	return pushRegistrationDTO(row), created, nil
}

// DeletePushRegistration removes one of the caller's registrations.
func (l *Library) DeletePushRegistration(ctx context.Context, uc *UserCtx, apiRegPID string) error {
	prefix, pid, ok := parseAPIPID(apiRegPID)
	if !ok || prefix != PrefixPushReg {
		return errNotFound("no push registration " + apiRegPID)
	}
	if err := l.db.DeletePushRegistration(ctx, uc.ID, string(pid)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no push registration " + apiRegPID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// DeleteAllPushRegistrations removes every registration the caller
// holds.
func (l *Library) DeleteAllPushRegistrations(ctx context.Context, uc *UserCtx) error {
	if err := l.db.DeleteAllPushRegistrations(ctx, uc.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

func pushRegistrationDTO(r wdb.PushRegistration) PushRegistration {
	return PushRegistration{
		PID:       PrefixPushReg + "-" + r.ID,
		Endpoint:  r.Endpoint,
		Label:     r.Label,
		CreatedAt: time.Unix(0, r.CreatedAtNS).UTC(),
	}
}
