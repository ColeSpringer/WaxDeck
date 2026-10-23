package service

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
)

// awayEngine is a fake engine that can go away and come back: while it
// is away the bridge offers no jobs surface, as a configured sidecar not
// answering does.
type awayEngine struct {
	*fakeBookEngine
	away atomic.Bool
}

func (e *awayEngine) JobsSupported() bool { return !e.away.Load() }

// drainWhileAway drains the task n times with the engine away, and
// fails unless each pass left it waiting on the engine, no attempt spent.
func drainWhileAway(t *testing.T, ctx context.Context, svc *Library, id string, n int) {
	t.Helper()
	for i := 1; i <= n; i++ {
		if !drainAt(ctx, svc, i) {
			t.Fatalf("pass %d found no task", i)
		}
		row := toolTaskRow(t, ctx, svc, id)
		if row.State != "running" || row.WaitReason != "engine-unavailable" || row.Attempts != 0 {
			t.Fatalf("task after pass %d with the engine away = state %s, wait %q, attempts %d (error %q); want it waiting on the engine, no attempt spent",
				i, row.State, row.WaitReason, row.Attempts, row.Error)
		}
	}
}

// A merge, a split or a CUE split leased while the engine is away waits
// for it, however often it is leased, spending no attempt, and runs once
// the engine answers.
func TestAFileToolWaitsForAnEngineThatIsAway(t *testing.T) {
	t.Parallel()
	t.Run("merge", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, engine := bookToolFixture(t, false)
		away := &awayEngine{fakeBookEngine: engine}
		svc.SetFlowJobs(away)
		if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
			t.Fatal(err)
		}
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		away.away.Store(true)
		drainWhileAway(t, ctx, svc, task.ID, toolTaskMaxAttempts+1)
		away.away.Store(false)
		if !drainAt(ctx, svc, toolTaskMaxAttempts+2) {
			t.Fatal("the worker found no task once the engine answered")
		}
		wantMerged(t, ctx, svc, uc, task.ID, dir)
	})
	t.Run("split", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, engine := chapteredBookFixture(t)
		away := &awayEngine{fakeBookEngine: engine}
		svc.SetFlowJobs(away)
		task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
		if err != nil {
			t.Fatal(err)
		}
		away.away.Store(true)
		drainWhileAway(t, ctx, svc, task.ID, toolTaskMaxAttempts+1)
		away.away.Store(false)
		if !drainAt(ctx, svc, toolTaskMaxAttempts+2) {
			t.Fatal("the worker found no task once the engine answered")
		}
		if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateDone {
			t.Fatalf("task = %s (error %q), want it done", got.State, got.Error)
		}
	})
	t.Run("cue split", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, one, _, engine := cueSplitFixture(t)
		away := &awayEngine{fakeBookEngine: engine}
		svc.SetFlowJobs(away)
		task, err := svc.StartCueSplit(ctx, uc, one, false)
		if err != nil {
			t.Fatal(err)
		}
		away.away.Store(true)
		drainWhileAway(t, ctx, svc, task.ID, toolTaskMaxAttempts+1)
		away.away.Store(false)
		if !drainAt(ctx, svc, toolTaskMaxAttempts+2) {
			t.Fatal("the worker found no task once the engine answered")
		}
		if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateDone {
			t.Fatalf("task = %s (error %q), want it done", got.State, got.Error)
		}
		if real := tracksTitled(t, ctx, svc, "Rip One", false); len(real) != 1 {
			t.Errorf("real Rip One tracks = %v, want one", real)
		}
	})
}

// A task whose run must be finished is never failed by a count of its
// attempts: a last attempt that ends with a failure the run did not
// decide on leaves it for the next lease, which finishes it.
func TestAResumableTaskIsNeverFailedByItsAttemptCount(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	for n, step := range []string{"staged", "trashed"} {
		svc.toolStepHook = stopAt(step, nil)
		if err := attempt(t, ctx, svc, n+1); !errors.Is(err, errStopped) {
			t.Fatalf("attempt %d = %v, want it stopped after %s", n+1, err, step)
		}
	}
	svc.toolStepHook = stopAt("placed", nil)
	if !drainAt(ctx, svc, 3) {
		t.Fatal("the worker found no task")
	}
	svc.toolStepHook = nil
	if got := toolTask(t, ctx, svc, task.ID); got.State != "running" {
		t.Fatalf("task after its third attempt stopped = %s (error %q), want it left to run again", got.State, got.Error)
	}
	if !drainAt(ctx, svc, 4) {
		t.Fatal("the worker found no task once the lease was out")
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// A file tool on a server that now runs no streaming engine at all, the
// one it was queued under taken out of the configuration, fails at once
// saying so: no engine is coming back for it to wait on.
func TestAFileToolOnAServerWithoutAnEngineFailsAtOnce(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{"merge", "cue split"} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			var ctx context.Context
			var svc *Library
			var id string
			switch kind {
			case "merge":
				c, s, uc, book, _, _ := bookToolFixture(t, false)
				task, err := s.StartBookMerge(c, uc, apiPID(PrefixBook, book), nil, false)
				if err != nil {
					t.Fatal(err)
				}
				ctx, svc, id = c, s, task.ID
			default:
				c, s, uc, one, _, _ := cueSplitFixture(t)
				task, err := s.StartCueSplit(c, uc, one, false)
				if err != nil {
					t.Fatal(err)
				}
				ctx, svc, id = c, s, task.ID
			}
			svc.SetFlowJobs(nil)
			if !drainAt(ctx, svc, 1) {
				t.Fatal("the worker found no task")
			}
			row := toolTaskRow(t, ctx, svc, id)
			if row.State != taskStateFailed || row.WaitReason != "" || !strings.Contains(row.Error, "runs without") {
				t.Fatalf("task = state %s, wait %q, error %q; want it failed at once, saying the server runs no engine",
					row.State, row.WaitReason, row.Error)
			}
		})
	}
}
