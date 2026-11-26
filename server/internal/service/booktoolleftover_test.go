package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// failWhileStaging has a split's folder refuse the server once its first
// piece is staged, so the rest cannot be written and the first cannot be
// removed: the run fails for good with that piece left behind.
func failWhileStaging(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, book model.PID, dir string) string {
	t.Helper()
	task, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = func(step string) error {
		if step == "staging" {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
		return nil
	}
	t.Cleanup(func() {
		svc.Tools.toolStepHook = nil
		_ = os.Chmod(dir, 0o755)
	})
	drainOnce(t, ctx, svc)
	svc.Tools.toolStepHook = nil
	return task.ID
}

// A split that fails leaving a piece it could not remove names it, holds
// its book until it is cleared, and its clear removes the piece rather
// than give it a name in the book's folder, even with the book's file
// moved since.
func TestAFailedSplitNamesWhatItLeftAndHoldsItsBook(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	id := failWhileStaging(t, ctx, svc, uc, book, dir)
	row := storedTask(t, ctx, svc, id)
	left := hiddenLeft(t, dir)
	if !ToolTaskFinished(row.State) || row.State == taskStateDone || len(left) == 0 {
		t.Fatalf("task = %s (error %q) with %v left, want it failed with its piece stuck", row.State, row.Error, left)
	}
	for _, path := range left {
		if !strings.Contains(row.Error, filepath.Base(path)) {
			t.Errorf("the error %q does not name %s", row.Error, filepath.Base(path))
		}
	}
	if strings.Contains(row.Error, "nothing was written") {
		t.Errorf("the error %q says nothing was written", row.Error)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskParked || p["task"] != id {
		t.Fatalf("a second split beside the failed one's leftovers = %v (params %v), want it refused for that task", err, p)
	}
	// The book's file moved since: the clear may not take the piece for
	// what is left of the book.
	away := filepath.Join(filepath.Dir(dir), "Elsewhere")
	if err := os.MkdirAll(away, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(dir, "The Chaptered Fixture.m4b"), filepath.Join(away, "The Chaptered Fixture.m4b")); err != nil {
		t.Fatal(err)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing the failed split: %v", err)
	}
	if names := namesIn(t, dir); len(names) != 0 {
		t.Errorf("clearing left %q in the book's folder, want the discarded piece removed", names)
	}
}

// A canceled split whose book can no longer be worked out from its task
// still has its clear remove the pieces its error names.
func TestAClearOfABookToolItCannotReadRetriesItsLeftovers(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	id := cancelWhileStaging(t, ctx, svc, uc, book)
	svc.Tools.drainHook = func(point, taskID string) {
		if point == "ran" && taskID == id {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	drainOnce(t, ctx, svc)
	svc.Tools.drainHook = nil
	if row := storedTask(t, ctx, svc, id); row.State != taskStateCanceled || len(hiddenLeft(t, dir)) == 0 {
		t.Fatalf("task = %s (error %q), want it canceled with its pieces stuck", row.State, row.Error)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	setParams(t, ctx, svc, id, func(p *toolTaskParams) { p.SrcPath, p.SrcFilePID = "", "" })
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing the canceled split: %v", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("clearing left %v in the book's folder", left)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"The Chaptered Fixture.m4b"}) {
		t.Errorf("the book's folder holds %q, want the original alone", names)
	}
}

// A split whose discard was recorded but whose failure was not (the
// process died between the two) runs again; once that run is done, its
// clear leaves the finished book's files alone.
func TestARerunPastALostFailureKeepsItsFilesOnTheClear(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	task, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = func(step string) error {
		if step == "staging" {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
		return nil
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	// Run without the drain's arms: the failure is never recorded.
	if err := attempt(t, ctx, svc, 1); err == nil || !permanentToolErr(err) {
		t.Fatalf("first attempt = %v, want it refused for good", err)
	}
	svc.Tools.toolStepHook = nil
	if p := taskParams(t, ctx, svc, task.ID); !p.Discarded || p.Step != "" {
		t.Fatalf("params after the lost failure: step %q, discarded %v; want the discard recorded", p.Step, p.Discarded)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	drainTaskAt(t, ctx, svc, time.Now().Add(10*toolTaskLease))
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone {
		t.Fatalf("rerun = %s (error %q), want it done", row.State, row.Error)
	}
	before := namesIn(t, dir)
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing the done split: %v", err)
	}
	if after := namesIn(t, dir); !slices.Equal(after, before) || len(after) < 2 {
		t.Errorf("the book's folder went from %q to %q on the clear, want the split's files kept", before, after)
	}
}

// A split its attempts ran out on, whose discard by the retire pass
// leaves a piece it cannot remove, holds its book until it is cleared.
func TestARetiredSplitWithLeftoversHoldsItsBook(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	task, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = stopAt("staging", nil)
	if err := attempt(t, ctx, svc, 1); err == nil {
		t.Fatal("first attempt finished, want it stopped once a piece is staged")
	}
	svc.Tools.toolStepHook = nil
	spendAttempts(t, ctx, svc, task.ID, toolTaskMaxAttempts)
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	svc.Tools.retireExhaustedToolTasks(ctx, time.Now().Add(10*toolTaskLease).UnixNano())
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateParked || len(hiddenLeft(t, dir)) == 0 || !strings.Contains(row.Error, "clearing the task tries again") {
		t.Fatalf("task = %s (error %q) with %v left, want it parked naming its stuck piece", row.State, row.Error, hiddenLeft(t, dir))
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err = svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskParked || p["task"] != task.ID {
		t.Fatalf("a second split beside the retired one's leftovers = %v (params %v), want it refused for that task", err, p)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing the retired split: %v", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("clearing left %v", left)
	}
}
