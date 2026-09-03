package service

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/providers"
)

// The placeholder gate is what keeps a stranger's portrait off every
// compilation: Deezer holds real artist pages under these names, and
// the sweep's match is exact. It lives in the providers package now,
// beside the by-name lookup it guards; the pin stays here because the
// sweep is what would put the wrong face on a library.
func TestArtistArtPlaceholder(t *testing.T) {
	t.Parallel()
	for _, name := range []string{
		"Various Artists", "various  artists", "VA", "Unknown Artist",
		"unknown", "Soundtrack", "Original Soundtrack",
	} {
		if !providers.ArtistNamePlaceholder(name) {
			t.Errorf("ArtistNamePlaceholder(%q) = false, want true", name)
		}
	}
	for _, name := range []string{"Vanessa", "The Unknowns", "Daft Punk"} {
		if providers.ArtistNamePlaceholder(name) {
			t.Errorf("ArtistNamePlaceholder(%q) = true, want false", name)
		}
	}
}
