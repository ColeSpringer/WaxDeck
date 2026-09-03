package providers

import (
	"testing"

	"github.com/colespringer/waxbin/enrich"
)

// The token vocabulary is a round trip: the health surface renders a
// provider's capabilities as these names, and a custom provider
// advertises itself with them. A token the write side does not know
// parses to zero and the provider is dropped at startup with a line
// about advertising nothing this build understands - so a name the read
// surface emits and the bridge cannot parse is a provider silently
// refused for saying what it does.
//
// The read side lives in the service package and cannot be imported
// from here (it imports this one), so the check runs the other way:
// every bit this build has a name for on either side is named on both.
func TestBridgeParsesEveryCapabilityBit(t *testing.T) {
	t.Parallel()
	all := []struct {
		name string
		cap  enrich.Capability
	}{
		{"identity", enrich.CapIdentity},
		{"genres", enrich.CapGenres},
		{"cover", enrich.CapCover},
		{"lyrics", enrich.CapLyrics},
		{"book", enrich.CapBookMeta},
		{"aux-art", enrich.CapAuxArt},
		{"artist-art", enrich.CapArtistArt},
	}
	for _, want := range all {
		got, ok := bridgeCapabilities[want.name]
		if !ok {
			t.Errorf("the bridge cannot parse %q; a provider advertising it is dropped at startup", want.name)
			continue
		}
		if got != want.cap {
			t.Errorf("%q parses to %v, want %v", want.name, got, want.cap)
		}
	}
	if len(bridgeCapabilities) != len(all) {
		t.Errorf("the bridge knows %d tokens, this test names %d; add the new one here and to "+
			"capabilityStrings and docs/custom-provider-api/openapi.yaml",
			len(bridgeCapabilities), len(all))
	}
}
