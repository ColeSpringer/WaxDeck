package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// notifySink is one JSON webhook receiver counting deliveries.
type notifySink struct {
	mu     sync.Mutex
	status int
	got    []map[string]any
	ts     *httptest.Server
}

func newNotifySink(t *testing.T, status int) *notifySink {
	t.Helper()
	s := &notifySink{status: status}
	s.ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var m map[string]any
		json.Unmarshal(body, &m)
		s.mu.Lock()
		s.got = append(s.got, m)
		s.mu.Unlock()
		w.WriteHeader(s.status)
	}))
	t.Cleanup(s.ts.Close)
	return s
}

func (s *notifySink) deliveries() []map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]map[string]any(nil), s.got...)
}

// notifyHarness is the standard harness with the private-address guard
// relaxed so httptest sinks are reachable as user-pointed targets.
func notifyHarness(t *testing.T) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateNotifyHosts = true
	})
}

func drainNotify(t *testing.T, h *harness) {
	t.Helper()
	ctx := context.Background()
	for i := 0; h.svc.DrainNotifyOutbox(ctx); i++ {
		if i > 100 {
			t.Fatal("notify outbox did not drain")
		}
	}
}

func createTarget(t *testing.T, h *harness, path, token string, body map[string]any) NotificationTarget {
	t.Helper()
	resp := reqAs(t, h, "POST", path, token, body)
	if resp.StatusCode != 201 {
		t.Fatalf("create target status = %d", resp.StatusCode)
	}
	return decode[NotificationTarget](t, resp)
}

func TestNotificationEventCatalog(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// Any signed-in user reads the catalog, not just admins.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	list := decode[NotificationEventList](t, get(t, h.ts, "/api/v1/notifications/events", sam.Token))
	if len(list.Events) == 0 {
		t.Fatal("empty event catalog")
	}
	scopes := map[string]bool{}
	sawUserScope := false
	for _, e := range list.Events {
		if e.Name == "test" {
			t.Fatal("the reserved test event leaked into the catalog")
		}
		if e.Name == "" || e.Description == "" {
			t.Fatalf("catalog entry incomplete: %+v", e)
		}
		if e.Scope != "server" && e.Scope != "user" {
			t.Fatalf("catalog scope = %q", e.Scope)
		}
		// Server scope first: no server entry after the first user one.
		if e.Scope == "user" {
			sawUserScope = true
		} else if sawUserScope {
			t.Fatal("catalog is not server-scope first")
		}
		scopes[string(e.Scope)] = true
	}
	if !scopes["server"] || !scopes["user"] {
		t.Fatalf("catalog scopes = %v, want both", scopes)
	}
	for _, want := range []string{"signup-requested", "backup-completed", "backup-failed", "episode-downloaded", "feed-disabled", "review-ready", "import-completed"} {
		found := false
		for _, e := range list.Events {
			if e.Name == want {
				found = true
			}
		}
		if !found {
			t.Fatalf("catalog is missing %s", want)
		}
	}
}

func TestNotificationTargetCRUDAndIsolation(t *testing.T) {
	t.Parallel()
	h := notifyHarness(t)

	// The admin surface is admin-only.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	for _, probe := range []struct{ method, path string }{
		{"GET", "/api/v1/admin/notification-targets"},
		{"POST", "/api/v1/admin/notification-targets"},
		{"PUT", "/api/v1/admin/notification-targets/nt-01JZX5N8QW3F4V9T2B7KD3M9R6"},
		{"DELETE", "/api/v1/admin/notification-targets/nt-01JZX5N8QW3F4V9T2B7KD3M9R6"},
		{"POST", "/api/v1/admin/notification-targets/nt-01JZX5N8QW3F4V9T2B7KD3M9R6/test"},
	} {
		resp := reqAs(t, h, probe.method, probe.path, sam.Token, map[string]any{
			"kind": "webhook", "config": map[string]any{"url": "https://x.example"}, "enabledEvents": []string{},
		})
		if resp.StatusCode != 403 {
			t.Fatalf("non-admin %s %s = %d, want 403", probe.method, probe.path, resp.StatusCode)
		}
		resp.Body.Close()
	}

	// Create round-trips config verbatim, tokens included.
	created := createTarget(t, h, "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "gotify", "label": "My phone",
		"config":        map[string]any{"serverUrl": "https://gotify.example.net", "token": "app-secret", "priority": 5},
		"enabledEvents": []string{"episode-downloaded"},
	})
	if !strings.HasPrefix(created.Pid, "nt-") || created.Kind != "gotify" || created.Scope != "user" {
		t.Fatalf("created = %+v", created)
	}
	if created.Config["token"] != "app-secret" || created.Config["priority"] != float64(5) {
		t.Fatalf("config round trip = %v", created.Config)
	}
	list := decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", sam.Token))
	if len(list.Targets) != 1 || list.Targets[0].Config["token"] != "app-secret" {
		t.Fatalf("list = %+v", list.Targets)
	}

	// Unknown config fields and unknown events are refused.
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "gotify", "config": map[string]any{"serverUrl": "https://g.example", "token": "t", "prioritty": 1},
		"enabledEvents": []string{},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("unknown config field status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); !strings.Contains(e.Message, "unknown field") {
		t.Fatalf("unknown config field error = %+v", e)
	}
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://x.example"},
		"enabledEvents": []string{"no-such-event"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("unknown event status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// Update replaces label, config, and events; an omitted label
	// clears it.
	resp = reqAs(t, h, "PUT", "/api/v1/users/me/notification-targets/"+created.Pid, sam.Token, map[string]any{
		"config":        map[string]any{"serverUrl": "https://gotify.example.net", "token": "rotated"},
		"enabledEvents": []string{"feed-disabled"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("update status = %d", resp.StatusCode)
	}
	updated := decode[NotificationTarget](t, resp)
	if updated.Label != nil || updated.Config["token"] != "rotated" ||
		len(updated.EnabledEvents) != 1 || updated.EnabledEvents[0] != "feed-disabled" {
		t.Fatalf("updated = %+v", updated)
	}

	// Another user cannot see, edit, test, or delete it.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "kit", "password": testPassword})
	resp.Body.Close()
	kit := loginAs(t, h.ts, "kit", testPassword)
	if l := decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", kit.Token)); len(l.Targets) != 0 {
		t.Fatalf("cross-user list = %+v", l.Targets)
	}
	for _, probe := range []struct{ method, path string }{
		{"PUT", "/api/v1/users/me/notification-targets/" + created.Pid},
		{"DELETE", "/api/v1/users/me/notification-targets/" + created.Pid},
		{"POST", "/api/v1/users/me/notification-targets/" + created.Pid + "/test"},
	} {
		resp := reqAs(t, h, probe.method, probe.path, kit.Token, map[string]any{
			"config": map[string]any{"serverUrl": "https://g.example", "token": "t"}, "enabledEvents": []string{},
		})
		if resp.StatusCode != 404 {
			t.Fatalf("cross-user %s = %d, want 404", probe.method, resp.StatusCode)
		}
		resp.Body.Close()
	}

	// The admin surface cannot reach a personal target either.
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/notification-targets/"+created.Pid, h.token, nil)
	if resp.StatusCode != 404 {
		t.Fatalf("admin delete of personal target = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// Owner delete works and is final.
	resp = reqAs(t, h, "DELETE", "/api/v1/users/me/notification-targets/"+created.Pid, sam.Token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/users/me/notification-targets/"+created.Pid, sam.Token, nil)
	if resp.StatusCode != 404 {
		t.Fatalf("second delete status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// The per-kind cap answers conflict on the 21st target.
	for i := 0; i < 20; i++ {
		resp := reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
			"kind": "webhook", "config": map[string]any{"url": fmt.Sprintf("https://hooks.example.net/%d", i)},
			"enabledEvents": []string{},
		})
		if resp.StatusCode != 201 {
			t.Fatalf("target %d status = %d", i, resp.StatusCode)
		}
		resp.Body.Close()
	}
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://hooks.example.net/over"},
		"enabledEvents": []string{},
	})
	if resp.StatusCode != 409 {
		t.Fatalf("21st target status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" {
		t.Fatalf("21st target code = %q", e.Code)
	}
	// The cap is per kind: a gotify target still fits.
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "gotify", "config": map[string]any{"serverUrl": "https://g.example", "token": "t"},
		"enabledEvents": []string{},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("other-kind target status = %d, want 201", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestNotificationScopeRules(t *testing.T) {
	t.Parallel()
	h := notifyHarness(t)
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	// A non-admin cannot subscribe a personal target to a server event.
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://hooks.example.net/x"},
		"enabledEvents": []string{"signup-requested"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("non-admin server event status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); !strings.Contains(e.Message, "administrators") {
		t.Fatalf("non-admin server event error = %+v", e)
	}

	// An admin can; that is the signup-to-admin-phone flow.
	created := createTarget(t, h, "/api/v1/users/me/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://hooks.example.net/admin"},
		"enabledEvents": []string{"signup-requested", "episode-downloaded"},
	})
	if len(created.EnabledEvents) != 2 {
		t.Fatalf("admin personal target = %+v", created)
	}

	// Server-scope targets refuse user events.
	resp = reqAs(t, h, "POST", "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://hooks.example.net/srv"},
		"enabledEvents": []string{"episode-downloaded"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("server target with user event status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestNotificationDeliveryRouting(t *testing.T) {
	t.Parallel()
	h := notifyHarness(t)
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	samUser := decode[UserAccount](t, resp)
	sam := loginAs(t, h.ts, "sam", testPassword)
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "kit", "password": testPassword})
	kitUser := decode[UserAccount](t, resp)
	kit := loginAs(t, h.ts, "kit", testPassword)

	samSink := newNotifySink(t, 200)
	kitSink := newNotifySink(t, 200)
	serverSink := newNotifySink(t, 200)
	adminSink := newNotifySink(t, 200)

	createTarget(t, h, "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": samSink.ts.URL},
		"enabledEvents": []string{"episode-downloaded"},
	})
	createTarget(t, h, "/api/v1/users/me/notification-targets", kit.Token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": kitSink.ts.URL},
		"enabledEvents": []string{"feed-disabled"},
	})
	createTarget(t, h, "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": serverSink.ts.URL},
		"enabledEvents": []string{"signup-requested"},
	})
	createTarget(t, h, "/api/v1/users/me/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": adminSink.ts.URL},
		"enabledEvents": []string{"signup-requested"},
	})

	// A user event reaches only the named user's targets, and only
	// those enabled for it: kit's target selects feed-disabled, so the
	// same emit to both users delivers once.
	h.svc.EmitNotification(ctx, "episode-downloaded", "New episode: Show", "Ep 1",
		[]string{samUser.Id, kitUser.Id})
	drainNotify(t, h)
	if got := samSink.deliveries(); len(got) != 1 || got[0]["event"] != "episode-downloaded" || got[0]["title"] != "New episode: Show" {
		t.Fatalf("sam deliveries = %v", got)
	}
	if got := kitSink.deliveries(); len(got) != 0 {
		t.Fatalf("kit deliveries = %v, want none (event not selected)", got)
	}

	// A server event reaches server targets and the admin's opted-in
	// personal target, never a non-admin's.
	h.svc.EmitServerNotification(ctx, "signup-requested", "New account request", "pat is waiting.")
	drainNotify(t, h)
	if got := serverSink.deliveries(); len(got) != 1 || got[0]["event"] != "signup-requested" {
		t.Fatalf("server deliveries = %v", got)
	}
	if got := adminSink.deliveries(); len(got) != 1 {
		t.Fatalf("admin personal deliveries = %v", got)
	}
	if got := samSink.deliveries(); len(got) != 1 {
		t.Fatalf("sam deliveries after server emit = %v, want unchanged", got)
	}
}

func TestNotificationUnifiedPushGatingRegression(t *testing.T) {
	t.Parallel()
	// Push delivery used to ignore the enabled-event selection
	// entirely; gating is structural now. A registration narrowed in
	// the targets surface must receive nothing for a deselected event,
	// and the legacy re-register must not widen it back.
	h := notifyHarness(t)
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	samUser := decode[UserAccount](t, resp)
	sam := loginAs(t, h.ts, "sam", testPassword)

	resp = reqAs(t, h, "POST", "/api/v1/users/me/push-registrations", sam.Token, map[string]any{
		"endpoint": "https://push.example.net/ep/1", "label": "Phone",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("register status = %d", resp.StatusCode)
	}
	reg := decode[PushRegistration](t, resp)

	// A fresh registration selects every user event, matching the old
	// unconditional behavior.
	list := decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", sam.Token))
	if len(list.Targets) != 1 || list.Targets[0].Kind != "unifiedpush" {
		t.Fatalf("targets after register = %+v", list.Targets)
	}
	if len(list.Targets[0].EnabledEvents) == 0 {
		t.Fatal("fresh registration has no enabled events")
	}

	// Narrow it, then re-register the same endpoint the way UP clients
	// do at app start: the selection must survive.
	resp = reqAs(t, h, "PUT", "/api/v1/users/me/notification-targets/"+reg.Pid, sam.Token, map[string]any{
		"config":        map[string]any{"endpoint": "https://push.example.net/ep/1"},
		"enabledEvents": []string{"feed-disabled"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("narrow status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "POST", "/api/v1/users/me/push-registrations", sam.Token, map[string]any{
		"endpoint": "https://push.example.net/ep/1", "label": "Phone renamed",
	})
	if resp.StatusCode != 200 {
		t.Fatalf("re-register status = %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()
	list = decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", sam.Token))
	if len(list.Targets) != 1 || len(list.Targets[0].EnabledEvents) != 1 || list.Targets[0].EnabledEvents[0] != "feed-disabled" {
		t.Fatalf("selection after re-register = %+v, want the narrowed set preserved", list.Targets)
	}
	if list.Targets[0].Label == nil || *list.Targets[0].Label != "Phone renamed" {
		t.Fatalf("label after re-register = %+v, want refreshed", list.Targets[0].Label)
	}

	// The deselected event enqueues nothing: the outbox stays empty
	// (nothing dials the unreachable endpoint) and the target's health
	// fields stay untouched.
	h.svc.EmitNotification(ctx, "episode-downloaded", "New episode", "Body", []string{samUser.Id})
	if h.svc.DrainNotifyOutbox(ctx) {
		t.Fatal("a deselected event reached the outbox")
	}
	list = decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", sam.Token))
	if list.Targets[0].LastError != nil || list.Targets[0].LastSuccessAt != nil {
		t.Fatalf("health after deselected emit = %+v, want untouched", list.Targets[0])
	}
}

func TestNotificationTargetTestAndHealth(t *testing.T) {
	t.Parallel()
	h := notifyHarness(t)

	okSink := newNotifySink(t, 200)
	target := createTarget(t, h, "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": okSink.ts.URL},
		"enabledEvents": []string{},
	})
	resp := h.postJSON(t, "/api/v1/admin/notification-targets/"+target.Pid+"/test", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("test status = %d, want 202", resp.StatusCode)
	}
	resp.Body.Close()
	drainNotify(t, h)
	if got := okSink.deliveries(); len(got) != 1 || got[0]["event"] != "test" || got[0]["title"] != "WaxDeck test notification" {
		t.Fatalf("test delivery = %v", got)
	}
	list := decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/admin/notification-targets", h.token))
	if list.Targets[0].LastSuccessAt == nil || list.Targets[0].LastError != nil {
		t.Fatalf("health after success = %+v", list.Targets[0])
	}

	// A permanent rejection surfaces on the health fields and leaves
	// the queue (no retries against a 404).
	badSink := newNotifySink(t, 404)
	bad := createTarget(t, h, "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": badSink.ts.URL},
		"enabledEvents": []string{},
	})
	resp = h.postJSON(t, "/api/v1/admin/notification-targets/"+bad.Pid+"/test", nil)
	resp.Body.Close()
	drainNotify(t, h)
	if got := badSink.deliveries(); len(got) != 1 {
		t.Fatalf("rejected delivery attempts = %d, want exactly 1", len(got))
	}
	list = decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/admin/notification-targets", h.token))
	var badRow *NotificationTarget
	for i := range list.Targets {
		if list.Targets[i].Pid == bad.Pid {
			badRow = &list.Targets[i]
		}
	}
	if badRow == nil || badRow.LastError == nil || !strings.Contains(*badRow.LastError, "404") || badRow.LastErrorAt == nil {
		t.Fatalf("health after rejection = %+v", badRow)
	}

	// A delivery whose target vanished before the drain completes
	// silently: deleting the target cascades its queued rows away.
	goneSink := newNotifySink(t, 200)
	gone := createTarget(t, h, "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": goneSink.ts.URL},
		"enabledEvents": []string{},
	})
	resp = h.postJSON(t, "/api/v1/admin/notification-targets/"+gone.Pid+"/test", nil)
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/notification-targets/"+gone.Pid, h.token, nil)
	resp.Body.Close()
	drainNotify(t, h)
	if got := goneSink.deliveries(); len(got) != 0 {
		t.Fatalf("deleted-target deliveries = %v, want none", got)
	}
}

func TestNotifyPrivateHostRefusedAtWrite(t *testing.T) {
	t.Parallel()
	// The default harness keeps the guard on: user-pointed kinds refuse
	// private hosts at write time with the friendly message, while the
	// deliberately exempt kinds accept them.
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	for _, tc := range []struct {
		kind   string
		config map[string]any
	}{
		{"ntfy", map[string]any{"topic": "waxdeck", "serverUrl": "http://127.0.0.1:9"}},
		{"gotify", map[string]any{"serverUrl": "http://127.0.0.1:9", "token": "t"}},
		{"webhook", map[string]any{"url": "http://127.0.0.1:9/hook"}},
		{"apprise", map[string]any{"serverUrl": "http://127.0.0.1:9"}},
	} {
		resp := reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
			"kind": tc.kind, "config": tc.config, "enabledEvents": []string{},
		})
		if resp.StatusCode != 400 {
			t.Fatalf("%s private host status = %d, want 400", tc.kind, resp.StatusCode)
		}
		if e := decode[Error](t, resp); !strings.Contains(e.Message, "private") {
			t.Fatalf("%s private host error = %+v", tc.kind, e)
		}
	}

	// UnifiedPush is deliberately exempt: LAN distributors are
	// legitimate.
	resp = reqAs(t, h, "POST", "/api/v1/users/me/notification-targets", sam.Token, map[string]any{
		"kind": "unifiedpush", "config": map[string]any{"endpoint": "https://127.0.0.1:9/ep"},
		"enabledEvents": []string{},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("private unifiedpush status = %d, want 201", resp.StatusCode)
	}
	resp.Body.Close()

	// Server-scope targets are administrator-configured and unguarded.
	resp = reqAs(t, h, "POST", "/api/v1/admin/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "http://127.0.0.1:9/hook"},
		"enabledEvents": []string{},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("server-scope private host status = %d, want 201", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestPushRegistrationCompat(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// The endpoint must be https.
	resp := h.postJSON(t, "/api/v1/users/me/push-registrations", map[string]any{
		"endpoint": "http://push.example.net/ep/plain", "label": "Phone",
	})
	if resp.StatusCode != 400 {
		t.Fatalf("http endpoint status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("http endpoint code = %q", e.Code)
	}

	resp = h.postJSON(t, "/api/v1/users/me/push-registrations", map[string]any{
		"endpoint": "https://push.example.net/ep/1", "label": "Phone",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	reg := decode[PushRegistration](t, resp)
	if !strings.HasPrefix(reg.Pid, "nt-") || reg.Label == nil || *reg.Label != "Phone" {
		t.Fatalf("created registration = %+v", reg)
	}
	if reg.Endpoint != "https://push.example.net/ep/1" {
		t.Fatalf("registration endpoint = %q", reg.Endpoint)
	}

	list := decode[PushRegistrationList](t, get(t, h.ts, "/api/v1/users/me/push-registrations", h.token))
	if len(list.Registrations) != 1 || list.Registrations[0].Pid != reg.Pid {
		t.Fatalf("listing = %+v", list.Registrations)
	}

	// Re-registering the same endpoint updates the label in place and
	// answers 200, not 201.
	resp = h.postJSON(t, "/api/v1/users/me/push-registrations", map[string]any{
		"endpoint": "https://push.example.net/ep/1", "label": "Tablet",
	})
	if resp.StatusCode != 200 {
		t.Fatalf("re-register status = %d, want 200", resp.StatusCode)
	}
	again := decode[PushRegistration](t, resp)
	if again.Pid != reg.Pid || again.Label == nil || *again.Label != "Tablet" {
		t.Fatalf("re-registered = %+v, want the original row relabeled", again)
	}

	// The legacy surface reaches unifiedpush targets only: a webhook
	// target is invisible to it and unreachable through it.
	wh := createTarget(t, h, "/api/v1/users/me/notification-targets", h.token, map[string]any{
		"kind": "webhook", "config": map[string]any{"url": "https://hooks.example.net/x"},
		"enabledEvents": []string{},
	})
	list = decode[PushRegistrationList](t, get(t, h.ts, "/api/v1/users/me/push-registrations", h.token))
	if len(list.Registrations) != 1 {
		t.Fatalf("listing with webhook present = %+v", list.Registrations)
	}
	resp = h.deleteReq(t, "/api/v1/users/me/push-registrations/"+wh.Pid)
	if resp.StatusCode != 404 {
		t.Fatalf("legacy delete of webhook target = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.deleteReq(t, "/api/v1/users/me/push-registrations/"+reg.Pid)
	if resp.StatusCode != 204 {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = h.deleteReq(t, "/api/v1/users/me/push-registrations/"+reg.Pid)
	if resp.StatusCode != 404 {
		t.Fatalf("second delete status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// The per-user cap answers conflict on the 21st distinct endpoint.
	for i := 0; i < 20; i++ {
		resp = h.postJSON(t, "/api/v1/users/me/push-registrations", map[string]any{
			"endpoint": fmt.Sprintf("https://push.example.net/cap/%d", i),
		})
		if resp.StatusCode != 201 {
			t.Fatalf("registration %d status = %d", i, resp.StatusCode)
		}
		resp.Body.Close()
	}
	resp = h.postJSON(t, "/api/v1/users/me/push-registrations", map[string]any{
		"endpoint": "https://push.example.net/cap/over",
	})
	if resp.StatusCode != 409 {
		t.Fatalf("21st registration status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" {
		t.Fatalf("21st registration code = %q, want conflict", e.Code)
	}

	// Delete-all clears the UnifiedPush slate and nothing else.
	resp = h.deleteReq(t, "/api/v1/users/me/push-registrations")
	if resp.StatusCode != 204 {
		t.Fatalf("delete-all status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	list = decode[PushRegistrationList](t, get(t, h.ts, "/api/v1/users/me/push-registrations", h.token))
	if len(list.Registrations) != 0 {
		t.Fatalf("listing after delete-all = %+v", list.Registrations)
	}
	targets := decode[NotificationTargetList](t, get(t, h.ts, "/api/v1/users/me/notification-targets", h.token))
	if len(targets.Targets) != 1 || targets.Targets[0].Kind != "webhook" {
		t.Fatalf("targets after delete-all = %+v, want the webhook untouched", targets.Targets)
	}
}
