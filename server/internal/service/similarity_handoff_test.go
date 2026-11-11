package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// sonicQueueFixture is the catalog fixture with sonic analysis on and
// swept, so its tracks wait in the analysis queue; it answers how many.
func sonicQueueFixture(t *testing.T) (context.Context, *Library, int) {
	t.Helper()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	queued := queueDepth(t, ctx, svc)
	if queued == 0 {
		t.Fatal("the sweep queued nothing")
	}
	return ctx, svc, queued
}

// handOff suspends the catalog until the test ends. Workers gate on
// Maintenance(), so with unseen the flag is cleared again: a hand-off that
// began after a worker passed its check, whose catalog reads then fail.
func handOff(t *testing.T, ctx context.Context, svc *Library, unseen bool) {
	t.Helper()
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := svc.lib.EndMaintenance(ctx); err != nil {
			t.Error(err)
		}
	})
	if unseen {
		svc.maintenance.Store(false)
	}
}

// unleased is how many queue rows a worker could lease right now: the rows
// a drain left alone, not ones it leased away or dropped.
func unleased(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	work, err := svc.db.LeaseSimilarityWork(ctx, 50, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	return len(work)
}

// A hand-off leaves the analysis queue waiting for it: a lease would spend
// an attempt on work that cannot be read.
func TestTheEmbeddedAnalysisWaitsOutAHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	handOff(t, ctx, svc, false)

	an := &windowAnalyzer{}
	if worked, err := svc.DrainEmbeddedAnalysis(ctx, an); worked || err != nil {
		t.Errorf("drain during the hand-off = %v, %v; want it idle", worked, err)
	}
	if got := unleased(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows left alone, want all of them", got, queued)
	}
}

// A hand-off that begins after the worker leased its batch fails its
// catalog reads; that is not a track that left, so no row is dropped.
func TestAHandOffBeginningMidBatchDropsNoSonicAnalysis(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	handOff(t, ctx, svc, true)

	an := &windowAnalyzer{}
	if _, err := svc.DrainEmbeddedAnalysis(ctx, an); KindOf(err) != KindMaintenance {
		t.Errorf("drain during the hand-off: %v, want a catalog-maintenance failure", err)
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
	if len(an.files) != 0 {
		t.Errorf("analyzed %v during the hand-off", an.files)
	}
}

// A hand-off that begins between the item read and the file read ends the
// batch with its rows still leased.
func TestAHandOffBeginningBetweenTheReadsDropsNoSonicAnalysis(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	svc.catalogFile = func(context.Context, model.PID) (*model.File, error) {
		return nil, errors.New("database is closed")
	}

	an := &windowAnalyzer{}
	if _, err := svc.DrainEmbeddedAnalysis(ctx, an); KindOf(err) != KindMaintenance {
		t.Errorf("drain during the hand-off: %v, want a catalog-maintenance failure", err)
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
	if len(an.files) != 0 {
		t.Errorf("analyzed %v during the hand-off", an.files)
	}
}

// A file row the catalog cannot read is no file that left either: the row
// stays leased, and nothing in the batch is dropped.
func TestAFailedFileReadDropsNoSonicAnalysis(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	svc.catalogFile = func(context.Context, model.PID) (*model.File, error) {
		return nil, errors.New("database is locked")
	}

	an := &windowAnalyzer{}
	if _, err := svc.DrainEmbeddedAnalysis(ctx, an); err != nil {
		t.Errorf("drain with unreadable files: %v, want the batch to go on", err)
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want them all held until their lease lapses", got)
	}
	if len(an.files) != 0 {
		t.Errorf("analyzed %v without reading their files", an.files)
	}
}

// failFirst answers a read that fails once, for the first pid it is asked
// about, and reports which; every later read goes through.
type failFirst struct{ pid model.PID }

func (f *failFirst) fail(pid model.PID) bool {
	if f.pid != "" {
		return false
	}
	f.pid = pid
	return true
}

// One row whose file the catalog cannot read ends nothing for the rows
// leased with it: they are analyzed, and it stays leased for a retry.
func TestAnUnreadableFileLeavesTheRestOfASonicBatchServed(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	read, bad := svc.catalogFile, &failFirst{}
	svc.catalogFile = func(ctx context.Context, pid model.PID) (*model.File, error) {
		if bad.fail(pid) {
			return nil, errors.New("database is locked")
		}
		return read(ctx, pid)
	}

	if worked, err := svc.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{}); !worked || err != nil {
		t.Fatalf("drain = %v, %v; want the batch served", worked, err)
	}
	if got := embeddingCount(t, ctx, svc); got != queued-1 {
		t.Errorf("%d vectors stored, want %d: every row but the unreadable one", got, queued-1)
	}
	if got := queueDepth(t, ctx, svc); got != 1 {
		t.Errorf("%d rows left queued, want only the unreadable one", got)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want the unreadable one held until its lease lapses", got)
	}
}

// The same for an item row the catalog cannot read.
func TestAnUnreadableItemLeavesTheRestOfASonicBatchServed(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	read, bad := svc.catalogItem, &failFirst{}
	svc.catalogItem = func(ctx context.Context, pid model.PID) (*model.ItemView, error) {
		if bad.fail(pid) {
			return nil, errors.New("database is locked")
		}
		return read(ctx, pid)
	}

	if worked, err := svc.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{}); !worked || err != nil {
		t.Fatalf("drain = %v, %v; want the batch served", worked, err)
	}
	if got := embeddingCount(t, ctx, svc); got != queued-1 {
		t.Errorf("%d vectors stored, want %d: every row but the unreadable one", got, queued-1)
	}
	if got := queueDepth(t, ctx, svc); got != 1 {
		t.Errorf("%d rows left queued, want only the unreadable one", got)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want the unreadable one held until its lease lapses", got)
	}
}

// And for a remote lease: the unreadable row is not handed out, the rest of
// the batch is, and the row stays leased.
func TestAnUnreadableItemLeavesTheRestOfASimilarityLeaseServed(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	read, bad := svc.catalogItem, &failFirst{}
	svc.catalogItem = func(ctx context.Context, pid model.PID) (*model.ItemView, error) {
		if bad.fail(pid) {
			return nil, errors.New("database is locked")
		}
		return read(ctx, pid)
	}

	work, err := svc.LeaseSimilarityWork(ctx, 50, true)
	if err != nil {
		t.Fatalf("lease: %v, want the batch served", err)
	}
	if len(work) != queued-1 {
		t.Errorf("%d rows handed out, want %d: every row but the unreadable one", len(work), queued-1)
	}
	for _, w := range work {
		if w.PID == apiPID(PrefixTrack, bad.pid) {
			t.Error("the lease handed out the track it could not read")
		}
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want them all held until their lease lapses", got)
	}
}

// A request that ends mid-lease stops the batch: the reads left would all
// fail the same way, each a track it could not read.
func TestACancelledLeaseStopsReadingItsBatch(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	if queued < 2 {
		t.Fatalf("%d rows queued, want a batch to stop partway", queued)
	}
	reqCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	reads := 0
	svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) {
		reads++
		cancel()
		return nil, reqCtx.Err()
	}

	work, err := svc.LeaseSimilarityWork(reqCtx, 50, true)
	if !errors.Is(err, context.Canceled) {
		t.Errorf("lease of a cancelled request: %v, want the cancellation", err)
	}
	if len(work) != 0 {
		t.Errorf("lease of a cancelled request handed out %v", work)
	}
	if reads != 1 {
		t.Errorf("%d item reads, want the batch to stop after the one that met the cancellation", reads)
	}
}

// An unreadable row costs the drain no less rest than an analyzed one: the
// worker loop calls again while any work was attempted, so a queue whose
// reads all fail would otherwise be walked at once.
func TestAnUnreadableRowIsPacedLikeAnAnalyzedOne(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		fail func(svc *Library, read func())
	}{
		{"item", func(svc *Library, read func()) {
			svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) {
				read()
				return nil, errors.New("database is locked")
			}
		}},
		{"file", func(svc *Library, read func()) {
			svc.catalogFile = func(context.Context, model.PID) (*model.File, error) {
				read()
				return nil, errors.New("database is locked")
			}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, _ := sonicQueueFixture(t)
			drainCtx, cancel := context.WithCancel(ctx)
			defer cancel()
			var at []time.Time
			tc.fail(svc, func() {
				at = append(at, time.Now())
				if len(at) == 2 {
					cancel()
				}
			})

			if _, err := svc.DrainEmbeddedAnalysis(drainCtx, &windowAnalyzer{}); err != nil {
				t.Fatal(err)
			}
			if len(at) != 2 {
				t.Fatalf("%d reads, want the drain to stop at the second", len(at))
			}
			if gap := at[1].Sub(at[0]); gap < embeddedAnalysisPace {
				t.Errorf("%v between two unreadable rows, want at least %v", gap, embeddedAnalysisPace)
			}
		})
	}
}

// A worker polling during a hand-off is handed nothing, and spends no
// attempt of the rows it would have leased.
func TestTheSimilarityLeaseWaitsOutAHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	handOff(t, ctx, svc, false)

	if work, err := svc.LeaseSimilarityWork(ctx, 50, true); err != nil || len(work) != 0 {
		t.Errorf("lease during the hand-off = %v, %v; want nothing", work, err)
	}
	if got := unleased(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows left alone, want all of them", got, queued)
	}
}

// A hand-off that begins mid-lease fails the item reads; the rows stay
// queued and re-offer when their lease lapses.
func TestAHandOffBeginningMidLeaseDropsNoSimilarityWork(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	handOff(t, ctx, svc, true)

	if _, err := svc.LeaseSimilarityWork(ctx, 50, true); KindOf(err) != KindMaintenance {
		t.Errorf("lease during the hand-off: %v, want a catalog-maintenance failure", err)
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
}

// A track that left the library retires its row from both the embedded
// worker and the lease: the one read failure that means gone.
func TestAVanishedTrackLeavesTheAnalysisQueue(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := sonicQueueFixture(t)
	const gone = "01J00000000000000000000000"
	enqueue := func(key string) {
		t.Helper()
		if err := svc.db.EnqueueSimilarity(ctx, key, gone); err != nil {
			t.Fatal(err)
		}
	}
	queuedKey := func(key string) bool {
		t.Helper()
		states, err := svc.db.SimilarityQueueStates(ctx)
		if err != nil {
			t.Fatal(err)
		}
		_, ok := states[key]
		return ok
	}

	enqueue("ghost-drained")
	for {
		worked, err := svc.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{})
		if err != nil {
			t.Fatal(err)
		}
		if !worked {
			break
		}
	}
	if queuedKey("ghost-drained") {
		t.Error("the embedded worker kept the row of a track that left the library")
	}

	enqueue("ghost-leased")
	work, err := svc.LeaseSimilarityWork(ctx, 50, true)
	if err != nil {
		t.Fatal(err)
	}
	for _, w := range work {
		if w.Essence == "ghost-leased" {
			t.Error("the lease handed out the work of a track that left the library")
		}
	}
	if queuedKey("ghost-leased") {
		t.Error("the lease kept the row of a track that left the library")
	}
}
