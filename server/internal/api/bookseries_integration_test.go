package api

import (
	"io"
	"path/filepath"
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
