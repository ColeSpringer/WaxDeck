package service

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// cancelAtImport asks the task to cancel as its run takes what it made
// into the library, before the run is resumable, then runs act; the run
// learns of the cancel only when its commit is refused.
func cancelAtImport(t *testing.T, ctx context.Context, svc *Library, id string, act func()) {
	t.Helper()
	asked := false
	svc.Tools.activityHook = func(task string, a ToolTaskActivity) {
		if task != id || a.Phase != activityImporting || asked {
			return
		}
		asked = true
		if ok, err := svc.db.RequestToolTaskCancel(context.WithoutCancel(ctx), id); err != nil || !ok {
			t.Errorf("asking to cancel = %v, %v", ok, err)
		}
		act()
	}
	t.Cleanup(func() { svc.Tools.activityHook = nil })
}

// A canceled merge whose cleanup left its hidden output in the book's
// folder keeps the book from another merge or split until it is cleared,
// as a parked task does; cleared, the book is free again.
func TestACanceledMergeWithLeftoversHoldsItsBook(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	cancelAtImport(t, ctx, svc, task.ID, func() {})
	svc.Tools.drainHook = func(point, taskID string) {
		if point == "ran" && taskID == task.ID {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	drainOnce(t, ctx, svc)
	svc.Tools.drainHook = nil
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled || len(hiddenLeft(t, dir)) == 0 {
		t.Fatalf("task = %s (error %q) with %v left, want it canceled and its output stuck", row.State, row.Error, hiddenLeft(t, dir))
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err = svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskParked || p["task"] != task.ID {
		t.Fatalf("a second merge beside the canceled one's leftovers = %v (params %v), want it refused for that task", err, p)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing the canceled merge: %v", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("clearing left %v in the book's folder", left)
	}
	if _, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); err != nil {
		t.Errorf("a merge once the canceled one is cleared = %v, want it queued", err)
	}
}

// A canceled merge whose cleanup removed everything frees its book at once.
func TestACanceledMergeThatCleanedUpFreesItsBook(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	cancelAtImport(t, ctx, svc, task.ID, func() {})
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled || len(hiddenLeft(t, dir)) != 0 {
		t.Fatalf("task = %s (error %q) with %v left, want it canceled and clean", row.State, row.Error, hiddenLeft(t, dir))
	}
	if _, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); err != nil {
		t.Errorf("a merge after a clean cancel = %v, want it queued", err)
	}
}

// A canceled CUE split whose workspace could not be removed frees its rip
// at once: the workspace is the server's scratch, not the library. Its
// clear goes through, and the startup sweep takes the workspace once its
// task is gone.
func TestACanceledCueSplitsWorkspaceNeverHoldsItsRip(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.Tools.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	ws := filepath.Join(svc.Ingest.stagingDir, "tools", task.ID)
	album := filepath.Join(ws, "Rip Album")
	cancelAtImport(t, ctx, svc, task.ID, func() {
		if err := os.Chmod(album, 0o555); err != nil {
			t.Error(err)
		}
	})
	t.Cleanup(func() { _ = os.Chmod(album, 0o755) })
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, task.ID)
	if _, err := os.Stat(ws); row.State != taskStateCanceled || err != nil || row.Error != "" {
		t.Fatalf("task = %s (error %q), workspace %v, want it canceled, its workspace stuck and unmentioned", row.State, row.Error, err)
	}
	if _, err := svc.Tools.StartCueSplit(ctx, uc, one, false); err != nil {
		t.Fatalf("a second split beside the canceled one's workspace = %v, want it queued", err)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing while the workspace still refuses = %v, want the task gone", err)
	}
	if err := os.Chmod(album, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := svc.Tools.sweepToolWorkspaces(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(ws); !os.IsNotExist(err) {
		t.Errorf("the sweep left the cleared task's workspace (%v)", err)
	}
}

// The workspace sweep keeps the folders of tasks that still exist, a
// leased one and a queued one, and takes only one whose task is gone; on
// shutdown it stops quietly, keeping whatever it had not reached.
func TestTheWorkspaceSweepKeepsLiveTasksFolders(t *testing.T) {
	t.Parallel()
	var logs syncBuffer
	ctx, svc, uc := acquireFixture(t, &stagingSource{}, loggingTo(&logs))
	var ids []string
	for _, url := range []string{"https://tube.example/watch?v=one", "https://tube.example/watch?v=two"} {
		task, err := svc.Ingest.StartAcquisition(ctx, uc, url, false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, task.ID)
	}
	leased, err := svc.db.LeaseToolTask(ctx, time.Now().UnixNano(), toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{})
	if err != nil || leased.State != taskStateRunning {
		t.Fatalf("lease = %+v, %v; want one task running", leased, err)
	}
	root := filepath.Join(svc.Ingest.stagingDir, "tools")
	for _, id := range append(ids, "tk-gone") {
		if err := os.MkdirAll(filepath.Join(root, id), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	stopped, stop := context.WithCancel(ctx)
	stop()
	_ = svc.Tools.sweepToolWorkspaces(stopped)
	if _, err := os.Stat(filepath.Join(root, "tk-gone")); err != nil {
		t.Errorf("a sweep stopped before it began removed the orphan (%v)", err)
	}
	if strings.Contains(logs.String(), "level=WARN") {
		t.Errorf("a sweep stopped on shutdown warned:\n%s", logs.String())
	}
	if err := svc.Tools.sweepToolWorkspaces(ctx); err != nil {
		t.Fatal(err)
	}
	for _, id := range ids {
		if _, err := os.Stat(filepath.Join(root, id)); err != nil {
			t.Errorf("the sweep removed live task %s's workspace (%v)", id, err)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "tk-gone")); !os.IsNotExist(err) {
		t.Errorf("the sweep kept the orphaned workspace (%v)", err)
	}
}
