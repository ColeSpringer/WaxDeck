package service

import (
	"context"
	"testing"
)

// taskState reads a task's state.
func taskState(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id string) string {
	t.Helper()
	task, err := svc.Tools.GetToolTaskFor(ctx, uc, id)
	if err != nil {
		t.Fatal(err)
	}
	return task.State
}

// A catalog repair, which can run for hours, runs on the long-task worker:
// the shared tool worker never takes it, and an import queued behind a
// running repair runs on the shared worker while the repair does.
func TestAnImportRunsWhileARepairDoes(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	repair, err := f.svc.StartCatalogRepair(ctx, f.uc)
	if err != nil {
		t.Fatal(err)
	}
	if f.svc.Tools.DrainToolTasks(ctx) {
		t.Fatal("the shared tool worker took the repair")
	}
	ts := starredSongs(t, `{"id":"s-alpha","title":"Alpha Song","artist":"Fixture Artist",`+
		`"album":"Fixture Album","duration":2,"starred":"2025-11-05T10:20:30.000Z"}`)
	imp, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	var meanwhile []string
	f.svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairSortKeys {
			for f.svc.Tools.DrainToolTasks(ctx) {
			}
			meanwhile = []string{taskState(t, ctx, f.svc, f.uc, repair.ID), taskState(t, ctx, f.svc, f.uc, imp.ID)}
		}
		return nil
	}
	if !f.svc.Tools.DrainLongToolTasks(ctx) {
		t.Fatal("the long-task worker did not take the repair")
	}
	if len(meanwhile) != 2 || meanwhile[0] != taskStateRunning || meanwhile[1] != taskStateDone {
		t.Fatalf("while the repair ran: repair and import %v, want the repair running and the import done", meanwhile)
	}
	if got := taskState(t, ctx, f.svc, f.uc, repair.ID); got != taskStateDone {
		t.Fatalf("the repair = %s, want done", got)
	}
}

// Health fixes and catalog repairs share the long-task worker, which runs
// one task at a time, the oldest first: a fix queued behind a running
// repair waits for it, and the shared tool worker takes neither.
func TestAHealthFixAndARepairRunOneAtATime(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	repair, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	fix, err := svc.Health.StartHealthFix(ctx, uc, ruleWriteUnsynced, nil)
	if err != nil {
		t.Fatal(err)
	}
	if svc.Tools.DrainToolTasks(ctx) {
		t.Fatal("the shared tool worker took a long task")
	}
	var fixWhileRepairing string
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairSearch {
			fixWhileRepairing = taskState(t, ctx, svc, uc, fix.TaskID)
		}
		return nil
	}
	if !svc.Tools.DrainLongToolTasks(ctx) {
		t.Fatal("the long-task worker took nothing")
	}
	if fixWhileRepairing != taskStateQueued {
		t.Fatalf("the fix was %s while the repair ran, want queued behind it", fixWhileRepairing)
	}
	if repaired, fixed := taskState(t, ctx, svc, uc, repair.ID), taskState(t, ctx, svc, uc, fix.TaskID); repaired != taskStateDone || fixed != taskStateQueued {
		t.Fatalf("after one turn of the long-task worker: repair %s, fix %s; want the repair done, the fix still queued", repaired, fixed)
	}
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	if fixed := taskState(t, ctx, svc, uc, fix.TaskID); fixed != taskStateDone {
		t.Fatalf("after the long-task worker's next turn: fix %s, want done", fixed)
	}
}
