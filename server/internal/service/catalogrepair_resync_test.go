package service

import (
	"context"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// snapshotSince is the change cursor a fresh mirror of the catalog takes
// its deltas from.
func snapshotSince(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	page, err := svc.SyncCatalogSnapshot(ctx, uc, "", 1)
	if err != nil {
		t.Fatal(err)
	}
	return page.NextSince
}

// retired reports whether a catalog cursor answers sync-reset.
func retired(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, since string) bool {
	t.Helper()
	_, err := svc.SyncCatalogDelta(ctx, uc, since, 10)
	if err != nil && KindOf(err) != KindGone {
		t.Fatal(err)
	}
	return err != nil
}

// The release years a repair puts back reach no delta, and the sort keys
// it rewrites order lists the delta does not carry, so a repair that got
// past its first step sends every mirror back to a snapshot once it ends:
// a cursor handed out before it, or while it ran, answers sync-reset, and
// one handed out after it does not.
func TestARepairRetiresEveryCatalogCursor(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	before := snapshotSince(t, ctx, svc, uc)
	var during string
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairSearch {
			during = snapshotSince(t, ctx, svc, uc)
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	repairSummary(t, ctx, svc, uc, task.ID)
	if !retired(t, ctx, svc, uc, before) {
		t.Error("a cursor from before the repair still serves")
	}
	if !retired(t, ctx, svc, uc, during) {
		t.Error("a cursor handed out while the repair ran still serves")
	}
	if retired(t, ctx, svc, uc, snapshotSince(t, ctx, svc, uc)) {
		t.Error("a cursor handed out after the repair answers sync-reset")
	}
}

// A repair refused at its first step changed nothing, and one a hand-off
// cut short is followed by a run that starts over: neither retires a
// cursor, and the run that finishes after the hand-off does.
func TestARepairRetiresCursorsOnlyOnceItHasRun(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	before := snapshotSince(t, ctx, svc, uc)
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairRollups {
			return &Error{Kind: KindInvalid, Msg: "refused"}
		}
		return nil
	}
	refused, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	if row, err := svc.db.ToolTaskByID(ctx, refused.ID); err != nil || row.State != taskStateFailed {
		t.Fatalf("the repair refused at its first step = %+v (%v), want it failed", row, err)
	}
	if retired(t, ctx, svc, uc, before) {
		t.Fatal("a repair refused at its first step retired the cursors")
	}

	handedOff := false
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairSortKeys && !handedOff {
			handedOff = true
			return svc.lib.BeginMaintenance(ctx)
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if !svc.Tools.DrainLongToolTasks(ctx) {
		t.Fatal("the repair did not run")
	}
	if row, err := svc.db.ToolTaskByID(ctx, task.ID); err != nil || row.WaitReason != "catalog-maintenance" {
		t.Fatalf("the cut repair = %+v (%v), want it waiting out the hand-off", row, err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if retired(t, ctx, svc, uc, before) {
		t.Fatal("a repair a hand-off cut short retired the cursors")
	}
	if !svc.Tools.drainToolTasksAt(ctx, wdb.TaskTypes{Only: longToolTasks}, time.Now().Add(time.Hour).UnixNano()) {
		t.Fatal("the waiting repair did not run again")
	}
	repairSummary(t, ctx, svc, uc, task.ID)
	if !retired(t, ctx, svc, uc, before) {
		t.Error("the run that finished after the hand-off left the cursors serving")
	}
}
