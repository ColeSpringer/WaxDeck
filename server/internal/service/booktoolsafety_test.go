package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// taskParams reads a task's recorded params.
func taskParams(t *testing.T, ctx context.Context, svc *Library, id string) toolTaskParams {
	t.Helper()
	var p toolTaskParams
	if err := json.Unmarshal([]byte(toolTaskRow(t, ctx, svc, id).Params), &p); err != nil {
		t.Fatal(err)
	}
	return p
}

// setParams rewrites a task's recorded params through edit.
func setParams(t *testing.T, ctx context.Context, svc *Library, id string, edit func(*toolTaskParams)) {
	t.Helper()
	p := taskParams(t, ctx, svc, id)
	edit(&p)
	if err := svc.db.UpdateToolTaskParams(ctx, id, marshalJSON(p)); err != nil {
		t.Fatal(err)
	}
}

// longWaited records a task as waiting since before the wait cap, so its
// next wait ends it.
func longWaited(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	setParams(t, ctx, svc, id, func(p *toolTaskParams) {
		p.Waits, p.WaitFromNS = 1, time.Now().Add(-toolWaitCap-time.Minute).UnixNano()
	})
}

// busyAlways answers a busy catalog every time op runs.
func busyAlways(op string) func(string) error {
	return func(got string) error {
		if got == op {
			return busyOnce(op)(op)
		}
		return nil
	}
}

// purgeTrash empties the trash for good, as an administrator can.
func purgeTrash(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if _, err := svc.lib.EmptyTrash(ctx, waxbin.EmptyTrashOptions{}); err != nil {
		t.Fatal(err)
	}
}

// An undo whose put-back is blocked while the trash is emptied cannot be
// undone: the run keeps its output, which holds the purged part's audio,
// and finishes the merge instead, never removing that output.
func TestAnUndoWhosePartsLeftTheTrashFinishesTheMergeInstead(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	part1 := filepath.Join(dir, "CD1", "part 1.m4b")
	svc.toolStepHook = stopAt("trashing", func() { trashAs(t, ctx, svc, taskTypeBookMerge, parts[0]) })
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	// The second part's folder refuses the server, which undoes the run;
	// a file of another's at the first part's place blocks its put-back.
	cd2 := filepath.Join(dir, "CD2")
	if err := os.Chmod(cd2, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(cd2, 0o755) })
	if err := os.MkdirAll(filepath.Dir(part1), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(part1, []byte("not the part"), 0o644); err != nil {
		t.Fatal(err)
	}
	err = attempt(t, ctx, svc, 2)
	var wait *toolRetry
	if !errors.As(err, &wait) || taskParams(t, ctx, svc, task.ID).Step != toolStepUndoing {
		t.Fatalf("second attempt = %v, want the undo waiting on its blocked put-back", err)
	}
	purgeTrash(t, ctx, svc)
	if err := os.Chmod(cd2, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("the rerun after the purge = %v, want the merge finished", err)
	}
	done := toolTask(t, ctx, svc, task.ID)
	if done.State != taskStateDone || len(done.ResultPIDs) != 1 {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if data, err := os.ReadFile(part1); err != nil || string(data) != "not the part" {
		t.Errorf("the other file at the first part's place = %q, %v; want it untouched", data, err)
	}
	if !onDisk(filepath.Join(dir, "Tool Book.m4b")) {
		t.Errorf("the merged book is not in %s: %q", dir, namesIn(t, dir))
	}
}

// A catalog read that fails while an undo checks its parts are back is
// no answer: the undo waits it out and finishes undoing, rather than read
// the failure as a part gone for good and finish the merge.
func TestAnUndoWhoseCheckCannotReadTheCatalogWaits(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
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
	// The second part's folder refuses the server, which undoes the run;
	// the undo's check of the book's files meets a busy catalog once.
	cd2 := filepath.Join(dir, "CD2")
	lockFolder(t, cd2)
	svc.mutateHook = busyOnce("files")
	err = attempt(t, ctx, svc, 2)
	var wait *toolRetry
	if p := taskParams(t, ctx, svc, task.ID); !errors.As(err, &wait) || p.Forward || p.Step != toolStepUndoing {
		t.Fatalf("second attempt = %v (forward %v, step %q), want the undo waiting on the read", err, p.Forward, p.Step)
	}
	if err := os.Chmod(cd2, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 3); !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "nothing was written") {
		t.Fatalf("the rerun = %v, want the undo finished, nothing written", err)
	}
	if !onDisk(filepath.Join(dir, "CD1", "part 1.m4b")) || onDisk(filepath.Join(dir, "Tool Book.m4b")) {
		t.Errorf("book folder holds %q, want the part back and no merged book", namesIn(t, dir))
	}
}

// A name the run recorded for an output and never gave it is not the
// run's: when another file holds it by the rerun, the output takes a free
// name and the record lets the first one go, so nothing the run removes
// later can reach the other file.
func TestANameAnotherTookBeforeTheRenameIsLetGo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("trashed", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once trashed", err)
	}
	svc.toolStepHook = nil
	// The run recorded the merged file's name and stopped before the
	// rename; another file took the name since.
	taken := filepath.Join(dir, "Tool Book.m4b")
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) {
		p.Step, p.Names, p.Placed = toolStepPlacing, []string{"Tool Book.m4b"}, []string{taken}
	})
	if err := os.WriteFile(taken, []byte("another's"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want the merge finished", err)
	}
	if p := taskParams(t, ctx, svc, task.ID); slices.Contains(p.Placed, taken) {
		t.Errorf("placed = %q, want the name another holds let go", p.Placed)
	}
	if data, err := os.ReadFile(taken); err != nil || string(data) != "another's" {
		t.Errorf("the other file = %q, %v; want it untouched", data, err)
	}
	if !onDisk(filepath.Join(dir, "Tool Book (2).m4b")) {
		t.Errorf("book folder holds %q, want the merged book under a free name", namesIn(t, dir))
	}
}

// A run removes a file it recorded only when the file is the one it
// wrote: one another put at a recorded name since is left alone.
func TestARunRemovesOnlyTheFilesItWrote(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("staged", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once staged", err)
	}
	svc.toolStepHook = nil
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	p := taskParams(t, ctx, svc, task.ID)
	b, err := svc.bookToolFor(ctx, &row, &p)
	if err != nil {
		t.Fatal(err)
	}
	staged := b.stagedPath(0)
	// Recorded as given its name, the way place records it, but the file
	// under the name is another's.
	theirs := filepath.Join(dir, "Tool Book.m4b")
	b.p.Placed = append(b.p.Placed, theirs)
	id, ok := identOf(staged)
	if !ok {
		t.Fatal("the staged output is not on disk")
	}
	if b.p.Idents == nil {
		b.p.Idents = map[string]fileIdent{}
	}
	b.p.Idents[theirs] = id
	if err := os.WriteFile(theirs, []byte("another's"), 0o644); err != nil {
		t.Fatal(err)
	}
	b.discard()
	if data, err := os.ReadFile(theirs); err != nil || string(data) != "another's" {
		t.Errorf("the other file = %q, %v; want it left alone", data, err)
	}
	if onDisk(staged) {
		t.Errorf("the run's own staged file is still in %q", namesIn(t, dir))
	}
}

// A merge or split of a book an earlier one that did not finish left part
// of in the trash is refused when it is queued, naming the files the trash
// holds: from what remains it would make a book that looks whole without
// them. A clear that gives the earlier run's new files their names makes
// them hold those files, and lifts it.
func TestABookAnEarlierRunLeftPartlyInTheTrashIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() {
		trashAs(t, ctx, svc, taskTypeBookMerge, parts[0])
		// Another file at the part's place blocks its put-back.
		if err := os.WriteFile(filepath.Join(dir, "part 1.m4b"), []byte("not the part"), 0o644); err != nil {
			t.Error(err)
		}
	})
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	// The trash stays busy past the cap: the run ends keeping every file.
	svc.mutateHook = busyAlways("trash")
	longWaited(t, ctx, svc, task.ID)
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	svc.mutateHook = nil
	if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateFailed {
		t.Fatalf("task = %s (error %q), want it failed", got.State, got.Error)
	}
	for name, start := range map[string]func() error{
		"merge": func() error { _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); return err },
		"split": func() error { _, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false); return err },
	} {
		err := start()
		params := RefusalParams(err)
		if params["reason"] != refusalPartsInTrash || !strings.Contains(params["files"], "part 1.m4b") || params["count"] != "1" ||
			!strings.Contains(err.Error(), "did not finish") {
			t.Errorf("%s = %v (params %v), want it refused, naming the part in the trash", name, err, params)
		}
	}
	if err := svc.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing the failed task = %v", err)
	}
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); RefusalParams(err)["reason"] == refusalPartsInTrash {
		t.Errorf("a merge once the clear named the merged file = %v, want it not refused on the part that file holds", err)
	}
}

// Clearing a finished merge or split leaves no hidden output behind: with
// every part in place its hidden files go, and with some of the book in
// the trash they take their names, for the next scan to catalog, so
// nothing is lost. The task's error line says which beforehand, and the
// clear's audit says which it did.
func TestClearingAParkedTaskLeavesNoHiddenOutput(t *testing.T) {
	t.Parallel()
	cleared := func(t *testing.T, ctx context.Context, svc *Library, id string) map[string]any {
		t.Helper()
		for _, d := range auditDetails(t, ctx, svc, "book.merge") {
			if d["task"] == id && d["result"] == "cleared" {
				return d
			}
		}
		t.Fatalf("no audit of the task's clear")
		return nil
	}
	t.Run("every part in place, dismissed", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
		id := parkMerge(t, ctx, svc, uc, book, "staged")
		if e := toolTask(t, ctx, svc, id).Error; !strings.Contains(e, "clearing the task removes") {
			t.Errorf("error %q, want it to say clearing removes the hidden file", e)
		}
		if err := svc.DeleteToolTaskFor(ctx, uc, id); err != nil {
			t.Fatal(err)
		}
		if names := namesIn(t, dir); !slices.Equal(names, []string{"part 1.m4b", "part 2.m4b"}) {
			t.Errorf("book folder holds %q, want the parts alone", names)
		}
		if d := cleared(t, ctx, svc, id); d["outputs"] != "removed" {
			t.Errorf("clear audit = %v, want the outputs removed", d)
		}
	})
	t.Run("part of the book in the trash, swept", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
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
		setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
		if !drainAt(ctx, svc, 2) {
			t.Fatal("the worker found no task")
		}
		if e := toolTask(t, ctx, svc, task.ID).Error; !strings.Contains(e, "clearing the task gives") {
			t.Errorf("error %q, want it to say clearing names the hidden file", e)
		}
		if n, _, err := svc.ClearFinishedToolTasksFor(ctx, uc, ToolTasksMine); err != nil || n != 1 {
			t.Fatalf("clearing finished tasks = %d, %v", n, err)
		}
		if names := namesIn(t, dir); !slices.Equal(names, []string{"Tool Book.m4b", "part 2.m4b"}) {
			t.Errorf("book folder holds %q, want the merged book named beside the part left", names)
		}
		if d := cleared(t, ctx, svc, task.ID); d["outputs"] != "named" {
			t.Errorf("clear audit = %v, want the outputs named", d)
		}
		// The named file holds the part in the trash: no merge of the book
		// is refused on it.
		if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
		if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); RefusalParams(err)["reason"] == refusalPartsInTrash {
			t.Errorf("a merge after the named clear = %v, want it not refused on the part the named file holds", err)
		}
	})
	t.Run("every part in place, pruned", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
		id := parkMerge(t, ctx, svc, uc, book, "staged")
		row, err := svc.db.ToolTaskByID(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		row.FinishedAtNS = time.Now().Add(-72 * time.Hour).UnixNano()
		if err := svc.db.UpdateToolTask(ctx, row); err != nil {
			t.Fatal(err)
		}
		if err := svc.db.SettingSet(ctx, settingTaskRetention, "1", time.Now().UnixNano()); err != nil {
			t.Fatal(err)
		}
		if err := svc.RunPrune(ctx); err != nil {
			t.Fatal(err)
		}
		if _, err := svc.db.ToolTaskByID(ctx, id); !errors.Is(err, wdb.ErrNotFound) {
			t.Fatalf("the parked task = %v, want it pruned", err)
		}
		if names := namesIn(t, dir); !slices.Equal(names, []string{"part 1.m4b", "part 2.m4b"}) {
			t.Errorf("book folder holds %q, want the parts alone", names)
		}
		if d := cleared(t, ctx, svc, id); d["outputs"] != "removed" {
			t.Errorf("clear audit = %v, want the outputs removed", d)
		}
	})
}

// A merge or split that fails, or stops for good, tells whoever started
// it in their inbox, as a failed job does, naming the task and its book.
func TestAFileToolThatFailsOrParksTellsItsStarter(t *testing.T) {
	t.Parallel()
	t.Run("parked", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		id := parkMerge(t, ctx, svc, uc, book, "staged")
		row := waitForInbox(t, ctx, svc, uc, "tool-task-failed")
		// The body names the task and its book: the app heads the row
		// with its own words and shows the body under them.
		if row.TargetPID != id || !strings.Contains(row.Title, "Tool Book") ||
			!strings.HasPrefix(row.Body, "Book merge of Tool Book: ") || !strings.Contains(row.Body, "the merged book waits") {
			t.Errorf("inbox row = %+v, want the parked merge of the book, saying where its file is", row)
		}
	})
	t.Run("failed", func(t *testing.T) {
		t.Parallel()
		skipWithoutUnwritablePaths(t)
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
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
		// The second part's folder refuses the server: the run undoes and
		// fails.
		lockFolder(t, filepath.Join(dir, "CD2"))
		if !drainAt(ctx, svc, 2) {
			t.Fatal("the worker found no task")
		}
		if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateFailed {
			t.Fatalf("task = %s (error %q), want it failed", got.State, got.Error)
		}
		row := waitForInbox(t, ctx, svc, uc, "tool-task-failed")
		if row.TargetPID != task.ID || !strings.HasPrefix(row.Body, "Book merge of Tool Book: ") || !strings.Contains(row.Body, "nothing was written") {
			t.Errorf("inbox row = %+v, want the failed merge of the book and why", row)
		}
	})
}

// The parts a finished merge put in the trash are the merged book's, not
// missing from it: the book takes a split, and the refusal is only for
// files a run that did not finish left there.
func TestABookAFinishedMergeTrashedTheOriginalsOfIsNotRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("merge = %v, want it finished", err)
	}
	done := toolTask(t, ctx, svc, task.ID)
	if done.State != taskStateDone || len(done.ResultPIDs) != 1 {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if _, err := svc.StartBookSplit(ctx, uc, done.ResultPIDs[0], false); err != nil {
		t.Fatalf("a split of the merged book = %v, want it queued", err)
	}
}

// A clear that cannot give the hidden files their names (the folder
// refuses the server) keeps the task, saying so, and records what it did;
// once the folder takes them, the task clears.
func TestAClearThatCannotNameTheHiddenFilesKeepsTheTask(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
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
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	lockFolder(t, dir)
	err = svc.DeleteToolTaskFor(ctx, uc, task.ID)
	if RefusalParams(err)["reason"] != refusalOutputsHidden {
		t.Fatalf("clearing = %v (params %v), want it refused for the hidden file", err, RefusalParams(err))
	}
	if n, k, err := svc.ClearFinishedToolTasksFor(ctx, uc, ToolTasksMine); err != nil || n != 0 || k != 1 {
		t.Fatalf("clear finished = %d cleared, %d kept, %v; want the task kept and counted", n, k, err)
	}
	kept := toolTask(t, ctx, svc, task.ID)
	if kept.State != taskStateParked || !strings.Contains(kept.Error, "could not give") {
		t.Errorf("task = %s (error %q), want it kept, saying why", kept.State, kept.Error)
	}
	var said bool
	for _, d := range auditDetails(t, ctx, svc, "book.merge") {
		if d["task"] == task.ID && d["result"] == "kept" && d["hidden"] != nil {
			said = true
		}
	}
	if !said {
		t.Error("no audit says the clear kept the task and which file stayed hidden")
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing once the folder takes the file = %v", err)
	}
	if !onDisk(filepath.Join(dir, "Tool Book.m4b")) {
		t.Errorf("book folder holds %q, want the merged book named", namesIn(t, dir))
	}
}

// A clear that cannot remove the hidden files (the folder refuses the
// server) keeps the task as one that cannot name them does: it stays,
// saying so, the clear is refused and counted as kept, and its audit is
// written once for the cause, not on every pass of the prune.
func TestAClearThatCannotRemoveTheHiddenFilesKeepsTheTask(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	id := parkMerge(t, ctx, svc, uc, book, "staged")
	lockFolder(t, dir)
	err := svc.DeleteToolTaskFor(ctx, uc, id)
	if params := RefusalParams(err); params["reason"] != refusalOutputsHidden || params["cause"] == "" {
		t.Fatalf("clearing = %v (params %v), want it refused for the hidden file", err, params)
	}
	if n, k, err := svc.ClearFinishedToolTasksFor(ctx, uc, ToolTasksMine); err != nil || n != 0 || k != 1 {
		t.Fatalf("clear finished = %d cleared, %d kept, %v; want the task kept and counted", n, k, err)
	}
	row := toolTaskRow(t, ctx, svc, id)
	row.FinishedAtNS = time.Now().Add(-72 * time.Hour).UnixNano()
	if err := svc.db.UpdateToolTask(ctx, row); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.SettingSet(ctx, settingTaskRetention, "1", time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if err := svc.RunPrune(ctx); err != nil {
			t.Fatal(err)
		}
	}
	kept := toolTask(t, ctx, svc, id)
	if kept.State != taskStateParked || !strings.Contains(kept.Error, "could not remove") {
		t.Errorf("task = %s (error %q), want it kept, saying why", kept.State, kept.Error)
	}
	var audits int
	for _, d := range auditDetails(t, ctx, svc, "book.merge") {
		if d["task"] == id && d["result"] == "kept" {
			audits++
		}
	}
	if audits != 1 {
		t.Errorf("kept audits = %d, want one for the cause, however often the clear was tried", audits)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing once the folder takes it = %v", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("hidden copies left: %q", left)
	}
}

// A failed task kept because its hidden files cannot be named holds its
// book as a parked one does, until it can be cleared: a merge into a
// folder that refuses the server would fail as it did, and the row says
// what to fix.
func TestAKeptFailedTaskHoldsItsBook(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	parts := partFiles(t, ctx, svc, book)
	svc.toolStepHook = stopAt("trashing", func() {
		trashAs(t, ctx, svc, taskTypeBookMerge, parts[0])
		if err := os.WriteFile(filepath.Join(dir, "part 1.m4b"), []byte("not the part"), 0o644); err != nil {
			t.Error(err)
		}
	})
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
	}
	svc.toolStepHook = nil
	svc.mutateHook = busyAlways("trash")
	longWaited(t, ctx, svc, task.ID)
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	svc.mutateHook = nil
	if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateFailed {
		t.Fatalf("task = %s (error %q), want it failed", got.State, got.Error)
	}
	lockFolder(t, dir)
	if err := svc.DeleteToolTaskFor(ctx, uc, task.ID); RefusalParams(err)["reason"] != refusalOutputsHidden {
		t.Fatalf("clearing = %v, want it refused for the hidden file", err)
	}
	_, err = svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if params := RefusalParams(err); params["reason"] != refusalTaskParked || params["task"] != task.ID {
		t.Errorf("a merge while the kept task stands = %v (params %v), want it refused, naming the task", err, params)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteToolTaskFor(ctx, uc, task.ID); err != nil {
		t.Fatalf("clearing once the folder takes the file = %v", err)
	}
	if held, err := svc.db.ToolTaskHolding(ctx, bookToolLock(book)); err != nil || held != "" {
		t.Errorf("the book's lock = %q, %v; want it free once the task is cleared", held, err)
	}
}

// The run's own hidden files are known by their size and time: a mount
// whose inode numbers do not hold still lets the run remove them.
func TestTheRunsOwnHiddenFilesGoWhereInodesDoNotHold(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("staged", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once staged", err)
	}
	svc.toolStepHook = nil
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	p := taskParams(t, ctx, svc, task.ID)
	b, err := svc.bookToolFor(ctx, &row, &p)
	if err != nil {
		t.Fatal(err)
	}
	staged := b.stagedPath(0)
	id, ok := b.p.Idents[staged]
	if !ok {
		t.Fatal("the staged output's identity was not recorded")
	}
	// What a remount of a mount with unstable inode numbers shows.
	id.Ino++
	b.p.Idents[staged] = id
	b.discard()
	if onDisk(staged) {
		t.Errorf("the run's own staged file is still in %q", namesIn(t, dir))
	}
}

// The parts-in-trash refusal names a few of many files and counts the
// rest, so it never runs past what a notice can show.
func TestThePartsInTrashRefusalNamesAFewOfManyFiles(t *testing.T) {
	t.Parallel()
	names := make([]string, 60)
	for i := range names {
		names[i] = fmt.Sprintf("Ada/Book/part %d.m4b", i+1)
	}
	params := RefusalParams(partsInTrashRefusal(names))
	if params["reason"] != refusalPartsInTrash || params["count"] != "60" || params["more"] != "55" ||
		params["files"] != strings.Join(names[:5], ", ") {
		t.Errorf("params = %v, want five named and 55 more of 60", params)
	}
	one := RefusalParams(partsInTrashRefusal(names[:1]))
	if one["count"] != "1" || one["more"] != "0" || one["files"] != names[0] {
		t.Errorf("params = %v, want the one named", one)
	}
}

// A wait that outlasts the cap ends the task safely for its step: before
// the trash its output goes and the book is free again; after the trash
// the parts come back, or where they cannot, every file stays and the
// failure says where; with its outputs in place it ends leaving them for
// the next scan.
func TestAWaitPastTheCapEndsTheTaskSafelyForItsStep(t *testing.T) {
	t.Parallel()
	t.Run("before the trash", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		svc.mutateHook = busyAlways("trash")
		var wait *toolRetry
		if err := attempt(t, ctx, svc, 1); !errors.As(err, &wait) {
			t.Fatalf("first attempt = %v, want it waiting", err)
		}
		longWaited(t, ctx, svc, task.ID)
		err = attempt(t, ctx, svc, 2)
		if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "gave up waiting") || !strings.Contains(err.Error(), "nothing was written") {
			t.Fatalf("the capped attempt = %v, want it ended with nothing written", err)
		}
		if left := hiddenLeft(t, dir); len(left) != 0 {
			t.Errorf("hidden copies left: %q", left)
		}
		if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
			t.Errorf("trash = %q, want nothing moved", trash)
		}
	})
	t.Run("after the trash, put back", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
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
		svc.mutateHook = busyAlways("trash")
		longWaited(t, ctx, svc, task.ID)
		err = attempt(t, ctx, svc, 2)
		if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "put back") {
			t.Fatalf("the capped attempt = %v, want it ended with the part put back", err)
		}
		if got := partFiles(t, ctx, svc, book); len(got) != 2 {
			t.Errorf("the book has %d parts, want both back", len(got))
		}
		if left := hiddenLeft(t, dir); len(left) != 0 {
			t.Errorf("hidden copies left: %q", left)
		}
	})
	t.Run("after the trash, put-back blocked", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		parts := partFiles(t, ctx, svc, book)
		part1 := filepath.Join(dir, "part 1.m4b")
		svc.toolStepHook = stopAt("trashing", func() {
			trashAs(t, ctx, svc, taskTypeBookMerge, parts[0])
			if err := os.WriteFile(part1, []byte("not the part"), 0o644); err != nil {
				t.Error(err)
			}
		})
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("first attempt = %v, want it stopped mid-trash", err)
		}
		svc.toolStepHook = nil
		svc.mutateHook = busyAlways("trash")
		longWaited(t, ctx, svc, task.ID)
		err = attempt(t, ctx, svc, 2)
		if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "the trash holds 1 of the book's files") ||
			!strings.Contains(err.Error(), "the merged book waits") {
			t.Fatalf("the capped attempt = %v, want it ended keeping every file and saying where", err)
		}
		if left := hiddenLeft(t, dir); len(left) != 1 {
			t.Errorf("hidden copies = %q, want the output kept", left)
		}
		if trash := activeTrash(t, ctx, svc); len(trash) != 1 {
			t.Errorf("trash = %q, want the part still there", trash)
		}
	})
	t.Run("placed", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		svc.toolStepHook = stopAt("placed", nil)
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("first attempt = %v, want it stopped once placed", err)
		}
		svc.toolStepHook = nil
		svc.mutateHook = busyAlways("scan")
		longWaited(t, ctx, svc, task.ID)
		err = attempt(t, ctx, svc, 2)
		if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "the next scan of the library will catalog them") {
			t.Fatalf("the capped attempt = %v, want it ended with the files in place", err)
		}
		if !onDisk(filepath.Join(dir, "Tool Book.m4b")) {
			t.Errorf("the merged book left its place: %q", namesIn(t, dir))
		}
		// The merged book holds what the trash took: the next scan makes
		// it the book, which is never refused on its own parts.
		svc.mutateHook = nil
		row := toolTaskRow(t, ctx, svc, task.ID)
		svc.failToolTask(ctx, &row, err)
		splitTheScannedBook(t, ctx, svc, uc)
	})
	t.Run("placed, the scan failing for good", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		svc.toolStepHook = stopAt("placed", nil)
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("first attempt = %v, want it stopped once placed", err)
		}
		svc.toolStepHook = nil
		svc.mutateHook = func(op string) error {
			if op == "scan" {
				return errors.New("the scanner broke")
			}
			return nil
		}
		err = attempt(t, ctx, svc, 2)
		if !errors.Is(err, errToolPermanent) {
			t.Fatalf("second attempt = %v, want the scan failed for good", err)
		}
		svc.mutateHook = nil
		row := toolTaskRow(t, ctx, svc, task.ID)
		svc.failToolTask(ctx, &row, err)
		splitTheScannedBook(t, ctx, svc, uc)
	})
}

// splitTheScannedBook scans the library and queues a split of the one
// book it holds, which nothing an earlier run left noted may refuse.
func splitTheScannedBook(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) {
	t.Helper()
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	merged, _ := theToolBook(t, svc)
	if _, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, merged), false); err != nil {
		t.Errorf("a split of the merged book = %v, want it queued", err)
	}
}

// A run removes only files it recorded making: a file of another's that
// took a name the run recorded stays when the run undoes.
func TestAnUndoRemovesOnlyFilesTheRunMade(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	theirs := filepath.Join(dir, "02 - Middle.m4b")
	svc.toolStepHook = func(step string) error {
		if step != "trashed" {
			return nil
		}
		// Another's file takes the second piece's name, and the third
		// piece goes before it is placed.
		if err := os.WriteFile(theirs, []byte("not a piece"), 0o644); err != nil {
			t.Error(err)
		}
		if err := os.Remove(filepath.Join(dir, fmt.Sprintf(".waxdeck-tool-%s-2", task.ID))); err != nil {
			t.Error(err)
		}
		return nil
	}
	err = attempt(t, ctx, svc, 1)
	if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "put back") {
		t.Fatalf("split = %v, want it undone", err)
	}
	if data, err := os.ReadFile(theirs); err != nil || string(data) != "not a piece" {
		t.Errorf("the other file at a piece's name = %q, %v; want it kept", data, err)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"02 - Middle.m4b", "The Chaptered Fixture.m4b"}) {
		t.Errorf("the book's folder holds %q, want the original back and the other's file", names)
	}
}

// The scan of a run's outputs catalogs them alone, not another file in
// their folder.
func TestABookToolScansOnlyItsOwnOutputs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	stray := filepath.Join(dir, "stray.flac")
	if _, err := fixtures.Generate(dir, fixtures.Spec{Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2100 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nobody"}}); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("merge = %v", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, "Stray").Build(), "")
	if err != nil || len(items) != 0 {
		t.Fatalf("items titled Stray = %d (%v), want the stray file of %s left to the library's own scan", len(items), err, stray)
	}
}

// A part moved by organize since the merge was queued is followed where
// the catalog has it, not read as missing.
func TestAPartMovedSinceTheQueueIsFollowed(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
	})
	misc := filepath.Join(root, "misc")
	toolBook(t, misc, 1)
	toolBook(t, misc, 2)
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, parts := theToolBook(t, svc)
	if parts != 2 {
		t.Fatalf("parts = %d, want two", parts)
	}
	engine := newFakeBookEngine(t)
	svc.SetFlowJobs(engine)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	plan, err := svc.lib.PlanOrganize(ctx, query.New(query.EntityItems).Build(), waxbin.OrganizeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	rep, err := svc.lib.ApplyOrganize(ctx, plan)
	if err != nil || rep.Moved == 0 {
		t.Skipf("organize moved nothing (%+v, %v), so nothing is followed", rep, err)
	}
	if onDisk(filepath.Join(misc, "part 1.m4b")) {
		t.Fatal("the part is still where it was queued")
	}
	moved, err := svc.lib.File(ctx, partFiles(t, ctx, svc, book)[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("merge after the move = %v, want it finished", err)
	}
	done := toolTask(t, ctx, svc, task.ID)
	if done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 2 {
		t.Errorf("trash = %q, want both parts, followed to where they went", trash)
	}
	// The merged book goes where the parts went, not where they were.
	to := filepath.Dir(string(moved.Path))
	if !onDisk(filepath.Join(to, "Tool Book.m4b")) || onDisk(filepath.Join(misc, "Tool Book.m4b")) {
		t.Errorf("the merged book is not beside the moved parts: %s holds %q", to, namesIn(t, to))
	}
}

// A task whose runs kept ending with the server is parked, not run again:
// it says so, is not leased, and keeps the book.
func TestAToolTaskWhoseRunsKeepEndingWithTheServerIsParked(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("staged", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once staged", err)
	}
	svc.toolStepHook = nil
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	parked := toolTask(t, ctx, svc, task.ID)
	if parked.State != taskStateParked || !strings.Contains(parked.Error, "ended with the server") || !strings.Contains(parked.Error, "the merged book waits") {
		t.Fatalf("task = %s (error %q), want it parked, saying why and where its files are", parked.State, parked.Error)
	}
	if _, err := svc.db.LeaseToolTask(ctx, time.Now().Add(time.Hour).UnixNano(), toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{}); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("lease of a parked task = %v, want none", err)
	}
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); RefusalParams(err)["reason"] != refusalTaskParked {
		t.Errorf("a merge of the parked task's book = %v, want it refused", err)
	}
}

// parkMerge queues a merge of book, stops its first run at step, and
// has its next start find three runs that never came back, so the task
// parks.
func parkMerge(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, book model.PID, step string) string {
	t.Helper()
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt(step, nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped at %s", err, step)
	}
	svc.toolStepHook = nil
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	if parked := toolTask(t, ctx, svc, task.ID); parked.State != taskStateParked {
		t.Fatalf("task = %s (error %q), want it parked", parked.State, parked.Error)
	}
	return task.ID
}

// A parked task is finished and failed: it holds its book from another
// merge or split until it is dismissed or swept with the finished tasks,
// and once it is gone the book takes a new merge.
func TestAParkedTaskHoldsItsBookUntilItIsCleared(t *testing.T) {
	t.Parallel()
	for _, clear := range []string{"dismissed", "swept"} {
		t.Run(clear, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
			id := parkMerge(t, ctx, svc, uc, book, "staged")
			parked := toolTask(t, ctx, svc, id)
			if parked.FinishedAtNS == 0 {
				t.Error("the parked task has no finish time, which the retention prune reads")
			}
			if !strings.Contains(parked.Error, ".waxdeck-tool-"+id+"-0") {
				t.Errorf("error %q, want it to name the merged file waiting beside the book", parked.Error)
			}
			if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); RefusalParams(err)["reason"] != refusalTaskParked {
				t.Fatalf("a merge while the parked task stands = %v, want it refused", err)
			}
			switch clear {
			case "dismissed":
				if err := svc.DeleteToolTaskFor(ctx, uc, id); err != nil {
					t.Fatalf("dismissing the parked task = %v", err)
				}
			default:
				if n, _, err := svc.ClearFinishedToolTasksFor(ctx, uc, ToolTasksMine); err != nil || n != 1 {
					t.Fatalf("clearing finished tasks = %d, %v; want the parked one cleared", n, err)
				}
			}
			if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); err != nil {
				t.Fatalf("a merge once the parked task is cleared = %v, want it queued", err)
			}
		})
	}
}

// A task parked after its trash took the book names each file the trash
// holds and the file waiting beside the book, so whoever clears it knows
// what to put right, and is on the record as failed: once it is cleared,
// nothing else would say what the run moved.
func TestATaskParkedAfterItsTrashNamesEveryFileAndIsAudited(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	id := parkMerge(t, ctx, svc, uc, book, "trashed")
	parked := toolTask(t, ctx, svc, id)
	for _, want := range []string{"part 1.m4b", "part 2.m4b", ".waxdeck-tool-" + id + "-0"} {
		if !strings.Contains(parked.Error, want) {
			t.Errorf("error %q, want it to name %s", parked.Error, want)
		}
	}
	var failed int
	for _, d := range auditDetails(t, ctx, svc, "book.merge") {
		if d["result"] == "failed" && d["task"] == id {
			failed++
		}
	}
	if failed != 1 {
		t.Errorf("failed book.merge audits of the task = %d, want 1", failed)
	}
	if _, err := os.Stat(filepath.Join(svc.stagingDir, "tools", id)); !os.IsNotExist(err) {
		t.Errorf("the parked task's workspace = %v, want it gone with the run", err)
	}
}

// The book is said to be in the trash only while a run's trash holds it:
// a merge that keeps the originals, placing its file, has put none there.
func TestOnlyARunWhoseTrashTookTheBookSaysItIsInTheTrash(t *testing.T) {
	t.Parallel()
	for _, keep := range []bool{true, false} {
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, keep)
		if err != nil {
			t.Fatal(err)
		}
		svc.toolStepHook = stopAt("placed", nil)
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("keep %v: first attempt = %v, want it stopped placing", keep, err)
		}
		got, err := svc.GetToolTaskFor(ctx, uc, task.ID)
		if err != nil {
			t.Fatal(err)
		}
		if got.BookInTrash == keep {
			t.Errorf("keep %v: book in the trash = %v, want %v", keep, got.BookInTrash, !keep)
		}
	}
}

// A waiting task says what it waits on and when it tries again, and a
// book whose parts its run took says the book is in the trash until the
// task finishes.
func TestAWaitingBookTaskSaysWhyUntilWhenAndThatTheBookIsInTheTrash(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
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
	svc.mutateHook = busyOnce("trash")
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	got, err := svc.GetToolTaskFor(ctx, uc, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.State != taskStateRunning || got.WaitReason != "catalog-busy" || got.RetryAtNS <= time.Now().UnixNano() || !got.BookInTrash {
		t.Fatalf("task = %+v, want it running, waiting on the busy catalog until later, the book in the trash", got)
	}
	if got.RetryAtNS > time.Now().Add(time.Minute).UnixNano() {
		t.Errorf("retry at %v, want the wait counted from when the run ended", time.Unix(0, got.RetryAtNS))
	}
}
