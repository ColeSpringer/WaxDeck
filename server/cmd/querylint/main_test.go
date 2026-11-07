package main

import (
	"fmt"
	"slices"
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc/linttest"
)

// The service's bare item and track queries report wherever they stand,
// in a file the host's build leaves out too; an allowlisted function, the
// helpers' own file and test files are exempt, and other entities pass.
func TestBareQueries(t *testing.T) {
	bare := func(at, where string) string {
		return fmt.Sprintf("%s: bare item/track query in %s: build it with visibleItems or visibleTracks so a trashed item stays out of the listing, or add %s to querylint's allowlist with a reason", at, where, where)
	}
	want := []string{
		bare("elsewhere.go:8", "elsewhere"),
		bare("reads.go:5", "a package-level declaration"),
		bare("reads.go:8", "listing"),
	}
	if got := linttest.Diagnostics(t, analyzer, guardedPackage); !slices.Equal(got, want) {
		t.Errorf("diagnostics = %q,\nwant %q", got, want)
	}
}

func TestOnlyTheServiceIsGuarded(t *testing.T) {
	analysistest.Run(t, analysistest.TestData(), analyzer, "outside")
}
