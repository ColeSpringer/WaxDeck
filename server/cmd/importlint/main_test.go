package main

import (
	"slices"
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc/linttest"
)

const module = "github.com/colespringer/waxdeck/server/"

func TestImportBoundary(t *testing.T) {
	for _, tc := range []struct{ name, pkg string }{
		{"facade outside the service layer", "forbidden/facade"},
		{"subpackage outside the allowlist", "forbidden/model"},
		{"store/sqlite outside the module", "forbidden/sqlite"},
		{"package below store/sqlite", "forbidden/sqlitedriver"},
		{"test files are exempt", "forbidden/intest"},
		{"allowlisted package: subpackage passes, facade reports", module + "internal/providers"},
		{"service: facade and subpackage pass, store/sqlite reports", module + "internal/service"},
		{"unlisted package inside the module", module + "internal/api"},
		{"composition root: source and enrich pass, another subpackage, the facade and store/sqlite report", module + "cmd/waxdeck"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			analysistest.Run(t, analysistest.TestData(), analyzer, tc.pkg)
		})
	}
}

// A file the host's build leaves out is held to the same rules, a test
// file again exempt and a file that is not Go never read as Go.
func TestBuildConstrainedFilesAreChecked(t *testing.T) {
	for _, tc := range []struct {
		name, pkg string
		want      []string
	}{
		{"unlisted package", "forbidden/constrained", []string{
			"elsewhere.go:5: imports the waxbin facade outside the service layer",
			"tagged.go:5: imports waxbin above the service layer",
		}},
		{"allowlisted package", module + "internal/genre", []string{
			"elsewhere.go:6: imports the waxbin facade outside the service layer",
			"elsewhere.go:8: imports waxbin/store/sqlite, which nothing in WaxDeck may import",
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := linttest.Diagnostics(t, analyzer, tc.pkg); !slices.Equal(got, tc.want) {
				t.Errorf("diagnostics = %q, want %q", got, tc.want)
			}
		})
	}
}
