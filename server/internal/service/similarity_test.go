package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
)

// ripRate is the cue rip's sample rate; its tracks split at three
// seconds, which is 225 CD frames.
const ripRate = 44100

// newCueFixture adds a cue-carved album (two tracks over one FLAC)
// beside the catalog fixture's four whole-file tracks.
func newCueFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	return newCueFixtureSplitAt(t, "00:03:00")
}

// newCueFixtureSplitAt is newCueFixture with the second track starting
// at split (mm:ss:ff) of the six-second rip.
func newCueFixtureSplitAt(t *testing.T, split string) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		workerLocalPaths: true,
		extra: func(t *testing.T, libDir string) {
			ripDir := filepath.Join(libDir, "rip")
			if _, err := fixtures.Generate(ripDir, fixtures.Spec{
				Name: "Rip Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
				SampleRate: ripRate,
				Tags:       map[string]string{"ALBUM": "Rip Album", "ARTIST": "Rip Artist"},
			}); err != nil {
				t.Fatal(err)
			}
			sheet := "PERFORMER \"Rip Artist\"\nTITLE \"Rip Album\"\nFILE \"Rip Album.flac\" WAVE\n" +
				"  TRACK 01 AUDIO\n    TITLE \"Rip One\"\n    INDEX 01 00:00:00\n" +
				"  TRACK 02 AUDIO\n    TITLE \"Rip Two\"\n    INDEX 01 " + split + "\n"
			if err := os.WriteFile(filepath.Join(ripDir, "Rip Album.cue"), []byte(sheet), 0o644); err != nil {
				t.Fatal(err)
			}
		},
	})
	enableSonicAnalysis(t, ctx, svc, uc)
	return ctx, svc, uc
}

// carvedTracks answers the two cue tracks' api pids and the rip's essence.
func carvedTracks(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) (one, two, ripEssence string) {
	t.Helper()
	for _, pid := range fixtureItemPIDs(t, ctx, svc, uc) {
		it, err := svc.getVisibleItem(ctx, uc, pid)
		if err != nil {
			t.Fatal(err)
		}
		switch it.Title {
		case "Rip One":
			one = pid
		case "Rip Two":
			two = pid
		default:
			continue
		}
		if !it.Virtual {
			t.Fatalf("%s is not a carved track", it.Title)
		}
		f, err := svc.lib.File(ctx, it.FilePID)
		if err != nil {
			t.Fatal(err)
		}
		ripEssence = f.EssenceHash
	}
	if one == "" || two == "" || ripEssence == "" {
		t.Fatalf("cue tracks missing from the scan: %q %q %q", one, two, ripEssence)
	}
	return one, two, ripEssence
}

func leaseAll(t *testing.T, ctx context.Context, svc *Library) map[string]SimilarityWorkItem {
	t.Helper()
	return leaseAllServing(t, ctx, svc, true)
}

// leaseAllServing leases as a worker for a server that can, or cannot,
// serve a carved track's window.
func leaseAllServing(t *testing.T, ctx context.Context, svc *Library, windows bool) map[string]SimilarityWorkItem {
	t.Helper()
	work, err := svc.LeaseSimilarityWork(ctx, 50, windows)
	if err != nil {
		t.Fatal(err)
	}
	byPID := map[string]SimilarityWorkItem{}
	for _, w := range work {
		byPID[w.PID] = w
	}
	return byPID
}

func TestSweepKeysCarvedTracksByTheirWindow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, two, rip := carvedTracks(t, ctx, svc, uc)

	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	work := leaseAll(t, ctx, svc)
	if got := work[one].Essence; got != rip+"@0-225" {
		t.Errorf("first carved track keyed %q, want %q", got, rip+"@0-225")
	}
	if got := work[two].Essence; got != rip+"@225-0" {
		t.Errorf("second carved track keyed %q, want %q", got, rip+"@225-0")
	}
	for pid, w := range work {
		if w.Essence == rip {
			t.Errorf("%s leased under the whole rip's essence", pid)
		}
		// A carved track's local path is the whole rip, which the
		// analyzer would decode end to end.
		carved := pid == one || pid == two
		if carved && w.LocalPath != "" {
			t.Errorf("carved %s leased with local path %q", pid, w.LocalPath)
		}
		if !carved && w.LocalPath == "" {
			t.Errorf("whole-file %s leased without its local path", pid)
		}
	}
	if len(work) != 6 {
		t.Errorf("leased %d items, want six tracks", len(work))
	}
}

func TestSweepKeepsWindowedVectors(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCueFixture(t)

	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	work := leaseAll(t, ctx, svc)
	for _, w := range work {
		_, bare, _ := parseAPIPID(w.PID)
		storeEmbedding(t, ctx, svc, w.Essence, string(bare))
		if err := svc.db.CompleteSimilarityWork(ctx, w.Essence); err != nil {
			t.Fatal(err)
		}
	}
	svc.simSweepVersion.Store(0)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	if got := embeddingCount(t, ctx, svc); got != len(work) {
		t.Errorf("embeddings after a second sweep = %d, want all %d kept", got, len(work))
	}
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Errorf("queue depth after a second sweep = %d, want 0", depth)
	}
}

func TestCarvedSiblingsAreSonicNeighbours(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, two, _ := carvedTracks(t, ctx, svc, uc)

	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	var uploads []EmbeddingUpload
	for pid, w := range leaseAll(t, ctx, svc) {
		vec := []float32{0, 1, 0, 0, 0, 0, 0, 0}
		if pid == one || pid == two {
			vec = []float32{1, 0.1, 0, 0, 0, 0, 0, 0}
		}
		uploads = append(uploads, EmbeddingUpload{PID: pid, Essence: w.Essence, Vector: vec})
	}
	if _, err := svc.IngestEmbeddings(ctx, "test", 8, uploads); err != nil {
		t.Fatal(err)
	}

	res, err := svc.SimilarTracksFor(ctx, uc, one, 5)
	if err != nil {
		t.Fatal(err)
	}
	if res.Basis != BasisSonic || len(res.Items) == 0 || res.Items[0].PID != two {
		var got []string
		for _, it := range res.Items {
			got = append(got, it.PID)
		}
		t.Fatalf("neighbours of %s = %s %v, want %s first on sonic", one, res.Basis, got, two)
	}
}

// windowAnalyzer records what the embedded analyzer was asked to read.
type windowAnalyzer struct {
	files   []string
	windows [][2]int64
}

func (a *windowAnalyzer) Model() string   { return "test" }
func (a *windowAnalyzer) VectorDims() int { return 8 }

// AnalyzeFileWindow records a carved track's window; a whole file reads
// as [0, 0) and is left out.
func (a *windowAnalyzer) AnalyzeFileWindow(_ context.Context, path string, from, to int64) ([]float32, error) {
	a.files = append(a.files, filepath.Base(path))
	if from == 0 && to == 0 {
		return []float32{1, 0, 0, 0, 0, 0, 0, 0}, nil
	}
	a.windows = append(a.windows, [2]int64{from, to})
	return []float32{0, 1, 0, 0, 0, 0, 0, 0}, nil
}

func TestEmbeddedAnalysisReadsACarvedTracksWindow(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCueFixture(t)

	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	an := &windowAnalyzer{}
	for {
		worked, err := svc.DrainEmbeddedAnalysis(ctx, an)
		if err != nil {
			t.Fatal(err)
		}
		if !worked {
			break
		}
	}

	slices.SortFunc(an.windows, func(a, b [2]int64) int { return int(a[0] - b[0]) })
	want := [][2]int64{{0, 3 * ripRate}, {3 * ripRate, 0}}
	if !slices.Equal(an.windows, want) {
		t.Errorf("windows read = %v, want %v", an.windows, want)
	}
	if got := embeddingCount(t, ctx, svc); got != 6 {
		t.Errorf("embeddings after the drain = %d, want 6", got)
	}
}

// A track under the analysis floor is not queued: the analyzer would
// refuse it, and a sweep would queue it again after every catalog change.
func TestATrackTooShortToAnalyzeIsNotQueued(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixtureSplitAt(t, "00:05:00")
	_, short, _ := carvedTracks(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	if _, queued := leaseAll(t, ctx, svc)[short]; queued {
		t.Fatal("a one-second track was queued for analysis")
	}
}

// refusingAnalyzer refuses every file, as an undecodable one is.
type refusingAnalyzer struct{ asked int }

func (a *refusingAnalyzer) Model() string   { return "test" }
func (a *refusingAnalyzer) VectorDims() int { return 8 }
func (a *refusingAnalyzer) AnalyzeFileWindow(context.Context, string, int64, int64) ([]float32, error) {
	a.asked++
	return nil, errors.New("decoding: not audio")
}

// A track the analyzer refuses is a verdict on its audio: it rests, and
// no later sweep queues it to be refused again.
func TestARefusedTrackIsNotQueuedAgain(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCueFixture(t)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	an := &refusingAnalyzer{}
	for {
		worked, err := svc.DrainEmbeddedAnalysis(ctx, an)
		if err != nil {
			t.Fatal(err)
		}
		if !worked {
			break
		}
	}
	asked := an.asked
	svc.simSweepVersion.Store(0)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	if worked, err := svc.DrainEmbeddedAnalysis(ctx, an); err != nil || worked || an.asked != asked {
		t.Fatalf("after a second sweep: worked %v (%v), asked %d more times", worked, err, an.asked-asked)
	}
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Errorf("queue depth = %d, want the refused tracks at rest", depth)
	}
}

// A worker for a server that cannot serve a window is not handed carved
// tracks; they wait untouched for one that can.
func TestAWorkerThatCannotReadAWindowIsNotHandedOne(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, two, _ := carvedTracks(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	work := leaseAllServing(t, ctx, svc, false)
	if _, ok := work[one]; ok {
		t.Fatal("a worker that cannot read windows was handed a carved track")
	}
	if _, ok := work[two]; ok {
		t.Fatal("a worker that cannot read windows was handed a carved track")
	}
	an := &windowAnalyzer{}
	for {
		worked, err := svc.DrainEmbeddedAnalysis(ctx, an)
		if err != nil {
			t.Fatal(err)
		}
		if !worked {
			break
		}
	}
	if len(an.windows) != 2 {
		t.Fatalf("the built-in analysis read %d windows, want both carved tracks", len(an.windows))
	}
}

// Trashing a rip trashes one file, which the journal logs against one of
// its tracks: every sibling's vector stays for the restore.
func TestTrashingACarvedRipKeepsEverySiblingsVector(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, _, _ := carvedTracks(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	work := leaseAll(t, ctx, svc)
	for _, w := range work {
		_, bare, _ := parseAPIPID(w.PID)
		storeEmbedding(t, ctx, svc, w.Essence, string(bare))
		if err := svc.db.CompleteSimilarityWork(ctx, w.Essence); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{one}, "trash", false); err != nil {
		t.Fatal(err)
	}
	svc.simSweepVersion.Store(0)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	if got := embeddingCount(t, ctx, svc); got != len(work) {
		t.Errorf("embeddings after trashing the rip = %d, want all %d kept", got, len(work))
	}
}

// A catalog read that fails is not audio that left: the sweep stops and
// prunes nothing, where it read every carved sibling of the file as gone.
func TestAFailedReadPrunesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	carvedTracks(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	work := leaseAll(t, ctx, svc)
	for _, w := range work {
		_, bare, _ := parseAPIPID(w.PID)
		storeEmbedding(t, ctx, svc, w.Essence, string(bare))
		if err := svc.db.CompleteSimilarityWork(ctx, w.Essence); err != nil {
			t.Fatal(err)
		}
	}
	svc.catalogFile = func(context.Context, model.PID) (*model.File, error) {
		return nil, errors.New("database is locked")
	}
	svc.simSweepVersion.Store(0)
	if _, err := svc.SimilaritySweep(ctx); err == nil {
		t.Error("a sweep that could not read the catalog reported success")
	}
	if got := embeddingCount(t, ctx, svc); got != len(work) {
		t.Errorf("embeddings after a failed read = %d, want all %d kept", got, len(work))
	}
}

// A carved track whose window ends before it starts has nothing to hand
// an analyzer, and says so the way a missing rate does.
func TestAReversedWindowIsNoWindow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, _, _ := carvedTracks(t, ctx, svc, uc)
	_, bare, _ := parseAPIPID(one)
	it, err := svc.lib.Get(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	reversed := *it
	reversed.StartFrames = it.EndFrames + 75
	if _, from, to, err := svc.sonicSource(ctx, &reversed); !errors.Is(err, errNoWindow) {
		t.Errorf("window = [%d, %d) (%v), want errNoWindow", from, to, err)
	}
}

// The window comes from the view the key was taken from, not a cache
// that may still hold the frames from before a cue edit.
func TestTheAnalysedWindowIsTheViewsOwn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	_, two, _ := carvedTracks(t, ctx, svc, uc)
	_, bare, _ := parseAPIPID(two)
	it, err := svc.lib.Get(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	moved := *it
	moved.StartFrames = 150
	_, from, to, err := svc.sonicSource(ctx, &moved)
	if err != nil || from != 2*ripRate || to != 0 {
		t.Fatalf("window = [%d, %d) (%v), want the view's own [%d, 0)", from, to, err, 2*ripRate)
	}
}
