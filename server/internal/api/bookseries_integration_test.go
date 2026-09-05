package api

import (
	"io"
	"path/filepath"
	"slices"
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
	hidden := decode[BookSeriesDetail](t, get(t, h.ts, "/api/v1/series/"+series, kid))
	if len(hidden.Books) != 0 {
		t.Fatalf("a tag rule did not hide the series' books: %+v", hidden.Books)
	}
	// And the counts go with them: this account sees every library, so
	// the grant alone would have advertised three books over no rows.
	if hidden.BookCount != nil || hidden.TotalDurationMs != nil {
		t.Fatalf("counts answered over a filtered series: %+v", hidden)
	}
}
