package main

import (
	"slices"
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc/linttest"
)

func TestSpawns(t *testing.T) {
	for _, tc := range []struct{ name, pkg string }{
		{"go statement and WaitGroup.Go reported, test files exempt", "spawn"},
		{"supervise exempt, its build-constrained files too", "supervise"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			analysistest.Run(t, analysistest.TestData(), analyzer, tc.pkg)
		})
	}
}

// A go statement in a file the host's build leaves out is reported, a
// test file's again exempt.
func TestBuildConstrainedFilesAreChecked(t *testing.T) {
	want := []string{
		"elsewhere.go:6: bare go statement: spawn workers through supervise.Group so panics degrade the subsystem, not the process",
	}
	if got := linttest.Diagnostics(t, analyzer, "constrained"); !slices.Equal(got, want) {
		t.Errorf("diagnostics = %q, want %q", got, want)
	}
}
