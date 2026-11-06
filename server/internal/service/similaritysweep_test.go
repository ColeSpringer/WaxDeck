package service

import (
	"context"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
)

// sweepWoken reports, and consumes, a pending wakeup of the sweep loop.
func sweepWoken(svc *Library) bool {
	select {
	case <-svc.simWake:
		return true
	default:
		return false
	}
}

// startSweeps runs the sweep loop on schedule s for the rest of the test.
func startSweeps(t *testing.T, ctx context.Context, svc *Library, s similaritySchedule) {
	t.Helper()
	loopCtx, stop := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = svc.runSimilaritySweeps(loopCtx, s)
	}()
	t.Cleanup(func() { stop(); <-done })
}

// quietFixture is a scanned catalog no sweep has walked yet, with its
// scan's wakeups spent.
func quietFixture(t *testing.T, analysis bool) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, svc, uc := newCatalogFixture(t)
	if analysis {
		enableSonicAnalysis(t, ctx, svc, uc)
	}
	feedCaughtUp(t, ctx, svc)
	sweepWoken(svc)
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Fatalf("queue depth %d before any sweep", depth)
	}
	return ctx, svc, uc
}

// What the analysis queue waits on wakes the sweep: a new item, a
// changed library (a root added or brought back), a replaced catalog.
// An edit does not, and neither does a change from before the boot,
// which the first sweep covers.
func TestArrivalsWakeTheSimilaritySweep(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := quietFixture(t, false)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UnixNano()
	// In order: a replacement starts a new boot, after which no change
	// is history.
	for _, c := range []struct {
		name string
		ch   model.Change
		want bool
	}{
		{"an edit", model.Change{TS: now, EntityType: "item", EntityPID: "x", Op: model.OpUpdate}, false},
		{"a new item", model.Change{TS: now, EntityType: "item", EntityPID: "x", Op: model.OpCreate}, true},
		{"a changed library", model.Change{TS: now, EntityType: "library", EntityPID: "x", Op: model.OpUpdate}, true},
		{"a new item from before the boot", model.Change{TS: 1, EntityType: "item", EntityPID: "x", Op: model.OpCreate}, false},
		{"a replaced catalog", model.Change{Seq: head, TS: now, EntityType: model.ChangeCatalog}, true},
	} {
		svc.advanceFeed(ctx, c.ch)
		if got := sweepWoken(svc); got != c.want {
			t.Errorf("%s: woke the sweep = %v, want %v", c.name, got, c.want)
		}
	}
}

// A scan that adds a track wakes the sweep, so the track joins the
// analysis queue once the scan goes quiet rather than at the backstop.
func TestAScannedTrackIsQueuedWithoutWaitingForTheBackstop(t *testing.T) {
	t.Parallel()
	var libDir string
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		extra: func(_ *testing.T, dir string) { libDir = dir },
	})
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	queued := queueDepth(t, ctx, svc)
	feedCaughtUp(t, ctx, svc)
	sweepWoken(svc)
	// Neither the boot sweep nor the backstop comes due in the test.
	startSweeps(t, ctx, svc, similaritySchedule{first: time.Hour, settle: 20 * time.Millisecond, backstop: time.Hour})

	if _, err := fixtures.Generate(libDir, fixtures.Spec{
		Name: "ember", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Ember Line", "ARTIST": "Test Ensemble", "ALBUM": "Signal Garden"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return queueDepth(t, ctx, svc) == queued+1 }, "the scanned track queued for analysis")
}

// Turning sonic analysis on queues a library scanned while it was off,
// rather than leaving coverage at nothing until the backstop.
func TestTurningAnalysisOnQueuesTheLibraryWithoutTheBackstop(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := quietFixture(t, false)
	startSweeps(t, ctx, svc, similaritySchedule{first: time.Hour, settle: 20 * time.Millisecond, backstop: time.Hour})
	enableSonicAnalysis(t, ctx, svc, uc)
	waitFor(t, func() bool { return queueDepth(t, ctx, svc) > 0 }, "the library queued once analysis is on")
}

// Arrivals that keep coming hold the sweep until they stop, so a long
// scan is not walked again for every burst of it.
func TestASweepWaitsForArrivalsToStop(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := quietFixture(t, true)
	startSweeps(t, ctx, svc, similaritySchedule{first: time.Hour, settle: 500 * time.Millisecond, backstop: time.Hour})
	for end := time.Now().Add(1500 * time.Millisecond); time.Now().Before(end); time.Sleep(20 * time.Millisecond) {
		svc.similarityWakeup()
	}
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Fatalf("queue depth %d while arrivals kept coming, want no sweep yet", depth)
	}
	waitFor(t, func() bool { return queueDepth(t, ctx, svc) > 0 }, "the sweep once the arrivals stopped")
}

// A scan that never goes quiet is still swept at the backstop.
func TestTheBackstopSweepsAScanThatNeverGoesQuiet(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := quietFixture(t, true)
	startSweeps(t, ctx, svc, similaritySchedule{first: time.Hour, settle: time.Hour, backstop: 300 * time.Millisecond})
	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case <-stop:
				return
			case <-time.After(20 * time.Millisecond):
				svc.similarityWakeup()
			}
		}
	}()
	t.Cleanup(func() { close(stop); <-done })
	waitFor(t, func() bool { return queueDepth(t, ctx, svc) > 0 }, "a backstop sweep while arrivals kept coming")
}

// A sweep a catalog hand-off held off runs once the hand-off ends, not at
// the backstop.
func TestASweepHeldOffByMaintenanceRunsWhenItEnds(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := quietFixture(t, true)
	gen := svc.suspendGen.Add(1)
	svc.maintenance.Store(true)
	startSweeps(t, ctx, svc, similaritySchedule{first: time.Hour, settle: 20 * time.Millisecond, backstop: time.Hour})
	svc.similarityWakeup()
	waitFor(t, func() bool { return len(svc.simWake) == 0 }, "the loop taking the wakeup")
	time.Sleep(200 * time.Millisecond) // ten settles: its sweep has found the hand-off
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Fatalf("queue depth %d during the hand-off, want none", depth)
	}
	svc.endMaintenance(gen)
	waitFor(t, func() bool { return queueDepth(t, ctx, svc) > 0 }, "the held-off sweep once the hand-off ended")
}
