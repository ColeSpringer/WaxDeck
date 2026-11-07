// Command spawnlint forbids bare goroutine spawns in server code. One
// process hosts hostile-input parsing beside live audio, and only the
// supervise package's recover boundary keeps a panicking worker from
// taking the process down, so it is the only sanctioned spawn path.
// Both the go statement and sync.WaitGroup.Go are flagged outside it;
// test files are exempt, files the host's build leaves out are not.
//
// Run as: go run ./cmd/spawnlint ./...
package main

import (
	"go/ast"
	"go/parser"
	"go/types"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/singlechecker"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc"
)

var analyzer = &analysis.Analyzer{
	Name: "spawnlint",
	Doc:  "forbids goroutine spawns outside internal/supervise (use supervise.Group)",
	Run:  run,
}

func main() { singlechecker.Main(analyzer) }

func run(pass *analysis.Pass) (any, error) {
	if pass.Pkg.Name() == "supervise" {
		return nil, nil
	}
	// Files the host's build leaves out have no types, so a WaitGroup.Go in one goes unseen.
	files, err := lintsrc.Files(pass, parser.SkipObjectResolution)
	if err != nil {
		return nil, err
	}
	for _, file := range files {
		ast.Inspect(file, func(n ast.Node) bool {
			switch stmt := n.(type) {
			case *ast.GoStmt:
				pass.Reportf(stmt.Pos(), "bare go statement: spawn workers through supervise.Group so panics degrade the subsystem, not the process")
			case *ast.CallExpr:
				if isWaitGroupGo(pass, stmt) {
					pass.Reportf(stmt.Pos(), "sync.WaitGroup.Go spawns an unsupervised goroutine: use supervise.Group")
				}
			}
			return true
		})
	}
	return nil, nil
}

// isWaitGroupGo reports a call to (*sync.WaitGroup).Go.
func isWaitGroupGo(pass *analysis.Pass, call *ast.CallExpr) bool {
	sel, ok := call.Fun.(*ast.SelectorExpr)
	if !ok || sel.Sel.Name != "Go" {
		return false
	}
	tv, ok := pass.TypesInfo.Types[sel.X]
	if !ok {
		return false
	}
	t := tv.Type
	if p, ok := t.(*types.Pointer); ok {
		t = p.Elem()
	}
	named, ok := t.(*types.Named)
	if !ok {
		return false
	}
	obj := named.Obj()
	return obj.Name() == "WaitGroup" && obj.Pkg() != nil && obj.Pkg().Path() == "sync"
}
