package dlna

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

func testItems(n int) []connect.MediaItem {
	items := make([]connect.MediaItem, n)
	for i := range items {
		items[i] = connect.MediaItem{
			PID:        "tr-item" + string(rune('a'+i)),
			URL:        "http://media.local/" + string(rune('a'+i)) + ".mp3",
			MimeType:   "audio/mpeg",
			Title:      "Track & Co <" + string(rune('A'+i)) + ">",
			Artist:     "Tester",
			DurationMS: 30_000,
		}
	}
	return items
}

// dialDriver dials the fake renderer and shortens the poll so tests
// observe advances in milliseconds.
func dialDriver(t *testing.T, r *testrenderer.Renderer) *driver {
	t.Helper()
	group := supervise.NewGroup(nil)
	dial := Device{Location: r.Location()}.Dial(group, nil)
	drv, err := dial(context.Background())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	d := drv.(*driver)
	d.pollInterval = 10 * time.Millisecond
	t.Cleanup(func() { d.Close() })
	return d
}

func waitEvent(t *testing.T, d *driver, what string, want func(connect.DriverEvent) bool) connect.DriverEvent {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case ev, ok := <-d.Events():
			if !ok {
				t.Fatalf("events closed waiting for %s", what)
			}
			if want(ev) {
				return ev
			}
		case <-deadline:
			t.Fatalf("timed out waiting for %s", what)
		}
	}
}

// commandNames filters the renderer's action log down to the commands,
// dropping the Get polls that interleave freely.
func commandNames(r *testrenderer.Renderer) []string {
	var out []string
	for _, a := range r.Actions() {
		if strings.HasPrefix(a.Name, "Get") {
			continue
		}
		out = append(out, a.Name)
	}
	return out
}

func findAction(r *testrenderer.Renderer, name string) (testrenderer.Action, bool) {
	for _, a := range r.Actions() {
		if a.Name == name {
			return a, true
		}
	}
	return testrenderer.Action{}, false
}

func TestDriverLoadAndCommands(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	ctx := context.Background()
	items := testItems(2)

	if err := d.Load(ctx, items, 0, 5000, true); err != nil {
		t.Fatalf("load: %v", err)
	}
	if err := d.Pause(ctx); err != nil {
		t.Fatalf("pause: %v", err)
	}
	if err := d.SetVolume(ctx, 0.3); err != nil {
		t.Fatalf("setVolume: %v", err)
	}
	if err := d.SeekTo(ctx, 65_000); err != nil {
		t.Fatalf("seekTo: %v", err)
	}

	want := []string{"SetAVTransportURI", "Play", "Seek", "SetNextAVTransportURI", "Pause", "SetVolume", "Seek"}
	got := commandNames(r)
	if len(got) != len(want) {
		t.Fatalf("commands = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("commands = %v, want %v", got, want)
		}
	}

	set, _ := findAction(r, "SetAVTransportURI")
	if set.Args["CurrentURI"] != items[0].URL {
		t.Errorf("CurrentURI = %q", set.Args["CurrentURI"])
	}
	meta := r.MetadataFor(items[0].URL)
	if !strings.Contains(meta, "Track &amp; Co &lt;A&gt;") {
		t.Errorf("metadata not escaped: %q", meta)
	}
	if !strings.Contains(meta, `protocolInfo="http-get:*:audio/mpeg:*"`) {
		t.Errorf("metadata protocolInfo missing: %q", meta)
	}
	next, _ := findAction(r, "SetNextAVTransportURI")
	if next.Args["NextURI"] != items[1].URL {
		t.Errorf("NextURI = %q", next.Args["NextURI"])
	}
	vol, _ := findAction(r, "SetVolume")
	if vol.Args["DesiredVolume"] != "30" || vol.Args["Channel"] != "Master" {
		t.Errorf("SetVolume args = %v", vol.Args)
	}
	if r.Volume() != 30 {
		t.Errorf("renderer volume = %d", r.Volume())
	}
	if r.TransportState() != "PAUSED_PLAYBACK" {
		t.Errorf("state = %q", r.TransportState())
	}
}

func TestDriverLoadWithoutPlay(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	items := testItems(1)

	// positionMS without play is dropped: renderers refuse Seek while
	// stopped, so only the URI may be set.
	if err := d.Load(context.Background(), items, 0, 9000, false); err != nil {
		t.Fatalf("load: %v", err)
	}
	got := commandNames(r)
	if len(got) != 1 || got[0] != "SetAVTransportURI" {
		t.Fatalf("commands = %v, want SetAVTransportURI only", got)
	}
	if r.TransportState() != "STOPPED" {
		t.Errorf("state = %q, want STOPPED", r.TransportState())
	}
	ev := waitEvent(t, d, "poll tick", func(connect.DriverEvent) bool { return true })
	if ev.Playing || ev.Finished {
		t.Errorf("unexpected event %+v", ev)
	}
}

func TestDriverPositionAndVolumeEvents(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	items := testItems(1)

	if err := d.Load(context.Background(), items, 0, 0, true); err != nil {
		t.Fatalf("load: %v", err)
	}
	// The first poll reads volume; the device's resting volume arrives
	// as the first Volume observation.
	ev := waitEvent(t, d, "initial volume", func(ev connect.DriverEvent) bool { return ev.Volume != nil })
	if *ev.Volume != 0.5 {
		t.Errorf("volume = %v, want 0.5", *ev.Volume)
	}
	waitEvent(t, d, "playing", func(ev connect.DriverEvent) bool { return ev.Playing && ev.Index == 0 })

	r.Advance(10 * time.Second)
	ev = waitEvent(t, d, "position", func(ev connect.DriverEvent) bool { return ev.PositionMS >= 10_000 })
	if !ev.Playing {
		t.Errorf("position event not playing: %+v", ev)
	}
}

func TestDriverSelfAdvanceAndFinish(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	items := testItems(2)

	if err := d.Load(context.Background(), items, 0, 0, true); err != nil {
		t.Fatalf("load: %v", err)
	}
	waitEvent(t, d, "playing item 0", func(ev connect.DriverEvent) bool { return ev.Playing && ev.Index == 0 })

	// Gapless is off: the renderer stops at the item end and the
	// driver must set and start the next item itself.
	r.Advance(31 * time.Second)
	waitEvent(t, d, "advance to item 1", func(ev connect.DriverEvent) bool { return ev.Playing && ev.Index == 1 })
	uris := r.URIsSet()
	if len(uris) != 2 || uris[1] != items[1].URL {
		t.Fatalf("uris set = %v", uris)
	}

	r.Advance(31 * time.Second)
	ev := waitEvent(t, d, "finished", func(ev connect.DriverEvent) bool { return ev.Finished })
	if ev.Playing || ev.Index != 1 {
		t.Errorf("finished event = %+v", ev)
	}
}

func TestDriverRendererPromotedAdvance(t *testing.T) {
	r := testrenderer.Start(t)
	r.EnableGaplessNext()
	d := dialDriver(t, r)
	items := testItems(3)

	if err := d.Load(context.Background(), items, 0, 0, true); err != nil {
		t.Fatalf("load: %v", err)
	}
	waitEvent(t, d, "playing item 0", func(ev connect.DriverEvent) bool { return ev.Playing && ev.Index == 0 })

	// The renderer promotes the armed next URI itself; the driver must
	// notice through the playing URI, not re-set the transport.
	r.Advance(31 * time.Second)
	waitEvent(t, d, "promoted to item 1", func(ev connect.DriverEvent) bool { return ev.Playing && ev.Index == 1 })
	if uris := r.URIsSet(); len(uris) != 1 {
		t.Fatalf("driver re-set the transport uri: %v", uris)
	}

	// The next slot was re-armed with the item after the promoted one.
	var armed []string
	for _, a := range r.Actions() {
		if a.Name == "SetNextAVTransportURI" {
			armed = append(armed, a.Args["NextURI"])
		}
	}
	if len(armed) < 2 || armed[len(armed)-1] != items[2].URL {
		t.Fatalf("next slot arms = %v, want last %q", armed, items[2].URL)
	}
}

func TestDriverFatalAfterPollFailures(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	items := testItems(1)

	if err := d.Load(context.Background(), items, 0, 0, true); err != nil {
		t.Fatalf("load: %v", err)
	}
	waitEvent(t, d, "playing", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.Kill()
	ev := waitEvent(t, d, "fatal", func(ev connect.DriverEvent) bool { return ev.Fatal })
	if ev.Err == nil {
		t.Error("fatal event carries no error")
	}
}

func TestDriverSetRateUnsupported(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	if err := d.SetRate(context.Background(), 1.5); err == nil {
		t.Fatal("SetRate succeeded; renderers play at fixed rate")
	}
}

func TestDriverLoadIndexOutOfRange(t *testing.T) {
	r := testrenderer.Start(t)
	d := dialDriver(t, r)
	if err := d.Load(context.Background(), testItems(1), 1, 0, true); err == nil {
		t.Fatal("out of range load succeeded")
	}
}
