package gpodder

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A device id runs to 128 bytes and is never this server's own, and a
// caption is cut at 256 bytes without splitting a character.
func TestDeviceBounds(t *testing.T) {
	e := newEnv(t)
	long := strings.Repeat("d", 129)
	resp, raw := e.call("POST", "/api/2/devices/alice/"+long+".json", `{"caption":"x"}`, true)
	mustStatus(t, resp, raw, 400)
	resp, raw = e.call("PUT", "/subscriptions/alice/"+long+".json", `[]`, true)
	mustStatus(t, resp, raw, 400)

	resp, raw = e.call("POST", "/api/2/devices/alice/waxdeck.json", `{}`, true)
	mustStatus(t, resp, raw, 400)

	caption := strings.Repeat("\u00e9", 200) // 400 bytes
	resp, raw = e.call("POST", "/api/2/devices/alice/dev-0.json",
		fmt.Sprintf(`{"caption":%q,"type":"mobile"}`, caption), true)
	mustStatus(t, resp, raw, 200)
	for _, d := range e.devices() {
		if d.ID == "dev-0" && (len(d.Caption) > 256 || !utf8.ValidString(d.Caption) || !strings.HasPrefix(caption, d.Caption)) {
			t.Errorf("long caption stored as %d bytes %q", len(d.Caption), d.Caption)
		}
	}
}

func (e *env) devices() []deviceJSON {
	e.t.Helper()
	resp, raw := e.call("GET", "/api/2/devices/alice.json", "", true)
	mustStatus(e.t, resp, raw, 200)
	var devices []deviceJSON
	if err := json.Unmarshal(raw, &devices); err != nil {
		e.t.Fatal(err)
	}
	return devices
}

func (e *env) hasDevice(id string) bool {
	e.t.Helper()
	for _, d := range e.devices() {
		if d.ID == id {
			return true
		}
	}
	return false
}

// removedDevices is the account's inbox rows for devices let go.
func (e *env) removedDevices() []service.InboxNotification {
	e.t.Helper()
	page, err := e.svc.Notifications(e.ctx, e.uc, "", 100)
	if err != nil {
		e.t.Fatal(err)
	}
	var out []service.InboxNotification
	for _, n := range page.Notifications {
		if n.Event == "gpodder-device-removed" {
			out = append(out, n)
		}
	}
	return out
}

// An account keeps fifty devices and is never locked out at fifty: a new
// one takes the slot of the least recently seen device that holds
// nothing, quietly; when every device holds something, the least recently
// seen goes anyway, what it alone kept stays followed, and the inbox says
// so.
func TestAFullDeviceRegistryMakesRoom(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	e.change("dev-0", []string{b}, nil) // the stalest, and B's only holder
	resp, raw := e.call("POST", "/api/2/devices/alice/dev-1.json", `{}`, true)
	mustStatus(t, resp, raw, 200) // holds nothing
	for i := 2; i < 50; i++ {
		e.change(fmt.Sprintf("dev-%d", i), []string{a}, nil)
	}
	if n := len(e.devices()); n != 50 {
		t.Fatalf("devices = %d, want 50", n)
	}

	resp, raw = e.call("POST", "/api/2/devices/alice/new-1.json", `{"caption":"New phone"}`, true)
	mustStatus(t, resp, raw, 200)
	if e.hasDevice("dev-1") || !e.hasDevice("dev-0") || !e.hasDevice("new-1") || len(e.devices()) != 50 {
		t.Fatalf("devices = %+v, want dev-1, which held nothing, to have made room", e.devices())
	}
	if rows := e.removedDevices(); len(rows) != 0 {
		t.Fatalf("inbox = %+v, want nothing said for a device that held nothing", rows)
	}

	e.change("new-1", []string{a}, nil)
	e.change("new-2", []string{a}, nil)
	if e.hasDevice("dev-0") || !e.hasDevice("new-2") {
		t.Fatalf("devices = %+v, want dev-0, the least recently seen, to have made room", e.devices())
	}
	if rows := e.removedDevices(); len(rows) != 1 || !strings.Contains(rows[0].Body, "dev-0") {
		t.Fatalf("inbox = %+v, want one row naming dev-0", rows)
	}
	// B, which only dev-0 held, is the apps' to keep now.
	e.wantList("after dev-0 made room", a, b)
	e.put("new-2", "json", `[]`)
	e.wantList("after another device emptied its list", a, b)
}

// truncateForReport keeps a failure message readable when a body runs to
// kilobytes, saying how long it was.
func truncateForReport(s string) string {
	if len(s) <= 300 {
		return s
	}
	return fmt.Sprintf("%s... (%d bytes)", s[:300], len(s))
}

// A client that makes room again and again, a new device id each time,
// files a handful of inbox rows a day, not one per device it pushes out;
// a row names the newcomer by the caption the server keeps, never by what
// the request sent.
func TestManyRemovedDevicesFileAHandfulOfRows(t *testing.T) {
	e := newEnv(t)
	a := e.feedURLOf(1)
	for i := range 50 {
		e.change(fmt.Sprintf("dev-%d", i), []string{a}, nil)
	}
	long := strings.Repeat("x", 10_000)
	resp, raw := e.call("POST", "/api/2/devices/alice/new-0.json", `{"caption":"`+long+`"}`, true)
	mustStatus(t, resp, raw, 200)
	if rows := e.removedDevices(); len(rows) != 1 || strings.Contains(rows[0].Body, strings.Repeat("x", 257)) {
		for i := range rows {
			rows[i].Body = truncateForReport(rows[i].Body)
		}
		t.Fatalf("inbox = %+v, want one row naming the newcomer by its kept caption", rows)
	}
	for i := 1; i < 40; i++ {
		e.change(fmt.Sprintf("new-%d", i), []string{a}, nil)
	}
	if rows := e.removedDevices(); len(rows) != 4 {
		t.Fatalf("inbox after 40 devices made room = %d rows, want three by name and one saying more went", len(rows))
	}
	e.wantList("after 40 devices made room", a)
}

// An action's time is checked and spelled the protocol's way. An action
// whose time is not one, or not one an action can have, is skipped and the
// rest of its batch kept: a client sends a batch again until it is
// answered, so refusing it whole would leave that client's sync stuck.
func TestActionTimestampsAreChecked(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	action := func(n int, ts string) string {
		return fmt.Sprintf(`{"podcast":%q,"episode":"%s/%d.mp3","action":"download","timestamp":%q}`, feed, e.feed.URL, n, ts)
	}
	// Before 2000, or a day past now, is no time this server was sent from;
	// a year in the 0500s once wrapped into the 2250s.
	e.upload(
		action(1, "2026-01-10T09:00:00+01:00"),
		action(2, "yesterday at noon"),
		action(3, "0500-06-01T00:00:00"),
		action(4, "1999-12-31T23:59:59"),
		action(5, time.Now().UTC().Add(48*time.Hour).Format("2006-01-02T15:04:05")),
		action(6, "2026-01-10T08:30:00.25"),
	)
	var got []string
	for _, a := range e.actions("since=0").Actions {
		got = append(got, a.Episode+" "+a.Timestamp)
	}
	want := []string{e.feed.URL + "/1.mp3 2026-01-10T08:00:00", e.feed.URL + "/6.mp3 2026-01-10T08:30:00"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("stored = %v, want %v: the two with a time, in UTC, zoneless, whole seconds", got, want)
	}
}

// A body over the limit is too large, which no client can fix by trying
// the same request again, rather than malformed.
func TestOversizedBodiesAreTooLarge(t *testing.T) {
	e := newEnv(t)
	huge := `["` + strings.Repeat("x", 8<<20) + `"]`
	for _, c := range []struct{ method, path string }{
		{"PUT", "/subscriptions/alice/phone.json"},
		{"POST", "/api/2/subscriptions/alice/phone.json"},
		{"POST", "/api/2/episodes/alice.json"},
		{"POST", "/api/2/devices/alice/phone.json"},
	} {
		resp, raw := e.call(c.method, c.path, huge, true)
		if resp.StatusCode != 413 {
			t.Errorf("%s %s = %d (%.80s), want 413", c.method, c.path, resp.StatusCode, raw)
		}
	}
}

// A since past any second this server can stamp is no wrap into the past.
func TestAFarFutureSinceAnswersNothing(t *testing.T) {
	e := newEnv(t)
	e.change("phone", []string{e.feedURLOf(2)}, nil)
	_, ep := e.episodePID(e.feedURLOf(2), "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 30_000, nil); err != nil {
		t.Fatal(err)
	}
	for _, since := range []string{"9223372037", "9223372036854775807"} {
		if page := e.actions("since=" + since); len(page.Actions) != 0 {
			t.Errorf("since=%s answered %+v, want nothing", since, page.Actions)
		}
		if d := e.changesSince("phone", mustAtoi(t, since)); len(d.Add) != 0 || len(d.Remove) != 0 {
			t.Errorf("delta since=%s = %+v, want nothing", since, d)
		}
	}
}

func mustAtoi(t *testing.T, s string) int64 {
	t.Helper()
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

// One stored row carries a bounded number of bytes: a list line longer
// than a URL runs is no feed URL, and an action naming one, or a device
// past its 128 bytes or this server's own, or lacking what an action names,
// is skipped while the rest of its batch is kept, the log saying how many
// in one line.
func TestStoredFieldsAreBounded(t *testing.T) {
	var logged logLines
	e := newEnvWith(t, func(cfg *service.Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelInfo}))
	})
	long := "https://feeds.example/" + strings.Repeat("x", 2048)
	e.put("desk", "txt", long+"\n")
	e.wantList("after a list naming an over-long URL")
	if events, _, err := e.svc.GpodderSubChangesSince(e.ctx, e.uc, "", 0); err != nil || len(events) != 0 {
		t.Fatalf("change log = %+v (%v), want nothing", events, err)
	}
	action := func(podcast, episode, act, device string) string {
		return fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":%q,"device":%q}`, podcast, episode, act, device)
	}
	feed, ep := "https://feeds.example/a.xml", "https://feeds.example/1.mp3"
	e.upload(
		action(long, ep, "download", "phone"),
		action(feed, long, "download", "phone"),
		action(feed, ep, "download", strings.Repeat("d", 129)),
		action(feed, ep, "download", "waxdeck"),
		action("", ep, "download", "phone"),
		action(feed, "", "download", "phone"),
		action(feed, ep, "listen", "phone"),
		action(feed, ep, "download", "phone"),
	)
	if page := e.actions("since=0"); len(page.Actions) != 1 || page.Actions[0].Device != "phone" || page.Actions[0].Podcast != feed {
		t.Fatalf("stored %+v, want only the one valid action", page.Actions)
	}
	var said []string
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, "gpodder episode actions skipped") {
			said = append(said, line)
		}
	}
	if len(said) != 1 || !strings.Contains(said[0], "skipped=7") || !strings.Contains(said[0], "kept=1") {
		t.Errorf("log = %q, want one line counting seven skipped and one kept", said)
	}
}

// A read the catalog cannot serve during a hand-off answers 503, as the
// REST surface does, never an answer a client would take for the truth.
func TestACatalogHandOffIsAnsweredUnavailable(t *testing.T) {
	h := &handler{log: slog.New(slog.DiscardHandler)}
	for _, c := range []struct {
		err  error
		want int
	}{
		{&service.Error{Kind: service.KindMaintenance}, http.StatusServiceUnavailable},
		{&service.Error{Kind: service.KindInternal}, http.StatusInternalServerError},
	} {
		rec := httptest.NewRecorder()
		h.failService(rec, c.err, "listing subscriptions failed")
		if rec.Code != c.want {
			t.Errorf("%v answered %d, want %d", c.err, rec.Code, c.want)
		}
	}
}
