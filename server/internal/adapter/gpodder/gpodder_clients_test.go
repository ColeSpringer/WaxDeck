package gpodder

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The real-client conformance trace: the request sequence AntennaPod
// actually issues when syncing against a gpodder.net-compatible
// server, in its order and shapes. Basic credentials appear only on
// login; everything after rides the sessionid cookie in the jar, the
// way the client's HTTP stack behaves. A regression on any step here
// is a sync failure in the real app, so it fails here.

// antennaPod is one emulated device: a cookie-jarred client bound to
// a device id.
type antennaPod struct {
	t      *testing.T
	e      *env
	client *http.Client
	device string
}

func newAntennaPod(t *testing.T, e *env, device string) *antennaPod {
	t.Helper()
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	return &antennaPod{t: t, e: e, client: &http.Client{Jar: jar}, device: device}
}

// request performs one call the way the app does: cookie-jarred, the
// app's User-Agent, Basic credentials only when asked for.
func (a *antennaPod) request(method, path, body string, basic bool) (int, []byte) {
	a.t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, a.e.ts.URL+path, rd)
	if err != nil {
		a.t.Fatal(err)
	}
	req.Header.Set("User-Agent", "AntennaPod/3.4.0")
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if basic {
		req.SetBasicAuth("alice", a.e.secret)
	}
	resp, err := a.client.Do(req)
	if err != nil {
		a.t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, b
}

func (a *antennaPod) mustJSON(method, path, body string, out any) {
	a.t.Helper()
	status, b := a.request(method, path, body, false)
	if status != http.StatusOK {
		a.t.Fatalf("%s %s status = %d: %s", method, path, status, b)
	}
	if out != nil {
		if err := json.Unmarshal(b, out); err != nil {
			a.t.Fatalf("%s %s: %v (%s)", method, path, err, b)
		}
	}
}

// login is the app's connect step: Basic on the login endpoint, then
// the cookie carries the session.
func (a *antennaPod) login() {
	a.t.Helper()
	status, b := a.request("POST", "/api/2/auth/alice/login.json", "", true)
	if status != http.StatusOK {
		a.t.Fatalf("login status = %d: %s", status, b)
	}
}

// register announces the device, as the app does right after login.
func (a *antennaPod) register() {
	a.t.Helper()
	a.mustJSON("POST", "/api/2/devices/alice/"+a.device+".json",
		`{"caption":"AntennaPod on Test","type":"mobile"}`, nil)
}

func TestGpodderClientAntennaPod(t *testing.T) {
	e := newEnv(t)
	phone := newAntennaPod(t, e, "phone-1")
	phone.login()
	phone.register()

	// The device list shows the registration.
	var devices []deviceJSON
	phone.mustJSON("GET", "/api/2/devices/alice.json", "", &devices)
	found := false
	for _, d := range devices {
		if d.ID == "phone-1" && d.Type == "mobile" {
			found = true
		}
	}
	if !found {
		t.Fatalf("device list = %+v, want phone-1 registered as mobile", devices)
	}

	// First sync: the device asks for everything since zero, gets an
	// empty delta, and uploads its local subscription.
	var delta subDeltaJSON
	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since=0", "", &delta)
	if len(delta.Add) != 0 || len(delta.Remove) != 0 {
		t.Fatalf("first delta = %+v, want empty", delta)
	}
	var ack uploadAckJSON
	phone.mustJSON("POST", "/api/2/subscriptions/alice/phone-1.json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, e.feedURL()), &ack)
	if ack.Timestamp == 0 {
		t.Fatalf("subscription upload ack = %+v", ack)
	}

	// A second device syncing from zero learns the subscription.
	tablet := newAntennaPod(t, e, "tablet-1")
	tablet.login()
	tablet.register()
	tablet.mustJSON("GET", "/api/2/subscriptions/alice/tablet-1.json?since=0", "", &delta)
	if len(delta.Add) != 1 || delta.Add[0] != e.feedURL() {
		t.Fatalf("second-device delta = %+v, want the feed", delta)
	}

	// The phone plays an episode and uploads its actions: a download
	// marker and a timed play with position, in the app's timestamp
	// format (UTC, no zone designator).
	episode := e.feed.URL + "/ep1.mp3"
	stamp := time.Now().UTC().Add(-time.Minute).Format("2006-01-02T15:04:05")
	actions := fmt.Sprintf(`[
		{"podcast":%q,"episode":%q,"device":"phone-1","action":"download","timestamp":%q},
		{"podcast":%q,"episode":%q,"device":"phone-1","action":"play","timestamp":%q,"started":0,"position":120,"total":600}
	]`, e.feedURL(), episode, stamp, e.feedURL(), episode, stamp)
	phone.mustJSON("POST", "/api/2/episodes/alice.json", actions, &ack)

	// The tablet pulls the actions and sees the play position, which
	// is how resume points travel between the app's devices.
	var page actionsPageJSON
	tablet.mustJSON("GET", "/api/2/episodes/alice.json?since=0", "", &page)
	var play *episodeActionJSON
	for i, act := range page.Actions {
		if act.Action == "play" && act.Episode == episode {
			play = &page.Actions[i]
		}
	}
	if play == nil {
		t.Fatalf("actions = %+v, want the play action back", page.Actions)
	}
	if play.Position == nil || *play.Position != 120 {
		t.Fatalf("play action = %+v, want position 120", play)
	}

	// A position the WaxDeck apps move, in an episode whose length the feed
	// gives, reaches the tablet on its next pull.
	phone.mustJSON("POST", "/api/2/subscriptions/alice/phone-1.json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, e.feedURLOf(2)), &ack)
	_, pilot := e.episodePID(e.feedURLOf(2), "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, pilot, 42_000, nil); err != nil {
		t.Fatal(err)
	}
	var next actionsPageJSON
	tablet.mustJSON("GET", "/api/2/episodes/alice.json?since="+strconv.FormatInt(page.Timestamp, 10), "", &next)
	moved := actionsFor(next, e.feed.URL+"/show2.mp3")
	if len(moved) != 1 || moved[0].Device != "waxdeck" || *moved[0].Position != 42 || moved[0].Total == nil || *moved[0].Total != 600 {
		t.Fatalf("the tablet's next pull = %+v, want the apps' position", next.Actions)
	}

	// Sign out; the protocol answers 200 and the app forgets the
	// cookie. The sign-out is the phone's alone: the tablet, signed in
	// with the same app password, keeps syncing on its own cookie.
	status, b := phone.request("POST", "/api/2/auth/alice/logout.json", "", false)
	if status != http.StatusOK {
		t.Fatalf("logout status = %d: %s", status, b)
	}
	tablet.mustJSON("GET", "/api/2/devices/alice.json", "", &devices)

	// Revoking the app password ends the tablet's session at its next
	// call, and the app's recovery - a fresh login with a new app
	// password - works.
	if err := e.svc.RevokeAppPassword(e.ctx, e.uc, e.apID); err != nil {
		t.Fatal(err)
	}
	if status, b := tablet.request("GET", "/api/2/devices/alice.json", "", false); status != http.StatusUnauthorized {
		t.Fatalf("the tablet after the revoke = %d: %s, want 401", status, b)
	}
	fresh, err := e.svc.CreateAppPassword(e.ctx, e.uc, "antennapod again")
	if err != nil {
		t.Fatal(err)
	}
	e.secret = fresh.Secret
	tablet.login()
	tablet.mustJSON("GET", "/api/2/devices/alice.json", "", &devices)
}

// gpodderDesktop is gPodder on a desktop, through mygpoclient: urllib with
// a cookie jar and a Basic handler that sends credentials only to answer a
// challenge, from a password manager that hands them out three times in
// the client's life, and JSON bodies under urllib's default form content
// type. gPodder builds one client per configuration and turns its sync off
// at the first Unauthorized, so a server must let the jar carry the login.
type gpodderDesktop struct {
	t       *testing.T
	e       *env
	device  string
	client  *http.Client
	lookups int
}

func newGpodderDesktop(t *testing.T, e *env, device string) *gpodderDesktop {
	t.Helper()
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	return &gpodderDesktop{t: t, e: e, device: device, client: &http.Client{Jar: jar}}
}

// call sends one request the way urllib does, answering a Basic challenge
// while the password manager still gives out the credentials.
func (g *gpodderDesktop) call(method, path, body string) (int, []byte) {
	g.t.Helper()
	send := func(basic bool) (*http.Response, []byte) {
		var rd io.Reader
		if body != "" {
			rd = strings.NewReader(body)
		}
		req, err := http.NewRequest(method, g.e.ts.URL+path, rd)
		if err != nil {
			g.t.Fatal(err)
		}
		req.Header.Set("User-Agent", "mygpoclient/1.10 (+https://gpodder.org/mygpoclient/)")
		if body != "" {
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		}
		if basic {
			req.SetBasicAuth("alice", g.e.secret)
		}
		resp, err := g.client.Do(req)
		if err != nil {
			g.t.Fatal(err)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return resp, b
	}
	resp, b := send(false)
	if resp.StatusCode == http.StatusUnauthorized && strings.HasPrefix(resp.Header.Get("WWW-Authenticate"), "Basic ") {
		if g.lookups++; g.lookups <= 3 {
			resp, b = send(true)
		}
	}
	return resp.StatusCode, b
}

func (g *gpodderDesktop) mustOK(method, path, body string, out any) []byte {
	g.t.Helper()
	status, b := g.call(method, path, body)
	if status != http.StatusOK {
		g.t.Fatalf("%s %s status = %d: %s", method, path, status, b)
	}
	if out != nil {
		if err := json.Unmarshal(b, out); err != nil {
			g.t.Fatalf("%s %s: %v (%s)", method, path, err, b)
		}
	}
	return b
}

// connect is gPodder's first contact: the account's devices listed, then
// its own registered with its caption and type.
func (g *gpodderDesktop) connect() {
	g.t.Helper()
	var devices []deviceJSON
	g.mustOK("GET", "/api/2/devices/alice.json", "", &devices)
	g.mustOK("POST", "/api/2/devices/alice/"+g.device+".json", `{"caption":"gPodder on laptop","type":"laptop"}`, nil)
}

// pull is mygpoclient's pull_subscriptions.
func (g *gpodderDesktop) pull(since int64) subDeltaJSON {
	g.t.Helper()
	var d subDeltaJSON
	g.mustOK("GET", fmt.Sprintf("/api/2/subscriptions/alice/%s.json?since=%d", g.device, since), "", &d)
	return d
}

// push is mygpoclient's update_subscriptions, whose answer must carry both
// keys it reads.
func (g *gpodderDesktop) push(add, remove []string) uploadAckJSON {
	g.t.Helper()
	body, _ := json.Marshal(map[string][]string{"add": append([]string{}, add...), "remove": append([]string{}, remove...)})
	raw := g.mustOK("POST", "/api/2/subscriptions/alice/"+g.device+".json", string(body), nil)
	var keys map[string]json.RawMessage
	var ack uploadAckJSON
	if json.Unmarshal(raw, &keys) != nil || keys["timestamp"] == nil || keys["update_urls"] == nil || json.Unmarshal(raw, &ack) != nil {
		g.t.Fatalf("update_subscriptions answered %s, want timestamp and update_urls", raw)
	}
	return ack
}

// downloadActions is mygpoclient's download_episode_actions, which refuses
// an answer without its actions and an integer timestamp, or an action
// mygpoclient cannot build or gPodder cannot read; gPodder then keeps its
// since and meets the same action on every sync.
func (g *gpodderDesktop) downloadActions(since int64) actionsPageJSON {
	g.t.Helper()
	raw := g.mustOK("GET", fmt.Sprintf("/api/2/episodes/alice.json?since=%d", since), "", nil)
	var keys struct {
		Actions   []map[string]json.RawMessage `json:"actions"`
		Timestamp json.RawMessage              `json:"timestamp"`
	}
	var ts int64
	if json.Unmarshal(raw, &keys) != nil || keys.Actions == nil || json.Unmarshal(keys.Timestamp, &ts) != nil {
		g.t.Fatalf("download_episode_actions answered %s, want actions and an integer timestamp", raw)
	}
	for _, a := range keys.Actions {
		if why := mygpoclientRefuses(a); why != "" {
			g.t.Fatalf("download_episode_actions answered an action gPodder cannot take (%s): %s", why, a)
		}
	}
	var page actionsPageJSON
	if err := json.Unmarshal(raw, &page); err != nil {
		g.t.Fatal(err)
	}
	return page
}

// mygpoclientRefuses says why an action would stop gPodder desktop's
// episode download: mygpoclient's EpisodeAction refuses a missing podcast,
// episode or action, an action outside the protocol's, a start, position
// or length on an action other than play, and a play with a start or
// length but no position; gPodder's convert_from_api reads the time with
// no check for its absence. "" for an action both take.
func mygpoclientRefuses(a map[string]json.RawMessage) string {
	for _, key := range []string{"podcast", "episode", "action"} {
		if a[key] == nil {
			return "no " + key
		}
	}
	var action string
	if json.Unmarshal(a["action"], &action) != nil || !slices.Contains([]string{"download", "play", "delete", "new", "flattr"}, action) {
		return "the action " + string(a["action"])
	}
	has := func(key string) bool { return a[key] != nil && string(a[key]) != "null" }
	if action != "play" && (has("started") || has("position") || has("total")) {
		return "a start, position or length on " + action
	}
	if action == "play" && !has("position") && (has("started") || has("total")) {
		return "a play's start or length with no position"
	}
	var at string
	if json.Unmarshal(a["timestamp"], &at) != nil {
		return "no time"
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02T15:04:05Z"} {
		if _, err := time.Parse(layout, at); err == nil {
			return ""
		}
	}
	return "the time " + at
}

// uploadActions is mygpoclient's upload_episode_actions, which refuses an
// answer without an integer timestamp; gPodder then drops the timestamp.
func (g *gpodderDesktop) uploadActions(actions string) {
	g.t.Helper()
	raw := g.mustOK("POST", "/api/2/episodes/alice.json", actions, nil)
	var keys map[string]json.RawMessage
	var ts int64
	if json.Unmarshal(raw, &keys) != nil || json.Unmarshal(keys["timestamp"], &ts) != nil {
		g.t.Fatalf("upload_episode_actions answered %s, want an integer timestamp", raw)
	}
}

// replace is gPodder's set_subscriptions, mygpoclient's put_subscriptions:
// the Simple API's JSON list.
func (g *gpodderDesktop) replace(urls ...string) {
	g.t.Helper()
	body, _ := json.Marshal(append([]string{}, urls...))
	g.mustOK("PUT", "/subscriptions/alice/"+g.device+".json", string(body), nil)
}

// The two-device trace: AntennaPod on a phone and gPodder on a laptop sync
// one account, the laptop's replace of its own list leaves the phone's
// feeds where they are, and episode actions travel both ways, gPodder
// keeping its download's timestamp and dropping its upload's.
func TestGpodderClientDesktopBesideAntennaPod(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	phone := newAntennaPod(t, e, "phone-1")
	phone.login()
	phone.register()
	var delta subDeltaJSON
	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since=0", "", &delta)
	var ack uploadAckJSON
	phone.mustJSON("POST", "/api/2/subscriptions/alice/phone-1.json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, a), &ack)

	laptop := newGpodderDesktop(t, e, "laptop")
	laptop.connect()
	if d := laptop.pull(0); !slices.Contains(d.Add, a) {
		t.Fatalf("the laptop's first pull = %+v, want the whole account's", d)
	}
	// Replace list on server: the laptop's own list is only B.
	laptop.replace(b)
	e.wantList("after the laptop replaced its list", a, b)

	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since="+strconv.FormatInt(ack.Timestamp, 10), "", &delta)
	if slices.Contains(delta.Remove, a) || !slices.Contains(delta.Add, b) {
		t.Fatalf("the phone's delta after the laptop's replace = %+v, want B added and A kept", delta)
	}
	if d := laptop.pull(0); !slices.Contains(d.Add, a) || !slices.Contains(d.Add, b) {
		t.Fatalf("the laptop's pull since zero = %+v, want both", d)
	}

	// A remove from the laptop is deliberate and reaches the phone.
	laptopAck := laptop.push(nil, []string{b})
	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since="+strconv.FormatInt(laptopAck.Timestamp, 10), "", &delta)
	if !slices.Contains(delta.Remove, b) {
		t.Fatalf("the phone's delta after the laptop's remove = %+v, want B removed", delta)
	}

	// And an empty replace from the laptop takes nothing of the phone's.
	laptop.replace()
	e.wantList("after the laptop emptied its list", a)

	// Episode actions as gPodder syncs them: a download from the since it
	// kept, then its queue uploaded, a download marker bare and a full play
	// with its numbers, stamped in UTC to the second.
	episode := e.feed.URL + "/ep1.mp3"
	// A third app of the account uploads what gPodder cannot take: an
	// action with no time, a download with a position, a play with a length
	// and no position. gPodder's downloads meet none of them as sent.
	resp, raw := e.call("POST", "/api/2/episodes/alice.json", fmt.Sprintf(`[
		{"podcast":%q,"episode":%q,"action":"download","device":"kasts"},
		{"podcast":%q,"episode":%q,"action":"download","device":"kasts","timestamp":%q,"position":0},
		{"podcast":%q,"episode":%q,"action":"play","device":"kasts","timestamp":%q,"started":0,"total":600}
	]`, a, episode, a, episode, time.Now().UTC().Format("2006-01-02T15:04:05"),
		a, e.feed.URL+"/ep2.mp3", time.Now().UTC().Format("2006-01-02T15:04:05")), true)
	mustStatus(t, resp, raw, http.StatusOK)
	kept := laptop.downloadActions(0).Timestamp
	at := time.Now().UTC().Add(-time.Minute).Format("2006-01-02T15:04:05")
	laptop.uploadActions(fmt.Sprintf(`[
		{"podcast":%q,"episode":%q,"action":"download","device":"laptop","timestamp":%q},
		{"podcast":%q,"episode":%q,"action":"play","device":"laptop","timestamp":%q,"started":0,"position":95,"total":600}
	]`, a, episode, at, a, episode, at))
	var phonePage actionsPageJSON
	phone.mustJSON("GET", "/api/2/episodes/alice.json?since=0", "", &phonePage)
	if plays := actionsFor(phonePage, episode); !slices.ContainsFunc(plays, func(p episodeActionJSON) bool {
		return p.Device == "laptop" && p.Action == "play" && p.Position != nil && *p.Position == 95
	}) {
		t.Fatalf("the phone's download = %+v, want the laptop's play", phonePage.Actions)
	}
	phone.mustJSON("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
		`[{"podcast":%q,"episode":%q,"device":"phone-1","action":"play","timestamp":%q,"started":95,"position":150,"total":600}]`,
		a, episode, time.Now().UTC().Format("2006-01-02T15:04:05")), &ack)
	page := laptop.downloadActions(kept)
	if plays := actionsFor(page, episode); !slices.ContainsFunc(plays, func(p episodeActionJSON) bool {
		return p.Device == "phone-1" && p.Position != nil && *p.Position == 150
	}) {
		t.Fatalf("the laptop's download from the since it kept = %+v, want the phone's play", page.Actions)
	}
}

// AntennaPod with the username typed in another case than the account's.
func TestGpodderClientAntennaPodTypedInAnotherCase(t *testing.T) {
	e := newEnv(t)
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Jar: jar}
	do := func(method, path, body string, basic bool) int {
		t.Helper()
		req, _ := http.NewRequest(method, e.ts.URL+path, strings.NewReader(body))
		req.Header.Set("User-Agent", "AntennaPod/3.4.0")
		if basic {
			req.SetBasicAuth("Alice", e.secret)
		}
		resp, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	for _, step := range []struct {
		method, path, body string
		basic              bool
	}{
		{"POST", "/api/2/auth/Alice/login.json", "", true},
		{"POST", "/api/2/devices/Alice/phone.json", `{"caption":"AntennaPod","type":"mobile"}`, false},
		{"POST", "/api/2/subscriptions/Alice/phone.json", fmt.Sprintf(`{"add":[%q],"remove":[]}`, e.feedURL()), false},
		{"GET", "/api/2/subscriptions/Alice/phone.json?since=0", "", false},
	} {
		if got := do(step.method, step.path, step.body, step.basic); got != http.StatusOK {
			t.Fatalf("%s %s = %d, want 200", step.method, step.path, got)
		}
	}
	e.wantList("after syncing as Alice", e.feedURL())
}

// Both clients compare feed URLs exactly, so each is told a show by the
// URL it holds it under: AntennaPod by the spelling it added, gPodder
// desktop by the one its first pull was told, and neither by the
// spelling another account's subscribe made the catalog's.
func TestGpodderClientsAreToldTheirOwnSpellings(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	e.subscribeFirstParty(a)
	bob := e.listener("bob")
	if _, _, err := e.svc.Subscribe(e.ctx, bob, service.SubscribeRequest{URL: b}); err != nil {
		t.Fatal(err)
	}

	phone := newAntennaPod(t, e, "phone-1")
	phone.login()
	phone.register()
	var first subDeltaJSON
	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since=0", "", &first)
	mine := b + "/"
	var ack uploadAckJSON
	phone.mustJSON("POST", "/api/2/subscriptions/alice/phone-1.json",
		fmt.Sprintf(`{"add":[%q],"remove":[]}`, mine), &ack)
	if len(ack.UpdateURLs) != 0 {
		t.Fatalf("the phone's add of its own spelling was answered %v, want no rewrite", ack.UpdateURLs)
	}

	laptop := newGpodderDesktop(t, e, "laptop")
	laptop.connect()
	if d := laptop.pull(0); !slices.Contains(d.Add, a) || !slices.Contains(d.Add, mine) {
		t.Fatalf("the laptop's first pull = %+v, want A and the account's own spelling of B", d)
	}

	// Another account's subscribe makes the catalog spell B its way, and
	// the account then leaves B in the apps.
	theirs := strings.Replace(b, "http://", "HTTP://", 1)
	if _, _, err := e.svc.Subscribe(e.ctx, bob, service.SubscribeRequest{URL: theirs}); err != nil {
		t.Fatal(err)
	}
	show, _ := e.episodePID(mine, "Show 2 Pilot")
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}

	var delta subDeltaJSON
	phone.mustJSON("GET", "/api/2/subscriptions/alice/phone-1.json?since="+strconv.FormatInt(ack.Timestamp, 10), "", &delta)
	if !slices.Equal(delta.Remove, []string{mine}) {
		t.Errorf("the phone's delta = %+v, want B removed under the spelling it added", delta)
	}
	if delta = laptop.pull(0); !slices.Equal(delta.Add, []string{a}) || !slices.Equal(delta.Remove, []string{mine}) {
		t.Errorf("the laptop's pull since zero = %+v, want A added and B removed under what it was first told", delta)
	}
}
