package service

import (
	"strings"
	"testing"
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

// TestScopedFacetBypassesTheCacheBothWays is the trap this change had to
// avoid. The enumeration cache is keyed on dimension and order alone, so
// a scoped result published under that key would answer every later
// unscoped read with one artist's albums until the catalog moved; and a
// scoped read served *from* it would hand an artist page the whole
// library. Neither direction is allowed.
func TestScopedFacetBypassesTheCacheBothWays(t *testing.T) {
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
