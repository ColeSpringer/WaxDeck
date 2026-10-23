package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// folderState is what a probe would change in a folder: its entries and
// its modification time.
func folderState(t *testing.T, dir string) (int, time.Time) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	return len(entries), st.ModTime()
}

// probedOnce rereads the libraries and runs a probe pass over them.
func probedOnce(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	svc.refreshLibraryState(ctx)
	svc.probeRoots()
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
}

// A library the server treats as read-only, by its own flag or the whole
// server's, is never written to by the probe, and says nothing of whether
// it could be: the folder keeps its entries and its time.
func TestAReadOnlyLibraryIsNeverProbed(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	held, open := filepath.Join(dataDir, "held"), filepath.Join(dataDir, "open")
	for _, dir := range []string{held, open} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots,
			Root{Name: "held", Path: held, Managed: true},
			Root{Name: "open", Path: open, Managed: true})
	})
	if err := svc.LibraryReadOnlySet(ctx, uc, libraryAt(t, ctx, svc, held).PID, true); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
	n, mtime := folderState(t, held)
	probedOnce(t, ctx, svc)
	if n2, mtime2 := folderState(t, held); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the read-only library's folder went from %d entries at %v to %d at %v, want it untouched", n, mtime, n2, mtime2)
	}
	if w := libraryAt(t, ctx, svc, held).Writable; w != nil {
		t.Errorf("the read-only library lists writable %v, want it unsaid", *w)
	}
	if w := libraryAt(t, ctx, svc, open).Writable; w == nil || !*w {
		t.Errorf("the writable managed library lists writable %v, want true", w)
	}

	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
	n, mtime = folderState(t, open)
	probedOnce(t, ctx, svc)
	if n2, mtime2 := folderState(t, open); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("on a read-only server the folder went from %d entries at %v to %d at %v, want it untouched", n, mtime, n2, mtime2)
	}
	if w := libraryAt(t, ctx, svc, open).Writable; w != nil {
		t.Errorf("on a read-only server the library lists writable %v, want it unsaid", *w)
	}
}

// A folder whose ownership was fixed reads as writable once the timer
// probes it again, without a restart or a library edit.
func TestAFixedFolderListsWritableAfterTheTimedProbe(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	dataDir := t.TempDir()
	locked := filepath.Join(dataDir, "locked")
	if err := os.Mkdir(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	chmodFor(t, locked, 0o555)
	ctx, svc, _, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "locked", Path: locked, Managed: true})
		c.RootProbeEvery = 20 * time.Millisecond
	})
	waitFor(t, func() bool {
		w := libraryAt(t, ctx, svc, locked).Writable
		return w != nil && !*w
	}, "the locked root to list not writable")
	if err := os.Chmod(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		w := libraryAt(t, ctx, svc, locked).Writable
		return w != nil && *w
	}, "the fixed root to list writable after a timed probe")
}

// A create aimed at a library's folder, or at a folder inside one, is
// refused before anything is written there: a library the server keeps
// read-only keeps its folder as it was.
func TestACreateAtALibrarysFolderWritesNothingThere(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	held := filepath.Join(dataDir, "held")
	inside := filepath.Join(held, "inside")
	if err := os.MkdirAll(inside, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "held", Path: held, Managed: true})
	})
	if err := svc.LibraryReadOnlySet(ctx, uc, libraryAt(t, ctx, svc, held).PID, true); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
	for _, dir := range []string{held, inside} {
		n, mtime := folderState(t, dir)
		_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "again", Path: dir, Managed: true})
		if err == nil {
			t.Fatalf("a managed create at %s was accepted", dir)
		}
		if dir == held && KindOf(err) != KindConflict {
			t.Errorf("a managed create at the library's folder = %v, want that it exists", err)
		}
		if n2, mtime2 := folderState(t, dir); n2 != n || !mtime2.Equal(mtime) {
			t.Errorf("%s went from %d entries at %v to %d at %v, want it untouched", dir, n, mtime, n2, mtime2)
		}
	}
}

// While the server is read-only a managed create writes no probe into its
// folder, and says nothing of whether it could.
func TestACreateOnAReadOnlyServerWritesNoProbe(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	fresh := filepath.Join(dataDir, "fresh")
	if err := os.Mkdir(fresh, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	n, mtime := folderState(t, fresh)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "fresh", Path: fresh, Managed: true})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
	if n2, mtime2 := folderState(t, fresh); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the folder went from %d entries at %v to %d at %v, want it untouched", n, mtime, n2, mtime2)
	}
	if lib.Writable != nil {
		t.Errorf("the library lists writable %v, want it unsaid", *lib.Writable)
	}
}
