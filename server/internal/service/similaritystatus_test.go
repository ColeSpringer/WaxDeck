package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
)

// coverageFixture is the catalog fixture beside a track under the
// analysis floor and a file of noise whose duration no scan reads. It
// answers the library's folder too.
func coverageFixture(t *testing.T) (context.Context, *Library, *UserCtx, string) {
	t.Helper()
	var dir string
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, libDir string) {
		dir = libDir
		if _, err := fixtures.Generate(libDir,
			fixtures.Spec{Name: "blip", Codec: fixtures.CodecFLAC, Duration: time.Second},
			fixtures.Spec{Name: "noise", Codec: fixtures.CodecFLAC, Duration: time.Second, Corrupt: fixtures.CorruptGarbage},
		); err != nil {
			t.Fatal(err)
		}
	}})
	return ctx, svc, uc, dir
}

// pidsTitled maps each title the caller can list to its tracks' pids.
func pidsTitled(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) map[string][]string {
	t.Helper()
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string][]string{}
	for _, it := range page.Items {
		out[it.Title] = append(out[it.Title], it.PID)
	}
	return out
}

func statusOf(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) SimilarityStatus {
	t.Helper()
	st, err := svc.SimilarityStatusFor(ctx, uc)
	if err != nil {
		t.Fatalf("reading the similarity status: %v", err)
	}
	return st
}

func wantCoverage(t *testing.T, what string, st SimilarityStatus, total, embedded, queued int) {
	t.Helper()
	if st.TotalTracks != total || st.EmbeddedTracks != embedded || st.QueueDepth != queued {
		t.Errorf("%s: %d tracks, %d embedded, %d queued; want %d, %d, %d",
			what, st.TotalTracks, st.EmbeddedTracks, st.QueueDepth, total, embedded, queued)
	}
}

func sweep(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}
}

// The status is the sweep's own reading of the library: the track under
// the floor is never in it, the noise is until the analyzer gives up on
// it, and then it leaves the total along with the queue, so coverage can
// finish.
func TestTheStatusCountsWhatTheSweepQueues(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := coverageFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	titled := pidsTitled(t, ctx, svc, uc)
	if len(titled) != 6 || len(titled["blip"]) != 1 || len(titled["noise"]) != 1 {
		t.Fatalf("the fixture lists %v, want the four tracks, a blip and the noise", titled)
	}
	// No sweep yet: the status walks the library itself.
	wantCoverage(t, "before a sweep", statusOf(t, ctx, svc, uc), 5, 0, 0)
	sweep(t, ctx, svc)
	wantCoverage(t, "once swept", statusOf(t, ctx, svc, uc), 5, 0, 5)
	if depth := queueDepth(t, ctx, svc); depth != 5 {
		t.Errorf("queue rows = %d, want the 5 the status counts", depth)
	}
	amber, bare := essenceFor(t, ctx, svc, uc, titled["Amber Waves"][0])
	storeEmbedding(t, ctx, svc, amber, string(bare))
	if err := svc.db.CompleteSimilarityWork(ctx, amber); err != nil {
		t.Fatal(err)
	}
	wantCoverage(t, "with one vector", statusOf(t, ctx, svc, uc), 5, 1, 4)
	noise, _ := essenceFor(t, ctx, svc, uc, titled["noise"][0])
	if err := svc.db.RetireSimilarityWork(ctx, noise, "decoding: not audio"); err != nil {
		t.Fatal(err)
	}
	wantCoverage(t, "with the noise given up on", statusOf(t, ctx, svc, uc), 4, 1, 3)
}

// A trashed track keeps its vector, so a restore costs no analysis, but
// it is not a track the library offers: it counts nowhere, where its
// vector used to stay in the coverage while the track left the total.
func TestAVectorKeptForATrashedTrackCountsNowhere(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	sweep(t, ctx, svc)
	for _, w := range leaseAll(t, ctx, svc) {
		_, bare, _ := parseAPIPID(w.PID)
		storeEmbedding(t, ctx, svc, w.Essence, string(bare))
		if err := svc.db.CompleteSimilarityWork(ctx, w.Essence); err != nil {
			t.Fatal(err)
		}
	}
	wantCoverage(t, "analyzed", statusOf(t, ctx, svc, uc), 4, 4, 0)
	if _, err := svc.DeleteItems(ctx, uc, fixtureItemPIDs(t, ctx, svc, uc)[:1], "trash", false); err != nil {
		t.Fatalf("trashing: %v", err)
	}
	sweep(t, ctx, svc)
	if got := embeddingCount(t, ctx, svc); got != 4 {
		t.Errorf("embeddings after trashing one track = %d, want all 4 kept", got)
	}
	st := statusOf(t, ctx, svc, uc)
	wantCoverage(t, "after trashing one", st, 3, 3, 0)
	if st.CoveragePct != 100 {
		t.Errorf("coverage = %v%%, want 100", st.CoveragePct)
	}
}

// Audio queued before the scan read how short it is waits on nothing:
// the sweep drops its row rather than leasing it until its attempts run
// out, and the status never counted it.
func TestASweepDropsAQueuedTrackUnderTheFloor(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := coverageFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	blip, bare := essenceFor(t, ctx, svc, uc, pidsTitled(t, ctx, svc, uc)["blip"][0])
	if err := svc.db.EnqueueSimilarity(ctx, blip, string(bare)); err != nil {
		t.Fatal(err)
	}
	sweep(t, ctx, svc)
	queue, err := svc.db.SimilarityQueueStates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, kept := queue[blip]; kept {
		t.Error("the sweep kept a queue row for audio under the analysis floor")
	}
	wantCoverage(t, "once swept", statusOf(t, ctx, svc, uc), 5, 0, 5)
}

// A reader under tag rules counts only the tracks the rules leave them.
func TestATagRestrictedReaderCountsWhatItsRulesLeave(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	loud := pidsTitled(t, ctx, svc, uc)["Delta Groove"]
	if len(loud) != 1 {
		t.Fatalf("Delta Groove pids = %v, want one", loud)
	}
	if _, err := svc.SetItemTag(ctx, uc, loud[0], "MOOD", []string{"loud"}, MetadataEditParams{}); err != nil {
		t.Fatalf("tagging: %v", err)
	}
	sweep(t, ctx, svc)
	reader := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: "MOOD", Value: "loud"}},
	}
	wantCoverage(t, "the reader", statusOf(t, ctx, svc, reader), 3, 0, 3)
	wantCoverage(t, "the administrator", statusOf(t, ctx, svc, uc), 4, 0, 4)
}

// With analysis off no sweep keeps the counts current, so a status walks
// a library that moved, in the background and not on every request,
// answering from the walk it has meanwhile.
func TestTheStatusFollowsALibraryNoSweepWalks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, dir := coverageFixture(t)
	wantCoverage(t, "first", statusOf(t, ctx, svc, uc), 5, 0, 0)
	if _, err := fixtures.Generate(dir, fixtures.Spec{Name: "late", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	wantCoverage(t, "straight after the scan", statusOf(t, ctx, svc, uc), 5, 0, 0)
	svc.simIndexChecked.Store(0) // as if the walk were statusIndexReuse old
	waitFor(t, func() bool { return statusOf(t, ctx, svc, uc).TotalTracks == 6 }, "the late track walked in")
}

// While analysis runs the status follows the library too, not only when
// a sweep walks it: a departure wakes no sweep, and a sweep that keeps
// failing never walks at all.
func TestTheStatusFollowsTheLibraryWhileAnalysisRuns(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	sweep(t, ctx, svc)
	wantCoverage(t, "swept", statusOf(t, ctx, svc, uc), 4, 0, 4)
	if _, err := svc.DeleteItems(ctx, uc, fixtureItemPIDs(t, ctx, svc, uc)[:1], "trash", false); err != nil {
		t.Fatalf("trashing: %v", err)
	}
	svc.simIndexChecked.Store(0) // as if the walk were statusIndexReuse old
	waitFor(t, func() bool { return statusOf(t, ctx, svc, uc).TotalTracks == 3 }, "the trashed track out of the total with no sweep")
	wantCoverage(t, "with no sweep since", statusOf(t, ctx, svc, uc), 3, 0, 3)
}

// countFileReads counts the catalog file reads a walk makes, from any
// goroutine.
func countFileReads(svc *Library) *atomic.Int64 {
	var reads atomic.Int64
	read := svc.catalogFile
	svc.catalogFile = func(ctx context.Context, pid model.PID) (*model.File, error) {
		reads.Add(1)
		return read(ctx, pid)
	}
	return &reads
}

// The first sweep after a status walk of the same catalog acts on that
// walk instead of reading every file again.
func TestASweepReusesTheStatusWalk(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	reads := countFileReads(svc)
	statusOf(t, ctx, svc, uc)
	walked := reads.Load()
	sweep(t, ctx, svc)
	if walked == 0 || reads.Load() != walked {
		t.Errorf("file reads: %d by the status, %d more by the sweep; want some, then none", walked, reads.Load()-walked)
	}
	wantCoverage(t, "once swept", statusOf(t, ctx, svc, uc), 4, 0, 4)
}

// A walk answers only for the catalog version it read, compared for
// equality as WaxBin asks: a walk labeled with any other version, a
// higher one included, is walked again.
func TestAWalkIsReusedOnlyForItsOwnVersion(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	sweep(t, ctx, svc)
	other := *svc.simIndex.Load()
	other.version += 1000
	svc.simIndex.Store(&other)
	svc.simSweepVersion.Store(0)
	reads := countFileReads(svc)
	sweep(t, ctx, svc)
	if reads.Load() == 0 {
		t.Error("the sweep acted on a walk of another catalog version")
	}
}

// The first walk runs off the request: a caller that gives up does not
// cancel it, and the next status answers from it without walking again.
func TestTheFirstStatusWalkOutlivesItsRequest(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	reads := countFileReads(svc)
	gone, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := svc.SimilarityStatusFor(gone, uc); err == nil {
		t.Fatal("a request already given up read a status")
	}
	waitFor(t, func() bool { return svc.simIndex.Load() != nil }, "the walk that request started")
	walked := reads.Load()
	wantCoverage(t, "the next status", statusOf(t, ctx, svc, uc), 4, 0, 0)
	if walked == 0 || reads.Load() != walked {
		t.Errorf("file reads: %d by the first walk, %d more after; want some, then none", walked, reads.Load()-walked)
	}
}

// Only audio the analyzer judged unreadable leaves the total. A row out
// of attempts with its audio never judged (a mount that kept failing, a
// worker that kept crashing) stays in it, so the gap shows, and a row's
// last attempt still waits while its lease runs.
func TestOnlyAJudgedTrackLeavesTheTotal(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)
	sweep(t, ctx, svc)
	for range 7 {
		if work, err := svc.db.LeaseSimilarityWork(ctx, 50, 0, true); err != nil || len(work) != 4 {
			t.Fatalf("lease = %+v (%v), want all four", work, err)
		}
	}
	running, err := svc.db.LeaseSimilarityWork(ctx, 1, time.Hour, true)
	if err != nil || len(running) != 1 {
		t.Fatalf("last lease = %+v (%v), want one row", running, err)
	}
	spent, err := svc.db.LeaseSimilarityWork(ctx, 50, 0, true)
	if err != nil || len(spent) != 3 {
		t.Fatalf("last leases = %+v (%v), want the other three", spent, err)
	}
	wantCoverage(t, "out of attempts, one still under its last lease", statusOf(t, ctx, svc, uc), 4, 0, 1)
	if err := svc.db.RetireSimilarityWork(ctx, spent[0].Essence, "decoding: not audio"); err != nil {
		t.Fatal(err)
	}
	wantCoverage(t, "with one judged unreadable", statusOf(t, ctx, svc, uc), 3, 0, 1)
}

// A grant reaches a track through its primary file, the rule every item
// read applies (viewVisible): a reader granted only the library holding
// a copy of a track can neither list nor open it, so the status does not
// count it either.
func TestAGrantCountsATrackThroughItsPrimaryFile(t *testing.T) {
	t.Parallel()
	var dir string
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(_ *testing.T, libDir string) { dir = libDir }})
	enableSonicAnalysis(t, ctx, svc, uc)
	copies := t.TempDir()
	amber, err := os.ReadFile(filepath.Join(dir, "amber.flac"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(copies, "amber.flac"), amber, 0o644); err != nil {
		t.Fatal(err)
	}
	// Adding the library scans it.
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "copies", Path: copies, Media: "music"})
	if err != nil {
		t.Fatalf("adding the library of copies: %v", err)
	}
	held := strings.TrimPrefix(lib.PID, PrefixLibrary+"-")
	track := pidsTitled(t, ctx, svc, uc)["Amber Waves"][0]
	_, bare, _ := parseAPIPID(track)
	waitFor(t, func() bool {
		files, err := svc.lib.ItemFiles(ctx, bare)
		return err == nil && slices.ContainsFunc(files, func(f model.ItemFileRef) bool { return string(f.LibraryPID) == held })
	}, "the copy scanned in as an alternate of Amber Waves")
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "reader", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	reader, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	reader.AllLibraries = false
	reader.Libraries = map[string]bool{held: true}
	if listed := pidsTitled(t, ctx, svc, reader); len(listed) != 0 {
		t.Fatalf("the reader lists %v, want nothing: a copy grants no track", listed)
	}
	if _, err := svc.getVisibleItem(ctx, reader, track); err == nil {
		t.Fatal("the reader opened Amber Waves through its copy")
	}
	sweep(t, ctx, svc)
	wantCoverage(t, "the reader", statusOf(t, ctx, svc, reader), 0, 0, 0)
	wantCoverage(t, "the administrator", statusOf(t, ctx, svc, uc), 4, 0, 4)
}
