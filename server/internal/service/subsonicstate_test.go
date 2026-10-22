package service

import (
	"context"
	"fmt"
	"maps"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Folders are the caller's music libraries, each under the id it was
// first listed with.
func TestMusicFoldersAreTheCallersMusicLibraries(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	music, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "vinyl", Path: t.TempDir(), Media: "music"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "books", Path: t.TempDir(), Media: "audiobook"}); err != nil {
		t.Fatal(err)
	}

	folders, err := svc.MusicFolders(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	names := map[string]MusicFolder{}
	for _, f := range folders {
		names[f.Name] = f
	}
	if len(folders) != 2 || names["lib"].ID == 0 || names["vinyl"].ID == 0 {
		t.Fatalf("folders = %+v, want lib and vinyl, never the audiobook library", folders)
	}
	again, _ := svc.MusicFolders(ctx, admin)
	for _, f := range again {
		if names[f.Name].ID != f.ID {
			t.Fatalf("%s moved from %d to %d", f.Name, names[f.Name].ID, f.ID)
		}
	}
	lib, err := svc.MusicFolderLibrary(ctx, admin, names["vinyl"].ID)
	if err != nil || lib != music.PID {
		t.Fatalf("vinyl's folder = %q (%v), want %s", lib, err, music.PID)
	}

	granted := &UserCtx{ID: "us-restricted", CatalogPID: admin.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(music.PID, PrefixLibrary+"-"): true}}
	theirs, err := svc.MusicFolders(ctx, granted)
	if err != nil || len(theirs) != 1 || theirs[0].ID != names["vinyl"].ID {
		t.Fatalf("restricted folders = %+v (%v), want vinyl alone under its id", theirs, err)
	}
	if _, err := svc.MusicFolderLibrary(ctx, granted, names["lib"].ID); KindOf(err) != KindNotFound {
		t.Errorf("an ungranted folder = %v, want not-found", err)
	}
	if _, err := svc.MusicFolderLibrary(ctx, admin, 99999); KindOf(err) != KindNotFound {
		t.Errorf("an unknown folder = %v, want not-found", err)
	}
	// An id whose library has since gone names nothing.
	gone, err := svc.db.MusicFolderIDs(ctx, []string{PrefixLibrary + "-" + ulid.Make().String()})
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range gone {
		if _, err := svc.MusicFolderLibrary(ctx, admin, id); KindOf(err) != KindNotFound {
			t.Errorf("a removed library's folder = %v, want not-found", err)
		}
	}
}

// Bookmarks hold for every kind: a track's is its own row and never
// touches the track's resume position, while a book's or an episode's is
// its resume position, the comment riding beside it.
func TestSubsonicBookmarksForEveryKind(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateBook(dir); err != nil {
			t.Fatal(err)
		}
	}})
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	books, err := svc.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v), want the fixture book", books.Items, err)
	}
	book := books.Items[0].PID

	if _, err := svc.Checkpoint(ctx, uc, track, 1500, nil); err != nil {
		t.Fatal(err)
	}
	if err := svc.SaveSubsonicBookmark(ctx, uc, track, 5000, "chorus"); err != nil {
		t.Fatal(err)
	}
	if st, _ := svc.PlayState(ctx, uc, track); st.PositionMS != 1500 {
		t.Fatalf("a track's bookmark moved its resume position to %d", st.PositionMS)
	}
	if err := svc.SaveSubsonicBookmark(ctx, uc, book, 6500, "the duel"); err != nil {
		t.Fatal(err)
	}
	if st, _ := svc.PlayState(ctx, uc, book); st.PositionMS != 6500 {
		t.Fatalf("a book's bookmark left its resume position at %d, want 6500", st.PositionMS)
	}
	// The first-party apps move the book on; the bookmark is where it is.
	if _, err := svc.Checkpoint(ctx, uc, book, 9000, nil); err != nil {
		t.Fatal(err)
	}

	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]SubsonicBookmark{}
	for _, b := range marks {
		got[b.Item.PID] = b
	}
	if b := got[track]; len(marks) != 2 || b.PositionMS != 5000 || b.Comment != "chorus" || b.CreatedAt.IsZero() {
		t.Fatalf("bookmarks = %+v, want the track at 5000 with its comment", marks)
	}
	if b := got[book]; b.PositionMS != 9000 || b.Comment != "the duel" {
		t.Fatalf("book bookmark = %+v, want its resume position 9000 and the comment", b)
	}

	// A book's bookmark without a comment is its resume position alone.
	if err := svc.SaveSubsonicBookmark(ctx, uc, book, 7000, ""); err != nil {
		t.Fatal(err)
	}
	marks, _ = svc.SubsonicBookmarks(ctx, uc)
	for _, b := range marks {
		if b.Item.PID == book && (b.PositionMS != 7000 || b.Comment != "") {
			t.Fatalf("book bookmark = %+v, want 7000 with no comment", b)
		}
	}

	if err := svc.DeleteSubsonicBookmark(ctx, uc, track); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteSubsonicBookmark(ctx, uc, book); err != nil {
		t.Fatal(err)
	}
	if marks, _ := svc.SubsonicBookmarks(ctx, uc); len(marks) != 0 {
		t.Fatalf("bookmarks after deleting both = %+v", marks)
	}
	if st, _ := svc.PlayState(ctx, uc, book); st.PositionMS != 0 {
		t.Errorf("deleting a book's bookmark left its resume position at %d", st.PositionMS)
	}
	if st, _ := svc.PlayState(ctx, uc, track); st.PositionMS != 1500 {
		t.Errorf("deleting a track's bookmark moved its resume position to %d", st.PositionMS)
	}
}

func TestSubsonicBookmarksAreTheCallersAndVisible(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, other := marksFixture(t)
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	if err := svc.SaveSubsonicBookmark(ctx, uc, track, 5000, ""); err != nil {
		t.Fatal(err)
	}
	if marks, err := svc.SubsonicBookmarks(ctx, other); err != nil || len(marks) != 0 {
		t.Fatalf("another account's bookmarks = %+v (%v), want none", marks, err)
	}
	nobody := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	if err := svc.SaveSubsonicBookmark(ctx, nobody, track, 1, ""); KindOf(err) != KindNotFound {
		t.Errorf("bookmarking a hidden item = %v, want not-found", err)
	}
	if marks, _ := svc.SubsonicBookmarks(ctx, nobody); len(marks) != 0 {
		t.Errorf("a caller who cannot see the item lists %+v", marks)
	}
	if err := svc.SaveSubsonicBookmark(ctx, uc, track, 1, strings.Repeat("x", subsonicCommentMax+1)); KindOf(err) != KindInvalid {
		t.Errorf("an oversized comment = %v, want invalid", err)
	}

	// A row for an item the catalog no longer holds is dropped on read.
	gone := PrefixTrack + "-" + ulid.Make().String()
	if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
		UserID: uc.ID, ItemPID: gone, PositionMS: 1, CreatedAtNS: 1, UpdatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil || len(marks) != 1 || marks[0].Item.PID != track {
		t.Fatalf("bookmarks = %+v (%v), want the live track alone", marks, err)
	}
	rows, _ := svc.db.SubsonicBookmarks(ctx, uc.ID)
	for _, r := range rows {
		if r.ItemPID == gone {
			t.Error("the row for a deleted item survived the read")
		}
	}
}

// A tag-restricted account's bookmarks are filtered by its rules, read in
// one batch for the whole listing.
func TestSubsonicBookmarksFollowContentRules(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	restricted := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	for _, title := range []string{"Flagged", "Unsaid"} {
		pid, _ := fixtureTrackPID(t, ctx, svc, uc, title)
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: 1000, CreatedAtNS: 1, UpdatedAtNS: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
	titles := func(who *UserCtx) []string {
		t.Helper()
		marks, err := svc.SubsonicBookmarks(ctx, who)
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, b := range marks {
			out = append(out, b.Item.Title)
		}
		return out
	}
	if got := titles(uc); len(got) != 2 {
		t.Fatalf("unrestricted bookmarks = %v, want both", got)
	}
	if got := titles(restricted); len(got) != 1 || got[0] != "Unsaid" {
		t.Fatalf("restricted bookmarks = %v, want the unflagged track alone", got)
	}
}

// At the cap a new bookmark is refused and changes nothing, a book's
// resume position included; a book's bookmark with no comment keeps no
// row, so it is never refused; and the listing shows the newest up to
// the cap.
func TestSubsonicBookmarkCapRefusesWholly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateBook(dir); err != nil {
			t.Fatal(err)
		}
		if _, err := fixtures.Generate(dir, bulkTracks("Capped", 0, wdb.SubsonicBookmarkCap)...); err != nil {
			t.Fatal(err)
		}
	}})
	books, err := svc.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v)", books.Items, err)
	}
	book := books.Items[0].PID
	var capped []string
	for cursor := ""; ; {
		page, err := svc.Items(ctx, uc, ItemFilter{MediaType: "music"}, cursor, 500)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			if strings.HasPrefix(it.Title, "Capped") {
				capped = append(capped, it.PID)
			}
		}
		if cursor = page.Next; cursor == "" {
			break
		}
	}
	if len(capped) != wdb.SubsonicBookmarkCap {
		t.Fatalf("found %d bulk tracks, want %d", len(capped), wdb.SubsonicBookmarkCap)
	}
	for i, pid := range capped {
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: int64(i), CreatedAtNS: int64(i + 1), UpdatedAtNS: int64(i + 1),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.Checkpoint(ctx, uc, book, 2000, nil); err != nil {
		t.Fatal(err)
	}
	if err := svc.SaveSubsonicBookmark(ctx, uc, book, 5000, "a note"); KindOf(err) != KindConflict {
		t.Fatalf("a bookmark past the cap = %v, want a conflict", err)
	}
	if st, _ := svc.PlayState(ctx, uc, book); st.PositionMS != 2000 {
		t.Fatalf("a refused bookmark moved the book to %d, want it left at 2000", st.PositionMS)
	}
	if err := svc.SaveSubsonicBookmark(ctx, uc, book, 5000, ""); err != nil {
		t.Fatalf("a book bookmark with no comment at the cap = %v, want it saved", err)
	}
	if st, _ := svc.PlayState(ctx, uc, book); st.PositionMS != 5000 {
		t.Fatalf("the book is at %d, want 5000", st.PositionMS)
	}
	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if len(marks) != wdb.SubsonicBookmarkCap || marks[0].Item.PID != book {
		t.Fatalf("the listing = %d entries led by %+v, want %d led by the book", len(marks), marks[0], wdb.SubsonicBookmarkCap)
	}
	for _, b := range marks {
		if b.Item.PID == capped[0] {
			t.Fatal("the oldest bookmark was listed past the cap")
		}
	}
}

// A music folder's lists are its own library's tracks, in the list's
// order, so a folder holds its own newest list however far behind the
// rest of the catalog its additions sit.
func TestRecentlyAddedInAFolder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	dir := t.TempDir()
	vinyl, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "vinyl", Path: dir, Media: "music"})
	if err != nil {
		t.Fatal(err)
	}
	for _, title := range []string{"First Press", "Second Press"} {
		if _, err := fixtures.Generate(dir, fixtures.Spec{Name: title, Codec: fixtures.CodecFLAC, Duration: time.Second,
			Tags: map[string]string{"TITLE": title, "ARTIST": "Groove Band", "ALBUM": "Vinyl Days"}}); err != nil {
			t.Fatal(err)
		}
		// AddLibrary started a scan of its own; wait out whatever holds
		// the catalog.
		for deadline := time.Now().Add(30 * time.Second); ; {
			_, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
			if err == nil {
				break
			}
			if KindOf(classify(err)) != KindConflict || time.Now().After(deadline) {
				t.Fatal(err)
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
	inVinyl := ItemFilter{MediaType: "music", Library: vinyl.PID}
	var titles []string
	cursor := ""
	for {
		page, err := svc.Browse(ctx, uc, "recently-added", inVinyl, 0, cursor, 1)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			titles = append(titles, it.Title)
		}
		if page.Next == "" {
			break
		}
		cursor = page.Next
	}
	if got := strings.Join(titles, ", "); got != "Second Press, First Press" {
		t.Fatalf("vinyl's recently added = [%s], want its own two tracks, newest first", got)
	}
	none := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	if page, err := svc.Browse(ctx, none, "recently-added", inVinyl, 0, "", 10); err != nil || len(page.Items) != 0 {
		t.Fatalf("a caller without the library = %v (%v), want nothing", page.Items, err)
	}
	if _, err := svc.Browse(ctx, uc, "recently-added", ItemFilter{Library: "nonsense"}, 0, "", 10); KindOf(err) != KindInvalid {
		t.Fatalf("a library filter naming no library = %v, want invalid", err)
	}
}

// Every book and episode in progress is a bookmark, however many newer
// checkpoints, of any kind, came after it.
func TestSubsonicBookmarksListEveryResumePosition(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateBook(dir); err != nil {
			t.Fatal(err)
		}
	}})
	books, err := svc.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v)", books.Items, err)
	}
	book := books.Items[0].PID
	if err := svc.SaveSubsonicBookmark(ctx, uc, book, 6500, "the duel"); err != nil {
		t.Fatal(err)
	}
	later := time.Now().Add(time.Minute).UnixNano()
	for i := range 2100 {
		if err := svc.db.StampPlayState(ctx, uc.ID, PrefixTrack+"-"+ulid.Make().String(), later+int64(i), 0); err != nil {
			t.Fatal(err)
		}
	}
	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range marks {
		if b.Item.PID == book && b.PositionMS == 6500 && b.Comment == "the duel" {
			return
		}
	}
	t.Fatalf("bookmarks = %+v, want the book at 6500 with its comment", marks)
}

// A track's bookmark outlives the track becoming a book: it lists under
// the item's current kind, at the position it was saved at.
func TestASubsonicBookmarkSurvivesAChangeOfKind(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, bare := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")
	if err := svc.SaveSubsonicBookmark(ctx, uc, track, 5000, "chorus"); err != nil {
		t.Fatal(err)
	}
	job, err := svc.SetItemsKind(ctx, uc, []string{track}, "audiobook", false)
	if err != nil {
		t.Fatal(err)
	}
	_, jobPID, _ := parseAPIPID(job.PID)
	waitForJob(t, ctx, svc, jobPID)
	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	book := apiPID(PrefixBook, bare)
	if len(marks) != 1 || marks[0].Item.PID != book || marks[0].PositionMS != 5000 || marks[0].Comment != "chorus" {
		t.Fatalf("bookmarks = %+v, want %s at 5000 with its comment", marks, book)
	}
}

// Rows the listing cannot show never count toward the cap: a row whose
// item is gone, or whose pid names nothing, is let go, and a row the
// caller's own rules hide is kept for the day they do not.
func TestUnlistedBookmarkRowsDoNotCountTowardTheCap(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	flagged, _ := fixtureTrackPID(t, ctx, svc, uc, "Flagged")
	unsaid, _ := fixtureTrackPID(t, ctx, svc, uc, "Unsaid")
	put := func(pid string) {
		t.Helper()
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: 1000, CreatedAtNS: 1, UpdatedAtNS: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
	put(flagged)
	put("garbage")
	for range 998 {
		put(PrefixTrack + "-" + ulid.Make().String())
	}
	if err := svc.SaveSubsonicBookmark(ctx, kid, unsaid, 2000, ""); err != nil {
		t.Fatalf("a bookmark beside rows nobody can list = %v, want it saved", err)
	}
	rows, err := svc.db.SubsonicBookmarks(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	held := map[string]bool{}
	for _, r := range rows {
		held[r.ItemPID] = true
	}
	if len(rows) != 2 || !held[flagged] || !held[unsaid] {
		t.Fatalf("rows held = %v, want the hidden track's and the new one alone", held)
	}
	if marks, _ := svc.SubsonicBookmarks(ctx, uc); len(marks) != 2 {
		t.Errorf("the account that sees both lists %+v, want both", marks)
	}
}

// A song's bookmark stands where the listing places it: a track's at its
// own row, never at its resume position; a book's at its resume position
// while it has one, else at its row.
func TestSubsonicBookmarkPositionsFollowTheListing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateBook(dir); err != nil {
			t.Fatal(err)
		}
	}})
	marked, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	resumed, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")
	books, err := svc.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v)", books.Items, err)
	}
	book := books.Items[0].PID
	if err := svc.SaveSubsonicBookmark(ctx, uc, marked, 5000, ""); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
		UserID: uc.ID, ItemPID: book, PositionMS: 3000, CreatedAtNS: 1, UpdatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	pids := []string{marked, resumed, book}
	at := func(resume map[string]int64) map[string]int64 {
		t.Helper()
		got, err := svc.SubsonicBookmarkPositions(ctx, uc, pids, resume)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	if got := at(map[string]int64{resumed: 1500}); len(got) != 2 || got[marked] != 5000 || got[book] != 3000 {
		t.Fatalf("positions = %v, want the track's row and the book's row alone", got)
	}
	if got := at(map[string]int64{book: 7000}); got[book] != 7000 {
		t.Fatalf("positions = %v, want the book at its resume position", got)
	}
}

// SubsonicItems answers only what the caller may be offered: a content
// rule, a missing library grant and the trash each keep an item out, and
// an id naming no item is skipped.
func TestSubsonicItemsOfferOnlyWhatTheCallerMay(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	flagged, _ := fixtureTrackPID(t, ctx, svc, uc, "Flagged")
	unsaid, _ := fixtureTrackPID(t, ctx, svc, uc, "Unsaid")
	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	none := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	ask := []string{flagged, unsaid, PrefixTrack + "-NOTAPID", "garbage", PrefixAlbum + "-" + ulid.Make().String()}
	offered := func(who *UserCtx) []string {
		t.Helper()
		got, err := svc.SubsonicItems(ctx, who, ask)
		if err != nil {
			t.Fatal(err)
		}
		return slices.Sorted(maps.Keys(got))
	}
	if got, want := offered(uc), slices.Sorted(slices.Values([]string{flagged, unsaid})); !slices.Equal(got, want) {
		t.Errorf("the admin is offered %v, want %v", got, want)
	}
	if got := offered(kid); !slices.Equal(got, []string{unsaid}) {
		t.Errorf("a caller whose rule hides the flagged track is offered %v, want the other alone", got)
	}
	if got := offered(none); len(got) != 0 {
		t.Errorf("a caller with no libraries is offered %v, want nothing", got)
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{unsaid}, "trash", false); err != nil {
		t.Fatal(err)
	}
	if got := offered(uc); !slices.Equal(got, []string{flagged}) {
		t.Errorf("after the trash the admin is offered %v, want the flagged track alone", got)
	}
}

// Two rows naming one item list once, at the newer row, and the older
// row is let go.
func TestTheOlderOfTwoBookmarkRowsForOneItemIsLetGo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, bare := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")
	asBook := apiPID(PrefixBook, bare)
	for i, pid := range []string{track, asBook} {
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: int64(1000 * (i + 1)), Comment: pid,
			CreatedAtNS: int64(i + 1), UpdatedAtNS: int64(i + 1),
		}); err != nil {
			t.Fatal(err)
		}
	}
	marks, err := svc.SubsonicBookmarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if len(marks) != 1 || marks[0].Item.PID != track || marks[0].PositionMS != 2000 || marks[0].Comment != asBook {
		t.Fatalf("bookmarks = %+v, want %s once, at the newer row's 2000", marks, track)
	}
	rows, err := svc.db.SubsonicBookmarks(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].ItemPID != asBook {
		t.Fatalf("rows held = %+v, want the newer one alone", rows)
	}
}

// The in-progress read pages through the catalog's list, newest first,
// and stops at its limit.
func TestPositionedSpokenPagesToItsLimit(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	_, eps := followedFeed(t, ctx, svc, uc, "Paged", 5)
	var played []string
	for _, ep := range eps {
		if _, err := svc.Checkpoint(ctx, uc, ep, 30_000, nil); err != nil {
			t.Fatal(err)
		}
		played = append([]string{ep}, played...)
	}
	got, err := svc.positionedSpoken(ctx, uc, 3, 2)
	if err != nil {
		t.Fatal(err)
	}
	var pids []string
	for _, it := range got {
		pids = append(pids, it.PID)
	}
	if want := played[:3]; !slices.Equal(pids, want) {
		t.Fatalf("in progress, three at most, two a page = %v, want the newest three %v", pids, want)
	}
}

// The rows kept for items hidden from the caller for now have a ceiling
// of their own, as many as the account can list: past it the oldest go.
func TestHiddenBookmarkRowsHaveACeiling(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	_, oldestFirst := followedFeed(t, ctx, svc, uc, "Long", wdb.SubsonicBookmarkCap+50)
	for i, pid := range oldestFirst {
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: 1000, CreatedAtNS: int64(i + 1), UpdatedAtNS: int64(i + 1),
		}, oldestFirst...); err != nil {
			t.Fatal(err)
		}
	}
	// The same account with no library: every row is hidden from it.
	none := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	if marks, err := svc.SubsonicBookmarks(ctx, none); err != nil || len(marks) != 0 {
		t.Fatalf("the listing without libraries = %d (%v), want none", len(marks), err)
	}
	rows, err := svc.db.SubsonicBookmarks(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	held := map[string]bool{}
	for _, r := range rows {
		held[r.ItemPID] = true
	}
	if len(rows) != wdb.SubsonicBookmarkCap || held[oldestFirst[49]] || !held[oldestFirst[50]] {
		t.Fatalf("rows held = %d (oldest gone: %v, the 51st kept: %v), want the newest %d",
			len(rows), !held[oldestFirst[49]], held[oldestFirst[50]], wdb.SubsonicBookmarkCap)
	}
}

// A star moves a book's play state but not its last progress write, so a
// bookmark keeps its changed time and its place in the listing.
func TestAStarDoesNotMoveABookmark(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	older := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")
	newer := f.itemPID(t, ctx, model.KindBook, "The Chaptered Fixture")
	for _, book := range []string{older, newer} {
		if _, err := f.svc.Checkpoint(ctx, f.uc, book, 5000, nil); err != nil {
			t.Fatal(err)
		}
	}
	listing := func() ([]string, []time.Time) {
		t.Helper()
		marks, err := f.svc.SubsonicBookmarks(ctx, f.uc)
		if err != nil {
			t.Fatal(err)
		}
		var pids []string
		var changed []time.Time
		for _, b := range marks {
			pids, changed = append(pids, b.Item.PID), append(changed, b.ChangedAt)
		}
		return pids, changed
	}
	pids, changed := listing()
	if !slices.Equal(pids, []string{newer, older}) {
		t.Fatalf("bookmarks = %v, want the newer book first", pids)
	}
	if _, err := f.svc.SetStar(ctx, f.uc, older, true, nil); err != nil {
		t.Fatal(err)
	}
	if after, afterChanged := listing(); !slices.Equal(after, pids) || !slices.Equal(afterChanged, changed) {
		t.Fatalf("after starring the older book: %v changed %v, want %v changed %v", after, afterChanged, pids, changed)
	}
}

// followedFeed follows a feed of n episodes, none fetched, answering the
// show's pid and its episodes'.
func followedFeed(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, title string, n int) (string, []string) {
	t.Helper()
	feed := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var items strings.Builder
		for i := range n {
			fmt.Fprintf(&items, `<item><title>%s %d</title><guid>%s-%d</guid>`+
				`<enclosure url="http://%s/%s-%d.mp3" type="audio/mpeg" length="1"/></item>`, title, i, title, i, r.Host, title, i)
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>%s</title>%s</channel></rss>`, title, items.String())
	}))
	t.Cleanup(feed.Close)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	var pids []string
	for cursor := ""; ; {
		eps, next, err := svc.Episodes(ctx, uc, sub.Show.PID, cursor, 500)
		if err != nil {
			t.Fatal(err)
		}
		for _, ep := range eps {
			pids = append(pids, ep.PID)
		}
		if cursor = next; cursor == "" {
			break
		}
	}
	if len(pids) != n {
		t.Fatalf("the %s feed made %d episodes, want %d", title, len(pids), n)
	}
	return sub.Show.PID, pids
}

// A listing whose follow-set read fails hides every episode, as it must,
// and lets no row go on that say-so: the next listing finds them all.
func TestAFailedReadLetsNoBookmarkRowGo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	_, alpha := followedFeed(t, ctx, svc, uc, "Alpha", 1000)
	bravoShow, bravo := followedFeed(t, ctx, svc, uc, "Bravo", 400)
	at := int64(0)
	put := func(pids []string, uncounted ...string) {
		t.Helper()
		for _, pid := range pids {
			at++
			if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
				UserID: uc.ID, ItemPID: pid, PositionMS: 1000, CreatedAtNS: at, UpdatedAtNS: at,
			}, uncounted...); err != nil {
				t.Fatal(err)
			}
		}
	}
	rows := func() int {
		t.Helper()
		held, err := svc.db.SubsonicBookmarks(ctx, uc.ID)
		if err != nil {
			t.Fatal(err)
		}
		return len(held)
	}
	listed := func() int {
		t.Helper()
		marks, err := svc.SubsonicBookmarks(ctx, uc)
		if err != nil {
			t.Fatal(err)
		}
		return len(marks)
	}
	// What the API reaches: the cap filled, Bravo unfollowed, and the
	// retry at the cap taking 400 more on Alpha beside Bravo's hidden rows.
	put(alpha[:600])
	put(bravo)
	if err := svc.Unsubscribe(ctx, uc, bravoShow, false); err != nil {
		t.Fatal(err)
	}
	put(alpha[600:], bravo...)
	if n, held := listed(), rows(); n != 1000 || held != 1400 {
		t.Fatalf("a healthy listing = %d bookmarks over %d rows, want 1000 over 1400", n, held)
	}
	restore := failFollowSets(t, ctx, svc)
	n := listed()
	restore()
	if held := rows(); n != 0 || held != 1400 {
		t.Errorf("a listing under a failed follow-set read = %d bookmarks, leaving %d rows, want none and all 1400", n, held)
	}
	if n := listed(); n != 1000 {
		t.Errorf("the next healthy listing = %d bookmarks, want 1000", n)
	}
}

// failFollowSets makes every follow-set read fail, for real, until the
// returned func puts the table back.
func failFollowSets(t *testing.T, ctx context.Context, svc *Library) func() {
	t.Helper()
	rename := func(from, to string) {
		t.Helper()
		if _, err := svc.db.Writer().ExecContext(ctx, `ALTER TABLE `+from+` RENAME TO `+to); err != nil {
			t.Fatal(err)
		}
	}
	rename("podcast_subscriptions", "podcast_subscriptions_away")
	return func() { rename("podcast_subscriptions_away", "podcast_subscriptions") }
}

// failLibraryList makes a reload of the catalog's library list fail, for
// real, and holds what the failure leaves - no reload for a while, the
// podcast library's answer no judgment - until the returned func lets the
// next look reload.
func failLibraryList(t *testing.T, ctx context.Context, svc *Library) func() {
	t.Helper()
	due := func(at time.Time) {
		svc.libDirs.mu.Lock()
		svc.libDirs.missed = at
		svc.libDirs.mu.Unlock()
	}
	if _, read := svc.podcastLibrary(ctx); !read {
		t.Fatal("the library list could not be read to start with")
	}
	due(time.Time{})
	failing, cancel := context.WithCancel(ctx)
	cancel()
	if _, read := svc.podcastLibrary(failing); read {
		t.Fatal("a library list reload under a cancelled context was read")
	}
	due(time.Now().Add(time.Hour))
	return func() { due(time.Time{}) }
}

// A listing that cannot read the library list hides every episode from a
// reader with library grants, and lets no row go on that say-so; once the
// list reads again, the ceiling applies.
func TestAFailedLibraryListReadLetsNoBookmarkRowGo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	_, eps := followedFeed(t, ctx, svc, uc, "Granted", wdb.SubsonicBookmarkCap+50)
	for i, pid := range eps {
		if err := svc.db.PutSubsonicBookmark(ctx, wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: 1000, CreatedAtNS: int64(i + 1), UpdatedAtNS: int64(i + 1),
		}, eps...); err != nil {
			t.Fatal(err)
		}
	}
	rows := func() int {
		t.Helper()
		held, err := svc.db.SubsonicBookmarks(ctx, uc.ID)
		if err != nil {
			t.Fatal(err)
		}
		return len(held)
	}
	granted := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	restore := failLibraryList(t, ctx, svc)
	marks, err := svc.SubsonicBookmarks(ctx, granted)
	restore()
	if err != nil || len(marks) != 0 {
		t.Fatalf("a listing without the library list = %d bookmarks (%v), want none", len(marks), err)
	}
	if n := rows(); n != len(eps) {
		t.Errorf("a listing without the library list left %d rows, want all %d", n, len(eps))
	}
	if _, err := svc.SubsonicBookmarks(ctx, granted); err != nil {
		t.Fatal(err)
	}
	if n := rows(); n != wdb.SubsonicBookmarkCap {
		t.Errorf("a listing with the library list read left %d rows, want the ceiling's %d", n, wdb.SubsonicBookmarkCap)
	}
}

// A playlist's members read while the library list cannot be read hides
// the episodes from a reader with library grants and says it fell back,
// so totals counted over it are not kept; read again, the same answer is
// a judgment.
func TestAFailedLibraryListReadIsAFallbackForPlaylistMembers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	_, eps := followedFeed(t, ctx, svc, uc, "Listed", 1)
	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "With an episode", Kind: "static", ItemPIDs: eps})
	if err != nil {
		t.Fatal(err)
	}
	granted := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	members := func() (int, bool) {
		t.Helper()
		counted, fell := WatchDegraded(ctx)
		page, err := svc.PlaylistItems(counted, granted, pl.PID, "", 500)
		if err != nil {
			t.Fatal(err)
		}
		return len(page.Entries), fell()
	}
	restore := failLibraryList(t, ctx, svc)
	n, fell := members()
	restore()
	if n != 0 || !fell {
		t.Errorf("members read without the library list = %d, fell back %v; want none, and the fallback told", n, fell)
	}
	if n, fell := members(); n != 0 || fell {
		t.Errorf("members read with the library list = %d, fell back %v; want none, and no fallback", n, fell)
	}
}
