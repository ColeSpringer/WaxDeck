package db

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// The removal cap reads and trims an account's removals by seeking their
// index, never by walking the account's change log, so a remove costs the
// writer the same at the cap as below it.
func TestTheRemovalCapSeeksItsIndex(t *testing.T) {
	d, _ := gpodderFixture(t)
	for name, q := range map[string]string{"span": gpodderRemovalSpan, "trim": gpodderDropRemovals} {
		plan := queryPlan(t, d.r, q, "us-A", "us-A")
		if !strings.Contains(plan, "gpodder_sub_events_removals") || strings.Contains(plan, "SCAN gpodder_sub_events") {
			t.Errorf("%s plan:\n%s\nwant gpodder_sub_events_removals searched, never a scan", name, plan)
		}
	}
}

// The log keeps the removals within the cap of the newest, trimming them
// only once a tenth more have piled up.
func TestTheRemovalCapTrimsPastAMargin(t *testing.T) {
	d, ctx := gpodderFixture(t)
	removals := func() []string {
		t.Helper()
		evs, err := d.GpodderSubEventsSince(ctx, "us-A", 0)
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, ev := range evs {
			out = append(out, ev.ShowPID)
		}
		return out
	}
	for i := range 21 {
		if err := d.AppendGpodderSubEvent(ctx, GpodderSubEvent{UserID: "us-A", ShowPID: fmt.Sprintf("pc-%02d", i),
			FeedURL: "https://feeds.example/x", Action: "remove", TsSec: int64(100 + i)}, 10); err != nil {
			t.Fatal(err)
		}
		switch got := len(removals()); {
		case i < 11 && got != i+1:
			t.Fatalf("after %d removals the log keeps %d, want every one up to the cap and its margin", i+1, got)
		case got > 11:
			t.Fatalf("after %d removals the log keeps %d, want at most 11", i+1, got)
		}
	}
	want := []string{"pc-10", "pc-11", "pc-12", "pc-13", "pc-14", "pc-15", "pc-16", "pc-17", "pc-18", "pc-19", "pc-20"}
	if got := removals(); !slices.Equal(got, want) {
		t.Errorf("removals kept = %v, want the newest %v", got, want)
	}
}

// A subscription keeps the URL the account last subscribed the show by,
// a device what it last sent or was sent, and a device nobody registered
// keeps none. What a device calls a show outlives its hold and the
// subscription, for the removal it is still to be told, and goes with the
// device, or with the last change the log keeps of the show.
func TestWhoCallsAShowWhat(t *testing.T) {
	d, ctx := gpodderFixture(t)
	for _, dev := range []string{"phone", "tablet"} {
		if _, err := d.RegisterGpodderDevice(ctx, GpodderDevice{UserID: "us-A", DeviceID: dev}, 2); err != nil {
			t.Fatal(err)
		}
	}
	attach := func(holder, url string) {
		t.Helper()
		if _, err := d.AttachSubscription(ctx, Subscription{UserID: "us-A", ShowPID: "pc-1"}, holder, url); err != nil {
			t.Fatal(err)
		}
	}
	accountURL := func() string {
		t.Helper()
		urls, err := d.SubscriptionURLs(ctx, "us-A")
		if err != nil {
			t.Fatal(err)
		}
		if len(urls) != 1 {
			return ""
		}
		return urls[0].FeedURL
	}
	deviceURLs := func(dev string) []GpodderDeviceURL {
		t.Helper()
		urls, err := d.GpodderDeviceURLs(ctx, "us-A", dev)
		if err != nil {
			t.Fatal(err)
		}
		return urls
	}
	attach("", "https://feeds.example/a")
	attach("phone", "https://feeds.example/a/")
	attach("ghost", "https://feeds.example/a?x")
	if got := accountURL(); got != "https://feeds.example/a?x" {
		t.Errorf("the account's URL = %q, want the last it subscribed the show by", got)
	}
	if got := deviceURLs("phone"); !slices.Equal(got, []GpodderDeviceURL{{ShowPID: "pc-1", FeedURL: "https://feeds.example/a/"}}) {
		t.Errorf("the phone's URLs = %v, want its own", got)
	}
	if got := deviceURLs("ghost"); len(got) != 0 {
		t.Errorf("an unregistered device's URLs = %v, want none", got)
	}
	if err := d.RememberGpodderDeviceURLs(ctx, "us-A", "tablet", []ShowURL{{"pc-1", "https://feeds.example/a?x"}}); err != nil {
		t.Fatal(err)
	}
	if gone, url, err := d.ReleaseGpodderHold(ctx, "us-A", "pc-1", "phone"); err != nil || gone || url != "" {
		t.Errorf("releasing the phone's hold = %v, %q (%v), want the others keeping the show", gone, url, err)
	}
	if existed, url, err := d.RemoveSubscription(ctx, "us-A", "pc-1"); err != nil || !existed || url != "https://feeds.example/a?x" {
		t.Errorf("the unsubscribe = %v, %q (%v), want the account's URL answered", existed, url, err)
	}
	if got := deviceURLs("phone"); len(got) != 1 {
		t.Errorf("the phone's URLs after the unsubscribe = %v, want its own kept", got)
	}
	if err := d.AppendGpodderSubEvent(ctx, GpodderSubEvent{UserID: "us-A", ShowPID: "pc-1",
		FeedURL: "https://feeds.example/a?x", Action: "remove", TsSec: 100}, 10); err != nil {
		t.Fatal(err)
	}
	if _, err := d.PruneGpodderSubEvents(ctx, 50); err != nil {
		t.Fatal(err)
	}
	if got := deviceURLs("phone"); len(got) != 1 {
		t.Errorf("the phone's URLs while the log has the removal = %v, want them kept", got)
	}
	if _, err := d.RegisterGpodderDevice(ctx, GpodderDevice{UserID: "us-A", DeviceID: "watch", UpdatedAtNS: 9}, 2); err != nil {
		t.Fatal(err)
	}
	if got := deviceURLs("phone"); len(got) != 0 {
		t.Errorf("the URLs of the device removed to make room = %v, want them gone with it", got)
	}
	if _, err := d.PruneGpodderSubEvents(ctx, 200); err != nil {
		t.Fatal(err)
	}
	if got := deviceURLs("tablet"); len(got) != 0 {
		t.Errorf("the tablet's URLs once the log let the removal go = %v, want none", got)
	}
}
