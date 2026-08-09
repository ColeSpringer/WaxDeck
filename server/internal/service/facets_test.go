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
func settleCatalogFeed(t *testing.T, svc *Library) int64 {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	last, stable := svc.CatalogTailSeq(), 0
	for time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
		switch now := svc.CatalogTailSeq(); {
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
	page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: dimension, Limit: 500})
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
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	for _, dimension := range []string{
		"genre", "artist", "album-artist", "album", "release-group", "year", "kind",
	} {
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
	t.Parallel()
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

// TestFacetEntityPidsOnEntityDimensions: an artist, album, or
// release-group bucket carries the catalog entity behind it, so a browse
// tab can navigate to a real entity page; year and kind buckets carry
// none, and a minted "ar-" with no ULID after it would parse back as
// malformed.
func TestFacetEntityPidsOnEntityDimensions(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)

	for _, tc := range []struct{ dimension, prefix string }{
		{"artist", PrefixArtist},
		{"album", PrefixAlbum},
		{"release-group", PrefixReleaseGroup},
	} {
		for _, b := range facetsOf(t, f, tc.dimension) {
			if b.Unknown {
				continue
			}
			if !strings.HasPrefix(b.EntityPID, tc.prefix+"-") {
				t.Fatalf("%s bucket %q carries entityPid %q", tc.dimension, b.Label, b.EntityPID)
			}
			if _, _, ok := parseAPIPID(b.EntityPID); !ok {
				t.Fatalf("%s bucket %q carries an unparseable pid %q", tc.dimension, b.Label, b.EntityPID)
			}
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
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	want := facetsOf(t, f, "genre")
	var got []FacetBucket
	cursor := ""
	for i := 0; ; i++ {
		if i > len(want)+2 {
			t.Fatal("paging never reached the last page")
		}
		page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Cursor: cursor, Limit: 1})
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

	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Cursor: "not-a-cursor", Limit: 10}); err == nil {
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
	t.Parallel()
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
	page, err := f.svc.Facets(f.ctx, restricted, FacetQuery{Dimension: "artist", Limit: 100})
	if err != nil {
		t.Fatalf("restricted enumeration: %v", err)
	}
	if len(page.Buckets) != 0 {
		t.Fatalf("a caller granted only an empty library saw %+v", page.Buckets)
	}

	// A caller with no grant at all short-circuits to the same answer.
	page, err = f.svc.Facets(f.ctx, &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID},
		FacetQuery{Dimension: "artist", Limit: 100})
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
	_, ok := l.facets.byDimension[facetCacheKey{dimension, FacetSortCount}]
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
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)
	tail := settleCatalogFeed(t, f.svc)

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
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)
	settleCatalogFeed(t, f.svc)

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
	f.svc.publishFacetBuckets(stale, "genre", FacetSortCount, staleBuckets)
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
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	first, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Limit: 1})
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

	next, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Cursor: first.Next, Limit: 50})
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
	t.Parallel()
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
	t.Parallel()
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Canonical")
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), "MOOD", []string{"calm"}, false, false); err != nil {
		t.Fatalf("setting a custom tag: %v", err)
	}
	// The tag write moves the catalog feed; let it land before asserting
	// on a cache that keys on where the feed is.
	settleCatalogFeed(t, f.svc)

	for _, spelling := range []string{"tag.MOOD", "tag.mood", "tag.MoOd", "tag. mood "} {
		page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: spelling, Limit: 10})
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
	// One dimension in the cache, not four. It holds an entry per order -
	// both come out of the one aggregation - so the thing to count is the
	// dimensions, which is what a client could otherwise mint without
	// bound.
	f.svc.facets.mu.Lock()
	dimensions := map[string]bool{}
	for key := range f.svc.facets.byDimension {
		dimensions[key.dimension] = true
	}
	f.svc.facets.mu.Unlock()
	if len(dimensions) != 1 {
		t.Fatalf("four spellings of one tag key minted %d cached dimensions: %v",
			len(dimensions), dimensions)
	}
}

// TestFacetRejectsUnknownDimensions keeps the dimension name fail-closed
// on both halves: enumeration and the listing filter agree on what a
// dimension is, so a filter can never reach the query grammar with a
// field name the enumeration would have refused.
func TestFacetRejectsUnknownDimensions(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)

	for _, dimension := range []string{"", "artists", "tag.", "tag.BAD=KEY", "genre_pid"} {
		if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: dimension, Limit: 10}); err == nil {
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
	t.Parallel()
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
	t.Parallel()
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

// TestFacetLabelOrderIsAnAlphabet pins the three things the A-to-Z index
// depends on and the byte order gets wrong: case is folded, so "abba"
// does not sort behind "Zebra"; the unknown bucket sorts last whatever
// its sentinel spells, so "[No Genre]" does not lead the list on its
// bracket; and equal labels stay in a fixed order, so a keyset cursor
// can resume on one.
func TestFacetLabelOrderIsAnAlphabet(t *testing.T) {
	t.Parallel()
	buckets := []FacetBucket{
		facetFolded(FacetBucket{Key: "u", Label: "[No Genre]", Count: 9, Unknown: true}),
		facetFolded(FacetBucket{Key: "z", Label: "Zebra", Count: 1}),
		facetFolded(FacetBucket{Key: "b", Label: "abba", Count: 2}),
		facetFolded(FacetBucket{Key: "m2", Label: "mogwai", Count: 3}),
		facetFolded(FacetBucket{Key: "m1", Label: "Mogwai", Count: 4}),
	}
	sortFacetBuckets(buckets, FacetSortLabel)

	var got []string
	for _, b := range buckets {
		got = append(got, b.Label+"/"+b.Key)
	}
	want := []string{"abba/b", "Mogwai/m1", "mogwai/m2", "Zebra/z", "[No Genre]/u"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("label order = %v; want %v", got, want)
		}
	}

	// And the default order is untouched by any of it: biggest first.
	sortFacetBuckets(buckets, FacetSortCount)
	if buckets[0].Label != "[No Genre]" || buckets[len(buckets)-1].Label != "Zebra" {
		t.Fatalf("count order = %+v", buckets)
	}
}

// TestFacetLabelOrderPagesTheWholeDimension: the label order is served
// through the same in-memory keyset as the default one, so the thing to
// prove is that paging it visits every bucket exactly once and hands
// back the same set the other order does.
func TestFacetLabelOrderPagesTheWholeDimension(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	byCount := facetsOf(t, f, "genre")
	if len(byCount) < 3 {
		t.Fatalf("the fixture enumerated %d genre buckets; this test needs several", len(byCount))
	}

	seen := map[string]int{}
	var labels []string
	cursor := ""
	for pages := 0; ; pages++ {
		if pages > len(byCount)+1 {
			t.Fatal("label paging never reached the last page")
		}
		page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Cursor: cursor, Limit: 1})
		if err != nil {
			t.Fatalf("label page %d: %v", pages, err)
		}
		for _, b := range page.Buckets {
			seen[b.Key]++
			labels = append(labels, b.Label)
		}
		if page.Next == "" {
			break
		}
		cursor = page.Next
	}

	if len(seen) != len(byCount) {
		t.Fatalf("label order enumerated %d buckets, count order %d", len(seen), len(byCount))
	}
	for _, b := range byCount {
		if seen[b.Key] != 1 {
			t.Fatalf("bucket %q (%s) appeared %d times under label order", b.Label, b.Key, seen[b.Key])
		}
	}
	for i := 1; i < len(labels); i++ {
		if strings.ToLower(labels[i-1]) > strings.ToLower(labels[i]) {
			t.Fatalf("label paging is out of order at %d: %v", i, labels)
		}
	}
}

// TestFacetCursorBelongsToItsOrder: the two orders interleave
// differently, so a cursor carried across a sort toggle would silently
// skip or repeat buckets. It is refused instead.
func TestFacetCursorBelongsToItsOrder(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	byCount, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Limit: 1})
	if err != nil {
		t.Fatalf("first count page: %v", err)
	}
	if byCount.Next == "" {
		t.Fatal("the fixture fits one page; this test needs two")
	}
	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Cursor: byCount.Next, Limit: 10}); err == nil {
		t.Fatal("a count cursor was accepted under the label order")
	} else if KindOf(err) != KindInvalid {
		t.Fatalf("a mismatched cursor answered %v", KindOf(err))
	}

	byLabel, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Limit: 1})
	if err != nil {
		t.Fatalf("first label page: %v", err)
	}
	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Cursor: byLabel.Next, Limit: 10}); err == nil {
		t.Fatal("a label cursor was accepted under the default order")
	}

	// An order nobody serves is a request error, not a silent default:
	// answering biggest-first to a caller who asked for A to Z would put
	// the wrong letters under the rail.
	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSort("popularity"), Limit: 10}); err == nil {
		t.Fatal("an unknown sort was accepted")
	} else if KindOf(err) != KindInvalid {
		t.Fatalf("an unknown sort answered %v", KindOf(err))
	}
}

// The fold-alignment assertion, which "startsAt lands where paging
// would have" cannot catch: a shared wrong fold fails both the same.
func TestFacetFoldTrimsLeadingWhitespace(t *testing.T) {
	t.Parallel()
	buckets := []FacetBucket{
		facetFolded(FacetBucket{Key: "a", Label: "Abba", Count: 3}),
		facetFolded(FacetBucket{Key: "w", Label: " Weeknd", Count: 2}),
		facetFolded(FacetBucket{Key: "m", Label: "Mogwai", Count: 1}),
	}
	sortFacetBuckets(buckets, FacetSortLabel)
	if got := []string{buckets[0].Key, buckets[1].Key, buckets[2].Key}; got[0] != "a" || got[2] != "w" {
		t.Fatalf("label order = %v; a leading space must not sort ahead of the A's", got)
	}
	// And the seek agrees with the sort.
	if got := facetSeekPrefix(buckets, "w"); got != 2 {
		t.Fatalf("startsAt=w seeked to %d, want the space-prefixed W bucket at 2", got)
	}
}

// Each rule the parameter's description states; every one is a real
// case a rail tap produces.
func TestFacetStartsAtSemantics(t *testing.T) {
	t.Parallel()
	buckets := []FacetBucket{
		facetFolded(FacetBucket{Key: "u", Label: "[No Genre]", Count: 9, Unknown: true}),
		facetFolded(FacetBucket{Key: "a", Label: "Ambient", Count: 4}),
		facetFolded(FacetBucket{Key: "l", Label: "Lounge", Count: 3}),
		facetFolded(FacetBucket{Key: "n", Label: "Noise", Count: 2}),
	}
	sortFacetBuckets(buckets, FacetSortLabel)

	// At-or-after: L to N lands on the first N, not on nothing.
	if got := facetSeekPrefix(buckets, "m"); got != 2 || buckets[got].Key != "n" {
		t.Errorf("startsAt=m seeked to %d (%+v), want the Noise bucket", got, buckets)
	}
	// An exact letter lands on its own first bucket, not past it.
	if got := facetSeekPrefix(buckets, "l"); buckets[got].Key != "l" {
		t.Errorf("startsAt=l seeked to %q, want Lounge", buckets[got].Key)
	}
	// Case is folded, like every other comparison in this order.
	if got := facetSeekPrefix(buckets, "A"); buckets[got].Key != "a" {
		t.Errorf("startsAt=A seeked to %q, want Ambient", buckets[got].Key)
	}
	// Past every real bucket is an empty page, not the sentinel.
	if got := facetSeekPrefix(buckets, "z"); got != len(buckets) {
		t.Errorf("startsAt=z seeked to %d, want the end at %d", got, len(buckets))
	}
	// Not seekable: its own sentinel seeks among the real buckets.
	if got := facetSeekPrefix(buckets, "["); got != 0 {
		t.Errorf("startsAt=[ seeked to %d; the unknown bucket is not addressable by prefix", got)
	}
}

// Through the endpoint, where the refusals live.
func TestFacetStartsAtOverTheCatalog(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	all, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Limit: 500})
	if err != nil {
		t.Fatalf("whole dimension: %v", err)
	}
	if len(all.Buckets) < 3 {
		t.Fatalf("the fixture enumerated %d buckets; this test needs several", len(all.Buckets))
	}

	// The same place paging from the head would have reached.
	target := all.Buckets[len(all.Buckets)/2]
	letter := strings.ToLower(strings.TrimLeft(target.Label, " "))[:1]
	page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, StartsAt: letter, Limit: 500})
	if err != nil {
		t.Fatalf("startsAt=%q: %v", letter, err)
	}
	if len(page.Buckets) == 0 {
		t.Fatalf("startsAt=%q answered nothing; %q is in the dimension", letter, target.Label)
	}
	if got := strings.ToLower(page.Buckets[0].Label)[:1]; got != letter {
		t.Errorf("startsAt=%q opened on %q", letter, page.Buckets[0].Label)
	}

	// Past the end: empty, no cursor, not an error.
	past, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, StartsAt: "zzzz", Limit: 500})
	if err != nil {
		t.Fatalf("startsAt past the end: %v", err)
	}
	if len(past.Buckets) != 0 || past.Next != "" {
		t.Errorf("startsAt=zzzz answered %d buckets and cursor %q, want an empty page", len(past.Buckets), past.Next)
	}

	// Refused rather than silently implying sort=label.
	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", StartsAt: "a", Limit: 10}); KindOf(err) != KindInvalid {
		t.Errorf("startsAt without sort=label answered %v, want invalid-request", KindOf(err))
	}

	// A cursor already names a position.
	first, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Limit: 1})
	if err != nil {
		t.Fatalf("first label page: %v", err)
	}
	if first.Next == "" {
		t.Fatal("the fixture fits one page; this test needs two")
	}
	if _, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Order: FacetSortLabel, Cursor: first.Next, StartsAt: "a", Limit: 10}); KindOf(err) != KindInvalid {
		t.Errorf("startsAt with a cursor answered %v, want invalid-request", KindOf(err))
	}
}

// tag.mood and tag.MOOD are one dimension, so a scope keyed on the raw
// spelling would refuse a cursor the caller could reuse.
func TestBrowseCursorScopeUsesTheCanonicalDimension(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	for _, title := range []string{"Canonical", "Synonym", "Lowercase"} {
		it := f.itemNamed(t, title)
		if _, err := f.svc.SetItemTag(
			f.ctx, f.uc, apiPID(PrefixTrack, it.PID), "MOOD", []string{"calm"}, false, false,
		); err != nil {
			t.Fatalf("setting a custom tag: %v", err)
		}
	}

	scoped := ItemFilter{Facet: "tag.MOOD", FacetKey: "calm"}
	first, err := f.svc.Browse(f.ctx, f.uc, "alphabetical", scoped, 0, "", 1)
	if err != nil {
		t.Fatalf("first page: %v", err)
	}
	if first.Next == "" {
		t.Fatal("the tagged set fits one page; this test needs two")
	}
	for _, spelling := range []string{"tag.MOOD", "tag.mood", "tag.MoOd"} {
		filter := ItemFilter{Facet: spelling, FacetKey: "calm"}
		if _, err := f.svc.Browse(f.ctx, f.uc, "alphabetical", filter, 0, first.Next, 10); err != nil {
			t.Errorf("a cursor from tag.MOOD reused under %s: %v", spelling, err)
		}
	}

	// A different bucket is still a different scope.
	other := ItemFilter{Facet: "tag.mood", FacetKey: "restless"}
	if _, err := f.svc.Browse(f.ctx, f.uc, "alphabetical", other, 0, first.Next, 10); KindOf(err) != KindInvalid {
		t.Errorf("a cursor reused under another bucket answered %v, want invalid-request", KindOf(err))
	}
}

// A cursor carries its dimension: replayed on another it used to seek
// among the wrong buckets and answer an empty page with no error.
func TestFacetCursorBelongsToItsDimension(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Limit: 1})
	if err != nil {
		t.Fatalf("first genre page: %v", err)
	}
	if page.Next == "" {
		t.Fatal("the fixture fits one page; this test needs two")
	}
	if _, err := f.svc.Facets(f.ctx, f.uc,
		FacetQuery{Dimension: "artist", Cursor: page.Next, Limit: 10}); KindOf(err) != KindInvalid {
		t.Errorf("a genre cursor under artist answered %v, want invalid-request", KindOf(err))
	}
	if _, err := f.svc.Facets(f.ctx, f.uc,
		FacetQuery{Dimension: "genre", Cursor: page.Next, Limit: 10}); err != nil {
		t.Errorf("its own dimension still pages: %v", err)
	}
}

// Every browse resolves the acting user's catalog pid, filtered or not.
//
// Before ADR-0048 an unfiltered browse passed the catalog a zero Query
// and so skipped the lookup, which meant a stale pid was ignored on one
// list and rejected on the next. The state predicate is always present
// now, so there is no unfiltered case left to short-circuit and the
// answer is the same either way. Pinned because the asymmetry it
// replaces was itself pinned: whichever way this goes it should be a
// decision, not a side effect of what the query happened to carry.
func TestBrowseRejectsAStaleUserOnEveryList(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	stale := &UserCtx{ID: f.uc.ID, CatalogPID: "us-01JZXNOTAUSERATALL0000000", AllLibraries: true}

	for _, filter := range []ItemFilter{{}, {MediaType: "music"}} {
		if _, err := f.svc.Browse(f.ctx, stale, "alphabetical", filter, 0, "", 10); err == nil {
			t.Errorf("browse with filter %+v resolved a user that does not exist", filter)
		}
	}
	// The live user still pages both ways, so the rejection is about the
	// pid rather than about the predicate the query now always carries.
	for _, filter := range []ItemFilter{{}, {MediaType: "music"}} {
		if _, err := f.svc.Browse(f.ctx, f.uc, "alphabetical", filter, 0, "", 10); err != nil {
			t.Errorf("browse with filter %+v: %v", filter, err)
		}
	}
}
