package service

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// artistBucketKey is the bare pid a bucket's key carries, which is what
// a scope takes: the API prefix belongs to the entity surfaces.
func artistBucketKey(apiArtistPID string) string {
	return strings.TrimPrefix(apiArtistPID, PrefixArtist+"-")
}

// TestScopedFacetCountsTheScopeOnly is the read behind an artist's
// "Appears on": album buckets counted over one artist's items rather
// than over the library. Before this the only scoped read available
// answered *items*, so the shelf downloaded track rows and collapsed
// them client-side.
func TestScopedFacetCountsTheScopeOnly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	artist := bucketPID(t, ctx, svc, uc, "artist", "Field Notes")
	key := artistBucketKey(artist)

	page, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Limit: 500,
	})
	if err != nil {
		t.Fatalf("scoped enumeration: %v", err)
	}
	if len(page.Buckets) != 1 {
		t.Fatalf("scoping album by one artist gave %+v", page.Buckets)
	}
	got := page.Buckets[0]
	if got.Label != "Long Exposure" || got.Count != 2 {
		t.Fatalf("scoped bucket is %+v, want Long Exposure with 2", got)
	}
	// The entity pid still rides the bucket, which is what makes the
	// shelf's card openable without a second read.
	if got.EntityPID == "" {
		t.Fatalf("scoped bucket carries no entity pid: %+v", got)
	}

	// And the unscoped enumeration still answers the whole library, so the
	// scope narrowed the read rather than the dimension.
	whole, err := svc.Facets(ctx, uc, FacetQuery{Dimension: "album", Limit: 500})
	if err != nil {
		t.Fatal(err)
	}
	if len(whole.Buckets) != 2 {
		t.Fatalf("the unscoped album enumeration has %d buckets, want 2", len(whole.Buckets))
	}
}

// TestScopedFacetBypassesTheCacheBothWays is the trap an entity scope
// (an artist, a genre, any scope but a kind) has to avoid. The cache key
// does not name the entity, so an entity-scoped result published under
// it would answer every later unscoped read with one artist's albums
// until the catalog moved; and an entity-scoped read served *from* it
// would hand an artist page the whole library. Neither direction is
// allowed. A kind scope is keyed in instead; see
// TestKindScopedFacetIsCachedPerKind.
func TestScopedFacetBypassesTheCacheBothWays(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)
	settleCatalogFeed(t, svc)

	// Warming only the artist dimension, so the album cache is still cold
	// when the scoped read below runs.
	artist := bucketPID(t, ctx, svc, uc, "artist", "Field Notes")
	key := artistBucketKey(artist)
	if servesFromCache(svc, "album") {
		t.Fatal("the album enumeration was cached before anything asked for it")
	}

	scoped, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Limit: 500,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(scoped.Buckets) != 1 {
		t.Fatalf("scoped read gave %+v", scoped.Buckets)
	}
	// No publish: the scoped answer must not become the album dimension's
	// cached enumeration.
	if servesFromCache(svc, "album") {
		t.Fatal("a scoped enumeration was published under the dimension's cache key")
	}

	// Now warm the cache with the real thing, and prove the scoped read
	// does not take it.
	whole, err := svc.Facets(ctx, uc, FacetQuery{Dimension: "album", Limit: 500})
	if err != nil {
		t.Fatal(err)
	}
	if len(whole.Buckets) != 2 || !servesFromCache(svc, "album") {
		t.Fatalf("the unscoped enumeration did not warm the cache: %+v", whole.Buckets)
	}
	again, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Limit: 500,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(again.Buckets) != 1 {
		t.Fatalf("a scoped read was answered from the cache: %+v", again.Buckets)
	}
}

// TestScopedFacetRefusals covers what the pair may not be: a dimension
// cannot scope itself (it would answer the one bucket it was handed),
// and the scope obeys the drill's own empty-key rules.
func TestScopedFacetRefusals(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	for _, bad := range []struct {
		why              string
		dimension, facet string
		key              string
	}{
		{"a dimension scoped by itself", "album", "album", "whatever"},
		{"an unknown scope dimension", "album", "not-a-dimension", ""},
		{"kind has no unknown bucket to scope by", "album", "kind", ""},
	} {
		_, err := svc.Facets(ctx, uc, FacetQuery{
			Dimension: bad.dimension, Facet: bad.facet, FacetKey: bad.key, Limit: 100,
		})
		if KindOf(err) != KindInvalid {
			t.Fatalf("%s should be a request error, got %v", bad.why, err)
		}
	}

	// An empty key on a dimension that has an unknown bucket is a real
	// scope: the items the dimension is absent from. The fixture tags
	// every track with an artist, so it is legitimately empty.
	page, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: "", Limit: 100,
	})
	if err != nil {
		t.Fatalf("scoping by the unknown artist bucket: %v", err)
	}
	if len(page.Buckets) != 0 {
		t.Fatalf("no track is artist-less, but the scope found %+v", page.Buckets)
	}
}

// TestScopedFacetCursorCarriesItsScope: a scoped page and an unscoped
// one are two bucket lists, not two windows onto one, so a cursor minted
// under either names no position in the other. Refused rather than
// answered, for the reason every other cursor mismatch here is.
func TestScopedFacetCursorCarriesItsScope(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	// One bucket per page over the two-album library, so both directions
	// have a cursor to misuse.
	whole, err := svc.Facets(ctx, uc, FacetQuery{Dimension: "album", Limit: 1})
	if err != nil {
		t.Fatal(err)
	}
	if whole.Next == "" {
		t.Fatal("the unscoped enumeration fit one bucket")
	}
	artist := bucketPID(t, ctx, svc, uc, "artist", "Field Notes")
	key := artistBucketKey(artist)
	if _, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Cursor: whole.Next, Limit: 1,
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an unscoped cursor replayed under a scope gave %v", err)
	}

	// Every artist at once, so the scoped listing has more than one bucket
	// and mints a cursor of its own.
	scoped, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "artist", Facet: "kind", FacetKey: "track", Limit: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if scoped.Next == "" {
		t.Fatal("the scoped enumeration fit one bucket")
	}
	if _, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "artist", Cursor: scoped.Next, Limit: 1,
	}); KindOf(err) != KindInvalid {
		t.Fatalf("a scoped cursor replayed unscoped gave %v", err)
	}
	// The same scope still pages, so the refusal is about the scope rather
	// than about the cursor.
	if _, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "artist", Facet: "kind", FacetKey: "track", Cursor: scoped.Next, Limit: 1,
	}); err != nil {
		t.Fatalf("the scoped listing did not page: %v", err)
	}
}

// TestScopedFacetHonoursTheGrant: the scope narrows what is counted; it
// does not widen who may count it.
func TestScopedFacetHonoursTheGrant(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)

	artist := bucketPID(t, ctx, svc, uc, "artist", "Field Notes")
	key := artistBucketKey(artist)
	restricted := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{"lb-nothing": true},
	}
	page, err := svc.Facets(ctx, restricted, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Limit: 100,
	})
	if err != nil {
		t.Fatalf("restricted scoped enumeration: %v", err)
	}
	if len(page.Buckets) != 0 {
		t.Fatalf("a caller granted no holding library saw %+v", page.Buckets)
	}

	// A caller granted nothing at all short-circuits to an empty page
	// without touching the catalog - but a malformed scope is still a
	// request error, or the refusal would depend on who asked.
	ungranted := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID}
	if _, err := svc.Facets(ctx, ungranted, FacetQuery{
		Dimension: "album", Facet: "album", FacetKey: key, Limit: 100,
	}); KindOf(err) != KindInvalid {
		t.Fatalf("a bad scope should refuse whoever asks, got %v", err)
	}
	if _, err := svc.Facets(ctx, ungranted, FacetQuery{
		Dimension: "album", Facet: "artist", FacetKey: key, Limit: 100,
	}); err != nil {
		t.Fatalf("a good scope should still answer empty, got %v", err)
	}
}

// TestScopedFacetByKindBookCountsBooksOnly pins what the Books Authors
// and Genres indexes read: an artist or genre enumeration scoped to the
// book kind counts books alone, and a bucket's count agrees with the
// book-scoped list it opens, though a track shares the artist and genre.
func TestScopedFacetByKindBookCountsBooksOnly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateM4B(dir, fixtures.Spec{
			Name: "ensemble-book", Duration: 2 * time.Second,
			Tags: map[string]string{
				"TITLE": "Ensemble Tales", "ALBUM": "Ensemble Tales",
				"ARTIST": "Test Ensemble", "ALBUMARTIST": "Test Ensemble", "GENRE": "Ambient",
			},
		}); err != nil {
			t.Fatal(err)
		}
	}})
	books, err := svc.Items(ctx, uc, ItemFilter{MediaType: "audiobook"}, "", 10)
	if err != nil || len(books.Items) != 1 {
		t.Fatalf("books = %+v (%v), want the one fixture book", books.Items, err)
	}
	book := books.Items[0].PID

	for _, tc := range []struct{ dimension, label string }{
		{"artist", "Test Ensemble"},
		{"genre", "Ambient"},
	} {
		whole, err := svc.Facets(ctx, uc, FacetQuery{Dimension: tc.dimension, Limit: 500})
		if err != nil {
			t.Fatal(err)
		}
		if got := bucketCount(whole.Buckets, tc.label); got != 4 {
			t.Fatalf("unscoped %s %q counts %d, want the 3 tracks and the book", tc.dimension, tc.label, got)
		}

		scoped, err := svc.Facets(ctx, uc, FacetQuery{
			Dimension: tc.dimension, Facet: "kind", FacetKey: "book", Limit: 500,
		})
		if err != nil {
			t.Fatalf("%s scoped to books: %v", tc.dimension, err)
		}
		if len(scoped.Buckets) != 1 || scoped.Buckets[0].Label != tc.label || scoped.Buckets[0].Count != 1 {
			t.Fatalf("%s scoped to books = %+v, want %q with 1", tc.dimension, scoped.Buckets, tc.label)
		}

		opened, err := svc.Items(ctx, uc, ItemFilter{
			MediaType: "audiobook", Facet: tc.dimension, FacetKey: scoped.Buckets[0].Key,
		}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		if len(opened.Items) != 1 || opened.Items[0].PID != book {
			t.Fatalf("%s bucket opened %+v, want the book alone", tc.dimension, opened.Items)
		}
	}
}

func bucketCount(buckets []FacetBucket, label string) int {
	for _, b := range buckets {
		if b.Label == label {
			return b.Count
		}
	}
	return 0
}

// servesKindFromCache is servesFromCache for an enumeration scoped to
// one kind.
func servesKindFromCache(l *Library, dimension, kind string) bool {
	gen := l.facetGeneration(context.Background())
	l.facets.mu.Lock()
	defer l.facets.mu.Unlock()
	if l.facets.gen != gen {
		return false
	}
	_, ok := l.facets.byDimension[facetCacheKey{dimension: dimension, sort: FacetSortCount, kind: kind}]
	return ok
}

// TestKindScopedFacetIsCachedPerKind: the music and books indexes read
// whole dimensions scoped to a kind, and a music library's track scope is
// as large as the unscoped read, so it is cached as that one is: per
// catalog generation, for the callers the unscoped cache serves, under a
// key naming the kind. A repeated read is a hit, a catalog change
// invalidates it, and no other caller or scope shares the entry.
func TestKindScopedFacetIsCachedPerKind(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	tracks := func(who *UserCtx) map[string]int {
		t.Helper()
		page, err := svc.Facets(ctx, who, FacetQuery{
			Dimension: "artist", Facet: "kind", FacetKey: "track", Limit: 500,
		})
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]int{}
		for _, b := range page.Buckets {
			out[b.Label] = b.Count
		}
		return out
	}

	if got := tracks(uc); got["Test Ensemble"] != 3 || got["Brass Nine"] != 1 {
		t.Fatalf("artists over tracks = %v, want the fixture's", got)
	}
	if !servesKindFromCache(svc, "artist", "track") {
		t.Fatal("the kind-scoped enumeration did not cache")
	}
	// Under its own key: neither the whole library's nor another kind's.
	if servesFromCache(svc, "artist") || servesKindFromCache(svc, "artist", "book") {
		t.Fatal("the kind-scoped enumeration was published under another scope's key")
	}

	// A hit: what the cache holds is what the next read answers.
	gen := svc.facetGeneration(ctx)
	marked := []FacetBucket{facetFolded(FacetBucket{Key: "marked", Label: "Marked", Count: 7})}
	svc.publishFacetBuckets(ctx, gen, facetCacheKey{dimension: "artist", sort: FacetSortCount, kind: "track"}, marked)
	if got := tracks(uc); len(got) != 1 || got["Marked"] != 7 {
		t.Fatalf("a repeated kind-scoped read = %v, want the cached entry", got)
	}

	// Another grant never shares it: a caller granted a library holding
	// nothing reads live, past the marked entry, and its empty answer is
	// not published over it.
	restricted := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{"01JZX5N8QW3F4V9T2B7KDNOLIB0": true},
	}
	if got := tracks(restricted); len(got) != 0 {
		t.Fatalf("a caller granted no library holding tracks saw %v", got)
	}
	if got := tracks(uc); len(got) != 1 || got["Marked"] != 7 {
		t.Fatalf("after a restricted read the cached entry = %v, want it untouched", got)
	}

	// A key that names no kind is not cached: it is any string a client
	// sends.
	if _, err := svc.Facets(ctx, uc, FacetQuery{
		Dimension: "artist", Facet: "kind", FacetKey: "not-a-kind", Limit: 500,
	}); err != nil {
		t.Fatal(err)
	}
	if servesKindFromCache(svc, "artist", "not-a-kind") {
		t.Fatal("a kind scope naming no kind was cached")
	}

	// A catalog change invalidates it.
	settleCatalogFeed(t, svc)
	tracks(uc)
	if !servesKindFromCache(svc, "artist", "track") {
		t.Fatal("the kind-scoped enumeration did not cache again")
	}
	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	if _, err := svc.EditItemMetadata(ctx, uc, amber, map[string]string{"artist": "Brass Nine"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); servesKindFromCache(svc, "artist", "track"); {
		if time.Now().After(deadline) {
			t.Fatal("an edit to what the catalog holds left the kind-scoped enumeration cached")
		}
		time.Sleep(10 * time.Millisecond)
	}
	settleCatalogFeed(t, svc)
	if got := tracks(uc); got["Test Ensemble"] != 2 || got["Brass Nine"] != 2 {
		t.Errorf("artists over tracks after the edit = %v, want the track moved to Brass Nine", got)
	}
}
