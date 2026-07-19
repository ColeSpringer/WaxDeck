package gpodder

// Golden-flow tests over a real service instance: a scratch catalog,
// a real user with a minted app password, and a synthesized RSS feed
// served from an httptest server on the loopback.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

const testKey = "0123456789abcdef0123456789abcdef"

// env is one test's world: the adapter served over httptest, the
// backing service, the test user's context, and the feed server.
type env struct {
	t      *testing.T
	ctx    context.Context
	ts     *httptest.Server
	svc    *service.Library
	uc     *service.UserCtx
	secret string // the minted app password
	feed   *httptest.Server
}

func newEnv(t *testing.T) *env {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	dataDir := t.TempDir()
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	sealer, err := auth.NewSealer([]byte(testKey), "waxdeck-app-password-v1")
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := service.Open(ctx, service.Config{
		DataDir: dataDir,
		Roots:   []service.Root{{Name: "lib", Path: t.TempDir()}},
		Sealer:  sealer,
		// The podcast dir lives outside the library root, and the feed
		// fixtures ride httptest on the loopback, so the private-host
		// guard must stand down.
		PodcastDir:            t.TempDir(),
		PodcastRootName:       "podcasts",
		AllowPrivateFeedHosts: true,
		Logger:                log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})

	acct, err := svc.CreateAccount(ctx, service.AccountCreate{
		Username: "alice", Password: "login-password-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	ap, err := svc.CreateAppPassword(ctx, uc, "gpodder test")
	if err != nil {
		t.Fatal(err)
	}

	ts := httptest.NewServer(New(svc, []byte(testKey), log))
	t.Cleanup(ts.Close)

	return &env{
		t: t, ctx: ctx, ts: ts, svc: svc, uc: uc,
		secret: ap.Secret, feed: newFeedServer(t),
	}
}

// newFeedServer serves a minimal well-formed two-episode RSS feed and
// small fake enclosure bytes from one httptest server.
func newFeedServer(t *testing.T) *httptest.Server {
	t.Helper()
	var ts *httptest.Server
	mux := http.NewServeMux()
	audio := []byte("fake-mp3-bytes-for-tests")
	for _, name := range []string{"/ep1.mp3", "/ep2.mp3"} {
		mux.HandleFunc(name, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write(audio)
		})
	}
	mux.HandleFunc("/feed.xml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Show</title>
    <link>http://example.invalid/show</link>
    <description>A synthesized test feed</description>
    <item>
      <title>Episode One</title>
      <guid>test-show-ep-1</guid>
      <enclosure url="%s/ep1.mp3" type="audio/mpeg" length="%d"/>
      <pubDate>Mon, 05 Jan 2026 09:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Episode Two</title>
      <guid>test-show-ep-2</guid>
      <enclosure url="%s/ep2.mp3" type="audio/mpeg" length="%d"/>
      <pubDate>Tue, 06 Jan 2026 09:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>`, ts.URL, len(audio), ts.URL, len(audio))
	})
	ts = httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

func (e *env) feedURL() string { return e.feed.URL + "/feed.xml" }

// call sends one request, with Basic app-password auth when basic is
// set, and returns the response and its drained body.
func (e *env) call(method, path, body string, basic bool) (*http.Response, []byte) {
	e.t.Helper()
	req, err := http.NewRequest(method, e.ts.URL+path, strings.NewReader(body))
	if err != nil {
		e.t.Fatal(err)
	}
	if basic {
		req.SetBasicAuth("alice", e.secret)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	raw, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		e.t.Fatal(err)
	}
	return resp, raw
}

// mustStatus fails the test unless the response carries the status.
func mustStatus(t *testing.T, resp *http.Response, raw []byte, want int) {
	t.Helper()
	if resp.StatusCode != want {
		t.Fatalf("%s %s status = %d, want %d (body %s)",
			resp.Request.Method, resp.Request.URL.Path, resp.StatusCode, want, raw)
	}
}

// subscribe adds the fixture feed through the diff endpoint.
func (e *env) subscribe(device string) {
	e.t.Helper()
	resp, raw := e.call("POST", "/api/2/subscriptions/alice/"+device+".json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, e.feedURL()), true)
	mustStatus(e.t, resp, raw, 200)
}

// subscriptionList reads the user's list back in json format.
func (e *env) subscriptionList() []string {
	e.t.Helper()
	resp, raw := e.call("GET", "/subscriptions/alice.json", "", true)
	mustStatus(e.t, resp, raw, 200)
	var urls []string
	if err := json.Unmarshal(raw, &urls); err != nil {
		e.t.Fatalf("subscription list: %v (body %s)", err, raw)
	}
	return urls
}

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}

func TestLoginSession(t *testing.T) {
	e := newEnv(t)

	// Wrong password: 401.
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/2/auth/alice/login.json", nil)
	req.SetBasicAuth("alice", "not-the-app-password")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("wrong-password login status = %d, want 401", resp.StatusCode)
	}

	// No credentials at all: 401.
	resp, raw := e.call("POST", "/api/2/auth/alice/login.json", "", false)
	mustStatus(t, resp, raw, 401)

	// The right app password logs in, answers {} as JSON, and mints
	// the sessionid cookie.
	resp, raw = e.call("POST", "/api/2/auth/alice/login.json", "", true)
	mustStatus(t, resp, raw, 200)
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("login content type = %q", ct)
	}
	if strings.TrimSpace(string(raw)) != "{}" {
		t.Fatalf("login body = %q, want {}", raw)
	}
	var session *http.Cookie
	for _, c := range resp.Cookies() {
		if c.Name == "sessionid" {
			session = c
		}
	}
	if session == nil || session.Value == "" {
		t.Fatal("login set no sessionid cookie")
	}

	withCookie := func(method, path string) *http.Response {
		t.Helper()
		req, _ := http.NewRequest(method, e.ts.URL+path, nil)
		req.AddCookie(session)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		return resp
	}

	// The cookie alone validates against login for the same user.
	if resp := withCookie("POST", "/api/2/auth/alice/login.json"); resp.StatusCode != 200 {
		t.Fatalf("cookie-only login status = %d, want 200", resp.StatusCode)
	}

	// The cookie authenticates every other endpoint.
	if resp := withCookie("GET", "/api/2/devices/alice.json"); resp.StatusCode != 200 {
		t.Fatalf("cookie-only devices status = %d, want 200", resp.StatusCode)
	}

	// Alice's cookie on bob's login path: 400 per the protocol.
	if resp := withCookie("POST", "/api/2/auth/bob/login.json"); resp.StatusCode != 400 {
		t.Fatalf("cross-user cookie login status = %d, want 400", resp.StatusCode)
	}

	// Alice's cookie on bob's data paths: 401 like any bad credential.
	if resp := withCookie("GET", "/api/2/devices/bob.json"); resp.StatusCode != 401 {
		t.Fatalf("cross-user cookie devices status = %d, want 401", resp.StatusCode)
	}

	// A tampered cookie never authenticates.
	forged := *session
	forged.Value = forged.Value[:len(forged.Value)-2] + "xx"
	req, _ = http.NewRequest("GET", e.ts.URL+"/api/2/devices/alice.json", nil)
	req.AddCookie(&forged)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("forged cookie status = %d, want 401", resp.StatusCode)
	}

	// Logout answers 200 for the cookie's own user, 400 for another.
	if resp := withCookie("POST", "/api/2/auth/bob/logout.json"); resp.StatusCode != 400 {
		t.Fatalf("cross-user logout status = %d, want 400", resp.StatusCode)
	}
	if resp := withCookie("POST", "/api/2/auth/alice/logout.json"); resp.StatusCode != 200 {
		t.Fatalf("logout status = %d, want 200", resp.StatusCode)
	}
}

func TestSubscriptionDiffUpload(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()

	resp, raw := e.call("POST", "/api/2/subscriptions/alice/phone.json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, feed), true)
	mustStatus(t, resp, raw, 200)
	var ack struct {
		Timestamp  int64       `json:"timestamp"`
		UpdateURLs [][2]string `json:"update_urls"`
	}
	if err := json.Unmarshal(raw, &ack); err != nil {
		t.Fatalf("upload ack: %v (body %s)", err, raw)
	}
	if ack.Timestamp <= 0 {
		t.Fatalf("upload timestamp = %d, want positive", ack.Timestamp)
	}
	if !strings.Contains(string(raw), "update_urls") || len(ack.UpdateURLs) != 0 {
		t.Fatalf("update_urls = %v (body %s), want present and empty", ack.UpdateURLs, raw)
	}

	// The list surfaces the subscription in every format.
	if urls := e.subscriptionList(); !contains(urls, feed) {
		t.Fatalf("subscription list = %v, want %s", urls, feed)
	}
	resp, raw = e.call("GET", "/subscriptions/alice.txt", "", true)
	mustStatus(t, resp, raw, 200)
	if !strings.Contains(string(raw), feed+"\n") {
		t.Fatalf("txt list = %q, want line %q", raw, feed)
	}
	resp, raw = e.call("GET", "/subscriptions/alice.opml", "", true)
	mustStatus(t, resp, raw, 200)
	if !strings.Contains(string(raw), `xmlUrl=`) || !strings.Contains(string(raw), feed) {
		t.Fatalf("opml list = %q, want an outline for %q", raw, feed)
	}

	// Unknown formats answer 400.
	resp, raw = e.call("GET", "/subscriptions/alice.csv", "", true)
	mustStatus(t, resp, raw, 400)

	// The device-scoped list works for the auto-created device and
	// 404s for one no upload ever named.
	resp, raw = e.call("GET", "/subscriptions/alice/phone.json", "", true)
	mustStatus(t, resp, raw, 200)
	resp, raw = e.call("GET", "/subscriptions/alice/ghost.json", "", true)
	mustStatus(t, resp, raw, 404)

	// The delta download since zero reports the add.
	resp, raw = e.call("GET", "/api/2/subscriptions/alice/phone.json?since=0", "", true)
	mustStatus(t, resp, raw, 200)
	var delta struct {
		Add       []string `json:"add"`
		Remove    []string `json:"remove"`
		Timestamp int64    `json:"timestamp"`
	}
	if err := json.Unmarshal(raw, &delta); err != nil {
		t.Fatal(err)
	}
	if !contains(delta.Add, feed) || len(delta.Remove) != 0 || delta.Timestamp <= 0 {
		t.Fatalf("delta = %+v, want add [%s]", delta, feed)
	}
}

func TestSubscriptionValidation(t *testing.T) {
	e := newEnv(t)

	// The same URL in add and remove rejects the request.
	resp, raw := e.call("POST", "/api/2/subscriptions/alice/phone.json",
		`{"add":["http://example.com/a"],"remove":["http://example.com/a"]}`, true)
	mustStatus(t, resp, raw, 400)

	// A javascript: URL sanitizes to "" in update_urls and is ignored.
	resp, raw = e.call("POST", "/api/2/subscriptions/alice/phone.json",
		`{"add":["javascript:alert(1)"],"remove":[]}`, true)
	mustStatus(t, resp, raw, 200)
	var ack struct {
		UpdateURLs [][2]string `json:"update_urls"`
	}
	if err := json.Unmarshal(raw, &ack); err != nil {
		t.Fatal(err)
	}
	if len(ack.UpdateURLs) != 1 || ack.UpdateURLs[0] != [2]string{"javascript:alert(1)", ""} {
		t.Fatalf("update_urls = %v, want [[javascript:alert(1) ]]", ack.UpdateURLs)
	}
	if urls := e.subscriptionList(); len(urls) != 0 {
		t.Fatalf("sanitized url landed in the list: %v", urls)
	}
}

func TestFullListUpload(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()

	resp, raw := e.call("PUT", "/subscriptions/alice/laptop.json",
		fmt.Sprintf(`[%q]`, feed), true)
	mustStatus(t, resp, raw, 200)
	if urls := e.subscriptionList(); !contains(urls, feed) {
		t.Fatalf("after PUT list = %v, want %s", urls, feed)
	}

	// An empty full list means unsubscribe everything (diff semantics).
	resp, raw = e.call("PUT", "/subscriptions/alice/laptop.json", `[]`, true)
	mustStatus(t, resp, raw, 200)
	if urls := e.subscriptionList(); len(urls) != 0 {
		t.Fatalf("after empty PUT list = %v, want empty", urls)
	}

	// The change log collapses per URL: the latest state since zero is
	// the remove, so the add never resurfaces.
	resp, raw = e.call("GET", "/api/2/subscriptions/alice/laptop.json?since=0", "", true)
	mustStatus(t, resp, raw, 200)
	var delta struct {
		Add    []string `json:"add"`
		Remove []string `json:"remove"`
	}
	if err := json.Unmarshal(raw, &delta); err != nil {
		t.Fatal(err)
	}
	if contains(delta.Add, feed) || !contains(delta.Remove, feed) {
		t.Fatalf("collapsed delta = %+v, want only the remove", delta)
	}
}

func TestEpisodeActions(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	episode := e.feed.URL + "/ep1.mp3"
	e.subscribe("phone")

	// An invalid entry rejects the whole request.
	resp, raw := e.call("POST", "/api/2/episodes/alice.json",
		fmt.Sprintf(`[{"podcast":%q,"episode":%q}]`, feed, episode), true)
	mustStatus(t, resp, raw, 400)

	// One play action, mixed case, with position and total.
	resp, raw = e.call("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
		`[{"podcast":%q,"episode":%q,"action":"Play","device":"phone",`+
			`"timestamp":"2026-01-10T08:00:00","started":0,"position":120,"total":600}]`,
		feed, episode), true)
	mustStatus(t, resp, raw, 200)
	var ack struct {
		Timestamp  int64       `json:"timestamp"`
		UpdateURLs [][2]string `json:"update_urls"`
	}
	if err := json.Unmarshal(raw, &ack); err != nil {
		t.Fatal(err)
	}
	if ack.Timestamp <= 0 || !strings.Contains(string(raw), "update_urls") {
		t.Fatalf("actions ack = %s", raw)
	}

	// The download echoes the stored action.
	type action struct {
		Podcast   string `json:"podcast"`
		Episode   string `json:"episode"`
		Action    string `json:"action"`
		Device    string `json:"device"`
		Timestamp string `json:"timestamp"`
		Started   *int64 `json:"started"`
		Position  *int64 `json:"position"`
		Total     *int64 `json:"total"`
	}
	var page struct {
		Actions   []action `json:"actions"`
		Timestamp int64    `json:"timestamp"`
	}
	resp, raw = e.call("GET", "/api/2/episodes/alice.json?since=0", "", true)
	mustStatus(t, resp, raw, 200)
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Actions) != 1 || page.Timestamp <= 0 {
		t.Fatalf("episodes page = %s", raw)
	}
	got := page.Actions[0]
	if got.Podcast != feed || got.Episode != episode || got.Action != "play" ||
		got.Device != "phone" || got.Timestamp != "2026-01-10T08:00:00" ||
		got.Position == nil || *got.Position != 120 || got.Total == nil || *got.Total != 600 {
		t.Fatalf("echoed action = %+v", got)
	}

	// A second, newer play action on the same episode.
	resp, raw = e.call("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
		`[{"podcast":%q,"episode":%q,"action":"play","device":"phone",`+
			`"timestamp":"2026-01-10T09:00:00","position":240,"total":600}]`,
		feed, episode), true)
	mustStatus(t, resp, raw, 200)

	// Unaggregated returns both; aggregated keeps only the newest.
	resp, raw = e.call("GET", "/api/2/episodes/alice.json?since=0", "", true)
	mustStatus(t, resp, raw, 200)
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Actions) != 2 {
		t.Fatalf("unaggregated actions = %d, want 2", len(page.Actions))
	}
	resp, raw = e.call("GET", "/api/2/episodes/alice.json?since=0&aggregated=true", "", true)
	mustStatus(t, resp, raw, 200)
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Actions) != 1 || page.Actions[0].Position == nil || *page.Actions[0].Position != 240 {
		t.Fatalf("aggregated actions = %s", raw)
	}

	// The play position wrote through to WaxDeck playback state.
	subs, _, err := e.svc.Subscriptions(e.ctx, e.uc, "", 10)
	if err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions = %d (%v), want 1", len(subs), err)
	}
	eps, _, err := e.svc.Episodes(e.ctx, e.uc, subs[0].Show.PID, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var epPID string
	for _, ep := range eps {
		if ep.Title == "Episode One" {
			epPID = ep.PID
		}
	}
	if epPID == "" {
		t.Fatalf("Episode One not cataloged; episodes = %+v", eps)
	}
	st, err := e.svc.PlayState(e.ctx, e.uc, epPID)
	if err != nil {
		t.Fatal(err)
	}
	if st.PositionMS != 240*1000 {
		t.Fatalf("play state position = %d ms, want %d", st.PositionMS, 240*1000)
	}
}

func TestDevices(t *testing.T) {
	e := newEnv(t)

	resp, raw := e.call("POST", "/api/2/devices/alice/phone.json",
		`{"caption":"My Phone","type":"mobile"}`, true)
	mustStatus(t, resp, raw, 200)

	// An off-vocabulary type stores as other.
	resp, raw = e.call("POST", "/api/2/devices/alice/fridge.json",
		`{"caption":"Kitchen","type":"appliance"}`, true)
	mustStatus(t, resp, raw, 200)

	// A caption-only update keeps the stored type.
	resp, raw = e.call("POST", "/api/2/devices/alice/phone.json",
		`{"caption":"Alice's Phone"}`, true)
	mustStatus(t, resp, raw, 200)

	resp, raw = e.call("GET", "/api/2/devices/alice.json", "", true)
	mustStatus(t, resp, raw, 200)
	var devices []struct {
		ID            string `json:"id"`
		Caption       string `json:"caption"`
		Type          string `json:"type"`
		Subscriptions int    `json:"subscriptions"`
	}
	if err := json.Unmarshal(raw, &devices); err != nil {
		t.Fatal(err)
	}
	if len(devices) != 2 {
		t.Fatalf("devices = %s, want 2", raw)
	}
	byID := map[string]int{}
	for i, d := range devices {
		byID[d.ID] = i
	}
	phone := devices[byID["phone"]]
	if phone.Caption != "Alice's Phone" || phone.Type != "mobile" || phone.Subscriptions != 0 {
		t.Fatalf("phone = %+v", phone)
	}
	if fridge := devices[byID["fridge"]]; fridge.Type != "other" {
		t.Fatalf("fridge type = %q, want other", fridge.Type)
	}

	// After a subscription lands, every device reports the user-global
	// count.
	e.subscribe("phone")
	resp, raw = e.call("GET", "/api/2/devices/alice.json", "", true)
	mustStatus(t, resp, raw, 200)
	if err := json.Unmarshal(raw, &devices); err != nil {
		t.Fatal(err)
	}
	for _, d := range devices {
		if d.Subscriptions != 1 {
			t.Fatalf("device %s subscriptions = %d, want 1", d.ID, d.Subscriptions)
		}
	}
}
