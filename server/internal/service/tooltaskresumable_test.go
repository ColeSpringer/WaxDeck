package service

import (
	"context"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// spendAttempts leaves a task as if n of its attempts had run.
func spendAttempts(t *testing.T, ctx context.Context, svc *Library, taskID string, n int) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET attempts = ? WHERE id = ?`, n, taskID); err != nil {
		t.Fatal(err)
	}
}

// drainOnce leases and works one task as the worker would now.
func drainOnce(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if !svc.drainToolTasksAt(ctx, wdb.TaskTypes{Except: taskTypeHealthFix}, time.Now().UnixNano()) {
		t.Fatal("the worker found no task to run")
	}
}

// A CUE split that cuts its pieces on its last counted attempt is
// resumable from then on, and a passing failure to record the cut (a busy
// or failing disk) is waited out as the database says, never ended by
// the drain for its count of attempts; the next run finishes the split.
func TestACueSplitCutOnItsLastAttemptWaitsOutAFailedRecordOfTheCut(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	spendAttempts(t, ctx, svc, task.ID, toolTaskMaxAttempts-1)
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_cut BEFORE UPDATE OF params ON tool_tasks
		WHEN json_extract(NEW.params, '$.step') = 'staged' BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END`); err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.State != taskStateRunning || !row.Resumable || row.WaitReason == "" {
		t.Fatalf("task = %s, resumable %v, waiting on %q (error %q); want it waiting, resumable", row.State, row.Resumable,
			row.WaitReason, row.Error)
	}
	if _, err := svc.db.Writer().ExecContext(ctx, `DROP TRIGGER refuse_cut`); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 4); err != nil {
		t.Fatalf("the next run = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone || len(done.ResultPIDs) != 2 {
		t.Fatalf("task = %s (error %q), results %v; want it done with two tracks", done.State, done.Error, done.ResultPIDs)
	}
}

// A book merge that stages its output on its last counted attempt is
// resumable from then on, so a run that stops there with a passing
// failure is never ended by the drain for its count of attempts; the
// next run finishes the merge.
func TestABookMergeStagedOnItsLastAttemptIsNotFailedForItsAttempts(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	spendAttempts(t, ctx, svc, task.ID, toolTaskMaxAttempts-1)
	svc.toolStepHook = stopAt("staged", nil)
	drainOnce(t, ctx, svc)
	svc.toolStepHook = nil
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.State != taskStateRunning || !row.Resumable {
		t.Fatalf("task = %s, resumable %v (error %q); want it running, resumable", row.State, row.Resumable, row.Error)
	}
	if err := attempt(t, ctx, svc, 4); err != nil {
		t.Fatalf("the next run = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}
