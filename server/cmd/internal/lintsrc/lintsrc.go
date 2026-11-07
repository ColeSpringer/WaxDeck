// Package lintsrc gathers the source files the server's lint commands
// check.
package lintsrc

import (
	"go/ast"
	"go/parser"
	"strings"

	"golang.org/x/tools/go/analysis"
)

// Files is the package's non-test Go files: those the host's build
// compiles, and those it leaves out (another OS, a build tag), which are
// parsed with mode into pass.Fset so a report names their file and line.
// The files left out carry no type information.
func Files(pass *analysis.Pass, mode parser.Mode) ([]*ast.File, error) {
	var files []*ast.File
	for _, file := range pass.Files {
		if !strings.HasSuffix(pass.Fset.Position(file.Pos()).Filename, "_test.go") {
			files = append(files, file)
		}
	}
	for _, name := range pass.IgnoredFiles {
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		src, err := pass.ReadFile(name)
		if err != nil {
			return nil, err
		}
		file, err := parser.ParseFile(pass.Fset, name, src, mode)
		if err != nil {
			return nil, err
		}
		files = append(files, file)
	}
	return files, nil
}
