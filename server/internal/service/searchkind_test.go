package service

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// kindsLibrary holds a musician with two tracks (Alder Ames), an author
// with two books (Bertha Quill), and a person with one of each (Cora
// Both), tracks in the music root and books in the audiobook root. It
// returns the books library's bare pid for grant tests.
func kindsLibrary(t *testing.T) (context.Context, *Library, *UserCtx, string) {
	t.Helper()
	ctx, svc, admin, music, books := spellingLibraryWithBooks(t)
	track := func(name, title, artist string, d time.Duration) fixtures.Spec {
		return spellingTrack(name, d, map[string]string{
			"TITLE": title, "ARTIST": artist, "ALBUMARTIST": artist, "ALBUM": title + " LP"})
	}
	book := func(name, title, author string, d time.Duration) fixtures.Spec {
		return spellingTrack(name, d, map[string]string{
			"TITLE": title, "ARTIST": author, "ALBUMARTIST": author, "ALBUM": title, "TRACKNUMBER": "1"})
	}
	if _, err := fixtures.Generate(music,
		track("anvil", "Anvil Song", "Alder Ames", 1*time.Second),
		track("bellows", "Bellows", "Alder Ames", 2*time.Second),
		track("chorus", "Chorale", "Cora Both", 3*time.Second),
	); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(books,
		book("tome", "Long Tome", "Bertha Quill", 1*time.Second),
		book("saga", "Short Saga", "Bertha Quill", 2*time.Second),
		book("memoir", "Memoir", "Cora Both", 3*time.Second),
	); err != nil {
		t.Fatal(err)
	}
	spellingScan(t, ctx, svc)
	libs, err := svc.Roots.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if lib.Name == "books" {
			return ctx, svc, admin, strings.TrimPrefix(lib.PID, PrefixLibrary+"-")
		}
	}
	t.Fatalf("no books library in %+v", libs)
	return nil, nil, nil, ""
}

func hitTitles(hits []SearchHit) []string {
	out := make([]string, 0, len(hits))
	for _, h := range hits {
		out = append(out, h.Title)
	}
	return out
}

// Search's artists are people credited on music and its authors people
// credited on books: an author with no tracks is not an artist, a
// musician with no books is not an author, and one with both is both.
func TestSearchKeepsArtistsAndAuthorsApart(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := kindsLibrary(t)
	for _, c := range []struct {
		query            string
		artists, authors []string
	}{
		{"Bertha", nil, []string{"Bertha Quill"}},
		{"Alder", []string{"Alder Ames"}, nil},
		{"Cora", []string{"Cora Both"}, []string{"Cora Both"}},
	} {
		res, err := svc.Reads.Search(ctx, admin, c.query, 10)
		if err != nil {
			t.Fatal(err)
		}
		if got := hitTitles(res.Artists); strings.Join(got, "|") != strings.Join(c.artists, "|") {
			t.Errorf("%q: artists = %v, want %v", c.query, got, c.artists)
		}
		if got := hitTitles(res.Authors); strings.Join(got, "|") != strings.Join(c.authors, "|") {
			t.Errorf("%q: authors = %v, want %v", c.query, got, c.authors)
		}
		for _, h := range res.Authors {
			if h.Kind != "author" || !strings.HasPrefix(h.PID, PrefixArtist+"-") || h.Exact {
				t.Errorf("%q: author hit %+v, want kind author on an artist pid", c.query, h)
			}
		}
		for _, h := range res.Artists {
			if h.Kind != "artist" {
				t.Errorf("%q: artist hit %+v, want kind artist", c.query, h)
			}
		}
	}
	// A whole name is the exact author, as it is the exact artist.
	res, err := svc.Reads.Search(ctx, admin, "Bertha Quill", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Authors) != 1 || !res.Authors[0].Exact {
		t.Errorf("authors for the whole name = %+v, want Bertha Quill marked exact", res.Authors)
	}
}

// A caller granted only the books sees Cora Both as an author and not as
// an artist: her track is outside the grant.
func TestSearchAuthorsFollowTheGrant(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, booksLib := kindsLibrary(t)
	reader := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, Libraries: map[string]bool{booksLib: true}}
	res, err := svc.Reads.Search(ctx, reader, "Cora", 10)
	if err != nil {
		t.Fatal(err)
	}
	if got := hitTitles(res.Artists); len(got) != 0 {
		t.Errorf("artists = %v, want none", got)
	}
	if got := hitTitles(res.Authors); strings.Join(got, "|") != "Cora Both" {
		t.Errorf("authors = %v, want [Cora Both]", got)
	}
}

// kindsItem finds one of the library's items by its title.
func kindsItem(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, title string) ItemSummary {
	t.Helper()
	page, err := svc.Reads.Items(ctx, uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range page.Items {
		if it.Title == title {
			return it
		}
	}
	t.Fatalf("no item titled %q", title)
	return ItemSummary{}
}

// A tag rule that denies a person's track and allows their book leaves
// them an author and not an artist. The catalog's search does not read
// tag rules, so only the track gate keeps them out of Artists.
func TestSearchArtistsFollowTagRules(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := kindsLibrary(t)
	chorale := kindsItem(t, ctx, svc, admin, "Chorale")
	if _, err := svc.Editor.SetItemTag(ctx, admin, chorale.PID, "MOOD", []string{"loud"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	settleCatalogFeed(t, svc)
	reader := &UserCtx{
		ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: "MOOD", Value: "loud"}},
	}
	res, err := svc.Reads.Search(ctx, reader, "Cora", 10)
	if err != nil {
		t.Fatal(err)
	}
	if got := hitTitles(res.Artists); len(got) != 0 {
		t.Errorf("artists = %v, want none: the track is denied", got)
	}
	if got := hitTitles(res.Authors); strings.Join(got, "|") != "Cora Both" {
		t.Errorf("authors = %v, want [Cora Both]", got)
	}
}

// Authors rank by how their names meet the query, as artists do: the
// name that is the query first, then one the query begins a word of,
// then the rest, whatever order their books ranked in.
func TestSearchRanksAuthorsByName(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, books := spellingLibraryWithBooks(t)
	book := func(name, title, author string) fixtures.Spec {
		return spellingTrack(name, time.Second, map[string]string{
			"TITLE": title, "ARTIST": author, "ALBUMARTIST": author, "ALBUM": title, "TRACKNUMBER": "1"})
	}
	// Each title names the query, so the unmatched or partly matched
	// author's book outranks the better-named author's.
	if _, err := fixtures.Generate(books,
		book("garden", "Herbert Herbert Garden", "Zed Zimmer"),
		book("dune", "Dune", "Frank Herbert"),
		book("quills", "Quill Quill Quill", "Bertha Quill"),
		book("ink", "Ink", "Quill"),
	); err != nil {
		t.Fatal(err)
	}
	spellingScan(t, ctx, svc)
	for _, c := range []struct {
		query string
		want  []string
	}{
		{"Herbert", []string{"Frank Herbert", "Zed Zimmer"}},
		{"Quill", []string{"Quill", "Bertha Quill"}},
	} {
		res, err := svc.Reads.Search(ctx, admin, c.query, 10)
		if err != nil {
			t.Fatal(err)
		}
		if got := hitTitles(res.Authors); strings.Join(got, "|") != strings.Join(c.want, "|") {
			t.Errorf("%q: authors = %v, want %v", c.query, got, c.want)
		}
	}
}

// The exact test folds kana as the artist group's does: a hiragana query
// is the katakana name.
func TestSearchNameKeyFoldsKana(t *testing.T) {
	t.Parallel()
	if newSearchName("かな").key != newSearchName("カナ").key {
		t.Fatal("hiragana and katakana spellings key apart")
	}
	if got := searchTier(newSearchName("カナ"), newSearchName("かな")); got != 0 {
		t.Fatalf("tier = %d, want 0", got)
	}
}
