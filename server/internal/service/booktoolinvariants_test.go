package service

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// drainAt runs the tool worker's pass the nth time, as of a moment past
// every earlier lease.
func drainAt(ctx context.Context, svc *Library, n int) bool {
	now := time.Now().Add(time.Duration(n) * 2 * toolTaskLease).UnixNano()
	return svc.drainToolTasksAt(ctx, wdb.TaskTypes{Except: taskTypeHealthFix}, now)
}

// busyOnce answers a busy catalog the first time op runs, as a scan or
// another job holding the catalog would.
func busyOnce(op string) func(string) error {
	done := false
	return func(got string) error {
		if got != op || done {
			return nil
		}
		done = true
		return waxerr.New(waxerr.CodeConflict, "jobs.Run", "another job holds scope fs-mutate")
	}
}

// A second merge or split of a book one is still at work on is refused
// when it is queued, naming the live task, whatever the book looks like
// part way through the first.
func TestASecondToolTaskOnABookIsRefusedWhileTheFirstIsLive(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	first, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() { trashAs(t, ctx, svc, taskTypeBookMerge, parts[0]) })
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	for _, start := range []func() (ToolTaskDTO, error){
		func() (ToolTaskDTO, error) { return svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false) },
		func() (ToolTaskDTO, error) { return svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false) },
	} {
		_, err := start()
		if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskRunning || p["task"] != first.ID {
			t.Fatalf("a second tool on the book = %v (kind %q, params %v), want it refused naming %s", err, KindOf(err), p, first.ID)
		}
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the first task's rerun = %v, want it finished", err)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"Tool Book.m4b"}) {
		t.Errorf("the book's folder holds %q, want the one merged file", names)
	}
}

// A run renews its task's lease while it works, not only while the
// engine runs.
func TestARunHoldsItsLeaseThroughEveryStep(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	svc.toolLeaseEvery = 5 * time.Millisecond
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	row, err := svc.db.LeaseToolTask(ctx, time.Now().UnixNano(), toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{})
	if err != nil {
		t.Fatal(err)
	}
	leased := row.LeaseUntilNS
	var renewed int64
	svc.toolStepHook = func(step string) error {
		if step == "trashed" {
			time.Sleep(60 * time.Millisecond)
			renewed = toolTaskRow(t, ctx, svc, task.ID).LeaseUntilNS
		}
		return nil
	}
	if err := svc.runToolTask(ctx, &row); err != nil {
		t.Fatal(err)
	}
	if renewed <= leased {
		t.Fatalf("lease during the run = %d, want it renewed past %d", renewed, leased)
	}
}

// toolTaskRow reads a task's row back.
func toolTaskRow(t *testing.T, ctx context.Context, svc *Library, id string) wdb.ToolTask {
	t.Helper()
	row, err := svc.db.ToolTaskByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	return row
}

// The retire pass leaves a task a run is still working, however its
// lease and attempts read: no second settle runs beside the attempt, and
// the run ends recorded once.
func TestTheRetirePassLeavesATaskARunHolds(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := chapteredBookFixture(t)
	task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	for n := 1; n <= 2; n++ {
		svc.toolStepHook = stopAt("producing", nil)
		if err := attempt(t, ctx, svc, n); !errors.Is(err, errStopped) {
			t.Fatalf("attempt %d = %v, want it stopped", n, err)
		}
	}
	var during string
	svc.toolStepHook = func(step string) error {
		if step == "producing" {
			svc.retireExhaustedToolTasks(ctx, time.Now().Add(20*toolTaskLease).UnixNano())
			during = toolTaskRow(t, ctx, svc, task.ID).State
		}
		return nil
	}
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("the third attempt = %v, want it finished", err)
	}
	if during != "running" {
		t.Errorf("task as the retire pass ran mid-attempt = %q, want it left running", during)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Errorf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if audits := auditDetails(t, ctx, svc, "book.split"); len(audits) != 1 {
		t.Errorf("book.split audits = %v, want one", audits)
	}
}

// Nothing goes to the trash with an output not staged: a rerun that finds
// its output gone puts back what its trash took and makes the output
// again before anything more goes.
func TestARerunMissingItsOutputPutsBackAndProducesItAgain(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, engine := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() { trashAs(t, ctx, svc, taskTypeBookMerge, parts[0]) })
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	for _, staged := range hiddenLeft(t, dir) {
		if err := os.Remove(staged); err != nil {
			t.Fatal(err)
		}
	}
	var trashedWithoutOutput bool
	svc.toolStepHook = func(step string) error {
		if step == "trashing" && len(hiddenLeft(t, dir)) == 0 {
			trashedWithoutOutput = true
		}
		return nil
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if trashedWithoutOutput {
		t.Error("the rerun went to the trash with no output staged")
	}
	if engine.made() != 2 {
		t.Errorf("engine jobs = %d, want the output made again", engine.made())
	}
	done := toolTask(t, ctx, svc, task.ID)
	if done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"Tool Book.m4b"}) {
		t.Errorf("the book's folder holds %q, want the merged file alone", names)
	}
	if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeBookMerge, taskTypeBookMerge}) {
		t.Errorf("trash = %q, want the two parts once each", trash)
	}
}

// A put-back that ended without its failure being recorded leaves the
// task where a rerun trashes nothing: the put-back records the start as
// the task's step once every file is back.
func TestARerunAfterAnUnrecordedPutBackTrashesNothing(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.deleteApplyHook = func(context.Context) { lockFolder(t, filepath.Join(dir, "CD2")) }
	svc.toolStepHook = stopAt("undone", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once the put-back was done", err)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Fatalf("trash after the put-back = %q, want it empty", trash)
	}
	var recorded toolTaskParams
	if err := json.Unmarshal([]byte(toolTaskRow(t, ctx, svc, task.ID).Params), &recorded); err != nil {
		t.Fatal(err)
	}
	if recorded.Step != "" || recorded.TrashFromNS != 0 {
		t.Fatalf("the task records step %q from %d after the put-back, want the start", recorded.Step, recorded.TrashFromNS)
	}
	svc.deleteApplyHook, svc.toolStepHook = nil, nil
	if err := os.Chmod(filepath.Join(dir, "CD2"), 0o755); err != nil {
		t.Fatal(err)
	}
	err = attempt(t, ctx, svc, 2)
	if !errors.Is(err, errToolPermanent) {
		t.Fatalf("the rerun = %v, want it refused for good", err)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash after the rerun = %q, want nothing moved", trash)
	}
	if got := partFiles(t, ctx, svc, book); len(got) != 2 {
		t.Errorf("the book has %d parts, want both", len(got))
	}
}

// A busy catalog at the trash is waited out: the attempt is handed back
// uncounted with its staged output kept, and the next one finishes
// without the engine.
func TestABusyCatalogAtTheTrashIsWaitedOut(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, engine := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.mutateHook = busyOnce("trash")
	if !drainAt(ctx, svc, 1) {
		t.Fatal("the worker found no task")
	}
	row := toolTaskRow(t, ctx, svc, task.ID)
	if row.State != "running" || row.Attempts != 0 || row.LeaseUntilNS <= time.Now().UnixNano() || !strings.Contains(row.Error, "conflicting catalog job") {
		t.Fatalf("task after the busy catalog = %+v, want it waiting, its attempt not counted, saying why", row)
	}
	if left := hiddenLeft(t, dir); len(left) != 1 {
		t.Fatalf("hidden copies = %q, want the staged output kept", left)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Fatalf("trash = %q, want nothing moved", trash)
	}
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task once the wait was out")
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
	if engine.made() != 1 {
		t.Errorf("engine jobs = %d, want the one", engine.made())
	}
}

// A busy catalog at the scan is waited out too, after the parts went:
// the next attempt scans, carries positions and records the run once.
func TestABusyCatalogAtTheScanIsWaitedOut(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.mutateHook = busyOnce("scan")
	err = attempt(t, ctx, svc, 1)
	var wait *toolRetry
	if !errors.As(err, &wait) || KindOf(err) != KindCatalogBusy {
		t.Fatalf("first attempt = %v, want it waiting on the busy catalog", err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// A last attempt that waits after the parts went is handed back, not
// failed: no count of attempts ends a task with the book in the trash.
func TestALastAttemptThatWaitsAfterTheTrashIsHandedBack(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	for n, step := range []string{"trashed", "placed"} {
		svc.toolStepHook = stopAt(step, nil)
		if err := attempt(t, ctx, svc, n+1); !errors.Is(err, errStopped) {
			t.Fatalf("attempt %d = %v, want it stopped after %s", n+1, err, step)
		}
	}
	svc.toolStepHook = nil
	svc.mutateHook = busyOnce("scan")
	if !drainAt(ctx, svc, 3) {
		t.Fatal("the worker found no task")
	}
	if got := toolTask(t, ctx, svc, task.ID); got.State != "running" {
		t.Fatalf("task after its last attempt waited = %s (error %q), want it handed back", got.State, got.Error)
	}
	if !drainAt(ctx, svc, 4) {
		t.Fatal("the worker found no task once the wait was out")
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// What the run's trash took is counted from the trash itself: a part the
// catalog let go of by other means is not claimed as the run's.
func TestTheRunsTrashIsCountedFromTheTrash(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() {
		trashAs(t, ctx, svc, taskTypeBookMerge, parts[0])
		trashAs(t, ctx, svc, "user", parts[1])
	})
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	row := toolTaskRow(t, ctx, svc, task.ID)
	var p toolTaskParams
	if err := json.Unmarshal([]byte(row.Params), &p); err != nil {
		t.Fatal(err)
	}
	b, err := svc.bookToolFor(ctx, &row, &p)
	if err != nil {
		t.Fatal(err)
	}
	ours, err := b.ourTrash(ctx, false)
	if err != nil || len(ours) != 1 {
		t.Fatalf("the run's trash = %+v, %v; want the one part it took", ours, err)
	}
	if where := b.whereLeft(ctx); !strings.Contains(where, "the trash holds 1 of the book's files") {
		t.Errorf("where the run left the book = %q, want the one part it took counted", where)
	}
}

// A library flagged read-only once the trash started is waited out, not
// refused for good: lifting the flag lets the run finish.
func TestAReadOnlyFlagAfterTheTrashStartedIsWaitedOut(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() { trashAs(t, ctx, svc, taskTypeBookMerge, parts[0]) })
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	flagReadOnly(t, ctx, svc, true)
	err = attempt(t, ctx, svc, 2)
	var wait *toolRetry
	if !errors.As(err, &wait) {
		t.Fatalf("the rerun on a read-only library = %v, want it waiting", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 1 {
		t.Errorf("hidden copies = %q, want the output kept", left)
	}
	flagReadOnly(t, ctx, svc, false)
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("the rerun once the flag went = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// flagReadOnly sets every library's read-only flag.
func flagReadOnly(t *testing.T, ctx context.Context, svc *Library, on bool) {
	t.Helper()
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if _, err := svc.lib.SetLibraryReadOnly(ctx, lib.PID, on); err != nil {
			t.Fatal(err)
		}
	}
	svc.refreshLibraryState(ctx)
}

// A part the catalog has that is not on disk where it has it, as the
// trash leaves one a crash cut between its move and its record, stops the
// merge after a few waits: what its trash took comes back, and its
// output, which holds that part's audio, stays and is named, with where
// to look for the part.
func TestAPartMissingFromItsPlaceStopsTheMergeKeepingItsOutput(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	cd2 := filepath.Join(dir, "CD2", "part 2.m4b")
	svc.toolStepHook = stopAt("trashing", func() {
		trashAs(t, ctx, svc, taskTypeBookMerge, parts[0])
		stranded := filepath.Join(filepath.Dir(filepath.Dir(dir)), model.TrashDirName, "lost", "part 2.m4b")
		if err := os.MkdirAll(filepath.Dir(stranded), 0o755); err != nil {
			t.Error(err)
		}
		if err := os.Rename(cd2, stranded); err != nil {
			t.Error(err)
		}
	})
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	var err error
	for n := 2; n <= 2+toolStrandWaits; n++ {
		err = attempt(t, ctx, svc, n)
		var wait *toolRetry
		if !errors.As(err, &wait) {
			break
		}
	}
	if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), model.TrashDirName) ||
		!strings.Contains(err.Error(), "CD2/part 2.m4b") || !strings.Contains(err.Error(), "the merged book waits") {
		t.Fatalf("the merge = %v, want it stopped naming the part, where to look, and its output", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 1 {
		t.Errorf("hidden copies = %q, want the output kept", left)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash = %q, want what the run took put back", trash)
	}
}

// A run that stopped after it recorded itself and before the task was
// recorded done is not recorded twice.
func TestARunRecordedBeforeItsTaskWasDoneIsRecordedOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("audited", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once recorded", err)
	}
	svc.toolStepHook = nil
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}
