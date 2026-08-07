package service

import (
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin/query"
)

// The console's per-library count and a library-scoped item query are two
// spellings of one question, and the count moved from a path prefix to the
// catalog's library dimension. Pin that they still agree.
func TestLibraryItemCountAgreesWithALibraryScopedQuery(t *testing.T) {
	ctx, svc, _ := newCatalogFixture(t)

	libs, err := svc.LibrariesWithCounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 1 {
		t.Fatalf("libraries = %d, want the one fixture root", len(libs))
	}
	if libs[0].ItemCount != 4 {
		t.Errorf("console count = %d, want the 4 scanned tracks", libs[0].ItemCount)
	}

	_, bare, ok := parseAPIPID(libs[0].PID)
	if !ok {
		t.Fatalf("library pid %q does not parse", libs[0].PID)
	}
	q := query.New(query.EntityItems).Where("library", query.OpIs, string(bare)).Build()
	n, err := svc.lib.Count(ctx, q, "")
	if err != nil {
		t.Fatal(err)
	}
	if int64(n) != libs[0].ItemCount {
		t.Errorf("library-scoped query = %d, console count = %d", n, libs[0].ItemCount)
	}

	// A pid no library holds counts nothing rather than everything: the
	// scope is a filter, not a default.
	q = query.New(query.EntityItems).Where("library", query.OpIs, "01ARZ3NDEKTSV4RRFFQ69G5FAV").Build()
	if n, err = svc.lib.Count(ctx, q, ""); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Errorf("unknown library counts %d items, want 0", n)
	}
}

func TestMatchDir(t *testing.T) {
	sep := string(filepath.Separator)
	dirs := []libraryDir{
		// Longest first, as attribution sorts them; the sibling with the
		// shared name prefix is the classic false-match trap.
		{path: filepath.Clean("/media/music-hd") + sep, pid: "hd"},
		{path: filepath.Clean("/media/music") + sep, pid: "music"},
	}
	cases := []struct {
		path string
		want string
	}{
		{"/media/music/a.flac", "music"},
		{"/media/music/deep/nested/b.flac", "music"},
		{"/media/music-hd/a.flac", "hd"},
		// The root directory itself attributes (Clean strips its
		// trailing separator, which a bare prefix check would miss).
		{"/media/music", "music"},
		{"/media/music/", "music"},
		{"/media/music-hd", "hd"},
		// A sibling sharing the name prefix never leaks across.
		{"/media/music-hd2/a.flac", ""},
		{"/media/musical/a.flac", ""},
		{"/media/other/a.flac", ""},
		{"/elsewhere.flac", ""},
	}
	for _, c := range cases {
		if got := matchDir(dirs, c.path); got != c.want {
			t.Errorf("matchDir(%q) = %q, want %q", c.path, got, c.want)
		}
	}
}

func TestTruncateUTF8(t *testing.T) {
	cases := []struct {
		in   string
		max  int
		want string
	}{
		{"short", 60, "short"},
		{"exact!", 6, "exact!"},
		{"abcdefgh", 4, "abcd"},
		// A multi-byte rune straddling the cut is dropped whole, never
		// split into invalid bytes.
		{"abécd", 3, "ab"},
		{"日本語", 4, "日"},
		{"日本語", 6, "日本"},
	}
	for _, c := range cases {
		if got := truncateUTF8(c.in, c.max); got != c.want {
			t.Errorf("truncateUTF8(%q, %d) = %q, want %q", c.in, c.max, got, c.want)
		}
	}
}
