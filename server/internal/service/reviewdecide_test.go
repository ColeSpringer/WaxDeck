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
	"strconv"
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
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		if plans.Add(1) == 1 {
			close(planning)
			<-release
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	first := make(chan error, 1)
	go func() {
		_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
		first <- err
	}()
	<-planning
	_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
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
	svc.Ingest.deciding.Store(id, struct{}{})
	busy := func(what string, err error) {
		t.Helper()
		if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "being decided") {
			t.Errorf("%s while the entry is being decided = %v, want a conflict saying so", what, err)
		}
	}
	_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "skip", "", "")
	busy("a decision", err)
	_, err = svc.Ingest.RevertReviewEntry(ctx, uc, id)
	busy("a revert", err)
	_, err = svc.Ingest.ReidentifyEntry(ctx, uc, id, ReviewOverrideDTO{Title: "Other"})
	busy("a new search", err)
	busy("discarding the upload", svc.Ingest.DeleteUpload(ctx, uc, up.ID))

	if status, _ := decidedEntry(t, ctx, svc, id); status != reviewPending {
		t.Fatalf("entry status = %s, want it still pending", status)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatalf("the upload is gone: %v", err)
	}
	if _, err := os.Stat(svc.Ingest.uploadFinalPath(row)); err != nil {
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
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		hangUp()
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(request, uc, id, "as-is", "", ""); err != nil {
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
	return uploadPathIn(t, ctx, svc, uc, path, media, identify, batchID, "")
}

// uploadPathIn is uploadPathAs for a batch member sent from a folder.
func uploadPathIn(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, path, media string, identify bool, batchID, batchPath string) UploadDTO {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: filepath.Base(path), SizeBytes: int64(len(data)), MediaType: media,
		Identify: &identify, BatchID: batchID, BatchPath: batchPath,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Ingest.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	done, err := svc.Ingest.CompleteUpload(ctx, uc, up.ID)
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
	return pendingUnitIn(t, ctx, svc, uc, media, "", paths...)
}

// pendingUnitIn is pendingUnitOf for files sent from one folder.
func pendingUnitIn(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, media, folder string, paths ...string) string {
	t.Helper()
	yes := true
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: media, Identify: &yes})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range paths {
		uploadPathIn(t, ctx, svc, uc, p, media, true, b.ID, folder)
	}
	done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
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
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
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
	out := svc.Ingest.DecideReviewBulk(ctx, uc, []string{id}, "as-is")
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
	if _, err := os.Stat(svc.Ingest.uploadFinalPath(row)); err != nil {
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", "", ""); KindOf(err) != KindConflict {
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", "", ""); KindOf(err) != KindConflict {
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
		up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
			FileName: "eleven.flac", SizeBytes: int64(len(data)), MediaType: "music",
			SHA256: hex.EncodeToString(sum[:]), Identify: &no,
		})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := svc.Ingest.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
			t.Fatal(err)
		}
		done, err := svc.Ingest.CompleteUpload(ctx, uc, up.ID)
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", "", ""); err != nil {
		t.Fatal(err)
	}
	it, err := svc.lib.Get(ctx, model.PID(holder))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Tools.DeleteItems(ctx, uc, []string{itemAPIPID(it)}, "permanent", false); err != nil {
		t.Fatal(err)
	}

	third, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
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
	if strings.Contains(msg, svc.Ingest.stagingDir) || strings.Contains(msg, "meta.") || strings.Contains(msg, "inbox.") {
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
	if err := os.Remove(svc.Ingest.uploadFinalPath(row)); err != nil {
		t.Fatal(err)
	}
	_, _, err = svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
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
	svc.Ingest.setUploadFormats([]string{"flac", "webm"})
	data, err := os.ReadFile(flacTagged(t, "odd", map[string]string{"TITLE": "Odd", "ARTIST": "Odd Band"}))
	if err != nil {
		t.Fatal(err)
	}
	yes := true
	up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "odd.webm", SizeBytes: int64(len(data)), MediaType: "music", Identify: &yes,
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
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = svc.Ingest.DecideReviewEntry(ctx, uc, row.ReviewEntryID, "as-is", "", "")
	wantPlainRefusal(t, svc, err)
}

// A write-back failure that names no file is worded without a name,
// rather than as the base name of nothing.
func TestAWriteBackWarningWithoutAFileNamesNone(t *testing.T) {
	l := bareLibrary(&core{})
	if got := l.Ingest.writeBackWarning(waxbin.WriteBackFailure{Reason: "no backing files present to write"}); got != "tags not written: no backing files present to write" {
		t.Fatalf("warning = %q", got)
	}
	if got := l.Ingest.writeBackWarning(waxbin.WriteBackFailure{Path: "/srv/music/a.flac", Reason: "meta.Writer.Apply: permission denied"}); got != "a.flac: tags not written: permission denied" {
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
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: "music", Identify: &no})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{path, again} {
		uploadPathAsking(t, ctx, svc, uc, p, false, b.ID)
	}
	if _, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Integrations.Notifications(ctx, uc, "", 10)
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

// An entry stopped part-way says how many of its files landed, not that
// it could not be imported: of two files with other audio for one place,
// the first lands and the second is refused.
func TestAReviewNoticeCountsTheFilesThatLanded(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	twins := []string{unitTrack(t, dir, "twin-a", "Twin", "1"), unitTrack(t, dir, "twin-b", "Twin", "1")}
	no := false
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: "music", Identify: &no})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range twins {
		uploadPathAsking(t, ctx, svc, uc, p, false, b.ID)
	}
	if _, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Integrations.Notifications(ctx, uc, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range page.Notifications {
		if n.Event != "review-ready" {
			continue
		}
		if !strings.Contains(n.Body, "1 of its 2 files was added to the library; the other waits for a decision") {
			t.Fatalf("review notice = %q, want the file that landed counted", n.Body)
		}
		return
	}
	t.Fatalf("no review notice among %+v", page.Notifications)
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "unofficial", "", ""); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	svc.Ingest.planHook = nil
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "unofficial", "", "")
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", ""); err != nil {
		t.Fatal(err)
	}
	detail, err := svc.Ingest.GetReviewEntry(ctx, uc, id)
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
	for _, r := range svc.Roots.libraryRoots() {
		if r.Name == "lib" {
			lib = r
		}
	}
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		res, err := svc.lib.ImportAcquired(ctx, f, kind, meta)
		if ferr := svc.Settings.LibraryReadOnlySet(ctx, uc, apiPID(PrefixLibrary, model.PID(lib.PID)), true); ferr != nil {
			t.Error(ferr)
		}
		return res, err
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", ""); KindOf(err) != KindReadOnly {
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
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
}

// chapterPart writes one part of a book that names only its chapter.
func chapterPart(t *testing.T, dir, name, title string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Ann Author"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// A book whose parts name only their chapters still lands as one book,
// named from the folder it was sent from rather than after a chapter.
func TestABookWithNoAlbumLandsAsOneBookNamedFromItsFolder(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Ann Author/Unit Book",
		chapterPart(t, dir, "chapter-1", "Chapter One"), chapterPart(t, dir, "chapter-2", "Chapter Two"))
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	_, p := decidedEntry(t, ctx, svc, id)
	it, err := svc.lib.Get(ctx, model.PID(p.Tracks[0].PID))
	if err != nil {
		t.Fatal(err)
	}
	if it.Title != "Unit Book" || it.Artist != "Ann Author" {
		t.Errorf("book = %q by %q, want %q by %q", it.Title, it.Artist, "Unit Book", "Ann Author")
	}
}

// A unit opened as music and decided as a book is titled as a book: its
// entry's title came from its first part, so the folder names it.
func TestAUnitOpenedAsMusicLandsAsOneBookNamedFromItsFolder(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "music", "Ann Author/Unit Book/Disc 1",
		chapterPart(t, dir, "switched-1", "Chapter One"), chapterPart(t, dir, "switched-2", "Chapter Two"))
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if e.Title != "Chapter One" {
		t.Fatalf("music entry titled %q, want its first part's title", e.Title)
	}
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	_, p := decidedEntry(t, ctx, svc, id)
	it, err := svc.lib.Get(ctx, model.PID(p.Tracks[0].PID))
	if err != nil {
		t.Fatal(err)
	}
	if it.Title != "Unit Book" {
		t.Errorf("book = %q, want %q", it.Title, "Unit Book")
	}
}

// bookFile writes one FLAC part of a book with the given tags.
func bookFile(t *testing.T, dir, name string, tags map[string]string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: tags,
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// landedBook reads the item a decided entry's first file landed on.
func landedBook(t *testing.T, ctx context.Context, svc *Library, id string) *model.ItemView {
	t.Helper()
	_, p := decidedEntry(t, ctx, svc, id)
	it, err := svc.lib.Get(ctx, model.PID(p.Tracks[0].PID))
	if err != nil {
		t.Fatal(err)
	}
	return it
}

// wantUploadedTags fails unless every staged file of the entry carries
// what it was uploaded with: no album, album artist or track number.
func wantUploadedTags(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	_, p := decidedEntry(t, ctx, svc, id)
	for _, doc := range p.Tracks {
		if doc.PID != "" || doc.Imported {
			t.Errorf("%s landed, want the unit staged", filepath.Base(doc.Path))
		}
		tags, _, err := parseFileTags(ctx, doc.Path)
		if err != nil {
			t.Fatal(err)
		}
		for _, k := range []string{"ALBUM", "ALBUMARTIST", "TRACKNUMBER"} {
			if tags[k] != "" || doc.Tags[k] != "" {
				t.Errorf("%s %s = %q (recorded %q), want it as uploaded, absent", filepath.Base(doc.Path), k, tags[k], doc.Tags[k])
			}
		}
		if tags["ARTIST"] != "Ann Author" {
			t.Errorf("%s ARTIST = %q, want it as uploaded", filepath.Base(doc.Path), tags["ARTIST"])
		}
	}
}

// A title typed for a book wins over the album its parts share.
func TestATypedTitleWinsOverTheAlbumABooksPartsShare(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitOf(t, ctx, svc, uc, "audiobook",
		bookPart(t, dir, "typed-1", "Chapter One", "1"), bookPart(t, dir, "typed-2", "Chapter Two", "2"))
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	var p reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &p); err != nil {
		t.Fatal(err)
	}
	p.Override = &reviewOverride{Album: "Typed Book"}
	e.Payload = marshalJSON(p)
	if err := svc.db.UpdateReviewEntry(ctx, e); err != nil {
		t.Fatal(err)
	}
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	if it := landedBook(t, ctx, svc, id); it.Title != "Typed Book" {
		t.Errorf("book = %q, want the typed title", it.Title)
	}
}

// A book across disc folders that number their tracks per disc, with no
// disc number, takes its places folder by folder, in the discs' order.
func TestABookAcrossDiscFoldersIsNumberedFolderByFolder(t *testing.T) {
	for _, discs := range [][2]string{{"CD1", "CD2"}, {"CD2", "CD10"}} {
		t.Run(discs[0]+" and "+discs[1], func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			dir := t.TempDir()
			yes := true
			b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAlbum, MediaType: "audiobook", Identify: &yes})
			if err != nil {
				t.Fatal(err)
			}
			for _, f := range []struct{ name, track, folder string }{
				{"later-01", "1", "Ann Author/Disc Book/" + discs[1]},
				{"first-02", "2", "Ann Author/Disc Book/" + discs[0]},
				{"first-01", "1", "Ann Author/Disc Book/" + discs[0]},
			} {
				path := bookFile(t, dir, f.name, map[string]string{"TITLE": "Part " + f.name, "ARTIST": "Ann Author", "TRACKNUMBER": f.track})
				uploadPathIn(t, ctx, svc, uc, path, "audiobook", true, b.ID, f.folder)
			}
			done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
			if err != nil || len(done.ReviewEntryIDs) != 1 {
				t.Fatalf("batch = %v (%v), want one entry", done.ReviewEntryIDs, err)
			}
			id := done.ReviewEntryIDs[0]
			_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
			if err != nil {
				t.Fatal(err)
			}
			wantPartsOfOneBook(t, ctx, svc, id, warnings)
			_, p := decidedEntry(t, ctx, svc, id)
			want := map[string]int{"first-01.flac": 1, "first-02.flac": 2, "later-01.flac": 3}
			for _, doc := range p.Tracks {
				if w := want[filepath.Base(doc.Path)]; doc.TrackNo != w || doc.Tags["TRACKNUMBER"] != strconv.Itoa(w) {
					t.Errorf("%s = place %d (%s), want %d", filepath.Base(doc.Path), doc.TrackNo, doc.Tags["TRACKNUMBER"], w)
				}
			}
			if it := landedBook(t, ctx, svc, id); it.Title != "Disc Book" {
				t.Errorf("book = %q, want %q", it.Title, "Disc Book")
			}
		})
	}
}

// A book sent as auto from part folders that number their tracks from 1
// in each, with no disc number, is one book numbered folder by folder,
// the folders in the order of their numbers.
func TestABookInPartFoldersIsNumberedFolderByFolder(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	yes := true
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAuto, MediaType: "audiobook", Identify: &yes})
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range []struct{ name, track, folder string }{
		{"p10-01", "1", "Part 10"},
		{"p2-02", "2", "Part 2"},
		{"p1-01", "1", "Part 1"},
		{"p2-01", "1", "Part 2"},
		{"p1-02", "2", "Part 1"},
	} {
		path := bookFile(t, dir, f.name, map[string]string{"TITLE": "Section " + f.name, "ARTIST": "Ann Author",
			"ALBUM": "Split Book", "TRACKNUMBER": f.track})
		uploadPathIn(t, ctx, svc, uc, path, "audiobook", true, b.ID, "Ann Author/Split Book/"+f.folder)
	}
	done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
	if err != nil || len(done.ReviewEntryIDs) != 1 {
		t.Fatalf("batch = %v (%v), want one entry", done.ReviewEntryIDs, err)
	}
	id := done.ReviewEntryIDs[0]
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	_, p := decidedEntry(t, ctx, svc, id)
	want := map[string]int{"p1-01.flac": 1, "p1-02.flac": 2, "p2-01.flac": 3, "p2-02.flac": 4, "p10-01.flac": 5}
	for _, doc := range p.Tracks {
		if w := want[filepath.Base(doc.Path)]; doc.TrackNo != w || doc.Tags["TRACKNUMBER"] != strconv.Itoa(w) {
			t.Errorf("%s = place %d (%s), want %d", filepath.Base(doc.Path), doc.TrackNo, doc.Tags["TRACKNUMBER"], w)
		}
	}
	if it := landedBook(t, ctx, svc, id); it.Title != "Split Book" {
		t.Errorf("book = %q, want %q", it.Title, "Split Book")
	}
}

// sentFile is one batch member: its name, track number and the folder
// it was sent from.
type sentFile struct{ name, track, folder string }

// batchUnit uploads files naming one album as a batch and answers the
// single entry it opened.
func batchUnit(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, grouping, media string, files []sentFile) string {
	t.Helper()
	dir := t.TempDir()
	yes := true
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: grouping, MediaType: media, Identify: &yes})
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		path := bookFile(t, dir, f.name, map[string]string{"TITLE": "Piece " + f.name, "ARTIST": "Ann Artist",
			"ALBUM": "Sent Whole", "TRACKNUMBER": f.track})
		uploadPathIn(t, ctx, svc, uc, path, media, true, b.ID, f.folder)
	}
	done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
	if err != nil || len(done.ReviewEntryIDs) != 1 {
		t.Fatalf("batch = %v (%v), want one entry", done.ReviewEntryIDs, err)
	}
	return done.ReviewEntryIDs[0]
}

// unitOrder is an entry's files by name, in the order it holds them.
func unitOrder(t *testing.T, ctx context.Context, svc *Library, id string) string {
	t.Helper()
	_, p := decidedEntry(t, ctx, svc, id)
	names := make([]string, 0, len(p.Tracks))
	for _, doc := range p.Tracks {
		base := filepath.Base(doc.Path)
		names = append(names, strings.TrimSuffix(base, filepath.Ext(base)))
	}
	return strings.Join(names, ",")
}

// wantPlaces fails unless a decided book's parts were numbered 1..n in
// the given order of their names.
func wantPlaces(t *testing.T, ctx context.Context, svc *Library, id string, order []string) {
	t.Helper()
	_, p := decidedEntry(t, ctx, svc, id)
	for _, doc := range p.Tracks {
		base := filepath.Base(doc.Path)
		name := strings.TrimSuffix(base, filepath.Ext(base))
		if w := slices.Index(order, name) + 1; doc.TrackNo != w || doc.Tags["TRACKNUMBER"] != strconv.Itoa(w) {
			t.Errorf("%s = place %d (%s), want %d", name, doc.TrackNo, doc.Tags["TRACKNUMBER"], w)
		}
	}
}

// Music sent from plain folders, numbered from 1 in each, comes out
// folder by folder under either grouping, not interleaved by number.
func TestMusicFromSideFoldersKeepsFolderOrder(t *testing.T) {
	files := []sentFile{
		{"b-01", "1", "Band/Record/Side B"},
		{"a-02", "2", "Band/Record/Side A"},
		{"b-02", "2", "Band/Record/Side B"},
		{"a-01", "1", "Band/Record/Side A"},
	}
	for _, grouping := range []string{groupingAlbum, groupingAuto} {
		t.Run(grouping, func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			id := batchUnit(t, ctx, svc, uc, grouping, "music", files)
			if got, want := unitOrder(t, ctx, svc, id), "a-01,a-02,b-01,b-02"; got != want {
				t.Errorf("order = %s, want %s", got, want)
			}
		})
	}
}

// Disc and track numbers that carry their totals ("3/12") order by the
// number before the total under either grouping.
func TestNumbersWithTotalsOrderByTheNumber(t *testing.T) {
	files := []struct{ name, disc, track string }{
		{"a", "1/2", "2/12"},
		{"b", "1/2", "1/12"},
		{"c", "2/2", "1/12"},
	}
	for _, grouping := range []string{groupingAlbum, groupingAuto} {
		t.Run(grouping, func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			dir := t.TempDir()
			yes := true
			b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: grouping, MediaType: "music", Identify: &yes})
			if err != nil {
				t.Fatal(err)
			}
			for _, f := range files {
				path := bookFile(t, dir, f.name, map[string]string{"TITLE": "Piece " + f.name, "ARTIST": "Ann Artist",
					"ALBUM": "Sent Whole", "DISCNUMBER": f.disc, "TRACKNUMBER": f.track})
				uploadPathIn(t, ctx, svc, uc, path, "music", true, b.ID, "Ann Artist/Sent Whole")
			}
			done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
			if err != nil || len(done.ReviewEntryIDs) != 1 {
				t.Fatalf("batch = %v (%v), want one entry", done.ReviewEntryIDs, err)
			}
			if got, want := unitOrder(t, ctx, svc, done.ReviewEntryIDs[0]), "b,a,c"; got != want {
				t.Errorf("order = %s, want %s", got, want)
			}
		})
	}
}

// A book in numbered part folders holding disc folders is numbered part
// by part and disc by disc, each level by the number its name carries.
func TestABookInNestedPartAndDiscFoldersIsNumberedInOrder(t *testing.T) {
	files := []sentFile{
		{"p10c1-01", "1", "Ann Author/Long Book/Part 10/CD1"},
		{"p2c10-01", "1", "Ann Author/Long Book/Part 2/CD10"},
		{"p1c1-02", "2", "Ann Author/Long Book/Part 1/CD1"},
		{"p2c2-01", "1", "Ann Author/Long Book/Part 2/CD2"},
		{"p2c1-01", "1", "Ann Author/Long Book/Part 2/CD1"},
		{"p1c1-01", "1", "Ann Author/Long Book/Part 1/CD1"},
	}
	order := []string{"p1c1-01", "p1c1-02", "p2c1-01", "p2c2-01", "p2c10-01", "p10c1-01"}
	for _, grouping := range []string{groupingAlbum, groupingAuto} {
		t.Run(grouping, func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			id := batchUnit(t, ctx, svc, uc, grouping, "audiobook", files)
			_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
			if err != nil {
				t.Fatal(err)
			}
			wantPartsOfOneBook(t, ctx, svc, id, warnings)
			wantPlaces(t, ctx, svc, id, order)
		})
	}
}

// Music sent from part folders and decided as an audiobook is numbered
// in the order it held as music, folder by folder.
func TestMusicDecidedAsABookKeepsItsFolderOrder(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	id := batchUnit(t, ctx, svc, uc, groupingAlbum, "music", []sentFile{
		{"p2-01", "1", "Ann Artist/Sent Whole/Part 2"},
		{"p1-02", "2", "Ann Artist/Sent Whole/Part 1"},
		{"p2-02", "2", "Ann Artist/Sent Whole/Part 2"},
		{"p1-01", "1", "Ann Artist/Sent Whole/Part 1"},
	})
	order := []string{"p1-01", "p1-02", "p2-01", "p2-02"}
	if got := unitOrder(t, ctx, svc, id); got != strings.Join(order, ",") {
		t.Errorf("music order = %s, want %s", got, strings.Join(order, ","))
	}
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	wantPlaces(t, ctx, svc, id, order)
}

// A book refused before any part lands keeps the tags it was uploaded
// with, so a later decision, under either medium, starts from them.
func TestABookRefusedBeforeAnythingLandsKeepsItsUploadedTags(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Ann Author/Unit Book",
		chapterPart(t, dir, "refused-1", "Chapter One"), chapterPart(t, dir, "refused-2", "Chapter Two"))
	failingPlan(svc, 1)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", ""); err == nil {
		t.Fatal("the decision stood, want it stopped by the failing plan")
	}
	wantUploadedTags(t, ctx, svc, id)

	svc.Ingest.planHook = nil
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "music"); err != nil {
		t.Fatal(err)
	}
	_, p := decidedEntry(t, ctx, svc, id)
	for _, doc := range p.Tracks {
		it, err := svc.lib.Get(ctx, model.PID(doc.PID))
		if err != nil {
			t.Fatal(err)
		}
		if it.Kind != model.KindTrack || it.Album != "" {
			t.Errorf("%s = %s on album %q, want a track carrying no book's album", filepath.Base(doc.Path), it.Kind, it.Album)
		}
	}
}

// A book whose stamped parts began landing finishes as one book when
// the decision is retried.
func TestAStampedBookRetriedAfterItsFirstPartFinishesOneBook(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Ann Author/Unit Book",
		chapterPart(t, dir, "retried-1", "Chapter One"), chapterPart(t, dir, "retried-2", "Chapter Two"))
	failingPlan(svc, 3)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", ""); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	if _, p := decidedEntry(t, ctx, svc, id); p.Tracks[0].PID == "" || p.Tracks[1].PID != "" {
		t.Fatalf("after the first attempt: pids %q / %q, want the first part landed alone", p.Tracks[0].PID, p.Tracks[1].PID)
	}
	svc.Ingest.planHook = nil
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	if it := landedBook(t, ctx, svc, id); it.Title != "Unit Book" {
		t.Errorf("book = %q, want %q", it.Title, "Unit Book")
	}
}

// A part the book's details cannot be written to refuses the decision
// before anything lands, naming the file, and leaves the unit as it was
// uploaded.
func TestAPartThatCannotBeStampedRefusesTheBook(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Ann Author/Unit Book",
		chapterPart(t, dir, "locked-1", "Chapter One"), chapterPart(t, dir, "locked-2", "Chapter Two"))
	_, p := decidedEntry(t, ctx, svc, id)
	locked := filepath.Dir(p.Tracks[1].Path)
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if KindOf(err) != KindConflict || !strings.Contains(err.Error(), filepath.Base(p.Tracks[1].Path)) {
		t.Fatalf("decision = %v, want a conflict naming %s", err, filepath.Base(p.Tracks[1].Path))
	}
	if status, _ := decidedEntry(t, ctx, svc, id); status != reviewPending {
		t.Errorf("entry = %s, want it still pending", status)
	}
	wantUploadedTags(t, ctx, svc, id)
	if err := os.Chmod(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
}

// With no album and no folder, or a generic one, a book is titled by
// what its file names share, less numbering and part words, and when
// that leaves no word by an untitled title its entry's id tells apart.
func TestABookFromNoFolderIsTitledByItsFileNames(t *testing.T) {
	for _, tc := range []struct {
		names []string
		want  string
	}{
		{[]string{"The Quiet Year - Part 01.mp3", "The Quiet Year - Part 02.mp3"}, "The Quiet Year"},
		{[]string{"Dune_CD1_Track01.flac", "Dune_CD1_Track02.flac", "Dune_CD2_Track01.flac"}, "Dune"},
		{[]string{"Moby Dick (Unabridged) 001.mp3", "Moby Dick (Unabridged) 002.mp3"}, "Moby Dick (Unabridged)"},
		{[]string{"Beowulf Prologue.mp3", "Beowulf Part 1.mp3"}, "Beowulf"},
		{[]string{"Interstellar.mp3", "Interstate.mp3"}, ""},
		{[]string{"01 - Chapter 1.mp3", "02 - Chapter 2.mp3"}, ""},
		{[]string{"Chapter 01.mp3", "Chapter 02.mp3"}, ""},
		{[]string{"Part 1 - Side A.mp3", "Part 1 - Side B.mp3"}, ""},
	} {
		if got := sharedNameTitle(tc.names); got != tc.want {
			t.Errorf("sharedNameTitle(%q) = %q, want %q", tc.names, got, tc.want)
		}
	}
	docs := []reviewTrackDoc{{Path: "/s/a/01 - Chapter 1.mp3", Title: "Chapter 1"}, {Path: "/s/b/02 - Chapter 2.mp3", Title: "Chapter 2"}}
	first, second := newReviewID(), newReviewID()
	for _, folder := range []string{"", "Audiobooks", "MP3", "new folder", " Untitled "} {
		got := bookUnitTitle(nil, docs, folder, first)
		if !strings.HasPrefix(got, untitledAudiobook+" (") || got != bookUnitTitle(nil, docs, folder, first) {
			t.Errorf("a book nothing names, from %q = %q, want a stable untitled title", folder, got)
		}
		if other := bookUnitTitle(nil, docs, folder, second); other == got {
			t.Errorf("two books nothing names are both %q, want them told apart", got)
		}
	}
	named := []reviewTrackDoc{{Path: "/s/a/The Quiet Year - Part 01.mp3"}, {Path: "/s/b/The Quiet Year - Part 02.mp3"}}
	if got := bookUnitTitle(nil, named, "Downloads", first); got != "The Quiet Year" {
		t.Errorf("a book from a generic folder = %q, want its file names' title", got)
	}
	if got := bookUnitTitle(nil, named, "Audio Diaries", first); got != "Audio Diaries" {
		t.Errorf("a book from a folder naming it = %q, want the folder", got)
	}
	if got := bookUnitTitle(&reviewOverride{Album: "Typed"}, docs, "Folder", first); got != "Typed" {
		t.Errorf("a typed title = %q, want it to win", got)
	}
	// A typed track title is ignored on a unit of several files.
	if got := bookUnitTitle(&reviewOverride{Title: "Chapter 1"}, docs, "Folder", first); got != "Folder" {
		t.Errorf("a typed track title = %q, want the folder", got)
	}
}

// untitledPart writes one MP3 part of a rip that names nothing: no
// album, no artist, no title.
func untitledPart(t *testing.T, dir, name string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: 2 * time.Second, Tags: map[string]string{},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// Two rips that name nothing, sent as audiobooks one after the other,
// are two books each holding its own parts once: a book nothing names
// is titled for its own entry, so the two never share the catalog's key.
func TestTwoBooksNothingNamesStayTwoBooks(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	var ids []string
	for range 2 {
		dir := t.TempDir()
		ids = append(ids, pendingUnitOf(t, ctx, svc, uc, "audiobook",
			untitledPart(t, dir, "Track 01"), untitledPart(t, dir, "Track 02")))
	}
	books := map[model.PID]string{}
	for _, id := range ids {
		_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
		if err != nil {
			t.Fatal(err)
		}
		wantPartsOfOneBook(t, ctx, svc, id, warnings)
		it := landedBook(t, ctx, svc, id)
		books[it.PID] = it.Title
		if !strings.HasPrefix(it.Title, untitledAudiobook) {
			t.Errorf("book = %q, want it titled as untitled", it.Title)
		}
		if names := bookFileNames(t, ctx, svc, it.PID); len(names) != 2 {
			t.Errorf("book %q holds %q, want its two parts once each", it.Title, names)
		}
		e, err := svc.db.ReviewEntryByID(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		if e.Title != it.Title {
			t.Errorf("entry titled %q, book %q: want the title the entry opened with", e.Title, it.Title)
		}
	}
	if len(books) != 2 {
		t.Fatalf("books = %v, want two", books)
	}
}

// A folder named for a format or a container names no book: its parts
// are titled by what their file names share.
func TestABookFromAGenericFolderIsTitledByItsFileNames(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	dir := t.TempDir()
	id := pendingUnitIn(t, ctx, svc, uc, "audiobook", "Downloads/MP3",
		chapterPart(t, dir, "The Quiet Year - Part 01", "Chapter One"),
		chapterPart(t, dir, "The Quiet Year - Part 02", "Chapter Two"))
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
	if err != nil {
		t.Fatal(err)
	}
	wantPartsOfOneBook(t, ctx, svc, id, warnings)
	if it := landedBook(t, ctx, svc, id); it.Title != "The Quiet Year" {
		t.Errorf("book = %q, want %q", it.Title, "The Quiet Year")
	}
}

// mp3Part writes one MP3 part of a book with the given tags.
func mp3Part(t *testing.T, dir, name string, tags map[string]string) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: 2 * time.Second, Tags: tags,
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// creditedFile is one batch member naming its album, artist and album
// artist.
type creditedFile struct{ name, track, folder, artist, albumArtist string }

// creditedBatch sends files naming the album "The Book" as an auto batch
// of the medium and answers the entries it opened.
func creditedBatch(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, media string, files []creditedFile) []string {
	t.Helper()
	dir := t.TempDir()
	yes := true
	b, err := svc.Ingest.CreateUploadBatch(ctx, uc, UploadBatchCreateParams{Grouping: groupingAuto, MediaType: media, Identify: &yes})
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		tags := map[string]string{"TITLE": "Section " + f.name, "ARTIST": f.artist, "ALBUM": "The Book", "TRACKNUMBER": f.track}
		if f.albumArtist != "" {
			tags["ALBUMARTIST"] = f.albumArtist
		}
		uploadPathIn(t, ctx, svc, uc, mp3Part(t, dir, f.name, tags), media, true, b.ID, f.folder)
	}
	done, err := svc.Ingest.CompleteUploadBatch(ctx, uc, b.ID)
	if err != nil {
		t.Fatal(err)
	}
	return done.ReviewEntryIDs
}

// A book's parts in part folders that share an album, a narrator
// credited beside the author on some, are one book in folder then track
// order, filed under the name every part credits, whichever part
// credits the narrator: in an audiobook batch the album groups them, and
// the stamp keys the book through its album artist, leaving each part's
// artist as it was sent. Sent as music they stay apart, as music
// clusters by artist.
func TestABooksPartsCreditingANarratorAreOneBook(t *testing.T) {
	for _, tc := range []struct{ name, first, second string }{
		{"author first", "Author", "Author; Narrator"},
		{"narrator first", "Author; Narrator", "Author"},
	} {
		files := []creditedFile{
			{name: "p2-01", track: "1", folder: "Book/Part 2", artist: tc.second},
			{name: "p1-02", track: "2", folder: "Book/Part 1", artist: tc.first},
			{name: "p2-02", track: "2", folder: "Book/Part 2", artist: tc.second},
			{name: "p1-01", track: "1", folder: "Book/Part 1", artist: tc.first},
		}
		sent := map[string]string{}
		for _, f := range files {
			sent["Section "+f.name] = f.artist
		}
		t.Run(tc.name+"/audiobook", func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			ids := creditedBatch(t, ctx, svc, uc, "audiobook", files)
			if len(ids) != 1 {
				t.Fatalf("the batch opened %d entries, want one", len(ids))
			}
			_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, ids[0], "as-is", "", "")
			if err != nil {
				t.Fatal(err)
			}
			wantPartsOfOneBook(t, ctx, svc, ids[0], warnings)
			wantPlaces(t, ctx, svc, ids[0], []string{"p1-01", "p1-02", "p2-01", "p2-02"})
			it := landedBook(t, ctx, svc, ids[0])
			if it.Title != "The Book" || it.Artist != "Author" {
				t.Errorf("book = %q by %q, want %q by %q", it.Title, it.Artist, "The Book", "Author")
			}
			bd, err := svc.lib.Book(ctx, it.PID)
			if err != nil {
				t.Fatal(err)
			}
			if len(bd.Files) != 4 {
				t.Errorf("book holds %d files, want its four parts", len(bd.Files))
			}
			for _, f := range bd.Files {
				file, err := svc.lib.File(ctx, f.FilePID)
				if err != nil {
					t.Fatal(err)
				}
				tags, _, err := parseFileTags(ctx, string(file.Path))
				if err != nil {
					t.Fatal(err)
				}
				if want := sent[tags["TITLE"]]; tags["ARTIST"] != want || tags["ALBUMARTIST"] != "Author" {
					t.Errorf("%s ARTIST %q ALBUMARTIST %q, want the artist sent (%q) and the author", tags["TITLE"], tags["ARTIST"], tags["ALBUMARTIST"], want)
				}
			}
			_, p := decidedEntry(t, ctx, svc, ids[0])
			for _, doc := range p.Tracks {
				if want := sent[doc.Tags["TITLE"]]; doc.Tags["ARTIST"] != want {
					t.Errorf("%s recorded ARTIST %q, want %q", doc.Tags["TITLE"], doc.Tags["ARTIST"], want)
				}
			}
		})
		t.Run(tc.name+"/music", func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			if ids := creditedBatch(t, ctx, svc, uc, "music", files); len(ids) != 2 {
				t.Errorf("the music batch opened %d entries, want one per artist", len(ids))
			}
		})
	}
}

// One album by two album artists, sent together from one folder as an
// audiobook batch, is two books: an album artist is the book's author.
func TestOneAlbumByTwoAuthorsIsTwoBooks(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	ids := creditedBatch(t, ctx, svc, uc, "audiobook", []creditedFile{
		{name: "a-01", track: "1", folder: "Stories", artist: "Ann Author", albumArtist: "Ann Author"},
		{name: "b-01", track: "1", folder: "Stories", artist: "Bea Writer", albumArtist: "Bea Writer"},
		{name: "a-02", track: "2", folder: "Stories", artist: "Ann Author", albumArtist: "Ann Author"},
		{name: "b-02", track: "2", folder: "Stories", artist: "Bea Writer", albumArtist: "Bea Writer"},
	})
	if len(ids) != 2 {
		t.Fatalf("the batch opened %d entries, want one per author", len(ids))
	}
	books := map[model.PID]bool{}
	for _, id := range ids {
		_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
		if err != nil {
			t.Fatal(err)
		}
		wantPartsOfOneBook(t, ctx, svc, id, warnings)
		books[landedBook(t, ctx, svc, id).PID] = true
	}
	if len(books) != 2 {
		t.Errorf("books = %v, want two", books)
	}
}

// A book is named for the folder its parts were sent from, a disc or
// part subfolder read as its parent. Batch paths are slash paths on
// every server, Windows included.
func TestABookIsNamedForTheFolderItsPartsWereSentFrom(t *testing.T) {
	for _, tc := range []struct {
		dirs []string
		want string
	}{
		{[]string{"Wren Hollis/The Hours/CD1", "Wren Hollis/The Hours/CD2"}, "The Hours"},
		{[]string{"Wren Hollis/The Hours/Part 1", "Wren Hollis/The Hours/Part 2"}, "The Hours"},
		{[]string{"Wren Hollis/The Hours", "Wren Hollis/The Hours/Disc 2"}, "The Hours"},
		{[]string{"Wren Hollis/The Hours/CD1"}, "The Hours"},
		{[]string{"Wren Hollis/The Hours/Part 1", "Wren Hollis/The Hours/Part 1"}, "The Hours"},
		{[]string{"Wren Hollis/The Hours"}, "The Hours"},
		{[]string{"Shelf/First", "Shelf/Second"}, "Shelf"},
		{[]string{"First", "Second"}, ""},
		{[]string{"", ""}, ""},
	} {
		if got := unitFolderName(tc.dirs); got != tc.want {
			t.Errorf("unitFolderName(%q) = %q, want %q", tc.dirs, got, tc.want)
		}
	}
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
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", ""); err == nil {
		t.Fatal("the first attempt stood, want it stopped by the failing plan")
	}
	_, p := decidedEntry(t, ctx, svc, id)
	if p.Tracks[0].PID == "" || p.Tracks[1].PID != "" {
		t.Fatalf("after the first attempt: pids %q / %q, want the first part landed alone", p.Tracks[0].PID, p.Tracks[1].PID)
	}
	var plans atomic.Int32
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		plans.Add(1)
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	_, warnings, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "")
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
	up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "twelve.flac", SizeBytes: int64(len(data)), MediaType: "music",
		SHA256: hex.EncodeToString(sum[:]), Identify: &no,
	})
	if err != nil {
		t.Fatal(err)
	}
	if up.Duplicate == nil {
		t.Fatal("the same bytes opened with no warning")
	}
	if _, err := svc.Ingest.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	svc.Ingest.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		if meta.Copy {
			return nil, errors.New("the catalog could not be read")
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	done, err := svc.Ingest.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if done.Duplicate == nil || done.Duplicate.Kind != "content" || done.State != uploadStaged {
		t.Fatalf("after a check that could not run = %s with duplicate %+v, want the content warning kept and the copy waiting", done.State, done.Duplicate)
	}
}
