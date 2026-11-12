package service

import (
	"context"
	"maps"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// spellingTrack is a tagged FLAC whose length keeps its audio its own, so no
// two of a test's files read as copies of one item.
func spellingTrack(name string, d time.Duration, tags map[string]string) fixtures.Spec {
	return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: d, Tags: tags}
}

// spellingLibrary opens a library holding the files the specs make and scans
// it, with an administrator to read it as.
func spellingLibrary(t *testing.T, specs ...fixtures.Spec) (context.Context, *Library, *UserCtx) {
	t.Helper()
	var root string
	ctx, svc, admin := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	if _, err := fixtures.Generate(root, specs...); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return ctx, svc, admin
}

// spellingLibraryWithBooks opens a library with a music root and an audiobook
// root, answering both folders.
func spellingLibraryWithBooks(t *testing.T) (ctx context.Context, svc *Library, admin *UserCtx, music, books string) {
	t.Helper()
	books = t.TempDir()
	ctx, svc, admin = openEnrichFixture(t, func(c *Config) {
		music = c.Roots[0].Path
		c.Roots = append(c.Roots, Root{Name: "books", Path: books, Media: "audiobook"})
	})
	return ctx, svc, admin, music, books
}

// spellingScan runs a scan and waits it out.
func spellingScan(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scan)
}

// spellingWalk reads the whole title-sorted listing a page at a time.
func spellingWalk(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, limit int) []ItemSummary {
	t.Helper()
	var out []ItemSummary
	cursor := ""
	for {
		page, err := svc.Reads.Items(ctx, uc, ItemFilter{}, cursor, limit)
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, page.Items...)
		if page.Next == "" {
			return out
		}
		cursor = page.Next
	}
}

// A listing says the key each title is filed under and the artist's sort
// spelling the file states, and the keys run in the order the catalog
// pages the titles in: a client sorting its own copy lands where the
// server would, whatever a bare lowercase would have done to an article,
// an accent or a number.
func TestAListingCarriesTheKeysItsOrderIsMadeOf(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := spellingLibrary(t,
		spellingTrack("zebra", 1*time.Second, map[string]string{
			"TITLE": "The Zebra Song", "ARTIST": "The Stripes", "ARTISTSORT": "Stripes, The", "ALBUM": "Savanna"}),
		spellingTrack("apple", 2*time.Second, map[string]string{"TITLE": "apple tune", "ARTIST": "Zed", "ALBUM": "Savanna"}),
		spellingTrack("eclair", 3*time.Second, map[string]string{"TITLE": "Éclair", "ARTIST": "Zed", "ALBUM": "Savanna"}),
		spellingTrack("ten", 4*time.Second, map[string]string{"TITLE": "Track 10", "ARTIST": "Zed", "ALBUM": "Savanna"}),
		spellingTrack("two", 5*time.Second, map[string]string{"TITLE": "Track 2", "ARTIST": "Zed", "ALBUM": "Savanna"}),
	)
	want := []struct{ title, key, artistSort string }{
		{"apple tune", "apple tune", ""},
		{"Éclair", "eclair", ""},
		{"Track 2", "track 0000000002", ""},
		{"Track 10", "track 0000000010", ""},
		{"The Zebra Song", "zebra song", "Stripes, The"},
	}
	for _, limit := range []int{50, 2} {
		got := spellingWalk(t, ctx, svc, admin, limit)
		if len(got) != len(want) {
			t.Fatalf("limit %d: listed %d items, want %d", limit, len(got), len(want))
		}
		for i, w := range want {
			it := got[i]
			if it.Title != w.title || it.SortKey != w.key || it.ArtistSort != w.artistSort {
				t.Errorf("limit %d, row %d = %q key %q artist sort %q; want %q key %q artist sort %q",
					limit, i, it.Title, it.SortKey, it.ArtistSort, w.title, w.key, w.artistSort)
			}
			if i > 0 && got[i-1].SortKey >= it.SortKey {
				t.Errorf("limit %d: key %q does not follow %q in the catalog's order", limit, it.SortKey, got[i-1].SortKey)
			}
		}
	}
	d, err := svc.Reads.Item(ctx, admin, spellingWalk(t, ctx, svc, admin, 50)[4].PID)
	if err != nil {
		t.Fatal(err)
	}
	if d.SortKey != "zebra song" || d.ArtistSort != "Stripes, The" {
		t.Errorf("detail keys = %q, %q; want the summary's", d.SortKey, d.ArtistSort)
	}
}

// A book's artist sort is its author's sort spelling.
func TestABooksArtistSortIsItsAuthorsSortSpelling(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, books := spellingLibraryWithBooks(t)
	if _, err := fixtures.Generate(books, spellingTrack("tome", 2*time.Second, map[string]string{
		"TITLE": "The Long Tome", "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author",
		"ARTISTSORT": "Author, Ann", "ALBUM": "The Long Tome", "TRACKNUMBER": "1"})); err != nil {
		t.Fatal(err)
	}
	spellingScan(t, ctx, svc)
	items := spellingWalk(t, ctx, svc, admin, 50)
	if len(items) != 1 || items[0].MediaType != "audiobook" {
		t.Fatalf("items = %+v, want the one book", items)
	}
	if b := items[0]; b.ArtistSort != "Author, Ann" || b.SortKey != "long tome" {
		t.Errorf("book = key %q artist sort %q; want %q and its author's %q", b.SortKey, b.ArtistSort, "long tome", "Author, Ann")
	}
}

// An episode carries the key its title is filed under.
func TestAnEpisodeCarriesTheKeyItsTitleIsFiledUnder(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 3, prefix: "The Drift"})
	sub := f.subscribe(t, "https://feeds.example/drift", "rss")
	rows, _, err := f.svc.Podcasts.Episodes(f.ctx, f.uc, sub.Show.PID, "", 10)
	if err != nil || len(rows) != 3 {
		t.Fatalf("episodes = %d (%v), want 3", len(rows), err)
	}
	for _, ep := range rows {
		want := map[string]string{
			"The Drift 000": "drift 0000000000",
			"The Drift 001": "drift 0000000001",
			"The Drift 002": "drift 0000000002",
		}[ep.Title]
		if ep.SortKey != want || ep.ArtistSort != "" {
			t.Errorf("episode %q = key %q artist sort %q; want key %q and no artist sort", ep.Title, ep.SortKey, ep.ArtistSort, want)
		}
	}
}

// A title the lists cut short is still filed whole, so its key is the
// catalog's and not the cut one's.
func TestAnOverlongEpisodeTitleIsShownCutAndFiledWhole(t *testing.T) {
	t.Parallel()
	long := strings.Repeat("a", feedTitleMaxChars)
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 2, prefix: long})
	sub := f.subscribe(t, "https://feeds.example/long", "rss")
	rows, _, err := f.svc.Podcasts.Episodes(f.ctx, f.uc, sub.Show.PID, "", 10)
	if err != nil || len(rows) != 2 {
		t.Fatalf("episodes = %d (%v), want 2", len(rows), err)
	}
	keys := map[string]bool{}
	for _, ep := range rows {
		if n := len([]rune(ep.Title)); n != feedTitleMaxChars {
			t.Errorf("a title is shown at %d characters, want it cut to %d", n, feedTitleMaxChars)
		}
		keys[ep.SortKey] = true
	}
	if want := map[string]bool{long + " 0000000000": true, long + " 0000000001": true}; !maps.Equal(keys, want) {
		t.Errorf("keys differ from the whole titles' (%d keys, want %d)", len(keys), len(want))
	}
}

// A detail carries the totals a file states beside its numbers, a book's
// part count among them, and none for a file stating none.
func TestAnItemDetailCarriesItsTotals(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, music, books := spellingLibraryWithBooks(t)
	if _, err := fixtures.Generate(music,
		spellingTrack("counted", 1*time.Second, map[string]string{
			"TITLE": "Counted", "ARTIST": "Tallies", "ALBUM": "Boxed Set",
			"TRACKNUMBER": "3", "TRACKTOTAL": "12", "DISCNUMBER": "1", "DISCTOTAL": "2"}),
		spellingTrack("loose", 2*time.Second, map[string]string{
			"TITLE": "Loose", "ARTIST": "Tallies", "ALBUM": "Single", "TRACKNUMBER": "1"}),
	); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(books, spellingTrack("tome", 3*time.Second, map[string]string{
		"TITLE": "Parted", "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author", "ALBUM": "Parted",
		"TRACKNUMBER": "1", "TRACKTOTAL": "5"})); err != nil {
		t.Fatal(err)
	}
	spellingScan(t, ctx, svc)
	type totals struct{ track, disc, part, trackNo, discNo int }
	want := map[string]totals{
		"Counted": {track: 12, disc: 2, trackNo: 3, discNo: 1},
		"Loose":   {trackNo: 1},
		"Parted":  {part: 5},
	}
	listed := spellingWalk(t, ctx, svc, admin, 50)
	if len(listed) != len(want) {
		t.Fatalf("listed %d items, want %d", len(listed), len(want))
	}
	for _, it := range listed {
		d, err := svc.Reads.Item(ctx, admin, it.PID)
		if err != nil {
			t.Fatal(err)
		}
		got := totals{d.TrackTotal, d.DiscTotal, d.PartTotal, d.TrackNo, d.DiscNo}
		if got != want[it.Title] {
			t.Errorf("%q = %+v, want %+v", it.Title, got, want[it.Title])
		}
	}
}
