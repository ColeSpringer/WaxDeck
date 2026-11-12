package service

import (
	"go/ast"
	"go/build"
	"go/parser"
	"go/token"
	"maps"
	"os"
	"reflect"
	"slices"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// dbAllowed is what may still take or answer a database type, each for the
// reason given, and only for one of two: the principal the API
// authenticates carries an account row, or the composition root opens the
// one store and hands it in, a dependency passed down rather than a
// database type handed up to a caller. Each is listed by name, so the next
// one is a decision.
var dbAllowed = map[string]string{
	"Grants.UserCtx":        "builds the principal's context from its row",
	"Open":                  "the composition root hands in the store it opened",
	"PermissionsOf":         "getSession, which is public and builds no context, and refreshToken render the principal's row",
	"ResetSyncAfterRestore": "the composition root hands in the store it opened, before Open",
}

// exportedFuncs is every exported function of the package, so the walk can
// ask their types; the test fails when the source and the list disagree.
var exportedFuncs = map[string]any{
	"AccountChanges":        AccountChanges,
	"AccountGrants":         AccountGrants,
	"AlbumYear":             AlbumYear,
	"ArtSizeOnLadder":       ArtSizeOnLadder,
	"DefaultPermissions":    DefaultPermissions,
	"EnclosureMediaType":    EnclosureMediaType,
	"EntityArtworkOwned":    EntityArtworkOwned,
	"FeedFailureReason":     FeedFailureReason,
	"FileAPIPID":            FileAPIPID,
	"HostOnlyLogger":        HostOnlyLogger,
	"JoinableMP3":           JoinableMP3,
	"KindOf":                KindOf,
	"NewBackups":            NewBackups,
	"NormalizeGpodderTime":  NormalizeGpodderTime,
	"Open":                  Open,
	"ParseFacetSort":        ParseFacetSort,
	"ParseFilePID":          ParseFilePID,
	"PeekCatalogMints":      PeekCatalogMints,
	"PermissionsOf":         PermissionsOf,
	"PlayPartAt":            PlayPartAt,
	"RadioDialRefusal":      RadioDialRefusal,
	"RefusalParams":         RefusalParams,
	"RelayableMediaType":    RelayableMediaType,
	"ResetSyncAfterRestore": ResetSyncAfterRestore,
	"SameOrigin":            SameOrigin,
	"ToolTaskFinished":      ToolTaskFinished,
	"UserAgentFor":          UserAgentFor,
	"VetRestore":            VetRestore,
	"WatchDegraded":         WatchDegraded,
}

// No exported function of the package, and no exported method or field of
// *Library, its domains, *Backups, or a service type reachable from any of
// them through a parameter, result or field, names a type of the database
// package, dbAllowed aside. A type of another of the server's packages
// that hands a database type on counts as naming one.
func TestTheExportedSurfaceHoldsNoDatabaseType(t *testing.T) {
	declared := exportedFuncDecls(t)
	for _, name := range declared {
		if _, ok := exportedFuncs[name]; !ok {
			t.Errorf("%s is exported but not in exportedFuncs: list it", name)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(exportedFuncs)) {
		if !slices.Contains(declared, name) {
			t.Errorf("exportedFuncs lists %s, which the package does not declare", name)
		}
	}

	svc := reflect.TypeFor[Library]().PkgPath()
	w := &surfaceWalk{
		db:     reflect.TypeFor[wdb.User]().PkgPath(),
		svc:    svc,
		server: strings.TrimSuffix(svc, "service"),
		seen:   map[reflect.Type]bool{},
		open:   map[reflect.Type]bool{},
	}
	for name, fn := range exportedFuncs {
		if w.touches(reflect.TypeOf(fn)) {
			w.leaks = append(w.leaks, name)
		}
	}
	w.touches(reflect.TypeFor[*Library]())
	w.touches(reflect.TypeFor[*Backups]())
	for len(w.queue) > 0 {
		next := w.queue[0]
		w.queue = w.queue[1:]
		w.visit(next)
	}

	for _, name := range w.opaque {
		t.Errorf("%s instantiates a generic type over a service type, which the walk cannot see into", name)
	}
	slices.Sort(w.leaks)
	w.leaks = slices.Compact(w.leaks)
	for _, name := range w.leaks {
		if _, ok := dbAllowed[name]; !ok {
			t.Errorf("%s names a type of %s: give it a service type", name, w.db)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(dbAllowed)) {
		if !slices.Contains(w.leaks, name) {
			t.Errorf("%s no longer names a database type: drop it from dbAllowed", name)
		}
	}
}

// exportedFuncDecls lists the exported functions the package's source
// declares for this build, methods aside.
func exportedFuncDecls(t *testing.T) []string {
	t.Helper()
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	fset := token.NewFileSet()
	var out []string
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		if ok, err := build.Default.MatchFile(".", name); err != nil || !ok {
			continue
		}
		f, err := parser.ParseFile(fset, name, nil, parser.SkipObjectResolution)
		if err != nil {
			t.Fatal(err)
		}
		for _, d := range f.Decls {
			if fd, ok := d.(*ast.FuncDecl); ok && fd.Recv == nil && fd.Name.IsExported() {
				out = append(out, fd.Name.Name)
			}
		}
	}
	slices.Sort(out)
	return out
}

// surfaceWalk visits every service type a caller can reach, each once,
// noting each member that names a database type.
type surfaceWalk struct {
	// server is the import path the server's internal packages share.
	db, svc, server string
	seen            map[reflect.Type]bool
	// open is the types carries is inside, so a cycle ends.
	open   map[reflect.Type]bool
	queue  []reflect.Type
	leaks  []string
	opaque []string
}

// touches reports whether t is a database type, is built from one, or is
// a type of another of the server's packages that hands one on, and
// queues every service type it meets for a visit of its own.
func (w *surfaceWalk) touches(t reflect.Type) bool {
	switch {
	case t.PkgPath() == w.db || strings.Contains(t.Name(), w.db+"."):
		return true
	case t.Name() == "":
		return w.builtFrom(t)
	case t.PkgPath() == w.svc:
		if !w.seen[t] {
			w.seen[t] = true
			w.queue = append(w.queue, t)
		}
	case strings.Contains(t.Name(), w.svc+"."):
		w.opaque = append(w.opaque, t.String())
	case strings.HasPrefix(t.PkgPath(), w.server):
		return w.carries(t)
	}
	return false
}

// carries reports whether t, a type of another of the server's packages,
// hands a database type on: in an exported field, in what its underlying
// type is built from, or through a method.
func (w *surfaceWalk) carries(t reflect.Type) bool {
	if w.open[t] {
		return false
	}
	w.open[t] = true
	defer delete(w.open, t)
	found := w.builtFrom(t)
	if t.Kind() != reflect.Interface {
		for m := range reflect.PointerTo(t).Methods() {
			found = w.touches(m.Type) || found
		}
	}
	return found
}

// builtFrom asks the parts t is made of, every one of them, so each
// service type among them is queued.
func (w *surfaceWalk) builtFrom(t reflect.Type) bool {
	var parts []reflect.Type
	switch t.Kind() {
	case reflect.Pointer, reflect.Slice, reflect.Array, reflect.Chan:
		parts = []reflect.Type{t.Elem()}
	case reflect.Map:
		parts = []reflect.Type{t.Key(), t.Elem()}
	case reflect.Func:
		parts = append(slices.Collect(t.Ins()), slices.Collect(t.Outs())...)
	case reflect.Interface:
		for m := range t.Methods() {
			parts = append(parts, m.Type)
		}
	case reflect.Struct:
		for f := range t.Fields() {
			if f.IsExported() {
				parts = append(parts, f.Type)
			}
		}
	}
	found := false
	for _, p := range parts {
		found = w.touches(p) || found
	}
	return found
}

// visit notes the members of the service type t that name a database
// type: its exported fields, promoted ones included, what an unnamed
// underlying type is built from, and its exported methods.
func (w *surfaceWalk) visit(t reflect.Type) {
	switch t.Kind() {
	case reflect.Struct:
		for _, f := range reflect.VisibleFields(t) {
			if f.IsExported() && w.touches(f.Type) {
				w.leaks = append(w.leaks, t.Name()+"."+f.Name)
			}
		}
	case reflect.Interface:
	default:
		if w.builtFrom(t) {
			w.leaks = append(w.leaks, t.Name())
		}
	}
	methods := reflect.PointerTo(t).Methods()
	if t.Kind() == reflect.Interface {
		methods = t.Methods()
	}
	for m := range methods {
		if w.touches(m.Type) {
			w.leaks = append(w.leaks, t.Name()+"."+m.Name)
		}
	}
}
