package service

import (
	"cmp"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// An item's artist is filed under one key: the stated sort spelling's
// when there is one, else the artist's, else a track's album artist's,
// folded the way titles are. A listing carries it, and read in its order
// the listing shelves artists as a library does.
func TestAListingCarriesTheKeyItsArtistsAreFiledUnder(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := spellingLibrary(t,
		spellingTrack("stripes", 1*time.Second, map[string]string{"TITLE": "One", "ARTIST": "The Stripes", "ALBUM": "Shelf"}),
		spellingTrack("zola", 2*time.Second, map[string]string{"TITLE": "Two", "ARTIST": "Émile Zola", "ALBUM": "Shelf"}),
		spellingTrack("zed", 3*time.Second, map[string]string{
			"TITLE": "Three", "ARTIST": "Zed", "ARTISTSORT": "Aardvark, Z", "ALBUM": "Shelf"}),
		spellingTrack("album", 4*time.Second, map[string]string{
			"TITLE": "Four", "ALBUMARTIST": "The Album Artist", "ALBUM": "Shelf"}),
		spellingTrack("beatles", 5*time.Second, map[string]string{
			"TITLE": "Five", "ARTIST": "The Beatles", "ARTISTSORT": "Beatles, Thé", "ALBUM": "Shelf"}),
	)
	want := map[string]struct{ key, spelling string }{
		"One":   {"stripes", ""},
		"Two":   {"emile zola", ""},
		"Three": {"aardvark, z", "Aardvark, Z"},
		"Four":  {"album artist", ""},
		"Five":  {"beatles, the", "Beatles, Thé"},
	}
	listed := spellingWalk(t, ctx, svc, admin, 50)
	if len(listed) != len(want) {
		t.Fatalf("listed %d items, want %d", len(listed), len(want))
	}
	for _, it := range listed {
		if w := want[it.Title]; it.ArtistSortKey != w.key || it.ArtistSort != w.spelling {
			t.Errorf("%q = artist key %q spelling %q; want %q and %q", it.Title, it.ArtistSortKey, it.ArtistSort, w.key, w.spelling)
		}
	}
	slices.SortFunc(listed, func(a, b ItemSummary) int { return cmp.Compare(a.ArtistSortKey, b.ArtistSortKey) })
	var titles []string
	for _, it := range listed {
		titles = append(titles, it.Title)
	}
	if want := []string{"Three", "Four", "Five", "Two", "One"}; !slices.Equal(titles, want) {
		t.Errorf("in artist key order the listing reads %q, want %q", titles, want)
	}
	for _, it := range listed {
		if it.Title != "Three" {
			continue
		}
		d, err := svc.Reads.Item(ctx, admin, it.PID)
		if err != nil {
			t.Fatal(err)
		}
		if d.ArtistSortKey != "aardvark, z" {
			t.Errorf("detail artist key = %q, want the summary's", d.ArtistSortKey)
		}
	}
}

// The key is the one the catalog stores, not a guess at it. A query of
// symbols alone is answered from the key beside each track's artist, so a
// stated spelling and an album artist reach their track exactly when the
// stored key was made from them.
func TestTheArtistKeyIsTheOneTheCatalogStores(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := spellingLibrary(t,
		spellingTrack("spelled", 1*time.Second, map[string]string{
			"TITLE": "Spelled", "ARTIST": "Quiet One", "ARTISTSORT": "!!!", "ALBUM": "Symbols"}),
		spellingTrack("album", 2*time.Second, map[string]string{
			"TITLE": "Albumed", "ALBUMARTIST": "###", "ALBUM": "Symbols"}),
	)
	keys := map[string]string{"Spelled": "!!!", "Albumed": "###"}
	for _, it := range spellingWalk(t, ctx, svc, admin, 50) {
		if it.ArtistSortKey != keys[it.Title] {
			t.Errorf("%q carries artist key %q, want %q", it.Title, it.ArtistSortKey, keys[it.Title])
		}
	}
	for title, key := range keys {
		res, err := svc.Reads.Search(ctx, admin, key, 10)
		if err != nil {
			t.Fatal(err)
		}
		if len(res.Tracks) != 1 || res.Tracks[0].Title != title {
			t.Errorf("searching for the key %q finds %+v, want the one track %q", key, res.Tracks, title)
		}
	}
}

// A book's artist key is its author's, and a list the catalog orders by
// author comes back in that key's order.
func TestABooksArtistKeyFollowsTheCatalogsAuthorOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, books := spellingLibraryWithBooks(t)
	book := func(name, title, author, spelling string, d time.Duration) fixtures.Spec {
		tags := map[string]string{"TITLE": title, "ARTIST": author, "ALBUMARTIST": author, "ALBUM": title, "TRACKNUMBER": "1"}
		if spelling != "" {
			tags["ARTISTSORT"] = spelling
		}
		return spellingTrack(name, d, tags)
	}
	if _, err := fixtures.Generate(books,
		book("one", "Bk One", "The Quiet Writer", "", 1*time.Second),
		book("two", "Bk Two", "Émile Zola", "", 2*time.Second),
		book("three", "Bk Three", "Ann Author", "Author, Ann", 3*time.Second),
		book("four", "Bk Four", "Zed Zimmer", "", 4*time.Second),
	); err != nil {
		t.Fatal(err)
	}
	spellingScan(t, ctx, svc)
	views, err := svc.lib.Query(ctx, visibleItems().
		Where("kind", query.OpIs, string(model.KindBook)).OrderBy("author_sort", false).Build(), "")
	if err != nil {
		t.Fatal(err)
	}
	var titles, keys []string
	for _, v := range views {
		s := summary(v)
		titles, keys = append(titles, s.Title), append(keys, s.ArtistSortKey)
	}
	if want := []string{"Bk Three", "Bk Two", "Bk One", "Bk Four"}; !slices.Equal(titles, want) {
		t.Fatalf("the catalog's author order is %q, want %q", titles, want)
	}
	if want := []string{"author, ann", "emile zola", "quiet writer", "zed zimmer"}; !slices.Equal(keys, want) {
		t.Errorf("in that order the books carry artist keys %q, want %q", keys, want)
	}
}
