package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
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

// decidedEntry reads an entry and its payload back.
func decidedEntry(t *testing.T, ctx context.Context, svc *Library, id string) (string, reviewPayload) {
	t.Helper()
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	var p reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &p); err != nil {
		t.Fatal(err)
	}
	return e.Status, p
}

// Two decisions of one entry never run at once: the second hears the
// first is still at it, and the first's record stands. Without that
// the second moved the files first, and the first, failing on files no
// longer staged, wrote its stale record over the second's.
func TestASecondDecisionOfAnEntryWaitsForTheFirst(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	planning, release := make(chan struct{}), make(chan struct{})
	var plans atomic.Int32
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		if plans.Add(1) == 1 {
			close(planning)
			<-release
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	first := make(chan error, 1)
	go func() {
		_, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
		first <- err
	}()
	<-planning
	_, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
	close(release)
	if KindOf(err) != KindConflict {
		t.Errorf("a second decision while the first runs = %v, want a conflict", err)
	}
	if err := <-first; err != nil {
		t.Fatalf("the first decision: %v", err)
	}
	status, p := decidedEntry(t, ctx, svc, id)
	if status != reviewAsIs || p.Tracks[0].PID == "" {
		t.Fatalf("entry after both = %s with track pid %q, want it as-is with its item", status, p.Tracks[0].PID)
	}
}

// Nothing else changes an entry while a decision of it runs: not a
// revert, a new search, or discarding its upload, whose staged file the
// decision is moving.
func TestAnEntryBeingDecidedTakesNoOtherChange(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	up, id := pendingUploadEntry(t, ctx, svc, uc)
	svc.deciding.Store(id, struct{}{})
	busy := func(what string, err error) {
		t.Helper()
		if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "being decided") {
			t.Errorf("%s while the entry is being decided = %v, want a conflict saying so", what, err)
		}
	}
	_, _, err := svc.DecideReviewEntry(ctx, uc, id, "skip", "")
	busy("a decision", err)
	_, err = svc.RevertReviewEntry(ctx, uc, id)
	busy("a revert", err)
	_, err = svc.ReidentifyEntry(ctx, uc, id, ReviewOverrideDTO{Title: "Other"})
	busy("a new search", err)
	busy("discarding the upload", svc.DeleteUpload(ctx, uc, up.ID))

	if status, _ := decidedEntry(t, ctx, svc, id); status != reviewPending {
		t.Fatalf("entry status = %s, want it still pending", status)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatalf("the upload is gone: %v", err)
	}
	if _, err := os.Stat(svc.uploadFinalPath(row)); err != nil {
		t.Fatalf("the staged file is gone: %v", err)
	}
}

// A decision the client walks away from midway still finishes: its
// files are moved and recorded, rather than left landed under an entry
// that says they never did.
func TestADecisionOutlivesTheClientThatAskedForIt(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	up, id := pendingUploadEntry(t, ctx, svc, uc)
	request, hangUp := context.WithCancel(ctx)
	defer hangUp()
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		hangUp()
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	if _, _, err := svc.DecideReviewEntry(request, uc, id, "as-is", ""); err != nil {
		t.Fatalf("decision whose client went away: %v", err)
	}
	status, p := decidedEntry(t, ctx, svc, id)
	if status != reviewAsIs || p.Tracks[0].PID == "" {
		t.Fatalf("entry = %s with track pid %q, want it as-is with its item", status, p.Tracks[0].PID)
	}
	if row, err := svc.db.UploadByID(ctx, up.ID); err != nil || row.State != uploadImported {
		t.Fatalf("upload after the decision = %+v, %v; want it imported", row, err)
	}
}

// unitTrack is a FLAC of one album, "Unit Album" by Unit Band.
func unitTrack(t *testing.T, dir, name, title, track string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Unit Band", "ALBUMARTIST": "Unit Band",
			"ALBUM": "Unit Album", "TRACKNUMBER": track},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// uploadPathAsking sends a music file whole and completes it, in a
// batch when batchID is set.
func uploadPathAsking(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, path string, identify bool, batchID string) UploadDTO {
	t.Helper()
	return uploadPathAs(t, ctx, svc, uc, path, "music", identify, batchID)
}

// uploadPathAs is uploadPathAsking for a file of the given media type.
func uploadPathAs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, path, media string, identify bool, batchID string) UploadDTO {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: filepath.Base(path), SizeBytes: int64(len(data)), MediaType: media,
		Identify: &identify, BatchID: batchID,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	done, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	return done
}

// pendingUnit uploads files as one album that asks to be identified, so
// they wait in one entry for a decision, and answers the entry's id.
func pendingUnit(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, paths ...string) string {
	t.Helper()
	return pendingUnitOf(t, ctx, svc, uc, "music", paths...)
}

// pendingUnitOf is pendingUnit for files of the given media type.
func pendingUnitOf(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, media string, paths ...string) string {
	t.Helper()
	yes := true
	b, err := svc.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: media, Identify: &yes})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range paths {
		uploadPathAs(t, ctx, svc, uc, p, media, true, b.ID)
	}
	done, err := svc.CompleteUploadBatch(ctx, uc, b.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(done.ReviewEntryIDs) != 1 {
		t.Fatalf("the album opened %d entries, want one", len(done.ReviewEntryIDs))
	}
	return done.ReviewEntryIDs[0]
}

// failingPlan makes the nth plan of an import fail.
func failingPlan(svc *Library, n int32) {
	var plans atomic.Int32
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		if plans.Add(1) == n {
			return nil, errors.New("the library went away")
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
}

// A bulk decision reports an entry's warnings only beside a decision
// that stood, as a single decide does: a file that landed before a
// later one failed says nothing about a decision there was not.
func TestABulkOutcomeThatFailedCarriesNoWarnings(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	held := unitTrack(t, dir, "held", "Held One", "1")
	uploadPathAsking(t, ctx, svc, uc, held, false, "")
	id := pendingUnit(t, ctx, svc, uc, held, unitTrack(t, dir, "other", "Other Two", "2"))
	// Both files planned up front, the held one landing on its plan, then
	// the second's own plan fails.
	failingPlan(svc, 3)
	out := svc.DecideReviewBulk(ctx, uc, []string{id}, "as-is")
	if len(out) != 1 || out[0].OK {
		t.Fatalf("bulk outcome = %+v, want the entry failed", out)
	}
	if len(out[0].Warnings) > 0 {
		t.Fatalf("failed outcome warnings = %q, want none", out[0].Warnings)
	}
}

// flacTagged is a FLAC whose audio is name's, under the given tags: two
// calls with one name and other tags make one recording labelled twice.
func flacTagged(t *testing.T, name string, tags map[string]string) string {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: tags,
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// stagedStill fails unless an upload's session is still staged with its
// file on disk.
func stagedStill(t *testing.T, ctx context.Context, svc *Library, uploadID string) {
	t.Helper()
	row, err := svc.db.UploadByID(ctx, uploadID)
	if err != nil {
		t.Fatalf("the upload is gone: %v", err)
	}
	if row.State != uploadStaged {
		t.Fatalf("upload state = %q, want it still staged", row.State)
	}
	if _, err := os.Stat(svc.uploadFinalPath(row)); err != nil {
		t.Fatalf("the staged file is gone: %v", err)
	}
}

// The library's copy of a recording does not make a file of it "held"
// when the file's tags send it to another item's place: that place is
// taken by someone else, so the decision is refused and the bytes kept.
func TestAFileWhosePlaceAnotherItemTakesIsNotHeld(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	held := map[string]string{"TITLE": "Ten Held", "ARTIST": "Ten Band", "ALBUM": "Ten Album", "TRACKNUMBER": "1"}
	taken := map[string]string{"TITLE": "Ten Taken", "ARTIST": "Ten Band", "ALBUM": "Ten Album", "TRACKNUMBER": "2"}
	uploadPathAsking(t, ctx, svc, uc, flacTagged(t, "tenaudio", held), false, "")
	uploadPathAsking(t, ctx, svc, uc, flacTagged(t, "tenother", taken), false, "")

	up := uploadPathAsking(t, ctx, svc, uc, flacTagged(t, "tenaudio", taken), true, "")
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.DuplicatePID == "" {
		t.Fatal("the relabelled recording arrived as no duplicate")
	}
	if _, _, err := svc.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", ""); KindOf(err) != KindConflict {
		t.Fatalf("decision = %v, want a conflict over the taken place", err)
	}
	stagedStill(t, ctx, svc, up.ID)
}

// The holder counts only in the library the file would enter: one whose
// copy of the recording plays from another library leaves a taken place
// a refusal, and the bytes staged.
func TestAHolderInAnotherLibraryDoesNotHoldAFile(t *testing.T) {
	other := t.TempDir()
	ctx, svc, uc := managedUploadFixture(t, Root{Name: "other", Path: other})
	tags := map[string]string{"TITLE": "Seventy", "ARTIST": "Seventy Band", "ALBUM": "Seventy Album", "TRACKNUMBER": "1"}
	// Another recording under these tags takes their place in the
	// managed library.
	uploadPathAsking(t, ctx, svc, uc, flacTagged(t, "seventy-other", tags), false, "")
	// The recording itself plays from the other library.
	recording := flacTagged(t, "seventy", tags)
	raw, err := os.ReadFile(recording)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(other, "seventy.flac"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	root, _ := rootAt(svc, other)
	scanPID, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{LibraryPID: model.PID(root.PID)})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scanPID)

	up := uploadPathAsking(t, ctx, svc, uc, recording, true, "")
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.DuplicatePID == "" {
		t.Fatal("the recording arrived as no duplicate of the other library's")
	}
	if _, _, err := svc.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", ""); KindOf(err) != KindConflict {
		t.Fatalf("decision = %v, want a conflict over the taken place", err)
	}
	stagedStill(t, ctx, svc, up.ID)
}

// Only a refusal for a taken place can mean the library already has a
// file where it would go; a file with no place, or one a failed check
// stopped, is refused whatever the library holds.
func TestOnlyATakenPlaceCanHoldAFile(t *testing.T) {
	for reason, want := range map[string]bool{
		"destination already exists in the library":       true,
		"destination case-collides with a cataloged file": true,
		"no destination: unsafe path segment":             false,
		"dedup check failed: database is locked":          false,
		"collision check failed: database is locked":      false,
		"held with its book, whose part 2 will not land":  false,
		"unreadable: meta.Read: bad frame":                false,
	} {
		if got := placeTaken(reason); got != want {
			t.Errorf("placeTaken(%q) = %v, want %v", reason, got, want)
		}
	}
}

// An upload is a duplicate only of what the library still holds: once
// the item an earlier copy of these bytes joined is deleted, the same
// bytes arrive as no one's, before the transfer and after it.
func TestAnUploadDuplicatesNothingTheLibraryNoLongerHolds(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	path := flacTagged(t, "eleven", map[string]string{"TITLE": "Eleven", "ARTIST": "Eleven Band", "ALBUM": "Eleven Album"})
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	send := func() UploadDTO {
		t.Helper()
		no := false
		up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
			FileName: "eleven.flac", SizeBytes: int64(len(data)), MediaType: "music",
			SHA256: hex.EncodeToString(sum[:]), Identify: &no,
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
			t.Fatal(err)
		}
		done, err := svc.CompleteUpload(ctx, uc, up.ID)
		if err != nil {
			t.Fatal(err)
		}
		return done
	}
	first := send()
	row, err := svc.db.UploadByID(ctx, first.ID)
	if err != nil {
		t.Fatal(err)
	}
	holder := row.ItemPID
	// The same bytes again: flagged, so held for a decision, and added.
	second := send()
	if second.Duplicate == nil {
		t.Fatal("the second copy arrived as no duplicate")
	}
	row, err = svc.db.UploadByID(ctx, second.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", ""); err != nil {
		t.Fatal(err)
	}
	it, err := svc.lib.Get(ctx, model.PID(holder))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{itemAPIPID(it)}, "permanent", false); err != nil {
		t.Fatal(err)
	}

	third, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "eleven.flac", SizeBytes: int64(len(data)), MediaType: "music", SHA256: hex.EncodeToString(sum[:]),
	})
	if err != nil {
		t.Fatal(err)
	}
	if third.Duplicate != nil {
		t.Fatalf("a copy of deleted bytes arrives as a duplicate: %+v", third.Duplicate)
	}
	again := send()
	if again.Duplicate != nil || again.State != uploadImported {
		t.Fatalf("after the transfer = %s with duplicate %+v, want it imported as no one's copy", again.State, again.Duplicate)
	}
}

// wantPlainRefusal fails unless a decision's refusal names neither where
// the server keeps files nor a library's operations.
func wantPlainRefusal(t *testing.T, svc *Library, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("the decision stood, want it refused")
	}
	msg := err.Error()
	if strings.Contains(msg, svc.stagingDir) || strings.Contains(msg, "meta.") || strings.Contains(msg, "inbox.") {
		t.Fatalf("refusal %q names the server's paths or operations", msg)
	}
}

// A unit whose staged file went missing is refused in plain words: the
// file's name and what is wrong, not the reading operation that found it.
func TestARefusalForAMissingStagedFileReadsPlainly(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	up, id := pendingUploadEntry(t, ctx, svc, uc)
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(svc.uploadFinalPath(row)); err != nil {
		t.Fatal(err)
	}
	_, _, err = svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
	if KindOf(err) != KindConflict {
		t.Fatalf("decision = %v, want a conflict", err)
	}
	wantPlainRefusal(t, svc, err)
}

// A file the importer cannot take at all - a format an operator allowed
// for uploads that the catalog does not import - is refused without the
// staging path the planner named it by.
func TestARefusalForAFileTheCatalogCannotImportNamesNoStagingPath(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	svc.setUploadFormats([]string{"flac", "webm"})
	data, err := os.ReadFile(flacTagged(t, "odd", map[string]string{"TITLE": "Odd", "ARTIST": "Odd Band"}))
	if err != nil {
		t.Fatal(err)
	}
	yes := true
	up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "odd.webm", SizeBytes: int64(len(data)), MediaType: "music", Identify: &yes,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); err != nil {
		t.Fatal(err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = svc.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", "")
	wantPlainRefusal(t, svc, err)
}

// A write-back failure that names no file is worded without a name,
// rather than as the base name of nothing.
func TestAWriteBackWarningWithoutAFileNamesNone(t *testing.T) {
	l := &Library{}
	if got := l.writeBackWarning(waxbin.WriteBackFailure{Reason: "no backing files present to write"}); got != "tags not written: no backing files present to write" {
		t.Fatalf("warning = %q", got)
	}
	if got := l.writeBackWarning(waxbin.WriteBackFailure{Path: "/srv/music/a.flac", Reason: "meta.Writer.Apply: permission denied"}); got != "a.flac: tags not written: permission denied" {
		t.Fatalf("warning = %q", got)
	}
}

// An import that held a file says nothing was added for it, rather than
// that it joined what the library holds: a held file adds nothing.
func TestAnImportNoticeSaysAHeldFileAddedNothing(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	path := unitTrack(t, t.TempDir(), "twice", "Twice", "1")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	again := filepath.Join(t.TempDir(), "twice-again.flac")
	if err := os.WriteFile(again, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	no := false
	b, err := svc.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: "music", Identify: &no})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{path, again} {
		uploadPathAsking(t, ctx, svc, uc, p, false, b.ID)
	}
	if _, err := svc.CompleteUploadBatch(ctx, uc, b.ID); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Notifications(ctx, uc, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range page.Notifications {
		if n.Event != "import-completed" {
			continue
		}
		if strings.Contains(n.Body, "added to what it holds") || !strings.Contains(n.Body, "nothing was added") {
			t.Fatalf("import notice = %q, want the held file said to add nothing", n.Body)
		}
		return
	}
	t.Fatalf("no import notice among %+v", page.Notifications)
}

// Marking an entry unofficial says which of its files it left unmarked
// because the library held them before, as an approval says which it
// left alone, even when an earlier attempt is what found them held.
func TestAnUnofficialMarkNamesTheFilesItLeftAlone(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	held := unitTrack(t, dir, "held", "Held One", "1")
	uploadPathAsking(t, ctx, svc, uc, held, false, "")
	id := pendingUnit(t, ctx, svc, uc, held, unitTrack(t, dir, "other", "Other Two", "2"))
	failingPlan(svc, 3)
	if _, _, err := svc.DecideReviewEntry(ctx, uc, id, "unofficial", ""); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	svc.planHook = nil
	_, warnings, err := svc.DecideReviewEntry(ctx, uc, id, "unofficial", "")
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(warnings, func(w string) bool { return strings.HasPrefix(w, "held.flac:") }) {
		t.Fatalf("warnings = %q, want the held file named", warnings)
	}
}

// An uploaded file is named alone for everyone, administrators too, once
// it has landed: the staging path it arrived under is gone.
func TestALandedUploadsTrackIsNamedNotByItsStagingPath(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	if _, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", ""); err != nil {
		t.Fatal(err)
	}
	detail, err := svc.GetReviewEntry(ctx, uc, id)
	if err != nil {
		t.Fatal(err)
	}
	if tr := detail.Tracks[0]; tr.PID == "" || tr.Path != "kept.flac" {
		t.Fatalf("landed track = pid %q path %q, want it named alone", tr.PID, tr.Path)
	}
}

// A library flagged read-only between a decision's plan and its move is
// answered as read-only, the reason the catalog stopped the file, rather
// than as an import that produced nothing.
func TestALibraryTurnedReadOnlyMidDecisionIsSaidSo(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	up, id := pendingUploadEntry(t, ctx, svc, uc)
	var lib Root
	for _, r := range svc.libraryRoots() {
		if r.Name == "lib" {
			lib = r
		}
	}
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		res, err := svc.lib.ImportAcquired(ctx, f, kind, meta)
		if ferr := svc.LibraryReadOnlySet(ctx, uc, apiPID(PrefixLibrary, model.PID(lib.PID)), true); ferr != nil {
			t.Error(ferr)
		}
		return res, err
	}
	if _, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", ""); KindOf(err) != KindReadOnly {
		t.Fatalf("decision = %v (%s), want read-only", err, KindOf(err))
	}
	stagedStill(t, ctx, svc, up.ID)
}

// bookPart is one part of "Unit Book" by Ann Author.
func bookPart(t *testing.T, dir, name, title, part string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author",
			"ALBUM": "Unit Book", "TRACKNUMBER": part},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// wantPartsOfOneBook fails unless every file of a decided book entry
// landed on one item the entry made, none of them joined to something
// the library held, each session carrying it.
func wantPartsOfOneBook(t *testing.T, ctx context.Context, svc *Library, id string, warnings []string) {
	t.Helper()
	for _, w := range warnings {
		if strings.Contains(w, "already in the library") {
			t.Errorf("warning %q: the book's own part read as something the library held", w)
		}
	}
	_, p := decidedEntry(t, ctx, svc, id)
	for _, doc := range p.Tracks {
		if doc.PID == "" || doc.PID != p.Tracks[0].PID || doc.heldBefore() {
			t.Errorf("track %s = pid %q joined %v held %v, want it a part of the book the entry made",
				filepath.Base(doc.Path), doc.PID, doc.Joined, doc.Held)
		}
	}
	rows, err := svc.db.ListUploadsByReviewEntry(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range rows {
		if r.ItemPID == "" {
			t.Errorf("session %s carries no item", r.FileName)
		}
	}
}

// A book decided in one call lands every part on the book its first part
// made: the later parts are the entry's own, not copies joined to what
// the library held.
func TestABooksLaterPartsAreItsOwnNotJoined(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitOf(t, ctx, svc, uc, "audiobook",
		bookPart(t, dir, "part-1", "Chapter One", "1"), bookPart(t, dir, "part-2", "Chapter Two", "2"),
		bookPart(t, dir, "part-3", "Chapter Three", "3"))
	_, warnings, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
}

// A decision retried after part of a book landed lands the rest on the
// book the first attempt made, and does not move the landed part again.
func TestARetriedBookDecisionFinishesTheBookItStarted(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitOf(t, ctx, svc, uc, "audiobook",
		bookPart(t, dir, "part-1", "Chapter One", "1"), bookPart(t, dir, "part-2", "Chapter Two", "2"))
	// Both parts planned up front, the first landing on its plan, then
	// the second's own plan fails.
	failingPlan(svc, 3)
	if _, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", ""); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	_, p := decidedEntry(t, ctx, svc, id)
	if p.Tracks[0].PID == "" || p.Tracks[1].PID != "" {
		t.Fatalf("after the first attempt: pids %q / %q, want the first part landed alone", p.Tracks[0].PID, p.Tracks[1].PID)
	}
	var plans atomic.Int32
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		plans.Add(1)
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	_, warnings, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", "")
	if err != nil {
		t.Fatal(err)
	}
	if n := plans.Load(); n != 1 {
		t.Errorf("the retry planned %d files, want the one still staged alone", n)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
}

// A completion whose duplicate check could not run keeps the warning the
// session opened with: only a check that ran answers for the bytes.
func TestACompletionThatCouldNotCheckKeepsTheOpeningWarning(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	path := flacTagged(t, "twelve", map[string]string{"TITLE": "Twelve", "ARTIST": "Twelve Band", "ALBUM": "Twelve Album"})
	uploadPathAsking(t, ctx, svc, uc, path, false, "")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	no := false
	up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "twelve.flac", SizeBytes: int64(len(data)), MediaType: "music",
		SHA256: hex.EncodeToString(sum[:]), Identify: &no,
	})
	if err != nil {
		t.Fatal(err)
	}
	if up.Duplicate == nil {
		t.Fatal("the same bytes opened with no warning")
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		if meta.Copy {
			return nil, errors.New("the catalog could not be read")
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	done, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if done.Duplicate == nil || done.Duplicate.Kind != "content" || done.State != uploadStaged {
		t.Fatalf("after a check that could not run = %s with duplicate %+v, want the content warning kept and the copy waiting", done.State, done.Duplicate)
	}
}
