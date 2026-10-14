package api

import (
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// TestBookSeriesListAndMerge covers the series rung. A series is a name
// a book's tags carry rather than an entity anyone curates, so a split
// spelling has no duplicates finding to arrive through: the listing is
// how a curator finds the two, and the merge is how they fold together.
func TestBookSeriesListAndMerge(t *testing.T) {
	t.Parallel()
	books := t.TempDir()
	for _, b := range []struct{ author, title string }{
		{"Wren Vale", "Harbor Book One"},
		{"Wren Vale", "Harbour Book Two"},
	} {
		if _, err := fixtures.GenerateM4B(filepath.Join(books, b.author, b.title), fixtures.Spec{
			Name: b.title, Duration: 3 * time.Second,
			Tags: map[string]string{
				"TITLE": b.title, "ALBUM": b.title,
				"ARTIST": b.author, "ALBUMARTIST": b.author,
			},
		}); err != nil {
			t.Fatalf("generating %s: %v", b.title, err)
		}
	}
	h := newHarness(t, service.Root{Name: "books", Path: books})

	// Two spellings of one series, set the way a curator would. The
	// series comes off the editor rather than the fixtures' tags: a
	// synthesized MP4 carries no GROUPING atom to read it from.
	for title, series := range map[string]string{
		"Harbor Book One":  "Harbor Chronicles",
		"Harbour Book Two": "Harbour Chronicles",
	} {
		pid := bookInSeries(t, h, title)
		resp := h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
			"fields": map[string]string{"series": series},
		})
		if resp.StatusCode != 200 {
			body, _ := io.ReadAll(resp.Body)
			t.Fatalf("setting the series on %s = %d: %s", title, resp.StatusCode, body)
		}
	}

	resp := get(t, h.ts, "/api/v1/books/series", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("series status = %d", resp.StatusCode)
	}
	page := decode[BookSeriesPage](t, resp)
	byName := map[string]string{}
	for _, sr := range page.Series {
		byName[sr.Name] = sr.Pid
	}
	survivor, loser := byName["Harbor Chronicles"], byName["Harbour Chronicles"]
	if survivor == "" || loser == "" {
		t.Fatalf("series listing = %+v, want both spellings", page.Series)
	}
	if survivor[:3] != "sr-" {
		t.Fatalf("series pid %q carries no sr- prefix", survivor)
	}

	// The book screen names its series, which is what a merge target is
	// picked against.
	bookPid := bookInSeries(t, h, "Harbour Book Two")
	before := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+bookPid, h.token))
	if before.SeriesPid == nil || *before.SeriesPid != loser {
		t.Fatalf("book seriesPid = %v, want %s", before.SeriesPid, loser)
	}

	resp = h.postJSON(t, "/api/v1/library/duplicates/merge", map[string]any{
		"entityType":  "series",
		"survivorPid": survivor,
		"loserPids":   []string{loser},
	})
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("series merge status = %d: %s", resp.StatusCode, body)
	}
	if res := decode[MergeResult](t, resp); res.Merged != 1 {
		t.Fatalf("merged = %d, want 1", res.Merged)
	}

	after := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+bookPid, h.token))
	if after.SeriesPid == nil || *after.SeriesPid != survivor {
		t.Fatalf("after the merge the book's seriesPid = %v, want the survivor %s",
			after.SeriesPid, survivor)
	}

	resp = get(t, h.ts, "/api/v1/books/series", h.token)
	for _, sr := range decode[BookSeriesPage](t, resp).Series {
		if sr.Pid == loser {
			t.Fatalf("the merged-away series is still listed: %+v", sr)
		}
	}

	// A cursor from nowhere is a refusal, not a silent restart.
	wantStatus(t, get(t, h.ts, "/api/v1/books/series?cursor=not-a-cursor", h.token),
		400, "a malformed series cursor")
}

// bookInSeries resolves the book pid behind one title.
func bookInSeries(t *testing.T, h *harness, title string) string {
	t.Helper()
	for _, it := range h.items(t, "?mediaType=audiobook&limit=100").Items {
		if it.Title == title {
			return it.Pid
		}
	}
	t.Fatalf("no book titled %q", title)
	return ""
}

// TestBookSeriesDetail covers the series screen's read: the books in
// sequence order, the counts an account that cannot see everything is
// not told, and the 404 that keeps a series out of a stranger's reach.
func TestBookSeriesDetail(t *testing.T) {
	t.Parallel()
	books := t.TempDir()
	if _, err := fixtures.GenerateSeriesBooks(books, "Tidewater", 3); err != nil {
		t.Fatalf("generating the series: %v", err)
	}
	h := newHarness(t, service.Root{Name: "books", Path: books})

	var series string
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", h.token)).Series {
		if sr.Name == "Tidewater" {
			series = sr.Pid
		}
	}
	if series == "" {
		t.Fatal("the tagged series is not in the listing")
	}

	detail := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, h.token))
	if detail.Pid != series || detail.Name != "Tidewater" {
		t.Fatalf("detail = %+v", detail)
	}
	// In sequence order, which is the catalog's, and each row carries
	// the number its tags spell rather than its position in the list.
	titles := make([]string, 0, len(detail.Books))
	seqs := make([]string, 0, len(detail.Books))
	for _, entry := range detail.Books {
		titles = append(titles, entry.Book.Title)
		seqs = append(seqs, deref(entry.Sequence))
	}
	wantTitles := []string{"Tidewater Book 1", "Tidewater Book 2", "Tidewater Book 3"}
	if !slices.Equal(titles, wantTitles) {
		t.Fatalf("books = %v, want %v", titles, wantTitles)
	}
	if !slices.Equal(seqs, []string{"1", "2", "3"}) {
		t.Fatalf("sequences = %v", seqs)
	}
	// The admin sees every library, so the counts are true and answered.
	if detail.BookCount == nil || *detail.BookCount != 3 {
		t.Fatalf("bookCount = %v, want 3", detail.BookCount)
	}
	if detail.TotalDurationMs == nil || *detail.TotalDurationMs <= 0 {
		t.Fatalf("totalDurationMs = %v", detail.TotalDurationMs)
	}

	// An account granted a library the series is not in gets a 404, not
	// an empty series: an empty answer would tell it one exists.
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token))
	var music string
	for _, lib := range libs.Libraries {
		if lib.Name != "books" {
			music = lib.Pid
		}
	}
	if music == "" {
		t.Fatal("no library beside the books root to grant")
	}
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "seriesless", "password": "seriesless-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{music}},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	stranger := loginAs(t, h.ts, "seriesless", "seriesless-pass").Token
	wantStatus(t, get(t, h.ts, "/api/v1/series/"+series, stranger),
		404, "a series held only in a library this account was not granted")

	// An account granted the books library sees the whole series, so
	// its counts are true for it and answered.
	var booksLib string
	for _, lib := range libs.Libraries {
		if lib.Name == "books" {
			booksLib = lib.Pid
		}
	}
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "seriesreader", "password": "seriesreader-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{booksLib}},
	})
	wantStatus(t, resp, 201, "create the books reader")
	reader := loginAs(t, h.ts, "seriesreader", "seriesreader-pass").Token
	whole := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, reader))
	if whole.BookCount == nil || *whole.BookCount != 3 {
		t.Fatalf("a reader granted the whole series reads bookCount %v, want 3", whole.BookCount)
	}

	// A pid of the wrong kind is a miss rather than a leak.
	wantStatus(t, get(t, h.ts, "/api/v1/series/al-01JZX5N8QW3F4V9T2B7KD3M9R6", h.token),
		404, "an album pid presented as a series")

	// Content rules bite here too. BooksInSeries takes no query node,
	// so nothing upstream has applied them: an allow-list naming a tag
	// no fixture carries hides every book, and the advisory check alone
	// would have listed all three by title, author and pid.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "serieskid", "password": "serieskid-pass",
		"libraryAccess": map[string]any{"mode": "all"},
		"permissions": map[string]any{
			"tagAllow": []map[string]any{{"key": "nosuchtag"}},
		},
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create restricted user status = %d: %s", resp.StatusCode, body)
	}
	resp.Body.Close()
	kid := loginAs(t, h.ts, "serieskid", "serieskid-pass").Token
	// Every book hidden is the series hidden: the 404 an ungranted
	// library gets, and no row in the listing.
	wantStatus(t, get(t, h.ts, "/api/v1/series/"+series, kid),
		404, "a series whose every book a tag rule hides")
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", kid)).Series {
		if sr.Pid == series {
			t.Errorf("the hidden series is listed for the restricted account: %+v", sr)
		}
	}

	// One book carrying the allowed tag opens the series onto that book,
	// and the counts stay withheld: this account sees every library, so
	// the grant alone would advertise three books over one row.
	first := detail.Books[0].Book.Pid
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+first+"/tags/nosuchtag", map[string]any{
		"values": []string{"yes"},
	}), 200, "tagging the first book")
	partial := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, kid))
	if len(partial.Books) != 1 || partial.Books[0].Book.Pid != first {
		t.Fatalf("the restricted account sees %+v, want the tagged book alone", partial.Books)
	}
	if partial.BookCount != nil || partial.TotalDurationMs != nil {
		t.Fatalf("counts answered over a filtered series: %+v", partial)
	}
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", kid)).Series {
		if sr.Pid == series && (sr.BookCount != nil || sr.TotalDurationMs != nil) {
			t.Errorf("the listing answers counts over a filtered series: %+v", sr)
		}
	}
}

// A book a content rule hides is hidden on the book routes as it is on
// the item routes: its detail, its resume point and its bookmarks all
// answer not-found, as if it did not exist.
func TestBookRoutesHonourContentRules(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture's one", len(books.Items))
	}
	book := books.Items[0].Pid
	kid := kidAccount(t, h, "reader")
	for _, path := range []string{"/api/v1/books/" + book, "/api/v1/books/" + book + "/bookmarks"} {
		wantStatus(t, get(t, h.ts, path, kid), 200, "before the flag: "+path)
	}
	flagExplicit(t, h, book)
	for _, path := range []string{
		"/api/v1/items/" + book,
		"/api/v1/books/" + book,
		"/api/v1/books/" + book + "/resume",
		"/api/v1/books/" + book + "/bookmarks",
	} {
		wantStatus(t, get(t, h.ts, path, kid), 404, "after the flag: "+path)
	}
}

// The series listing and its detail agree on what a reader is offered:
// a trashed book is in neither, so a series whose only book a
// tag-restricted reader may see is in the trash is absent from both.
func TestSeriesListingAndDetailAgreeOnTrashedBooks(t *testing.T) {
	t.Parallel()
	books := t.TempDir()
	if _, err := fixtures.GenerateSeriesBooks(books, "Ebbtide", 2); err != nil {
		t.Fatalf("generating the series: %v", err)
	}
	h := newHarness(t, service.Root{Name: "books", Path: books})
	var series string
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", h.token)).Series {
		if sr.Name == "Ebbtide" {
			series = sr.Pid
		}
	}
	detail := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, h.token))
	if len(detail.Books) != 2 {
		t.Fatalf("series books = %d, want 2", len(detail.Books))
	}
	flagExplicit(t, h, detail.Books[0].Book.Pid)
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{detail.Books[1].Book.Pid}, "mode": "trash",
	}), 200, "trash the permitted book")

	kid := kidAccount(t, h, "tidekid")
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", kid)).Series {
		if sr.Pid == series {
			t.Error("the series is listed with its only permitted book in the trash")
		}
	}
	wantStatus(t, get(t, h.ts, "/api/v1/series/"+series, kid), 404, "the detail of that series")
	got := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, h.token))
	if len(got.Books) != 1 {
		t.Fatalf("the administrator's detail lists %d books, want the one not trashed", len(got.Books))
	}
	count, total := 0, int64(0)
	if got.BookCount != nil && got.TotalDurationMs != nil {
		count, total = *got.BookCount, *got.TotalDurationMs
	}
	if count != 1 || total != got.Books[0].Book.DurationMs {
		t.Errorf("the administrator's detail counts %d books, %d ms; want the one it lists, %d ms",
			count, total, got.Books[0].Book.DurationMs)
	}
}

// A reader whose libraries hold a series only through an alternate
// copy of a book they cannot open is offered neither its listing row
// nor its detail: the two agree for a library grant as they do for a
// tag rule.
func TestSeriesListingAndDetailAgreeForALibraryGrant(t *testing.T) {
	t.Parallel()
	shelf, annex := t.TempDir(), t.TempDir()
	paths, err := fixtures.GenerateSeriesBooks(annex, "Ebbtide", 1)
	if err != nil {
		t.Fatalf("generating the series: %v", err)
	}
	copied := filepath.Join(shelf, strings.TrimPrefix(paths[0], annex))
	if err := os.MkdirAll(filepath.Dir(copied), 0o755); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(copied, body, 0o644); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, service.Root{Name: "annex", Path: annex}, service.Root{Name: "shelf", Path: shelf})
	var series, shelfLib string
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", h.token)).Series {
		if sr.Name == "Ebbtide" {
			series = sr.Pid
		}
	}
	detail := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, h.token))
	if len(detail.Books) != 1 {
		t.Fatalf("series books = %d, want the one book", len(detail.Books))
	}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "shelf" {
			shelfLib = lib.Pid
		}
	}
	id, reader, _ := mediaListener(t, h, "shelfreader", nil)
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{shelfLib}},
	}), 200, "grant the shelf alone")
	wantStatus(t, get(t, h.ts, "/api/v1/books/"+detail.Books[0].Book.Pid, reader), 404, "the book its copy belongs to")
	for _, sr := range decode[BookSeriesPage](t, get(t, h.ts, "/api/v1/books/series", reader)).Series {
		if sr.Pid == series {
			t.Error("the series is listed through a copy of a book the reader cannot open")
		}
	}
	wantStatus(t, get(t, h.ts, "/api/v1/series/"+series, reader), 404, "the detail of that series")
}
