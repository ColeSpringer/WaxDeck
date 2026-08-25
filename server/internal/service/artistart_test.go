package service

import "testing"

// The placeholder gate is what keeps a stranger's portrait off every
// compilation: Deezer holds real artist pages under these names, and
// the sweep's match is exact.
func TestArtistArtPlaceholder(t *testing.T) {
	t.Parallel()
	for _, name := range []string{
		"Various Artists", "various  artists", "VA", "Unknown Artist",
		"unknown", "Soundtrack", "Original Soundtrack",
	} {
		if !artistArtPlaceholder(name) {
			t.Errorf("artistArtPlaceholder(%q) = false, want true", name)
		}
	}
	for _, name := range []string{"Vanessa", "The Unknowns", "Daft Punk"} {
		if artistArtPlaceholder(name) {
			t.Errorf("artistArtPlaceholder(%q) = true, want false", name)
		}
	}
}
