package match

import (
	"fmt"
	"slices"
	"testing"
)

func TestSpreadReleases(t *testing.T) {
	hits := []SearchHit{
		{Title: "Song", Releases: []string{"a1", "a2", "a3"}},
		{Title: "Song", Releases: []string{"a1", "b1"}},
		{Title: "Song", Releases: []string{"c1"}},
	}
	// The lead takes two, each further hit one it does not share, then round
	// robin up to the cap.
	if got, want := SpreadReleases(hits, "", ""), []string{"a1", "a2", "b1", "c1", "a3"}; !slices.Equal(got, want) {
		t.Fatalf("spread = %q, want %q", got, want)
	}
	if got := SpreadReleases(nil, "", ""); len(got) != 0 {
		t.Fatalf("spread of nothing = %q", got)
	}
}

// The search asks for the song alone, so the recording an upload names is
// listed below every plain take: the real page for "Hallelujah" by Jeff
// Buckley lists 38 recordings titled "Hallelujah" before five titled
// "Hallelujah (live)". The spread takes the hits titled as the upload first.
func TestSpreadReleasesTakesTheNamedRecordingFirst(t *testing.T) {
	var hits []SearchHit
	for i := range 38 {
		hits = append(hits, SearchHit{Title: "Hallelujah", Releases: []string{fmt.Sprintf("plain-%d-a", i), fmt.Sprintf("plain-%d-b", i)}})
	}
	hits = append(hits,
		SearchHit{Title: "Hallelujah (live)", Releases: []string{"live-1-a", "live-1-b"}},
		SearchHit{Title: "Hallelujah (live)", Releases: []string{"live-2-a"}},
		SearchHit{Title: "Hallelujah (radio edit)", Releases: []string{"edit-a"}},
	)
	plain := []string{"plain-0-a", "plain-0-b", "plain-1-a", "plain-2-a", "plain-3-a"}
	for _, c := range []struct {
		name, named string
		want        []string
	}{
		{"the named recordings lead", "Hallelujah (Live)", []string{"live-1-a", "live-1-b", "live-2-a", "plain-0-a", "plain-1-a"}},
		{"no name keeps the search order", "", plain},
		{"a name nothing is titled as keeps the search order", "Hallelujah (Live at Sin-\u00e9)", plain},
	} {
		if got := SpreadReleases(hits, c.named, ""); !slices.Equal(got, c.want) {
			t.Errorf("%s: spread = %q, want %q", c.name, got, c.want)
		}
	}
}

// A unit naming an album gets the releases titled as it first, one of each
// hit carrying one, wherever the hit sits on the page; then the spread as it
// was. An edition note on either side is the same album.
func TestSpreadReleasesTakesTheNamedAlbumFirst(t *testing.T) {
	hits := []SearchHit{
		{Title: "Song", Releases: []string{"album", "single"}, Albums: map[string]string{
			AlbumKey("Album"): "album", AlbumKey("Song"): "single", AlbumKey("Big Hits"): "comp-1", AlbumKey("Summer Mix"): "mix",
		}},
		{Title: "Song", Releases: []string{"live"}, Albums: map[string]string{AlbumKey("Live at X"): "live"}},
	}
	for i := range 20 {
		hits = append(hits, SearchHit{Title: "Song", Releases: []string{fmt.Sprintf("take-%d", i)}})
	}
	hits = append(hits, SearchHit{Title: "Song", Releases: []string{"session"}, Albums: map[string]string{
		AlbumKey("Sessions"): "session", AlbumKey("Big Hits (Deluxe Edition)"): "comp-2",
	}})
	plain := []string{"album", "single", "live", "take-0", "take-1"}
	for _, c := range []struct {
		name, album string
		want        []string
	}{
		{"a compilation the lead ranks last", "Big Hits", []string{"comp-1", "comp-2", "album", "single", "live"}},
		{"an edition note on the file's side", "Summer Mix (Remastered)", []string{"mix", "album", "single", "live", "take-0"}},
		{"the album the spread takes anyway", "Album", plain},
		{"an album nothing is titled as", "Elsewhere", plain},
		{"no album", "", plain},
	} {
		if got := SpreadReleases(hits, "", c.album); !slices.Equal(got, c.want) {
			t.Errorf("%s: spread = %q, want %q", c.name, got, c.want)
		}
	}
}
