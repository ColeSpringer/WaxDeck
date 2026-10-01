package service

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeFlowRoots stands in for the bridge: it records what the service
// taught it and answers the reload however the test needs.
type fakeFlowRoots struct {
	mu      sync.Mutex
	names   []string
	syncErr error

	synced []Root
}

func (f *fakeFlowRoots) RootNames() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.names)
}

func (f *fakeFlowRoots) SyncRoot(_ context.Context, name, path string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.synced = append(f.synced, Root{Name: name, Path: path})
	if f.syncErr == nil {
		f.names = append(f.names, name)
	}
	return f.syncErr
}

// taught reports whether the bridge was taught name at path.
func (f *fakeFlowRoots) taught(name, path string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Contains(f.synced, Root{Name: name, Path: path})
}

// slowFlowRoots holds each reload until a second caller has asked for
// the names, so two unserialized syncs would both see a root as new.
type slowFlowRoots struct {
	fakeFlowRoots
	asked atomic.Int32
}

func (f *slowFlowRoots) RootNames() []string {
	f.asked.Add(1)
	return f.fakeFlowRoots.RootNames()
}

func (f *slowFlowRoots) SyncRoot(ctx context.Context, name, path string) error {
	for deadline := time.Now().Add(200 * time.Millisecond); f.asked.Load() < 2 && time.Now().Before(deadline); {
		time.Sleep(time.Millisecond)
	}
	return f.fakeFlowRoots.SyncRoot(ctx, name, path)
}

// Two syncs at once, as a restore's hook and feed can start, teach the
// bridge a root once: WaxFlow refuses a duplicate name.
func TestConcurrentFlowSyncsTeachARootOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &slowFlowRoots{fakeFlowRoots: fakeFlowRoots{names: []string{"configured"}}}
	svc.SetFlowRoots(flow)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			svc.syncFlowRoots(ctx)
		}()
	}
	wg.Wait()
	flow.mu.Lock()
	defer flow.mu.Unlock()
	if len(flow.synced) != 1 || flow.synced[0].Path != extra {
		t.Errorf("taught %v, want the new root once", flow.synced)
	}
}

// A root the CLI adds through the proxy streams without a restart.
func TestARootAddedElsewhereReachesTheBridge(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return flow.taught(filepath.Base(extra), extra) }, "the bridge taught the CLI's root")
}

// A configured root overlapping a library the catalog already holds is
// left out with a warning: nothing in the app could remove either.
func TestAnOverlappingConfiguredRootIsLeftOut(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	parent := filepath.Join(dataDir, "parent")
	child := filepath.Join(parent, "child")
	if err := os.MkdirAll(child, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "child", Path: child}); err != nil {
		t.Fatal(err)
	}
	stop()
	_, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "parent", Path: parent})
	})
	var paths []string
	for _, r := range svc.libraryRoots() {
		paths = append(paths, r.Path)
	}
	if !slices.Contains(paths, child) || slices.Contains(paths, parent) {
		t.Errorf("roots = %v, want the stored library kept and the overlapping one left out", paths)
	}
}

// A create at a path the catalog already holds is refused, rather than
// re-registering that library under another name and policy.
func TestAddingALibraryAtARegisteredPathIsRefused(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) { c.Roots[0].Managed = true })
	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "again", Path: filepath.Join(dataDir, "configured")})
	if KindOf(err) != KindConflict {
		t.Fatalf("a create over the configured root = %v, want conflict", err)
	}
	if roots := svc.RootTable(); len(roots) != 1 || roots[0].Name != "configured" || !roots[0].Managed {
		t.Errorf("roots = %+v, want the configured root untouched", roots)
	}
}

// A root added elsewhere whose directory shares a name the table already
// uses gets a name of its own, and keeps it: the name is the streaming
// engine's address for the root.
func TestARootNamedLikeAnotherGetsItsOwnName(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, _ := openServiceAt(t, dataDir, nil)
	twin := filepath.Join(t.TempDir(), "configured")
	if err := os.MkdirAll(twin, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: twin}); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	names := map[string]string{}
	for _, r := range svc.RootTable() {
		names[r.Path] = r.Name
	}
	if names[twin] != "configured-2" || names[filepath.Join(dataDir, "configured")] != "configured" {
		t.Fatalf("names = %v, want the twin renamed", names)
	}
	stored, err := svc.db.LibraryRootsList(ctx)
	if err != nil || !slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "configured-2" }) {
		t.Errorf("stored names = %+v (%v), want the twin's kept", stored, err)
	}
}

// Configured roots that overlap each other are a configuration error,
// refused at boot as the catalog always refused them.
func TestOverlappingConfiguredRootsRefuseBoot(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	outer := filepath.Join(dataDir, "outer")
	if err := os.MkdirAll(filepath.Join(outer, "inner"), 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	group := supervise.NewGroup(slog.New(slog.DiscardHandler))
	defer group.Wait()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	svc, err := Open(ctx, Config{DataDir: dataDir, Logger: slog.New(slog.DiscardHandler), Roots: []Root{
		{Name: "outer", Path: outer}, {Name: "inner", Path: filepath.Join(outer, "inner")},
	}}, store, group)
	if err == nil {
		cancel()
		group.Wait()
		svc.Close()
		t.Fatal("two configured roots, one inside the other, opened")
	}
}

// A hand-off leaves a configured root the catalog holds as configured
// alone: re-registering it would race an administrator's profile change.
func TestASettleLeavesConfiguredRootsAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	before, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.registerConfiguredRoots(ctx); err != nil {
		t.Fatal(err)
	}
	if after, err := svc.lib.LatestChangeSeq(ctx); err != nil || after != before {
		t.Errorf("change log %d -> %d (%v), want no write", before, after, err)
	}
}

// A media change made elsewhere reaches every account like any other.
func TestAMediaChangeTellsEveryAccount(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: filepath.Join(dataDir, "configured"), Media: model.MediaAudiobook}); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(delta.Events, func(e ServerSyncEvent) bool { return e.Kind == eventLibraries }) {
		t.Errorf("events = %+v, want a libraries marker", delta.Events)
	}
}

// A root added before the bridge was wired is taught once it is.
func TestARootAddedBeforeTheBridgeStreamsOnceWired(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	waitFor(t, func() bool { return flow.taught(filepath.Base(extra), extra) }, "the bridge taught the earlier root")
}

// A root the sidecar refused is not offered again by every settle; the
// console's own create still is.
func TestARefusedRootWaitsForItsPathToChange(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}, syncErr: errors.New("sidecar refused")}
	svc.SetFlowRoots(flow)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.refreshLibraryState(ctx)
	waitFor(t, func() bool { return flow.taught(filepath.Base(extra), extra) }, "the first offer")
	svc.syncFlowRoots(ctx)
	svc.syncFlowRoots(ctx)
	flow.mu.Lock()
	n := len(flow.synced)
	flow.mu.Unlock()
	if n != 1 {
		t.Errorf("offers = %d, want the refused root offered once", n)
	}
}

// Reading which root a path sits under races no root-table swap.
func TestRootAttributionRacesNoSwap(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for range 50 {
			svc.refreshLibraryState(ctx)
		}
	}()
	for range 50 {
		svc.storageRootFor("/nowhere/file.flac")
	}
	<-done
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
	t.Parallel()
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

// A library made in the console tells every account to re-read the
// libraries by the time the create answers.
func TestAddingALibraryTellsEveryAccount(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(delta.Events, func(e ServerSyncEvent) bool { return e.Kind == eventLibraries }) {
		t.Errorf("events = %+v, want a libraries marker", delta.Events)
	}
}

// TestAddLibraryDegradesOnReloadFailure pins the degrade rule: the
// sidecar opens each root while reconciling, so a path it cannot see
// fails the reload -- and that has to leave the library created (nothing
// but streaming depended on the sidecar) while telling the administrator
// who made the change what has to happen for streaming to follow.
func TestAddLibraryDegradesOnReloadFailure(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.podcastRootName = "podcasts"

	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "podcasts", Path: t.TempDir()})
	if KindOf(err) != KindConflict {
		t.Fatalf("AddLibrary(podcasts) = %v, want a conflict", err)
	}
}

// rootAt finds the root table's entry for path.
func rootAt(svc *Library, path string) (Root, bool) {
	for _, r := range svc.libraryRoots() {
		if r.Path == path {
			return r, true
		}
	}
	return Root{}, false
}

// A library added in the console keeps its name, its managed policy and
// the watcher's coverage across a restart: the catalog owns the policy
// and the name is stored beside it.
func TestARuntimeLibraryKeepsItsNameAndPolicyAcrossARestart(t *testing.T) {
	t.Parallel()
	dataDir, books := t.TempDir(), t.TempDir()
	watch := func(c *Config) { c.WatchLibraries, c.WatchSettle = true, 50*time.Millisecond }
	ctx, svc, uc, stop := openServiceAt(t, dataDir, watch)
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: books, Managed: true}); err != nil {
		t.Fatal(err)
	}
	dropAndWaitForTheWatcher(t, ctx, svc, books, "Dropped Before The Restart")
	stop()

	ctx, svc, _, _ = openServiceAt(t, dataDir, watch)
	if r, ok := rootAt(svc, books); !ok || r.Name != "books" || !r.Managed {
		t.Fatalf("root after a restart = %+v (found %v), want books, managed", r, ok)
	}
	dropAndWaitForTheWatcher(t, ctx, svc, books, "Dropped After The Restart")
}

// dropAndWaitForTheWatcher drops a track into dir once no catalog job
// runs, so only the watcher can catalog it, and waits until it does.
func dropAndWaitForTheWatcher(t *testing.T, ctx context.Context, svc *Library, dir, title string) {
	t.Helper()
	select {
	case <-svc.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed")
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the library's first scan to end")
	if _, err := fixtures.Generate(dir, fixtures.Spec{
		Name: strings.ReplaceAll(strings.ToLower(title), " ", "-"), Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Watch Ensemble"},
	}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		items, err := svc.lib.Query(ctx, query.New(query.EntityItems).
			Where("title", query.OpIs, title).Limit(1).Build(), "")
		return err == nil && len(items) > 0
	}, "the watcher cataloging "+title)
}

// A configured root's media set at runtime is the catalog's, which the
// next start no longer resets from configuration.
func TestAConfiguredRootKeepsItsRuntimeMedia(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, stop := openServiceAt(t, dataDir, nil)
	configured := filepath.Join(dataDir, "configured")
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: configured, Media: model.MediaAudiobook}); err != nil {
		t.Fatal(err)
	}
	stop()

	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if lib.DisplayRoot == configured && lib.MediaType() != model.MediaAudiobook {
			t.Fatalf("configured root media after a restart = %q, want audiobook", lib.MediaType())
		}
	}
}

// A root the CLI adds while it holds the catalog reaches the root table
// when the catalog comes back.
func TestARootAddedInAHandOffJoinsTheTable(t *testing.T) {
	t.Parallel()
	dataDir, added := t.TempDir(), t.TempDir()
	ctx, svc, _, _ := openServiceAt(t, dataDir, nil)
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	cli, err := waxbin.Open(ctx, waxbin.Options{DBPath: filepath.Join(dataDir, "waxbin.db"), Logger: slog.New(slog.DiscardHandler)})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cli.AddRoot(ctx, config.Root{Path: added}); err != nil {
		t.Fatal(err)
	}
	if err := cli.Close(); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if r, ok := rootAt(svc, added); !ok || r.Name != filepath.Base(added) {
		t.Fatalf("root added in the hand-off = %+v (found %v), want it named after its directory", r, ok)
	}
}

// The podcast library lists as one: the catalog stores no media for it.
func TestThePodcastLibraryListsAsPodcasts(t *testing.T) {
	t.Parallel()
	_, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	info := svc.libraryInfo(&model.Library{PID: model.NewPID(), DisplayRoot: "/srv/podcasts", Mode: model.ModePodcast})
	if info.Media != "podcast" {
		t.Errorf("media = %q, want podcast", info.Media)
	}
}
