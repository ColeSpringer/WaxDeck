package providers

import (
	"slices"
	"testing"

	"github.com/colespringer/waxbin/enrich"
)

// The status surface renders capabilities with the tokens a custom
// provider advertises itself with, so every token must read back as the
// bit it names, and no two may share a name or a bit.
func TestCapabilityTokensRoundTrip(t *testing.T) {
	t.Parallel()
	var all enrich.Capability
	names := map[string]bool{}
	for _, v := range capabilityVocab {
		if names[v.name] || all.Has(v.cap) {
			t.Errorf("%q repeats a name or a bit", v.name)
		}
		names[v.name] = true
		all |= v.cap
		if got := parseCapability(v.name); got != v.cap {
			t.Errorf("%q parses to %v, want %v", v.name, got, v.cap)
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
