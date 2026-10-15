package api

import (
	"context"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// joinHarness is a server whose roots take imports, answering the
// canned releases, with an uploader beside the administrator.
func joinHarness(t *testing.T, releases ...*match.Release) (*harness, string) {
	t.Helper()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: releases}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "bob", "password": testPassword, "uploadEnabled": true,
		"permissions": map[string]any{"download": true, "delete": false, "explicitContent": true},
	}), 201, "an uploader")
	return h, loginAs(t, h.ts, "bob", testPassword).Token
}

// mayCurateAs reads whether a caller may edit an item.
func mayCurateAs(t *testing.T, h *harness, token, pid string) bool {
	t.Helper()
	return decodeStatus[ItemPermissions](t, reqAs(t, h, "GET", "/api/v1/items/"+pid+"/permissions", token, nil),
		200, "item permissions").MayCurate
}

// decideAs decides a review entry as a caller, answering the result.
func decideAs(t *testing.T, h *harness, token, entryID string, body map[string]any) ReviewDecideResult {
	t.Helper()
	return decodeStatus[ReviewDecideResult](t, postJSONAs(t, h, token, "/api/v1/review/queue/"+entryID+"/decide", body),
		200, "decide "+entryID)
}

// reviewAs reads a review entry as a caller.
func reviewAs(t *testing.T, h *harness, token, entryID string) ReviewEntryDetail {
	t.Helper()
	return decodeStatus[ReviewEntryDetail](t, reqAs(t, h, "GET", "/api/v1/review/queue/"+entryID, token, nil),
		200, "review entry")
}

// A second account uploading audio the library holds gets a warning on
// completion and in the review pane; adding it anyway attaches the file
// to the item as a copy, leaves the item's metadata alone, and gives the
// uploader no right to edit it.
func TestDuplicateUploadJoinsWithoutRights(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid

	// The library's alpha, tagged as something else.
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "alpha", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Bob Takeover", "ARTIST": "Bob", "ALBUM": "Hijack Demo"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, bob, paths[0], "music", "")
	if up.Duplicate == nil || up.Duplicate.Kind != "content" || up.Duplicate.ItemPid == nil || *up.Duplicate.ItemPid != alpha {
		t.Fatalf("completion duplicate = %+v, want a content match on %s", up.Duplicate, alpha)
	}
	drainMatches(t, h)
	entry := reviewAs(t, h, bob, *up.ReviewEntryId)
	if entry.Status != "pending" || len(entry.Tracks) != 1 || entry.Tracks[0].Duplicate == nil ||
		entry.Tracks[0].Duplicate.Kind != "content" || entry.Tracks[0].Duplicate.Title == nil ||
		*entry.Tracks[0].Duplicate.Title != "Alpha Song" {
		t.Fatalf("review entry = %+v, want it pending with the duplicate named", entry)
	}
	page := decodeStatus[ReviewEntryPage](t, reqAs(t, h, "GET", "/api/v1/review/queue?status=pending", bob, nil), 200, "queue")
	if len(page.Entries) != 1 || page.Entries[0].DuplicateCount == nil || *page.Entries[0].DuplicateCount != 1 {
		t.Fatalf("queue rows = %+v, want one carrying a duplicate count", page.Entries)
	}

	res := decideAs(t, h, bob, *up.ReviewEntryId, map[string]any{"action": "as-is"})
	if res.Warnings == nil || !slices.ContainsFunc(*res.Warnings, func(w string) bool { return strings.Contains(w, "already in the library") }) {
		t.Fatalf("decide warnings = %v, want the joined file named", res.Warnings)
	}
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+alpha, h.token))
	if item.Title != "Alpha Song" || item.Album == nil || *item.Album != "Fixture Album" || item.Copies == nil || *item.Copies != 1 {
		t.Fatalf("item after the decide = %q / %v / copies %v, want it unchanged with one copy", item.Title, item.Album, item.Copies)
	}
	if mayCurateAs(t, h, bob, alpha) {
		t.Fatal("the uploader of a duplicate may edit the item it joined")
	}
	wantStatus(t, reqAs(t, h, "PATCH", "/api/v1/items/"+alpha+"/metadata", bob, map[string]any{
		"fields": map[string]string{"title": "Hijacked"},
	}), 403, "the uploader's edit")
	if dl := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+alpha+"/download-info", h.token)); len(dl.Files) != 1 {
		t.Fatalf("download-info files = %d, want the original alone", len(dl.Files))
	}
	if joined := reviewAs(t, h, bob, *up.ReviewEntryId).Tracks[0]; joined.Joined == nil || !*joined.Joined {
		t.Fatalf("decided track = %+v, want it marked joined", joined)
	}
	if u := decode[Upload](t, reqAs(t, h, "GET", "/api/v1/uploads/"+up.Id, bob, nil)); u.State != "imported" || u.Duplicate == nil {
		t.Fatalf("session = %+v, want it imported with its warning kept", u)
	}
}

// An uploader who cannot see the item their file duplicates is warned
// without being told which item it is.
func TestADuplicateOutOfReachNamesNothing(t *testing.T) {
	t.Parallel()
	h, _ := joinHarness(t)
	elsewhere := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "elsewhere", "path": t.TempDir(),
	}), 201, "a second library")
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "carol", "password": testPassword, "uploadEnabled": true,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{elsewhere.Pid}},
	}), 201, "an uploader granted another library")
	carol := loginAs(t, h.ts, "carol", testPassword).Token
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "bravo", Codec: fixtures.CodecMP3, Duration: 2500 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Carol's Bravo"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, carol, paths[0], "music", "")
	if d := up.Duplicate; d == nil || d.Kind != "content" || d.ItemPid != nil || d.Title != nil || d.Artist != nil {
		t.Fatalf("completion duplicate = %+v, want the kind alone", d)
	}
	// Added anyway, the copy joins that item, and the decided entry does
	// not name it either.
	decideAs(t, h, carol, *up.ReviewEntryId, map[string]any{"action": "as-is"})
	tracks := reviewAs(t, h, carol, *up.ReviewEntryId).Tracks
	if len(tracks) != 1 || tracks[0].Joined == nil || !*tracks[0].Joined || tracks[0].Pid != nil {
		t.Fatalf("decided tracks = %+v, want the joined copy with no pid", tracks)
	}
}

// Approving a match for a unit with a joined file edits the files the
// import brought in and leaves the item the duplicate joined as it was;
// the revert restores only what the approve edited. The unit's duplicate
// keeps the automatic apply from running in a library set to apply on
// its own.
func TestApproveLeavesAJoinedItemAlone(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t, nightfallRelease())
	if _, err := fixtures.Generate(h.library, messyNightfallSpecs()[0]); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	harbor := h.itemTitled(t, h.token, "Harbor Lights").Pid
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/matching", map[string]any{"mode": "auto"}), 200, "auto matching")

	// The library's Harbor Lights again, and Copper Sky, as one album.
	specs := messyNightfallSpecs()[:2]
	paths, err := fixtures.Generate(t.TempDir(), specs...)
	if err != nil {
		t.Fatal(err)
	}
	batch := createBatch(t, h, bob, "album", "music")
	for _, p := range paths {
		uploadBatchMember(t, h, bob, p, "music", batch.Id, "")
	}
	entryID := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds[0]
	drainMatches(t, h)
	entry := reviewAs(t, h, bob, entryID)
	if entry.Status != "pending" || entry.Best == nil || entry.Best.Mbid != "rel-nightfall" {
		t.Fatalf("entry = %s (best %+v), want a confident match held for a person", entry.Status, entry.Best)
	}

	res := decideAs(t, h, bob, entryID, map[string]any{"action": "approve", "candidateMbid": "rel-nightfall"})
	if res.Warnings == nil || !slices.ContainsFunc(*res.Warnings, func(w string) bool { return strings.Contains(w, "metadata was left alone") }) {
		t.Fatalf("approve warnings = %v, want the joined file named", res.Warnings)
	}
	held := decode[Item](t, get(t, h.ts, "/api/v1/items/"+harbor, h.token))
	if held.Artist == nil || *held.Artist != "The Cardnal Waves" {
		t.Fatalf("the joined item's artist = %v, want the tag it had", held.Artist)
	}
	if locks := h.itemMeta(t, harbor).LockedFields; len(locks) > 0 {
		t.Fatalf("the joined item carries locks %v after the approve", locks)
	}
	copper := h.itemTitled(t, h.token, "Copper Sky").Pid
	if got := decode[Item](t, get(t, h.ts, "/api/v1/items/"+copper, h.token)); got.Artist == nil || *got.Artist != "The Cardinal Waves" {
		t.Fatalf("the imported item's artist = %v, want the release's", got.Artist)
	}
	if !mayCurateAs(t, h, bob, copper) || mayCurateAs(t, h, bob, harbor) {
		t.Fatal("rights: want the imported item the uploader's and the joined one not")
	}

	wantStatus(t, h.postJSON(t, "/api/v1/review/queue/"+entryID+"/revert", nil), 200, "revert")
	if got := decode[Item](t, get(t, h.ts, "/api/v1/items/"+copper, h.token)); got.Artist == nil || *got.Artist != "The Cardnal Waves" {
		t.Fatalf("the reverted item's artist = %v, want its tag back", got.Artist)
	}
	if held := decode[Item](t, get(t, h.ts, "/api/v1/items/"+harbor, h.token)); held.Artist == nil || *held.Artist != "The Cardnal Waves" {
		t.Fatalf("the joined item's artist after the revert = %v", held.Artist)
	}
}

// A single that duplicates the library waits for a person even where
// singles apply on their own.
func TestAutoApplyWaitsForAFlaggedDuplicate(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t, nightfallRelease())
	spec := messyNightfallSpecs()[0]
	spec.Tags = map[string]string{
		"TITLE": "Harbor Lights", "ARTIST": "The Cardinal Waves", "ALBUM": "Nightfall Circuit",
		"ALBUMARTIST": "The Cardinal Waves", "TRACKNUMBER": "1", "DATE": "2014",
	}
	if _, err := fixtures.Generate(h.library, spec); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/matching",
		map[string]any{"mode": "auto", "singlesAutoApply": true}), 200, "auto singles")

	paths, err := fixtures.Generate(t.TempDir(), spec)
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, bob, paths[0], "music", "")
	if up.Duplicate == nil {
		t.Fatalf("the re-upload was not flagged: %+v", up)
	}
	drainMatches(t, h)
	if e := reviewAs(t, h, bob, *up.ReviewEntryId); e.Status != "pending" || e.Best == nil {
		t.Fatalf("flagged single = %s (best %+v), want it pending with its match", e.Status, e.Best)
	}
}

// A part uploaded for a book the library already holds becomes a part of
// that book, and its uploader gains no right over the book.
func TestABookPartJoinsAForeignBookGrantsNothing(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.itemTitled(t, h.token, "The Fixture Book").Pid

	part, err := fixtures.GenerateM4B(t.TempDir(), fixtures.Spec{
		Name: "04 - Part Four", Duration: 3 * time.Second,
		Tags: map[string]string{
			"TITLE": "Part Four", "ALBUM": "The Fixture Book", "ARTIST": "Ada Author",
			"ALBUMARTIST": "Ada Author", "TRACKNUMBER": "4",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, bob, part, "audiobook", "")
	drainMatches(t, h)
	decideAs(t, h, bob, *up.ReviewEntryId, map[string]any{"action": "as-is"})
	if files := h.itemFiles(t, h.token, book); len(files) != 4 {
		t.Fatalf("book files = %+v, want the new part among four", files)
	}
	if mayCurateAs(t, h, bob, book) {
		t.Fatal("the uploader of one part may edit another account's book")
	}
	if joined := reviewAs(t, h, bob, *up.ReviewEntryId).Tracks[0]; joined.Joined == nil || !*joined.Joined {
		t.Fatalf("decided part = %+v, want it marked joined", joined)
	}
}

// What an upload creates is still its uploader's to edit, and so is
// what a half-landed unit landed, after the rest is discarded.
func TestAFirstUploadStillGrantsTheUploader(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	solo, err := fixtures.Generate(t.TempDir(),
		batchTrackSpec("solo", "Only Child", "Single File", "Beacon Row", "1", 3))
	if err != nil {
		t.Fatal(err)
	}
	if pid := importAs(t, h, bob, solo[0], "music"); !mayCurateAs(t, h, bob, pid) {
		t.Fatal("the uploader may not edit the item their upload created")
	}

	// Two files of one unit that take the same place: the first lands,
	// the second is refused, and discarding the rest keeps the first.
	twins, err := fixtures.Generate(t.TempDir(),
		batchTrackSpec("twin-a", "Twin Track", "Twin Peaks Demo", "Beacon Row", "1", 3),
		batchTrackSpec("twin-b", "Twin Track", "Twin Peaks Demo", "Beacon Row", "1", 5))
	if err != nil {
		t.Fatal(err)
	}
	batch := createBatch(t, h, bob, "album", "music")
	for _, p := range twins {
		uploadBatchMember(t, h, bob, p, "music", batch.Id, "")
	}
	entryID := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds[0]
	drainMatches(t, h)
	wantStatus(t, postJSONAs(t, h, bob, "/api/v1/review/queue/"+entryID+"/decide",
		map[string]any{"action": "as-is"}), 409, "a decide whose second file's place the first took")
	landed := h.itemTitled(t, h.token, "Twin Track").Pid
	if !mayCurateAs(t, h, bob, landed) {
		t.Fatal("the landed half is not its uploader's")
	}
	decideAs(t, h, bob, entryID, map[string]any{"action": "discard"})
	if !mayCurateAs(t, h, bob, landed) {
		t.Fatal("discarding the rest took the landed half from its uploader")
	}
}

// An upload of audio the library holds that names a recording of its
// own starts its own item rather than joining, and its uploader may edit
// it: what the import did decides, not what it planned.
func TestAnUploadWithItsOwnRecordingStartsItsOwnItem(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "alpha", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{
			"TITLE": "Alpha Live", "ARTIST": "Bob", "ALBUM": "Own Recording",
			"MUSICBRAINZ_TRACKID": "00000000-0000-4000-8000-0000000000bb",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, bob, paths[0], "music", "")
	drainMatches(t, h)
	decideAs(t, h, bob, *up.ReviewEntryId, map[string]any{"action": "as-is"})
	tracks := reviewAs(t, h, bob, *up.ReviewEntryId).Tracks
	if len(tracks) != 1 || tracks[0].Pid == nil {
		t.Fatalf("decided tracks = %+v, want the imported item", tracks)
	}
	pid := *tracks[0].Pid
	if pid == alpha {
		t.Fatalf("the file joined %s, the item holding its audio, rather than starting its own", alpha)
	}
	if !mayCurateAs(t, h, bob, pid) {
		t.Fatalf("the uploader may not edit %s, the item their upload started", pid)
	}
	if mayCurateAs(t, h, bob, alpha) {
		t.Fatalf("the uploader may edit %s, the item whose audio theirs repeats", alpha)
	}
}

// A file is held only while the library has its audio on disk: once the
// item's own file went missing, the upload that could restore it is not
// thrown away when the import cannot place it, and its bytes wait for
// another try.
func TestAnUploadOfAMissingFilesAudioKeepsItsBytes(t *testing.T) {
	t.Parallel()
	h, _ := joinHarness(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "lost", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Lost Song", "ARTIST": "Lost Band", "ALBUM": "Lost Album"},
	})
	if err != nil {
		t.Fatal(err)
	}
	first := uploadFile(t, h, h.token, paths[0], "music", "")
	decideAs(t, h, h.token, *first.ReviewEntryId, map[string]any{"action": "as-is"})
	files := h.itemFiles(t, h.token, h.itemTitled(t, h.token, "Lost Song").Pid)
	if len(files) != 1 || files[0].Path == nil {
		t.Fatalf("files = %+v, want the one imported", files)
	}
	if err := os.Remove(*files[0].Path); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	again := uploadFile(t, h, h.token, paths[0], "music", "")
	resp := h.postJSON(t, "/api/v1/review/queue/"+*again.ReviewEntryId+"/decide", map[string]any{"action": "as-is"})
	if refusal := decodeStatus[Error](t, resp, 409, "the decide"); refusal.Code != "conflict" || !strings.Contains(refusal.Message, "lost.flac") {
		t.Fatalf("refusal = %+v, want the plan's conflict naming the file", refusal)
	}
	if u := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+again.Id, h.token)); u.State != "staged" {
		t.Fatalf("session = %+v, want it still staged", u)
	}
}

// A sync download whose audio the library already holds where its tags
// would put it adds nothing, and settles its map row with that audio's
// essence, which a later merge of the holding item re-resolves by rather
// than fetching the entry again.
func TestAHeldImportGivesItsSourceRowTheEssence(t *testing.T) {
	t.Parallel()
	h, _ := joinHarness(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "held", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Held Song", "ARTIST": "Held Band", "ALBUM": "Held Album"},
	})
	if err != nil {
		t.Fatal(err)
	}
	first := uploadFile(t, h, h.token, paths[0], "music", "")
	decideAs(t, h, h.token, *first.ReviewEntryId, map[string]any{"action": "as-is"})

	again := uploadFile(t, h, h.token, paths[0], "music", "")
	ctx := context.Background()
	if err := h.store.PutPlaylistSourceMapPending(ctx, "youtube", "held-entry", again.Id, time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	res := decideAs(t, h, h.token, *again.ReviewEntryId, map[string]any{"action": "as-is"})
	if res.Warnings == nil || !slices.ContainsFunc(*res.Warnings, func(w string) bool { return strings.Contains(w, "nothing was added") }) {
		t.Fatalf("decide warnings = %v, want the file held where it already is", res.Warnings)
	}
	rows, err := h.store.PlaylistSourceMapFor(ctx, "youtube", []string{"held-entry"})
	if err != nil {
		t.Fatal(err)
	}
	if row := rows["held-entry"]; row.ItemPID == "" || row.Essence == "" {
		t.Fatalf("map row = %+v, want the holding item and its essence", row)
	}
}

// A book's release id is every part's, so it cannot say a part is held:
// the second part of a book the library has, uploaded on its own, is no
// certain duplicate of the book it would join.
func TestALaterPartOfAHeldBookIsNoCertainDuplicate(t *testing.T) {
	t.Parallel()
	h, _ := joinHarness(t)
	part := func(name, title, track string) string {
		paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{
				"TITLE": title, "ALBUM": "Shared Release Book", "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author",
				"TRACKNUMBER": track, "MUSICBRAINZ_ALBUMID": "00000000-0000-4000-8000-0000000000c1",
			},
		})
		if err != nil {
			t.Fatal(err)
		}
		return paths[0]
	}
	first := uploadFile(t, h, h.token, part("part-one", "Part One", "1"), "audiobook", "")
	decideAs(t, h, h.token, *first.ReviewEntryId, map[string]any{"action": "as-is"})
	second := uploadFile(t, h, h.token, part("part-two", "Part Two", "2"), "audiobook", "")
	if d := second.Duplicate; d != nil && d.Kind == "id" {
		t.Fatalf("the second part's duplicate = %+v, want no certain match on the release id", d)
	}
}
