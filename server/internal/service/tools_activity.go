package service

import (
	"context"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// What a running task is doing: the record a run in this process keeps,
// the markers that tell the task's watchers, and the progress it implies.

// The phases a run reports.
const (
	activityListing     = "listing"
	activityDownloading = syncsource.PhaseDownloading
	activityProcessing  = syncsource.PhaseProcessing
	activityImporting   = "importing"
)

// activityMarkEvery is how often moving activity tells a task's watchers;
// a change of phase tells them at once.
const activityMarkEvery = 2 * time.Second

// taskRun is one task's run in this process: the holds on it, which the
// retire pass leaves, what ends it when the task is canceled, and what it
// is doing.
type taskRun struct {
	holds    int
	cancel   context.CancelCauseFunc
	activity ToolTaskActivity
	markedAt time.Time
	// markPending is a marker scheduled off a source's report, not yet sent.
	markPending bool
}

// noteActivity records what a task's run is doing now, through edit (nil
// for activity that changes nothing it says), and tells the task's
// watchers on a change of phase, else at most every activityMarkEvery.
// It reports whether a run here holds the task; one none holds has
// nothing to record.
func (l *Tools) noteActivity(ctx context.Context, taskID string, edit func(*ToolTaskActivity)) bool {
	return l.recordActivity(ctx, taskID, edit, false)
}

// noteSourceActivity is noteActivity for what a source reports from its
// own transfer or listing, which calls it inline: the record changes at
// once, and a marker due is sent off that path, one at most waiting per
// task, so a busy store never holds the source up.
func (l *Tools) noteSourceActivity(ctx context.Context, taskID string, edit func(*ToolTaskActivity)) bool {
	return l.recordActivity(ctx, taskID, edit, true)
}

func (l *Tools) recordActivity(ctx context.Context, taskID string, edit func(*ToolTaskActivity), deferMark bool) bool {
	now := time.Now()
	l.toolRunsMu.Lock()
	run := l.toolRuns[taskID]
	if run == nil {
		l.toolRunsMu.Unlock()
		return false
	}
	phase := run.activity.Phase
	if edit != nil {
		edit(&run.activity)
	}
	run.activity.AtNS = now.UnixNano()
	mark := run.activity.Phase != phase || now.Sub(run.markedAt) >= activityMarkEvery
	if mark && deferMark {
		// One waits at most, and reads the record as it stands when sent.
		if run.markPending {
			mark = false
		} else {
			run.markPending = true
		}
	}
	if mark {
		run.markedAt = now
	}
	seen := run.activity
	l.toolRunsMu.Unlock()
	if l.activityHook != nil {
		l.activityHook(taskID, seen)
	}
	if !mark {
		return true
	}
	if deferMark {
		l.wakeTaskMarkers()
		return true
	}
	l.notifyToolTaskProgress(context.WithoutCancel(ctx), taskID)
	return true
}

// wakeTaskMarkers tells the marker worker a marker waits.
func (l *Tools) wakeTaskMarkers() {
	select {
	case l.markWake <- struct{}{}:
	default:
	}
}

// RunTaskMarkers is the worker that sends the markers scheduled off a
// source's report, so a busy store never holds the source up.
func (l *Tools) RunTaskMarkers(ctx context.Context) error {
	for {
		l.sendWaitingMarks(ctx)
		select {
		case <-ctx.Done():
			return nil
		case <-l.markWake:
		}
	}
}

// sendWaitingMarks sends the marker of every run here that has one
// waiting; a run that ended meanwhile told its watchers so itself.
func (l *Tools) sendWaitingMarks(ctx context.Context) {
	for ctx.Err() == nil {
		l.toolRunsMu.Lock()
		taskID := ""
		for id, run := range l.toolRuns {
			if run.markPending {
				run.markPending = false
				taskID = id
				break
			}
		}
		l.toolRunsMu.Unlock()
		if taskID == "" {
			return
		}
		if l.markHook != nil {
			l.markHook(taskID)
		}
		l.notifyToolTaskProgress(ctx, taskID)
	}
}

// activityOf is what a run here says the task is doing, once it has said.
func (l *Tools) activityOf(taskID string) (ToolTaskActivity, bool) {
	l.toolRunsMu.Lock()
	defer l.toolRunsMu.Unlock()
	run := l.toolRuns[taskID]
	if run == nil || run.activity.Phase == "" {
		return ToolTaskActivity{}, false
	}
	return run.activity, true
}

// progress is the percent a run's items imply, with the bytes of the
// item in hand, on the share its items fill; 0 for a run that does not
// count so.
func (a ToolTaskActivity) progress() float64 {
	if a.pctShare <= 0 || a.ItemsTotal <= 0 {
		return 0
	}
	done := float64(a.ItemsDone)
	if a.BytesTotal > 0 {
		done += min(float64(a.BytesDone)/float64(a.BytesTotal), 1)
	}
	return min(done/float64(a.ItemsTotal), 1) * a.pctShare
}

// fetchEvent takes one event of the fetch of the item in hand: its phase,
// and while downloading its bytes, which a new attempt starts again.
func (a *ToolTaskActivity) fetchEvent(ev syncsource.FetchEvent) {
	if ev.Phase != "" {
		a.Phase = ev.Phase
	}
	if ev.Phase == activityDownloading {
		a.BytesDone = ev.Bytes
		if ev.Total > 0 || ev.Bytes == 0 {
			a.BytesTotal = ev.Total
		}
	}
}

// listingActivity says a task lists its source and is the listing's
// progress hook, whose every page and lookup is activity.
func (l *Tools) listingActivity(ctx context.Context, taskID string) syncsource.ListProgress {
	l.noteActivity(ctx, taskID, func(a *ToolTaskActivity) { *a = ToolTaskActivity{Phase: activityListing} })
	return syncsource.ListProgress{
		OnPage:   func(int) { l.noteSourceActivity(ctx, taskID, nil) },
		OnLookup: func(int, int) { l.noteSourceActivity(ctx, taskID, nil) },
	}
}

// noteJobOutput says an engine tool fetches its job's output i of n:
// processing, as downloading is a byte stream's phase and this has none.
func (l *Tools) noteJobOutput(ctx context.Context, taskID string, i, n int) {
	l.noteActivity(ctx, taskID, func(a *ToolTaskActivity) {
		*a = ToolTaskActivity{Phase: activityProcessing, ItemsDone: i, ItemsTotal: n}
	})
}

// noteToolImport says a tool takes what it made into the library.
func (l *Tools) noteToolImport(ctx context.Context, taskID string) {
	l.noteActivity(ctx, taskID, func(a *ToolTaskActivity) { *a = ToolTaskActivity{Phase: activityImporting} })
}

// withActivity is a task's DTO with what its run here is doing, and the
// progress that implies when it is past the progress recorded.
func (l *Tools) withActivity(dto ToolTaskDTO) ToolTaskDTO {
	if dto.State != taskStateRunning || dto.WaitReason != "" {
		return dto
	}
	if a, ok := l.activityOf(dto.ID); ok {
		dto.Activity = &a
		dto.ProgressPct = max(dto.ProgressPct, a.progress())
	}
	return dto
}

// stallWatch stops a download that shows no activity for its window:
// armed by the first downloading event and reset by every one after it,
// it lies still while the fetch is in any other phase, whose stages
// report only as they begin.
type stallWatch struct {
	window time.Duration
	stop   func()

	mu     sync.Mutex
	timer  *time.Timer
	phase  string
	closed bool
}

// event takes one fetch event, in the phase it names or, with none, the
// phase at hand.
func (w *stallWatch) event(phase string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.closed {
		return
	}
	if phase != "" {
		w.phase = phase
	}
	switch {
	case w.phase != activityDownloading:
		if w.timer != nil {
			w.timer.Stop()
		}
	case w.timer == nil:
		w.timer = time.AfterFunc(w.window, w.stop)
	default:
		w.timer.Reset(w.window)
	}
}

// done disarms the watch for good.
func (w *stallWatch) done() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.closed = true
	if w.timer != nil {
		w.timer.Stop()
	}
}
