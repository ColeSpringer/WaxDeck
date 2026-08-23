package service

import (
	"testing"

	waxart "github.com/colespringer/waxbin/art"
)

// Every size this server asks for has to be a rung of the catalog's
// ladder. The constants are numbers - they have to be, since the layers
// that use them may not import waxbin - so this is the only thing that
// notices when the ladder moves underneath them.
func TestArtSizesAreLadderRungs(t *testing.T) {
	for _, tc := range []struct {
		name string
		size int
	}{
		{"cast", ArtSizeCast},
		{"share", ArtSizeShare},
		{"mosaic", ArtSizeMosaic},
		{"tool cover", ArtSizeToolCover},
		{"max", ArtSizeMax},
	} {
		if !ArtSizeOnLadder(tc.size) {
			t.Errorf("%s size %d is not a rung; ladder is %v", tc.name, tc.size, waxart.Rungs())
		}
	}
}

// The accepted ceiling is the ladder's own top: a request above it is
// asking for an enlargement, which the resolver will not do, and one
// below it would leave rungs nothing can reach.
func TestArtSizeMaxIsTheTopRung(t *testing.T) {
	rungs := waxart.Rungs()
	top := rungs[len(rungs)-1]
	if ArtSizeMax != top {
		t.Errorf("ArtSizeMax = %d, top rung = %d", ArtSizeMax, top)
	}
}
