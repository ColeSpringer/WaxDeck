package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/colespringer/waxbin/model"
)

// A library whose create's scan started once the watcher had armed it is
// left to that scan: the watcher does not walk it a second time.
func TestTheWatcherLeavesANewLibraryToItsCreatesScan(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	added := t.TempDir()
	dropTrack(t, added, "Brought Along")
	decided := make(chan bool, 8)
	svc.watchScanHook = func(dir string, scanned bool) {
		if dir == added {
			decided <- scanned
		}
	}
	// The create's scan starts once the pass the create nudges has armed,
	// and that pass returns to its sweeps only once the create has
	// started the scan, so its first sweep finds the scan.
	armed := make(chan struct{})
	created := newGate(t)
	var once sync.Once
	hook := func(done bool) {
		if done {
			once.Do(func() {
				close(armed)
				created.wait()
			})
		}
	}
	svc.watchArmHook.Store(&hook)
	svc.scanStartHook = func() error {
		awaitClosed(t, armed, "the watcher to arm the new library")
		return nil
	}
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "added", Path: added})
	created.release()
	if err != nil {
		t.Fatal(err)
	}
	if !info.ScanStarted {
		t.Fatal("the create's scan did not start")
	}
	waitForTitle(t, ctx, svc, "Brought Along")
	select {
	case scanned := <-decided:
		if scanned {
			t.Fatal("the watcher walked the new library again after its create's scan")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never settled the new library's catch-up")
	}
}

// A root's catch-up stays owed through a requeue until a scan pays it;
// an event in the root makes its scan unconditional, and a catch-up never
// makes a pending event's scan conditional.
func TestWatchPendingKeepsWhatARootIsOwed(t *testing.T) {
	t.Parallel()
	p := newWatchPending(10 * time.Second)
	base := time.Now()
	p.owe("/lib/new", 0, base)
	due := p.due(base.Add(10 * time.Second))
	if len(due) != 1 {
		t.Fatalf("due = %v, want the root", due)
	}
	p.renote(due, base.Add(10*time.Second))
	if since, owed := p.owedSince("/lib/new"); !owed || since != 0 {
		t.Fatalf("after a requeue the root owes %d (%v), want its catch-up kept", since, owed)
	}
	p.note("/lib/new", base.Add(11*time.Second))
	if _, owed := p.owedSince("/lib/new"); owed {
		t.Fatal("an event in the root left its scan to a catalog scan")
	}
	p.owe("/lib/new", 5, base.Add(12*time.Second))
	if _, owed := p.owedSince("/lib/new"); owed {
		t.Fatal("a catch-up made a pending event's scan conditional")
	}

	p.owe("/lib/back", 5, base)
	p.owe("/lib/back", 9, base)
	p.paid("/lib/back", 5)
	if since, owed := p.owedSince("/lib/back"); !owed || since != 9 {
		t.Fatalf("the root owes %d (%v), want the later catch-up kept", since, owed)
	}
	p.paid("/lib/back", 9)
	if _, owed := p.owedSince("/lib/back"); owed {
		t.Fatal("a paid catch-up is still owed")
	}
}

// A library whose create could not start its scan, the catalog busy with
// another job, is caught up by the watcher once it takes the library up:
// no kept scan walked it, the one that ran before it existed included.
func TestTheWatcherCatchesUpALibraryItsCreateCouldNotScan(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if ended := scanAndSettle(t, ctx, svc, uc); ended.State != string(model.JobDone) {
		t.Fatalf("the scan before the create ended %s, want done", ended.State)
	}
	added := t.TempDir()
	dropTrack(t, added, "Caught Up Later")
	decided := make(chan bool, 8)
	svc.watchScanHook = func(dir string, scanned bool) {
		if dir == added {
			decided <- scanned
		}
	}
	svc.scanStartHook = func() error {
		return &Error{Kind: KindConflict, Msg: "another catalog job is running"}
	}
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "added", Path: added})
	if err != nil {
		t.Fatal(err)
	}
	if info.ScanStarted {
		t.Fatal("the create's scan started, want it refused as the catalog busy")
	}
	select {
	case scanned := <-decided:
		if !scanned {
			t.Fatal("the watcher let go of a library no scan walked")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never took the new library's catch-up in hand")
	}
	waitForTitle(t, ctx, svc, "Caught Up Later")
}

// A file that lands in a new library after its create's scan walked it
// and before the watcher armed it raises no event, so the watcher's
// catch-up scans it: a scan that started before the watch existed does
// not cover what landed in between.
func TestTheWatcherCatchesUpWhatLandsBeforeItArmsANewLibrary(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	added := t.TempDir()
	decided := make(chan bool, 8)
	svc.watchScanHook = func(dir string, scanned bool) {
		if dir == added {
			decided <- scanned
		}
	}
	// The pass the create nudges waits, unarmed, until the file is in.
	pass := parkNextArm(t, svc)
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "added", Path: added})
	if err != nil {
		t.Fatal(err)
	}
	if !info.ScanStarted {
		t.Fatal("the create's scan did not start")
	}
	awaitClosed(t, pass.parked, "the watcher to take the new library up")
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	dropTrack(t, added, "Landed Before The Watch")
	pass.release()
	select {
	case scanned := <-decided:
		if !scanned {
			t.Fatal("the watcher left the new library to a scan that started before its watch")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never settled the new library's catch-up")
	}
	waitForTitle(t, ctx, svc, "Landed Before The Watch")
}

// gate is a channel a test closes once; its cleanup closes it before the
// service stops, so a failure cannot leave the watcher parked on it.
type gate struct {
	ch   chan struct{}
	once sync.Once
}

func newGate(t *testing.T) *gate {
	g := &gate{ch: make(chan struct{})}
	t.Cleanup(g.release)
	return g
}

func (g *gate) release() { g.once.Do(func() { close(g.ch) }) }

func (g *gate) wait() { <-g.ch }

// armPass is a watcher pass, or a walk, parked before it arms anything.
type armPass struct {
	parked chan struct{}
	*gate
}

// parkNextArm parks the next watcher pass before it arms anything,
// until the test releases it.
func parkNextArm(t *testing.T, svc *Library) *armPass {
	p := &armPass{parked: make(chan struct{}), gate: newGate(t)}
	var once sync.Once
	hook := func(armed bool) {
		if !armed {
			once.Do(func() {
				close(p.parked)
				p.wait()
			})
		}
	}
	svc.watchArmHook.Store(&hook)
	return p
}

// parkNextWalk parks the next walk of root, a pass's or the root's own,
// before it arms anything, until the test releases it.
func parkNextWalk(t *testing.T, svc *Library, root string) *armPass {
	p := &armPass{parked: make(chan struct{}), gate: newGate(t)}
	var once sync.Once
	hook := func(stage, path string) {
		if stage == "walk" && path == root {
			once.Do(func() {
				close(p.parked)
				p.wait()
			})
		}
	}
	svc.watchLookHook.Store(&hook)
	return p
}

// watchAdmin is an administrator of a watched service.
func watchAdmin(t *testing.T, ctx context.Context, svc *Library) *UserCtx {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// A root already watched stays watched while a pass takes another up: a
// file that lands in it then raises its event.
func TestARootStaysWatchedWhileTheWatcherTakesAnotherUp(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	uc := watchAdmin(t, ctx, svc)
	pass := parkNextArm(t, svc)
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "added", Path: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, pass.parked, "the watcher to take the new library up")
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	dropTrack(t, lib, "Landed During A Re-arm")
	pass.release()
	waitForTitle(t, ctx, svc, "Landed During A Re-arm")
}

// A root still owed its catch-up when a later pass runs keeps its watch
// through that pass: a whole scan that walked it while the pass ran does
// not stand for a file that landed after the walk, whose event the watch
// still raises.
func TestAnOwedRootStaysWatchedThroughALaterPass(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	uc := watchAdmin(t, ctx, svc)
	// A window long enough that a's catch-up is still owed at b's pass.
	svc.watchQueue.mu.Lock()
	svc.watchQueue.settle = 2 * time.Second
	svc.watchQueue.mu.Unlock()
	// a's create cannot scan, so its catch-up is owed from its arm.
	owedRoot := t.TempDir()
	armedA := make(chan struct{})
	var once sync.Once
	hook := func(done bool) {
		if done {
			once.Do(func() { close(armedA) })
		}
	}
	svc.watchArmHook.Store(&hook)
	svc.scanStartHook = func() error {
		return &Error{Kind: KindConflict, Msg: "another catalog job is running"}
	}
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "a", Path: owedRoot}); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, armedA, "the watcher to take a up")
	// b's create scans every library, a included, while b's pass waits.
	svc.scanStartHook = nil
	pass := parkNextArm(t, svc)
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "b", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	if !info.ScanStarted {
		t.Fatal("b's create's scan did not start")
	}
	awaitClosed(t, pass.parked, "the watcher to take b up")
	if _, owed := svc.watchQueue.owedSince(owedRoot); !owed {
		t.Fatal("a is not owed its catch-up at b's pass")
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "b's create's scan to end")
	dropTrack(t, owedRoot, "Landed After The Walk")
	pass.release()
	waitForTitle(t, ctx, svc, "Landed After The Walk")
}

// A watcher the supervisor restarts after a failure watched nothing in
// between, so it catches every root up: a file that landed while it was
// down is catalogued without a scheduled scan.
func TestARestartedWatcherCatchesUpWhatLandedWhileItWasDown(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	down := make(chan struct{})
	back := newGate(t)
	var calls atomic.Int32
	hook := func(armed bool) {
		if armed {
			return
		}
		switch calls.Add(1) {
		case 1:
			panic("the watcher fails")
		case 2:
			close(down)
			back.wait()
		}
	}
	svc.watchArmHook.Store(&hook)
	svc.nudgeWatcher()
	awaitClosed(t, down, "the supervisor to restart the watcher")
	dropTrack(t, lib, "Landed While The Watcher Was Down")
	back.release()
	waitForTitle(t, ctx, svc, "Landed While The Watcher Was Down")
	if !strings.Contains(logged.String(), "worker panicked") {
		t.Errorf("the watcher did not fail through the supervisor:\n%s", logged.String())
	}
}

// A root whose folder goes away under its watch, as an unmount does, is
// taken up again once it is back, and caught up: what landed before the
// watch was back is catalogued without a scheduled scan.
func TestARootWhoseWatchWasLostIsCaughtUpOnceBack(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := filepath.Join(t.TempDir(), "lib")
	if err := os.Mkdir(lib, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	pass := parkNextArm(t, svc)
	if err := os.Remove(lib); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, pass.parked, "the watcher to notice the lost watch")
	if err := os.Mkdir(lib, 0o755); err != nil {
		t.Fatal(err)
	}
	dropTrack(t, lib, "Landed Before The Watch Was Back")
	pass.release()
	waitForTitle(t, ctx, svc, "Landed Before The Watch Was Back")
}

// Two roots on one folder by two paths, as a symlinked parent or a bind
// mount gives, are watched once: the kernel lists the folder under the
// path that took it first, which is no lost watch, so the recheck neither
// walks the other again nor owes it a catch-up.
func TestTwoRootsOnOneFolderAreNotTakenUpOnEveryRecheck(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	first := filepath.Join(base, "real", "music")
	if err := os.MkdirAll(first, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(base, "real"), filepath.Join(base, "link")); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(base, "link", "music")
	_, svc := openWatched(t, []Root{{Name: "a", Path: first}, {Name: "b", Path: alias}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	var passes, walks atomic.Int32
	arm := func(armed bool) {
		if !armed {
			passes.Add(1)
		}
	}
	svc.watchArmHook.Store(&arm)
	look := func(stage, _ string) {
		if stage == "walk" {
			walks.Add(1)
		}
	}
	svc.watchLookHook.Store(&look)
	var mu sync.Mutex
	checked := map[string]int{}
	rechecked := make(chan struct{})
	var once sync.Once
	check := func(root string) {
		mu.Lock()
		defer mu.Unlock()
		checked[root]++
		if checked[first] >= 5 && checked[alias] >= 5 {
			once.Do(func() { close(rechecked) })
		}
	}
	svc.watchCheckHook.Store(&check)
	awaitClosed(t, rechecked, "five rechecks of both roots")
	if n := passes.Load(); n != 0 {
		t.Fatalf("%d passes over five rechecks with nothing changed, want none", n)
	}
	if n := walks.Load(); n != 0 {
		t.Fatalf("%d walks over five rechecks with nothing changed, want none", n)
	}
	for _, root := range []string{first, alias} {
		if _, owed := svc.watchQueue.owedSince(root); owed {
			t.Errorf("%s is owed a catch-up with nothing changed", root)
		}
	}
}

// Of two roots on one folder, the one whose path the kernel lists the folder
// under can leave the table while its walk is out. The walk can arm the
// folder again before the other root's walk reaches it, and its late answer
// lets go of that watch: the root left in the table is walked again, so its
// folder stays watched.
func TestARemovedRootsLateWalkLeavesItsAliasWatched(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	first := filepath.Join(base, "real", "music")
	if err := os.MkdirAll(first, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(base, "real"), filepath.Join(base, "link")); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(base, "link", "music")
	roots := []Root{{Name: "a", Path: first}, {Name: "b", Path: alias}}
	ctx, svc := openWatched(t, roots, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	// The kernel lists the folder under the path that took it first.
	holder, kept := roots[0], roots[1]
	if slices.Contains(w.WatchList(), alias) {
		holder, kept = kept, holder
	}
	// The removal is the watcher's table alone: a refresh from the catalog
	// would put the holder back.
	svc.refreshMu.Lock()
	t.Cleanup(svc.refreshMu.Unlock)

	walking := map[string]chan struct{}{holder.Path: make(chan struct{}), kept.Path: make(chan struct{})}
	walks := map[string]*gate{holder.Path: newGate(t), kept.Path: newGate(t)}
	var held sync.Map
	look := func(stage, path string) {
		if ch, ok := walking[path]; ok && stage == "walk" {
			if _, again := held.LoadOrStore(path, true); !again {
				close(ch)
				walks[path].wait()
			}
		}
	}
	svc.watchLookHook.Store(&look)
	// The pass that let go of the holder's watch is held at its end.
	var removed atomic.Bool
	parked, park := make(chan struct{}), newGate(t)
	var parkOnce sync.Once
	arm := func(armed bool) {
		if armed && removed.Load() && !slices.Contains(w.WatchList(), holder.Path) {
			parkOnce.Do(func() {
				close(parked)
				park.wait()
			})
		}
	}
	svc.watchArmHook.Store(&arm)
	var mu sync.Mutex
	answered := map[string]bool{}
	both := make(chan struct{})
	var bothOnce sync.Once
	check := func(root string) {
		mu.Lock()
		defer mu.Unlock()
		if removed.Load() {
			answered[root] = true
		}
		if answered[holder.Path] && answered[kept.Path] {
			bothOnce.Do(func() { close(both) })
		}
	}
	svc.watchCheckHook.Store(&check)

	// An overflow walks both roots again; both walks wait.
	w.Errors <- fsnotify.ErrEventOverflow
	awaitClosed(t, walking[holder.Path], "the holder's walk")
	awaitClosed(t, walking[kept.Path], "the other root's walk")
	removed.Store(true)
	setRoots(svc, []Root{kept})
	svc.nudgeWatcher()
	awaitClosed(t, parked, "the pass after the removal")
	// The holder's walk arms the folder again, then the other root's walk
	// finds it armed. A folder made in between is the one thing the second
	// walk arms under its own path, which says it has walked.
	walks[holder.Path].release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), holder.Path) }, "the holder's late walk to arm the folder")
	if err := os.Mkdir(filepath.Join(holder.Path, "zz"), 0o755); err != nil {
		t.Fatal(err)
	}
	walks[kept.Path].release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), filepath.Join(kept.Path, "zz")) },
		"the other root's walk to finish")
	park.release()
	awaitClosed(t, both, "both walks' answers")
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), kept.Path) }, "the root left in the table watched again")
	dropTrack(t, kept.Path, "Heard After Its Alias Left")
	waitForTitle(t, ctx, svc, "Heard After Its Alias Left")
}

// An alias whose first walk is still out when its holder leaves the table
// is walked again too: its walk may have found the folder in the watch the
// holder's removal lets go of. Here the alias's folder appears after the
// start, so its first walk comes while the holder is watched.
func TestAnAliasOnItsFirstWalkIsWatchedWhenItsHolderLeaves(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	first := filepath.Join(base, "real", "music")
	if err := os.MkdirAll(first, 0o755); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(base, "link", "music")
	holder, kept := Root{Name: "a", Path: first}, Root{Name: "b", Path: alias}
	ctx, svc := openWatched(t, []Root{holder, kept}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	if !slices.Contains(w.WatchList(), first) {
		t.Fatalf("the watch table is %v, want the holder's %s", w.WatchList(), first)
	}
	// The removal is the watcher's table alone: a refresh from the catalog
	// would put the holder back.
	svc.refreshMu.Lock()
	t.Cleanup(svc.refreshMu.Unlock)

	walking := make(chan struct{})
	walk := newGate(t)
	var walkOnce sync.Once
	look := func(stage, path string) {
		if stage == "walk" && path == alias {
			walkOnce.Do(func() {
				close(walking)
				walk.wait()
			})
		}
	}
	svc.watchLookHook.Store(&look)
	// The pass that sends the alias's first walk is let end; the next, after
	// the removal, is held before it lets go of anything.
	var removed atomic.Bool
	var ended atomic.Int32
	parked, park := make(chan struct{}), newGate(t)
	var parkOnce sync.Once
	arm := func(armed bool) {
		switch {
		case armed:
			select {
			case <-walking:
				ended.Add(1)
			default:
			}
		case removed.Load():
			parkOnce.Do(func() {
				close(parked)
				park.wait()
			})
		}
	}
	svc.watchArmHook.Store(&arm)

	// A recheck finds the alias's folder there and takes it up.
	if err := os.Symlink(filepath.Join(base, "real"), filepath.Join(base, "link")); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, walking, "the alias's first walk")
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the pass to stop waiting for the walk")
	removed.Store(true)
	setRoots(svc, []Root{kept})
	svc.nudgeWatcher()
	awaitClosed(t, parked, "the pass after the removal")
	// The alias's walk finds the folder in the holder's watch. A folder made
	// first is the one thing it arms under its own path, which says it has
	// walked.
	if err := os.Mkdir(filepath.Join(first, "zz"), 0o755); err != nil {
		t.Fatal(err)
	}
	walk.release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), filepath.Join(alias, "zz")) },
		"the alias's walk to finish")
	if list := w.WatchList(); !slices.Contains(list, first) || slices.Contains(list, alias) {
		t.Fatalf("the watch table is %v, want the folder still under the holder's path", list)
	}
	park.release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), alias) }, "the alias watched under its own path")
	dropTrack(t, alias, "Heard Through A New Alias")
	waitForTitle(t, ctx, svc, "Heard Through A New Alias")
}

// A folder inside a root that another root reaches by another path, as a
// root symlinked into it does, is listed under the path that armed it
// first; when that root leaves the table, the one whose folder it is gets
// walked again and keeps it watched.
func TestARootsFolderListedUnderAnotherRootStaysWatchedWhenThatRootLeaves(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	music := filepath.Join(base, "music")
	if err := os.MkdirAll(filepath.Join(music, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	inner := filepath.Join(base, "inner")
	if err := os.Symlink(filepath.Join(music, "sub"), inner); err != nil {
		t.Fatal(err)
	}
	// The outer root's folder appears after the start, so the inner root
	// has armed the folder they share first.
	outer := filepath.Join(base, "outer")
	whole, part := Root{Name: "whole", Path: outer}, Root{Name: "part", Path: inner}
	ctx, svc := openWatched(t, []Root{whole, part}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	w := svc.watcher.Load()
	if err := os.Symlink(music, outer); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), outer) }, "the outer root taken up")
	shared := filepath.Join(outer, "sub")
	if list := w.WatchList(); !slices.Contains(list, inner) || slices.Contains(list, shared) {
		t.Fatalf("the watch table is %v, want the shared folder under %s alone", list, inner)
	}
	// The removal is the watcher's table alone: a refresh from the catalog
	// would put the inner root back.
	svc.refreshMu.Lock()
	t.Cleanup(svc.refreshMu.Unlock)
	setRoots(svc, []Root{whole})
	svc.nudgeWatcher()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), shared) }, "the shared folder watched under the outer root")
	dropTrack(t, shared, "Heard In A Folder Once Shared")
	waitForTitle(t, ctx, svc, "Heard In A Folder Once Shared")
}

// A root whose folder stops answering, as a hard-mounted network share
// whose server is gone does, delays only itself: the other roots stay
// watched, and one whose watch is lost is caught up, while its stat hangs.
func TestARootThatStopsAnsweringLeavesTheOthersWatched(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := filepath.Join(t.TempDir(), "lib")
	if err := os.Mkdir(lib, 0o755); err != nil {
		t.Fatal(err)
	}
	hung := t.TempDir()
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}, {Name: "hung", Path: hung}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	asked := make(chan struct{})
	answers := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "stat" && path == hung {
			once.Do(func() { close(asked) })
			answers.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	awaitClosed(t, asked, "the watcher to look at the root that stops answering")
	dropTrack(t, lib, "Heard Beside A Hung Root")
	waitForTitle(t, ctx, svc, "Heard Beside A Hung Root")
	pass := parkNextArm(t, svc)
	if err := os.RemoveAll(lib); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, pass.parked, "the watcher to notice the lost watch beside the hung root")
	if err := os.Mkdir(lib, 0o755); err != nil {
		t.Fatal(err)
	}
	dropTrack(t, lib, "Caught Up Beside A Hung Root")
	pass.release()
	waitForTitle(t, ctx, svc, "Caught Up Beside A Hung Root")
}

// A directory inside a root whose watch the kernel drops while the folder
// stays, as the unmount of a mount point nested in the root does, owes
// its root a walk and a catch-up: what landed while it was not watched is
// catalogued, and it is watched again after.
func TestADirectoryThatLostItsWatchIsCaughtUpAndWatchedAgain(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	nas := filepath.Join(lib, "nas")
	if err := os.Mkdir(nas, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	walk := parkNextWalk(t, svc, lib)
	if err := svc.watcher.Load().Remove(nas); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, walk.parked, "the watcher to notice the lost watch inside the root")
	dropTrack(t, nas, "Landed While Unmounted")
	walk.release()
	waitForTitle(t, ctx, svc, "Landed While Unmounted")
	dropTrack(t, nas, "Landed Once Watched Again")
	waitForTitle(t, ctx, svc, "Landed Once Watched Again")
}

// rootCatchUps counts the catch-ups of root the watcher decides, each
// sent as whether it scanned.
func rootCatchUps(svc *Library, root string) chan bool {
	decided := make(chan bool, 16)
	svc.watchScanHook = func(dir string, scanned bool) {
		if dir == root {
			decided <- scanned
		}
	}
	return decided
}

// caughtUp waits for a catch-up of the root that scanned it.
func caughtUp(t *testing.T, decided <-chan bool, what string) {
	t.Helper()
	select {
	case scanned := <-decided:
		if !scanned {
			t.Fatalf("the root's catch-up %s was left to a catalog scan that did not run", what)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the root was never caught up " + what)
	}
}

// setRoots replaces the root table the watcher reads, as a create or a
// removal does.
func setRoots(svc *Library, roots []Root) {
	svc.rootsMu.Lock()
	svc.roots = roots
	svc.rootsMu.Unlock()
}

// The mount table under a root is read on every recheck (Linux): a first
// mount on a directory inside it, a remount there and its unmount raise
// no event, and each walks the root again and catches it up.
func TestAMountChangeUnderARootIsCaughtUp(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	nas := filepath.Join(lib, "nas")
	if err := os.Mkdir(nas, 0o755); err != nil {
		t.Fatal(err)
	}
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	decided := rootCatchUps(svc, lib)
	var mu sync.Mutex
	table := ""
	read := func() (string, error) {
		mu.Lock()
		defer mu.Unlock()
		return table, nil
	}
	svc.watchMountsHook.Store(&read)
	mount := func(id int) string {
		return fmt.Sprintf("%d 1 0:%d / %s rw,relatime - tmpfs tmpfs rw\n", id, id, strings.ReplaceAll(nas, " ", `\040`))
	}
	for _, step := range []struct{ what, table string }{
		{"a first mount", mount(100)},
		{"a remount", mount(101)},
		{"an unmount", ""},
	} {
		walk := parkNextWalk(t, svc, lib)
		mu.Lock()
		table = step.table
		mu.Unlock()
		awaitClosed(t, walk.parked, "the watcher to notice "+step.what)
		walk.release()
		caughtUp(t, decided, "after "+step.what)
	}
}

// A directory renamed inside a root, moved to another root, or moved out
// of every root leaves nothing watched under its old path; inside a root
// it ends watched under its new path, subdirectories included, so what
// lands there is catalogued.
func TestARenamedDirectoryIsWatchedUnderItsNewPathAlone(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, other, outside := t.TempDir(), t.TempDir(), t.TempDir()
	a := filepath.Join(lib, "a")
	if err := os.MkdirAll(filepath.Join(a, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}, {Name: "other", Path: other}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	w := svc.watcher.Load()
	checked := make(chan struct{}, 256)
	check := func(root string) {
		if root == other {
			select {
			case checked <- struct{}{}:
			default:
			}
		}
	}
	svc.watchCheckHook.Store(&check)
	watchedAt := func(from, to string) func() bool {
		return func() bool {
			list := w.WatchList()
			if slices.ContainsFunc(list, func(p string) bool { return underRoot(p, from) }) {
				return false
			}
			return to == "" || (slices.Contains(list, to) && slices.Contains(list, filepath.Join(to, "x")))
		}
	}
	b := filepath.Join(lib, "b")
	if err := os.Rename(a, b); err != nil {
		t.Fatal(err)
	}
	waitFor(t, watchedAt(a, b), "the renamed directory watched under its new path alone")
	dropTrack(t, filepath.Join(b, "x"), "Landed Under The New Name")
	waitForTitle(t, ctx, svc, "Landed Under The New Name")
	dropTrack(t, b, "Landed In The Renamed Directory")
	waitForTitle(t, ctx, svc, "Landed In The Renamed Directory")
	moved := filepath.Join(other, "b")
	if err := os.Rename(b, moved); err != nil {
		t.Fatal(err)
	}
	waitFor(t, watchedAt(b, moved), "the directory moved to another root watched there alone")
	dropTrack(t, filepath.Join(moved, "x"), "Landed In The Other Root")
	waitForTitle(t, ctx, svc, "Landed In The Other Root")
	// Two looks at the other root answered after it holds the directory:
	// the second was sent out once the table listed it.
	drain(checked)
	for range 2 {
		select {
		case <-checked:
		case <-time.After(10 * time.Second):
			t.Fatal("timed out waiting for a look at the other root")
		}
	}
	if err := os.Rename(moved, filepath.Join(outside, "b")); err != nil {
		t.Fatal(err)
	}
	waitFor(t, watchedAt(moved, ""), "the directory moved out of every root watched nowhere")
}

// A directory recreated at the path of one that lost its watch, again and
// again, is armed by each create and settles: the rechecks in between do
// not walk the root again.
func TestADirectoryRecreatedAfterALostWatchSettles(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	nas := filepath.Join(lib, "nas")
	if err := os.Mkdir(nas, 0o755); err != nil {
		t.Fatal(err)
	}
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	decided := rootCatchUps(svc, lib)
	w := svc.watcher.Load()
	if err := w.Remove(nas); err != nil {
		t.Fatal(err)
	}
	caughtUp(t, decided, "after the lost watch")
	var walks atomic.Int32
	look := func(stage, path string) {
		if stage == "walk" && path == lib {
			walks.Add(1)
		}
	}
	svc.watchLookHook.Store(&look)
	checked := make(chan struct{}, 64)
	check := func(root string) {
		if root == lib {
			checked <- struct{}{}
		}
	}
	svc.watchCheckHook.Store(&check)
	for range 5 {
		if err := os.Remove(nas); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(nas, 0o755); err != nil {
			t.Fatal(err)
		}
		waitFor(t, func() bool { return slices.Contains(w.WatchList(), nas) }, "the recreated directory to be armed")
		// The second look in after the arm is one sent out after it.
		for range 2 {
			select {
			case <-checked:
			case <-time.After(10 * time.Second):
				t.Fatal("timed out waiting for a recheck of the root")
			}
		}
	}
	// A recheck already out when the directory came back may walk once.
	if n := walks.Load(); n > 1 {
		t.Fatalf("%d walks over five recreates, want at most one", n)
	}
}

// The loop never looks at what is created: a created directory whose
// look hangs holds only its own root's creates, and a drop in another
// root is catalogued meanwhile.
func TestACreateThatHangsLeavesTheOtherRootsWatched(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	slow, lib := t.TempDir(), t.TempDir()
	ctx, svc := openWatched(t, []Root{{Name: "slow", Path: slow}, {Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	created := filepath.Join(slow, "new")
	asked := make(chan struct{})
	answer := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "arm" && path == created {
			once.Do(func() { close(asked) })
			answer.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	if err := os.Mkdir(created, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, asked, "the watcher to look at the created directory")
	dropTrack(t, lib, "Heard While A Create Hangs")
	waitForTitle(t, ctx, svc, "Heard While A Create Hangs")
	answer.release()
	waitFor(t, func() bool { return slices.Contains(svc.watcher.Load().WatchList(), created) },
		"the created directory to be armed once it answered")
	dropTrack(t, created, "Heard Once The Create Answered")
	waitForTitle(t, ctx, svc, "Heard Once The Create Answered")
}

// A root that leaves the table while its walk is out lets go, once the
// walk answers, of every watch the walk added: none survives the removal.
func TestAWalkRacingItsRootsRemovalLeavesNoWatch(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	gone := t.TempDir()
	if err := os.Mkdir(filepath.Join(gone, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	walking := make(chan struct{})
	walk := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "walk" && path == gone {
			once.Do(func() { close(walking) })
			walk.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	var ended atomic.Int32
	arm := func(armed bool) {
		if armed {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&arm)
	answered := make(chan struct{})
	var answeredOnce sync.Once
	check := func(root string) {
		if root == gone {
			answeredOnce.Do(func() { close(answered) })
		}
	}
	svc.watchCheckHook.Store(&check)
	setRoots(svc, []Root{{Name: "lib", Path: lib}, {Name: "gone", Path: gone}})
	svc.nudgeWatcher()
	awaitClosed(t, walking, "the watcher to walk the added root")
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the pass to stop waiting for the walk")
	setRoots(svc, []Root{{Name: "lib", Path: lib}})
	svc.nudgeWatcher()
	waitFor(t, func() bool { return ended.Load() >= 2 }, "the pass after the removal")
	walk.release()
	awaitClosed(t, answered, "the watcher to take the walk's late answer in")
	if stray := slices.DeleteFunc(svc.watcher.Load().WatchList(), func(p string) bool { return !underRoot(p, gone) }); len(stray) > 0 {
		t.Fatalf("watches %v survived their root's removal", stray)
	}
}

// A pass says a root does not answer only when its stat has not: a walk
// that outlasts the pass's wait is no silence.
func TestOnlyARootWhoseStatHangsIsSaidNotToAnswer(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	slow, hung := t.TempDir(), t.TempDir()
	walking, statting := make(chan struct{}), make(chan struct{})
	walk, stat := newGate(t), newGate(t)
	var walkOnce, statOnce sync.Once
	look := func(stage, path string) {
		switch {
		case stage == "walk" && path == slow:
			walkOnce.Do(func() { close(walking) })
			walk.wait()
		case stage == "stat" && path == hung:
			statOnce.Do(func() { close(statting) })
			stat.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	var ended atomic.Int32
	arm := func(armed bool) {
		if armed {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&arm)
	setRoots(svc, []Root{{Name: "lib", Path: lib}, {Name: "slow", Path: slow}, {Name: "hung", Path: hung}})
	svc.nudgeWatcher()
	awaitClosed(t, walking, "the watcher to walk the slow root")
	awaitClosed(t, statting, "the watcher to look at the hung root")
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the pass to stop waiting")
	said := func(path string) bool {
		return slices.ContainsFunc(strings.Split(logged.String(), "\n"), func(line string) bool {
			return strings.Contains(line, "not answer") && strings.Contains(line, "path="+path)
		})
	}
	if said(slow) {
		t.Errorf("a slow walk was said not to answer:\n%s", logged.String())
	}
	if !said(hung) {
		t.Errorf("the root whose stat hangs was not said to stop answering:\n%s", logged.String())
	}
}

// drain empties ch of what it holds now.
func drain(ch chan struct{}) {
	for {
		select {
		case <-ch:
		default:
			return
		}
	}
}

// An overflow walks every root again, letting go first of the watches
// whose path no longer holds a directory: a rename the lost events never
// reported leaves no stale path behind, and its directory ends watched
// under its new path.
func TestAnOverflowLetsGoOfPathsRenamedInTheGap(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	a := filepath.Join(lib, "a")
	if err := os.MkdirAll(filepath.Join(a, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	w := svc.watcher.Load()
	// No event reports the rename: only a/x keeps its watch, under the
	// path it had.
	for _, p := range []string{a, lib} {
		if err := w.Remove(p); err != nil {
			t.Fatal(err)
		}
	}
	b := filepath.Join(lib, "b")
	if err := os.Rename(a, b); err != nil {
		t.Fatal(err)
	}
	w.Errors <- fsnotify.ErrEventOverflow
	waitFor(t, func() bool {
		list := w.WatchList()
		return !slices.ContainsFunc(list, func(p string) bool { return underRoot(p, a) }) &&
			slices.Contains(list, b) && slices.Contains(list, filepath.Join(b, "x"))
	}, "the renamed directory watched under its new path alone after the overflow")
	dropTrack(t, filepath.Join(b, "x"), "Landed After The Overflow")
	waitForTitle(t, ctx, svc, "Landed After The Overflow")
}

// An overflow walks every root again, one whose look was out as it came
// included: that root is walked again once its look answers, so a rename
// the lost events never reported leaves no stale path under it.
func TestAnOverflowWalksAgainARootWhoseLookWasOut(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	a := filepath.Join(lib, "a")
	if err := os.MkdirAll(filepath.Join(a, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	// No recheck: the look out is a create's, held at its arm.
	_, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	created := filepath.Join(lib, "c")
	arming := make(chan struct{})
	arm := newGate(t)
	var armOnce sync.Once
	look := func(stage, path string) {
		if stage == "arm" && path == created {
			armOnce.Do(func() {
				close(arming)
				arm.wait()
			})
		}
	}
	svc.watchLookHook.Store(&look)
	var overflowed atomic.Bool
	var ended atomic.Int32
	hook := func(armed bool) {
		if armed && overflowed.Load() {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&hook)
	if err := os.Mkdir(created, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, arming, "the create's arm")
	// No event reports the rename: only a/x keeps its watch, under the
	// path it had.
	for _, p := range []string{a, lib} {
		if err := w.Remove(p); err != nil {
			t.Fatal(err)
		}
	}
	b := filepath.Join(lib, "b")
	if err := os.Rename(a, b); err != nil {
		t.Fatal(err)
	}
	overflowed.Store(true)
	w.Errors <- fsnotify.ErrEventOverflow
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the overflow's pass to end")
	arm.release()
	waitFor(t, func() bool {
		list := w.WatchList()
		return !slices.ContainsFunc(list, func(p string) bool { return underRoot(p, a) }) &&
			slices.Contains(list, lib) && slices.Contains(list, b) && slices.Contains(list, filepath.Join(b, "x"))
	}, "the root walked again once its look answered")
}

// The re-walk an overflow owes a root it passed over is paid by the
// answer of the look that was out, before the creates queued behind that
// look go out: a create queued meanwhile neither strands the debt nor is
// lost, and the root is walked once, by a look of its own, with no pass.
func TestAnOverflowsOwedWalkIsPaidWhenItsLookAnswersWithACreateQueued(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	p := filepath.Join(lib, "p")
	if err := os.Mkdir(p, 0o755); err != nil {
		t.Fatal(err)
	}
	// No recheck: only the look's answer can pay.
	_, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	first, second := filepath.Join(lib, "c"), filepath.Join(lib, "d")
	arming, queued := make(chan struct{}), make(chan struct{})
	arm := newGate(t)
	var armOnce, queueOnce sync.Once
	var overflowed atomic.Bool
	var walks atomic.Int32
	look := func(stage, path string) {
		switch {
		case stage == "arm" && path == first:
			armOnce.Do(func() {
				close(arming)
				arm.wait()
			})
		case stage == "queue" && path == second:
			queueOnce.Do(func() { close(queued) })
		case stage == "walk" && path == lib && overflowed.Load():
			walks.Add(1)
		}
	}
	svc.watchLookHook.Store(&look)
	var ended atomic.Int32
	hook := func(armed bool) {
		if armed && overflowed.Load() {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&hook)
	var checked atomic.Int32
	check := func(root string) {
		if root == lib {
			checked.Add(1)
		}
	}
	svc.watchCheckHook.Store(&check)
	if err := os.Mkdir(first, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, arming, "the create's arm")
	// Born in the gap: p's watch is let go first, so its create raises
	// nothing; only a walk arms it.
	if err := w.Remove(p); err != nil {
		t.Fatal(err)
	}
	gap := filepath.Join(p, "gap")
	if err := os.Mkdir(gap, 0o755); err != nil {
		t.Fatal(err)
	}
	overflowed.Store(true)
	w.Errors <- fsnotify.ErrEventOverflow
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the overflow's pass to end")
	if err := os.Mkdir(second, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, queued, "the second create to queue behind the arm out")
	arm.release()
	// The arm's answer sends the root its walk, which takes the queued
	// create along: their two answers are the root's last.
	waitFor(t, func() bool { return checked.Load() >= 2 }, "the root walked again once its look answered")
	if list := w.WatchList(); !slices.Contains(list, gap) || !slices.Contains(list, second) {
		t.Fatalf("the watch table is %v, want the folder born in the gap and the queued create", list)
	}
	if n := ended.Load(); n != 1 {
		t.Fatalf("%d passes after the overflow, want its own alone", n)
	}
	// A pass that finds the root idle walks it only if it is still owed.
	svc.nudgeWatcher()
	waitFor(t, func() bool { return checked.Load() >= 3 }, "a pass to look at the root")
	if n := walks.Load(); n != 1 {
		t.Fatalf("the root walked %d times after the overflow, want once", n)
	}
}

// The re-walk an overflow owes a root is a look of the root's own, sent by
// the answer of the look that was out: no other root's look is waited on,
// so a second root whose stat is slow holds up no create the loop takes
// meanwhile, and the root is walked once.
func TestAnOverflowsOwedWalkWaitsOnNoOtherRoot(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, slow := t.TempDir(), t.TempDir()
	p := filepath.Join(lib, "p")
	if err := os.Mkdir(p, 0o755); err != nil {
		t.Fatal(err)
	}
	// No recheck: only the look's answer can pay.
	_, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}, {Name: "slow", Path: slow}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	// A pass waits for the slow root longer than the test waits for a create.
	svc.watchLookWait.Store(int64(time.Minute))
	w := svc.watcher.Load()
	first, next := filepath.Join(lib, "c"), filepath.Join(lib, "d")
	arming, walking, queued := make(chan struct{}), make(chan struct{}), make(chan struct{})
	arm, stat := newGate(t), newGate(t)
	var armOnce, walkOnce, queueOnce sync.Once
	var overflowed, slowed atomic.Bool
	var walks atomic.Int32
	look := func(stage, path string) {
		switch {
		case stage == "arm" && path == first:
			armOnce.Do(func() {
				close(arming)
				arm.wait()
			})
		case stage == "stat" && path == slow && slowed.Load():
			stat.wait()
		case stage == "walk" && path == lib && overflowed.Load():
			walks.Add(1)
			walkOnce.Do(func() { close(walking) })
		case stage == "queue" && path == next:
			queueOnce.Do(func() { close(queued) })
		}
	}
	svc.watchLookHook.Store(&look)
	var ended atomic.Int32
	hook := func(armed bool) {
		if armed && overflowed.Load() {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&hook)
	var checked atomic.Int32
	check := func(root string) {
		if root == lib {
			checked.Add(1)
		}
	}
	svc.watchCheckHook.Store(&check)
	if err := os.Mkdir(first, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, arming, "the create's arm")
	// Born in the gap: p's watch is let go first, so its create raises
	// nothing; only a walk arms it.
	if err := w.Remove(p); err != nil {
		t.Fatal(err)
	}
	gap := filepath.Join(p, "gap")
	if err := os.Mkdir(gap, 0o755); err != nil {
		t.Fatal(err)
	}
	overflowed.Store(true)
	w.Errors <- fsnotify.ErrEventOverflow
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the overflow's pass to end")
	slowed.Store(true)
	arm.release()
	awaitClosed(t, walking, "the owed walk of the root")
	if err := os.Mkdir(next, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, queued, "the next create to be taken while the slow root's stat is held")
	stat.release()
	// The arm's, the walk's and the next create's answers are the root's
	// last; a pass that then finds it idle walks it only if it is owed.
	waitFor(t, func() bool {
		list := w.WatchList()
		return checked.Load() >= 3 && slices.Contains(list, gap) && slices.Contains(list, next)
	}, "the root walked again and the next create armed")
	svc.nudgeWatcher()
	waitFor(t, func() bool { return checked.Load() >= 4 }, "a pass to look at the root")
	if n := walks.Load(); n != 1 {
		t.Fatalf("the root walked %d times after the overflow, want once", n)
	}
}

// The re-walk owed a root an overflow passed over may come after the
// overflow's catch-up of that root ran: it owes the root a catch-up of its
// own, so a file that landed between the two in a folder born in the gap
// is scanned.
func TestAnOverflowsOwedWalkOwesItsCatchUp(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	p := filepath.Join(lib, "p")
	if err := os.Mkdir(p, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	scanned := make(chan struct{}, 16)
	svc.watchScanHook = func(dir string, did bool) {
		if dir == lib && did {
			select {
			case scanned <- struct{}{}:
			default:
			}
		}
	}
	created := filepath.Join(lib, "c")
	arming := make(chan struct{})
	arm := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "arm" && path == created {
			once.Do(func() {
				close(arming)
				arm.wait()
			})
		}
	}
	svc.watchLookHook.Store(&look)
	var overflowed atomic.Bool
	var ended atomic.Int32
	hook := func(armed bool) {
		if armed && overflowed.Load() {
			ended.Add(1)
		}
	}
	svc.watchArmHook.Store(&hook)
	if err := os.Mkdir(created, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, arming, "the create's arm")
	// Born in the gap: p's watch is let go first, so its create raises
	// nothing; only a walk arms it.
	if err := w.Remove(p); err != nil {
		t.Fatal(err)
	}
	gap := filepath.Join(p, "gap")
	if err := os.Mkdir(gap, 0o755); err != nil {
		t.Fatal(err)
	}
	overflowed.Store(true)
	w.Errors <- fsnotify.ErrEventOverflow
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the overflow's pass to end")
	// The overflow's catch-up of the root runs with the look still out.
	awaitClosed(t, scanned, "the overflow's catch-up of the root")
	dropTrack(t, gap, "Landed Between The Catch Up And The Walk")
	arm.release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), gap) },
		"the owed walk to arm the folder born in the gap")
	waitForTitle(t, ctx, svc, "Landed Between The Catch Up And The Walk")
}

// The overflow pass's own walk of a root may outlast the settle window of
// the overflow's catch-up: it owes the root a catch-up of its own, so a
// file that landed in a folder born in the gap after that scan started is
// scanned.
func TestAnOverflowsWalkOutlastingItsCatchUpOwesAnother(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib := t.TempDir()
	p := filepath.Join(lib, "p")
	if err := os.Mkdir(p, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	scanned := make(chan struct{}, 16)
	svc.watchScanHook = func(dir string, did bool) {
		if dir == lib && did {
			select {
			case scanned <- struct{}{}:
			default:
			}
		}
	}
	walking := make(chan struct{})
	walk := newGate(t)
	var once sync.Once
	var overflowed atomic.Bool
	look := func(stage, path string) {
		if stage == "walk" && path == lib && overflowed.Load() {
			once.Do(func() {
				close(walking)
				walk.wait()
			})
		}
	}
	svc.watchLookHook.Store(&look)
	// Born in the gap: p's watch is let go first, so its create raises
	// nothing; only a walk arms it.
	if err := w.Remove(p); err != nil {
		t.Fatal(err)
	}
	gap := filepath.Join(p, "gap")
	if err := os.Mkdir(gap, 0o755); err != nil {
		t.Fatal(err)
	}
	overflowed.Store(true)
	w.Errors <- fsnotify.ErrEventOverflow
	awaitClosed(t, walking, "the overflow's walk of the root")
	// The pass stops waiting for the walk; the overflow's catch-up of the
	// root runs with the walk still out.
	awaitClosed(t, scanned, "the overflow's catch-up of the root")
	dropTrack(t, gap, "Landed While The Walk Was Out")
	walk.release()
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), gap) },
		"the walk to arm the folder born in the gap")
	waitForTitle(t, ctx, svc, "Landed While The Walk Was Out")
}

// returns fails the test when f does not return in time: the watcher
// deadlocked.
func returns(t *testing.T, what string, f func()) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		defer close(done)
		f()
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal(what + " never returned: the watcher deadlocked")
	}
}

// A watched directory moved out of every root and deleted while the loop
// is busy makes fsnotify's reader err under its own lock (its
// inotify_rm_watch finds the watch gone). The error is drained off the
// loop, so the loop's table calls and the watcher's Close still return,
// and no catch-up is owed for it.
func TestAMoveOutAndDeleteWithTheLoopBusyDoesNotDeadlock(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, outside := t.TempDir(), t.TempDir()
	a := filepath.Join(lib, "a")
	if err := os.MkdirAll(filepath.Join(a, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	w := svc.watcher.Load()
	dropping := make(chan struct{})
	drop := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "drop" && path == a {
			once.Do(func() { close(dropping) })
			drop.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	// The loop is busy in a pass while the directory leaves and goes.
	pass := parkNextArm(t, svc)
	svc.nudgeWatcher()
	awaitClosed(t, pass.parked, "the loop to be busy")
	moved := filepath.Join(outside, "a")
	if err := os.Rename(a, moved); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(moved); err != nil {
		t.Fatal(err)
	}
	pass.release()
	awaitClosed(t, dropping, "the loop to take the move in")
	// fsnotify's reader goes on to the move's MOVE_SELF, whose
	// inotify_rm_watch fails, and errs holding its lock.
	waitFor(t, func() bool { return strings.Contains(logged.String(), "filesystem watcher error") },
		"the watcher's error to be drained")
	drop.release()
	returns(t, "the watch table", func() {
		waitFor(t, func() bool {
			return !slices.ContainsFunc(w.WatchList(), func(p string) bool { return underRoot(p, a) })
		}, "the moved directory's watches to go")
	})
	if strings.Contains(logged.String(), "filesystem events dropped") {
		t.Errorf("a watcher error that is no overflow cost a catch-up:\n%s", logged.String())
	}
	returns(t, "closing the watcher", func() { w.Close() })
}

// A library whose path is a symlink to its folder is watched: its walk
// descends the folder the link names, and the table keeps the library's
// own paths, so what lands under it is scanned.
func TestARootThatIsASymlinkIsWatched(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	if err := os.MkdirAll(filepath.Join(base, "real", "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "link")
	if err := os.Symlink(filepath.Join(base, "real"), link); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: link}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	list := svc.watcher.Load().WatchList()
	if !slices.Contains(list, link) || !slices.Contains(list, filepath.Join(link, "sub")) {
		t.Fatalf("the watch table is %v, want the library's folder and its sub under %s", list, link)
	}
	dropTrack(t, filepath.Join(link, "sub"), "Heard Through The Link")
	waitForTitle(t, ctx, svc, "Heard Through The Link")
}

// A library whose symlink is pointed at another folder is walked again
// there and caught up, and the watches on the old folder go.
func TestARetargetedRootSymlinkIsWalkedAgainAndCaughtUp(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	base := t.TempDir()
	one, two := filepath.Join(base, "one"), filepath.Join(base, "two")
	for _, dir := range []string{filepath.Join(one, "sub"), filepath.Join(two, "other")} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	link := filepath.Join(base, "link")
	if err := os.Symlink(one, link); err != nil {
		t.Fatal(err)
	}
	_, svc := openWatched(t, []Root{{Name: "lib", Path: link}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	decided := rootCatchUps(svc, link)
	walk := parkNextWalk(t, svc, link)
	next := filepath.Join(base, "link.next")
	if err := os.Symlink(two, next); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(next, link); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, walk.parked, "the watcher to notice the link retargeted")
	walk.release()
	caughtUp(t, decided, "after the retarget")
	list := svc.watcher.Load().WatchList()
	if !slices.Contains(list, filepath.Join(link, "other")) || slices.Contains(list, filepath.Join(link, "sub")) {
		t.Fatalf("the watch table is %v, want the new folder's other and not the old one's sub", list)
	}
}

// A directory armed since the last recheck and moved out of every root
// leaves nothing under its old path, even when fsnotify let go of its own
// watch first: the arm told the loop it was a directory.
func TestADirectoryArmedSinceTheLastRecheckLeavesNoWatchWhenMovedOut(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, outside := t.TempDir(), t.TempDir()
	// No recheck runs in this test: only the pass and the arms say what
	// the table held.
	_, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	w := svc.watcher.Load()
	armed := make(chan struct{}, 16)
	check := func(root string) {
		if root == lib {
			armed <- struct{}{}
		}
	}
	svc.watchCheckHook.Store(&check)
	n := filepath.Join(lib, "n")
	if err := os.MkdirAll(filepath.Join(n, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return slices.Contains(w.WatchList(), filepath.Join(n, "x")) }, "the new directory to be armed")
	select {
	case <-armed:
	case <-time.After(10 * time.Second):
		t.Fatal("timed out waiting for the arm's answer")
	}
	dropping := make(chan struct{})
	drop := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "drop" && path == n {
			once.Do(func() { close(dropping) })
			drop.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	if err := os.Rename(n, filepath.Join(outside, "n")); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, dropping, "the loop to take the move in")
	// fsnotify's MOVE_SELF lets go of the directory's own watch first.
	waitFor(t, func() bool { return !slices.Contains(w.WatchList(), n) }, "fsnotify to let go of the moved directory")
	drop.release()
	waitFor(t, func() bool {
		return !slices.ContainsFunc(w.WatchList(), func(p string) bool { return underRoot(p, n) })
	}, "the moved directory's subtree to leave the table")
}

// A directory a pass's walk armed after the pass stopped waiting, moved out
// of every root before the next recheck, leaves nothing under its old path
// either: the walk's late answer told the loop what it armed. Here the
// walk is of a root whose folder came back, as a drive mounted late is.
func TestADirectoryALateWalkArmedLeavesNoWatchWhenMovedOut(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, base, outside := t.TempDir(), t.TempDir(), t.TempDir()
	later := filepath.Join(base, "later")
	// No recheck runs in this test: only the passes and the late answer say
	// what the table held.
	_, svc := openWatchedEvery(t, []Root{{Name: "lib", Path: lib}, {Name: "later", Path: later}}, &logged, time.Hour)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	w := svc.watcher.Load()
	walking, dropping := make(chan struct{}), make(chan struct{})
	walk, drop := newGate(t), newGate(t)
	n := filepath.Join(later, "n")
	var walkOnce, dropOnce sync.Once
	look := func(stage, path string) {
		switch {
		case stage == "walk" && path == later:
			walkOnce.Do(func() { close(walking) })
			walk.wait()
		case stage == "drop" && path == n:
			dropOnce.Do(func() { close(dropping) })
			drop.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	// Only a pass that ends with the walk held counts.
	var ended atomic.Int32
	arm := func(armed bool) {
		select {
		case <-walking:
			if armed {
				ended.Add(1)
			}
		default:
		}
	}
	svc.watchArmHook.Store(&arm)
	answered := make(chan struct{})
	var answeredOnce sync.Once
	check := func(root string) {
		if root == later {
			answeredOnce.Do(func() { close(answered) })
		}
	}
	svc.watchCheckHook.Store(&check)
	if err := os.MkdirAll(filepath.Join(n, "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	svc.nudgeWatcher()
	awaitClosed(t, walking, "the watcher to walk the root that came back")
	waitFor(t, func() bool { return ended.Load() >= 1 }, "the pass to stop waiting for the walk")
	walk.release()
	awaitClosed(t, answered, "the watcher to take the walk's late answer in")
	if !slices.Contains(w.WatchList(), filepath.Join(n, "x")) {
		t.Fatalf("the watch table is %v, want the late walk's %s", w.WatchList(), filepath.Join(n, "x"))
	}
	if err := os.Rename(n, filepath.Join(outside, "n")); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, dropping, "the loop to take the move in")
	// fsnotify's MOVE_SELF lets go of the directory's own watch first.
	waitFor(t, func() bool { return !slices.Contains(w.WatchList(), n) }, "fsnotify to let go of the moved directory")
	drop.release()
	waitFor(t, func() bool {
		return !slices.ContainsFunc(w.WatchList(), func(p string) bool { return underRoot(p, n) })
	}, "the moved directory's subtree to leave the table")
}

// An overflow's re-walk of each root looks at that root's paths only: a
// root that hangs holds its own look, and the others still arm what is
// created in them.
func TestAnOverflowReWalkOfAHungRootStallsOnlyItself(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, hung := t.TempDir(), t.TempDir()
	if err := os.Mkdir(filepath.Join(hung, "deep"), 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: lib}, {Name: "hung", Path: hung}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	asked := make(chan struct{})
	answer := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "prune" && underRoot(path, hung) {
			once.Do(func() { close(asked) })
			answer.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	svc.watcher.Load().Errors <- fsnotify.ErrEventOverflow
	awaitClosed(t, asked, "the re-walk to look at the hung root")
	created := filepath.Join(lib, "new")
	if err := os.Mkdir(created, 0o755); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return slices.Contains(svc.watcher.Load().WatchList(), created) },
		"the other root to arm what is created in it")
	dropTrack(t, created, "Heard Beside A Hung Re-walk")
	waitForTitle(t, ctx, svc, "Heard Beside A Hung Re-walk")
}

// A root that hangs while arming a created directory is said not to
// answer, as one whose stat hangs is.
func TestARootThatHangsWhileArmingIsSaidNotToAnswer(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	lib, slow := t.TempDir(), t.TempDir()
	_, svc := openWatched(t, []Root{{Name: "lib", Path: lib}, {Name: "slow", Path: slow}}, &logged)
	awaitClosed(t, svc.watchReady, "the watcher to arm")
	svc.watchLookWait.Store(int64(50 * time.Millisecond))
	created := filepath.Join(slow, "new")
	asked := make(chan struct{})
	answer := newGate(t)
	var once sync.Once
	look := func(stage, path string) {
		if stage == "arm" && path == created {
			once.Do(func() { close(asked) })
			answer.wait()
		}
	}
	svc.watchLookHook.Store(&look)
	if err := os.Mkdir(created, 0o755); err != nil {
		t.Fatal(err)
	}
	awaitClosed(t, asked, "the watcher to arm the created directory")
	waitFor(t, func() bool {
		svc.nudgeWatcher()
		return slices.ContainsFunc(strings.Split(logged.String(), "\n"), func(line string) bool {
			return strings.Contains(line, "not answer") && strings.Contains(line, "path="+slow)
		})
	}, "the root that hangs while arming to be said not to answer")
}
