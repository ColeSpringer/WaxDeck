package service

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// trashCopyFixture is a managed library's one track with a byte-identical
// copy in a second library, which the scan joins to the track.
type trashCopyFixture struct {
	ctx              context.Context
	svc              *Library
	admin            *UserCtx
	pid              string
	item             model.PID
	primary, copy    model.ItemFileRef
	home, elsewhere  model.PID
	homeDir, copyDir string
}

func newTrashCopyFixture(t *testing.T) trashCopyFixture {
	t.Helper()
	f := trashCopyFixture{copyDir: t.TempDir()}
	var paths []string
	f.ctx, f.svc, f.admin = openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		c.Roots = append(c.Roots, Root{Name: "elsewhere", Path: f.copyDir})
		f.homeDir = c.Roots[0].Path
		var err error
		if paths, err = fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	trashCopyInto(t, f.ctx, f.svc, paths[0], f.copyDir)
	items, err := f.svc.lib.Query(f.ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 1 {
		t.Fatalf("items = %v (%v), want the one track", items, err)
	}
	f.item = items[0].PID
	f.pid = apiPID(PrefixTrack, f.item)
	refs, err := f.svc.lib.ItemFiles(f.ctx, f.item)
	if err != nil || len(refs) != 2 {
		t.Fatalf("files = %+v (%v), want the track and its copy", refs, err)
	}
	f.primary, f.copy = refs[0], refs[1]
	if f.copy.Role != fileRoleAlternate || filepath.Dir(f.copy.DisplayPath) != filepath.Clean(f.copyDir) {
		t.Fatalf("files = %+v, want the copy under %s", refs, f.copyDir)
	}
	f.home, f.elsewhere = f.primary.LibraryPID, f.copy.LibraryPID
	return f
}

// trashCopyInto copies src byte for byte into dir and scans it in.
func trashCopyInto(t *testing.T, ctx context.Context, svc *Library, src, dir string) string {
	t.Helper()
	raw, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	dst := filepath.Join(dir, filepath.Base(src))
	if err := os.WriteFile(dst, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return dst
}

// caller is a non-administrator seeing every library, with or without
// the delete right, or only the given libraries.
func (f trashCopyFixture) caller(deleteRight bool, only ...model.PID) *UserCtx {
	uc := &UserCtx{ID: f.admin.ID, CatalogPID: f.admin.CatalogPID, Explicit: true, Delete: deleteRight, AllLibraries: len(only) == 0}
	if len(only) > 0 {
		uc.Libraries = map[string]bool{}
		for _, lib := range only {
			uc.Libraries[string(lib)] = true
		}
	}
	return uc
}

// trashFileStillThere fails unless path is on disk.
func trashFileStillThere(t *testing.T, path, what string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("%s went: %v", what, err)
	}
}

// Both delete verbs refuse an account without the delete right, and a
// permanent delete from one that holds it but is no administrator,
// before anything moves.
func TestTheDeleteVerbsRefuseWhatTheCallerMayNotDo(t *testing.T) {
	t.Parallel()
	f := newTrashCopyFixture(t)
	for _, c := range []struct {
		name string
		uc   *UserCtx
		mode string
	}{
		{"no delete right", f.caller(false), "trash"},
		{"permanent without the admin role", f.caller(true), "permanent"},
	} {
		if _, err := f.svc.DeleteItems(f.ctx, c.uc, []string{f.pid}, c.mode, false); KindOf(err) != KindForbidden {
			t.Errorf("items, %s = %v, want forbidden", c.name, err)
		}
		if _, err := f.svc.DeleteItemFiles(f.ctx, c.uc, f.pid, []string{string(f.copy.FilePID)}, c.mode, false); KindOf(err) != KindForbidden {
			t.Errorf("files, %s = %v, want forbidden", c.name, err)
		}
	}
	trashFileStillThere(t, f.primary.DisplayPath, "the track")
	trashFileStillThere(t, f.copy.DisplayPath, "the copy")
	if _, err := f.svc.DeleteItemFiles(f.ctx, f.caller(true), f.pid, []string{string(f.copy.FilePID)}, "trash", true); err != nil {
		t.Fatalf("a trash plan with the delete right = %v, want it planned", err)
	}
}

// A file of the item in a library the caller cannot see is no file of
// theirs to delete, though they see the item.
func TestDeletingAFileOutsideTheCallersLibrariesIsNotFound(t *testing.T) {
	t.Parallel()
	f := newTrashCopyFixture(t)
	curator := f.caller(true, f.home)
	if _, err := f.svc.DeleteItemFiles(f.ctx, curator, f.pid, []string{string(f.copy.FilePID)}, "trash", false); KindOf(err) != KindNotFound {
		t.Fatalf("delete = %v, want not-found", err)
	}
	trashFileStillThere(t, f.copy.DisplayPath, "the copy")
}

// A read-only server deletes none of an item's files, though the
// catalog, which knows nothing of the server's flag, would.
func TestAReadOnlyServerDeletesNoFileOfAnItem(t *testing.T) {
	t.Parallel()
	f := newTrashCopyFixture(t)
	setServerReadOnly(t, f.ctx, f.svc, true)
	if _, err := f.svc.DeleteItemFiles(f.ctx, f.admin, f.pid, []string{string(f.copy.FilePID)}, "trash", false); KindOf(err) != KindReadOnly {
		t.Fatalf("delete = %v, want read-only", err)
	}
	trashFileStillThere(t, f.copy.DisplayPath, "the copy")
}

// A delete some of whose files stayed reports what went at the size it
// had before it went.
func TestAPartlyAppliedDeleteReportsTheSizesItMeasuredFirst(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("a folder cannot be made unwritable here")
	}
	f := newTrashCopyFixture(t)
	locked := filepath.Join(f.homeDir, "locked")
	trashCopyInto(t, f.ctx, f.svc, f.primary.DisplayPath, locked)
	refs, err := f.svc.lib.ItemFiles(f.ctx, f.item)
	if err != nil || len(refs) != 3 {
		t.Fatalf("files = %+v (%v), want the track and two copies", refs, err)
	}
	var stuck model.ItemFileRef
	for _, r := range refs {
		if filepath.Dir(r.DisplayPath) == locked {
			stuck = r
		}
	}
	st, err := os.Stat(f.copy.DisplayPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	res, err := f.svc.DeleteItemFiles(f.ctx, f.admin, f.pid, []string{string(f.copy.FilePID), string(stuck.FilePID)}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Entries) != 1 || len(res.Entries[0].FileList) != 1 {
		t.Fatalf("entries = %+v, want the one copy that went", res.Entries)
	}
	e := res.Entries[0]
	if e.FileList[0].FilePID != string(f.copy.FilePID) || e.FileList[0].SizeBytes != st.Size() || e.Bytes != st.Size() {
		t.Fatalf("entry = %+v, want the copy that went at its %d bytes", e, st.Size())
	}
}

// A file the catalog skips as the delete runs, its library flagged
// read-only after the plan, stayed: neither verb reports it gone. A
// delete that moved the item's own file says the copy stayed; one that
// named the copy alone moved nothing, and is refused as read-only.
func TestAFileSkippedAsTheDeleteRunsStayed(t *testing.T) {
	t.Parallel()
	for _, whole := range []bool{false, true} {
		f := newTrashCopyFixture(t)
		f.svc.deleteApplyHook = func(ctx context.Context) {
			if _, err := f.svc.lib.SetLibraryReadOnly(ctx, f.elsewhere, true); err != nil {
				t.Error(err)
			}
		}
		var res DeleteItemsResultDTO
		var err error
		if whole {
			res, err = f.svc.DeleteItems(f.ctx, f.admin, []string{f.pid}, "trash", false)
		} else {
			_, err = f.svc.DeleteItemFiles(f.ctx, f.admin, f.pid, []string{string(f.copy.FilePID)}, "trash", false)
			if KindOf(err) != KindReadOnly {
				t.Errorf("the copy alone, skipped as it ran = %v (kind %q), want read-only", err, KindOf(err))
			}
			trashFileStillThere(t, f.copy.DisplayPath, "the skipped copy")
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range res.Entries {
			for _, fl := range e.FileList {
				if fl.FilePID == string(f.copy.FilePID) {
					t.Errorf("whole item %v: the skipped copy is reported gone: %+v", whole, res.Entries)
				}
			}
			if whole && !e.ItemSurvives {
				t.Errorf("whole item: entry %+v, want the item kept by its copy", e)
			}
		}
		if !slices.ContainsFunc(res.Warnings, func(w string) bool { return strings.Contains(w, "stray.flac stayed: library is read-only") }) {
			t.Errorf("whole item %v: warnings = %q, want the copy named as staying", whole, res.Warnings)
		}
		trashFileStillThere(t, f.copy.DisplayPath, "the skipped copy")
	}
}

// A copy that joins the item between the delete's read of its files and
// its plan, in a library the caller cannot see, is neither deleted nor
// named: what the caller was not shown stays.
func TestACopyJoiningMidDeleteOutsideTheCallersReachStays(t *testing.T) {
	t.Parallel()
	f := newTrashCopyFixture(t)
	curator := f.caller(true, f.home)
	late := filepath.Join(f.copyDir, "late")
	var joined string
	f.svc.deletePlanHook = func(ctx context.Context) {
		joined = trashCopyInto(t, ctx, f.svc, f.primary.DisplayPath, late)
	}
	// The first copy is in the snapshot and left for the caller's reach;
	// the late one is the gap under test.
	res, err := f.svc.DeleteItems(f.ctx, curator, []string{f.pid}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if joined == "" {
		t.Fatal("the hook never ran")
	}
	trashFileStillThere(t, joined, "the copy that joined mid-delete")
	for _, e := range res.Entries {
		if !e.ItemSurvives {
			t.Errorf("entry %+v, want the item kept by its copies", e)
		}
		for _, fl := range e.FileList {
			if fl.FilePID != string(f.primary.FilePID) {
				t.Errorf("entry names %+v, want the caller's own file alone", fl)
			}
		}
	}
}
