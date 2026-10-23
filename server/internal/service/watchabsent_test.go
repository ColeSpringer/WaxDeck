package service

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The write probe's file comes and goes in a managed root's own folder,
// inside the watched tree: its events must not wake a scan of the root.
func TestTheWriteProbeWakesNoScan(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	w, err := fsnotify.NewWatcher()
	if err != nil {
		t.Skipf("no fsnotify facility: %v", err)
	}
	defer w.Close()
	if armed, failed := watchTree(w, root); armed != 1 || failed != 0 {
		t.Fatalf("(armed, failed) = (%d, %d), want the root alone", armed, failed)
	}
	if err := probeWritable(root); err != nil {
		t.Fatal(err)
	}
	p := newWatchPending(time.Millisecond)
	seen := 0
	for drained := false; !drained; {
		select {
		case ev := <-w.Events:
			seen++
			noteWatchEvent(w, p, ev)
		case <-time.After(200 * time.Millisecond):
			drained = true
		}
	}
	if seen == 0 {
		t.Fatal("the probe raised no event to ignore")
	}
	if due := p.due(time.Now().Add(time.Second)); len(due) != 0 {
		t.Fatalf("the probe scheduled a scan of %v", due)
	}
}

// openWatched opens a service watching roots, with a short settle window
// and recheck, its log written to logs.
func openWatched(t *testing.T, roots []Root, logs io.Writer) (context.Context, *Library) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir, Roots: roots, WatchLibraries: true,
		WatchSettle: 50 * time.Millisecond, WatchRecheck: 100 * time.Millisecond, Logger: log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	return ctx, svc
}

// waitForTitle waits until the catalog holds an item titled title.
func waitForTitle(t *testing.T, ctx context.Context, svc *Library, title string) {
	t.Helper()
	waitFor(t, func() bool {
		items, err := svc.lib.Query(ctx, query.New(query.EntityItems).
			Where("title", query.OpIs, title).Limit(1).Build(), "")
		return err == nil && len(items) > 0
	}, "the watcher cataloging "+title)
}

func dropTrack(t *testing.T, dir, title string) {
	t.Helper()
	if _, err := fixtures.Generate(dir, fixtures.Spec{
		Name: strings.ReplaceAll(strings.ToLower(title), " ", "-"), Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Watch Ensemble"},
	}); err != nil {
		t.Fatal(err)
	}
}

// A root whose folder is not there is said so and left unwatched, not
// blamed on the inotify budget, while the rest are watched; once the
// folder is there the watcher takes it up without a restart.
func TestAnAbsentRootIsNotWatchedUntilItIsThere(t *testing.T) {
	t.Parallel()
	present, base := t.TempDir(), t.TempDir()
	later := filepath.Join(base, "later")
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: present}, {Name: "later", Path: later}}, &logged)
	select {
	case <-svc.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed")
	}
	const said = "library root is not present; not watched"
	waitFor(t, func() bool { return strings.Contains(logged.String(), said) }, "the absent root said")
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, said) && (!strings.Contains(line, "library=later") || !strings.Contains(line, "path="+later)) {
			t.Errorf("the line %q does not name the library and its path", line)
		}
		if strings.Contains(line, "fs.inotify") {
			t.Errorf("an absent root was blamed on the inotify budget: %q", line)
		}
	}
	dropTrack(t, present, "Watched Beside A Gap")
	waitForTitle(t, ctx, svc, "Watched Beside A Gap")

	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return strings.Contains(logged.String(), "library root is present again") }, "the root taken up")
	dropTrack(t, later, "Dropped Once Mounted")
	waitForTitle(t, ctx, svc, "Dropped Once Mounted")
	if n := strings.Count(logged.String(), said); n != 1 {
		t.Errorf("the absent root was said %d times, want once:\n%s", n, logged.String())
	}
}

// With every root's folder missing the watcher waits for one, without a
// failure or a retry storm, and watches it once it is there.
func TestAWatcherWithNoRootThereWaitsForOne(t *testing.T) {
	t.Parallel()
	later := filepath.Join(t.TempDir(), "later")
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "later", Path: later}}, &logged)
	waitFor(t, func() bool { return strings.Count(logged.String(), "looking again for missing library roots") >= 3 },
		"three looks for the missing folder")
	for _, bad := range []string{"no library directory could be watched", "worker failed"} {
		if strings.Contains(logged.String(), bad) {
			t.Errorf("the log says %q:\n%s", bad, logged.String())
		}
	}
	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	select {
	case <-svc.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed once the folder was there")
	}
	dropTrack(t, later, "First Light")
	waitForTitle(t, ctx, svc, "First Light")
}

// A root the watcher takes up after it started may hold files that came
// after its last scan and before its watch: the CLI adds one with no scan
// at all. The watcher catches it up with a scan once it watches it.
func TestARootTakenUpLaterIsCaughtUpByAScan(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}}, &logged)
	select {
	case <-svc.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed")
	}
	added := t.TempDir()
	dropTrack(t, added, "Already There")
	if _, err := svc.lib.AddRoot(ctx, config.Root{Path: added}); err != nil {
		t.Fatal(err)
	}
	waitForTitle(t, ctx, svc, "Already There")
}

// A folder back from an outage lists as reachable once the watcher has
// scanned it, without waiting for the next whole scan.
func TestARootBackFromAnOutageListsReachable(t *testing.T) {
	t.Parallel()
	later := filepath.Join(t.TempDir(), "later")
	var logged lockedBuffer
	ctx, svc := openWatched(t, []Root{{Name: "lib", Path: t.TempDir()}, {Name: "later", Path: later}}, &logged)
	if _, err := svc.Rescan(ctx, false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return libraryAt(t, ctx, svc, later).Unreachable }, "the scan to find later gone")
	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return !libraryAt(t, ctx, svc, later).Unreachable }, "later listed reachable once watched")
}
