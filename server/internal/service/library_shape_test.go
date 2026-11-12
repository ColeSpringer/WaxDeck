package service

import (
	"reflect"
	"slices"
	"strings"
	"testing"
)

// libraryFields, libraryHooks and coreShared are exact, and moved by hand:
// state leaves Library for the domain type that owns it, and the numbers
// follow once it has. Exact rather than a ceiling, so a field that left
// cannot be quietly replaced by another.
const libraryFields = 22

var libraryHooks = []string{
	"catalogRepairEndHook",
	"catalogRepairHook",
	"journalWalkHook",
	"scanStartHook",
	"suspendHook",
}

// coreShared is what core holds beside its domains: the process's
// dependencies and read-only state. Every domain reaches all of it, so a
// new entry is shared state by construction.
var coreShared = []string{
	"catalogFile",
	"catalogItem",
	"db",
	"lib",
	"library",
	"log",
	"lookupHost",
	"paths",
	"procCtx",
	"sealer",
	"userWake",
	"version",
	"workers",
}

func TestLibraryShape(t *testing.T) {
	if !slices.IsSorted(libraryHooks) {
		t.Error("libraryHooks is not sorted")
	}
	lt := reflect.TypeOf(Library{})
	switch n := lt.NumField(); {
	case n > libraryFields:
		t.Errorf("Library has %d fields, above its %d: put the new state on the domain type that owns it "+
			"(core.go lists them) rather than raising the number", n, libraryFields)
	case n < libraryFields:
		t.Errorf("Library has %d fields, below its %d: lower libraryFields to match", n, libraryFields)
	}
	var hooks []string
	for f := range lt.Fields() {
		if strings.HasSuffix(f.Name, "Hook") {
			hooks = append(hooks, f.Name)
		}
	}
	for _, name := range hooks {
		if !slices.Contains(libraryHooks, name) {
			t.Errorf("Library gained the test hook %s: put it on the domain type whose code it hooks "+
				"rather than adding it to libraryHooks", name)
		}
	}
	for _, name := range libraryHooks {
		if !slices.Contains(hooks, name) {
			t.Errorf("libraryHooks lists %s, which Library no longer has: drop it", name)
		}
	}
}

func TestCoreShape(t *testing.T) {
	if !slices.IsSorted(coreShared) {
		t.Error("coreShared is not sorted")
	}
	var shared []string
	for f := range reflect.TypeFor[core]().Fields() {
		if !f.IsExported() {
			shared = append(shared, f.Name)
		}
	}
	for _, name := range shared {
		if !slices.Contains(coreShared, name) {
			t.Errorf("core gained %s, which every domain would share: put it on the domain type that owns it "+
				"rather than adding it to coreShared", name)
		}
	}
	for _, name := range coreShared {
		if !slices.Contains(shared, name) {
			t.Errorf("coreShared lists %s, which core no longer has: drop it", name)
		}
	}
}

// domainFields are core's exported fields: every one is a domain type
// embedding the shared *core.
func domainFields(t *testing.T) []reflect.StructField {
	t.Helper()
	coreType := reflect.TypeFor[*core]()
	var out []reflect.StructField
	for f := range reflect.TypeFor[core]().Fields() {
		if !f.IsExported() {
			continue
		}
		if f.Type.Kind() != reflect.Pointer || f.Type.Elem().Kind() != reflect.Struct {
			t.Fatalf("core.%s is %s, not a pointer to a domain type", f.Name, f.Type)
		}
		embedded, ok := f.Type.Elem().FieldByName("core")
		if !ok || !embedded.Anonymous || embedded.Type != coreType {
			t.Fatalf("core.%s's type %s does not embed *core", f.Name, f.Type.Elem())
		}
		out = append(out, f)
	}
	if len(out) == 0 {
		t.Fatal("core has no domain fields")
	}
	return out
}

func TestCoreWired(t *testing.T) {
	// A sealer is optional (nil is a server without one); the admin
	// fixture configures one, and with it no pointer on the core may be
	// left nil.
	_, l, _ := newAdminFixture(t)
	c := reflect.ValueOf(l.core).Elem()
	for f := range reflect.TypeFor[core]().Fields() {
		if f.Type.Kind() == reflect.Pointer && c.FieldByIndex(f.Index).IsNil() {
			t.Errorf("core.%s is nil after Open", f.Name)
		}
	}
	if l.library != l {
		t.Errorf("core.library is %p, not the opened Library %p", l.library, l)
	}
	for _, f := range domainFields(t) {
		d := c.FieldByIndex(f.Index)
		if d.IsNil() {
			continue
		}
		if got := d.Elem().FieldByName("core").Pointer(); got != reflect.ValueOf(l.core).Pointer() {
			t.Errorf("core.%s's core is %#x, not the Library's %p", f.Name, got, l.core)
		}
	}
}

func TestWireOnBareCore(t *testing.T) {
	c := &core{}
	c.wire(Config{})
	v := reflect.ValueOf(c).Elem()
	for _, f := range domainFields(t) {
		d := v.FieldByIndex(f.Index)
		if d.IsNil() {
			t.Errorf("core.%s is nil after wire", f.Name)
			continue
		}
		if d.Elem().FieldByName("core").Pointer() != reflect.ValueOf(c).Pointer() {
			t.Errorf("core.%s is not built over the wired core", f.Name)
		}
	}
}
