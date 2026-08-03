package api

import (
	"net/url"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// A discovery list is scoped by the item listing's own filter engine
// now: a narrowed page comes back full, and a cursor names a scope.

// browseStatus reads a status, for the refusals browsePage fails on.
func browseStatus(t *testing.T, h *harness, query string) int {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/browse"+query, h.token)
	resp.Body.Close()
	return resp.StatusCode
}

// firstArtistBucket returns the key of an artist bucket the fixtures fill.
func firstArtistBucket(t *testing.T, h *harness) FacetBucket {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/facets?dimension=artist", h.token)
	for _, b := range decode[FacetPage](t, resp).Buckets {
		if b.Count > 0 && b.Key != "" {
			return b
		}
	}
	t.Fatal("no artist bucket in the fixture library")
	return FacetBucket{}
}

// The filter used to run over the page the catalog answered, so a shelf
// asking for N of one medium got however many of N rows matched.
func TestBrowseMediaTypeIsPushedDown(t *testing.T) {
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	// The book sorts last, so a one-row window at the head holds none of
	// it; filtering that window would answer an empty page.
	page := browsePage(t, h, "?list=alphabetical&mediaType=audiobook&limit=1")
	if len(page.Items) != 1 {
		t.Fatalf("a one-item audiobook shelf drew %d items, want 1", len(page.Items))
	}
	if page.Items[0].MediaType != "audiobook" {
		t.Fatalf("shelf drew a %s item", page.Items[0].MediaType)
	}

	// And the music side is unchanged.
	music := browsePage(t, h, "?list=alphabetical&mediaType=music&limit=100")
	if len(music.Items) != 4 {
		t.Fatalf("music shelf drew %d items, want the 4 fixture tracks", len(music.Items))
	}
}

// The same filter the bucket's listing uses, so a count, the list it
// opens, and a shuffle over it cannot disagree.
func TestBrowseScopesToAFacetBucket(t *testing.T) {
	h := newHarness(t)
	bucket := firstArtistBucket(t, h)

	scoped := browsePage(t, h,
		"?list=alphabetical&facet=artist&facetKey="+url.QueryEscape(bucket.Key)+"&limit=500")
	if len(scoped.Items) != bucket.Count {
		t.Fatalf("browse scoped to %q drew %d items, the bucket counts %d",
			bucket.Label, len(scoped.Items), bucket.Count)
	}

	// The scope composes with the list's order rather than replacing it.
	random := browsePage(t, h,
		"?list=random&facet=artist&facetKey="+url.QueryEscape(bucket.Key)+"&limit=500")
	if len(random.Items) != bucket.Count {
		t.Fatalf("random scoped to %q drew %d items, want %d",
			bucket.Label, len(random.Items), bucket.Count)
	}
}

// A browse cursor names a position in a seeded permutation, so under
// another seed it named a silently wrong window.
func TestBrowseCursorCarriesItsScope(t *testing.T) {
	h := newHarness(t)
	bucket := firstArtistBucket(t, h)

	first := browsePage(t, h, "?list=random&seed=7&limit=1")
	if first.NextCursor == nil {
		t.Fatal("a capped random page carries no cursor")
	}
	cursor := url.QueryEscape(*first.NextCursor)

	// A cursor with no seed is not a fresh seed: minting one would refuse
	// the cursor for a difference the caller never made.
	if got := browseStatus(t, h, "?list=random&limit=1&cursor="+cursor); got != 400 {
		t.Errorf("a seedless cursored page = %d, want 400 from the scope, not a minted seed", got)
	}

	// Its own scope still pages.
	if got := browseStatus(t, h, "?list=random&seed=7&limit=1&cursor="+cursor); got != 200 {
		t.Errorf("paging under the issuing scope = %d, want 200", got)
	}
	for _, tc := range []struct {
		name  string
		query string
	}{
		{"a changed seed", "?list=random&seed=8&limit=1&cursor=" + cursor},
		{"a changed list", "?list=alphabetical&seed=7&limit=1&cursor=" + cursor},
		{"a changed mediaType", "?list=random&seed=7&mediaType=music&limit=1&cursor=" + cursor},
		{"an added facet", "?list=random&seed=7&limit=1&facet=artist&facetKey=" +
			url.QueryEscape(bucket.Key) + "&cursor=" + cursor},
	} {
		if got := browseStatus(t, h, tc.query); got != 400 {
			t.Errorf("%s = %d, want 400", tc.name, got)
		}
	}
}

// Inverted risk from browse's: a reused cursor here only loses the new
// filter's head. Refused anyway; ADR-0040 says why.
func TestItemsCursorCarriesItsScope(t *testing.T) {
	h := newHarness(t)
	bucket := firstArtistBucket(t, h)

	page := h.items(t, "?limit=1")
	if page.NextCursor == nil {
		t.Fatal("a capped item page carries no cursor")
	}
	cursor := url.QueryEscape(*page.NextCursor)

	itemsStatus := func(query string) int {
		t.Helper()
		resp := get(t, h.ts, "/api/v1/library/items"+query, h.token)
		resp.Body.Close()
		return resp.StatusCode
	}
	if got := itemsStatus("?limit=1&cursor=" + cursor); got != 200 {
		t.Errorf("paging under the issuing scope = %d, want 200", got)
	}
	if got := itemsStatus("?limit=1&mediaType=music&cursor=" + cursor); got != 400 {
		t.Errorf("a cursor reused under a mediaType = %d, want 400", got)
	}
	if got := itemsStatus("?limit=1&facet=artist&facetKey=" +
		url.QueryEscape(bucket.Key) + "&cursor=" + cursor); got != 400 {
		t.Errorf("a cursor reused under a facet = %d, want 400", got)
	}
}

// A list scoped to some kinds cannot answer for the others, and upstream
// answers the pairing with an empty page. On a surface whose job is
// saying what the library holds, an empty page reads as "you have none";
// the refusal says which question was wrong.
func TestBrowseKindScopedListRefusesForeignScope(t *testing.T) {
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	if got := browseStatus(t, h, "?list=newest&mediaType=podcast"); got != 400 {
		t.Errorf("newest+podcast = %d, want 400", got)
	}
	if got := browseStatus(t, h, "?list=newest&facet=kind&facetKey=episode"); got != 400 {
		t.Errorf("newest drilled to the episode kind = %d, want 400", got)
	}

	// The kinds newest does order by are unaffected, filter or none.
	for _, q := range []string{
		"?list=newest",
		"?list=newest&mediaType=music",
		"?list=newest&mediaType=audiobook",
		"?list=newest&facet=kind&facetKey=track",
	} {
		if got := browseStatus(t, h, q); got != 200 {
			t.Errorf("browse%s = %d, want 200", q, got)
		}
	}

	// Only the scoped list refuses: an unscoped one still answers an
	// honest empty page for a medium the library has none of.
	if got := browseStatus(t, h, "?list=alphabetical&mediaType=podcast"); got != 200 {
		t.Errorf("alphabetical+podcast = %d, want 200", got)
	}
}
