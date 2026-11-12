package service

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
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
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeFlowRoots stands in for the bridge: it records what the service
// taught it and answers the reload however the test needs.
type fakeFlowRoots struct {
	mu        sync.Mutex
	names     []string
	syncErr   error
	removeErr error

	synced  []Root
	removed []string
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

func (f *fakeFlowRoots) RemoveRoot(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.removed = append(f.removed, name)
	if f.removeErr == nil {
		f.names = slices.DeleteFunc(f.names, func(n string) bool { return n == name })
	}
	return f.removeErr
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
	svc.Roots.SetFlowRoots(flow)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.Roots.refreshLibraryState(ctx)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			svc.Roots.syncFlowRoots(ctx)
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
	svc.Roots.SetFlowRoots(flow)
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
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "child", Path: child}); err != nil {
		t.Fatal(err)
	}
	stop()
	_, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "parent", Path: parent})
	})
	var paths []string
	for _, r := range svc.Roots.libraryRoots() {
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
	_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "again", Path: filepath.Join(dataDir, "configured")})
	if KindOf(err) != KindConflict {
		t.Fatalf("a create over the configured root = %v, want conflict", err)
	}
	if roots := svc.Roots.Table(); len(roots) != 1 || roots[0].Name != "configured" || !roots[0].Managed {
		t.Errorf("roots = %+v, want the configured root untouched", roots)
	}
}

// A create at a folder the catalog holds under another path through a
// symlink is refused: two libraries on one folder would catalog it twice.
// The path is stored resolved, so this is the path check's refusal; the
// identity checks a bind mount needs are pinned below.
func TestAddingALibraryAtARegisteredFolderByAnotherPathIsRefused(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	links := t.TempDir()
	parent := filepath.Join(links, "parent")
	if err := os.Symlink(dataDir, parent); err != nil {
		t.Fatal(err)
	}
	self := filepath.Join(links, "self")
	if err := os.Symlink(filepath.Join(dataDir, "configured"), self); err != nil {
		t.Fatal(err)
	}
	for i, path := range []string{filepath.Join(parent, "configured"), self} {
		name := fmt.Sprintf("again-%d", i)
		_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: path})
		if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "configured") {
			t.Fatalf("a create at %s = %v, want conflict naming the library that holds the folder", path, err)
		}
		stored, err := svc.db.LibraryRootsList(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == name }) {
			t.Errorf("stored names = %+v, want none for the refused library", stored)
		}
	}
	if roots := svc.Roots.Table(); len(roots) != 1 || roots[0].Name != "configured" {
		t.Errorf("roots = %+v, want the configured root alone", roots)
	}
}

// A library created at a symlink, or at a path that runs through one, is
// stored as the folder the link names: the catalog's whole-library scan
// does not follow a symlinked root, so the track already there is
// cataloged only this way.
func TestALibraryCreatedAtASymlinkIsStoredAsItsFolder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	base := resolvedTempDir(t)
	itself, through := filepath.Join(base, "itself"), filepath.Join(base, "through", "music")
	for _, dir := range []string{itself, through} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	dropTrack(t, itself, "Already Behind The Link")
	dropTrack(t, through, "Already Through The Parent")
	for link, to := range map[string]string{"link": itself, "parent": filepath.Join(base, "through")} {
		if err := os.Symlink(to, filepath.Join(base, link)); err != nil {
			t.Fatal(err)
		}
	}
	for _, c := range []struct{ name, typed, want, title string }{
		{"linked", filepath.Join(base, "link"), itself, "Already Behind The Link"},
		{"parented", filepath.Join(base, "parent", "music"), through, "Already Through The Parent"},
	} {
		info, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: c.name, Path: c.typed})
		if err != nil {
			t.Fatalf("a create at %s = %v", c.typed, err)
		}
		if info.Path != c.want || info.Name != c.name {
			t.Errorf("created %s at %q, want %s at the folder the link names, %q", info.Name, info.Path, c.name, c.want)
		}
		stored, err := svc.db.LibraryRootsList(ctx)
		if err != nil || !slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == c.name && r.Path == c.want }) {
			t.Errorf("stored names = %+v (%v), want %s at %s", stored, err, c.name, c.want)
		}
		if r, ok := rootAt(svc, c.want); !ok || r.Name != c.name {
			t.Errorf("root table entry = %+v (found %v), want %s at %s", r, ok, c.name, c.want)
		}
		waitForTitle(t, ctx, svc, c.title)
	}
}

// A library added before its folder is there is stored as the folder a
// symlink names all the same, through a link whose target is not there
// yet and through a link to the parent of a folder not there yet: once
// the drive mounts, its scans walk a real folder.
func TestALibraryAtASymlinkToAFolderNotThereYetIsStoredAsThatFolder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	base := resolvedTempDir(t)
	later := filepath.Join(base, "mnt", "later")
	if err := os.Mkdir(filepath.Join(base, "mnt"), 0o755); err != nil {
		t.Fatal(err)
	}
	dangling := filepath.Join(base, "dangling")
	// A relative target, as `ln -s mnt/later dangling` makes.
	if err := os.Symlink(filepath.Join("mnt", "later"), dangling); err != nil {
		t.Fatal(err)
	}
	parent := filepath.Join(base, "parent")
	if err := os.Symlink(filepath.Join(base, "mnt"), parent); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct{ name, typed, want string }{
		{"dangling", dangling, later},
		{"through", filepath.Join(parent, "elsewhere"), filepath.Join(base, "mnt", "elsewhere")},
	} {
		info, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: c.name, Path: c.typed, AllowAbsent: true})
		if err != nil {
			t.Fatalf("a create at %s = %v", c.typed, err)
		}
		if info.Path != c.want {
			t.Errorf("created %s at %q, want the folder the link names, %q", c.name, info.Path, c.want)
		}
		if r, ok := rootAt(svc, c.want); !ok || r.Name != c.name {
			t.Errorf("root table entry = %+v (found %v), want %s at %s", r, ok, c.name, c.want)
		}
	}
}

// A link not there yet whose relative target climbs out of its folder,
// reached through a linked folder, is followed from where the link really
// is, as the system follows it: the library is stored at that folder, not
// at the one the path's spelling suggests, whose files stay out of it.
func TestADanglingRelativeLinkIsFollowedFromWhereItIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	base := resolvedTempDir(t)
	sub := filepath.Join(base, "x", "y", "sub")
	unrelated := filepath.Join(base, "mnt", "later")
	for _, dir := range []string{sub, unrelated} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	dropTrack(t, unrelated, "Not This Library's")
	if err := os.Symlink(filepath.Join("x", "y", "sub"), filepath.Join(base, "sp")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join("..", "mnt", "later"), filepath.Join(sub, "d")); err != nil {
		t.Fatal(err)
	}
	info, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "climbing", Path: filepath.Join(base, "sp", "d"), AllowAbsent: true})
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(base, "x", "y", "mnt", "later"); info.Path != want {
		t.Errorf("created at %q, want %q, where the system follows the link", info.Path, want)
	}
	waitFor(t, func() bool {
		running, err := svc.Jobs.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, "Not This Library's").Limit(1).Build(), "")
	if err != nil || len(items) > 0 {
		t.Errorf("the catalog holds %d items from the unrelated folder (%v), want none", len(items), err)
	}
}

// A path under a file can never become a folder, so it is refused even
// for a library added before its folder is there.
func TestALibraryUnderAFileIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	file := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	below := filepath.Join(file, "below")
	for _, allowAbsent := range []bool{false, true} {
		_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "under", Path: below, AllowAbsent: allowAbsent})
		if KindOf(err) != KindInvalid || err.Error() != below+" lies under a file, so it can never be a folder" {
			t.Fatalf("a create under a file (allowAbsent %v) = %v, want it refused as under a file", allowAbsent, err)
		}
	}
	if roots := svc.Roots.Table(); len(roots) != 1 {
		t.Errorf("roots = %+v, want the configured root alone", roots)
	}
}

// A link not there yet whose absolute target climbs with ".." past a
// linked folder climbs out of the folder that link names, as the system
// follows it, not out of the target's spelling.
func TestADanglingAbsoluteLinkClimbsFromWhereItsFoldersAre(t *testing.T) {
	t.Parallel()
	base := resolvedTempDir(t)
	if err := os.MkdirAll(filepath.Join(base, "x", "y", "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join("x", "y", "sub"), filepath.Join(base, "sp")); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "d")
	if err := os.Symlink(base+"/sp/../mnt/later", link); err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(base, "x", "y", "mnt", "later")
	if got, err := resolveFolder(link); err != nil || got != want {
		t.Errorf("resolveFolder(%s) = %q, %v, want %q", link, got, err, want)
	}
}

// A ".." that would climb out of a link not followable yet (its folder not
// mounted) cannot be answered as the system will answer it once it is, so
// the path is kept as given rather than guessed from its spelling.
func TestAClimbOutOfALinkNotThereYetKeepsThePathAsGiven(t *testing.T) {
	t.Parallel()
	base := resolvedTempDir(t)
	if err := os.Symlink(filepath.Join(base, "elsewhere", "mnt"), filepath.Join(base, "dang")); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "d")
	if err := os.Symlink(base+"/dang/../x", link); err != nil {
		t.Fatal(err)
	}
	if got, err := resolveFolder(link); err == nil {
		t.Errorf("resolveFolder(%s) = %q, want it to give up, keeping the path as given", link, got)
	}
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	info, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "climbing", Path: link, AllowAbsent: true})
	if err != nil || info.Path != link {
		t.Errorf("created at %q (%v), want the path as given, %q", info.Path, err, link)
	}
}

// resolveFolder steps up through any number of absent folders, and
// through a path under a file, without reading either as a link it
// could not follow.
func TestResolveFolderStepsUpThroughWhatIsNotThere(t *testing.T) {
	t.Parallel()
	base := resolvedTempDir(t)
	deep := base
	for i := range 45 {
		deep = filepath.Join(deep, fmt.Sprintf("absent-%d", i))
	}
	if got, err := resolveFolder(deep); err != nil || got != deep {
		t.Errorf("resolveFolder(45 absent folders) = %q, %v, want the path as it is", got, err)
	}
	file := filepath.Join(base, "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if got, err := resolveFolder(filepath.Join(file, "below")); err != nil || got != filepath.Join(file, "below") {
		t.Errorf("resolveFolder(under a file) = %q, %v, want the path as it is", got, err)
	}
}

// resolvedTempDir is t.TempDir with its own symlinks followed, as macOS's
// /var -> /private/var needs, so a test's expected paths are the stored
// ones.
func resolvedTempDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

// A create at a folder a library holds under a path no string check
// equates with it, as a bind mount gives, is refused by the folders'
// identity alone: the stat of the configured root's folder answers the
// new folder.
func TestAddingALibraryAtARegisteredFolderIsRefusedByItsIdentity(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	configured := filepath.Join(dataDir, "configured")
	other := t.TempDir()
	svc.Roots.creates.stat = func(path string) (fs.FileInfo, error) {
		if path == configured {
			return os.Stat(other)
		}
		return os.Stat(path)
	}
	_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "bound", Path: other})
	if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "already holds that folder") {
		t.Fatalf("a create at the configured root's folder by another path = %v, want conflict", err)
	}
	if roots := svc.Roots.Table(); len(roots) != 1 || roots[0].Name != "configured" {
		t.Errorf("roots = %+v, want the configured root alone", roots)
	}
}

// A link and the folder it names, created together, make one library:
// while the first create to pass its checks has stored nothing yet, the
// other is refused as the same folder being added, which only the
// folders' identity can tell.
func TestALinkAndItsFolderCreatedTogetherMakeOneLibrary(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	base := resolvedTempDir(t)
	folder := filepath.Join(base, "folder")
	if err := os.Mkdir(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "link")
	if err := os.Symlink(folder, link); err != nil {
		t.Fatal(err)
	}
	// Each look waits until both creates are looking, and the first to
	// pass its checks waits until the other has answered.
	both := make(chan struct{})
	var arrived, passed atomic.Int32
	svc.Roots.creates.look = func(path string) folderAnswer {
		if arrived.Add(1) == 2 {
			close(both)
		}
		<-both
		return lookAt(path)
	}
	first := newGate(t)
	svc.Roots.creates.free = func() {
		if passed.Add(1) == 1 {
			first.wait()
		}
	}
	errs := make(chan error, 2)
	for i, path := range []string{link, folder} {
		go func() {
			_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: fmt.Sprintf("one-%d", i), Path: path})
			errs <- err
		}()
	}
	var refused []error
	for range 2 {
		if err := <-errs; err != nil {
			refused = append(refused, err)
		}
		first.release()
	}
	if len(refused) != 1 || KindOf(refused[0]) != KindConflict || !strings.Contains(refused[0].Error(), "is being added") {
		t.Fatalf("refused %v, want exactly one create refused as the same folder being added", refused)
	}
	if roots := svc.Roots.Table(); len(roots) != 2 {
		t.Errorf("roots = %+v, want the configured root and one library on the folder", roots)
	}
}

// Creates while a library's folder hangs share one stat of it: a create
// does not start another while one is out, and each lands meanwhile.
func TestCreatesShareOneStatOfALibraryFolderThatHangs(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	configured := filepath.Join(dataDir, "configured")
	hangs := newGate(t)
	var stats atomic.Int32
	svc.Roots.creates.wait = 100 * time.Millisecond
	svc.Roots.creates.stat = func(path string) (fs.FileInfo, error) {
		if path == configured {
			stats.Add(1)
			hangs.wait()
		}
		return os.Stat(path)
	}
	for i := range 3 {
		if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: fmt.Sprintf("beside-%d", i), Path: t.TempDir()}); err != nil {
			t.Fatalf("create %d beside a folder that hangs = %v, want it added", i, err)
		}
	}
	if n := stats.Load(); n != 1 {
		t.Fatalf("%d stats of the folder that hangs over three creates, want one", n)
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
	svc.Roots.refreshLibraryState(ctx)
	names := map[string]string{}
	for _, r := range svc.Roots.Table() {
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
	if err := svc.Roots.registerConfiguredRoots(ctx); err != nil {
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
	svc.Roots.refreshLibraryState(ctx)
	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(delta.Events, func(e ServerSyncEvent) bool { return e.Kind == eventLibraries }) {
		t.Errorf("events = %+v, want a libraries marker", delta.Events)
	}
}

// A library's folder fallback switched by the console or the CLI tells
// every account to re-read the libraries, as its other flags do.
func TestAFolderFallbackSwitchTellsEveryAccount(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.Roots.refreshLibraryState(ctx)
	lib := svc.Roots.libraryRoots()[0]
	before := markers(t, ctx, svc, uc.ID, eventLibraries, "")
	if err := svc.Settings.LibraryFolderFallbackSet(ctx, uc, apiPID(PrefixLibrary, model.PID(lib.PID)), true); err != nil {
		t.Fatal(err)
	}
	if n := markers(t, ctx, svc, uc.ID, eventLibraries, ""); n != before+1 {
		t.Fatalf("libraries markers after the console's switch = %d, want %d", n, before+1)
	}
	if _, err := svc.lib.SetLibraryFolderFallback(ctx, model.PID(lib.PID), false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return markers(t, ctx, svc, uc.ID, eventLibraries, "") == before+2 },
		"the CLI's switch telling every account")
}

// A root added before the bridge was wired is taught once it is.
func TestARootAddedBeforeTheBridgeStreamsOnceWired(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.Roots.refreshLibraryState(ctx)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.Roots.SetFlowRoots(flow)
	waitFor(t, func() bool { return flow.taught(filepath.Base(extra), extra) }, "the bridge taught the earlier root")
}

// A root the sidecar refused is not offered again by every settle; the
// console's own create still is.
func TestARefusedRootWaitsForItsPathToChange(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}, syncErr: errors.New("sidecar refused")}
	svc.Roots.SetFlowRoots(flow)
	extra := t.TempDir()
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: extra}); err != nil {
		t.Fatal(err)
	}
	svc.Roots.refreshLibraryState(ctx)
	waitFor(t, func() bool { return flow.taught(filepath.Base(extra), extra) }, "the first offer")
	svc.Roots.syncFlowRoots(ctx)
	svc.Roots.syncFlowRoots(ctx)
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
			svc.Roots.refreshLibraryState(ctx)
		}
	}()
	for range 50 {
		svc.Tools.storageRootFor("/nowhere/file.flac")
	}
	<-done
}

// libraryCreateDetail returns the streamingWarning recorded on the most
// recent library.create audit entry, empty when there is none.
func libraryCreateDetail(t *testing.T, ctx context.Context, svc *Library) string {
	t.Helper()
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: "library.create"}, "", 10)
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
	svc.Roots.SetFlowRoots(flow)

	dir := t.TempDir()
	lib, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir})
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

// The name is stored before the catalog takes the root, so a create whose
// name cannot be stored adds nothing: the feed's refresh would otherwise
// name the root after its directory, and the bridge learn both names.
func TestAddLibraryWhoseNameCannotBeStoredAddsNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	flow := &fakeFlowRoots{names: []string{"lib"}}
	svc.Roots.SetFlowRoots(flow)
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_names BEFORE INSERT ON library_roots
		BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir}); err == nil {
		t.Fatal("AddLibrary succeeded with its name refused")
	}
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if rootKey(lib.DisplayRoot) == rootKey(dir) {
			t.Errorf("the catalog took %s with no name stored for it", dir)
		}
	}
	flow.mu.Lock()
	defer flow.mu.Unlock()
	if len(flow.synced) != 0 {
		t.Errorf("synced roots = %v, want none", flow.synced)
	}
}

// A root the catalog refuses takes its stored name back out, so the name
// cannot attach to a root the CLI adds at that path later.
func TestAddLibraryRefusedByTheCatalogLeavesNoName(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	roots := svc.Roots.Table()
	if len(roots) == 0 {
		t.Fatal("the fixture has no library root")
	}
	// Inside an existing root: the catalog refuses an overlap.
	nested := filepath.Join(roots[0].Path, "nested")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "nested", Path: nested}); err == nil {
		t.Fatal("AddLibrary inside an existing root succeeded")
	}
	stored, err := svc.db.LibraryRootsList(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range stored {
		if rootKey(r.Path) == rootKey(nested) {
			t.Errorf("the refused root left its name %q stored", r.Name)
		}
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
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
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
	svc.Roots.SetFlowRoots(flow)

	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
		t.Fatalf("AddLibrary must succeed despite a failed reload, got %v", err)
	}
	libs, err := svc.Roots.Libraries(ctx)
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
	svc.Roots.SetFlowRoots(flow)

	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()}); err != nil {
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
	svc.Roots.SetFlowRoots(&fakeFlowRoots{names: []string{"lib", "podcasts"}})

	_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "podcasts", Path: t.TempDir()})
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
	svc.Roots.podcastRootName = "podcasts"

	_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "podcasts", Path: t.TempDir()})
	if KindOf(err) != KindConflict {
		t.Fatalf("AddLibrary(podcasts) = %v, want a conflict", err)
	}
}

// rootAt finds the root table's entry for path.
func rootAt(svc *Library, path string) (Root, bool) {
	for _, r := range svc.Roots.libraryRoots() {
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
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: books, Managed: true}); err != nil {
		t.Fatal(err)
	}
	dropAndWaitForTheWatcher(t, ctx, svc, books, "Dropped Before The Restart")
	stop()

	ctx, svc, _, _ = openServiceAt(t, dataDir, watch)
	if r, ok := rootAt(svc, books); !ok || r.Name != "books" || !r.Managed {
		t.Fatalf("root after a restart = %+v (found %v), want books, managed", r, ok)
	}
	// The start's first pass arms it like every root it opens with: no
	// catch-up scan on top of what the restart owes.
	awaitClosed(t, svc.Roots.watchReady, "the watcher to arm after the restart")
	svc.Roots.watchQueue.mu.Lock()
	_, pending := svc.Roots.watchQueue.dirs[books]
	svc.Roots.watchQueue.mu.Unlock()
	if pending {
		t.Error("the restart owed a library it already watched a catch-up scan")
	}
	dropAndWaitForTheWatcher(t, ctx, svc, books, "Dropped After The Restart")
}

// dropAndWaitForTheWatcher drops a track into dir once no catalog job
// runs, so only the watcher can catalog it, and waits until it does.
func dropAndWaitForTheWatcher(t *testing.T, ctx context.Context, svc *Library, dir, title string) {
	t.Helper()
	select {
	case <-svc.Roots.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed")
	}
	waitFor(t, func() bool {
		running, err := svc.Jobs.catalogJobRunning(ctx)
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

// A configured root declared to hold audiobooks registers as one, and a
// catalog that holds it as something else is put back on the next start;
// one not declared keeps whatever it holds.
func TestAConfiguredAudiobookRootIsDeclaredBooks(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	declared := func(cfg *Config) { cfg.Roots[0].Media = string(model.MediaAudiobook) }
	media := func(ctx context.Context, svc *Library) model.MediaType {
		t.Helper()
		libs, err := svc.lib.Libraries(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for _, lib := range libs {
			if lib.DisplayRoot == filepath.Join(dataDir, "configured") {
				return lib.MediaType()
			}
		}
		t.Fatal("the configured root is not registered")
		return ""
	}
	ctx, svc, uc, stop := openServiceAt(t, dataDir, declared)
	if got := media(ctx, svc); got != model.MediaAudiobook {
		t.Fatalf("declared root media = %q, want audiobook", got)
	}
	root, _ := rootAt(svc, filepath.Join(dataDir, "configured"))
	if _, err := svc.Roots.SetLibraryMedia(ctx, uc, apiPID(PrefixLibrary, model.PID(root.PID)), "music"); KindOf(err) != KindInvalid ||
		!strings.Contains(err.Error(), "WAXDECK_AUDIOBOOK_ROOTS") {
		t.Fatalf("changing a declared root = %v, want it refused for the configuration", err)
	}
	// The listing says so before an administrator tries.
	declaredAt := func(ctx context.Context, svc *Library) bool {
		t.Helper()
		libs, err := svc.Roots.Libraries(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for _, lib := range libs {
			if lib.Path == filepath.Join(dataDir, "configured") {
				return lib.MediaDeclared
			}
		}
		t.Fatal("the configured root is not listed")
		return false
	}
	if !declaredAt(ctx, svc) {
		t.Fatal("a declared root lists as not declared")
	}
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: filepath.Join(dataDir, "configured"), Media: model.MediaMusic}); err != nil {
		t.Fatal(err)
	}
	stop()

	ctx, svc, _, stop = openServiceAt(t, dataDir, declared)
	if got := media(ctx, svc); got != model.MediaAudiobook {
		t.Fatalf("declared root media after a restart = %q, want it put back to audiobook", got)
	}
	stop()
	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	if got := media(ctx, svc); got != model.MediaAudiobook {
		t.Fatalf("undeclared root media = %q, want what the catalog holds", got)
	}
	if declaredAt(ctx, svc) {
		t.Fatal("an undeclared root lists as declared")
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
	info := svc.Roots.libraryInfo(&model.Library{PID: model.NewPID(), DisplayRoot: "/srv/podcasts", Mode: model.ModePodcast})
	if info.Media != "podcast" {
		t.Errorf("media = %q, want podcast", info.Media)
	}
}

// A configured root whose folder is not there yet registers anyway, its
// scan saying the root was unreachable, and a profile change on it is
// not refused over the folder.
func TestAConfiguredRootThatIsGoneStillRegisters(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	gone := filepath.Join(dataDir, "unmounted")
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "unmounted", Path: gone, Managed: true})
	})
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var lib *model.Library
	var roots []string
	for _, l := range libs {
		roots = append(roots, l.DisplayRoot)
		if l.DisplayRoot == gone {
			lib = l
		}
	}
	if lib == nil {
		t.Fatalf("no library at the absent root %s; the catalog holds %v", gone, roots)
	}
	res, err := svc.lib.Scan(ctx, waxbin.ScanRequest{LibraryPID: lib.PID})
	if err != nil {
		t.Fatalf("scanning the absent root: %v", err)
	}
	if len(res.Runs) != 1 || !res.Runs[0].RootUnreachable {
		t.Errorf("the scan's runs = %+v, want one reporting the root unreachable", res.Runs)
	}
	if _, err := svc.Health.SetLibraryProfile(ctx, uc, apiPID(PrefixLibrary, lib.PID), organize.DefaultProfileName); err != nil {
		t.Errorf("a profile change on the absent library: %v", err)
	}
}

// A library is created at a folder the server can see. A path with
// nothing there, or a file, is refused in WaxDeck's words rather than
// with the catalog's advice about an option this endpoint lacks.
func TestALibraryNeedsAFolderThatIsThere(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	dir := t.TempDir()
	file := filepath.Join(dir, "notes.txt")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct{ path, want string }{
		{filepath.Join(dir, "absent"), "no folder"},
		{file, "not a folder"},
	} {
		_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "new", Path: c.path})
		if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), c.want) || strings.Contains(err.Error(), "allow") {
			t.Errorf("creating at %s = %v, want invalid saying %q", c.path, err, c.want)
		}
	}
	// A taken name is the answer, whatever the folder.
	taken := svc.Roots.libraryRoots()[0].Name
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: taken, Path: filepath.Join(dir, "absent")}); KindOf(err) != KindConflict {
		t.Errorf("a taken name at a missing folder = %v, want a conflict", err)
	}
}

// The podcast library holds what its feeds bring, so no media change
// reaches it.
func TestThePodcastLibrarysMediaIsNotChanged(t *testing.T) {
	t.Parallel()
	podcasts := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, t.TempDir(), func(c *Config) { c.PodcastDir = podcasts })
	defer stop()
	// The catalog makes the podcast library on the first episode it
	// files, which the missing source then refuses.
	show, err := svc.lib.Podcasts().AddManual(ctx, "Show", podcast.ManualOptions{})
	if err != nil {
		t.Fatal(err)
	}
	ep, err := svc.lib.Podcasts().AddEpisode(ctx, show.PID, model.FeedEpisode{GUID: "one", Title: "One"}, false)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = svc.lib.Podcasts().ImportEpisodeFile(ctx, ep.EpisodePID, filepath.Join(t.TempDir(), "absent.mp3"), true)
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var pid model.PID
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast {
			pid = lib.PID
		}
	}
	if pid == "" {
		t.Fatal("no podcast library")
	}
	_, err = svc.Roots.SetLibraryMedia(ctx, uc, apiPID(PrefixLibrary, pid), "music")
	if KindOf(err) != KindInvalid || err.Error() != "the podcast library holds podcasts" {
		t.Fatalf("changing the podcast library = %v, want it refused as the podcast library", err)
	}
}
