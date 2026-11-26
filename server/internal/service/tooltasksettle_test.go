package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// diedStaging is an acquisition of three whose run died once two of them
// staged, before their entries opened.
func diedStaging(t *testing.T) (context.Context, *Library, *UserCtx, string) {
	t.Helper()
	src := &stagingSource{}
	src.answerThree(func(context.Context) error { panic("the run died") })
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("the run did not die")
			}
		}()
		drainOnce(t, ctx, svc)
	}()
	if n := uploadsWithoutEntry(t, ctx, svc); n != 2 {
		t.Fatalf("%d staged downloads without an entry after the run died, want the two it staged", n)
	}
	return ctx, svc, uc, task.ID
}

// listsEntries fails unless the task lists n entries and no staged download
// is left without one.
func listsEntries(t *testing.T, ctx context.Context, svc *Library, id string, n int) {
	t.Helper()
	row := storedTask(t, ctx, svc, id)
	var results []string
	if err := json.Unmarshal([]byte(row.ResultPIDs), &results); err != nil {
		t.Fatal(err)
	}
	if left := uploadsWithoutEntry(t, ctx, svc); left != 0 || len(results) != n {
		t.Fatalf("task = %s listing %v with %d downloads still without an entry; want %d listed and none left",
			row.State, results, left, n)
	}
	if row.SettlePending {
		t.Errorf("task %s still reads its settle pending", row.State)
	}
}

// An acquisition its attempts ran out on, whose last run died after
// staging, opens the entries of what that run staged as it is failed, and
// lists them.
func TestARetiredAcquisitionOpensWhatItsLastRunStaged(t *testing.T) {
	t.Parallel()
	ctx, svc, _, id := diedStaging(t)
	spendAttempts(t, ctx, svc, id, toolTaskMaxAttempts)
	svc.Tools.retireExhaustedToolTasks(ctx, time.Now().Add(time.Hour).UnixNano())
	if row := storedTask(t, ctx, svc, id); row.State != taskStateFailed {
		t.Fatalf("task = %s, want it retired", row.State)
	}
	listsEntries(t, ctx, svc, id, 2)
}

// A cancel whose settle the process died in, after the state change and
// before the entries opened, is finished by the startup pass: what staged
// gets its entries, which the task lists.
func TestTheStartupPassOpensACanceledAcquisitionsEntries(t *testing.T) {
	t.Parallel()
	ctx, svc, _, id := diedStaging(t)
	// The process dies right after the state change.
	if ok, err := svc.db.SettleToolTaskCanceled(ctx, id, time.Now().UnixNano(), "[]", ""); err != nil || !ok {
		t.Fatalf("settle = %v, %v", ok, err)
	}
	if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
		t.Fatal(err)
	}
	if row := storedTask(t, ctx, svc, id); row.State != taskStateCanceled {
		t.Fatalf("task = %s, want it canceled", row.State)
	}
	listsEntries(t, ctx, svc, id, 2)
	// Again, as the next start would: nothing more.
	if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
		t.Fatal(err)
	}
	listsEntries(t, ctx, svc, id, 2)
}

// stagedThenCanceled is a split of the chaptered fixture's book whose run
// stopped with a piece staged, canceled by a settle the process died in
// right after the state change, before the discard.
func stagedThenCanceled(t *testing.T) (ctx context.Context, svc *Library, uc *UserCtx, id, dir, bookPID string) {
	t.Helper()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	bookPID = apiPID(PrefixBook, book)
	task, err := svc.Tools.StartBookSplit(ctx, uc, bookPID, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = stopAt("staging", nil)
	if err := attempt(t, ctx, svc, 1); err == nil {
		t.Fatal("the attempt finished, want it stopped once a piece is staged")
	}
	svc.Tools.toolStepHook = nil
	if len(hiddenLeft(t, dir)) == 0 {
		t.Fatal("the stopped split staged nothing")
	}
	if ok, err := svc.db.SettleToolTaskCanceled(ctx, task.ID, time.Now().UnixNano(), "[]", ""); err != nil || !ok {
		t.Fatalf("settle = %v, %v", ok, err)
	}
	return ctx, svc, uc, task.ID, dir, bookPID
}

// A canceled split whose settle died before its discard is cleared by
// removing what it staged, never by naming it into the book's folder, even
// with the book's file moved since.
func TestAClearOfACancelCutShortNamesNothingIntoTheBook(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, id, dir, _ := stagedThenCanceled(t)
	away := filepath.Join(filepath.Dir(dir), "Elsewhere")
	if err := os.MkdirAll(away, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(dir, "The Chaptered Fixture.m4b"), filepath.Join(away, "The Chaptered Fixture.m4b")); err != nil {
		t.Fatal(err)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing the canceled split: %v", err)
	}
	if names := namesIn(t, dir); len(names) != 0 {
		t.Errorf("clearing left %q in the book's folder, want the canceled run's pieces removed", names)
	}
}

// The startup pass finishes a canceled split's settle the process died in:
// what it staged goes, and its book is free for another split.
func TestTheStartupPassDiscardsACanceledSplitAndFreesItsBook(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, id, dir, book := stagedThenCanceled(t)
	if _, err := svc.Tools.StartBookSplit(ctx, uc, book, false); KindOf(err) != KindConflict {
		t.Fatalf("a second split before the startup pass = %v, want it refused for the canceled one", err)
	}
	if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
		t.Fatal(err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("the startup pass left %v in the book's folder", left)
	}
	row := storedTask(t, ctx, svc, id)
	if row.State != taskStateCanceled || row.LockKey != "" || row.Error != "" || row.SettlePending {
		t.Fatalf("task = %s holding %q (error %q, pending %v), want it canceled, its book free",
			row.State, row.LockKey, row.Error, row.SettlePending)
	}
	if p := taskParamsOf(&row); !p.Discarded {
		t.Errorf("the discard is not recorded")
	}
	if _, err := svc.Tools.StartBookSplit(ctx, uc, book, false); err != nil {
		t.Fatalf("a second split after the startup pass = %v, want it queued", err)
	}
}

// unsettle marks a task's settle unfinished, as a stop after its last
// step and before its marker ended leaves it.
func unsettle(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET settle_pending = 1 WHERE id = ?`, id); err != nil {
		t.Fatal(err)
	}
}

// A download its attempts ran out on, whose retire the process died in
// right after the state change, tells its starter at the next start, and
// once however often a start finds the settle unfinished.
func TestTheStartupPassTellsARetiredDownloadsStarterOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, id := diedStaging(t)
	spendAttempts(t, ctx, svc, id, toolTaskMaxAttempts)
	if ids, err := svc.db.FailExhaustedToolTasks(ctx, time.Now().Add(time.Hour).UnixNano(), toolTaskMaxAttempts, nil); err != nil || len(ids) != 1 {
		t.Fatalf("retired = %v, %v", ids, err)
	}
	for pass := 1; pass <= 2; pass++ {
		if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 1 || rows[0].TargetPID != id {
			t.Fatalf("start %d: failure notices %+v, want the one for the retired download", pass, rows)
		}
		listsEntries(t, ctx, svc, id, 2)
		unsettle(t, ctx, svc, id)
	}
}

// A canceled import whose settle the process died in right after the
// state change drops its sealed credentials and is on the record at the
// next start, once however often a start finds the settle unfinished.
func TestTheStartupPassFinishesACanceledImportsEnd(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	dto, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: "http://old-box.example:4533", Username: "demo", Password: "demo-pass",
	})
	if err != nil {
		t.Fatal(err)
	}
	if row := storedTask(t, ctx, f.svc, dto.ID); !strings.Contains(row.Params, "secretSealed") {
		t.Fatalf("params %s, want the sealed credentials", row.Params)
	}
	if ok, err := f.svc.db.SettleToolTaskCanceled(ctx, dto.ID, time.Now().UnixNano(), "[]", ""); err != nil || !ok {
		t.Fatalf("settle = %v, %v", ok, err)
	}
	for pass := 1; pass <= 2; pass++ {
		if err := f.svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		row := storedTask(t, ctx, f.svc, dto.ID)
		if strings.Contains(row.Params, "secretSealed") || row.SettlePending {
			t.Fatalf("start %d: params %s (pending %v), want the credentials dropped and the settle ended", pass, row.Params, row.SettlePending)
		}
		if runs := migrationRuns(t, ctx, f); len(runs) != 1 || runs[0].Detail["canceled"] != true {
			t.Fatalf("start %d: migration.run entries %+v, want the one canceled run", pass, runs)
		}
		unsettle(t, ctx, f.svc, dto.ID)
	}
}

// awaitClose fails the test unless ch closes within a few seconds.
func awaitClose(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(10 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
	}
}

// One task's settle never waits behind another's.
func TestASettleWaitsForNoOtherTask(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	// Set before any task can settle, so whichever settle of the first
	// task enters (this test's, or a startup pass's) holds it.
	var (
		mu      sync.Mutex
		blocked string
		once    sync.Once
	)
	entered, release := make(chan struct{}), make(chan struct{})
	var released sync.Once
	let := func() { released.Do(func() { close(release) }) }
	// A failed wait still lets a held settle go, so the fixture can close.
	defer let()
	svc.Tools.settleHook = func(id string) {
		mu.Lock()
		hold := id == blocked
		mu.Unlock()
		if hold {
			once.Do(func() { close(entered) })
			<-release
		}
	}
	var ids []string
	for i, link := range []string{"https://tube.example/watch?v=one", "https://tube.example/watch?v=two"} {
		task, err := svc.Ingest.StartAcquisition(ctx, uc, link, false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		if i == 0 {
			mu.Lock()
			blocked = task.ID
			mu.Unlock()
		}
		if ok, err := svc.db.SettleToolTaskCanceled(ctx, task.ID, time.Now().UnixNano(), "[]", ""); err != nil || !ok {
			t.Fatalf("settle = %v, %v", ok, err)
		}
		ids = append(ids, task.ID)
	}
	first := make(chan struct{})
	go func() {
		defer close(first)
		svc.Tools.finishSettle(ctx, ids[0])
	}()
	awaitClose(t, entered, "the first task's settle to start")
	second := make(chan struct{})
	go func() {
		defer close(second)
		svc.Tools.finishSettle(ctx, ids[1])
	}()
	select {
	case <-second:
	case <-time.After(5 * time.Second):
		t.Error("the second task's settle waited behind the first's")
	}
	let()
	awaitClose(t, first, "the first task's settle to end")
	awaitClose(t, second, "the second task's settle to end")
	for _, id := range ids {
		if row := storedTask(t, ctx, svc, id); row.SettlePending {
			t.Errorf("task %s still reads its settle pending", id)
		}
	}
}

// An acquisition whose next run fails before it begins, its account gone,
// opens the entries of what the run before it staged as it fails, and
// lists them.
func TestAnAcquisitionFailingBeforeItsRunOpensWhatItStaged(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, id := diedStaging(t)
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE users SET disabled = 1 WHERE id = ?`, uc.ID); err != nil {
		t.Fatal(err)
	}
	drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
	if row := storedTask(t, ctx, svc, id); row.State != taskStateFailed {
		t.Fatalf("task = %s (error %q), want it failed for its account", row.State, row.Error)
	}
	listsEntries(t, ctx, svc, id, 2)
}

// A canceled split whose settle ended without its discard recorded (the
// save failed) is cleared by removing what it staged, never by naming it
// into the book's folder, even with the book's file moved since.
func TestAClearOfACanceledSplitWhoseDiscardWentUnrecordedNamesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, id, dir, _ := stagedThenCanceled(t)
	if err := svc.db.EndToolTaskSettle(ctx, id); err != nil {
		t.Fatal(err)
	}
	if row := storedTask(t, ctx, svc, id); taskParamsOf(&row).Discarded || row.SettlePending {
		t.Fatalf("task = %+v, want its settle ended with no discard recorded", row)
	}
	away := filepath.Join(filepath.Dir(dir), "Elsewhere")
	if err := os.MkdirAll(away, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(dir, "The Chaptered Fixture.m4b"), filepath.Join(away, "The Chaptered Fixture.m4b")); err != nil {
		t.Fatal(err)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing the canceled split: %v", err)
	}
	if names := namesIn(t, dir); len(names) != 0 {
		t.Errorf("clearing left %q in the book's folder, want the canceled run's pieces removed", names)
	}
}

// taskEnds are the audit entries of action that name task id and carry
// key, which only the entry for its end does.
func taskEnds(t *testing.T, ctx context.Context, svc *Library, action, id, key string) []AuditEventDTO {
	t.Helper()
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: action}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var out []AuditEventDTO
	for _, e := range page.Events {
		if _, ok := e.Detail[key]; ok && e.Detail["task"] == id {
			out = append(out, e)
		}
	}
	return out
}

// A canceled catalog repair whose settle a start finds unfinished is on
// the record once, and gives the catalog reset it owed once, however
// often a start finds it so.
func TestTheStartupPassEndsACanceledRepairOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	var taskID string
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairArt {
			cancelTask(t, ctx, svc, uc, taskID)
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	taskID = task.ID
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	if ends := taskEnds(t, ctx, svc, "catalog.repair", task.ID, "state"); len(ends) != 1 {
		t.Fatalf("catalog.repair entries %+v after the cancel, want its one end", ends)
	}
	since := snapshotSince(t, ctx, svc, uc)
	for pass := 1; pass <= 2; pass++ {
		unsettle(t, ctx, svc, task.ID)
		if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		if ends := taskEnds(t, ctx, svc, "catalog.repair", task.ID, "state"); len(ends) != 1 {
			t.Fatalf("start %d: catalog.repair entries %+v, want the one end", pass, ends)
		}
		if retired(t, ctx, svc, uc, since) {
			t.Fatalf("start %d: the repair's reset was given again", pass)
		}
	}
}

// A path fix its attempts ran out on, whose retire the process died in
// right after the state change, is on the record and tells its starter
// at the next start, once each however often a start finds the settle
// unfinished.
func TestTheStartupPassEndsARetiredPathFixOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.Health.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	spendAttempts(t, ctx, svc, start.TaskID, toolTaskMaxAttempts)
	if ids, err := svc.db.FailExhaustedToolTasks(ctx, time.Now().Add(time.Hour).UnixNano(), toolTaskMaxAttempts, nil); err != nil || len(ids) != 1 {
		t.Fatalf("retired = %v, %v", ids, err)
	}
	for pass := 1; pass <= 2; pass++ {
		if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		if ends := taskEnds(t, ctx, svc, "health.fix", start.TaskID, "moved"); len(ends) != 1 {
			t.Fatalf("start %d: health.fix end entries %+v, want the one", pass, ends)
		}
		if rows := inboxOf(t, ctx, svc, uc, "health-fix-finished"); len(rows) != 1 || rows[0].TargetPID != start.TaskID {
			t.Fatalf("start %d: fix notices %+v, want the one for the retired fix", pass, rows)
		}
		unsettle(t, ctx, svc, start.TaskID)
	}
}

// unfinishRunEnd marks a task's own end unfinished (settle_pending 2), as
// a stop after its run's terminal write and before its last end step
// leaves it.
func unfinishRunEnd(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET settle_pending = 2 WHERE id = ?`, id); err != nil {
		t.Fatal(err)
	}
}

// A download whose run failed, the process stopping right after the run
// recorded the failure, tells its starter at the next start, once however
// often a start finds its end unfinished, and the start takes only the
// end's steps: the failure the run recorded stays as it wrote it.
func TestTheStartupPassFinishesAFailedRunsEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, svc, task.ID)
	row.State, row.Error, row.FinishedAtNS = taskStateFailed, "the source refused it", time.Now().UnixNano()
	// The run's terminal write, and then the stop.
	if err := svc.db.FinishToolTask(ctx, row); err != nil {
		t.Fatal(err)
	}
	if got := storedTask(t, ctx, svc, task.ID); !got.SettlePending {
		t.Fatal("the run's terminal write left no marker")
	}
	for pass := 1; pass <= 2; pass++ {
		if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 1 || rows[0].TargetPID != task.ID {
			t.Fatalf("start %d: failure notices %+v, want the one for the failed download", pass, rows)
		}
		got := storedTask(t, ctx, svc, task.ID)
		if got.State != taskStateFailed || got.SettlePending || got.Summary != row.Summary || got.ResultPIDs != row.ResultPIDs {
			t.Fatalf("start %d: task = %s (pending %v) with summary %s and results %s, want it failed as its run recorded it (%s, %s)",
				pass, got.State, got.SettlePending, got.Summary, got.ResultPIDs, row.Summary, row.ResultPIDs)
		}
		unfinishRunEnd(t, ctx, svc, task.ID)
	}
}

// An import whose run finished, the process stopping right after the run
// recorded it done, drops its sealed credentials at the next start.
func TestTheStartupPassFinishesADoneRunsEnd(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	dto, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: "http://old-box.example:4533", Username: "demo", Password: "demo-pass",
	})
	if err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, f.svc, dto.ID)
	if !strings.Contains(row.Params, "secretSealed") {
		t.Fatalf("params %s, want the sealed credentials", row.Params)
	}
	row.State, row.ProgressPct, row.FinishedAtNS = taskStateDone, 100, time.Now().UnixNano()
	if err := f.svc.db.FinishToolTask(ctx, row); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Tools.finishToolTaskSettles(ctx); err != nil {
		t.Fatal(err)
	}
	got := storedTask(t, ctx, f.svc, dto.ID)
	if got.State != taskStateDone || strings.Contains(got.Params, "secretSealed") || got.SettlePending {
		t.Fatalf("task = %s with params %s (pending %v), want it done, the credentials dropped and its end finished",
			got.State, got.Params, got.SettlePending)
	}
}

// A run's failure that meets a cancel's settle of the same task waits for
// it before it opens the task's stranded entries, so the two never open
// them side by side.
func TestAFailureWaitsForTheCancelSettlingItsTask(t *testing.T) {
	t.Parallel()
	ctx, svc, _, id := diedStaging(t)
	entered, release := make(chan struct{}), make(chan struct{})
	var once, released sync.Once
	let := func() { released.Do(func() { close(release) }) }
	defer let()
	svc.Tools.settleHook = func(got string) {
		if got == id {
			once.Do(func() { close(entered) })
			<-release
		}
	}
	running := storedTask(t, ctx, svc, id)
	canceled, failed := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(canceled)
		row := running
		svc.Tools.cancelToolTask(ctx, &row)
	}()
	awaitClose(t, entered, "the cancel's settle to start")
	go func() {
		defer close(failed)
		row := running
		svc.Tools.failToolTask(ctx, &row, fmt.Errorf("%w: the source refused it", errToolPermanent))
	}()
	select {
	case <-failed:
		t.Fatal("the failure ended while the cancel's settle held the task")
	case <-time.After(300 * time.Millisecond):
	}
	if n := uploadsWithoutEntry(t, ctx, svc); n != 2 {
		t.Fatalf("%d staged downloads without an entry while the cancel's settle held the task, want both untouched", n)
	}
	let()
	awaitClose(t, canceled, "the cancel to end")
	awaitClose(t, failed, "the failure to end")
	if row := storedTask(t, ctx, svc, id); row.State != taskStateCanceled {
		t.Fatalf("task = %s, want it canceled", row.State)
	}
	listsEntries(t, ctx, svc, id, 2)
}

// unfinishParkEnd marks a parked task's own end unfinished (settle_pending
// 3), as a stop after its run's park and before its last end step leaves
// it.
func unfinishParkEnd(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET settle_pending = 3 WHERE id = ?`, id); err != nil {
		t.Fatal(err)
	}
}

// failedAudits counts a task's failed book.merge audit entries.
func failedAudits(t *testing.T, ctx context.Context, svc *Library, id string) int {
	t.Helper()
	n := 0
	for _, d := range auditDetails(t, ctx, svc, "book.merge") {
		if d["result"] == "failed" && d["task"] == id {
			n++
		}
	}
	return n
}

// A merge whose run parked it after its trash took the book, the process
// stopping right after the park, has its end taken at the next start, once
// however often a start finds it unfinished: its workspace goes, its
// starter hears it needs attention, and the run is on the record as failed.
func TestTheStartupPassFinishesAParkedRunsEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = stopAt("trashed", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once trashed", err)
	}
	svc.Tools.toolStepHook = nil
	ws := filepath.Join(svc.Ingest.stagingDir, "tools", task.ID)
	if err := os.MkdirAll(ws, 0o755); err != nil {
		t.Fatal(err)
	}
	// The run's park, and then the stop.
	why := "stopped: its last 3 runs ended with the server and never came back"
	if ok, err := svc.db.ParkToolTask(ctx, task.ID, why, time.Now().UnixNano()); err != nil || !ok {
		t.Fatal(err)
	}
	for pass := 1; pass <= 2; pass++ {
		if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Stat(ws); !os.IsNotExist(err) {
			t.Errorf("start %d: the parked task's workspace = %v, want it gone", pass, err)
		}
		rows := inboxOf(t, ctx, svc, uc, "tool-task-failed")
		if len(rows) != 1 || rows[0].TargetPID != task.ID || !strings.Contains(rows[0].Title, "needs attention") {
			t.Fatalf("start %d: notices %+v, want the one saying the merge needs attention", pass, rows)
		}
		if n := failedAudits(t, ctx, svc, task.ID); n != 1 {
			t.Fatalf("start %d: failed book.merge audits = %d, want 1", pass, n)
		}
		row := storedTask(t, ctx, svc, task.ID)
		if row.State != taskStateParked || row.Error != why || row.SettlePending {
			t.Fatalf("start %d: task = %s (error %q, pending %v), want it parked as its run said, its end finished",
				pass, row.State, row.Error, row.SettlePending)
		}
		unfinishParkEnd(t, ctx, svc, task.ID)
	}
}

// A run that parks its task takes the park's end itself: the marker its
// park set ends, with the notice filed and the run audited once.
func TestARunThatParksEndsItsOwnMarker(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	id := parkMerge(t, ctx, svc, uc, book, "trashed")
	if row := storedTask(t, ctx, svc, id); row.SettlePending {
		t.Errorf("the parked task still reads its end pending")
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 1 {
		t.Errorf("notices %+v, want the one", rows)
	}
	if n := failedAudits(t, ctx, svc, id); n != 1 {
		t.Errorf("failed book.merge audits = %d, want 1", n)
	}
}

// A done merge whose end a start finds unfinished keeps what it made: the
// start takes the end's steps only, never a retire's discard.
func TestTheStartupPassLeavesADoneMergeAsItIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatal(err)
	}
	done := storedTask(t, ctx, svc, task.ID)
	if done.State != taskStateDone || done.SettlePending {
		t.Fatalf("task = %s (error %q, pending %v), want it done, its end finished", done.State, done.Error, done.SettlePending)
	}
	before := namesIn(t, dir)
	unfinishRunEnd(t, ctx, svc, task.ID)
	if err := svc.Tools.finishToolTaskSettles(ctx); err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateDone || row.SettlePending || taskParamsOf(&row).Discarded || row.Params != done.Params {
		t.Fatalf("task = %s (pending %v) with params %s, want it done as its run left it (%s)",
			row.State, row.SettlePending, row.Params, done.Params)
	}
	if after := namesIn(t, dir); fmt.Sprint(after) != fmt.Sprint(before) {
		t.Errorf("the book's folder holds %q after the start, want %q as the merge left it", after, before)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("the done merge filed %+v, want no failure notice", rows)
	}
}

// A park whose write matched no row (the task left running meanwhile, a
// cancel for one) ends nothing: no notice, no audit, the row as it was.
func TestAParkThatMatchedNoRowEndsNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.toolStepHook = stopAt("staged", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once staged", err)
	}
	svc.Tools.toolStepHook = nil
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	row := storedTask(t, ctx, svc, task.ID)
	// The row leaves running before the run's park lands.
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET state = 'canceled' WHERE id = ?`, task.ID); err != nil {
		t.Fatal(err)
	}
	p := taskParamsOf(&row)
	b, err := svc.Tools.bookToolFor(ctx, &row, &p)
	if err != nil {
		t.Fatal(err)
	}
	if err := b.begin(ctx, b.whereEnded); err == nil {
		t.Fatal("begin went on, want the run stopped")
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("a park that matched no row filed %+v", rows)
	}
	if n := failedAudits(t, ctx, svc, task.ID); n != 0 {
		t.Errorf("failed book.merge audits = %d, want none", n)
	}
	if got := storedTask(t, ctx, svc, task.ID); got.State != taskStateCanceled || got.SettlePending {
		t.Errorf("task = %s (pending %v), want it canceled as it was", got.State, got.SettlePending)
	}
}
