// Command importlint enforces the waxbin ownership boundary. The facade
// belongs to internal/service alone; the other waxbin packages carry
// contract types, so the service layer and the packages below it that
// speak those types may import any of them, and the composition root only
// waxbin/source and waxbin/enrich; nothing imports the SQLite store.
// Everything above the service layer (api, adapters, auth, events) works
// on the service's DTOs. Test files are exempt; files the host's build
// leaves out are not.
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
	// subpackageUsers may import waxbin subpackages other than store/sqlite:
	// every one when the list is nil, otherwise the listed ones and the
	// packages below them. The root builds service.Config.SourceProviders
	// and EnrichmentProviders, which are typed with waxbin/source and
	// waxbin/enrich.
	subpackageUsers = map[string][]string{
		"internal/service":      nil,
		"internal/providers":    nil,
		"internal/genre":        nil,
		"internal/bridge/flow":  nil,
		"internal/stubsource":   nil,
		"internal/waxtapsource": nil,
		"cmd/waxdeck":           {"source", "enrich"},
	}
)

var analyzer = &analysis.Analyzer{
	Name: "importlint",
	Doc:  "confines waxbin imports to the service layer and the packages below it, and the composition root to waxbin/source and waxbin/enrich",
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
				rel := relative(pkg)
				only, ok := subpackageUsers[rel]
				switch {
				case !ok:
					pass.Reportf(spec.Pos(), "imports waxbin above the service layer")
				case !mayImport(only, path):
					pass.Reportf(spec.Pos(), "imports waxbin/%s; %s may import only waxbin/%s",
						strings.TrimPrefix(path, facadePath+"/"), rel, strings.Join(only, ", waxbin/"))
				}
			}
		}
	}
	return nil, nil
}

// listed reports whether pkg, a full import path, is in users. A path
// outside the module is never listed.
func listed(users map[string]bool, pkg string) bool {
	return users[relative(pkg)]
}

// relative returns pkg, a full import path, as a module-relative one. A
// path outside the module comes back empty, which no map lists.
func relative(pkg string) string {
	rel, ok := strings.CutPrefix(pkg, modulePath+"/")
	if !ok {
		return ""
	}
	return rel
}

// mayImport reports whether an importer limited to only, waxbin
// subpackages, may import path. A nil only is no limit.
func mayImport(only []string, path string) bool {
	if only == nil {
		return true
	}
	for _, sub := range only {
		allowed := facadePath + "/" + sub
		if path == allowed || strings.HasPrefix(path, allowed+"/") {
			return true
		}
	}
	return false
}
