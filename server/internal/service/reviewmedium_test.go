package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// entryMedium reads an entry's medium back.
func entryMedium(t *testing.T, ctx context.Context, svc *Library, id string) string {
	t.Helper()
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	return e.MediaType
}

// wantStaged fails unless the entry is pending with none of its files
// landed.
func wantStaged(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	status, p := decidedEntry(t, ctx, svc, id)
	if status != reviewPending {
		t.Errorf("entry = %s, want it pending", status)
	}
	for _, doc := range p.Tracks {
		if doc.PID != "" || doc.Imported || doc.Held {
			t.Errorf("%s landed, want the unit staged", filepath.Base(doc.Path))
		}
	}
}

// withCandidate gives an entry a release to approve, pairing each file.
func withCandidate(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	_, p := decidedEntry(t, ctx, svc, id)
	row, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	cand := reviewCandidateDoc{MBID: "11111111-1111-1111-1111-111111111111", Title: "Some Release",
		Artist: "Ann Author", TrackCount: len(p.Tracks), SimilarityPct: 90}
	for i, doc := range p.Tracks {
		cand.Pairings = append(cand.Pairings, reviewPairingDoc{TrackIndex: i, Position: i + 1, Title: doc.Title})
	}
	p.Candidates = []reviewCandidateDoc{cand}
	row.Payload = marshalJSON(p)
	row.BestMBID, row.BestTitle, row.BestArtist = cand.MBID, cand.Title, cand.Artist
	if err := svc.db.UpdateReviewEntry(ctx, row); err != nil {
		t.Fatal(err)
	}
}

// partLanded fails unless a first attempt left the first file landed and
// the second staged.
func partLanded(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	if _, p := decidedEntry(t, ctx, svc, id); p.Tracks[0].PID == "" || p.Tracks[1].PID != "" {
		t.Fatalf("after the first attempt: pids %q / %q, want the first part landed alone", p.Tracks[0].PID, p.Tracks[1].PID)
	}
}

// A unit opened as music and decided as it is as an audiobook lands as
// one book, titled as a book, and the entry keeps the medium chosen.
func TestAMusicEntryDecidedAsAnAudiobookLandsOneBook(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book",
		chapterPart(t, dir, "medium-1", "Chapter One"), chapterPart(t, dir, "medium-2", "Chapter Two"))
	dto, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false)
	if err != nil {
		t.Fatal(err)
	}
	if dto.MediaType != "audiobook" || dto.Title != "Unit Book" {
		t.Errorf("decided entry = %s %q, want the audiobook %q", dto.MediaType, dto.Title, "Unit Book")
	}
	if got := entryMedium(t, ctx, svc, id); got != "audiobook" {
		t.Errorf("stored entry medium = %q, want audiobook", got)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	if it := landedBook(t, ctx, svc, id); it.Kind != model.KindBook || it.Title != "Unit Book" {
		t.Errorf("landed = %s %q, want the book %q", it.Kind, it.Title, "Unit Book")
	}
}

// A decision as an audiobook stopped after its first part landed is
// finished by a retry that names no medium: the entry took the medium
// the first attempt chose.
func TestAnAudiobookDecisionRetriedWithNoMediumFinishesOneBook(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book",
		chapterPart(t, dir, "again-1", "Chapter One"), chapterPart(t, dir, "again-2", "Chapter Two"))
	failingPlan(svc, 3)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	if e, err := svc.db.ReviewEntryByID(ctx, id); err != nil || e.MediaType != "audiobook" || e.Title != "Unit Book" {
		t.Fatalf("entry after the first attempt = %s %q (%v), want the audiobook %q", e.MediaType, e.Title, err, "Unit Book")
	}
	partLanded(t, ctx, svc, id)
	svc.Ingest.planHook = nil
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false)
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	if it := landedBook(t, ctx, svc, id); it.Kind != model.KindBook || it.Title != "Unit Book" {
		t.Errorf("landed = %s %q, want the book %q", it.Kind, it.Title, "Unit Book")
	}
}

// mediumFixed reads whether an entry's detail says its medium is fixed.
func mediumFixed(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id string) bool {
	t.Helper()
	d, err := svc.Ingest.GetReviewEntry(ctx, uc, id)
	if err != nil {
		t.Fatal(err)
	}
	return d.MediumFixed
}

// Once a file has landed, a decision naming another medium is refused
// and changes nothing; naming the entry's own still finishes it. The
// entry's detail says so from the moment the file lands.
func TestADifferentMediumAfterAFileLandedIsRefused(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book",
		chapterPart(t, dir, "late-1", "Chapter One"), chapterPart(t, dir, "late-2", "Chapter Two"))
	if mediumFixed(t, ctx, svc, uc, id) {
		t.Error("a staged entry's medium reads fixed, want it open")
	}
	failingPlan(svc, 3)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	partLanded(t, ctx, svc, id)
	if !mediumFixed(t, ctx, svc, uc, id) {
		t.Error("an entry with a landed file reads its medium open, want it fixed")
	}
	svc.Ingest.planHook = nil
	_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false)
	if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "is already in the library as music") {
		t.Fatalf("decision as audiobook = %v (%s), want a conflict saying part is already in the library", err, KindOf(err))
	}
	if got := entryMedium(t, ctx, svc, id); got != "music" {
		t.Errorf("entry medium = %q, want it left music", got)
	}
	partLanded(t, ctx, svc, id)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "music", false); err != nil {
		t.Fatalf("decision naming the entry's own medium = %v, want it to stand", err)
	}
}

// An approval would apply a music release, so it is refused for a unit
// imported as an audiobook, and for a value no upload takes.
func TestADecisionRefusesAMediumItCannotImportAs(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book",
		chapterPart(t, dir, "refuse-1", "Chapter One"), chapterPart(t, dir, "refuse-2", "Chapter Two"))
	withCandidate(t, ctx, svc, id)
	for _, tc := range []struct{ action, medium string }{
		{"approve", "audiobook"},
		{"as-is", "podcast"},
		{"as-is", "film"},
	} {
		if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, tc.action, "", tc.medium, false); KindOf(err) != KindInvalid {
			t.Errorf("%s as %s = %v (%s), want invalid-request", tc.action, tc.medium, err, KindOf(err))
		}
	}
	wantStaged(t, ctx, svc, id)
	if got := entryMedium(t, ctx, svc, id); got != "music" {
		t.Errorf("entry medium = %q, want it left music", got)
	}
}

// An entry an earlier decision switched to audiobook keeps the music
// candidates it was identified with, and still is never approved.
func TestAnEntrySwitchedToAudiobookIsNeverApproved(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book",
		chapterPart(t, dir, "switched-1", "Chapter One"), chapterPart(t, dir, "switched-2", "Chapter Two"))
	withCandidate(t, ctx, svc, id)
	failingPlan(svc, 3)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	partLanded(t, ctx, svc, id)
	svc.Ingest.planHook = nil
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "approve", "", "", false); KindOf(err) != KindInvalid {
		t.Fatalf("approval of the switched entry = %v (%s), want invalid-request", err, KindOf(err))
	}
	if status, p := decidedEntry(t, ctx, svc, id); status != reviewPending || p.Tracks[1].PID != "" {
		t.Errorf("entry = %s with second pid %q, want it pending with the second part staged", status, p.Tracks[1].PID)
	}
}

// A library that does not take the medium refuses it before anything
// is written.
func TestALibraryThatDoesNotAcceptTheMediumRefusesIt(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t, Root{Name: "vinyl", Path: t.TempDir(), Managed: true, Media: "music"})
	id := vinylUnit(t, ctx, svc, uc)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false); KindOf(err) != KindInvalid {
		t.Fatalf("decision as audiobook into a music library = %v (%s), want invalid-request", err, KindOf(err))
	}
	wantStaged(t, ctx, svc, id)
	if got := entryMedium(t, ctx, svc, id); got != "music" {
		t.Errorf("entry medium = %q, want it left music", got)
	}
}

// A medium the decision could never import as is refused as such even
// once a file has landed: the request is wrong whatever the entry holds.
func TestARefusedMediumIsInvalidBeforeALandedFileConflicts(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t, Root{Name: "vinyl", Path: t.TempDir(), Managed: true, Media: "music"})
	id := vinylUnit(t, ctx, svc, uc)
	failingPlan(svc, 3)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	partLanded(t, ctx, svc, id)
	svc.Ingest.planHook = nil
	for _, action := range []string{"approve", "as-is"} {
		if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, action, "", "audiobook", false); KindOf(err) != KindInvalid {
			t.Errorf("%s as audiobook with a part landed = %v (%s), want invalid-request", action, err, KindOf(err))
		}
	}
	partLanded(t, ctx, svc, id)
}

// vinylUnit opens a pending two-file music entry for the music-only
// library named vinyl.
func vinylUnit(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	targets, err := svc.Ingest.UploadTargets(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	var vinyl string
	for _, tg := range targets {
		if tg.Name == "vinyl" && slices.Equal(tg.MediaTypes, []string{"music"}) {
			vinyl = tg.PID
		}
	}
	if vinyl == "" {
		t.Fatalf("targets = %+v, want a music-only library named vinyl", targets)
	}
	dir := t.TempDir()
	yes := true
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{
		Grouping: groupingAlbum, MediaType: "music", Identify: &yes, LibraryPID: vinyl,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"vinyl-1", "vinyl-2"} {
		data, err := os.ReadFile(chapterPart(t, dir, name, "Chapter "+name))
		if err != nil {
			t.Fatal(err)
		}
		up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
			FileName: name + ".flac", SizeBytes: int64(len(data)), MediaType: "music", Identify: &yes,
			BatchID: b.ID, BatchPath: "Ann Author/Unit Book", LibraryPID: vinyl,
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := svc.Ingest.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
			t.Fatal(err)
		}
		if _, err := svc.Ingest.CompleteUpload(ctx, uc, up.ID); err != nil {
			t.Fatal(err)
		}
	}
	done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
	if err != nil || len(done.ReviewEntryIDs) != 1 {
		t.Fatalf("batch = %v (%v), want one entry", done.ReviewEntryIDs, err)
	}
	return done.ReviewEntryIDs[0]
}

// An entry over items already in the library stages nothing to import
// under another medium: naming one is refused, naming its own is not,
// and a skip ignores the field.
func TestAnEntryStagingNoFilesKeepsItsMedium(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	open := func() string {
		id, err := svc.Ingest.openReviewEntry(ctx, wdb.ReviewEntry{
			Kind: reviewKindMatch, MediaType: "music", Origin: reviewOriginRematch, Title: "Held Album",
		}, reviewPayload{Tracks: []reviewTrackDoc{{PID: "tr-held", Path: "/lib/held.flac", Title: "Held"}}}, false)
		if err != nil {
			t.Fatal(err)
		}
		return id
	}
	id := open()
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false); KindOf(err) != KindInvalid {
		t.Fatalf("a rematch decided as audiobook = %v (%s), want invalid-request", err, KindOf(err))
	}
	if status, _ := decidedEntry(t, ctx, svc, id); status != reviewPending {
		t.Fatalf("entry = %s, want it pending", status)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "music", false); err != nil {
		t.Fatalf("a rematch decided as its own medium = %v, want it to stand", err)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, open(), "skip", "", "audiobook", false); err != nil {
		t.Fatalf("a skip naming another medium = %v, want the field ignored", err)
	}
}

// An approval that switched the medium and stopped at writing the
// release's values keeps what landed and the medium it landed as on the
// entry, so its retry finishes instead of being refused.
func TestAnApprovalStoppedAtItsEditsKeepsWhatLanded(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Ann Author/Unit Book",
		chapterPart(t, dir, "edit-1", "Chapter One"), chapterPart(t, dir, "edit-2", "Chapter Two"))
	withCandidate(t, ctx, svc, id)
	svc.Ingest.editFieldsHook = func(context.Context, []model.ItemFieldEdit, waxbin.EditOptions) (*waxbin.BatchEditResult, error) {
		return nil, errors.New("the catalog went away")
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "approve", "", "music", false); err == nil {
		t.Fatal("the approval stood, want it stopped at its edits")
	}
	if got := entryMedium(t, ctx, svc, id); got != "music" {
		t.Errorf("entry medium = %q, want the music its files landed as", got)
	}
	status, p := decidedEntry(t, ctx, svc, id)
	if status != reviewPending {
		t.Errorf("entry = %s, want it pending", status)
	}
	for _, doc := range p.Tracks {
		if doc.PID == "" {
			t.Errorf("%s carries no pid, want the landed item recorded", filepath.Base(doc.Path))
		}
	}
	svc.Ingest.editFieldsHook = nil
	dto, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "approve", "", "", false)
	if err != nil {
		t.Fatalf("retried approval = %v, want it to finish", err)
	}
	if dto.Status != reviewApplied {
		t.Errorf("entry = %s, want applied", dto.Status)
	}
	_, p = decidedEntry(t, ctx, svc, id)
	for _, doc := range p.Tracks {
		it, err := svc.lib.Get(ctx, model.PID(doc.PID))
		if err != nil {
			t.Fatal(err)
		}
		if it.Kind != model.KindTrack || it.Album != "Some Release" {
			t.Errorf("%s = %s on %q, want a track of the approved release", filepath.Base(doc.Path), it.Kind, it.Album)
		}
	}
}

// heldRelease is a match source answering one release, whose first
// search waits for release so a test can act while identification runs.
type heldRelease struct {
	rel              *match.Release
	entered, release chan struct{}
	once             sync.Once
}

func (h *heldRelease) hold() {
	h.once.Do(func() {
		close(h.entered)
		<-h.release
	})
}

func (h *heldRelease) ReleaseByMBID(_ context.Context, mbid string) (*match.Release, error) {
	if mbid == h.rel.MBID {
		return h.rel, nil
	}
	return nil, nil
}

func (h *heldRelease) ReleasesByGroup(context.Context, string) ([]*match.Release, error) {
	return nil, nil
}

func (h *heldRelease) LookupFingerprint(context.Context, match.Fingerprint) ([]match.FingerprintHit, error) {
	return nil, nil
}

func (h *heldRelease) SearchReleases(context.Context, string, string, int) ([]*match.Release, error) {
	h.hold()
	return []*match.Release{h.rel}, nil
}

func (h *heldRelease) SearchRecordings(context.Context, string, string, string, string) (match.RecordingSearch, error) {
	h.hold()
	return match.RecordingSearch{Releases: []*match.Release{h.rel}}, nil
}

// A decision that switched a music entry to audiobook and then failed
// keeps the new medium, and identification still running on the entry
// as music does not auto-apply it: it would import the files as tracks
// and write the music row back over the audiobook one.
func TestAFailedMediumChangeStopsAnIdentificationStillRunning(t *testing.T) {
	titles := []string{"Harbor Lights", "Copper Sky", "Meridian Line"}
	rel := &match.Release{MBID: "rel-nightfall", ReleaseGroupMBID: "rg-nightfall", Title: "Nightfall Circuit",
		Artist: "The Cardinal Waves", Year: 2014, Media: 1}
	for i, title := range titles {
		rel.Tracks = append(rel.Tracks, match.ReleaseTrack{
			RecordingMBID: "00000000-0000-4000-8000-00000000000" + strconv.Itoa(i+1),
			Title:         title, Disc: 1, Position: i + 1, DurationSec: float64(3 + i),
		})
	}
	src := &heldRelease{rel: rel, entered: make(chan struct{}), release: make(chan struct{})}
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = src })
	dir := t.TempDir()
	var paths []string
	for i, title := range titles {
		got, err := fixtures.Generate(dir, fixtures.Spec{
			Name: "nf-" + strconv.Itoa(i+1), Codec: fixtures.CodecFLAC, Duration: time.Duration(3+i) * time.Second,
			Tags: map[string]string{"TITLE": title, "ARTIST": "The Cardinal Waves", "ALBUMARTIST": "The Cardinal Waves",
				"ALBUM": "Nightfall Circuit", "TRACKNUMBER": strconv.Itoa(i + 1)},
		})
		if err != nil {
			t.Fatal(err)
		}
		paths = append(paths, got[0])
	}
	id := pendingUnitOf(t, ctx, svc, uc, "music", paths...)

	drained := make(chan struct{})
	go func() {
		defer close(drained)
		for n := 0; n < 10 && svc.Ingest.DrainMatchQueue(ctx); n++ {
		}
	}()
	select {
	case <-src.entered:
	case <-time.After(20 * time.Second):
		t.Fatal("identification never reached the source")
	}
	failingPlan(svc, 1)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", false); err == nil {
		t.Fatal("the decision stood, want it stopped by the failing plan")
	}
	if got := entryMedium(t, ctx, svc, id); got != "audiobook" {
		t.Fatalf("entry medium after the failed decision = %q, want audiobook", got)
	}
	svc.Ingest.planHook = nil
	close(src.release)
	select {
	case <-drained:
	case <-time.After(30 * time.Second):
		t.Fatal("identification did not finish")
	}
	wantStaged(t, ctx, svc, id)
	if got := entryMedium(t, ctx, svc, id); got != "audiobook" {
		t.Errorf("entry medium after identification = %q, want audiobook", got)
	}
}

// A discard after an approval that landed the files and then failed takes
// back what the approval wrote on them before the files stay.
func TestADiscardAfterAFailedApplyUndoesItOnWhatLanded(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Album",
		chapterPart(t, dir, "landed-1", "Chapter One"), chapterPart(t, dir, "landed-2", "Chapter Two"))
	withCandidate(t, ctx, svc, id)
	svc.Ingest.appliedWriteHook = func() error { return errors.New("the database is full") }
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "approve", "", "", false); err == nil {
		t.Fatal("the approval stood, want its last write to fail")
	}
	row, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	var snap reviewSnapshot
	if err := json.Unmarshal([]byte(row.Snapshot), &snap); err != nil || len(snap.Items) != 2 {
		t.Fatalf("snapshot = %q (%v), want the landed items' before-state", row.Snapshot, err)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "discard", "", "", false); err != nil {
		t.Fatalf("discard: %v", err)
	}
	for pid, fields := range snap.Items {
		it, err := svc.lib.Get(ctx, model.PID(pid))
		if err != nil {
			t.Fatal(err)
		}
		now := applyFields(it)
		for f, want := range fields {
			if now[f] != want {
				t.Errorf("%s: %s = %q after the discard, want %q as before the approval", pid, f, now[f], want)
			}
		}
		if it.Album == "Some Release" {
			t.Errorf("%s still carries the approved album", pid)
		}
	}
}
