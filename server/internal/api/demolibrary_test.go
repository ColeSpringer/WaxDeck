package api

import (
	"os"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/auth"
)

func TestMain(m *testing.M) {
	// A hundred-odd harnesses each mint an admin (and some tests mint
	// more accounts on top); at production argon2 cost that is seconds
	// of hashing per test under the race detector, and none of these
	// tests are about KDF strength.
	auth.WeakenKDFForTesting()
	os.Exit(m.Run())
}

// generateDemoLibrary fills dir with the demo library: Alpha (flac),
// Bravo (mp3), Charlie (opus), and Delta (vorbis), all titled and
// tagged. Encoding is memoized inside fixtures per spec, so the
// per-harness cost is four file writes.
func generateDemoLibrary(t *testing.T, dir string) {
	t.Helper()
	if _, err := fixtures.Generate(dir, fixtures.DemoLibrary()...); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}
}
