// Command importlint enforces the waxbin ownership boundary. The facade
// belongs to internal/service alone; the other waxbin packages carry
// contract types, so only the service layer, the packages below it that
// speak those types, and the composition root may import them; nothing
// imports the SQLite store. Everything above the service layer (api,
// adapters, auth, events) works on the service's DTOs. Test files are
// exempt; files the host's build leaves out are not.
//
// Run as: go run ./cmd/importlint ./...
package main

import (
	"go/parser"
	"strconv"
	"strings"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/singlechecker"

	"github.com/colespringer/waxdeck/server/cmd/internal/lintsrc"
)

const (
	modulePath = "github.com/colespringer/waxdeck/server"
	facadePath = "github.com/colespringer/waxbin"
	sqlitePath = facadePath + "/store/sqlite"
)

// Importers are module-relative package paths, matched exactly.
var (
	// facadeUsers may import the waxbin facade.
	facadeUsers = map[string]bool{
		"internal/service": true,
	}
	// subpackageUsers may import every waxbin subpackage but store/sqlite.
	// The root builds service.Config.SourceProviders and EnrichmentProviders,
	// which are typed with waxbin/source and waxbin/enrich.
	subpackageUsers = map[string]bool{
		"internal/service":      true,
		"internal/providers":    true,
		"internal/genre":        true,
		"internal/bridge/flow":  true,
		"internal/stubsource":   true,
		"internal/waxtapsource": true,
		"cmd/waxdeck":           true,
	}
)

var analyzer = &analysis.Analyzer{
	Name: "importlint",
	Doc:  "confines waxbin imports to the service layer and the packages below it",
	Run:  run,
}

func main() { singlechecker.Main(analyzer) }

func run(pass *analysis.Pass) (any, error) {
	files, err := lintsrc.Files(pass, parser.ImportsOnly)
	if err != nil {
		return nil, err
	}
	pkg := pass.Pkg.Path()
	for _, file := range files {
		for _, spec := range file.Imports {
			path, err := strconv.Unquote(spec.Path.Value)
			if err != nil {
				continue
			}
			switch {
			case path == sqlitePath || strings.HasPrefix(path, sqlitePath+"/"):
				pass.Reportf(spec.Pos(), "imports waxbin/store/sqlite, which nothing in WaxDeck may import")
			case path == facadePath:
				if !listed(facadeUsers, pkg) {
					pass.Reportf(spec.Pos(), "imports the waxbin facade outside the service layer")
				}
			case strings.HasPrefix(path, facadePath+"/"):
				if !listed(subpackageUsers, pkg) {
					pass.Reportf(spec.Pos(), "imports waxbin above the service layer")
				}
			}
		}
	}
	return nil, nil
}

// listed reports whether pkg, a full import path, is in users. A path
// outside the module is never listed.
func listed(users map[string]bool, pkg string) bool {
	rel, ok := strings.CutPrefix(pkg, modulePath+"/")
	return ok && users[rel]
}
