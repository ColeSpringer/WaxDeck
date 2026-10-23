package service

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// countProbePasses counts the probe passes that start from now on.
func countProbePasses(svc *Library) *atomic.Int32 {
	var passes atomic.Int32
	p := &svc.rootProbe
	p.mu.Lock()
	p.step = func(step string) {
		if step == "pass" {
			passes.Add(1)
		}
	}
	p.mu.Unlock()
	return &passes
}

// managedOpenRoot opens the service with a managed root that takes
// writes, the boot probe done, and answers the root's folder.
func managedOpenRoot(t *testing.T, dataDir string, mutate func(*Config)) (context.Context, *Library, *UserCtx, string, func()) {
	t.Helper()
	open := filepath.Join(dataDir, "open")
	if err := os.MkdirAll(open, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc, uc, stop := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "open", Path: open, Managed: true})
		if mutate != nil {
			mutate(c)
		}
	})
	waitFor(t, svc.rootProbe.idle, "the boot probe pass to end")
	return ctx, svc, uc, open, stop
}

// The administrators' listing and a rebuild of the root table answer the
// last probe and write nothing into a managed folder: a probe wakes a
// sleeping disk and moves the folder's time.
func TestAListingOrARefreshProbesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, _, open, _ := managedOpenRoot(t, t.TempDir(), nil)
	n, mtime := folderState(t, open)
	passes := countProbePasses(svc)
	if _, err := svc.LibrariesWithCounts(ctx); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	waitFor(t, svc.rootProbe.idle, "any probe pass to end")
	if got := passes.Load(); got != 0 {
		t.Errorf("a listing and a refresh ran %d probe passes, want none", got)
	}
	if n2, mtime2 := folderState(t, open); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the folder went from %d entries at %v to %d at %v, want it untouched", n, mtime, n2, mtime2)
	}
	if w := libraryAt(t, ctx, svc, open).Writable; w == nil || !*w {
		t.Errorf("the root lists writable %s, want the boot probe's answer", said(w))
	}
}

// The slow timer probes the managed roots again by itself.
func TestTheTimerProbesTheRootsAgain(t *testing.T) {
	t.Parallel()
	_, svc, _, _, _ := managedOpenRoot(t, t.TempDir(), func(c *Config) { c.RootProbeEvery = 20 * time.Millisecond })
	passes := countProbePasses(svc)
	waitFor(t, func() bool { return passes.Load() >= 2 }, "two timed probe passes")
}

// A server saved read-only writes no probe into its managed folders when
// it starts: the switch is read before the first probe.
func TestAReadOnlyServerWritesNoProbeAtItsStart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, open, stop := managedOpenRoot(t, dataDir, nil)
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	stop()
	n, mtime := folderState(t, open)
	ctx, svc, _, _, _ = managedOpenRoot(t, dataDir, nil)
	if n2, mtime2 := folderState(t, open); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the start moved the folder from %d entries at %v to %d at %v, want it untouched", n, mtime, n2, mtime2)
	}
	if w := libraryAt(t, ctx, svc, open).Writable; w != nil {
		t.Errorf("on a read-only server the library lists writable %v, want it unsaid", *w)
	}
}

// listedWritable is what the listing says of the library at root.
func listedWritable(t *testing.T, ctx context.Context, svc *Library, root string) *bool {
	t.Helper()
	return libraryAt(t, ctx, svc, root).Writable
}

// said is a listed writable flag in words.
func said(w *bool) string {
	if w == nil {
		return "unsaid"
	}
	return strconv.FormatBool(*w)
}

// An upload the managed folder refused has the roots probed again at
// once: the libraries say the folder stopped taking writes without
// waiting for the timer.
func TestARefusedUploadProbesTheRootsAgain(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc := managedUploadFixture(t)
	waitFor(t, svc.rootProbe.idle, "the boot probe pass to end")
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	var root string
	for _, r := range svc.libraryRoots() {
		if r.Name == "lib" {
			root = r.Path
		}
	}
	lockFolder(t, root)
	if w := listedWritable(t, ctx, svc, root); w == nil || !*w {
		t.Fatalf("before any write the root lists writable %s, want the boot probe's answer", said(w))
	}
	if _, _, err := svc.DecideReviewEntry(ctx, uc, id, "as-is", ""); KindOf(err) != KindStorageUnwritable {
		t.Fatalf("decision = %v, want storage-unwritable", err)
	}
	waitFor(t, func() bool {
		w := listedWritable(t, ctx, svc, root)
		return w != nil && !*w
	}, "the refused write to have the root probed again")
}

// A delete the filesystem refused, wholly or in part, probes the roots
// again.
func TestARefusedDeleteProbesTheRootsAgain(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	for _, albums := range [][]string{{"Locked"}, {"Open", "Locked"}} {
		ctx, svc, admin, root, tracks := newTrashFixture(t, albums...)
		waitFor(t, svc.rootProbe.idle, "the boot probe pass to end")
		lockFolder(t, filepath.Join(root, "Locked"))
		passes := countProbePasses(svc)
		var pids []string
		for _, album := range albums {
			pids = append(pids, tracks[album].pid)
		}
		if _, err := svc.DeleteItems(ctx, admin, pids, "trash", false); err != nil && KindOf(err) != KindStorageUnwritable {
			t.Fatalf("%v: delete = %v", albums, err)
		}
		waitFor(t, func() bool { return passes.Load() >= 1 }, "a probe pass after the refused delete")
	}
}

// An organize run whose moves the filesystem refused probes the roots
// again when it ends.
func TestARefusedOrganizeProbesTheRootsAgain(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
		if _, err := fixtures.Generate(root, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), ""); err != nil || len(items) != 1 {
		t.Fatalf("items = %d (%v), want the stray track", len(items), err)
	}
	waitFor(t, svc.rootProbe.idle, "the boot probe pass to end")
	lockFolder(t, root)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Failed == 0 {
		t.Fatalf("apply = %+v (%v), want the move refused", rep, err)
	}
	waitFor(t, func() bool {
		w := listedWritable(t, ctx, svc, root)
		return w != nil && !*w
	}, "the refused moves to have the root probed again")
}

// A refresh never puts back the writable flag a probe pass changed while
// the refresh was reading the catalog: the pass's answer stands.
func TestARefreshKeepsTheAnswerOfAProbeLandingMidway(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, _, open, _ := managedOpenRoot(t, t.TempDir(), nil)
	if w := listedWritable(t, ctx, svc, open); w == nil || !*w {
		t.Fatalf("at the start the root lists writable %s, want true", said(w))
	}
	chmodFor(t, open, 0o555)
	var once sync.Once
	svc.refreshMu.Lock()
	svc.refreshHook = func() {
		once.Do(func() {
			svc.probeRoots()
			waitFor(t, svc.rootProbe.idle, "the probe pass inside the refresh to end")
		})
	}
	svc.refreshMu.Unlock()
	svc.refreshLibraryState(ctx)
	if w := listedWritable(t, ctx, svc, open); w == nil || *w {
		t.Fatalf("after the refresh the root lists writable %s, want the pass's false", said(w))
	}
}

// twoManagedRoots opens the service with two managed roots that take
// writes, the boot probe done, answering their folders.
func twoManagedRoots(t *testing.T) (context.Context, *Library, *UserCtx, string, string) {
	t.Helper()
	dataDir := t.TempDir()
	flipped, other := filepath.Join(dataDir, "flipped"), filepath.Join(dataDir, "other")
	ctx, svc, uc, _, _ := managedOpenRoot(t, dataDir, func(c *Config) {
		for _, dir := range []string{flipped, other} {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
		}
		c.Roots = append(c.Roots,
			Root{Name: "flipped", Path: flipped, Managed: true},
			Root{Name: "other", Path: other, Managed: true})
	})
	return ctx, svc, uc, flipped, other
}

// Lifting a library's read-only flag probes that library's folder, and
// no other: a folder locked while it was read-only lists as not writable
// without waiting for the timer.
func TestLiftingALibrarysReadOnlyFlagProbesIt(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, uc, flipped, other := twoManagedRoots(t)
	pid := libraryAt(t, ctx, svc, flipped).PID
	if err := svc.LibraryReadOnlySet(ctx, uc, pid, true); err != nil {
		t.Fatal(err)
	}
	chmodFor(t, flipped, 0o555)
	waitFor(t, svc.rootProbe.idle, "any probe pass to end")
	n, mtime := folderState(t, other)
	if err := svc.LibraryReadOnlySet(ctx, uc, pid, false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, svc.rootProbe.idle, "the probe pass the lift started")
	if w := listedWritable(t, ctx, svc, flipped); w == nil || *w {
		t.Errorf("after the lift the locked library lists writable %s, want false", said(w))
	}
	if n2, mtime2 := folderState(t, other); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the lift probed another library: its folder went from %d entries at %v to %d at %v", n, mtime, n2, mtime2)
	}
}

// Turning the server's read-only switch off probes every managed root.
func TestLiftingTheServersReadOnlySwitchProbesTheRoots(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, uc, flipped, _ := twoManagedRoots(t)
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	chmodFor(t, flipped, 0o555)
	st.ReadOnly = false
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	waitFor(t, svc.rootProbe.idle, "the probe pass the lift started")
	if w := listedWritable(t, ctx, svc, flipped); w == nil || *w {
		t.Errorf("after the lift the locked library lists writable %s, want false", said(w))
	}
}

// A managed root another process adds, as the waxbin CLI does, is probed
// once the server takes it into its table.
func TestAManagedRootAddedElsewhereIsProbed(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	ctx, svc, _, _, _ := managedOpenRoot(t, t.TempDir(), nil)
	added := t.TempDir()
	chmodFor(t, added, 0o555)
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: added, Mode: model.ModeManaged}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		w := listedWritable(t, ctx, svc, added)
		return w != nil && !*w
	}, "the added root to be probed and list not writable")
}

// A library created in the console is probed by its create's own look at
// the folder, and its arrival in the table starts no pass of its own.
func TestAConsoleCreateIsProbedOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedOpenRoot(t, t.TempDir(), nil)
	passes := countProbePasses(svc)
	fresh := t.TempDir()
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "fresh", Path: fresh, Managed: true}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, svc.rootProbe.idle, "any probe pass to end")
	if n := passes.Load(); n != 0 {
		t.Errorf("the create ran %d probe passes beside its own look, want none", n)
	}
	if w := listedWritable(t, ctx, svc, fresh); w == nil || !*w {
		t.Errorf("the new library lists writable %s, want its create's answer", said(w))
	}
}
