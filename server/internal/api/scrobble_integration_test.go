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
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// lbListen is one listen the fake ListenBrainz captured.
type lbListen struct {
	Artist     string
	Title      string
	ListenedAt int64
}

// fakeListenBrainz implements the two endpoints the client speaks:
// token validation and listen submission, with a settable failure
// budget so retry behavior is testable.
type fakeListenBrainz struct {
	ts     *httptest.Server
	tokens map[string]string

	mu       sync.Mutex
	subs     []lbListen
	failNext int
}

func newFakeListenBrainz(t *testing.T, tokens map[string]string) *fakeListenBrainz {
	t.Helper()
	f := &fakeListenBrainz{tokens: tokens}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /1/validate-token", func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Token ")
		w.Header().Set("Content-Type", "application/json")
		if user, ok := f.tokens[token]; ok {
			fmt.Fprintf(w, `{"valid":true,"user_name":%q}`, user)
			return
		}
		fmt.Fprint(w, `{"valid":false}`)
	})
	mux.HandleFunc("POST /1/submit-listens", func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Token ")
		if _, ok := f.tokens[token]; !ok {
			http.Error(w, `{"code":401}`, http.StatusUnauthorized)
			return
		}
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.failNext > 0 {
			f.failNext--
			http.Error(w, `{"code":503}`, http.StatusServiceUnavailable)
			return
		}
		var payload struct {
			ListenType string `json:"listen_type"`
			Payload    []struct {
				ListenedAt    int64 `json:"listened_at"`
				TrackMetadata struct {
					Artist string `json:"artist_name"`
					Track  string `json:"track_name"`
				} `json:"track_metadata"`
			} `json:"payload"`
		}
		body, _ := io.ReadAll(r.Body)
		if err := json.Unmarshal(body, &payload); err != nil {
			http.Error(w, `{"code":400}`, http.StatusBadRequest)
			return
		}
		if payload.ListenType == "single" {
			for _, e := range payload.Payload {
				f.subs = append(f.subs, lbListen{
					Artist:     e.TrackMetadata.Artist,
					Title:      e.TrackMetadata.Track,
					ListenedAt: e.ListenedAt,
				})
			}
		}
		fmt.Fprint(w, `{"status":"ok"}`)
	})
	f.ts = httptest.NewServer(mux)
	t.Cleanup(f.ts.Close)
	return f
}

func (f *fakeListenBrainz) submissions() []lbListen {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]lbListen(nil), f.subs...)
}

func (f *fakeListenBrainz) failOnce() {
	f.mu.Lock()
	f.failNext = 1
	f.mu.Unlock()
}

// scrobblerSlot reads one service's slot from the caller's listing.
func scrobblerSlot(t *testing.T, h *harness, service string) Scrobbler {
	t.Helper()
	list := decode[ScrobblerList](t, get(t, h.ts, "/api/v1/users/me/scrobblers", h.token))
	for _, s := range list.Scrobblers {
		if s.Service == service {
			return s
		}
	}
	t.Fatalf("no %s slot in %+v", service, list.Scrobblers)
	return Scrobbler{}
}

func drainScrobbles(t *testing.T, h *harness) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for h.svc.DrainScrobbleOutbox(context.Background()) {
		if time.Now().After(deadline) {
			t.Fatal("scrobble outbox did not drain")
		}
	}
}

func scrobbleOutboxCount(t *testing.T, h *harness) int {
	t.Helper()
	var n int
	if err := h.store.Reader().QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM scrobble_outbox").Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestListenBrainzScrobbleFlow(t *testing.T) {
	// The fake service lives on the loopback, which the scrobble SSRF
	// guard refuses unless the server opts LAN hosts in.
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateScrobbleHosts = true })
	lb := newFakeListenBrainz(t, map[string]string{"tok-good": "listener"})
	ctx := context.Background()

	// A bad token is refused after validation against the service.
	resp := h.putJSON(t, "/api/v1/users/me/scrobblers/listenbrainz", map[string]any{
		"token": "tok-bad", "apiUrl": lb.ts.URL,
	})
	if resp.StatusCode != 400 {
		t.Fatalf("bad-token connect status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("bad-token connect code = %q", e.Code)
	}

	// An unreachable service is the typed 502, not a token rejection.
	dead := httptest.NewServer(http.NotFoundHandler())
	dead.Close()
	resp = h.putJSON(t, "/api/v1/users/me/scrobblers/listenbrainz", map[string]any{
		"token": "tok-good", "apiUrl": dead.URL,
	})
	if resp.StatusCode != 502 {
		t.Fatalf("unreachable connect status = %d, want 502", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "service-unreachable" {
		t.Fatalf("unreachable connect code = %q", e.Code)
	}

	// The good token connects and the slot reports the username.
	resp = h.putJSON(t, "/api/v1/users/me/scrobblers/listenbrainz", map[string]any{
		"token": "tok-good", "apiUrl": lb.ts.URL,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("connect status = %d", resp.StatusCode)
	}
	sc := decode[Scrobbler](t, resp)
	if !sc.Connected || sc.Username == nil || *sc.Username != "listener" {
		t.Fatalf("connect result = %+v", sc)
	}
	list := decode[ScrobblerList](t, get(t, h.ts, "/api/v1/users/me/scrobblers", h.token))
	byService := map[string]Scrobbler{}
	for _, s := range list.Scrobblers {
		byService[s.Service] = s
	}
	if lbSlot := byService["listenbrainz"]; !lbSlot.Available || !lbSlot.Connected ||
		lbSlot.Username == nil || *lbSlot.Username != "listener" ||
		lbSlot.ApiUrl == nil || *lbSlot.ApiUrl != lb.ts.URL {
		t.Fatalf("listenbrainz slot = %+v", byService["listenbrainz"])
	}
	if lf := byService["lastfm"]; lf.Available || lf.Connected {
		t.Fatalf("lastfm slot = %+v, want unavailable without server credentials", lf)
	}

	// A listen crossing the music played threshold queues a delivery,
	// and the drain hands it to the service exactly once.
	items := h.items(t, "")
	alpha := items.Items[0]
	started := time.Now().UTC().Truncate(time.Second).Add(-time.Minute)
	res := decode[ListenIngestResult](t, h.postJSON(t, "/api/v1/listens", map[string]any{
		"sessions": []map[string]any{{
			"sessionId": "lb-sess-1", "pid": alpha.Pid,
			"startedAt": started.Format(time.RFC3339), "msPlayed": alpha.DurationMs, "finished": true,
		}},
	}))
	if res.Accepted != 1 {
		t.Fatalf("ingest = %+v", res)
	}
	drainScrobbles(t, h)
	subs := lb.submissions()
	if len(subs) != 1 {
		t.Fatalf("submissions = %d, want 1", len(subs))
	}
	if subs[0].Artist != "Fixture Artist" || subs[0].Title != "Alpha Song" || subs[0].ListenedAt != started.Unix() {
		t.Fatalf("submission = %+v, want Fixture Artist / Alpha Song at %d", subs[0], started.Unix())
	}

	// The slot now carries the delivery-health stamp.
	slot := scrobblerSlot(t, h, "listenbrainz")
	if slot.LastSuccessAt == nil || slot.LastError != nil {
		t.Fatalf("slot after delivery = %+v, want a success stamp and no error", slot)
	}

	// A transient failure retries and still delivers exactly once. The
	// backoff is real time, so the lease is cleared by hand between the
	// failed and the successful attempt.
	lb.failOnce()
	bravo := items.Items[1]
	resp = h.postJSON(t, "/api/v1/listens", map[string]any{
		"sessions": []map[string]any{{
			"sessionId": "lb-sess-2", "pid": bravo.Pid,
			"startedAt": started.Format(time.RFC3339), "msPlayed": bravo.DurationMs, "finished": true,
		}},
	})
	resp.Body.Close()
	drainScrobbles(t, h)
	if got := lb.submissions(); len(got) != 1 {
		t.Fatalf("submissions after the failed attempt = %d, want still 1", len(got))
	}
	if n := scrobbleOutboxCount(t, h); n != 1 {
		t.Fatalf("outbox rows after the failed attempt = %d, want the retried row", n)
	}
	slot = scrobblerSlot(t, h, "listenbrainz")
	if slot.LastError == nil || slot.LastErrorAt == nil || slot.LastSuccessAt == nil {
		t.Fatalf("slot after failure = %+v, want the error recorded beside the earlier success", slot)
	}
	if _, err := h.store.Writer().ExecContext(ctx, "UPDATE scrobble_outbox SET lease_until_ns = 0"); err != nil {
		t.Fatal(err)
	}
	drainScrobbles(t, h)
	subs = lb.submissions()
	if len(subs) != 2 || subs[1].Title != "Bravo Song" {
		t.Fatalf("submissions after retry = %+v, want the queued row delivered once", subs)
	}
	// A further drain finds nothing to resubmit.
	drainScrobbles(t, h)
	if got := lb.submissions(); len(got) != 2 {
		t.Fatalf("submissions after idle drain = %d, want 2", len(got))
	}
	if n := scrobbleOutboxCount(t, h); n != 0 {
		t.Fatalf("outbox rows after delivery = %d, want 0", n)
	}
	slot = scrobblerSlot(t, h, "listenbrainz")
	if slot.LastError != nil || slot.LastSuccessAt == nil {
		t.Fatalf("slot after recovery = %+v, want the error cleared", slot)
	}

	// Disconnecting removes the connection and its queued rows.
	charlie := items.Items[2]
	resp = h.postJSON(t, "/api/v1/listens", map[string]any{
		"sessions": []map[string]any{{
			"sessionId": "lb-sess-3", "pid": charlie.Pid,
			"startedAt": started.Format(time.RFC3339), "msPlayed": charlie.DurationMs, "finished": true,
		}},
	})
	resp.Body.Close()
	if n := scrobbleOutboxCount(t, h); n != 1 {
		t.Fatalf("outbox rows before disconnect = %d, want 1", n)
	}
	resp = h.deleteReq(t, "/api/v1/users/me/scrobblers/listenbrainz")
	if resp.StatusCode != 204 {
		t.Fatalf("disconnect status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	if n := scrobbleOutboxCount(t, h); n != 0 {
		t.Fatalf("outbox rows after disconnect = %d, want 0", n)
	}
	list = decode[ScrobblerList](t, get(t, h.ts, "/api/v1/users/me/scrobblers", h.token))
	for _, s := range list.Scrobblers {
		if s.Service == "listenbrainz" && s.Connected {
			t.Fatalf("still connected after disconnect: %+v", s)
		}
	}
	resp = h.deleteReq(t, "/api/v1/users/me/scrobblers/listenbrainz")
	if resp.StatusCode != 404 {
		t.Fatalf("second disconnect status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestLastfmConnectSurface(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.LastfmAPIKey = "key123"
		cfg.LastfmSecret = "sec456"
	})

	// With server credentials the slot reads available.
	list := decode[ScrobblerList](t, get(t, h.ts, "/api/v1/users/me/scrobblers", h.token))
	found := false
	for _, s := range list.Scrobblers {
		if s.Service == "lastfm" {
			found = true
			if !s.Available || s.Connected {
				t.Fatalf("lastfm slot = %+v, want available and not connected", s)
			}
		}
	}
	if !found {
		t.Fatalf("no lastfm slot in %+v", list.Scrobblers)
	}

	// The connect start hands back the authorization URL carrying the
	// server's API key and the stateful callback.
	resp := h.postJSON(t, "/api/v1/users/me/scrobblers/lastfm/connect", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("connect start status = %d", resp.StatusCode)
	}
	start := decode[LastfmConnectStart](t, resp)
	if !strings.HasPrefix(start.AuthUrl, "https://www.last.fm/api/auth/?api_key=key123&cb=") {
		t.Fatalf("authUrl = %q", start.AuthUrl)
	}
	if !strings.Contains(start.AuthUrl, "%2Fapi%2Fv1%2Fscrobble%2Flastfm%2Fcallback%3Fstate%3D") {
		t.Fatalf("authUrl carries no stateful callback: %q", start.AuthUrl)
	}

	// The callback authenticates by state alone; a bogus one is a
	// human-readable 400 page, not a JSON error.
	cbResp, err := http.Get(h.ts.URL + "/api/v1/scrobble/lastfm/callback?state=bogus&token=tok")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(cbResp.Body)
	cbResp.Body.Close()
	if cbResp.StatusCode != 400 {
		t.Fatalf("bogus-state callback status = %d, want 400", cbResp.StatusCode)
	}
	if ct := cbResp.Header.Get("Content-Type"); !strings.Contains(ct, "text/html") {
		t.Fatalf("bogus-state callback content type = %q, want text/html", ct)
	}
	if !strings.Contains(string(body), "Last.fm") {
		t.Fatalf("callback page = %s", body)
	}

	// Disconnecting a never-connected slot is a 404.
	resp = h.deleteReq(t, "/api/v1/users/me/scrobblers/lastfm")
	if resp.StatusCode != 404 {
		t.Fatalf("disconnect status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestSubsonicScrobbleParity(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateScrobbleHosts = true })
	lb := newFakeListenBrainz(t, map[string]string{"tok-good": "listener"})
	resp := h.putJSON(t, "/api/v1/users/me/scrobblers/listenbrainz", map[string]any{
		"token": "tok-good", "apiUrl": lb.ts.URL,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("connect status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	secret := newSubsonicSecret(t, h)

	pid := h.items(t, "?limit=1").Items[0].Pid
	tms := time.Now().Add(-time.Hour).Truncate(time.Second).UnixMilli()

	env := subsonicGet(t, h, "scrobble", secret, fmt.Sprintf("&id=%s&time=%d", pid, tms))
	if env.Status != "ok" {
		t.Fatalf("scrobble envelope = %+v", env)
	}
	st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if !st.Played || st.PlayCount != 1 {
		t.Fatalf("play state after scrobble = %+v, want one play", st)
	}

	// The same timed submission replayed is deduplicated, never a
	// second play.
	env = subsonicGet(t, h, "scrobble", secret, fmt.Sprintf("&id=%s&time=%d", pid, tms))
	if env.Status != "ok" {
		t.Fatalf("replayed scrobble envelope = %+v", env)
	}
	st = decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if st.PlayCount != 1 {
		t.Fatalf("play count after replay = %d, want 1", st.PlayCount)
	}

	// Exactly one outbox row reached the connected service, stamped
	// with the submitted time.
	drainScrobbles(t, h)
	subs := lb.submissions()
	if len(subs) != 1 {
		t.Fatalf("submissions = %d, want 1", len(subs))
	}
	if subs[0].Title != "Alpha Song" || subs[0].ListenedAt != tms/1000 {
		t.Fatalf("submission = %+v, want Alpha Song at %d", subs[0], tms/1000)
	}
}

func TestPushRegistrations(t *testing.T) {
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
	if !strings.HasPrefix(reg.Pid, "pr-") || reg.Label == nil || *reg.Label != "Phone" {
		t.Fatalf("created registration = %+v", reg)
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

	// Delete-all clears the slate.
	resp = h.deleteReq(t, "/api/v1/users/me/push-registrations")
	if resp.StatusCode != 204 {
		t.Fatalf("delete-all status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	list = decode[PushRegistrationList](t, get(t, h.ts, "/api/v1/users/me/push-registrations", h.token))
	if len(list.Registrations) != 0 {
		t.Fatalf("listing after delete-all = %+v", list.Registrations)
	}
}

func TestNotificationConfigAndDelivery(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()

	// The surface is admin-only.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	for _, method := range []string{"GET", "POST"} {
		resp = reqAs(t, h, method, "/api/v1/admin/notifications", sam.Token, nil)
		if resp.StatusCode != 403 {
			t.Fatalf("non-admin %s status = %d, want 403", method, resp.StatusCode)
		}
		resp.Body.Close()
	}
	resp = reqAs(t, h, "PUT", "/api/v1/admin/notifications", sam.Token, map[string]any{
		"appriseUrl": "", "enabledEvents": []string{},
	})
	if resp.StatusCode != 403 {
		t.Fatalf("non-admin PUT status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()

	// A test with nothing configured has nowhere to deliver.
	resp = h.postJSON(t, "/api/v1/admin/notifications", nil)
	if resp.StatusCode != 400 {
		t.Fatalf("unconfigured test status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("unconfigured test code = %q", e.Code)
	}

	// PUT and GET round trip, including targets.
	resp = h.putJSON(t, "/api/v1/admin/notifications", map[string]any{
		"appriseUrl": "https://apprise.example", "targets": "ntfys://host/waxdeck", "enabledEvents": []string{"test"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("config PUT status = %d", resp.StatusCode)
	}
	cfg := decode[NotificationConfig](t, resp)
	if cfg.AppriseUrl != "https://apprise.example" || cfg.Targets == nil || *cfg.Targets != "ntfys://host/waxdeck" {
		t.Fatalf("stored config = %+v", cfg)
	}
	if len(cfg.EnabledEvents) != 1 || cfg.EnabledEvents[0] != "test" {
		t.Fatalf("enabled events = %v", cfg.EnabledEvents)
	}
	knownHasTest := false
	for _, ev := range cfg.KnownEvents {
		if ev == "test" {
			knownHasTest = true
		}
	}
	if !knownHasTest {
		t.Fatalf("known events = %v, want test included", cfg.KnownEvents)
	}
	cfg = decode[NotificationConfig](t, get(t, h.ts, "/api/v1/admin/notifications", h.token))
	if cfg.Targets == nil || *cfg.Targets != "ntfys://host/waxdeck" {
		t.Fatalf("config read back = %+v", cfg)
	}

	// The replace is full: an omitted targets clears it.
	resp = h.putJSON(t, "/api/v1/admin/notifications", map[string]any{
		"appriseUrl": "https://apprise.example", "enabledEvents": []string{"test"},
	})
	if got := decode[NotificationConfig](t, resp); got.Targets != nil {
		t.Fatalf("omitted targets survived the replace: %+v", got)
	}

	// A malformed relay URL is refused.
	resp = h.putJSON(t, "/api/v1/admin/notifications", map[string]any{
		"appriseUrl": "gopher://relay", "enabledEvents": []string{},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("bad relay URL status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// With a live relay configured, the queued test reaches it with
	// title and body intact.
	type delivered struct {
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	var mu sync.Mutex
	var got []delivered
	apprise := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/notify" {
			http.NotFound(w, r)
			return
		}
		var d delivered
		body, _ := io.ReadAll(r.Body)
		if err := json.Unmarshal(body, &d); err != nil {
			http.Error(w, "bad payload", http.StatusBadRequest)
			return
		}
		mu.Lock()
		got = append(got, d)
		mu.Unlock()
	}))
	t.Cleanup(apprise.Close)

	resp = h.putJSON(t, "/api/v1/admin/notifications", map[string]any{
		"appriseUrl": apprise.URL, "enabledEvents": []string{"test"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("relay config status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = h.postJSON(t, "/api/v1/admin/notifications", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("test status = %d, want 202", resp.StatusCode)
	}
	resp.Body.Close()

	deadline := time.Now().Add(30 * time.Second)
	for h.svc.DrainNotifyOutbox(ctx) {
		if time.Now().After(deadline) {
			t.Fatal("notify outbox did not drain")
		}
	}
	mu.Lock()
	defer mu.Unlock()
	if len(got) != 1 {
		t.Fatalf("relay deliveries = %d, want 1", len(got))
	}
	if got[0].Title != "WaxDeck test notification" || got[0].Body == "" {
		t.Fatalf("delivery = %+v", got[0])
	}
}

func TestListenBrainzPrivateHostRefused(t *testing.T) {
	// Without the opt-in flag, a caller-supplied API base on a private
	// address is refused at connect: the delivery client is the same
	// dial-guarded shape every user-pointed fetch rides.
	h := newHarness(t)
	lb := newFakeListenBrainz(t, map[string]string{"tok-good": "listener"})
	resp := h.putJSON(t, "/api/v1/users/me/scrobblers/listenbrainz", map[string]any{
		"token": "tok-good", "apiUrl": lb.ts.URL,
	})
	if resp.StatusCode != 400 {
		t.Fatalf("private-host connect status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" || !strings.Contains(e.Message, "private") {
		t.Fatalf("private-host connect error = %+v", e)
	}
}
