package service

import (
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
)

// settleCatalogFeed waits for the change-feed consumer to catch up with
// everything written so far. The enumeration cache keys on that
// position, so an assertion about what is cached needs it to hold still
// -- and the sweeper's own rewrites keep it moving for a moment after
// the sweep returns.
func settleCatalogFeed(t *testing.T, f genreFixture) int64 {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	last, stable := f.svc.CatalogTailSeq(), 0
	for time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
		switch now := f.svc.CatalogTailSeq(); {
		case now == last:
			if stable++; stable >= 5 {
				return now
			}
		default:
			last, stable = now, 0
		}
	}
	t.Fatal("the catalog change feed never settled")
	return last
}

// facetsOf reads every bucket of a dimension in one page.
func facetsOf(t *testing.T, f genreFixture, dimension string) []FacetBucket {
	t.Helper()
	page, err := f.svc.Facets(f.ctx, f.uc, dimension, "", 500)
	if err != nil {
		t.Fatalf("enumerating %s: %v", dimension, err)
	}
	if page.Next != "" {
		t.Fatalf("%s did not fit one page of 500", dimension)
	}
	if page.Dimension != dimension {
		t.Fatalf("page reports dimension %q", page.Dimension)
	}
	return page.Buckets
}

// TestFacetDimensionsDrillToTheirCount is the contract between the two
// halves of faceted browse: the number a bucket advertises and the
// number of items opening it returns have to be the same, or the browse
// tab lies. It covers the unknown bucket too, which is a real bucket
// with an empty key and the one most likely to be filtered differently
// by the drill than by the aggregation.
func TestFacetDimensionsDrillToTheirCount(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	for _, dimension := range []string{"genre", "artist", "album-artist", "album", "year", "kind"} {
		t.Run(dimension, func(t *testing.T) {
			buckets := facetsOf(t, f, dimension)
			if len(buckets) == 0 {
				t.Fatalf("%s enumerated no buckets", dimension)
			}
			total := 0
			for _, b := range buckets {
				total += b.Count
				page, err := f.svc.Items(f.ctx, f.uc,
					ItemFilter{Facet: dimension, FacetKey: b.Key}, "", 500)
				if err != nil {
					t.Fatalf("drilling %s bucket %q: %v", dimension, b.Label, err)
				}
				if len(page.Items) != b.Count {
					t.Fatalf("%s bucket %q counts %d but opens %d items",
						dimension, b.Label, b.Count, len(page.Items))
				}
			}
			if total != 5 {
				t.Fatalf("%s buckets cover %d items; the fixture holds 5", dimension, total)
			}
		})
	}
}

// TestFacetUnknownBucketIsDrillable: the fixture tags no years, so every
// track lands in the unknown year bucket, which must open its items
// rather than 400 on an empty key.
func TestFacetUnknownBucketIsDrillable(t *testing.T) {
	f := newGenreFixture(t)

	buckets := facetsOf(t, f, "year")
	if len(buckets) != 1 || !buckets[0].Unknown || buckets[0].Key != "" {
		t.Fatalf("year buckets = %+v; want one unknown bucket with an empty key", buckets)
	}
	if !strings.HasPrefix(buckets[0].Label, "[") {
		t.Fatalf("the unknown bucket's label is %q; it should be the catalog's sentinel", buckets[0].Label)
	}
	page, err := f.svc.Items(f.ctx, f.uc, ItemFilter{Facet: "year", FacetKey: ""}, "", 100)
	if err != nil {
		t.Fatalf("drilling the unknown year bucket: %v", err)
	}
	if len(page.Items) != buckets[0].Count {
		t.Fatalf("the unknown year bucket counts %d but opens %d", buckets[0].Count, len(page.Items))
	}
}

// TestFacetEntityPidsOnEntityDimensions: an artist or album bucket
// carries the catalog entity behind it, so a browse tab can navigate to
// a real entity page; year and kind buckets carry none, and a minted
// "ar-" with no ULID after it would parse back as malformed.
func TestFacetEntityPidsOnEntityDimensions(t *testing.T) {
	f := newGenreFixture(t)

	for _, b := range facetsOf(t, f, "artist") {
		if b.Unknown {
			continue
		}
		if !strings.HasPrefix(b.EntityPID, PrefixArtist+"-") {
			t.Fatalf("artist bucket %q carries entityPid %q", b.Label, b.EntityPID)
		}
		if _, _, ok := parseAPIPID(b.EntityPID); !ok {
			t.Fatalf("artist bucket %q carries an unparseable pid %q", b.Label, b.EntityPID)
		}
	}
	for _, dimension := range []string{"year", "kind"} {
		for _, b := range facetsOf(t, f, dimension) {
			if b.EntityPID != "" {
				t.Fatalf("%s bucket %q carries entityPid %q; it is not an entity",
					dimension, b.Label, b.EntityPID)
			}
		}
	}
}

// TestFacetPagingIsStableAcrossTheCache walks a dimension one bucket at
// a time. The first call computes and caches the whole enumeration and
// later pages are served from it, so a paging bug or an unstable sort
// would show up here as a duplicate or a dropped bucket.
func TestFacetPagingIsStableAcrossTheCache(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	want := facetsOf(t, f, "genre")
	var got []FacetBucket
	cursor := ""
	for i := 0; ; i++ {
		if i > len(want)+2 {
			t.Fatal("paging never reached the last page")
		}
		page, err := f.svc.Facets(f.ctx, f.uc, "genre", cursor, 1)
		if err != nil {
			t.Fatalf("paging genres: %v", err)
		}
		got = append(got, page.Buckets...)
		if page.Next == "" {
			break
		}
		cursor = page.Next
	}
	if len(got) != len(want) {
		t.Fatalf("paged %d buckets one at a time, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].Key != want[i].Key || got[i].Count != want[i].Count {
			t.Fatalf("bucket %d paged as %+v, want %+v", i, got[i], want[i])
		}
	}

	if _, err := f.svc.Facets(f.ctx, f.uc, "genre", "not-a-cursor", 10); err == nil {
		t.Fatal("a malformed cursor was accepted")
	} else if KindOf(err) != KindInvalid {
		t.Fatalf("a malformed cursor answered %v", KindOf(err))
	}
}

// TestRestrictedFacetsAreComputedLive: the cache holds the
// full-visibility answer only. A restricted caller's enumeration is a
// function of their grant as well as the catalog position, so serving
// them from that cache would hand them counts over a library they were
// never granted.
func TestRestrictedFacetsAreComputedLive(t *testing.T) {
	f := newGenreFixture(t)

	// Warm the cache with the full-visibility answer first: that is the
	// state a leak would come from.
	full := facetsOf(t, f, "artist")
	if len(full) == 0 {
		t.Fatal("the full-visibility enumeration is empty")
	}

	empty, err := f.svc.AddLibrary(f.ctx, f.uc, AddLibraryInput{Name: "empty", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	restricted := &UserCtx{
		ID: f.uc.ID, CatalogPID: f.uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(empty.PID, PrefixLibrary+"-"): true},
	}
	page, err := f.svc.Facets(f.ctx, restricted, "artist", "", 100)
	if err != nil {
		t.Fatalf("restricted enumeration: %v", err)
	}
	if len(page.Buckets) != 0 {
		t.Fatalf("a caller granted only an empty library saw %+v", page.Buckets)
	}

	// A caller with no grant at all short-circuits to the same answer.
	page, err = f.svc.Facets(f.ctx, &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID}, "artist", "", 100)
	if err != nil {
		t.Fatalf("ungranted enumeration: %v", err)
	}
	if len(page.Buckets) != 0 {
		t.Fatalf("a caller granted nothing saw %+v", page.Buckets)
	}

	// And the full-visibility answer is unchanged by any of it.
	if again := facetsOf(t, f, "artist"); len(again) != len(full) {
		t.Fatalf("the full-visibility enumeration changed from %d to %d buckets", len(full), len(again))
	}
}

// servesFromCache reports whether the enumeration cache would answer
// this dimension right now: the entry has to exist *and* belong to the
// generation the cache is currently valid for.
func servesFromCache(l *Library, dimension string) bool {
	gen := l.facetGeneration()
	l.facets.mu.Lock()
	defer l.facets.mu.Unlock()
	if l.facets.gen != gen {
		return false
	}
	_, ok := l.facets.byDimension[dimension]
	return ok
}

// TestVocabularyEditInvalidatesTheEnumerationCache: a cached bucket list
// is a function of the catalog *and* of WaxDeck's genre vocabulary,
// since the vocabulary supplies the genre labels. Keying the cache on
// the catalog feed position alone would leave a vocabulary edit
// invisible to it -- such an edit writes no catalog state, so the feed
// never moves -- and the browse tab would serve the previous spellings
// until some unrelated item change happened to bump it.
func TestVocabularyEditInvalidatesTheEnumerationCache(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)
	tail := settleCatalogFeed(t, f)

	before := facetsOf(t, f, "genre")
	facetsOf(t, f, "artist")
	if !servesFromCache(f.svc, "genre") || !servesFromCache(f.svc, "artist") {
		t.Fatal("the enumerations did not cache")
	}
	var hipHop bool
	for _, b := range before {
		if b.Label == "Hip Hop" {
			hipHop = true
		}
	}
	if !hipHop {
		t.Fatalf("the fixture did not produce a Hip Hop bucket: %+v", before)
	}

	// Rename the canonical spelling. Nothing the catalog stores changes:
	// "Hip-Hop" folds to the same key, so no item is rewritten, and the
	// edit itself writes only to waxdeck.db. The feed position must stay
	// exactly where it was -- which is the whole reason the cache cannot
	// notice this by watching the catalog.
	if _, err := f.svc.PutGenreTree(f.ctx, f.uc, []GenreNodeDTO{
		{Name: "Hip-Hop", Aliases: []string{"Rap", "HipHop"}},
	}); err != nil {
		t.Fatalf("storing a vocabulary: %v", err)
	}
	if now := f.svc.CatalogTailSeq(); now != tail {
		t.Fatalf("a vocabulary edit moved the catalog feed (%d -> %d); it writes no catalog state", tail, now)
	}
	if servesFromCache(f.svc, "genre") {
		t.Fatal("a vocabulary edit left the stale genre enumeration servable")
	}

	after := facetsOf(t, f, "genre")
	for _, b := range after {
		if b.Label == "Hip Hop" {
			t.Fatalf("the genre tab still shows the previous canonical spelling: %+v", after)
		}
	}
	var renamed bool
	for _, b := range after {
		if b.Label == "Hip-Hop" {
			renamed = true
		}
	}
	if !renamed {
		t.Fatalf("no bucket carries the new canonical spelling: %+v", after)
	}
}

// TestStaleEnumerationCannotEvictACurrentOne: enumerations are computed
// unlocked, so a slow one can finish after a faster one that started
// later. Both then try to publish. Letting the slow, superseded result
// land would not just cache stale buckets -- it would stamp the whole
// cache with the older generation, throwing away the current entry and
// turning every later read into a miss until something moved the
// generation again. A vocabulary edit moves nothing else, so "until
// something moved it" can be a long time.
func TestStaleEnumerationCannotEvictACurrentOne(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)
	settleCatalogFeed(t, f)

	// The slow reader's work: computed and held, not yet published.
	stale := f.svc.facetGeneration()
	staleBuckets := facetsOf(t, f, "genre")

	// The generation moves under it, and a second dimension publishes
	// against the new one.
	if _, err := f.svc.PutGenreTree(f.ctx, f.uc, []GenreNodeDTO{
		{Name: "Hip-Hop", Aliases: []string{"Rap", "HipHop"}},
	}); err != nil {
		t.Fatalf("storing a vocabulary: %v", err)
	}
	facetsOf(t, f, "artist")
	if !servesFromCache(f.svc, "artist") {
		t.Fatal("the current enumeration did not cache")
	}

	// Now the slow reader publishes. It must be dropped on the floor.
	f.svc.publishFacetBuckets(stale, "genre", staleBuckets)
	if !servesFromCache(f.svc, "artist") {
		t.Fatal("a superseded enumeration rolled the cache back and evicted a current one")
	}
	if servesFromCache(f.svc, "genre") {
		t.Fatal("a superseded enumeration was published")
	}
	for _, b := range facetsOf(t, f, "genre") {
		if b.Label == "Hip Hop" {
			t.Fatal("the superseded labels were served")
		}
	}
}

// TestFacetPagingSurvivesACountChange is why the cursor is a keyset and
// not an offset. Counts are the leading sort term and they move as the
// library changes, so an offset into a re-sorted list skips or repeats
// buckets. Resuming after a remembered position cannot.
func TestFacetPagingSurvivesACountChange(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	first, err := f.svc.Facets(f.ctx, f.uc, "genre", "", 1)
	if err != nil {
		t.Fatalf("first page: %v", err)
	}
	if len(first.Buckets) != 1 || first.Next == "" {
		t.Fatalf("first page = %+v, cursor %q", first.Buckets, first.Next)
	}
	lead := first.Buckets[0]

	// Move a count so the sort order changes under the cursor: retag the
	// off-tree item onto the leading bucket's genre, which grows it.
	it := f.itemNamed(t, "Off Tree")
	if err := f.svc.lib.EditFields(f.ctx, it.PID,
		map[string]string{"genre": lead.Label}, waxbin.EditOptions{}); err != nil {
		t.Fatalf("retagging: %v", err)
	}

	next, err := f.svc.Facets(f.ctx, f.uc, "genre", first.Next, 50)
	if err != nil {
		t.Fatalf("second page: %v", err)
	}
	// Whatever moved, the page after the cursor must not repeat the
	// bucket the cursor pointed at.
	for _, b := range next.Buckets {
		if b.Key == lead.Key {
			t.Fatalf("paging repeated the bucket the cursor ended on: %+v", b)
		}
	}
	// And the two pages together still cover every genre that survived.
	seen := map[string]bool{lead.Key: true}
	for _, b := range next.Buckets {
		seen[b.Key] = true
	}
	for _, b := range facetsOf(t, f, "genre") {
		if !seen[b.Key] {
			t.Fatalf("paging dropped bucket %+v", b)
		}
	}
}

// TestFacetDimensionsWithoutAnUnknownBucket: kind is never absent from
// an item and a custom tag only counts items that carry it, so neither
// enumerates an unknown bucket. An empty key on them is a bad drill, not
// a real-but-empty one, and must say so rather than answering an empty
// page that reads like a legitimate result.
func TestFacetDimensionsWithoutAnUnknownBucket(t *testing.T) {
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Canonical")
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), "MOOD", []string{"calm"}, false, false); err != nil {
		t.Fatalf("setting a custom tag: %v", err)
	}

	for _, dimension := range []string{"kind", "tag.MOOD"} {
		for _, b := range facetsOf(t, f, dimension) {
			if b.Unknown {
				t.Fatalf("%s enumerated an unknown bucket: %+v", dimension, b)
			}
		}
		if _, err := f.svc.Items(f.ctx, f.uc, ItemFilter{Facet: dimension, FacetKey: ""}, "", 10); err == nil {
			t.Fatalf("%s accepted an unknown-bucket drill", dimension)
		} else if KindOf(err) != KindInvalid {
			t.Fatalf("%s answered %v", dimension, KindOf(err))
		}
	}
}

// TestTagDimensionsCanonicalize: tag keys canonicalize, so every casing
// of one key is one dimension. Treating them as distinct would let a
// client mint an unbounded number of cache entries holding identical
// enumerations while the catalog sat idle.
func TestTagDimensionsCanonicalize(t *testing.T) {
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Canonical")
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), "MOOD", []string{"calm"}, false, false); err != nil {
		t.Fatalf("setting a custom tag: %v", err)
	}
	// The tag write moves the catalog feed; let it land before asserting
	// on a cache that keys on where the feed is.
	settleCatalogFeed(t, f)

	for _, spelling := range []string{"tag.MOOD", "tag.mood", "tag.MoOd", "tag. mood "} {
		page, err := f.svc.Facets(f.ctx, f.uc, spelling, "", 10)
		if err != nil {
			t.Fatalf("enumerating %q: %v", spelling, err)
		}
		if page.Dimension != "tag.MOOD" {
			t.Fatalf("%q reported dimension %q; the canonical key is what everything downstream keys on",
				spelling, page.Dimension)
		}
		if len(page.Buckets) != 1 || page.Buckets[0].Key != "calm" {
			t.Fatalf("%q enumerated %+v", spelling, page.Buckets)
		}
		if !servesFromCache(f.svc, "tag.MOOD") {
			t.Fatalf("%q did not populate the canonical cache entry", spelling)
		}
	}
	// One cache entry, not four.
	f.svc.facets.mu.Lock()
	entries := len(f.svc.facets.byDimension)
	f.svc.facets.mu.Unlock()
	if entries != 1 {
		t.Fatalf("four spellings of one tag key minted %d cache entries", entries)
	}
}

// TestFacetRejectsUnknownDimensions keeps the dimension name fail-closed
// on both halves: enumeration and the listing filter agree on what a
// dimension is, so a filter can never reach the query grammar with a
// field name the enumeration would have refused.
func TestFacetRejectsUnknownDimensions(t *testing.T) {
	f := newGenreFixture(t)

	for _, dimension := range []string{"", "artists", "tag.", "tag.BAD=KEY", "genre_pid"} {
		if _, err := f.svc.Facets(f.ctx, f.uc, dimension, "", 10); err == nil {
			t.Fatalf("dimension %q was enumerated", dimension)
		} else if KindOf(err) != KindInvalid {
			t.Fatalf("dimension %q answered %v", dimension, KindOf(err))
		}
		if dimension == "" {
			// An empty facet on a listing means "no filter", not a bad one.
			continue
		}
		if _, err := f.svc.Items(f.ctx, f.uc, ItemFilter{Facet: dimension, FacetKey: "x"}, "", 10); err == nil {
			t.Fatalf("dimension %q was accepted as a listing filter", dimension)
		}
	}
}

// TestTagFacetDimension covers the open-ended half of the dimension set:
// a custom tag key facets and drills like a fixed dimension, and has no
// unknown bucket, since only items carrying the key contribute.
func TestTagFacetDimension(t *testing.T) {
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Canonical")
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), "MOOD", []string{"calm"}, false, false); err != nil {
		t.Fatalf("setting a custom tag: %v", err)
	}

	buckets := facetsOf(t, f, "tag.MOOD")
	if len(buckets) != 1 || buckets[0].Key != "calm" || buckets[0].Count != 1 {
		t.Fatalf("tag.MOOD buckets = %+v", buckets)
	}
	page, err := f.svc.Items(f.ctx, f.uc, ItemFilter{Facet: "tag.MOOD", FacetKey: "calm"}, "", 10)
	if err != nil {
		t.Fatalf("drilling tag.MOOD: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].Title != "Canonical" {
		t.Fatalf("tag.MOOD drill returned %+v", page.Items)
	}
	if _, err := f.svc.Items(f.ctx, f.uc, ItemFilter{Facet: "tag.MOOD", FacetKey: ""}, "", 10); err == nil {
		t.Fatal("a custom tag dimension accepted an unknown-bucket drill")
	}
}

// TestFacetComposesWithMediaType: the browse tab's dimension filter and
// the media-type filter narrow together rather than one replacing the
// other.
func TestFacetComposesWithMediaType(t *testing.T) {
	f := newGenreFixture(t)

	buckets := facetsOf(t, f, "kind")
	if len(buckets) != 1 || buckets[0].Key != "track" {
		t.Fatalf("kind buckets = %+v; the fixture is all music", buckets)
	}
	page, err := f.svc.Items(f.ctx, f.uc,
		ItemFilter{MediaType: "audiobook", Facet: "kind", FacetKey: "track"}, "", 10)
	if err != nil {
		t.Fatalf("composed filter: %v", err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("a track bucket filtered to audiobooks returned %d items", len(page.Items))
	}
}
