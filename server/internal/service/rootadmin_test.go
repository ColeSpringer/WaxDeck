package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// fakeFlowRoots stands in for the bridge: it records what the service
// taught it and answers the reload however the test needs.
type fakeFlowRoots struct {
	names   []string
	syncErr error

	synced []Root
}

func (f *fakeFlowRoots) RootNames() []string { return f.names }

func (f *fakeFlowRoots) SyncRoot(_ context.Context, name, path string) error {
	f.synced = append(f.synced, Root{Name: name, Path: path})
	if f.syncErr == nil {
		f.names = append(f.names, name)
	}
	return f.syncErr
}

// libraryCreateDetail returns the streamingWarning recorded on the most
// recent library.create audit entry, empty when there is none.
func libraryCreateDetail(t *testing.T, ctx context.Context, svc *Library) string {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.create"}, "", 10)
	if err != nil {
		t.Fatalf("reading the audit log: %v", err)
	}
	if len(page.Events) == 0 {
		t.Fatal("no library.create audit entry")
	}
	warn, _ := page.Events[0].Detail["streamingWarning"].(string)
	return warn
}

// TestAddLibrarySyncsFlowRoot pins the sync a runtime library depends
// on: the streaming side is told the new root by name and path, and a
// library that synced cleanly carries no warning.
func TestAddLibrarySyncsFlowRoot(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	flow := &fakeFlowRoots{names: []string{"lib"}}
	svc.SetFlowRoots(flow)

	dir := t.TempDir()
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir})
	if err != nil {
		t.Fatalf("AddLibrary: %v", err)
	}
	if lib.Name != "books" {
		t.Errorf("name = %q, want books", lib.Name)
	}
	if len(flow.synced) != 1 || flow.synced[0].Name != "books" || flow.synced[0].Path != dir {
		t.Errorf("synced roots = %v, want the new root by name and path", flow.synced)
	}
	if warn := libraryCreateDetail(t, ctx, svc); warn != "" {
		t.Errorf("streamingWarning = %q, want none on a successful sync", warn)
	}
}

// TestAddLibraryDegradesOnReloadFailure pins the degrade rule: the
// sidecar opens each root while reconciling, so a path it cannot see
// fails the reload -- and that has to leave the library created (nothing
// but streaming depended on the sidecar) while telling the administrator
// who made the change what has to happen for streaming to follow.
func TestAddLibraryDegradesOnReloadFailure(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	flow := &fakeFlowRoots{
		names:   []string{"lib"},
		syncErr: errors.New("roots reload refused (400 Bad Request): invalid-request: opening root books"),
	}
	svc.SetFlowRoots(flow)

	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
		t.Fatalf("AddLibrary must succeed despite a failed reload, got %v", err)
	}
	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var found bool
	for _, l := range libs {
		if l.Name == "books" {
			found = true
		}
	}
	if !found {
		t.Error("the library was not created; a failed reload must not roll it back")
	}
	warn := libraryCreateDetail(t, ctx, svc)
	if !strings.Contains(warn, "opening root books") {
		t.Errorf("streamingWarning = %q, want the sidecar's reason recorded for the admin", warn)
	}
}

// TestAddLibraryWithoutReloadSupport covers an env-configured or older
// sidecar: the library is still created, and the recorded warning names
// the restart streaming waits on.
func TestAddLibraryWithoutReloadSupport(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	flow := &fakeFlowRoots{
		names:   []string{"lib"},
		syncErr: errors.New("the sidecar at http://waxflow:4418 does not serve root reloads, so it has to be restarted with this root to stream from it"),
	}
	svc.SetFlowRoots(flow)

	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
		t.Fatalf("AddLibrary: %v", err)
	}
	if warn := libraryCreateDetail(t, ctx, svc); !strings.Contains(warn, "restarted") {
		t.Errorf("streamingWarning = %q, want the restart requirement recorded", warn)
	}
}

// TestAddLibraryRefusesBridgeRootName is the widened collision check.
// The podcast download dir is a bridge root and never enters the
// service's library table, so a library named after it used to pass the
// table-only check and then shadow the sidecar's podcast root, making
// stream-ref resolution ambiguous -- the exact thing the check exists
// for.
func TestAddLibraryRefusesBridgeRootName(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	svc.SetFlowRoots(&fakeFlowRoots{names: []string{"lib", "podcasts"}})

	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "podcasts", Path: t.TempDir()})
	if KindOf(err) != KindConflict {
		t.Fatalf("AddLibrary(podcasts) = %v, want a conflict", err)
	}
}

// TestAddLibraryRefusesPodcastRootWithoutBridge keeps the name reserved
// with no sidecar configured: one wired up later mounts the podcast
// root under that name regardless.
func TestAddLibraryRefusesPodcastRootWithoutBridge(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	svc.podcastRootName = "podcasts"

	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "podcasts", Path: t.TempDir()})
	if KindOf(err) != KindConflict {
		t.Fatalf("AddLibrary(podcasts) = %v, want a conflict", err)
	}
}
