package service

import (
	"path/filepath"
	"testing"
)

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
