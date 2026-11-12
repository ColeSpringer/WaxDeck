package service

import (
	"testing"
	"time"
)

// A search says which artist or album carries the query as its own name,
// ignoring case, and only those: a name that merely starts with it or
// holds it is a hit but not the one, and a track, book or episode never
// is.
func TestSearchMarksOnlyAnArtistOrAlbumNamedAsTheQuery(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := spellingLibrary(t,
		spellingTrack("river", 1*time.Second, map[string]string{
			"TITLE": "Moon River", "ARTIST": "Moon", "ALBUM": "Moon Songs"}),
		spellingTrack("beam", 2*time.Second, map[string]string{
			"TITLE": "Moonbeam", "ARTIST": "Moonlight Band", "ALBUM": "Moon"}),
		spellingTrack("sunrise", 3*time.Second, map[string]string{
			"TITLE": "Sunrise", "ARTIST": "Dawn Chorus", "ALBUM": "Daybreak"}),
	)
	exact := func(hits []SearchHit) map[string]bool {
		out := make(map[string]bool, len(hits))
		for _, h := range hits {
			out[h.Title] = h.Exact
		}
		return out
	}
	for _, c := range []struct {
		query          string
		artists, album map[string]bool
	}{
		{"Moon", map[string]bool{"Moon": true, "Moonlight Band": false}, map[string]bool{"Moon": true, "Moon Songs": false}},
		{"moon songs", map[string]bool{"Moon": false}, map[string]bool{"Moon Songs": true}},
		{"Moonlight", map[string]bool{"Moonlight Band": false}, map[string]bool{"Moon": false}},
	} {
		res, err := svc.Reads.Search(ctx, admin, c.query, 10)
		if err != nil {
			t.Fatal(err)
		}
		if got := exact(res.Artists); !sameExactFlags(got, c.artists) {
			t.Errorf("%q: artists = %v, want %v", c.query, got, c.artists)
		}
		if got := exact(res.Albums); !sameExactFlags(got, c.album) {
			t.Errorf("%q: albums = %v, want %v", c.query, got, c.album)
		}
		for _, h := range res.Tracks {
			if h.Exact {
				t.Errorf("%q: track %q is marked exact", c.query, h.Title)
			}
		}
		// The named one leads its group, so a client pinning it has it first.
		for _, group := range [][]SearchHit{res.Artists, res.Albums} {
			for i, h := range group {
				if h.Exact && i != 0 {
					t.Errorf("%q: exact %q at %d, want it first", c.query, h.Title, i)
				}
			}
		}
	}
}

// sameExactFlags reports whether two maps hold the same entries.
func sameExactFlags(a, b map[string]bool) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if w, ok := b[k]; !ok || w != v {
			return false
		}
	}
	return true
}
