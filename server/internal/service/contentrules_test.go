package service

import (
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
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
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), key, values, MetadataEditParams{Lock: false, Force: false}); err != nil {
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

// genreFixtureTitles are every track of the genre fixture, one album
// ("Folded") by one artist ("Vocabulary Test").
var genreFixtureTitles = []string{"Lowercase", "Synonym", "Run Together", "Canonical", "Off Tree"}

// calmDenied is a caller whose only narrowing is a MOOD=calm deny.
func (f genreFixture) calmDenied() *UserCtx {
	return f.restricted(nil, []TagRule{{Key: "MOOD", Value: "calm"}})
}

// tagAllCalm tags every track calm, so a calm-deny caller sees none of
// the fixture's album or artist.
func (f genreFixture) tagAllCalm(t *testing.T) {
	t.Helper()
	for _, title := range genreFixtureTitles {
		f.tag(t, title, "MOOD", "calm")
	}
}

// Search gates entity hits on content rules as well as grants: an album
// or artist whose every track a tag rule denies is no hit.
func TestRestrictedSearchOmitsAnEntityWhoseTracksAreAllDenied(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()

	f.tag(t, "Canonical", "MOOD", "calm")
	res, err := f.svc.Search(f.ctx, kid, "Folded", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Albums) != 1 {
		t.Fatalf("an album with one denied track of five: %d album hits, want 1", len(res.Albums))
	}

	f.tagAllCalm(t)
	if res, err = f.svc.Search(f.ctx, kid, "Folded", 10); err != nil {
		t.Fatal(err)
	}
	if len(res.Albums) != 0 {
		t.Errorf("a fully denied album is still a hit: %+v", res.Albums)
	}
	if res, err = f.svc.Search(f.ctx, kid, "Vocabulary Test", 10); err != nil {
		t.Fatal(err)
	}
	if len(res.Artists) != 0 {
		t.Errorf("a fully denied artist is still a hit: %+v", res.Artists)
	}
	if res, err = f.svc.Search(f.ctx, f.uc, "Folded", 10); err != nil || len(res.Albums) != 1 {
		t.Errorf("the unrestricted caller's search = %+v (%v), want the album", res.Albums, err)
	}
}

func TestAlbumDetailForADeniedAlbumIsNotFound(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()
	album := apiPID(PrefixAlbum, f.itemNamed(t, "Canonical").AlbumPID)

	f.tag(t, "Canonical", "MOOD", "calm")
	if _, err := f.svc.Album(f.ctx, kid, album); err != nil {
		t.Fatalf("a partly denied album: %v, want it readable", err)
	}
	f.tagAllCalm(t)
	if _, err := f.svc.Album(f.ctx, kid, album); KindOf(err) != KindNotFound {
		t.Errorf("a fully denied album = %v, want not-found", err)
	}
}

// TestAlbumCountIsWithheldFromAContentRestrictedCaller: the counts are
// the catalog's, so a caller a tag rule narrows must not read them.
func TestAlbumCountIsWithheldFromAContentRestrictedCaller(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()
	album := apiPID(PrefixAlbum, f.itemNamed(t, "Canonical").AlbumPID)
	f.tag(t, "Canonical", "MOOD", "calm")

	theirs, err := f.svc.Album(f.ctx, kid, album)
	if err != nil {
		t.Fatal(err)
	}
	if theirs.ItemCount != 0 || theirs.TotalDurationMS != 0 {
		t.Errorf("restricted album detail counts %d tracks, %d ms; want them withheld", theirs.ItemCount, theirs.TotalDurationMS)
	}
	mine, err := f.svc.Album(f.ctx, f.uc, album)
	if err != nil {
		t.Fatal(err)
	}
	if mine.ItemCount != 5 {
		t.Errorf("unrestricted album detail counts %d tracks, want 5", mine.ItemCount)
	}

	cards, _, err := f.svc.EntityCards(f.ctx, kid, []string{album})
	if err != nil {
		t.Fatal(err)
	}
	if len(cards) != 1 || cards[0].ItemCount != nil {
		t.Errorf("restricted card = %+v, want one card with no count", cards)
	}
}

func TestEntityCardsDropAFullyDeniedAlbum(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()
	album := apiPID(PrefixAlbum, f.itemNamed(t, "Canonical").AlbumPID)
	f.tagAllCalm(t)

	cards, departed, err := f.svc.EntityCards(f.ctx, kid, []string{album})
	if err != nil {
		t.Fatal(err)
	}
	if len(cards) != 0 {
		t.Errorf("restricted cards = %+v, want the fully denied album dropped", cards)
	}
	if len(departed) != 0 {
		t.Errorf("departed = %v, want none: the album exists, the caller just cannot see it", departed)
	}
	if cards, _, err := f.svc.EntityCards(f.ctx, f.uc, []string{album}); err != nil || len(cards) != 1 {
		t.Errorf("unrestricted cards = %+v (%v), want the album", cards, err)
	}
}

// A kids-mode account cannot share an album none of whose tracks it may
// hear.
func TestAlbumShareRefusedWhenEveryTrackIsDenied(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()
	album := apiPID(PrefixAlbum, f.itemNamed(t, "Canonical").AlbumPID)

	f.tag(t, "Canonical", "MOOD", "calm")
	if _, err := f.svc.CreateShare(f.ctx, kid, album, 0, false, 0); err != nil {
		t.Fatalf("sharing a partly denied album: %v, want it allowed", err)
	}
	f.tagAllCalm(t)
	if _, err := f.svc.CreateShare(f.ctx, kid, album, 0, false, 0); KindOf(err) != KindNotFound {
		t.Errorf("sharing a fully denied album = %v, want not-found", err)
	}
}

// The server recap ranks only what its reader can see: its top tracks,
// artists and genres name nothing the reader's libraries or rules hide,
// whatever other accounts heard.
func TestServerYearInReviewRanksOnlyWhatTheCallerCanSee(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	started := time.Now().Add(-time.Hour)
	var rows []wdb.ListenSession
	for i, title := range []string{"Canonical", "Lowercase"} {
		rows = append(rows, wdb.ListenSession{
			UserID: f.uc.ID, SessionID: fmt.Sprintf("recap-%d", i),
			ItemPID: string(f.itemNamed(t, title).PID), MediaType: "music",
			StartedAt: started, MsPlayed: int64(60000 * (2 - i)),
		})
	}
	if _, err := f.svc.db.InsertListens(f.ctx, rows); err != nil {
		t.Fatal(err)
	}
	titles := func(uc *UserCtx) []string {
		t.Helper()
		recap, err := f.svc.ServerWideYearInReview(f.ctx, uc, started.Year())
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, e := range recap.TopTracks {
			out = append(out, e.Name)
		}
		return out
	}
	if got := titles(f.uc); !slices.Equal(got, []string{"Canonical", "Lowercase"}) {
		t.Fatalf("unrestricted top tracks = %v", got)
	}
	if got := titles(f.calmDenied()); !slices.Equal(got, []string{"Lowercase"}) {
		t.Errorf("restricted top tracks = %v, want the denied track left out", got)
	}
}

// A reader's recap leaves out only what their libraries or rules hide:
// a track in the trash, or one gone from the catalog, ranks for them
// exactly as it does for a reader who sees everything.
func TestServerYearInReviewHidesOnlyWhatTheReaderCannotSee(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	started := time.Now().Add(-time.Hour)
	trashed := f.itemNamed(t, "Lowercase")
	var rows []wdb.ListenSession
	for i, pid := range []string{string(trashed.PID), "01JZZZZZZZZZZZZZZZZZZZZZZZ"} {
		rows = append(rows, wdb.ListenSession{
			UserID: f.uc.ID, SessionID: fmt.Sprintf("kept-%d", i),
			ItemPID: pid, MediaType: "music",
			StartedAt: started, MsPlayed: int64(60000 * (2 - i)),
		})
	}
	if _, err := f.svc.db.InsertListens(f.ctx, rows); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.DeleteItems(f.ctx, f.uc, []string{itemAPIPID(trashed)}, "trash", false); err != nil {
		t.Fatal(err)
	}
	ranked := func(uc *UserCtx) []TopEntry {
		t.Helper()
		recap, err := f.svc.ServerWideYearInReview(f.ctx, uc, started.Year())
		if err != nil {
			t.Fatal(err)
		}
		return recap.TopTracks
	}
	all, restricted := ranked(f.uc), ranked(f.calmDenied())
	if len(all) != 2 || !slices.Equal(all, restricted) {
		t.Errorf("restricted top tracks = %+v, want the unrestricted %+v", restricted, all)
	}
}

// The explicit toggle hides podcast episodes and nothing else, so an
// account of every library with it off reads an album's counts like
// one with it on.
func TestExplicitToggleLeavesAlbumCountsAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	page, err := svc.Items(ctx, admin, ItemFilter{}, "", 10)
	if err != nil || len(page.Items) == 0 {
		t.Fatalf("items = %v, %v", page.Items, err)
	}
	album := page.Items[0].AlbumPID
	read := func(explicit bool) AlbumDetail {
		t.Helper()
		uc := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true, Explicit: explicit}
		out, err := svc.Album(ctx, uc, album)
		if err != nil {
			t.Fatal(err)
		}
		return out
	}
	on, off := read(true), read(false)
	if on.ItemCount == 0 || off.ItemCount != on.ItemCount || off.TotalDurationMS != on.TotalDurationMS {
		t.Errorf("album counts with explicit off = %d/%d ms, with it on %d/%d ms",
			off.ItemCount, off.TotalDurationMS, on.ItemCount, on.TotalDurationMS)
	}
}

// A caller granted more libraries than the engine takes in one
// membership test still gets answers: the entity gates chunk the grant
// the way the playlist narrowing does.
func TestEntityGatesTakeMoreThanFiveHundredGrants(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	libs, err := svc.Libraries(ctx)
	if err != nil || len(libs) == 0 {
		t.Fatalf("libraries = %v, %v", libs, err)
	}
	grants := map[string]bool{strings.TrimPrefix(libs[0].PID, PrefixLibrary+"-"): true}
	for i := range 500 {
		grants[fmt.Sprintf("01NOSUCHLIBRARY%011d", i)] = true
	}
	wide := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, Libraries: grants}
	page, err := svc.Items(ctx, admin, ItemFilter{}, "", 10)
	if err != nil || len(page.Items) == 0 {
		t.Fatalf("items = %v, %v", page.Items, err)
	}
	album := page.Items[0].AlbumPID
	if _, err := svc.Album(ctx, wide, album); err != nil {
		t.Errorf("album detail for a caller with 501 grants: %v", err)
	}
}

// An entity kind the visibility table does not know is an error, never
// an answer: a nil set reads as "nothing filtered" to the card and star
// surfaces and as "nothing visible" to search, so a kind added to one
// table and not the other must fail loudly rather than open one of them.
func TestVisibleEntitiesRefusesAnUnknownKind(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	kid := f.calmDenied()
	if vis, err := f.svc.visibleEntities(f.ctx, kid, "zz", []model.PID{"x"}); err == nil {
		t.Errorf("an unknown entity kind = %v, nil; want an error", vis)
	}
	if vis, err := f.svc.visibleEntities(f.ctx, kid, PrefixAlbum, nil); err != nil || vis == nil {
		t.Errorf("an empty batch = %v, %v; want an empty set", vis, err)
	}
}
