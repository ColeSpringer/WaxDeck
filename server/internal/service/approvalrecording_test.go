package service

import (
	"context"
	"errors"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// ownRecording is a recording id a file arrives carrying.
const ownRecording = "9d4a7f51-be60-4182-ad3e-4f5a6b7c8d9e"

type recordingFixture struct {
	ctx  context.Context
	svc  *Library
	uc   *UserCtx
	root string
	path string
	pid  string // the track's API pid
}

// openRecordingFixture is one scanned track in a managed library, tagged
// with extra.
func openRecordingFixture(t *testing.T, extra map[string]string) recordingFixture {
	t.Helper()
	return openRecordingFixtureWith(t, extra, nil)
}

// openRecordingFixtureWith is openRecordingFixture with the service's
// config changed by mutate first.
func openRecordingFixtureWith(t *testing.T, extra map[string]string, mutate func(*Config)) recordingFixture {
	t.Helper()
	tags := map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"}
	maps.Copy(tags, extra)
	var root string
	var paths []string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		if mutate != nil {
			mutate(c)
		}
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
		var err error
		if paths, err = fixtures.Generate(root, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: tags,
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	pid, _ := fixtureTrackPID(t, ctx, svc, uc, "Stray")
	return recordingFixture{ctx: ctx, svc: svc, uc: uc, root: root, path: paths[0], pid: pid}
}

func (f recordingFixture) item(t *testing.T) *model.ItemView {
	t.Helper()
	_, bare, _ := parseAPIPID(f.pid)
	it, err := f.svc.lib.Get(f.ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	return it
}

// approve applies a release whose recording for the track is recording.
func (f recordingFixture) approve(t *testing.T, recording string) string {
	t.Helper()
	cand := reviewCandidateDoc{
		MBID: approvedRelease, ReleaseGroupMBID: approvedGroup,
		Title: "The Release", Artist: "The Release Artist", TrackCount: 1, SimilarityPct: 97,
		Pairings: []reviewPairingDoc{{TrackIndex: 0, Position: 1, Title: "Stray", RecordingMBID: recording}},
	}
	e := pendingMatch(t, f.ctx, f.svc, cand, f.item(t))
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err != nil {
		t.Fatalf("approve: %v", err)
	}
	return e.ID
}

// reread forces a re-read of every file and returns the track's pid
// after it, found by title: the catalog is the one to key the file.
func (f recordingFixture) reread(t *testing.T) string {
	t.Helper()
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{Force: true}); err != nil {
		t.Fatal(err)
	}
	pid, _ := fixtureTrackPID(t, f.ctx, f.svc, f.uc, "Stray")
	return pid
}

// An approved track keeps its pid when its file is read again, and the
// approval's other values reach the file while its recording id stays in
// the catalog.
func TestAnApprovedTrackKeepsItsPidThroughAForcedReRead(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	f.approve(t, approvedTrack)
	if got := fileTag(t, f.path, tag.Album); got != "The Release" {
		t.Errorf("file album = %q, want the approved release written", got)
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Errorf("file recording id = %q, want it kept out of the file", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Album != "The Release" {
		t.Fatalf("after the re-read: recording %q, album %q; want the approval's", it.MBID, it.Album)
	}
}

// The organize move an approval's new album asks for keeps the pid, and
// so does reading the moved file again.
func TestAnApprovedTrackKeepsItsPidThroughAnOrganizeMove(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	f.approve(t, approvedTrack)
	start, err := f.svc.Health.StartHealthFix(f.ctx, f.uc, rulePathMismatch, []string{f.pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, f.ctx, f.svc, f.uc, start.TaskID); sum.Moved == nil || *sum.Moved != 1 {
		t.Fatalf("path fix %+v, want the approved track moved", sum)
	}
	if it := f.item(t); it.PID == "" || string(it.Path) == f.path {
		t.Fatalf("item after the move = %s at %s, want it moved under its pid", it.PID, it.Path)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after the move and a re-read = %s, want %s kept", got, f.pid)
	}
}

// The catalog answers the recording id an approval recorded, and the
// file's lacking it is nothing the health rule or its fix acts on.
func TestTheCatalogAnswersAnApprovedRecordingID(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	f.approve(t, approvedTrack)
	items, err := f.svc.lib.Query(f.ctx, visibleTracks().Where("mbid", query.OpIs, approvedTrack).Build(), "")
	if err != nil || len(items) != 1 || apiPID(PrefixTrack, items[0].PID) != f.pid {
		t.Fatalf("tracks by the recording id = %v (%v), want the approved track", items, err)
	}
	dto, err := f.svc.Reads.Item(f.ctx, f.uc, f.pid)
	if err != nil || dto.MBID != approvedTrack {
		t.Fatalf("item recording id = %q (%v), want the approval's", dto.MBID, err)
	}
	if got := writeUnsyncedIssues(t, f.ctx, f.svc, f.uc); len(got) != 0 {
		t.Fatalf("tags out of sync = %v, want none for a catalog-only recording id", got)
	}
	start, err := f.svc.Health.StartHealthFix(f.ctx, f.uc, ruleWriteUnsynced, []string{f.pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, f.ctx, f.svc, f.uc, start.TaskID); sum.Skipped["already in sync"] != 1 {
		t.Fatalf("write fix %+v, want the track already in sync", sum)
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Fatalf("file recording id after the fix = %q, want none", got)
	}
}

// A file that arrived with its own recording id is keyed by it as
// before: an approval naming another leaves the file's alone and the pid
// in place, and a second encoding carrying the same id joins the item.
func TestAFileWithItsOwnRecordingIDIsKeyedAsBefore(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording})
	if it := f.item(t); it.MBID != ownRecording {
		t.Fatalf("scanned recording id = %q, want the file's", it.MBID)
	}
	f.approve(t, approvedTrack)
	if got := fileTag(t, f.path, tag.MBRecordingID); got != ownRecording {
		t.Errorf("file recording id = %q, want its own kept", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack {
		t.Fatalf("recording id after the re-read = %q, want the approval's", it.MBID)
	}
	if _, err := fixtures.Generate(f.root, fixtures.Spec{
		Name: "stray-again", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "MUSICBRAINZ_TRACKID": ownRecording},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	items, err := f.svc.lib.Query(f.ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 1 || apiPID(PrefixTrack, items[0].PID) != f.pid {
		t.Fatalf("items = %v (%v), want the second encoding joined to the track", items, err)
	}
}

// A revert puts the recording id back in the catalog, unlocked, and the
// file and pid stay as they were.
func TestRevertingAnApprovalRestoresTheRecordingID(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	id := f.approve(t, approvedTrack)
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	it := f.item(t)
	if it.MBID != "" || it.Album != "Wander" {
		t.Fatalf("after the revert: recording %q, album %q; want the file's", it.MBID, it.Album)
	}
	prov, err := f.svc.lib.Provenance(f.ctx, it.PID)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range prov {
		if p.Field == "mbid" && p.Locked {
			t.Fatalf("recording id still locked after the revert: %+v", p)
		}
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Fatalf("file recording id = %q, want none", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a re-read = %s, want %s kept", got, f.pid)
	}
	if got := writeUnsyncedIssues(t, f.ctx, f.svc, f.uc); len(got) != 0 {
		t.Fatalf("tags out of sync = %v, want none", got)
	}
}

// A hand edit of a track's recording id with write-back keeps it in the
// catalog, and the pid survives the next read of the file.
func TestAHandEditedRecordingIDKeepsThePid(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid,
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, MetadataEditParams{WriteBack: true, Lock: true}); err != nil {
		t.Fatal(err)
	}
	if got := fileTag(t, f.path, tag.Genre); got != "Dub" {
		t.Errorf("file genre = %q, want the edit written", got)
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Errorf("file recording id = %q, want it kept out of the file", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack {
		t.Fatalf("recording id after the re-read = %q, want the edit's", it.MBID)
	}
	if got := writeUnsyncedIssues(t, f.ctx, f.svc, f.uc); len(got) != 0 {
		t.Fatalf("tags out of sync = %v, want none", got)
	}
}

// A bulk edit of a track's recording id with write-back keeps it in the
// catalog too, and writes the rest.
func TestABulkEditedRecordingIDKeepsThePid(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	out, err := f.svc.Editor.BulkEditMetadata(f.ctx, f.uc, []string{f.pid},
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, true, false, false)
	if err != nil || len(out.Edited) != 1 || len(out.Failures) != 0 {
		t.Fatalf("bulk edit = %+v (%v), want the track edited", out, err)
	}
	if got := fileTag(t, f.path, tag.Genre); got != "Dub" {
		t.Errorf("file genre = %q, want the edit written", got)
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Errorf("file recording id = %q, want it kept out of the file", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Genre != "Dub" {
		t.Fatalf("after the re-read: recording %q, genre %q; want the edit's", it.MBID, it.Genre)
	}
}

// The editor's vocabulary says a track's recording id stays in the
// catalog.
func TestATracksRecordingIDIsNotAWriteBackField(t *testing.T) {
	t.Parallel()
	for _, f := range editorFieldsForKind(model.KindTrack) {
		if f.Name == recordingIDField && f.WriteBack {
			t.Fatalf("track %s writes back, want it catalog-only", f.Name)
		}
	}
}

// A locked recording id refuses an unforced edit naming it before
// anything moves, and a bulk edit with skipLocked skips its item whole.
func TestALockedRecordingIDHoldsTheWholeEdit(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid,
		map[string]string{"mbid": ownRecording}, MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	edit := map[string]string{"mbid": approvedTrack, "genre": "Dub"}
	if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid, edit, MetadataEditParams{WriteBack: true, Lock: true}); err == nil {
		t.Fatal("an edit over a locked recording id stood, want it refused")
	}
	out, err := f.svc.Editor.BulkEditMetadata(f.ctx, f.uc, []string{f.pid}, edit, true, true, false)
	if err != nil || len(out.Edited) != 0 || len(out.Skipped) != 1 {
		t.Fatalf("bulk edit = %+v (%v), want the track skipped", out, err)
	}
	if it := f.item(t); it.MBID != ownRecording || it.Genre == "Dub" {
		t.Fatalf("item = recording %q, genre %q; want neither edit landed", it.MBID, it.Genre)
	}
	if got := fileTag(t, f.path, tag.Genre); got == "Dub" {
		t.Fatalf("file genre = %q, want it untouched", got)
	}
}

// locked reports whether one of the track's fields is locked.
func (f recordingFixture) locked(t *testing.T, field string) bool {
	t.Helper()
	prov, err := f.svc.lib.Provenance(f.ctx, f.item(t).PID)
	if err != nil {
		t.Fatal(err)
	}
	return slices.ContainsFunc(prov, func(p model.FieldProvenance) bool { return p.Field == field && p.Locked })
}

// An edit of a track's recording id holds it locked whatever the edit's
// lock says: no file carries it, so an unlocked one would be cleared by
// the next read of the file. The other fields keep the edit's lock.
func TestAnUnlockedRecordingIDEditSurvivesAForcedReRead(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		fields    map[string]string
		writeBack bool
	}{
		"beside a written field": {map[string]string{"mbid": approvedTrack, "genre": "Dub"}, true},
		"alone":                  {map[string]string{"mbid": approvedTrack}, true},
		"catalog only":           {map[string]string{"mbid": approvedTrack, "genre": "Dub"}, false},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := openRecordingFixture(t, nil)
			if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid, c.fields,
				MetadataEditParams{WriteBack: c.writeBack}); err != nil {
				t.Fatal(err)
			}
			if _, ok := c.fields["genre"]; ok && f.locked(t, "genre") {
				t.Error("genre locked, want the edit's lock kept for it")
			}
			if got := f.reread(t); got != f.pid {
				t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
			}
			if it := f.item(t); it.MBID != approvedTrack {
				t.Fatalf("recording id after a forced re-read = %q, want the edit's", it.MBID)
			}
		})
	}
}

// Reverting a second approval restores the first's recording id, which
// no file carries, held locked, so a forced re-read keeps it.
func TestRevertingASecondApprovalKeepsTheFirstsRecordingID(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	f.approve(t, approvedTrack)
	id := f.approve(t, ownRecording)
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack {
		t.Fatalf("recording id after the revert and a re-read = %q, want the first approval's", it.MBID)
	}
	prov, err := f.svc.lib.Provenance(f.ctx, f.item(t).PID)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range prov {
		if p.Field == recordingIDField &&
			(p.Source != model.SourceEnrichment || p.Provider != reviewMatchProvider || !p.Locked) {
			t.Fatalf("restored recording id provenance = %+v, want the first approval's, locked", p)
		}
	}
}

// A revert restoring the recording id the file itself carries leaves it
// unlocked, as any value the file states.
func TestRevertingToAFilesOwnRecordingIDUnlocksIt(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording})
	id := f.approve(t, approvedTrack)
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	if it := f.item(t); it.MBID != ownRecording {
		t.Fatalf("recording id after the revert = %q, want the file's", it.MBID)
	}
	if f.locked(t, "mbid") {
		t.Fatal("the file's own recording id is locked after the revert, want it unlocked")
	}
}

// A request cancelled once an edit's other fields have committed still
// records the recording id beside them, and the write-back failures of
// the fields that went first stay in the result.
func TestACancelledEditStillRecordsItsRecordingID(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	unwritable(t, f.path)
	ctx, cancel := context.WithCancel(f.ctx)
	defer cancel()
	f.svc.Editor.recordingIDsHook = func() error { cancel(); return nil }
	out, err := f.svc.Editor.EditItemMetadata(ctx, f.uc, f.pid,
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, MetadataEditParams{WriteBack: true, Lock: true})
	if err != nil {
		t.Fatalf("edit = %v, want it to stand", err)
	}
	if len(out.Failures) == 0 {
		t.Error("edit reported no write-back failure, want the unwritable file's")
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Genre != "Dub" {
		t.Fatalf("item = recording %q, genre %q; want both edited", it.MBID, it.Genre)
	}
}

// A bulk edit whose request is cancelled once its other fields have
// committed records the recording ids too, and reports the batch edited.
func TestACancelledBulkEditStillRecordsItsRecordingIDs(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	ctx, cancel := context.WithCancel(f.ctx)
	defer cancel()
	f.svc.Editor.recordingIDsHook = func() error { cancel(); return nil }
	out, err := f.svc.Editor.BulkEditMetadata(ctx, f.uc, []string{f.pid},
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, true, false, false)
	if err != nil || len(out.Edited) != 1 {
		t.Fatalf("bulk edit = %+v (%v), want the track edited", out, err)
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Genre != "Dub" {
		t.Fatalf("item = recording %q, genre %q; want both edited", it.MBID, it.Genre)
	}
}

// A revert whose recording ids fail to restore once its other fields
// have is not taken as done: the entry stays applied, and a retry
// finishes it.
func TestARevertThatFailsAtItsRecordingIDsStaysApplied(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	id := f.approve(t, approvedTrack)
	f.svc.Ingest.recordingIDsHook = func() error { return errors.New("the catalog went away") }
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err == nil {
		t.Fatal("the revert stood without its recording ids, want it failed")
	}
	if status, _ := decidedEntry(t, f.ctx, f.svc, id); status != reviewApplied {
		t.Fatalf("entry = %s, want it still applied", status)
	}
	f.svc.Ingest.recordingIDsHook = nil
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("retried revert: %v", err)
	}
	if it := f.item(t); it.Album != "Wander" || it.MBID != "" {
		t.Fatalf("after the retry: album %q, recording %q; want both restored", it.Album, it.MBID)
	}
}

// In a bulk edit naming a track and a book, the book's recording id
// reaches its file as the catalog writes it and the track's stays in the
// catalog.
func TestABulkEditSplitsRecordingIDsByKind(t *testing.T) {
	t.Parallel()
	books := t.TempDir()
	var music string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		music = c.Roots[0].Path
		c.Roots = append(c.Roots, Root{Name: "books", Path: books, Media: "audiobook", Managed: true})
	})
	trackPaths, err := fixtures.Generate(music, fixtures.Spec{Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"}})
	if err != nil {
		t.Fatal(err)
	}
	bookPaths, err := fixtures.Generate(books, fixtures.Spec{Name: "tome", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Tome", "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author", "ALBUM": "Tome", "TRACKNUMBER": "1"}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Stray")
	views, err := svc.lib.Query(ctx, visibleItems().Where("kind", query.OpIs, string(model.KindBook)).Build(), "")
	if err != nil || len(views) != 1 {
		t.Fatalf("books = %v (%v), want one", views, err)
	}
	book := apiPID(PrefixBook, views[0].PID)
	out, err := svc.Editor.BulkEditMetadata(ctx, uc, []string{track, book},
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, true, false, false)
	if err != nil || len(out.Edited) != 2 || len(out.Failures) != 0 {
		t.Fatalf("bulk edit = %+v (%v), want both edited", out, err)
	}
	if got := fileTag(t, bookPaths[0], tag.MBReleaseID); got != approvedTrack {
		t.Errorf("book file release id = %q, want the edit written", got)
	}
	if got := fileTag(t, trackPaths[0], tag.MBRecordingID); got != "" {
		t.Errorf("track file recording id = %q, want it kept out of the file", got)
	}
	for _, p := range []string{trackPaths[0], bookPaths[0]} {
		if got := fileTag(t, p, tag.Genre); got != "Dub" {
			t.Errorf("%s genre = %q, want the edit written", filepath.Base(p), got)
		}
	}
}

// A track owing its file both its recording id and another value is
// listed for the other, and the fix writes that one and never the id.
func TestAWriteFixPaysTheOtherOwedKeysAndNotTheRecordingID(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid,
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	if got := writeUnsyncedIssues(t, f.ctx, f.svc, f.uc); len(got) != 1 || got[0] != f.pid {
		t.Fatalf("tags out of sync = %v, want the track for its genre", got)
	}
	start, err := f.svc.Health.StartHealthFix(f.ctx, f.uc, ruleWriteUnsynced, []string{f.pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, f.ctx, f.svc, f.uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("write fix %+v, want the track filled", sum)
	}
	if got := fileTag(t, f.path, tag.Genre); got != "Dub" {
		t.Errorf("file genre = %q, want the owed genre written", got)
	}
	if got := fileTag(t, f.path, tag.MBRecordingID); got != "" {
		t.Errorf("file recording id = %q, want it kept out of the file", got)
	}
	if got := writeUnsyncedIssues(t, f.ctx, f.svc, f.uc); len(got) != 0 {
		t.Fatalf("tags out of sync after the fix = %v, want none", got)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack {
		t.Fatalf("recording id after the re-read = %q, want the edit's", it.MBID)
	}
}

// A track's recording id its file does not carry cannot be unlocked: the
// refusal says why, and the id survives a forced re-read.
func TestARecordingIDTheFileLacksCannotBeUnlocked(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, nil)
	f.approve(t, approvedTrack)
	_, err := f.svc.Editor.SetItemLocks(f.ctx, f.uc, f.pid, []string{"mbid", "genre"}, false)
	if err == nil || RefusalParams(err)["reason"] != "recording-id-held" {
		t.Fatalf("unlock = %v (params %v), want refused as recording-id-held", err, RefusalParams(err))
	}
	if !f.locked(t, "mbid") || !f.locked(t, "album") {
		t.Fatal("the refused unlock moved a lock, want none moved")
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != approvedTrack {
		t.Fatalf("recording id after a forced re-read = %q, want the approval's", it.MBID)
	}
}

// A recording id the file carries unlocks as any field.
func TestARecordingIDTheFileCarriesUnlocks(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording})
	if _, err := f.svc.Editor.SetItemLocks(f.ctx, f.uc, f.pid, []string{"mbid"}, true); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Editor.SetItemLocks(f.ctx, f.uc, f.pid, []string{"mbid"}, false); err != nil {
		t.Fatalf("unlock = %v, want it to stand", err)
	}
	if f.locked(t, "mbid") {
		t.Fatal("recording id still locked, want it unlocked")
	}
}

// unwritable makes files and their folders read-only for the test, which
// root ignores.
func unwritable(t *testing.T, paths ...string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root writes through read-only permissions")
	}
	for _, p := range paths {
		for _, q := range []string{p, filepath.Dir(p)} {
			mode := os.FileMode(0o444)
			if q != p {
				mode = 0o555
			}
			if err := os.Chmod(q, mode); err != nil {
				t.Fatal(err)
			}
		}
	}
	t.Cleanup(func() {
		for _, p := range paths {
			_ = os.Chmod(filepath.Dir(p), 0o755)
			_ = os.Chmod(p, 0o644)
		}
	})
}

// cancelAtWriteFailure is a log handler that, once armed, cancels a
// request at the catalog's first failed tag write, inside its write pass.
type cancelAtWriteFailure struct {
	cancel *atomic.Pointer[context.CancelFunc]
}

func (h cancelAtWriteFailure) Enabled(context.Context, slog.Level) bool { return true }
func (h cancelAtWriteFailure) WithAttrs([]slog.Attr) slog.Handler       { return h }
func (h cancelAtWriteFailure) WithGroup(string) slog.Handler            { return h }
func (h cancelAtWriteFailure) Handle(_ context.Context, r slog.Record) error {
	if c := h.cancel.Load(); c != nil && r.Message == "tag write-back" {
		(*c)()
	}
	return nil
}

// twoFileTrack is a track with two encodings, both unwritable, whose
// request the catalog's first failed write cancels once arm has run.
func twoFileTrack(t *testing.T) (f recordingFixture, arm func() (context.Context, context.CancelFunc)) {
	t.Helper()
	var cancel atomic.Pointer[context.CancelFunc]
	f = openRecordingFixtureWith(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording}, func(c *Config) {
		c.Logger = slog.New(cancelAtWriteFailure{cancel: &cancel})
	})
	second, err := fixtures.Generate(f.root, fixtures.Spec{
		Name: "stray-again", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "MUSICBRAINZ_TRACKID": ownRecording},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if refs, err := f.svc.lib.ItemFiles(f.ctx, f.item(t).PID); err != nil || len(refs) != 2 {
		t.Fatalf("track files = %v (%v), want two", refs, err)
	}
	unwritable(t, f.path, second[0])
	return f, func() (context.Context, context.CancelFunc) {
		ctx, stop := context.WithCancel(f.ctx)
		cancel.Store(&stop)
		return ctx, stop
	}
}

// An edit cancelled inside its write pass, after the catalog committed,
// still records the recording id beside the other fields.
func TestAnEditCancelledInItsWritePassStillRecordsItsRecordingID(t *testing.T) {
	t.Parallel()
	f, arm := twoFileTrack(t)
	ctx, stop := arm()
	defer stop()
	if _, err := f.svc.Editor.EditItemMetadata(ctx, f.uc, f.pid,
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, MetadataEditParams{WriteBack: true, Lock: true}); err == nil {
		t.Fatal("edit stood, want the cancellation answered")
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Genre != "Dub" {
		t.Fatalf("item = recording %q, genre %q; want both edited", it.MBID, it.Genre)
	}
	if !f.locked(t, recordingIDField) {
		t.Fatal("recording id unlocked, want it held")
	}
}

// A bulk edit cancelled inside its write pass records the recording ids
// too.
func TestABulkEditCancelledInItsWritePassStillRecordsItsRecordingIDs(t *testing.T) {
	t.Parallel()
	f, arm := twoFileTrack(t)
	ctx, stop := arm()
	defer stop()
	if _, err := f.svc.Editor.BulkEditMetadata(ctx, f.uc, []string{f.pid},
		map[string]string{"mbid": approvedTrack, "genre": "Dub"}, true, false, false); err == nil {
		t.Fatal("bulk edit stood, want the cancellation answered")
	}
	if it := f.item(t); it.MBID != approvedTrack || it.Genre != "Dub" {
		t.Fatalf("item = recording %q, genre %q; want both edited", it.MBID, it.Genre)
	}
}

// A file carrying a different recording id than the catalog lets it be
// unlocked: the file's own id comes back on the next read, keying the
// track as before.
func TestARecordingIDTheFileContradictsUnlocks(t *testing.T) {
	t.Parallel()
	f := openRecordingFixture(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording})
	f.approve(t, approvedTrack)
	if _, err := f.svc.Editor.SetItemLocks(f.ctx, f.uc, f.pid, []string{recordingIDField}, false); err != nil {
		t.Fatalf("unlock = %v, want it to stand", err)
	}
	if got := f.reread(t); got != f.pid {
		t.Fatalf("pid after a forced re-read = %s, want %s kept", got, f.pid)
	}
	if it := f.item(t); it.MBID != ownRecording {
		t.Fatalf("recording id after a forced re-read = %q, want the file's", it.MBID)
	}
}

// An edit locks a recording id only when it is one the file lacks; a
// cleared id or the file's own follows the edit's lock.
func TestAnEditLocksOnlyARecordingIDTheFileLacks(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		id     string
		locked bool
	}{
		"one the file lacks": {approvedTrack, true},
		"the file's own":     {ownRecording, false},
		"cleared":            {"", false},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := openRecordingFixture(t, map[string]string{"MUSICBRAINZ_TRACKID": ownRecording})
			if _, err := f.svc.Editor.EditItemMetadata(f.ctx, f.uc, f.pid,
				map[string]string{"mbid": c.id, "genre": "Dub"}, MetadataEditParams{WriteBack: true}); err != nil {
				t.Fatal(err)
			}
			if got := f.locked(t, recordingIDField); got != c.locked {
				t.Fatalf("recording id locked = %v, want %v", got, c.locked)
			}
			if f.locked(t, "genre") {
				t.Fatal("genre locked, want the edit's lock kept for it")
			}
		})
	}
}
