package service

import (
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// A library whose create started its scan is left to that scan when the
// watcher takes it up: the watcher does not walk it a second time.
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
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "added", Path: added})
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
