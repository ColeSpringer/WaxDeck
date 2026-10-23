package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// A delete the request's own cancellation reaches mid-run still finishes
// and is recorded: a started delete is not cut short with what moved
// left out of the record.
func TestACanceledDeleteFinishesAndIsRecorded(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, tracks := newTrashFixture(t, "Gone")
	tr := tracks["Gone"]
	request, cancel := context.WithCancel(ctx)
	defer cancel()
	svc.deleteApplyHook = func(context.Context) { cancel() }
	res, err := svc.DeleteItems(request, admin, []string{tr.pid}, "trash", false)
	if err != nil || res.Trashed != 1 {
		t.Fatalf("a delete whose request ended mid-run = %+v, %v; want it finished", res, err)
	}
	if _, err := os.Stat(tr.path); !os.IsNotExist(err) {
		t.Fatalf("the file is still in place: %v", err)
	}
	if got := auditDetails(t, ctx, svc, "items.delete"); len(got) != 1 || got[0]["trashed"] != float64(1) {
		t.Fatalf("items.delete audits = %v, want the delete recorded with what moved", got)
	}
}

// A delete whose every file the catalog skipped as it ran, its library
// flagged read-only after the plan, moved nothing, so it is refused and
// recorded as refused rather than answered as done.
func TestADeleteSkippedWholeAsItRanIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, tracks := newTrashFixture(t, "Flagged")
	tr := tracks["Flagged"]
	svc.deleteApplyHook = func(ctx context.Context) {
		libs, err := svc.lib.Libraries(ctx)
		if err != nil {
			t.Error(err)
			return
		}
		for _, lib := range libs {
			if _, err := svc.lib.SetLibraryReadOnly(ctx, lib.PID, true); err != nil {
				t.Error(err)
			}
		}
	}
	if _, err := svc.DeleteItems(ctx, admin, []string{tr.pid}, "trash", false); KindOf(err) != KindReadOnly {
		t.Fatalf("delete = %v (kind %q), want read-only", err, KindOf(err))
	}
	trashFileStillThere(t, tr.path, "the skipped track")
	if got := auditDetails(t, ctx, svc, "items.delete"); len(got) != 0 {
		t.Errorf("items.delete audits = %v, want none for a delete that moved nothing", got)
	}
	if got := auditDetails(t, ctx, svc, "items.delete.refused"); len(got) != 1 {
		t.Errorf("items.delete.refused audits = %v, want the refusal recorded", got)
	}
}

// A resolve whose every move failed for a reason other than a refused
// write is recorded as refused, as the same failure through a delete is.
func TestAnUpgradeThatMovedNothingIsAuditedAsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, paths, pids := twoTrackFixture(t)
	svc.deleteApplyHook = func(context.Context) {
		if err := os.Remove(paths[1]); err != nil {
			t.Error(err)
		}
	}
	if _, err := svc.ResolveUpgrade(ctx, uc, UpgradeResolveDTO{KeepItemPID: pids[0], RemoveItemPIDs: []string{pids[1]}}); KindOf(err) != KindInternal {
		t.Fatalf("resolve of a vanished file = %v (kind %q), want internal", err, KindOf(err))
	}
	if got := auditDetails(t, ctx, svc, "items.delete.refused"); len(got) != 1 || got[0]["reason"] != "quality-upgrade" {
		t.Fatalf("items.delete.refused audits = %v, want the refused resolve recorded", got)
	}
}

// A trashed file whose library the server no longer holds is named by
// its file alone, never by the server's folders.
func TestATrashedFileOfAGoneLibraryIsNamedByItsFile(t *testing.T) {
	t.Parallel()
	_, svc, _ := openEnrichFixture(t, func(*Config) {})
	gone := filepath.Join(string(filepath.Separator), "srv", "gone", "Album", "song.flac")
	if got := svc.trashEntryName(model.TrashEntry{OrigDisplay: gone, LibraryPID: "01ARZ3NDEKTSV4RRFFQ69G5FAV"}); got != "song.flac" {
		t.Fatalf("name = %q, want the file's own name", got)
	}
}

// A permanent delete that removed a file the catalog then failed to let
// go of says so: the file is gone, though the delete counted it failed.
func TestAPermanentDeleteSaysWhenAFileWentButStaysListed(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	here := filepath.Join(dir, "here.flac")
	if err := os.WriteFile(here, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	gone := filepath.Join(dir, "gone.flac")
	if got := stayedWarning(model.DeletePermanent, here, "database is locked"); got != "here.flac stayed: database is locked" {
		t.Errorf("a file still on disk = %q", got)
	}
	if got := stayedWarning(model.DeletePermanent, gone, "database is locked"); !strings.Contains(got, "gone.flac was deleted") ||
		!strings.Contains(got, "still lists it") {
		t.Errorf("a permanent delete's removed file = %q, want it said gone and still listed", got)
	}
	if got := stayedWarning(model.DeleteTrash, gone, "permission denied"); got != "gone.flac stayed: permission denied" {
		t.Errorf("a trash move = %q", got)
	}
}

// A resolve naming every track of a CUE rip moves the rip's file once,
// under the first of them: when the rip's folder refuses it, none of its
// tracks is recorded as removed, though another item's file went.
func TestAPartlyAppliedResolveKeepsEveryTrackOfARipThatStayed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, two, _ := carvedTracks(t, ctx, svc, uc)
	var whole []string
	for _, pid := range fixtureItemPIDs(t, ctx, svc, uc) {
		if pid != one && pid != two {
			whole = append(whole, pid)
		}
	}
	it, err := svc.getVisibleItem(ctx, uc, one)
	if err != nil {
		t.Fatal(err)
	}
	ripDir := filepath.Dir(string(it.Path))
	if err := os.Chmod(ripDir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(ripDir, 0o755) })
	if _, err := svc.ResolveUpgrade(ctx, uc, UpgradeResolveDTO{
		KeepItemPID: whole[0], RemoveItemPIDs: []string{one, two, whole[1]},
	}); err == nil || !strings.Contains(err.Error(), "1 of the files") {
		t.Fatalf("a resolve whose rip stayed answered %v, want the one file that stayed", err)
	}
	got := auditDetails(t, ctx, svc, "items.delete")
	if len(got) != 1 {
		t.Fatalf("records = %v, want one", got)
	}
	if removed, _ := got[0]["removed"].([]any); !slices.Equal(removed, []any{whole[1]}) {
		t.Errorf("removed = %v, want only %s (the rip's tracks %s and %s stayed)", removed, whole[1], one, two)
	}
}
