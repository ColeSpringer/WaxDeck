package providers

import (
	"slices"
	"testing"

	"github.com/colespringer/waxbin/enrich"
)

// The status surface renders capabilities with the tokens a custom
// provider advertises itself with, so every token must read back as the
// bits it names and render back as itself. The artist halves are the one
// overlap: both at once render as artist-art.
func TestCapabilityTokensRoundTrip(t *testing.T) {
	t.Parallel()
	var all enrich.Capability
	names := map[string]bool{}
	for _, v := range capabilityVocab {
		if names[v.name] {
			t.Errorf("%q is listed twice", v.name)
		}
		names[v.name] = true
		all |= v.cap
		if got := parseCapability(v.name); got != v.cap {
			t.Errorf("%q parses to %v, want %v", v.name, got, v.cap)
		}
		if got := CapabilityNames(v.cap); !slices.Equal(got, []string{v.name}) {
			t.Errorf("%q renders as %v", v.name, got)
		}
	}
	want := []string{"identity", "genres", "cover", "lyrics", "book", "aux-art", "artist-art", "fields"}
	if got := CapabilityNames(all); !slices.Equal(got, want) {
		t.Errorf("CapabilityNames = %v, want %v", got, want)
	}
	if parseCapability("telepathy") != 0 {
		t.Error("an unknown token parsed to a capability")
	}
}
