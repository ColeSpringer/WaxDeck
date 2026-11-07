// Package linttest runs a lint command's analyzer over the calling test's
// testdata. It is apart from lintsrc so the lint binaries never link
// testing or analysistest.
package linttest

import (
	"fmt"
	"path/filepath"
	"slices"
	"testing"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/analysistest"
)

// recorder is an analysistest.Testing that keeps what Run reports.
type recorder []string

func (r *recorder) Errorf(format string, args ...any) { *r = append(*r, fmt.Sprintf(format, args...)) }

// Diagnostics is every diagnostic a reports on pkg, as file:line: message,
// once each. analysistest reads no `// want` in a file the build leaves
// out and calls a diagnostic there unexpected, so what Run reports is set
// aside and the caller compares these instead.
func Diagnostics(t *testing.T, a *analysis.Analyzer, pkg string) []string {
	t.Helper()
	var reported recorder
	results := analysistest.Run(&reported, analysistest.TestData(), a, pkg)
	if len(results) == 0 {
		t.Fatalf("%s did not load: %q", pkg, reported)
	}
	var out []string
	for _, r := range results {
		if r.Action.Err != nil {
			t.Fatalf("analyzing %s: %v", pkg, r.Action.Err)
		}
		for _, d := range r.Action.Diagnostics {
			posn := r.Action.Package.Fset.Position(d.Pos)
			out = append(out, fmt.Sprintf("%s:%d: %s", filepath.Base(posn.Filename), posn.Line, d.Message))
		}
	}
	slices.Sort(out)
	return slices.Compact(out)
}
