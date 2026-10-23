package service

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// skipWithoutUnwritableDirs skips where a mode cannot refuse the test's
// own process: Windows has no POSIX bits, and root ignores them.
func skipWithoutUnwritableDirs(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("windows os.Chmod cannot make a directory unwritable")
	}
	if os.Geteuid() == 0 {
		t.Skip("root ignores permissions, so an unwritable directory cannot refuse it")
	}
}

// chmodFor sets dir's mode for the test and puts it back before the
// temporary tree is removed.
func chmodFor(t *testing.T, dir string, mode os.FileMode) {
	t.Helper()
	if err := os.Chmod(dir, mode); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755) })
}

// A relative path would resolve against wherever the server runs, so it
// is refused in WaxDeck's words and nothing is stored.
func TestAddLibraryRefusesARelativePath(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "rel", Path: "relative/path"})
	if KindOf(err) != KindInvalid || err.Error() != "the library path must be absolute" {
		t.Fatalf("a relative path = %v, want it refused as not absolute", err)
	}
	stored, err := svc.db.LibraryRootsList(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "rel" }) {
		t.Errorf("stored names = %+v, want none for the refused library", stored)
	}
}

// A folder mounted later registers before it is there, and its scan says
// the root was unreachable rather than marking anything missing. A file
// is no library either way.
func TestAnAbsentRootIsRegisteredWhenAllowed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	dir := t.TempDir()
	later := filepath.Join(dir, "later")
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "later", Path: later, AllowAbsent: true})
	if err != nil {
		t.Fatalf("an absent folder with AllowAbsent = %v, want it registered", err)
	}
	if info.Name != "later" || info.Path != later {
		t.Fatalf("created %+v, want later at %s", info, later)
	}
	_, bare, _ := parseAPIPID(info.PID)
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	res, err := svc.lib.Scan(ctx, waxbin.ScanRequest{LibraryPID: bare})
	if err != nil {
		t.Fatalf("scanning the absent root: %v", err)
	}
	if len(res.Runs) != 1 || !res.Runs[0].RootUnreachable {
		t.Errorf("the scan's runs = %+v, want one reporting the root unreachable", res.Runs)
	}

	file := filepath.Join(dir, "notes.txt")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "file", Path: file, AllowAbsent: true}); KindOf(err) != KindInvalid ||
		!strings.Contains(err.Error(), "not a folder") {
		t.Errorf("a file with AllowAbsent = %v, want it refused as not a folder", err)
	}
}

// A managed library is one the server writes into, so a folder it cannot
// write is refused at the create rather than at the first upload, and
// the probe leaves nothing behind. The same folder in place is fine.
func TestAManagedLibraryMustBeWritable(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	dir := t.TempDir()
	chmodFor(t, dir, 0o555)
	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "locked", Path: dir, Managed: true})
	if KindOf(err) != KindInvalid || err.Error() !=
		"the library path is not writable by the server, so it cannot be managed; fix its ownership or add it unmanaged" {
		t.Fatalf("an unwritable managed folder = %v, want it refused as unwritable", err)
	}
	if entries, err := os.ReadDir(dir); err != nil || len(entries) != 0 {
		t.Errorf("the folder holds %v (%v) after the refusal, want nothing", entries, err)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "locked" }) {
		t.Errorf("stored names = %+v (%v), want none for the refused library", stored, err)
	}
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "locked", Path: dir}); err != nil {
		t.Errorf("the same folder in place = %v, want it created", err)
	}
}

// A path the server may not even look at is said so, not answered as an
// internal failure of the catalog's stat.
func TestAnUnreadableLibraryPathIsSaidSo(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	parent := t.TempDir()
	music := filepath.Join(parent, "music")
	if err := os.Mkdir(music, 0o755); err != nil {
		t.Fatal(err)
	}
	chmodFor(t, parent, 0)
	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "hidden", Path: music})
	if KindOf(err) != KindInvalid || err.Error() != "the server cannot read the library path" {
		t.Fatalf("an unreadable path = %v, want it refused as unreadable", err)
	}
	// A folder the server reaches but may not list: a stat passes, and
	// every scan of it would fail.
	closed := filepath.Join(t.TempDir(), "closed")
	if err := os.Mkdir(closed, 0o755); err != nil {
		t.Fatal(err)
	}
	chmodFor(t, closed, 0)
	_, err = svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "closed", Path: closed})
	if KindOf(err) != KindInvalid || err.Error() != "the server cannot read the library path" {
		t.Fatalf("an unlistable folder = %v, want it refused as unreadable", err)
	}
}

// The catalog, the stored name and the audit all hold the path as the
// catalog keys it, never the spelling typed, and the audit names the
// library it made.
func TestALibraryIsKeptByItsCleanPath(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	dir := t.TempDir()
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "tidy", Path: dir + "/./"})
	if err != nil {
		t.Fatal(err)
	}
	if info.Path != dir {
		t.Errorf("created path = %q, want %q", info.Path, dir)
	}
	stored, err := svc.db.LibraryRootsList(ctx)
	if err != nil || !slices.Contains(stored, wdb.LibraryRoot{Path: dir, Name: "tidy", CreatedAtNS: storedAt(stored, dir)}) {
		t.Errorf("stored names = %+v (%v), want tidy at %s", stored, err, dir)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.create"}, "", 10)
	if err != nil || len(page.Events) == 0 {
		t.Fatalf("no library.create audit entry (%v)", err)
	}
	e := page.Events[0]
	if e.TargetName != "tidy" || e.TargetPID != info.PID || e.Detail["path"] != dir {
		t.Errorf("audit = %+v, want tidy, %s, path %s", e, info.PID, dir)
	}
	if r, ok := rootAt(svc, dir); !ok || r.Name != "tidy" {
		t.Errorf("root table entry = %+v (found %v), want tidy at %s", r, ok, dir)
	}
}

// storedAt is when the name stored for path was first stored.
func storedAt(rows []wdb.LibraryRoot, path string) int64 {
	for _, r := range rows {
		if r.Path == path {
			return r.CreatedAtNS
		}
	}
	return 0
}
