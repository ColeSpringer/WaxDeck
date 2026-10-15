package service

import (
	"context"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/waxerr"
)

// busyCatalog makes every import meet a lease another job holds while
// busy is set.
func busyCatalog(svc *Library, busy *atomic.Bool) {
	svc.applyImportHook = func(ctx context.Context, plan *inbox.Plan) (*inbox.Report, error) {
		if busy.Load() {
			return nil, waxerr.New(waxerr.CodeConflict, "jobs.Run", "another job holds scope fs-mutate")
		}
		return svc.lib.ApplyImport(ctx, plan)
	}
}

// declinedEntry uploads a file that declined identification and answers
// the entry it opened.
func declinedEntry(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name string) string {
	t.Helper()
	up := uploadPathAsking(t, ctx, svc, uc, flacTagged(t, name, map[string]string{
		"TITLE": "Held " + name, "ARTIST": "Lease Band", "ALBUM": "Lease Album"}), false, "")
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil || row.ReviewEntryID == "" {
		t.Fatalf("upload = %+v, %v; want it linked to an entry", row, err)
	}
	return row.ReviewEntryID
}

// waitImported waits for a declined entry to be filed as it arrived.
func waitImported(t *testing.T, ctx context.Context, svc *Library, entryID string) {
	t.Helper()
	waitFor(t, func() bool {
		e, err := svc.db.ReviewEntryByID(ctx, entryID)
		return err == nil && e.Status == reviewAsIs
	}, "the declined entry should import once the catalog frees")
}

// A declined import a busy catalog held back goes once the catalog
// frees, whatever job held it: a scan nobody here started has no one
// waiting on its end.
func TestADeclinedImportTheCatalogHeldBackGoesWhenAnyJobEnds(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	var busy atomic.Bool
	busy.Store(true)
	busyCatalog(svc, &busy)
	id := declinedEntry(t, ctx, svc, uc, "anyjob")
	if e, err := svc.db.ReviewEntryByID(ctx, id); err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v, %v; want it waiting", e, err)
	}
	busy.Store(false)
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scan)
	waitImported(t, ctx, svc, id)
}

// A declined import a busy catalog held back still goes after a restart:
// what it waits for is kept with the entry, not only in memory.
func TestADeclinedImportTheCatalogHeldBackGoesAfterARestart(t *testing.T) {
	dataDir := t.TempDir()
	managed := func(cfg *Config) { cfg.Roots[0].Managed = true }
	ctx, svc, uc, stop := openServiceAt(t, dataDir, managed)
	var busy atomic.Bool
	busy.Store(true)
	busyCatalog(svc, &busy)
	id := declinedEntry(t, ctx, svc, uc, "restart")
	stop()
	ctx, svc, _, _ = openServiceAt(t, dataDir, managed)
	waitImported(t, ctx, svc, id)
}

// A declined import that meets its entry held by another change goes
// once that change lets go, rather than staying pending for no one.
func TestADeclinedImportAnotherChangeHeldOffGoesWhenItLetsGo(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	var busy atomic.Bool
	busy.Store(true)
	busyCatalog(svc, &busy)
	id := declinedEntry(t, ctx, svc, uc, "claimed")
	release, ok := svc.claimEntry(id)
	if !ok {
		t.Fatal("the entry is already claimed")
	}
	busy.Store(false)
	svc.importDeclinedEntry(ctx, id)
	if e, err := svc.db.ReviewEntryByID(ctx, id); err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v, %v; want it still waiting while held", e, err)
	}
	release()
	waitImported(t, ctx, svc, id)
}
