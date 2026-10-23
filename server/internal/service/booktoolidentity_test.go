package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// bookFileNames are the names of a book's files, in reading order.
func bookFileNames(t *testing.T, ctx context.Context, svc *Library, book model.PID) []string {
	t.Helper()
	bd, err := svc.lib.Book(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, f := range bd.Files {
		file, err := svc.lib.File(ctx, f.FilePID)
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, filepath.Base(string(file.Path)))
	}
	return out
}

// clearAudit is the audit of a merge task's clear.
func clearAudit(t *testing.T, ctx context.Context, svc *Library, id string) map[string]any {
	t.Helper()
	for _, d := range auditDetails(t, ctx, svc, "book.merge") {
		if d["task"] == id && d["result"] == "cleared" {
			return d
		}
	}
	t.Fatalf("no audit of the task's clear")
	return nil
}

// A part put back from the trash is cataloged anew under another file
// pid, and still counts as in place: a merge parked after its trash took
// the book, whose parts were then restored, has its hidden merged copy
// removed when it is cleared, dismissed or pruned, and the book keeps its
// parts alone.
func TestARestoredPartCountsAsInPlaceWhateverItsFilePID(t *testing.T) {
	t.Parallel()
	for _, clear := range []string{"dismissed", "pruned"} {
		t.Run(clear, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
			before := partFiles(t, ctx, svc, book)
			id := parkMerge(t, ctx, svc, uc, book, "trashed")
			entries, err := svc.lib.Trash(ctx, false, 0)
			if err != nil {
				t.Fatal(err)
			}
			if len(entries) != 2 {
				t.Fatalf("trash holds %d entries, want both parts", len(entries))
			}
			for _, e := range entries {
				if err := svc.lib.RestoreTrash(ctx, e.PID); err != nil {
					t.Fatal(err)
				}
			}
			if after := partFiles(t, ctx, svc, book); len(after) != 2 || slices.Contains(after, before[0]) || slices.Contains(after, before[1]) {
				t.Fatalf("part files after the restore = %v (before %v), want both cataloged anew", after, before)
			}
			switch clear {
			case "dismissed":
				if err := svc.DeleteToolTaskFor(ctx, uc, id); err != nil {
					t.Fatal(err)
				}
			default:
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
			}
			if names := namesIn(t, dir); !slices.Equal(names, []string{"part 1.m4b", "part 2.m4b"}) {
				t.Errorf("book folder holds %q, want the parts alone", names)
			}
			if d := clearAudit(t, ctx, svc, id); d["outputs"] != "removed" {
				t.Errorf("clear audit = %v, want the outputs removed", d)
			}
			if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
				t.Fatal(err)
			}
			if names := bookFileNames(t, ctx, svc, book); !slices.Equal(names, []string{"part 1.m4b", "part 2.m4b"}) {
				t.Errorf("book files after the next scan = %q, want its parts alone", names)
			}
		})
	}
}

// An undo whose put-back of a part landed, and which waits before its
// check, finds that part though organize moved it in the wait: the part is
// back, not gone from the trash for good, so the undo ends the run with
// its output removed and the book holding both parts, once each.
func TestAnUndoFindsAPutBackPartThatOrganizeMoved(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
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
	cd2 := filepath.Join(dir, "CD2")
	if err := os.Chmod(cd2, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(cd2, 0o755) })
	svc.mutateHook = busyOnce("files")
	var retry *toolRetry
	if err := attempt(t, ctx, svc, 2); !errors.As(err, &retry) {
		t.Fatalf("second attempt = %v, want it waiting on the busy catalog after the put-back", err)
	}
	svc.mutateHook = nil
	if p := taskParams(t, ctx, svc, task.ID); p.Step != toolStepUndoing {
		t.Fatalf("step = %q, want the run undoing", p.Step)
	}
	moved := filepath.Join(dir, "Moved", "part 1.m4b")
	if err := os.MkdirAll(filepath.Dir(moved), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(dir, "CD1", "part 1.m4b"), moved); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(cd2, 0o755); err != nil {
		t.Fatal(err)
	}
	err = attempt(t, ctx, svc, 3)
	if err == nil || !strings.Contains(err.Error(), "what went to the trash was put back") {
		t.Fatalf("third attempt = %v, want the undo ended, saying the part was put back", err)
	}
	if p := taskParams(t, ctx, svc, task.ID); p.Forward {
		t.Error("the run went on to finish the merge, reading the moved part as gone from the trash")
	}
	if left := hiddenLeft(t, dir); len(left) > 0 {
		t.Errorf("hidden copies left: %v", left)
	}
	if _, err := os.Stat(filepath.Join(dir, "Tool Book.m4b")); err == nil {
		t.Error("the merged book took its name beside the parts")
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if names := bookFileNames(t, ctx, svc, book); len(names) != 2 || names[0] != "part 1.m4b" || names[1] != "part 2.m4b" {
		t.Errorf("book files = %q, want both parts, once each", names)
	}
}

// stopMidTrash queues a merge of the disc fixture's book and stops its
// first run with part 1 alone in the trash, part 1 recorded as part 2
// reads: two parts alike in size, time and all.
func stopMidTrash(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, book model.PID, dir string, discs bool) string {
	t.Helper()
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
	second := filepath.Join(dir, "part 2.m4b")
	if discs {
		second = filepath.Join(dir, "CD2", "part 2.m4b")
	}
	alike, ok := identOf(second)
	if !ok {
		t.Fatal("no part 2 to read")
	}
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.SourceIdents[0] = alike })
	return task.ID
}

// A part never stands in for another, however alike they read: with part
// 1 gone from the trash for good, part 2 does not answer for it, so the
// undo keeps the merged file, part 1's only copy, and the run goes on to
// finish instead.
func TestAnAlikePartDoesNotStandInForOneGoneFromTheTrash(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	id := stopMidTrash(t, ctx, svc, uc, book, dir, true)
	purgeTrash(t, ctx, svc)
	cd2 := filepath.Join(dir, "CD2")
	if err := os.Chmod(cd2, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(cd2, 0o755) })
	err := attempt(t, ctx, svc, 2)
	var wait *toolRetry
	if !errors.As(err, &wait) {
		t.Fatalf("second attempt = %v, want it waiting to finish the merge", err)
	}
	if p := taskParams(t, ctx, svc, id); !p.Forward {
		t.Errorf("step %q, want the run going on to finish: part 1 is gone for good", p.Step)
	}
	if left := hiddenLeft(t, dir); len(left) != 1 {
		t.Errorf("hidden copies = %v, want the merged file kept", left)
	}
}

// A clear with part 1 in the trash and part 2, alike, in place names the
// hidden merged file rather than remove it: part 2 does not answer for
// part 1.
func TestAClearDoesNotTakeAnAlikePartForOneInTheTrash(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	id := stopMidTrash(t, ctx, svc, uc, book, dir, false)
	setParams(t, ctx, svc, id, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	if got := toolTask(t, ctx, svc, id); got.State != taskStateParked {
		t.Fatalf("task = %s (error %q), want it parked", got.State, got.Error)
	}
	if err := svc.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatal(err)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"Tool Book.m4b", "part 2.m4b"}) {
		t.Errorf("book folder holds %q, want the merged book named beside part 2", names)
	}
	if d := clearAudit(t, ctx, svc, id); d["outputs"] != "named" {
		t.Errorf("clear audit = %v, want the outputs named", d)
	}
}

// An undo that put part 2 back, cataloged anew, and then found part 1
// gone from the trash for good goes on to finish: the part it put back
// goes to the trash again before the merged file takes its name, so the
// book holds the merged file alone and plays nothing twice.
func TestAMergeGoingOnAfterAPartialPutBackTrashesWhatCameBack(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("trashed", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped with both parts in the trash", err)
	}
	svc.toolStepHook = nil
	// A failure that stands sends the run to undo.
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) {
		p.Step, p.Failure = toolStepUndoing, "a refusal that stands"
	})
	// Another file holds part 1's place, so only part 2 comes back.
	part1 := filepath.Join(dir, "CD1", "part 1.m4b")
	if err := os.MkdirAll(filepath.Dir(part1), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(part1, []byte("not the part"), 0o644); err != nil {
		t.Fatal(err)
	}
	var retry *toolRetry
	if err := attempt(t, ctx, svc, 2); !errors.As(err, &retry) {
		t.Fatalf("second attempt = %v, want it waiting to put part 1 back", err)
	}
	if !onDisk(filepath.Join(dir, "CD2", "part 2.m4b")) {
		t.Fatal("part 2 was not put back")
	}
	// Part 1 leaves the trash for good: the run can only go on.
	purgeTrash(t, ctx, svc)
	if err := os.Remove(part1); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("third attempt = %v, want the merge finished", err)
	}
	got := toolTask(t, ctx, svc, task.ID)
	if got.State != taskStateDone || len(got.ResultPIDs) != 1 {
		t.Fatalf("task = %s (error %q), results %v; want it done with the merged book", got.State, got.Error, got.ResultPIDs)
	}
	_, merged, _ := parseAPIPID(got.ResultPIDs[0])
	if names := bookFileNames(t, ctx, svc, merged); !slices.Equal(names, []string{"Tool Book.m4b"}) {
		t.Errorf("the merged book holds %q, want the merged file alone", names)
	}
	if onDisk(filepath.Join(dir, "CD2", "part 2.m4b")) {
		t.Error("part 2's put-back copy is still beside the merged file")
	}
	if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeBookMerge}) {
		t.Errorf("trash = %v, want part 2's put-back copy under the merge", trash)
	}
}

// A run that lost a staged output goes back to making its outputs, which
// puts back what its trash took first. A part it put back that organize
// moved before the rest came back is still the part: the run starts over
// from it where it is now, rather than read the book as changed.
func TestARestageStartsOverFromAPutBackPartThatMoved(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("trashed", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped with both parts in the trash", err)
	}
	svc.toolStepHook = nil
	for _, staged := range hiddenLeft(t, dir) {
		if err := os.Remove(staged); err != nil {
			t.Fatal(err)
		}
	}
	// Another file holds part 2's place, so only part 1 comes back.
	part2 := filepath.Join(dir, "CD2", "part 2.m4b")
	if err := os.MkdirAll(filepath.Dir(part2), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(part2, []byte("not the part"), 0o644); err != nil {
		t.Fatal(err)
	}
	var retry *toolRetry
	if err := attempt(t, ctx, svc, 2); !errors.As(err, &retry) {
		t.Fatalf("second attempt = %v, want it waiting to put part 2 back", err)
	}
	if err := os.Remove(part2); err != nil {
		t.Fatal(err)
	}
	moved := filepath.Join(dir, "Moved", "part 1.m4b")
	if err := os.MkdirAll(filepath.Dir(moved), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(dir, "CD1", "part 1.m4b"), moved); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("third attempt = %v, want the merge made again and finished", err)
	}
	got := toolTask(t, ctx, svc, task.ID)
	if got.State != taskStateDone || len(got.ResultPIDs) != 1 {
		t.Fatalf("task = %s (error %q), results %v; want it done with the merged book", got.State, got.Error, got.ResultPIDs)
	}
	_, merged, _ := parseAPIPID(got.ResultPIDs[0])
	if names := bookFileNames(t, ctx, svc, merged); !slices.Equal(names, []string{"Tool Book.m4b"}) {
		t.Errorf("the merged book holds %q, want the merged file alone", names)
	}
}
