package gpodder

import (
	"encoding/json"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// put uploads one device's full list.
func (e *env) put(device, format, body string) {
	e.t.Helper()
	resp, raw := e.call("PUT", "/subscriptions/alice/"+device+"."+format, body, true)
	mustStatus(e.t, resp, raw, 200)
}

// change posts one device's incremental upload and answers its ack.
func (e *env) change(device string, add, remove []string) uploadAckJSON {
	e.t.Helper()
	body, err := json.Marshal(map[string][]string{"add": append([]string{}, add...), "remove": append([]string{}, remove...)})
	if err != nil {
		e.t.Fatal(err)
	}
	resp, raw := e.call("POST", "/api/2/subscriptions/alice/"+device+".json", string(body), true)
	mustStatus(e.t, resp, raw, 200)
	var ack uploadAckJSON
	if err := json.Unmarshal(raw, &ack); err != nil {
		e.t.Fatalf("ack %s: %v", raw, err)
	}
	return ack
}

// changesSince reads one device's subscription delta.
func (e *env) changesSince(device string, since int64) subDeltaJSON {
	e.t.Helper()
	resp, raw := e.call("GET", "/api/2/subscriptions/alice/"+device+".json?since="+strconv.FormatInt(since, 10), "", true)
	mustStatus(e.t, resp, raw, 200)
	var d subDeltaJSON
	if err := json.Unmarshal(raw, &d); err != nil {
		e.t.Fatalf("delta %s: %v", raw, err)
	}
	return d
}

// subscribeFirstParty follows a feed the way the WaxDeck apps do.
func (e *env) subscribeFirstParty(feed string) string {
	e.t.Helper()
	sub, _, err := e.svc.Subscribe(e.ctx, e.uc, service.SubscribeRequest{URL: feed})
	if err != nil {
		e.t.Fatalf("subscribing %s: %v", feed, err)
	}
	return sub.Show.PID
}

// wantList checks the account's list holds exactly these feeds.
func (e *env) wantList(what string, want ...string) {
	e.t.Helper()
	got := e.subscriptionList()
	slices.Sort(got)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		e.t.Fatalf("%s: list = %v, want %v", what, got, want)
	}
}

// One device's full list is that device's contribution: it adds what it
// names and takes away only what nothing else holds.
func TestFullListUploadIsPerDevice(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	e.subscribeFirstParty(a)
	ack := e.change("phone", []string{b}, nil)

	e.put("desk", "txt", b+"\n")
	e.wantList("after the desk's upload of B", a, b)
	if d := e.changesSince("phone", ack.Timestamp); len(d.Remove) != 0 {
		t.Fatalf("the phone's delta after the desk's upload = %+v, want no remove", d)
	}

	e.put("desk", "json", `[]`)
	e.wantList("after the desk let go of B, which the phone holds", a, b)

	e.put("phone", "json", `[]`)
	e.wantList("after the phone let go of B, which only it held", a)

	d := e.changesSince("phone", 0)
	if !slices.Equal(d.Add, []string{a}) || !slices.Equal(d.Remove, []string{b}) {
		t.Fatalf("delta since zero = %+v, want A added and B removed", d)
	}
}

// A device that has never uploaded, or uploads nothing, removes nothing.
func TestEmptyUploadFromANewDeviceRemovesNothing(t *testing.T) {
	e := newEnv(t)
	a, b, c := e.feedURLOf(1), e.feedURLOf(2), e.feedURLOf(3)
	e.subscribeFirstParty(a)
	e.change("phone", []string{b, c}, nil)
	for _, upload := range []struct{ format, body string }{
		{"json", `[]`}, {"opml", ""}, {"txt", ""},
	} {
		e.put("fresh", upload.format, upload.body)
		e.wantList("after an empty "+upload.format+" upload from a new device", a, b, c)
	}
}

// A remove sent as a change is a deliberate unsubscribe for the whole
// account, and every hold on the show goes with it.
func TestDeltaRemoveIsAccountWide(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	e.subscribeFirstParty(a)
	e.change("phone", []string{a, b}, nil)
	e.change("desk", nil, []string{a})
	e.wantList("after the desk removed A, which the apps and the phone held", b)

	// Every hold went with it: the desk adding A again is its one holder.
	e.change("desk", []string{a}, nil)
	e.put("desk", "json", `[]`)
	e.wantList("after the desk, A's only holder now, let go of it", b)

	// Subscribing again in the apps and a phone list that does not name A
	// leave A where the apps put it.
	e.subscribeFirstParty(a)
	e.put("phone", "json", `[]`)
	e.wantList("after resubscribing in the apps and the phone emptying its list", a)
}

// An unsubscribe in the apps clears every device's hold, so a device that
// adds the show again later is its only holder.
func TestFirstPartyUnsubscribeClearsTheHolds(t *testing.T) {
	e := newEnv(t)
	a := e.feedURLOf(1)
	e.change("phone", []string{a}, nil)
	show := e.subscribeFirstParty(a)
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}
	e.wantList("after the apps unsubscribed")

	e.change("desk", []string{a}, nil)
	e.put("desk", "json", `[]`)
	e.wantList("after the desk, A's only holder, let go of it")
}

// A device's own spelling of a subscribed feed is that subscription: no
// fetch, no add, no remove, and no new URL for the account, which a fetch
// of that spelling never proved; only the device calls the show by it.
func TestPutMatchesByShowNotSpelling(t *testing.T) {
	e := newEnv(t)
	a := e.feedURLOf(1)
	e.change("phone", []string{a}, nil)
	added, _, err := e.svc.GpodderSubChangesSince(e.ctx, e.uc, "", 0)
	if err != nil || len(added) != 1 {
		t.Fatalf("change log after the add = %+v (%v), want one row", added, err)
	}
	// The scheme upper-cased and secure, a trailing slash, a stray space:
	// one feed to the catalog, and a fetch of it would fail.
	spelled := " HTTPS://" + strings.TrimPrefix(a, "http://") + "/ "

	e.put("desk", "txt", spelled+"\n")
	e.put("phone", "txt", spelled+"\n")
	e.wantList("after both devices listed another spelling", a)
	// The log keeps a show's latest change only, so a remove and re-add
	// would also leave one add: the row itself has to be the first one.
	if events, _, err := e.svc.GpodderSubChangesSince(e.ctx, e.uc, "", 0); err != nil || len(events) != 1 ||
		events[0].ID != added[0].ID || events[0].TsSec != added[0].TsSec || events[0].Action != "add" {
		t.Fatalf("change log after the respelled uploads = %+v (%v), want the original add %+v unchanged", events, err, added[0])
	}

	// The export and a device new to the account are told the account's
	// URL, never the unfetched spelling.
	if export, err := e.svc.ExportOPML(e.ctx, e.uc); err != nil || !strings.Contains(string(export), `xmlUrl="`+a+`"`) {
		t.Errorf("the export = %s (%v), want the account's %s", export, err, a)
	}
	resp, raw := e.call("POST", "/api/2/devices/alice/watch.json", `{"caption":"new"}`, true)
	mustStatus(t, resp, raw, 200)
	resp, raw = e.call("GET", "/subscriptions/alice/watch.json", "", true)
	mustStatus(t, resp, raw, 200)
	if want, _ := json.Marshal([]string{a}); strings.TrimSpace(string(raw)) != string(want) {
		t.Errorf("a new device's list = %s, want %s", raw, want)
	}

	// The desk's hold on it is the same show's: letting go leaves the
	// phone's.
	e.put("desk", "json", `[]`)
	e.wantList("after the desk let go of its spelling", a)
}

// A download filtered by a client's own spelling of a feed finds the
// first-party plays of the show it means.
func TestTheEpisodeFilterMatchesByShowNotSpelling(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURLOf(2)
	e.change("phone", []string{feed}, nil)
	_, ep := e.episodePID(feed, "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 30_000, nil); err != nil {
		t.Fatal(err)
	}
	respelled := strings.Replace(feed, "http://", "HTTPS://", 1) + "/"
	page := e.actions("since=0&podcast=" + url.QueryEscape(respelled))
	if len(page.Actions) != 1 || page.Actions[0].Device != "waxdeck" {
		t.Fatalf("actions for %s = %+v, want the play of the show it names", respelled, page.Actions)
	}
}
