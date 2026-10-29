package service

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
)

// copyOfDir copies a stopped service's data directory aside, as a full
// backup of the server takes it.
func copyOfDir(t *testing.T, dir string) string {
	t.Helper()
	out := t.TempDir()
	copyTree(t, dir, out)
	return out
}

// putBackDir replaces a stopped service's data directory with a copy taken
// earlier: a full restore, its own database included.
func putBackDir(t *testing.T, saved, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if err := os.RemoveAll(filepath.Join(dir, e.Name())); err != nil {
			t.Fatal(err)
		}
	}
	copyTree(t, saved, dir)
}

func copyTree(t *testing.T, from, to string) {
	t.Helper()
	err := filepath.WalkDir(from, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(from, path)
		if err != nil {
			return err
		}
		target := filepath.Join(to, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		src, err := os.Open(path)
		if err != nil {
			return err
		}
		defer src.Close()
		dst, err := os.Create(target)
		if err != nil {
			return err
		}
		if _, err := io.Copy(dst, src); err != nil {
			dst.Close()
			return err
		}
		return dst.Close()
	})
	if err != nil {
		t.Fatal(err)
	}
}

// growCatalog adds n rows to the catalog's change log and waits for the
// feed to read them.
func growCatalog(t *testing.T, ctx context.Context, svc *Library, n int) {
	t.Helper()
	for i := range n {
		if _, err := svc.lib.CreateUser(ctx, fmt.Sprintf("grown-%s-%d", feedGen(svc), i)); err != nil {
			t.Fatal(err)
		}
	}
	feedCaughtUp(t, ctx, svc)
}

// A full restore puts the server's own database back with the catalog, so
// the catalog's generation survives it and its log hands out again the
// numbers it had handed out after the copy. A device whose cursor is from
// after the copy is told to re-mirror, before the log reaches that number
// again and once it has grown past it.
func TestACatalogCursorFromARolledBackHistoryResets(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, stop := openServiceAt(t, dataDir, nil)
	feedCaughtUp(t, ctx, svc)
	gen := feedGen(svc)
	stop()
	saved := copyOfDir(t, dataDir)

	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	growCatalog(t, ctx, svc, 5)
	snap, err := svc.SyncCatalogSnapshot(ctx, uc, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	cursor := snap.NextSince
	stop()

	putBackDir(t, saved, dataDir)
	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	if feedGen(svc) != gen {
		t.Fatal("the restored server minted a new generation; this test needs the rollback that keeps it")
	}
	if _, err := svc.SyncCatalogDelta(ctx, uc, cursor, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor past the restored log's head answered %q (%v), want sync-reset", KindOf(err), err)
	}
	growCatalog(t, ctx, svc, 10)
	if _, err := svc.SyncCatalogDelta(ctx, uc, cursor, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor the regrown log has passed answered %q (%v), want sync-reset", KindOf(err), err)
	}
}

// The same for the stream of each account's own changes, which lives in
// the server's own database.
func TestAServerCursorFromARolledBackHistoryResets(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	_, svc, _, stop := openServiceAt(t, dataDir, nil)
	gen := svc.serverGen
	stop()
	saved := copyOfDir(t, dataDir)

	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	for range 3 {
		if _, err := svc.db.AppendEvent(ctx, uc.ID, eventPrefs, ""); err != nil {
			t.Fatal(err)
		}
	}
	cursor, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	stop()

	putBackDir(t, saved, dataDir)
	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	if svc.serverGen != gen {
		t.Fatal("the restored server minted a new generation; this test needs the rollback that keeps it")
	}
	if _, err := svc.SyncServerDelta(ctx, uc, cursor, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor past the restored log's tail answered %q (%v), want sync-reset", KindOf(err), err)
	}
	for range 6 {
		if _, err := svc.db.AppendEvent(ctx, uc.ID, eventPrefs, ""); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.SyncServerDelta(ctx, uc, cursor, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor the regrown log has passed answered %q (%v), want sync-reset", KindOf(err), err)
	}
}

// snapshotAt is the cursor a snapshot hands out once the feed has read the
// whole log: stamped with the head row.
func snapshotAt(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	feedCaughtUp(t, ctx, svc)
	snap, err := svc.SyncCatalogSnapshot(ctx, uc, "", 500)
	if err != nil {
		t.Fatal(err)
	}
	if c, _ := decodeCatalogCursor(snap.NextSince); c.ts == 0 {
		t.Fatal("the snapshot's cursor stands on no row")
	}
	return snap.NextSince
}

// keepAfter prunes the catalog's change log to exactly the rows after
// cursor, which puts its floor on the cursor's row.
func keepAfter(t *testing.T, ctx context.Context, svc *Library, cursor string) {
	t.Helper()
	c, _ := decodeCatalogCursor(cursor)
	after, err := svc.lib.Changes(ctx, c.seq)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PruneCatalogChanges(ctx, len(after)); err != nil {
		t.Fatal(err)
	}
	svc.feed.mu.Lock()
	floor := svc.feed.floor
	svc.feed.mu.Unlock()
	if floor != c.seq {
		t.Fatalf("the floor is %d, the cursor at %d: the case needs them equal", floor, c.seq)
	}
}

// The catalog delta's cursor at the places it can stand: at the tail (an
// empty delta, the cursor kept), behind it (the changes, a page at a
// time), at the floor (a prune took its row, the rest is there), past the
// tail (a position the log never reached), and in the shape cursors had
// before they carried their row's time.
func TestCatalogCursorsAtTheirTail(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, tracks := newTrashFixture(t, "One", "Two", "Three")
	feedCaughtUp(t, ctx, svc)
	snap, err := svc.SyncCatalogSnapshot(ctx, admin, "", 500)
	if err != nil {
		t.Fatal(err)
	}
	at := snap.NextSince

	still, err := svc.SyncCatalogDelta(ctx, admin, at, 10)
	if err != nil || len(still.Entries) != 0 || still.NextSince != at {
		t.Fatalf("a cursor at the tail = %d entries, cursor kept %v (%v), want none and kept",
			len(still.Entries), still.NextSince == at, err)
	}

	var pids []string
	for _, tr := range tracks {
		pids = append(pids, tr.pid)
	}
	if _, err := svc.DeleteItems(ctx, admin, pids, "trash", false); err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for since, page := at, 0; ; page++ {
		delta, err := svc.SyncCatalogDelta(ctx, admin, since, 1)
		if err != nil {
			t.Fatal(err)
		}
		if len(delta.Entries) > 1 || page > len(pids) {
			t.Fatalf("page %d = %d entries, want one at a time", page, len(delta.Entries))
		}
		for _, e := range delta.Entries {
			seen[e.PID] = true
		}
		since = delta.NextSince
		if !delta.More {
			break
		}
	}
	if len(seen) != len(pids) {
		t.Fatalf("paged %d items, want %d", len(seen), len(pids))
	}

	// At the floor: a prune took the row the cursor stands on and kept
	// every row after it, so nothing it has not seen is gone.
	floorCursor := snapshotAt(t, ctx, svc, admin)
	growCatalog(t, ctx, svc, 3)
	keepAfter(t, ctx, svc, floorCursor)
	served, err := svc.SyncCatalogDelta(ctx, admin, floorCursor, 10)
	if err != nil {
		t.Fatalf("a cursor at the floor answered %q (%v), want the rows kept after it", KindOf(err), err)
	}
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if moved, _ := decodeCatalogCursor(served.NextSince); moved.seq != head {
		t.Fatalf("a cursor at the floor moved to %d, want the head %d", moved.seq, head)
	}

	epoch, err := svc.grantEpoch(ctx, admin.ID)
	if err != nil {
		t.Fatal(err)
	}
	past := encodeCatalogCursor(feedGen(svc), epoch, head+1, 1)
	if _, err := svc.SyncCatalogDelta(ctx, admin, past, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor past the tail answered %q (%v), want sync-reset", KindOf(err), err)
	}
	old := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf("c1|%s|%d|%d", feedGen(svc), epoch, head)))
	if _, err := svc.SyncCatalogDelta(ctx, admin, old, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor of the earlier shape answered %q (%v), want sync-reset", KindOf(err), err)
	}
}

// The same places for the stream of the caller's own changes, which the
// server prunes nightly.
func TestServerCursorsAtTheirTail(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	at, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}

	still, err := svc.SyncServerDelta(ctx, uc, at, 10)
	if err != nil || len(still.Events) != 0 || still.NextSince != at {
		t.Fatalf("a cursor at the tail = %d events, cursor kept %v (%v), want none and kept",
			len(still.Events), still.NextSince == at, err)
	}

	for _, pid := range []string{"r1", "r2", "r3"} {
		if _, err := svc.db.AppendEvent(ctx, uc.ID, eventReview, pid); err != nil {
			t.Fatal(err)
		}
	}
	first, err := svc.SyncServerDelta(ctx, uc, at, 2)
	if err != nil || len(first.Events) != 2 || !first.More {
		t.Fatalf("the first page = %d events, more %v (%v), want two and more", len(first.Events), first.More, err)
	}
	rest, err := svc.SyncServerDelta(ctx, uc, first.NextSince, 2)
	if err != nil || len(rest.Events) != 1 || rest.More || rest.Events[0].PID != "r3" {
		t.Fatalf("the second page = %+v, more %v (%v), want r3 alone", rest.Events, rest.More, err)
	}

	// At the floor: the nightly prune took the event the cursor stands on
	// and kept every event after it.
	for _, pid := range []string{"r4", "r5", "r6"} {
		if _, err := svc.db.AppendEvent(ctx, uc.ID, eventReview, pid); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.PruneServerEvents(ctx, 3); err != nil {
		t.Fatal(err)
	}
	floor, err := svc.db.EventFloor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if c, _ := decodeServerCursor(rest.NextSince); c.id != floor || c.at == 0 {
		t.Fatalf("cursor at %d (stamped %v), floor %d: the case needs a stamped cursor at the floor", c.id, c.at != 0, floor)
	}
	kept, err := svc.SyncServerDelta(ctx, uc, rest.NextSince, 10)
	if err != nil || len(kept.Events) != 3 {
		t.Fatalf("a cursor at the floor = %d events (%q, %v), want the three kept after it", len(kept.Events), KindOf(err), err)
	}

	tail, _, err := svc.db.LatestEvent(ctx)
	if err != nil {
		t.Fatal(err)
	}
	past := encodeServerCursor(svc.serverGen, tail+1, 1)
	if _, err := svc.SyncServerDelta(ctx, uc, past, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor past the tail answered %q (%v), want sync-reset", KindOf(err), err)
	}
	old := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf("s1|%s|%d", svc.serverGen, tail)))
	if _, err := svc.SyncServerDelta(ctx, uc, old, 10); KindOf(err) != KindGone {
		t.Errorf("a cursor of the earlier shape answered %q (%v), want sync-reset", KindOf(err), err)
	}
}
