// Driver tests live in the external test package: they exercise the
// public surface against the in-process test receiver, and the
// receiver package imports castv2 for the codec, which an internal
// test file would turn into an import cycle.
package castv2_test

import (
	"context"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/castv2"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2/testreceiver"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

func newTestDriver(t *testing.T) (*testreceiver.Receiver, connect.Driver) {
	t.Helper()
	r := testreceiver.Start(t)
	group := supervise.NewGroup(nil)
	dial := r.Device().Dial(group, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	drv, err := dial(ctx)
	if err != nil {
		t.Fatalf("dialing test receiver: %v", err)
	}
	t.Cleanup(func() { drv.Close() })
	return r, drv
}

// waitEvent consumes events until one satisfies ok.
func waitEvent(t *testing.T, drv connect.Driver, what string, ok func(connect.DriverEvent) bool) connect.DriverEvent {
	t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case ev := <-drv.Events():
			if ok(ev) {
				return ev
			}
		case <-deadline:
			t.Fatalf("timed out waiting for %s", what)
		}
	}
}

func testItems(n int) []connect.MediaItem {
	items := make([]connect.MediaItem, n)
	pids := []string{"tr-01ABC", "tr-01DEF", "tr-01GHI"}
	for i := range items {
		items[i] = connect.MediaItem{
			PID:        pids[i%len(pids)],
			URL:        "http://waxdeck.local:4420/stream/" + pids[i%len(pids)] + "?tok=abc",
			MimeType:   "audio/flac",
			Title:      "Track " + pids[i%len(pids)],
			Artist:     "Artist",
			ArtURL:     "http://waxdeck.local:4420/art/" + pids[i%len(pids)],
			DurationMS: 180_000,
		}
	}
	return items
}

func TestLoadSingle(t *testing.T) {
	r, drv := newTestDriver(t)
	items := testItems(1)
	if err := drv.Load(context.Background(), items, 0, 30_000, true); err != nil {
		t.Fatalf("Load: %v", err)
	}

	if got := r.LaunchedApp(); got != castv2.DefaultMediaReceiverApp {
		t.Errorf("launched app = %q, want %q", got, castv2.DefaultMediaReceiverApp)
	}
	loads := r.Loads()
	if len(loads) != 1 || loads[0].Queue {
		t.Fatalf("loads = %+v, want one plain LOAD", loads)
	}
	if loads[0].CurrentTimeSeconds != 30 {
		t.Errorf("load currentTime = %v, want 30", loads[0].CurrentTimeSeconds)
	}
	got := r.LoadedItems()
	if len(got) != 1 {
		t.Fatalf("loaded %d items, want 1", len(got))
	}
	want := testreceiver.LoadedItem{
		ContentID:   items[0].URL,
		ContentType: "audio/flac",
		StreamType:  "BUFFERED",
		Title:       items[0].Title,
		Artist:      "Artist",
		ArtURL:      items[0].ArtURL,
		Autoplay:    true,
	}
	if got[0] != want {
		t.Errorf("loaded item mismatch:\n got %+v\nwant %+v", got[0], want)
	}

	ev := waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })
	if ev.Index != 0 {
		t.Errorf("event index = %d, want 0 for a single load", ev.Index)
	}
	if ev.PositionMS < 30_000 {
		t.Errorf("event position = %dms, want at least 30000", ev.PositionMS)
	}
}

func TestLoadQueue(t *testing.T) {
	r, drv := newTestDriver(t)
	items := testItems(3)
	if err := drv.Load(context.Background(), items, 1, 5_000, true); err != nil {
		t.Fatalf("Load: %v", err)
	}

	loads := r.Loads()
	if len(loads) != 1 || !loads[0].Queue {
		t.Fatalf("loads = %+v, want one QUEUE_LOAD", loads)
	}
	rec := loads[0]
	if rec.StartIndex != 1 || rec.CurrentTimeSeconds != 5 || rec.RepeatMode != "REPEAT_OFF" {
		t.Errorf("queue load startIndex/currentTime/repeatMode = %d/%v/%q", rec.StartIndex, rec.CurrentTimeSeconds, rec.RepeatMode)
	}
	if len(rec.Items) != 3 {
		t.Fatalf("queue carried %d items, want 3", len(rec.Items))
	}
	for i, item := range rec.Items {
		if !item.Autoplay {
			t.Errorf("queue item %d autoplay = false, want true", i)
		}
	}

	ev := waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })
	if ev.Index != 1 {
		t.Errorf("event index = %d, want 1 (currentItemId mapped into the queue)", ev.Index)
	}
}

// TestStatusCrossingAReloadIsNotTheReloads: a device reports on what it
// plays when it likes, so a status of the media session a reload
// replaces can be on the wire as the LOAD goes out, and is read after
// it. Taken as the reload's own, it moved playback back to where the
// reload had moved it from.
func TestStatusCrossingAReloadIsNotTheReloads(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	items := testItems(3)
	media := func(ev connect.DriverEvent) bool { return ev.Volume == nil }
	if err := drv.Load(ctx, items, 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "the first load's media report", media)

	r.CrossNextLoad()
	if err := drv.Load(ctx, items, 1, 4_000, true); err != nil {
		t.Fatalf("reload: %v", err)
	}
	ev := waitEvent(t, drv, "a media report after the reload", media)
	if ev.Index != 1 || ev.PositionMS != 4_000 {
		t.Fatalf("the first media report after the reload reads item %d at %dms, want item 1 at 4000", ev.Index, ev.PositionMS)
	}
}

// TestAFailedLoadLeavesWhatPlaysReporting: a load the device refuses
// leaves the media it was playing playing, and that media's reports
// are all the session will hear about it, its end included.
func TestAFailedLoadLeavesWhatPlaysReporting(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	items := testItems(2)
	if err := drv.Load(ctx, items[:1], 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.FailNextLoad("NOT_FOUND")
	if err := drv.Load(ctx, items[1:], 0, 0, true); err == nil {
		t.Fatal("a load the device refused succeeded")
	}
	r.Advance(5)
	r.PushStatus()
	waitEvent(t, drv, "a report on the media still playing", func(ev connect.DriverEvent) bool {
		return ev.Volume == nil && ev.Playing && ev.PositionMS >= 5_000
	})
	r.FinishCurrent()
	waitEvent(t, drv, "the media still playing finishing", func(ev connect.DriverEvent) bool { return ev.Finished })
}

// TestAReceiverKeepingItsSessionIDStillFinishes: a receiver that keeps
// the media session id across loads names the replaced session in
// every report on the new load, those it sends before its reply
// included. Dropped as the replaced session's, the new media never
// counted as played and its end never finished the load.
func TestAReceiverKeepingItsSessionIDStillFinishes(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	items := testItems(2)
	r.KeepSessionID()
	if err := drv.Load(ctx, items[:1], 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.AnnounceNextLoad()
	if err := drv.Load(ctx, items[1:], 0, 0, true); err != nil {
		t.Fatalf("reload: %v", err)
	}
	r.FinishCurrent()
	waitEvent(t, drv, "the reload finishing", func(ev connect.DriverEvent) bool { return ev.Finished })
}

// TestStatusCrossingASeekIsNotTheSeeks: a status of the playhead a seek
// moves away from can be on the wire as the SEEK goes out. Stamped as
// current, the session took it after writing the seek's position and
// the scrubber jumped back.
func TestStatusCrossingASeekIsNotTheSeeks(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	lc, ok := drv.(connect.LoadCounter)
	if !ok {
		t.Fatal("the driver does not number its loads")
	}
	media := func(ev connect.DriverEvent) bool { return ev.Volume == nil }
	if err := drv.Load(ctx, testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "the load's media report", media)
	for len(drv.Events()) > 0 {
		<-drv.Events()
	}

	r.Advance(7)
	r.CrossNextSeek()
	if err := drv.SeekTo(ctx, 90_000); err != nil {
		t.Fatalf("SeekTo: %v", err)
	}
	ev := waitEvent(t, drv, "a current media report after the seek", func(ev connect.DriverEvent) bool {
		return media(ev) && ev.Load == lc.CurrentLoad()
	})
	if ev.PositionMS < 90_000 {
		t.Fatalf("the first current media report after the seek reads %dms, want the seek's 90000", ev.PositionMS)
	}
}

// waitCurrent waits, well inside the status poll's interval, for a media
// report stamped with the current load that satisfies ok: what the
// reply to a command says, not what the next poll would.
func waitCurrent(t *testing.T, drv connect.Driver, what string, ok func(connect.DriverEvent) bool) {
	t.Helper()
	lc := drv.(connect.LoadCounter)
	deadline := time.After(2 * time.Second)
	for {
		select {
		case ev := <-drv.Events():
			if ev.Volume == nil && ev.Load == lc.CurrentLoad() && ok(ev) {
				return
			}
		case <-deadline:
			t.Fatalf("no current report of %s before the next poll", what)
		}
	}
}

// TestALoadReportsFromItsReply: a receiver that answers a LOAD and
// broadcasts nothing has said what it plays in the reply alone.
func TestALoadReportsFromItsReply(t *testing.T) {
	_, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(1), 0, 30_000, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitCurrent(t, drv, "the load playing", func(ev connect.DriverEvent) bool {
		return ev.Playing && ev.PositionMS >= 30_000
	})
}

// TestASeekFromPausedReportsFromItsReply: a seek resumes playback, and a
// receiver that broadcasts nothing says so in the reply alone.
func TestASeekFromPausedReportsFromItsReply(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	if err := drv.Load(ctx, testItems(1), 0, 0, false); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitCurrent(t, drv, "the load paused", func(ev connect.DriverEvent) bool { return !ev.Playing })
	if got := r.PlayerState(); got != "PAUSED" {
		t.Fatalf("player state = %q, want PAUSED before the seek", got)
	}
	if err := drv.SeekTo(ctx, 90_000); err != nil {
		t.Fatalf("SeekTo: %v", err)
	}
	waitCurrent(t, drv, "the seek playing", func(ev connect.DriverEvent) bool {
		return ev.Playing && ev.PositionMS >= 90_000
	})
}

func TestLoadQueuePausedPausesAfterStart(t *testing.T) {
	r, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(2), 0, 0, false); err != nil {
		t.Fatalf("Load: %v", err)
	}
	// QUEUE_LOAD has no autoplay knob, so the driver pauses right
	// after the receiver starts.
	if !slices.Contains(r.Actions(), "PAUSE") {
		t.Errorf("actions = %v, want a PAUSE after QUEUE_LOAD", r.Actions())
	}
	if got := r.PlayerState(); got != "PAUSED" {
		t.Errorf("player state = %q, want PAUSED", got)
	}
}

func TestVerbsReachReceiver(t *testing.T) {
	r, drv := newTestDriver(t)
	ctx := context.Background()
	if err := drv.Load(ctx, testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if err := drv.Pause(ctx); err != nil {
		t.Fatalf("Pause: %v", err)
	}
	if got := r.PlayerState(); got != "PAUSED" {
		t.Errorf("after Pause, player state = %q", got)
	}
	if err := drv.Play(ctx); err != nil {
		t.Fatalf("Play: %v", err)
	}
	if err := drv.SeekTo(ctx, 90_000); err != nil {
		t.Fatalf("SeekTo: %v", err)
	}
	if got := r.LastSeekSeconds(); got != 90 {
		t.Errorf("seek target = %v seconds, want 90", got)
	}
	if err := drv.SetVolume(ctx, 0.5); err != nil {
		t.Fatalf("SetVolume: %v", err)
	}
	if got := r.VolumeLevel(); got != 0.5 {
		t.Errorf("volume = %v, want 0.5", got)
	}
	if err := drv.Stop(ctx); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if got := r.PlayerState(); got != "IDLE" {
		t.Errorf("after Stop, player state = %q", got)
	}
	actions := r.Actions()
	for _, want := range []string{"LOAD", "PAUSE", "PLAY", "SEEK", "SET_VOLUME", "STOP"} {
		if !slices.Contains(actions, want) {
			t.Errorf("actions = %v, missing %s", actions, want)
		}
	}
}

func TestVolumeEventFromReceiverStatus(t *testing.T) {
	_, drv := newTestDriver(t)
	ctx := context.Background()
	if err := drv.Load(ctx, testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if err := drv.SetVolume(ctx, 0.25); err != nil {
		t.Fatalf("SetVolume: %v", err)
	}
	ev := waitEvent(t, drv, "volume event", func(ev connect.DriverEvent) bool {
		return ev.Volume != nil && *ev.Volume == 0.25
	})
	if ev.Fatal || ev.Finished {
		t.Errorf("volume event carried fatal/finished: %+v", ev)
	}
}

func TestVerbsWithoutLoadFail(t *testing.T) {
	_, drv := newTestDriver(t)
	ctx := context.Background()
	if err := drv.Play(ctx); err == nil {
		t.Error("Play before Load succeeded, want an error")
	}
	if err := drv.SeekTo(ctx, 1000); err == nil {
		t.Error("SeekTo before Load succeeded, want an error")
	}
}

func TestSetRateFails(t *testing.T) {
	_, drv := newTestDriver(t)
	if err := drv.SetRate(context.Background(), 1.5); err == nil {
		t.Fatal("SetRate succeeded, want an error: cast receivers play at fixed rate")
	}
}

func TestPositionsFollowMockClock(t *testing.T) {
	r, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(1), 0, 30_000, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.Advance(7)
	r.PushStatus()
	waitEvent(t, drv, "advanced position", func(ev connect.DriverEvent) bool {
		return ev.Playing && ev.PositionMS >= 37_000
	})
}

func TestFinishedEvent(t *testing.T) {
	r, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.FinishCurrent()
	ev := waitEvent(t, drv, "finished event", func(ev connect.DriverEvent) bool { return ev.Finished })
	if ev.Playing {
		t.Error("finished event still claims playing")
	}
}

func TestConnectionDeathIsFatal(t *testing.T) {
	r, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	waitEvent(t, drv, "playing event", func(ev connect.DriverEvent) bool { return ev.Playing })

	r.Close()
	ev := waitEvent(t, drv, "fatal event", func(ev connect.DriverEvent) bool { return ev.Fatal })
	if ev.Err == nil {
		t.Error("fatal event carries no error")
	}
}

func TestCloseSendsNoStop(t *testing.T) {
	r, drv := newTestDriver(t)
	if err := drv.Load(context.Background(), testItems(1), 0, 0, true); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if err := drv.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	// Close is teardown, not a verb: the receiver keeps playing.
	if slices.Contains(r.Actions(), "STOP") {
		t.Errorf("actions = %v, Close must not STOP", r.Actions())
	}
	if got := r.PlayerState(); got != "PLAYING" {
		t.Errorf("player state after Close = %q, want PLAYING", got)
	}
}
