package service

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

func TestWatchPendingSettles(t *testing.T) {
	t.Parallel()
	p := newWatchPending(10 * time.Second)
	base := time.Now()
	p.note("/lib/a", base)
	if due := p.due(base.Add(5 * time.Second)); len(due) != 0 {
		t.Fatalf("due before the settle window: %v", due)
	}
	// A fresh event restarts the quiet window.
	p.note("/lib/a", base.Add(8*time.Second))
	if due := p.due(base.Add(12 * time.Second)); len(due) != 0 {
		t.Fatalf("due despite a fresh event: %v", due)
	}
	if due := p.due(base.Add(18 * time.Second)); len(due) != 1 || due[0] != "/lib/a" {
		t.Fatalf("due = %v, want the settled directory", due)
	}
	if due := p.due(base.Add(30 * time.Second)); len(due) != 0 {
		t.Fatal("a due directory was answered twice")
	}
}

// A busy skip re-notes the directory, so a rescan deferred behind a
// running catalog job waits out a whole settle window before retrying
// rather than hammering the lease.
func TestWatchPendingRequeueWaitsAgain(t *testing.T) {
	t.Parallel()
	p := newWatchPending(10 * time.Second)
	base := time.Now()
	p.note("/lib/a", base)
	due := p.due(base.Add(10 * time.Second))
	if len(due) != 1 {
		t.Fatalf("due = %v, want one directory", due)
	}
	p.note(due[0], base.Add(10*time.Second))
	if due := p.due(base.Add(15 * time.Second)); len(due) != 0 {
		t.Fatalf("requeued directory came back early: %v", due)
	}
	if due := p.due(base.Add(20 * time.Second)); len(due) != 1 {
		t.Fatalf("requeued directory never came back: %v", due)
	}
}

// An undispatched batch goes back as already settled, so a busy scan
// worker delays it one sweep, not a whole fresh window.
func TestWatchPendingRestoreStaysDue(t *testing.T) {
	t.Parallel()
	p := newWatchPending(10 * time.Second)
	base := time.Now()
	p.restore([]string{"/lib/a"}, base)
	if due := p.due(base.Add(time.Second)); len(due) != 1 {
		t.Fatalf("restored directory not due at the next sweep: %v", due)
	}
}

// The trash directory lives inside the watched tree, and a delete fires
// create events there; the watcher must neither watch nor scan it, or a
// deleted file is re-cataloged straight out of the trash.
func TestWatchSkipsTrash(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	for _, dir := range []string{"albums", filepath.Join(model.TrashDirName, "tr-1")} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	w, err := fsnotify.NewWatcher()
	if err != nil {
		t.Skipf("no fsnotify facility: %v", err)
	}
	defer w.Close()
	armed, failed := watchTree(w, root)
	if armed != 2 || failed != 0 {
		t.Fatalf("(armed, failed) = (%d, %d), want the root and the album dir only", armed, failed)
	}
	// Events under the trash never schedule a scan.
	p := newWatchPending(time.Second)
	noteWatchEvent(w, p, fsnotify.Event{
		Name: filepath.Join(root, model.TrashDirName, "tr-1", "song.flac"),
		Op:   fsnotify.Create,
	})
	if due := p.due(time.Now().Add(2 * time.Second)); len(due) != 0 {
		t.Fatalf("a trash event was scheduled: %v", due)
	}
}

// newWatchFixture is a real Library over a scanned one-track catalog
// with the live watcher armed and a short settle window.
func newWatchFixture(t *testing.T) (context.Context, *Library, string) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir, fixtures.Spec{
		Name: "seed", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Seed Track", "ARTIST": "Watch Ensemble", "ALBUM": "Watch Garden"},
	}); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir:        dataDir,
		Roots:          []Root{{Name: "lib", Path: libDir}},
		WatchLibraries: true,
		WatchSettle:    50 * time.Millisecond,
		Logger:         log,
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
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return ctx, svc, libDir
}

// A file placed into a library root by hand is cataloged by the watcher
// alone: no client, no manual rescan, no schedule.
func TestWatcherCatalogsAManualDrop(t *testing.T) {
	t.Parallel()
	ctx, svc, libDir := newWatchFixture(t)
	select {
	case <-svc.watchReady:
	case <-time.After(10 * time.Second):
		t.Fatal("the watcher never armed")
	}
	if _, err := fixtures.Generate(libDir, fixtures.Spec{
		Name: "dropped", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Dropped By Hand", "ARTIST": "Watch Ensemble", "ALBUM": "Watch Garden"},
	}); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(20 * time.Second)
	for {
		b := query.New(query.EntityItems).
			Where("title", query.OpIs, "Dropped By Hand").Limit(1)
		items, err := svc.lib.Query(ctx, b.Build(), "")
		if err == nil && len(items) > 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("the dropped file was never cataloged")
		}
		time.Sleep(50 * time.Millisecond)
	}
}
