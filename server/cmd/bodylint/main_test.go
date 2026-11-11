package main

import (
	"slices"
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc/linttest"
)

func TestBodyBounds(t *testing.T) {
	for _, tc := range []struct{ name, pkg string }{
		{"both reported under any import name, another type's method and test files exempt", "bound"},
		{"internal/bodylimit exempt", sanctioned},
	} {
		t.Run(tc.name, func(t *testing.T) {
			analysistest.Run(t, analysistest.TestData(), analyzer, tc.pkg)
		})
	}
}

// A call in a file the host's build leaves out is reported, under the
// name that file imports net/http by, a test file's again exempt.
func TestBuildConstrainedFilesAreChecked(t *testing.T) {
	want := []string{
		"elsewhere.go:11: http.MaxBytesReader: bound a request body with bodylimit.Reader, which gives the limit the server's own writer",
		"elsewhere.go:12: http.MaxBytesHandler: bound a request body with bodylimit.Reader, which gives the limit the server's own writer",
	}
	if got := linttest.Diagnostics(t, analyzer, "constrained"); !slices.Equal(got, want) {
		t.Errorf("diagnostics = %q, want %q", got, want)
	}
}
