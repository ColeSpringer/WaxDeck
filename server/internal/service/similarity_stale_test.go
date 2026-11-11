package service

import (
	"context"
	"errors"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// rewrittenTrack is the catalog fixture with sonic analysis on and swept,
// around its MBID-tagged track: a rewrite at its path gives it other
// audio and leaves it the same track, since the MBID keys it.
type rewrittenTrack struct {
	ctx    context.Context
	svc    *Library
	uc     *UserCtx
	logs   *syncBuffer
	libDir string
	pid    string // api pid
	bare   model.PID
}

func newRewrittenTrack(t *testing.T) rewrittenTrack {
	t.Helper()
	return newRewrittenTrackWith(t, nil)
}

// newRewrittenTrackWith is newRewrittenTrack with extra files in the library.
func newRewrittenTrackWith(t *testing.T, extra func(t *testing.T, dir string)) rewrittenTrack {
	t.Helper()
	logs := &syncBuffer{}
	var libDir string
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		logs: logs,
		extra: func(t *testing.T, dir string) {
			libDir = dir
			if extra != nil {
				extra(t, dir)
			}
		},
	})
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	pid := itemPIDByTitle(t, ctx, svc, uc, "Delta Groove")
	_, bare, _ := parseAPIPID(pid)
	return rewrittenTrack{ctx: ctx, svc: svc, uc: uc, logs: logs, libDir: libDir, pid: pid, bare: bare}
}

// key is the analysis key the catalog files the track's audio under now.
func (s rewrittenTrack) key(t *testing.T) string {
	t.Helper()
	return s.keyOf(t, s.bare)
}

// keyOf is key for any track of the library.
func (s rewrittenTrack) keyOf(t *testing.T, pid model.PID) string {
	t.Helper()
	it, err := s.svc.lib.Get(s.ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	f, err := s.svc.lib.File(s.ctx, it.FilePID)
	if err != nil {
		t.Fatal(err)
	}
	return analysisKey(f.EssenceHash, it)
}

// rewrite re-encodes the track at its path, a second longer, and rescans.
func (s rewrittenTrack) rewrite(t *testing.T) {
	t.Helper()
	was := s.key(t)
	if _, err := fixtures.Generate(s.libDir, fixtures.Spec{
		Name: "delta", Codec: fixtures.CodecFLAC, Duration: 4500 * time.Millisecond,
		Tags: map[string]string{
			"TITLE": "Delta Groove", "ARTIST": "Brass Nine", "ALBUM": "Signal Garden", "GENRE": "Jazz",
			"ISRC": catalogFixtureISRC, "MUSICBRAINZ_TRACKID": catalogFixtureMBID,
		},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.svc.lib.Scan(s.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if pid := itemPIDByTitle(t, s.ctx, s.svc, s.uc, "Delta Groove"); pid != s.pid {
		t.Fatalf("the rewritten track is %s, want it still %s", pid, s.pid)
	}
	if s.key(t) == was {
		t.Fatalf("the rewritten track still keys %s; the rewrite has to change its audio", was)
	}
}

// drain runs the embedded analysis until the queue is idle.
func (s rewrittenTrack) drain(t *testing.T, an SonicAnalyzer) {
	t.Helper()
	for {
		worked, err := s.svc.DrainEmbeddedAnalysis(s.ctx, an)
		if err != nil {
			t.Fatal(err)
		}
		if !worked {
			return
		}
	}
}

func (s rewrittenTrack) vectorUnder(t *testing.T, key string) bool {
	t.Helper()
	_, err := s.svc.db.EmbeddingItemPID(s.ctx, key)
	if err != nil && !errors.Is(err, wdb.ErrNotFound) {
		t.Fatal(err)
	}
	return err == nil
}

func (s rewrittenTrack) queued(t *testing.T, key string) bool {
	t.Helper()
	states, err := s.svc.db.SimilarityQueueStates(s.ctx)
	if err != nil {
		t.Fatal(err)
	}
	_, ok := states[key]
	return ok
}

// queuedFor is the track the queue row of key names.
func (s rewrittenTrack) queuedFor(t *testing.T, key string) model.PID {
	t.Helper()
	var pid string
	if err := s.svc.db.Writer().QueryRowContext(s.ctx,
		`SELECT item_pid FROM similarity_queue WHERE essence = ?`, key).Scan(&pid); err != nil {
		t.Fatal(err)
	}
	return model.PID(pid)
}

// A track queued for analysis can hold other audio by the time the worker
// reads it: its file rewritten at its path, as here, an upgrade to another
// encoding, or a cue edit moving its window. The worker reads the track as
// it is then, so it must neither read that audio for the key nor file what
// it measures there.
func TestAStaleSonicAnalysisNeverFilesTheAudioThatReplacedIt(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	was := s.key(t)
	s.rewrite(t)

	an := &windowAnalyzer{}
	s.drain(t, an)
	if s.vectorUnder(t, was) {
		t.Error("the replaced audio's key holds a vector measured from the audio that replaced it")
	}
	if slices.Contains(an.files, "delta.flac") {
		t.Error("the analysis queued for the replaced audio read the audio that replaced it")
	}
	if s.queued(t, was) {
		t.Error("the stale analysis stays queued")
	}

	// The replacement is analyzed under its own key.
	if _, err := s.svc.SimilaritySweep(s.ctx); err != nil {
		t.Fatal(err)
	}
	s.drain(t, an)
	if !s.vectorUnder(t, s.key(t)) {
		t.Error("the rewritten track has no vector under its own key")
	}
}

// A worker reads a track's audio by its pid, so a report that arrives after
// the audio changed may describe either: it is refused, filed under neither
// key, and the work is not handed out again.
func TestASonicReportForAudioTheTrackNoLongerHoldsIsRefused(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	w, ok := leaseAll(t, s.ctx, s.svc)[s.pid]
	if !ok {
		t.Fatal("the track was not handed out")
	}
	s.rewrite(t)

	res, err := s.svc.IngestEmbeddings(s.ctx, "test", 8, []EmbeddingUpload{
		{PID: w.PID, Essence: w.Essence, Vector: []float32{1, 0, 0, 0, 0, 0, 0, 0}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Accepted != 0 || res.Replaced != 0 || len(res.Rejected) != 1 || res.Rejected[0].Code != "not-found" {
		t.Fatalf("report = %+v, want it refused as not-found", res)
	}
	if s.vectorUnder(t, w.Essence) || s.vectorUnder(t, s.key(t)) {
		t.Error("the stale report was filed")
	}
	if s.queued(t, w.Essence) {
		t.Error("the stale work stays queued, to be handed out under the track again")
	}
}

// rewritingAnalyzer rewrites the track the first time it reads file, as a
// rewrite landing while the worker decodes, then answers as windowAnalyzer.
type rewritingAnalyzer struct {
	windowAnalyzer
	file    string
	rewrite func()
}

func (a *rewritingAnalyzer) AnalyzeFileWindow(ctx context.Context, path string, from, to int64) ([]float32, error) {
	if a.rewrite != nil && filepath.Base(path) == a.file {
		rewrite := a.rewrite
		a.rewrite = nil
		rewrite()
	}
	return a.windowAnalyzer.AnalyzeFileWindow(ctx, path, from, to)
}

// The audio can change while the worker decodes it, after it checked the
// track: the ingest refuses the vector, which is no verdict on the audio,
// so the key is not rested as unreadable.
func TestASonicAnalysisOvertakenByARewriteRestsNothing(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	was := s.key(t)
	s.drain(t, &rewritingAnalyzer{file: "delta.flac", rewrite: func() { s.rewrite(t) }})
	if s.vectorUnder(t, was) {
		t.Error("the replaced audio's key holds a vector measured as it was replaced")
	}
	if s.queued(t, was) {
		t.Error("the overtaken analysis stays queued")
	}
	if strings.Contains(s.logs.String(), "rests until its audio changes") {
		t.Errorf("the refused vector rested the key as unreadable; log:\n%s", s.logs)
	}
}

// addTwin puts Delta Groove's audio in the library again under its own
// identity (no MBID), so the catalog keeps it a track apart that keys the
// same analysis.
func addTwin(t *testing.T, dir string) {
	t.Helper()
	if _, err := fixtures.Generate(filepath.Join(dir, "twin"), fixtures.Spec{
		Name: "delta-twin", SameAudioAs: "delta", Codec: fixtures.CodecFLAC, Duration: 3500 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Delta Twin", "ARTIST": "Brass Nine", "ALBUM": "Signal Garden", "GENRE": "Jazz"},
	}); err != nil {
		t.Fatal(err)
	}
}

// A queue row names one track of its audio. When that track leaves or moves
// on, the row goes, but another track holding the same audio still wants
// it analyzed: the next sweep queues it again even when nothing else in the
// catalog moved, as when the sweep ran between the change and the drain.
func TestADroppedRowLeavesItsAudioToAnotherTrack(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		change func(t *testing.T, s rewrittenTrack)
	}{
		{"rewritten", func(t *testing.T, s rewrittenTrack) { s.rewrite(t) }},
		{"trashed", func(t *testing.T, s rewrittenTrack) {
			if _, err := s.svc.DeleteItems(s.ctx, s.uc, []string{s.pid}, "trash", false); err != nil {
				t.Fatal(err)
			}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s := newRewrittenTrackWith(t, addTwin)
			was := s.key(t)
			twin := itemPIDByTitle(t, s.ctx, s.svc, s.uc, "Delta Twin")
			if twin == s.pid {
				t.Fatal("the twin is the same track; it needs an identity of its own")
			}
			if _, bare, _ := parseAPIPID(twin); s.keyOf(t, bare) != was {
				t.Fatalf("the twin keys %s, want the same audio as %s", s.keyOf(t, bare), was)
			}
			if got := s.queuedFor(t, was); got != s.bare {
				t.Fatalf("the shared audio is queued for %s, want %s, the track the change moves", got, s.bare)
			}
			tc.change(t, s)
			if _, err := s.svc.SimilaritySweep(s.ctx); err != nil {
				t.Fatal(err)
			}

			s.drain(t, &windowAnalyzer{})
			if _, err := s.svc.SimilaritySweep(s.ctx); err != nil {
				t.Fatal(err)
			}
			s.drain(t, &windowAnalyzer{})
			if !s.vectorUnder(t, was) {
				t.Error("the twin's audio was left with no row and no vector")
			}
		})
	}
}

// The lease checks a track still holds the audio its work names before
// handing it out: a worker would pull and decode the audio that replaced
// it, for a report the server then refuses.
func TestTheSimilarityLeaseKeepsBackWorkTheTrackNoLongerHolds(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	was := s.key(t)
	s.rewrite(t)

	if w, ok := leaseAll(t, s.ctx, s.svc)[s.pid]; ok && w.Essence == was {
		t.Error("the lease handed out the work of audio the track no longer holds")
	}
	if s.queued(t, was) {
		t.Error("the stale work stays queued")
	}
}

// A track trashed while its work is out is refused the vector reported for
// it, and the work is dropped: the trashed track has no file to check the
// key against, and a rewrite before the trash would have had the worker
// pull, by pid, other audio than the key names.
func TestAVectorReportedForATrashedTrackIsRefused(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	w, ok := leaseAll(t, s.ctx, s.svc)[s.pid]
	if !ok {
		t.Fatal("the track was not handed out")
	}
	if _, err := s.svc.DeleteItems(s.ctx, s.uc, []string{s.pid}, "trash", false); err != nil {
		t.Fatal(err)
	}

	res, err := s.svc.IngestEmbeddings(s.ctx, "test", 8, []EmbeddingUpload{
		{PID: w.PID, Essence: w.Essence, Vector: []float32{1, 0, 0, 0, 0, 0, 0, 0}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Accepted != 0 || res.Replaced != 0 || len(res.Rejected) != 1 || res.Rejected[0].Code != "not-found" {
		t.Fatalf("report = %+v, want it refused as not-found", res)
	}
	if s.vectorUnder(t, w.Essence) {
		t.Error("the vector reported for the trashed track was filed")
	}
	if s.queued(t, w.Essence) {
		t.Error("the trashed track's work stays queued")
	}
}
