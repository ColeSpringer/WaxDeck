package service

import (
	"context"
	"io"
	"log/slog"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startTaskMarkers runs the task-marker worker on a group of its own,
// logging to log (nil discards), until the test ends.
func startTaskMarkers(t *testing.T, ctx context.Context, svc *Library, log *slog.Logger) {
	t.Helper()
	if log == nil {
		log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	wctx, stop := context.WithCancel(ctx)
	group := supervise.NewGroup(log)
	group.Go(wctx, "task-markers", svc.Tools.RunTaskMarkers)
	t.Cleanup(func() {
		stop()
		group.Wait()
	})
}

func waitForMarks(t *testing.T, marks *atomic.Int32, n int32) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for marks.Load() < n {
		if time.Now().After(deadline) {
			t.Fatalf("%d markers sent, want %d", marks.Load(), n)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

const markerTask = "tk-01JZX5N8QW3F4V9T2B7KD3M9R6"

// A task-progress marker sent off a source's report that panics is logged,
// as a worker's panic is, and the next marker due is still sent.
func TestAPanickingMarkerIsLoggedAndTheNextOneSent(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	ctx, svc, _ := managedUploadFixtureWith(t, nil)
	var marks atomic.Int32
	svc.Tools.markHook = func(string) {
		if marks.Add(1) == 1 {
			panic("the marker broke")
		}
	}
	startTaskMarkers(t, ctx, svc, slog.New(slog.NewTextHandler(logs, nil)))
	release := svc.Tools.holdToolTask(markerTask, nil)
	defer release()
	svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = activityDownloading })
	waitForMarks(t, &marks, 1)
	deadline := time.Now().Add(5 * time.Second)
	for !strings.Contains(logs.String(), "the marker broke") {
		if time.Now().After(deadline) {
			t.Fatalf("logs %q, want the marker's panic", logs.String())
		}
		time.Sleep(10 * time.Millisecond)
	}
	svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = activityImporting })
	waitForMarks(t, &marks, 2)
}

// Behind a slow store, a source reporting fast keeps at most one marker
// waiting for its task: every one due while one waits is skipped, and the
// waiting one goes once the store answers.
func TestASlowStoreKeepsOneMarkerWaitingPerTask(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := managedUploadFixtureWith(t, nil)
	var marks, inside, most atomic.Int32
	gate := make(chan struct{})
	svc.Tools.markHook = func(string) {
		n := inside.Add(1)
		defer inside.Add(-1)
		for {
			m := most.Load()
			if n <= m || most.CompareAndSwap(m, n) {
				break
			}
		}
		marks.Add(1)
		<-gate
	}
	startTaskMarkers(t, ctx, svc, nil)
	release := svc.Tools.holdToolTask(markerTask, nil)
	defer release()
	phases := []string{activityDownloading, activityProcessing}
	svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = phases[0] })
	waitForMarks(t, &marks, 1)
	// Each event changes phase, so a marker is due at every one.
	for i := range 20 {
		svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = phases[(i+1)%2] })
	}
	time.Sleep(100 * time.Millisecond)
	if n := marks.Load(); n != 1 {
		t.Errorf("%d markers started behind the slow store, want the one", n)
	}
	close(gate)
	waitForMarks(t, &marks, 2)
	time.Sleep(100 * time.Millisecond)
	if n := marks.Load(); n != 2 {
		t.Errorf("%d markers sent, want the slow one and the one that waited", n)
	}
	if m := most.Load(); m != 1 {
		t.Errorf("%d markers in flight at once, want one", m)
	}
}

// The worker sends a waiting marker once, however often it is woken.
func TestTheWorkerSendsAWaitingMarkerOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := managedUploadFixtureWith(t, nil)
	var marks atomic.Int32
	svc.Tools.markHook = func(string) { marks.Add(1) }
	release := svc.Tools.holdToolTask(markerTask, nil)
	defer release()
	svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = activityDownloading })
	startTaskMarkers(t, ctx, svc, nil)
	waitForMarks(t, &marks, 1)
	svc.Tools.wakeTaskMarkers()
	svc.Tools.wakeTaskMarkers()
	time.Sleep(100 * time.Millisecond)
	if n := marks.Load(); n != 1 {
		t.Errorf("%d markers sent, want one", n)
	}
}

// A marker still waiting when its run ends is not sent: the run's end told
// the watchers itself.
func TestARunThatEndedSendsNoMarker(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := managedUploadFixtureWith(t, nil)
	var marks atomic.Int32
	svc.Tools.markHook = func(string) { marks.Add(1) }
	release := svc.Tools.holdToolTask(markerTask, nil)
	svc.Tools.noteSourceActivity(ctx, markerTask, func(a *ToolTaskActivity) { a.Phase = activityDownloading })
	release()
	startTaskMarkers(t, ctx, svc, nil)
	time.Sleep(200 * time.Millisecond)
	if n := marks.Load(); n != 0 {
		t.Errorf("%d markers sent for an ended run, want none", n)
	}
}
