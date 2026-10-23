package service

import (
	"fmt"
	"os"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A path fix over every mismatched file is an organize pass, previewed
// and applied from the Organize screen: unscoped, it is refused and no
// task is queued.
func TestAnUnscopedPathFixIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	_, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, nil)
	if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), "/organize") {
		t.Fatalf("unscoped path fix = %v, want invalid, pointing at organize", err)
	}
	tasks, _, err := svc.ListToolTasksFor(ctx, uc, "", 10)
	if err != nil || len(tasks) != 0 {
		t.Fatalf("tasks = %+v (%v), want none queued", tasks, err)
	}
}

// A scoped path fix moves its items as an organize job it names, which
// the history lists and an undo takes back.
func TestAScopedPathFixRecordsItsOrganizeJob(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Moved == nil || *sum.Moved != 1 || sum.Attempted != 1 || len(sum.JobPIDs) != 1 {
		t.Fatalf("summary %+v, want the track moved by one named job", sum)
	}
	if _, err := os.Stat(path); err == nil {
		t.Fatal("the track did not move")
	}
	runs, _, err := svc.OrganizeHistory(ctx, uc, "", 10)
	if err != nil || len(runs) != 1 || runs[0].JobPID != sum.JobPIDs[0] || !runs[0].Undoable {
		t.Fatalf("history = %+v (%v), want the fix's job, undoable", runs, err)
	}
	// Audited as the fix, with the runs it made and what they moved.
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "health.fix"}, "", 10)
	if err != nil || len(page.Events) != 2 {
		t.Fatalf("health.fix audit = %+v (%v), want its start and its end", page.Events, err)
	}
	end := page.Events[0].Detail
	if _, ok := end["jobPids"]; !ok {
		end = page.Events[1].Detail
	}
	if end["moved"] != float64(1) || fmt.Sprint(end["jobPids"]) != fmt.Sprint([]any{sum.JobPIDs[0]}) {
		t.Fatalf("health.fix end = %v, want the run it made and the move", end)
	}
	if undo, err := svc.UndoOrganize(ctx, uc, sum.JobPIDs[0]); err != nil || undo.Moved != 1 {
		t.Fatalf("undo = %+v (%v), want the track moved back", undo, err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track is not back: %v", err)
	}
}

// A path fix's news says it moved its items, never that it filled them,
// and words its holds.
func TestAPathFixSaysMovedNotFilled(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, scope := untaggedBesideStrayFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, scope)
	if err != nil {
		t.Fatal(err)
	}
	fixSummary(t, ctx, svc, uc, start.TaskID)
	row := waitForInbox(t, ctx, svc, uc, "health-fix-finished")
	if want := "Moved 1 of 2; 1 held (missing tags 1); 0 failed"; row.Body != want {
		t.Fatalf("body = %q, want %q", row.Body, want)
	}
}
