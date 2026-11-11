// Command bodylint forbids http.MaxBytesReader and http.MaxBytesHandler
// outside internal/bodylimit. MaxBytesReader tells the server a body ran
// past its limit only through the writer net/http itself made, and every
// handler here holds a writer that wraps that one: handed a wrapper, the
// read still fails at the limit, but the server reads a further 256 KB of
// the refused body before it sends the refusal. bodylimit.Reader finds
// the server's own writer first, so it is the one way to bound a body;
// MaxBytesHandler calls MaxBytesReader with whatever writer it is given.
// Test files are exempt; files the host's build leaves out are not.
//
// Run as: go run ./cmd/bodylint ./...
package main

import (
	"go/ast"
	"go/parser"
	"path"
	"strconv"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/singlechecker"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc"
)

var analyzer = &analysis.Analyzer{
	Name: "bodylint",
	Doc:  "forbids http.MaxBytesReader and http.MaxBytesHandler outside internal/bodylimit (use bodylimit.Reader)",
	Run:  run,
}

func main() { singlechecker.Main(analyzer) }

// sanctioned is the one package that may call them.
const sanctioned = "github.com/colespringer/waxdeck/server/internal/bodylimit"

const netHTTP = "net/http"

func run(pass *analysis.Pass) (any, error) {
	if pass.Pkg.Path() == sanctioned {
		return nil, nil
	}
	files, err := lintsrc.Files(pass, parser.SkipObjectResolution)
	if err != nil {
		return nil, err
	}
	for _, file := range files {
		names := importNames(file, netHTTP)
		ast.Inspect(file, func(n ast.Node) bool {
			sel, ok := n.(*ast.SelectorExpr)
			if !ok || (sel.Sel.Name != "MaxBytesReader" && sel.Sel.Name != "MaxBytesHandler") {
				return true
			}
			if fromNetHTTP(pass, sel, names) {
				pass.Reportf(sel.Pos(), "http.%s: bound a request body with bodylimit.Reader, which gives the limit the server's own writer", sel.Sel.Name)
			}
			return true
		})
	}
	return nil, nil
}

// fromNetHTTP reports whether sel names net/http's function: by its type
// where the file has types, and by the name net/http is imported under in
// a file the host's build leaves out, which has none.
func fromNetHTTP(pass *analysis.Pass, sel *ast.SelectorExpr, names map[string]bool) bool {
	if obj := pass.TypesInfo.Uses[sel.Sel]; obj != nil {
		return obj.Pkg() != nil && obj.Pkg().Path() == netHTTP
	}
	x, ok := sel.X.(*ast.Ident)
	return ok && names[x.Name]
}

// importNames is the names file imports pkg under.
func importNames(file *ast.File, pkg string) map[string]bool {
	names := map[string]bool{}
	for _, spec := range file.Imports {
		if p, err := strconv.Unquote(spec.Path.Value); err != nil || p != pkg {
			continue
		}
		if spec.Name != nil {
			names[spec.Name.Name] = true
		} else {
			names[path.Base(pkg)] = true
		}
	}
	return names
}
