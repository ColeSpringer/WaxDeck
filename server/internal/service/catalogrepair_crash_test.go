package service

import (
	"errors"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The reset a repair owes every client survives the process stopping
// between the repair's recorded end and the reset itself: the next start
// gives it, once, and a start with nothing owed gives none.
func TestARepairsResetSurvivesACrashAtItsEnd(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	before := snapshotSince(t, ctx, svc, uc)
	stop()
	ctx, svc, uc, stop = openServiceAt(t, dataDir, nil)
	if retired(t, ctx, svc, uc, before) {
		t.Fatal("a start with no repair behind it retired the cursors")
	}

	svc.catalogRepairEndHook = func() bool { return true }
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	if row, err := svc.db.ToolTaskByID(ctx, task.ID); err != nil || row.State != taskStateDone {
		t.Fatalf("the repair = %+v (%v), want its end on the record", row, err)
	}
	if retired(t, ctx, svc, uc, before) {
		t.Fatal("the cursors were retired before the point the process stops at")
	}
	stop()

	ctx, svc, uc, stop = openServiceAt(t, dataDir, nil)
	if !retired(t, ctx, svc, uc, before) {
		t.Fatal("after the next start, a cursor from before the repair still serves")
	}
	after := snapshotSince(t, ctx, svc, uc)
	stop()
	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	if retired(t, ctx, svc, uc, after) {
		t.Fatal("a second start reset the clients again")
	}
}

// A repair the process stopped partway, past its rollups step, gives the
// reset it owes at its own end rather than at the next start, so clients
// re-mirror once, after everything it rewrites.
func TestARepairCutShortGivesItsResetAtItsEnd(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	before := snapshotSince(t, ctx, svc, uc)
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairSortKeys {
			return errors.New("the process stopped")
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
	stop()

	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	if retired(t, ctx, svc, uc, before) {
		t.Fatal("the next start gave the reset of a repair still to finish")
	}
	if !svc.Tools.drainToolTasksAt(ctx, wdb.TaskTypes{Only: longToolTasks}, time.Now().Add(time.Hour).UnixNano()) {
		t.Fatal("the cut repair did not run again")
	}
	if row, err := svc.db.ToolTaskByID(ctx, task.ID); err != nil || row.State != taskStateDone {
		t.Fatalf("the resumed repair = %+v (%v), want it done", row, err)
	}
	if !retired(t, ctx, svc, uc, before) {
		t.Fatal("the resumed repair's end did not give the reset")
	}
}

// A rollups step that fails changed nothing, its one transaction rolled
// back, so it leaves no reset owed: here the catalog closes under it for a
// hand-off.
func TestAFailedRollupsStepOwesNoReset(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairRollups {
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
	if owed, err := svc.db.SyncStateGet(ctx, syncKeyCatalogResyncOwed); err != nil || owed != "" {
		t.Fatalf("owed reset = %q (%v), want none after a rollups step that failed", owed, err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
}
