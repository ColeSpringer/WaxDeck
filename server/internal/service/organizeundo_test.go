package service

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// auditDetail is the newest audit row of action, which has to exist.
func auditDetail(t *testing.T, ctx context.Context, svc *Library, action string) map[string]any {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: action}, "", 10)
	if err != nil || len(page.Events) == 0 {
		t.Fatalf("audit %s = %+v (%v), want a row", action, page.Events, err)
	}
	return page.Events[0].Detail
}

// An apply runs as a catalog job and answers it; the history lists the
// run, undoable, under the profile it laid out by, and its starter hears
// of it by the job.
func TestApplyAnswersItsJobAndHistoryListsIt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, _ := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Moved != 1 || !strings.HasPrefix(rep.JobPID, PrefixJob+"-") {
		t.Fatalf("apply = %+v (%v), want the track moved by a job", rep, err)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("the track is still where it was (%v)", err)
	}
	runs, _, err := svc.OrganizeHistory(ctx, uc, "", 10)
	if err != nil || len(runs) != 1 {
		t.Fatalf("history = %+v (%v), want the one run", runs, err)
	}
	if r := runs[0]; r.JobPID != rep.JobPID || r.Kind != "organize" || r.State != string(model.JobDone) ||
		r.Committed != 1 || !r.Undoable || r.Profile != organize.DefaultProfileName || r.StartedAt.IsZero() {
		t.Fatalf("run = %+v, want the apply's job, done and undoable", r)
	}
	if d := auditDetail(t, ctx, svc, "organize.apply"); d["jobPid"] != rep.JobPID || d["moved"] != float64(1) {
		t.Errorf("audit = %v, want the apply recorded with its job", d)
	}
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != rep.JobPID {
		t.Errorf("inbox = %+v, want the apply's job", row)
	}
}

// An undo moves the files back as a job of its own, which the history
// lists in turn and the job list reads like an organize run's.
func TestAnUndoMovesFilesBackAndIsListedInTurn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v)", rep, err)
	}
	undo, err := svc.UndoOrganize(ctx, uc, rep.JobPID)
	if err != nil || undo.Moved != 1 || undo.JobPID == "" || undo.JobPID == rep.JobPID {
		t.Fatalf("undo = %+v (%v), want the track moved back by a job of its own", undo, err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track is not back: %v", err)
	}
	_, bare, _ := parseAPIPID(pid)
	if it, err := svc.lib.Get(ctx, bare); err != nil || string(it.Path) != path {
		t.Fatalf("the catalog has the track at %v (%v), want %s", it, err, path)
	}
	runs, _, err := svc.OrganizeHistory(ctx, uc, "", 10)
	if err != nil || len(runs) != 2 {
		t.Fatalf("history = %+v (%v), want the run and its undo", runs, err)
	}
	if r := runs[0]; r.JobPID != undo.JobPID || r.Kind != "organize-undo" || r.Profile != "" || r.Committed != 1 || !r.Undoable {
		t.Fatalf("newest run = %+v, want the undo, undoable in turn", r)
	}
	if runs[1].JobPID != rep.JobPID {
		t.Fatalf("older run = %+v, want the apply", runs[1])
	}
	if d := auditDetail(t, ctx, svc, "organize.undo"); d["jobPid"] != undo.JobPID || d["undoneJob"] != rep.JobPID ||
		d["moved"] != float64(1) {
		t.Errorf("audit = %v, want the undo recorded with both jobs", d)
	}
	job, err := svc.JobStatus(ctx, undo.JobPID)
	if err != nil || job.Kind != "organize-undo" || job.Organize == nil || job.Organize.Moved != 1 {
		t.Fatalf("job = %+v (%v), want the undo's tally", job, err)
	}
	if job.Target == nil || job.Target.Type != "job" || job.Target.PID != rep.JobPID {
		t.Errorf("target = %+v, want the run it undid", job.Target)
	}
}

// The path rule is re-checked for what an apply moved, so its rows drop
// without waiting for the next sweep.
func TestApplyRechecksThePathRule(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if counts, err := svc.db.HealthRuleCounts(ctx); err != nil || counts[rulePathMismatch] != 1 {
		t.Fatalf("path-mismatch = %d (%v), want the misplaced track", counts[rulePathMismatch], err)
	}
	if _, err := svc.ApplyOrganize(ctx, uc, "", nil); err != nil {
		t.Fatal(err)
	}
	if counts, err := svc.db.HealthRuleCounts(ctx); err != nil || counts[rulePathMismatch] != 0 {
		t.Fatalf("path-mismatch = %d (%v), want the moved track off the rule", counts[rulePathMismatch], err)
	}
}

// An undo meeting a scan that holds the file-mutation scope is told the
// catalog is busy, which clears on its own; once the scan ends the same
// undo lands.
func TestUndoWhileAScanHoldsTheLeaseIsCatalogBusy(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, stray := fillerLibrary(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", []string{stray})
	if err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v)", rep, err)
	}
	scan := startForcedRescan(t, ctx, svc)
	if _, err := svc.UndoOrganize(ctx, uc, rep.JobPID); KindOf(err) != KindCatalogBusy {
		t.Fatalf("undo during the rescan = %v, want catalog-busy", err)
	}
	waitForEnd(t, ctx, svc, scan)
	if undo, err := svc.UndoOrganize(ctx, uc, rep.JobPID); err != nil || undo.Moved != 1 {
		t.Fatalf("undo after the rescan = %+v (%v), want the stray moved back", undo, err)
	}
}

// An undo is refused before anything moves for a job that is no organize
// run, one that cannot be found, a read-only server and a non-admin.
func TestAnUndoRefusesWhatItCannotUndo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, _ := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, pid := range []string{"jb-nope", apiPID(PrefixJob, model.NewPID()), apiPID(PrefixTrack, model.NewPID())} {
		if _, err := svc.UndoOrganize(ctx, uc, pid); KindOf(err) != KindNotFound {
			t.Errorf("undo of %s = %v, want not-found", pid, err)
		}
	}
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scan)
	if _, err := svc.UndoOrganize(ctx, uc, apiPID(PrefixJob, scan)); KindOf(err) != KindInvalid {
		t.Errorf("undo of a scan = %v, want invalid", err)
	}
	if _, err := svc.UndoOrganize(ctx, &UserCtx{ID: "listener"}, rep.JobPID); KindOf(err) != KindForbidden {
		t.Errorf("undo by a listener = %v, want forbidden", err)
	}
	if _, _, err := svc.OrganizeHistory(ctx, &UserCtx{ID: "listener"}, "", 10); KindOf(err) != KindForbidden {
		t.Errorf("history for a listener = %v, want forbidden", err)
	}
	setServerReadOnly(t, ctx, svc, true)
	if _, err := svc.UndoOrganize(ctx, uc, rep.JobPID); KindOf(err) != KindReadOnly {
		t.Errorf("undo on a read-only server = %v, want read-only", err)
	}
	if _, err := os.Stat(path); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("a refused undo moved the track back (%v)", err)
	}
}

// The scheduled prune keeps a run inside the task retention window, and
// with it the run's undo.
func TestThePruneKeepsAnOrganizeRunInsideTheWindow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if runs, _, err := svc.OrganizeHistory(ctx, uc, "", 10); err != nil || len(runs) != 1 || runs[0].JobPID != rep.JobPID {
		t.Fatalf("history after the prune = %+v (%v), want the run kept", runs, err)
	}
	if _, err := svc.UndoOrganize(ctx, uc, rep.JobPID); err != nil {
		t.Fatalf("undo after the prune = %v", err)
	}
}

// A history read with no limit lists every run, on one page.
func TestAnOrganizeHistoryWithNoLimitListsEveryRun(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	runs, next, err := svc.OrganizeHistory(ctx, uc, "", 0)
	if err != nil || len(runs) != 1 || runs[0].JobPID != rep.JobPID || next != "" {
		t.Fatalf("history = %+v (next %q, %v), want the one run and no cursor", runs, next, err)
	}
}
