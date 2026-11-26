package service

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// A path fix whose attempt ran out of time once it moved its track, and
// that is canceled while it waits to try again, ends saying what it moved.
func TestAPathFixCanceledWhileItWaitsCountsWhatItMoved(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.Health.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolRunBound = 500 * time.Millisecond
	svc.Health.awaitJobHook = func(runCtx context.Context, job model.PID, _ time.Duration, _ func(context.Context)) (*model.Job, error) {
		waitForEnd(t, ctx, svc, job)
		<-runCtx.Done()
		return nil, runCtx.Err()
	}
	if !svc.Tools.DrainLongToolTasks(ctx) {
		t.Fatal("the long-task worker found no fix")
	}
	if row := storedTask(t, ctx, svc, start.TaskID); row.State != taskStateRunning || row.WaitReason != "other" {
		t.Fatalf("task = %s waiting on %q (error %q), want it waiting to try again", row.State, row.WaitReason, row.Error)
	}
	if dto := cancelTask(t, ctx, svc, uc, start.TaskID); dto.State != taskStateCanceled {
		t.Fatalf("the cancel answered %s, want canceled", dto.State)
	}
	var sum healthFixSummary
	row := storedTask(t, ctx, svc, start.TaskID)
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatal(err)
	}
	if sum.Moved == nil || *sum.Moved != 1 || sum.Attempted != 1 {
		t.Fatalf("summary %s, want the track its attempt moved counted", row.Summary)
	}
}

// A genre normalize whose attempt ran out of time part way through its
// sweep, canceled while it waits to try again, ends with what the sweep
// counted, not its queue-time summary.
func TestAGenreNormalizeCanceledWhileItWaitsCountsWhatItDid(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	task, err := f.svc.Reads.StartGenreNormalize(f.ctx, f.uc, false)
	if err != nil {
		t.Fatal(err)
	}
	// Two items a page, the attempt's time running out once the first
	// page is counted.
	f.svc.Reads.genrePage = 2
	const bound = 3 * time.Second
	f.svc.Tools.toolRunBound = bound
	var outlasted bool
	f.svc.Tools.activityHook = func(_ string, a ToolTaskActivity) {
		if a.ItemsDone > 0 && !outlasted {
			outlasted = true
			time.Sleep(bound + 500*time.Millisecond)
		}
	}
	if !f.svc.Tools.DrainToolTasks(f.ctx) {
		t.Fatal("the worker found no task")
	}
	f.svc.Tools.activityHook = nil
	if row := storedTask(t, f.ctx, f.svc, task.ID); row.State != taskStateRunning || row.WaitReason != "other" {
		t.Fatalf("task = %s waiting on %q (error %q), want it waiting to try again", row.State, row.WaitReason, row.Error)
	}
	if dto := cancelTask(t, f.ctx, f.svc, f.uc, task.ID); dto.State != taskStateCanceled {
		t.Fatalf("the cancel answered %s, want canceled", dto.State)
	}
	var sum map[string]any
	row := storedTask(t, f.ctx, f.svc, task.ID)
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatal(err)
	}
	if sum["scanned"] != float64(2) || sum["dryRun"] != false {
		t.Fatalf("summary %s, want the first page's two items counted", row.Summary)
	}
}
