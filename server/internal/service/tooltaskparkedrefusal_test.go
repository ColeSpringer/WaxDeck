package service

import (
	"errors"
	"strings"
	"testing"
)

// A merge, a split or a CUE split of what a parked task holds is refused
// for what the parked task needs, not as one still at work: it never
// finishes by itself, so the refusal sends whoever asked to Tasks to
// clear it, naming it.
func TestWhatAParkedTaskHoldsIsRefusedForWhatItNeeds(t *testing.T) {
	t.Parallel()
	t.Run("book", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		id := parkMerge(t, ctx, svc, uc, book, "staged")
		for name, start := range map[string]func() error{
			"merge": func() error { _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); return err },
			"split": func() error { _, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false); return err },
		} {
			err := start()
			if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskParked || p["task"] != id ||
				!strings.Contains(err.Error(), "Tasks") {
				t.Errorf("a %s of the parked task's book = %v (params %v), want it refused for the parked task, naming it", name, err, p)
			}
		}
	})
	t.Run("rip", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, one, _, _ := cueSplitFixture(t)
		task, err := svc.StartCueSplit(ctx, uc, one, false)
		if err != nil {
			t.Fatal(err)
		}
		svc.toolStepHook = stopAt("staged", nil)
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("first attempt = %v, want it stopped once cut", err)
		}
		svc.toolStepHook = nil
		setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
		if !drainAt(ctx, svc, 2) {
			t.Fatal("the worker found no task")
		}
		if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateParked {
			t.Fatalf("task = %s (error %q), want it parked", got.State, got.Error)
		}
		_, err = svc.StartCueSplit(ctx, uc, one, false)
		if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskParked || p["task"] != task.ID {
			t.Errorf("a split of the parked task's rip = %v (params %v), want it refused for the parked task, naming it", err, p)
		}
	})
}
