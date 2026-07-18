package subsonic

import "testing"

// Untagged tracks group under the unknown buckets; every album lookup
// must apply the same defaults, or a song response loses the album and
// artist linkage its browse responses carry.
func TestUnknownTagAlbumLinkage(t *testing.T) {
	rows := []track{
		{PID: "tr-1", Title: "Tagged", Artist: "Artist", AlbumArtist: "Artist", Album: "Album"},
		{PID: "tr-2", Title: "Untagged"},
	}
	idx := buildIndex(rows)
	for _, tr := range rows {
		if idx.albumByKey[albumKeyForTrack(tr)] == nil {
			t.Fatalf("track %s: albumKeyForTrack misses the album it grouped under", tr.PID)
		}
	}
	if idx.albumByKey[albumKey("", "")] != nil {
		t.Fatal("an album grouped under raw empty tags instead of the unknown buckets")
	}
	al := idx.albumByKey[albumKeyForTrack(rows[1])]
	if al.artist != unknownArtist || al.name != unknownAlbum {
		t.Fatalf("untagged album = %q / %q, want the unknown buckets", al.artist, al.name)
	}
}

// Artist ordering groups by index section ("#" first) and folds case
// inside one. A byte-order sort runs A to Z twice (uppercase initials,
// then lowercase), and a plain folded sort still splits "#" (symbols
// past 'z'), either way emitting duplicate getArtists index sections.
func TestArtistIndexFoldsCase(t *testing.T) {
	rows := []track{
		{PID: "tr-1", AlbumArtist: "alpha ensemble", Album: "One"},
		{PID: "tr-2", AlbumArtist: "Beta Band", Album: "Two"},
		{PID: "tr-3", AlbumArtist: "Ann", Album: "Three"},
		{PID: "tr-4", AlbumArtist: "beta quartet", Album: "Four"},
		{PID: "tr-5", AlbumArtist: "~exotic", Album: "Five"},
		{PID: "tr-6", AlbumArtist: "9th Symphony", Album: "Six"},
	}
	idx := buildIndex(rows)
	want := []string{"9th Symphony", "~exotic", "alpha ensemble", "Ann", "Beta Band", "beta quartet"}
	if len(idx.artists) != len(want) {
		t.Fatalf("artists = %d, want %d", len(idx.artists), len(want))
	}
	for i, a := range idx.artists {
		if a.name != want[i] {
			t.Fatalf("artist order[%d] = %q, want %q", i, a.name, want[i])
		}
	}
	// Each index letter forms exactly one contiguous run.
	seen := map[string]bool{}
	last := ""
	for _, a := range idx.artists {
		letter := indexLetter(a.name)
		if letter != last && seen[letter] {
			t.Fatalf("index letter %q appears in two separate runs", letter)
		}
		seen[letter] = true
		last = letter
	}
}
