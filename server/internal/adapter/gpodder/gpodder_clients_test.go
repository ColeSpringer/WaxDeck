package gpodder

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"strings"
	"testing"
	"time"
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

	// Sign out; the protocol answers 200 and the app forgets the
	// cookie.
	status, b := phone.request("POST", "/api/2/auth/alice/logout.json", "", false)
	if status != http.StatusOK {
		t.Fatalf("logout status = %d: %s", status, b)
	}
}
