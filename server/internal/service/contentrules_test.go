package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// restricted builds a caller who can see every library and is allowed
// explicit content, so the only thing narrowing their view is the tag
// rules under test. Both other axes are deliberately wide: a short page
// caused by a library grant would look exactly like the bug these tests
// are about.
func (f genreFixture) restricted(allow, deny []TagRule) *UserCtx {
	return &UserCtx{
		ID:           f.uc.ID,
		CatalogPID:   f.uc.CatalogPID,
		AllLibraries: true,
		Explicit:     true,
		TagAllow:     allow,
		TagDeny:      deny,
	}
}

// tag writes one custom tag onto the item with this title.
func (f genreFixture) tag(t *testing.T, title, key string, values ...string) {
	t.Helper()
	it := f.itemNamed(t, title)
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), key, values, false, false); err != nil {
		t.Fatalf("tagging %s: %v", title, err)
	}
}

// TestRestrictedFacetsDrillToTheirCount is the bug: tag rules were
// applied per item and never in an aggregation, so a bucket advertised a
// count the list it opened could not produce - and a card built from one
// could open onto nothing.
//
// The same contract TestFacetDimensionsDrillToTheirCount holds for an
// unrestricted caller, now for a restricted one. The fixture carries no
// episodes on purpose: their advisory flag and subscription scoping are
// the two residuals that stay per-item, so a bucket holding one could
// legitimately read high and the equality would fail for a documented
// reason rather than a real one.
func TestRestrictedFacetsDrillToTheirCount(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	f.tag(t, "Lowercase", "MOOD", "loud")
	settleCatalogFeed(t, f.svc)

	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "loud"}})
	for _, dimension := range []string{"genre", "album", "kind", "tag.MOOD"} {
		t.Run(dimension, func(t *testing.T) {
			page, err := f.svc.Facets(f.ctx, uc, FacetQuery{Dimension: dimension, Limit: 500})
			if err != nil {
				t.Fatalf("enumerating %s: %v", dimension, err)
			}
			if len(page.Buckets) == 0 {
				t.Fatalf("%s enumerated no buckets for a restricted caller", dimension)
			}
			for _, b := range page.Buckets {
				items, err := f.svc.Items(f.ctx, uc,
					ItemFilter{Facet: dimension, FacetKey: b.Key}, "", 500)
				if err != nil {
					t.Fatalf("drilling %s bucket %q: %v", dimension, b.Label, err)
				}
				if len(items.Items) != b.Count {
					t.Fatalf("%s bucket %q counts %d but opens %d",
						dimension, b.Label, b.Count, len(items.Items))
				}
			}
		})
	}
}

// TestScopedFacetCarriesContentRules is the "Appears on" shelf, which
// reads album buckets scoped to one artist. It used to page the item
// listing, which applied the rules; since it moved to buckets, a denied
// release could hand the shelf a card that opens onto nothing.
func TestScopedFacetCarriesContentRules(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "loud")
	settleCatalogFeed(t, f.svc)

	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "loud"}})
	for _, b := range facetBucketsFor(t, f, uc, "artist") {
		page, err := f.svc.Facets(f.ctx, uc, FacetQuery{
			Dimension: "album", Facet: "artist", FacetKey: b.Key, Limit: 500,
		})
		if err != nil {
			t.Fatalf("scoped enumeration under %q: %v", b.Label, err)
		}
		for _, album := range page.Buckets {
			items, err := f.svc.Items(f.ctx, uc,
				ItemFilter{Facet: "album", FacetKey: album.Key}, "", 500)
			if err != nil {
				t.Fatalf("drilling scoped album %q: %v", album.Label, err)
			}
			if len(items.Items) != album.Count {
				t.Fatalf("scoped album %q counts %d but opens %d",
					album.Label, album.Count, len(items.Items))
			}
		}
	}
}

// TestContentRuleSpellingsFold pins the translation that could not be a
// straight compile: tagRuleMatches compares with EqualFold and SQL does
// not, so a rule's value resolves to the stored spellings that fold to
// it. A rule typed in any casing has to bite the value as stored.
func TestContentRuleSpellingsFold(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "Calm")
	settleCatalogFeed(t, f.svc)

	for _, spelling := range []string{"Calm", "calm", "CALM", "cAlM"} {
		uc := f.restricted([]TagRule{{Key: "MOOD", Value: spelling}}, nil)
		page, err := f.svc.Items(f.ctx, uc, ItemFilter{}, "", 100)
		if err != nil {
			t.Fatalf("listing under allow %q: %v", spelling, err)
		}
		if len(page.Items) != 1 {
			t.Fatalf("allow %q admitted %d items, want the one tagged Calm",
				spelling, len(page.Items))
		}
	}

	// A value nothing carries resolves to an empty set, and an allow rule
	// over an empty set admits nothing rather than everything.
	uc := f.restricted([]TagRule{{Key: "MOOD", Value: "nonesuch"}}, nil)
	page, err := f.svc.Items(f.ctx, uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatalf("listing under an unmatchable allow: %v", err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("an allow rule nothing satisfies admitted %d items", len(page.Items))
	}
}

// TestSetValuedDenyExcludesTheWholeItem is the second hazard the bug
// entry named. A tag is multi-valued, so a deny has to mean "carries
// none of these" rather than "has some other value too": an item tagged
// both Rock and Jazz under a Jazz deny is out of the listing entirely,
// and out of every bucket including Rock's.
func TestSetValuedDenyExcludesTheWholeItem(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "Rock", "Jazz")
	f.tag(t, "Lowercase", "MOOD", "Rock")
	settleCatalogFeed(t, f.svc)

	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "Jazz"}})
	denied := f.itemNamed(t, "Canonical")
	page, err := f.svc.Items(f.ctx, uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatalf("listing under a deny: %v", err)
	}
	for _, row := range page.Items {
		if row.PID == apiPID(PrefixTrack, denied.PID) {
			t.Fatal("an item carrying a denied value survived on the strength of its other one")
		}
	}

	// The Rock bucket is where a plain negation would have leaked it: the
	// item does carry Rock.
	for _, b := range facetBucketsFor(t, f, uc, "tag.MOOD") {
		items, err := f.svc.Items(f.ctx, uc,
			ItemFilter{Facet: "tag.MOOD", FacetKey: b.Key}, "", 100)
		if err != nil {
			t.Fatalf("drilling MOOD bucket %q: %v", b.Label, err)
		}
		if len(items.Items) != b.Count {
			t.Fatalf("MOOD bucket %q counts %d but opens %d", b.Label, b.Count, len(items.Items))
		}
		for _, row := range items.Items {
			if row.PID == apiPID(PrefixTrack, denied.PID) {
				t.Fatalf("the denied item is in the %q bucket", b.Label)
			}
		}
	}
}

// TestRestrictedListingPagesFull is what moving the filter into the
// query buys the caller: a page that used to come back short of its
// limit because the rules were applied to the rows after they were
// chosen now comes back full, and pays no per-row tag read to do it.
func TestRestrictedListingPagesFull(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "loud")
	settleCatalogFeed(t, f.svc)

	// Five tracks, one denied, asked for two at a time: the first page
	// has to hold two, which the per-item filter could not promise.
	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "loud"}})
	page, err := f.svc.Items(f.ctx, uc, ItemFilter{}, "", 2)
	if err != nil {
		t.Fatalf("listing: %v", err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("first page of 2 held %d items", len(page.Items))
	}

	seen := 0
	cursor := ""
	for {
		p, err := f.svc.Items(f.ctx, uc, ItemFilter{}, cursor, 2)
		if err != nil {
			t.Fatalf("paging: %v", err)
		}
		seen += len(p.Items)
		if p.Next == "" {
			break
		}
		cursor = p.Next
	}
	if seen != 4 {
		t.Fatalf("paging saw %d items; the fixture holds 5 and one is denied", seen)
	}
}

// TestContentRulesLeaveTheFacetCacheAlone: the enumeration cache is
// keyed on dimension and order, so a narrowed result published under it
// would hand every other caller the narrowed one.
func TestContentRulesLeaveTheFacetCacheAlone(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "loud")
	settleCatalogFeed(t, f.svc)

	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "loud"}})
	if _, err := f.svc.Facets(f.ctx, uc, FacetQuery{Dimension: "genre", Limit: 500}); err != nil {
		t.Fatalf("restricted enumeration: %v", err)
	}
	if servesFromCache(f.svc, "genre") {
		t.Fatal("a restricted caller's enumeration was published to the shared cache")
	}
	// And the unrestricted answer is still the whole library.
	whole := facetsOf(t, f, "genre")
	total := 0
	for _, b := range whole {
		total += b.Count
	}
	if total != 5 {
		t.Fatalf("the unrestricted genre enumeration covers %d items, want 5", total)
	}
}

// facetBucketsFor enumerates a dimension as one particular caller.
func facetBucketsFor(t *testing.T, f genreFixture, uc *UserCtx, dimension string) []FacetBucket {
	t.Helper()
	page, err := f.svc.Facets(f.ctx, uc, FacetQuery{Dimension: dimension, Limit: 500})
	if err != nil {
		t.Fatalf("enumerating %s: %v", dimension, err)
	}
	return page.Buckets
}

// TestUnaddressableAllowKeyKeepsEpisodesAside is the reserved-key trap:
// validatePermissions accepts any key, so an admin can save an allow
// rule on GENRE, which the engine cannot address as a custom tag. The
// per-item filter answers that rule with "nothing allowed" for music
// and books but never consults tags for an episode - so the compiled
// node has to hide every non-episode and still keep the episode arm
// open, or a listing and a detail read disagree about the same episode.
func TestUnaddressableAllowKeyKeepsEpisodesAside(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	uc := f.restricted([]TagRule{{Key: "GENRE"}}, nil)

	page, err := f.svc.Items(f.ctx, uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatalf("listing under a reserved allow key: %v", err)
	}
	if len(page.Items) != 0 {
		t.Errorf("reserved allow key listed %d non-episode items, want 0", len(page.Items))
	}

	// The node itself carries the episode arm even on this fail-closed
	// path; the fixture has no episodes to list, so the shape is the
	// assertion.
	node, ok := f.svc.contentRuleNode(f.ctx, uc).(query.Or)
	if !ok || len(node.Nodes) != 2 {
		t.Fatalf("fail-closed node = %#v, want Or(episode arm, match-nothing)", node)
	}
	arm, ok := node.Nodes[0].(query.Cond)
	if !ok || arm.Field != "kind" || arm.Value != string(model.KindEpisode) {
		t.Errorf("first arm = %#v, want kind is episode", node.Nodes[0])
	}
	if rest, ok := node.Nodes[1].(query.Or); !ok || len(rest.Nodes) != 0 {
		t.Errorf("second arm = %#v, want an empty Or matching nothing", node.Nodes[1])
	}
}
