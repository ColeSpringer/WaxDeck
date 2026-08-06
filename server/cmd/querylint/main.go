// Command querylint forbids bare item and track queries in the service
// package. ADR-0048 says a listing never offers an archived item, and
// two dozen call sites build one of these queries, so the predicate
// lives in one helper (service.visibleItems / visibleTracks) rather than
// at each of them. A query built with query.New(query.EntityItems) or
// query.New(query.EntityTracks) has skipped the helper and, unless it is
// an audit or a sweep, is a listing that will answer with deleted items.
//
// The allowlist below is the ADR's exception list: surfaces whose job is
// to see everything the catalog holds. Adding to it is a decision, which
// is why it lives here and in the ADR rather than in a comment.
//
// Run as: go run ./cmd/querylint ./...
package main

import (
	"go/ast"
	"go/token"
	"path/filepath"
	"strings"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/singlechecker"
)

var analyzer = &analysis.Analyzer{
	Name: "querylint",
	Doc:  "forbids bare item/track queries outside the visibleItems helpers (ADR-0048)",
	Run:  run,
}

func main() { singlechecker.Main(analyzer) }

// guardedPackage is the only package the rule applies to. Every catalog
// listing is assembled here; the adapters call services rather than the
// facade, so they have no query to build.
const guardedPackage = "github.com/colespringer/waxdeck/server/internal/service"

// helperFile is where the two helpers live, and the one file allowed to
// build these queries without a state predicate.
const helperFile = "itemquery.go"

// allowed lists the functions that legitimately see the whole catalog,
// archived items included, by file and enclosing function. These are
// audits, sweeps, dedupe units, coverage counts, and organize plans:
// surfaces about what the catalog holds rather than about what a
// listener is offered. ADR-0048 carries the same list with the reasons.
var allowed = map[string]map[string]bool{
	"health.go": {
		// The health grade (already narrowed to present items), the
		// lyrics and unofficial-tag sweeps behind it, the organize plan
		// it previews, and the one-item drill a fix runs against.
		"SweepHealth":     true,
		"lyricsPresence":  true,
		"unofficialItems": true,
		"plannedMoves":    true,
		"runHealthFix":    true,
	},
	// The genre normalizer rewrites tags wherever they are.
	"genres.go": {"runGenreNormalize": true},
	// A review unit is every track of an album, including ones already
	// retired, or the unit splits in two.
	"matching.go": {"albumUnit": true},
	// Coverage counts answer "of everything in the catalog, how much is
	// enriched"; filtering would flatter the number.
	"enrichment.go": {"EnrichmentStatusFor": true},
	// Book re-scan and cue-sibling discovery both work on files, and a
	// cue split's whole job is retiring the carvings it finds.
	"tools.go": {"scanToolBookDir": true, "cueSiblings": true},
	// Organize plans move files on disk, not listings.
	"organize.go": {"organizePlanFor": true},
	// The admin library row counts what a root holds.
	"visibility.go": {"libraryItemCount": true},
}

func run(pass *analysis.Pass) (any, error) {
	if pass.Pkg.Path() != guardedPackage {
		return nil, nil
	}
	for _, file := range pass.Files {
		name := filepath.Base(pass.Fset.Position(file.Pos()).Filename)
		if strings.HasSuffix(name, "_test.go") || name == helperFile {
			continue
		}
		// The whole file, not just its FuncDecls. A package-level var can
		// hold a query as easily as a function body can - reads.go
		// already keeps a map of closures at package scope - and walking
		// only the declarations that happen to be functions is precisely
		// the "nine of them get missed and nothing catches it" hole this
		// exists to close.
		ast.Inspect(file, func(n ast.Node) bool {
			if fn, ok := n.(*ast.FuncDecl); ok {
				if allowed[name][fn.Name.Name] {
					// Skipped whole: an allowed function's body is
					// allowed, closures inside it included.
					return false
				}
				return true
			}
			call, ok := n.(*ast.CallExpr)
			if !ok || !isBareItemQuery(call) {
				return true
			}
			where := enclosing(file, call.Pos())
			pass.Reportf(call.Pos(),
				"bare item/track query in %s: build it with visibleItems or visibleTracks so a trashed item stays out of the listing (ADR-0048), or add %s to querylint's allowlist with a reason",
				where, where)
			return true
		})
	}
	return nil, nil
}

// enclosing names the function a position sits in, for the message and
// for the allowlist entry a reader has to write. A query at package
// scope belongs to no function, and says so.
func enclosing(file *ast.File, pos token.Pos) string {
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && fn.Pos() <= pos && pos <= fn.End() {
			return fn.Name.Name
		}
	}
	return "a package-level declaration"
}

// isBareItemQuery reports a call to query.New with EntityItems or
// EntityTracks. Matched syntactically on the qualified names, which is
// enough: query is the package's only import spelled that way, and a
// renamed import would have to be deliberate.
func isBareItemQuery(call *ast.CallExpr) bool {
	if !isSelector(call.Fun, "query", "New") || len(call.Args) != 1 {
		return false
	}
	return isSelector(call.Args[0], "query", "EntityItems") ||
		isSelector(call.Args[0], "query", "EntityTracks")
}

// isSelector reports whether e is the expression pkg.name.
func isSelector(e ast.Expr, pkg, name string) bool {
	sel, ok := e.(*ast.SelectorExpr)
	if !ok || sel.Sel.Name != name {
		return false
	}
	ident, ok := sel.X.(*ast.Ident)
	return ok && ident.Name == pkg
}
