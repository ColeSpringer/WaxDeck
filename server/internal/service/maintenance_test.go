package service

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/port"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// openServiceAt opens the service over dataDir with one configured root
// and an admin account, stopping it at cleanup or when stop is called.
func openServiceAt(t *testing.T, dataDir string, mutate func(*Config)) (context.Context, *Library, *UserCtx, func()) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.DiscardHandler)
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	// No background path poll: its reads race the catalog's reopen
	// upstream, and these tests drive hand-offs.
	cfg := Config{DataDir: dataDir, Roots: []Root{{Name: "configured", Path: filepath.Join(dataDir, "configured")}},
		Logger: log, PathPollInterval: -1}
	if err := os.MkdirAll(cfg.Roots[0].Path, 0o755); err != nil {
		t.Fatal(err)
	}
	if mutate != nil {
		mutate(&cfg)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, cfg, store, group)
	if err != nil {
		cancel()
		group.Wait()
		store.Close()
		t.Fatal(err)
	}
	svc.maintenanceWatchEvery = time.Hour
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	}
	t.Cleanup(stop)
	u, err := svc.UserByName(ctx, "admin")
	if errors.Is(err, wdb.ErrNotFound) {
		acct, cerr := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
		if cerr != nil {
			t.Fatal(cerr)
		}
		u, err = acct.User, nil
	}
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, u)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc, stop
}

func feedGen(l *Library) string {
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.gen
}

func feedTail(l *Library) int64 {
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.tail
}

// feedCaughtUp waits for the feed consumer to reach the catalog's head,
// so a late reset of its own would have landed.
func feedCaughtUp(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	waitFor(t, func() bool {
		head, err := svc.lib.LatestChangeSeq(ctx)
		return err == nil && feedTail(svc) >= head
	}, "the feed reaching the catalog's head")
}

// countResyncs counts the catalog resyncs the service asks clients for.
func countResyncs(l *Library) *atomic.Int32 {
	var n atomic.Int32
	l.SetCatalogResyncer(func() { n.Add(1) })
	return &n
}

// backupOf builds a catalog in its own directory, lets fill shape it,
// and returns a backup of it.
func backupOf(t *testing.T, fill func(context.Context, *waxbin.Library)) string {
	t.Helper()
	ctx := context.Background()
	lib := openBareCatalog(t, waxbin.Options{})
	fill(ctx, lib)
	out := filepath.Join(t.TempDir(), "backup.db")
	if err := lib.Backup(ctx, out, false); err != nil {
		t.Fatal(err)
	}
	return out
}

// restoreUnder restores backup over the service's catalog inside a
// maintenance hand-off, the way `waxbin restore` does.
func restoreUnder(t *testing.T, ctx context.Context, svc *Library, dataDir, backup string) {
	t.Helper()
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if err := port.Restore(ctx, backup, filepath.Join(dataDir, "waxbin.db"), true); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
}

func catalogRowSeq(t *testing.T, ctx context.Context, svc *Library) int64 {
	t.Helper()
	var seq int64
	for since := int64(0); ; {
		rows, err := svc.lib.Changes(ctx, since)
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) == 0 {
			return seq
		}
		for _, r := range rows {
			if r.EntityType == model.ChangeCatalog {
				seq = r.Seq
			}
		}
		since = rows[len(rows)-1].Seq
	}
}

// A hand-off that reopens the same catalog is a pause: reads and writes
// meanwhile answer maintenance, and the feed runs on.
func TestASameCatalogHandOffKeepsTheFeed(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	resyncs := countResyncs(svc)
	gen, key := feedGen(svc), svc.CatalogTailSeq()

	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if !svc.Maintenance() {
		t.Error("not in maintenance during the hand-off")
	}
	if _, err := svc.lib.Libraries(ctx); KindOf(err) != KindMaintenance {
		t.Errorf("a read during the hand-off answered %q (%v)", KindOf(err), err)
	}
	if _, err := svc.lib.CreateUser(ctx, "during"); KindOf(err) != KindMaintenance {
		t.Errorf("a write during the hand-off answered %q (%v)", KindOf(err), err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if svc.Maintenance() {
		t.Error("still in maintenance after the reopen")
	}
	if feedGen(svc) != gen || resyncs.Load() != 0 || svc.CatalogTailSeq() < key {
		t.Errorf("generation %s -> %s, %d resyncs, key %d -> %d; want the feed running on",
			gen, feedGen(svc), resyncs.Load(), key, svc.CatalogTailSeq())
	}
}

// A restored catalog is another catalog: the accounts map to its users,
// the feed starts a new generation from its catalog row, the sweeps
// rewind, roots and origins follow it, and clients are told to re-mirror.
func TestARestoredCatalogResetsWhatWasDerivedFromTheOld(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	resyncs := countResyncs(svc)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	bRoot := t.TempDir()
	var userB model.PID
	backup := backupOf(t, func(ctx context.Context, lib *waxbin.Library) {
		if _, err := lib.AddRoot(ctx, config.Root{Path: bRoot}); err != nil {
			t.Fatal(err)
		}
		u, err := lib.CreateUser(ctx, uc.ID)
		if err != nil {
			t.Fatal(err)
		}
		userB = u.PID
	})
	lost := "01JZX5N8QW3F4V9T2B7KD3M9R6"
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: lost, UserID: uc.ID, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	gen, key := feedGen(svc), svc.CatalogTailSeq()

	restoreUnder(t, ctx, svc, dataDir, backup)

	u, err := svc.UserByName(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	after, err := svc.UserCtx(ctx, u)
	if err != nil || after.CatalogPID != string(userB) {
		t.Errorf("the admin acts as %q (%v), want the restored catalog's user %s", after.CatalogPID, err, userB)
	}
	row, tail := catalogRowSeq(t, ctx, svc), feedTail(svc)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if feedGen(svc) == gen || tail < row || tail > head || svc.CatalogTailSeq() <= key {
		t.Errorf("generation %s -> %s, tail %d (catalog row %d, head %d), key %d -> %d; want a new generation from the row",
			gen, feedGen(svc), tail, row, head, key, svc.CatalogTailSeq())
	}
	waitFor(t, func() bool {
		names := map[string]string{}
		for _, r := range svc.libraryRoots() {
			names[r.Path] = r.Name
		}
		return names[bRoot] == filepath.Base(bRoot) && names[filepath.Join(dataDir, "configured")] == "configured"
	}, "the restored root and the configured one it lacked in the root table")
	waitFor(t, func() bool { return flow.taught(filepath.Base(bRoot), bRoot) },
		"the streaming bridge taught the restored root")
	feedCaughtUp(t, ctx, svc)
	if n := resyncs.Load(); n != 1 {
		t.Errorf("resyncs = %d, want 1", n)
	}
	oldest, err := svc.lib.Changes(ctx, 0)
	if err != nil || len(oldest) == 0 {
		t.Fatalf("changes: %v", err)
	}
	if raw, _ := svc.db.SyncStateGet(ctx, genreSweepCursorKey); raw != strconv.FormatInt(oldest[0].Seq-1, 10) {
		t.Errorf("genre cursor = %q, want the oldest retained change %d less one", raw, oldest[0].Seq)
	}
	if raw, _ := svc.db.SyncStateGet(ctx, discoveryCursorKey); raw != strconv.FormatInt(row, 10) {
		t.Errorf("discovery cursor = %q, want the catalog row %d", raw, row)
	}
	waitFor(t, func() bool {
		has, err := svc.db.HasJobOrigin(ctx, lost)
		return err == nil && !has
	}, "the origin of a job the restored catalog lacks released")
}

// A boot that cannot continue its cursor (a fresh waxdeck.db) mints its
// own generation, so a replacement already in the log rewinds nothing.
func TestABootDoesNotReplayAnOldReplacement(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, stop := openServiceAt(t, dataDir, nil)
	restoreUnder(t, ctx, svc, dataDir, backupOf(t, func(context.Context, *waxbin.Library) {}))
	row := catalogRowSeq(t, ctx, svc)
	stop()
	for _, f := range []string{"waxdeck.db", "waxdeck.db-wal", "waxdeck.db-shm"} {
		if err := os.Remove(filepath.Join(dataDir, f)); err != nil && !errors.Is(err, os.ErrNotExist) {
			t.Fatal(err)
		}
	}
	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return feedTail(svc) >= head }, "the feed draining the log")
	svc.feed.mu.Lock()
	mints := svc.feed.mints
	svc.feed.mu.Unlock()
	cursor, _ := svc.db.SyncStateGet(ctx, discoveryCursorKey)
	if mints != 1 || cursor == strconv.FormatInt(row, 10) {
		t.Errorf("mints = %d, discovery cursor %q (catalog row %d); want the boot's one mint and no rewind", mints, cursor, row)
	}
	// A replacement after the boot is news again, even onto a shorter log.
	svc.advanceFeed(ctx, model.Change{Seq: row, TS: time.Now().UnixNano(), EntityType: model.ChangeCatalog})
	svc.feed.mu.Lock()
	mints = svc.feed.mints
	svc.feed.mu.Unlock()
	if mints != 2 {
		t.Errorf("mints after a later replacement = %d, want 2", mints)
	}
}

// Two restores in a row both reset, the second onto a shorter log whose
// catalog row lands below the first one's, and the key only grows.
func TestTwoRestoresInARowBothReset(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	resyncs := countResyncs(svc)
	long := backupOf(t, func(ctx context.Context, lib *waxbin.Library) {
		for i := range 40 {
			if _, err := lib.CreateUser(ctx, fmt.Sprintf("user-%d", i)); err != nil {
				t.Fatal(err)
			}
		}
	})
	short := backupOf(t, func(ctx context.Context, lib *waxbin.Library) {
		if _, err := lib.CreateUser(ctx, uc.ID); err != nil {
			t.Fatal(err)
		}
	})
	key := svc.CatalogTailSeq()
	restoreUnder(t, ctx, svc, dataDir, long)
	first, firstGen, firstKey := catalogRowSeq(t, ctx, svc), feedGen(svc), svc.CatalogTailSeq()
	restoreUnder(t, ctx, svc, dataDir, short)
	second := catalogRowSeq(t, ctx, svc)
	if second >= first {
		t.Fatalf("the second catalog row %d is not below the first %d", second, first)
	}
	feedCaughtUp(t, ctx, svc)
	if feedGen(svc) == firstGen || resyncs.Load() != 2 || firstKey <= key || svc.CatalogTailSeq() <= firstKey {
		t.Errorf("generations %s -> %s, %d resyncs, keys %d -> %d -> %d; want two resets and a growing key",
			firstGen, feedGen(svc), resyncs.Load(), key, firstKey, svc.CatalogTailSeq())
	}
}

// The reopen hook and the feed's catalog row report one replacement, in
// either order, and it resets once.
func TestTheHookAndTheCatalogRowResetOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	resyncs := countResyncs(svc)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	row := model.Change{Seq: head, TS: svc.tsOf(ctx, head), EntityType: model.ChangeCatalog}
	svc.advanceFeed(ctx, row)
	gen := feedGen(svc)
	svc.onReopen(ctx, waxbin.ReopenEvent{Seq: head, Replaced: true})
	svc.advanceFeed(ctx, row)
	if feedGen(svc) != gen || resyncs.Load() != 1 {
		t.Errorf("generation %s -> %s with %d resyncs, want one reset", gen, feedGen(svc), resyncs.Load())
	}
}

// A hand-off refused once the suspend hook ran still reopens the host:
// the flag drops and nothing resets.
func TestARefusedHandOffResumesTheHost(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	resyncs := countResyncs(svc)
	gen := feedGen(svc)
	handOff, cancel := context.WithCancel(ctx)
	svc.suspendHook = func(context.Context) { cancel() }
	if err := svc.lib.BeginMaintenance(handOff); err == nil {
		t.Fatal("a hand-off canceled in its suspend hook went ahead")
	}
	if svc.Maintenance() || feedGen(svc) != gen || resyncs.Load() != 0 {
		t.Errorf("maintenance %v, generation %s -> %s, %d resyncs; want the host resumed as it was",
			svc.Maintenance(), gen, feedGen(svc), resyncs.Load())
	}
}

// A reopen whose last step failed owes its hook; the watchdog finishes
// it once the catalog answers, and the flag drops.
func TestTheWatchdogFinishesAnOwedReopen(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, _ := openServiceAt(t, dataDir, nil)
	resyncs := countResyncs(svc)
	db := filepath.Join(dataDir, "waxbin.db")
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	blob, err := os.ReadFile(db)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(db+".new", blob, 0o600); err != nil {
		t.Fatal(err)
	}
	execCatalog(t, db+".new", `CREATE TRIGGER refuse_catalog BEFORE INSERT ON change_log
		WHEN NEW.entity_type = 'catalog' BEGIN SELECT RAISE(ABORT, 'refused'); END`)
	if err := os.Rename(db+".new", db); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EndMaintenance(ctx); err == nil {
		t.Fatal("the reopen wrote its catalog row through the trigger")
	}
	if !svc.Maintenance() {
		t.Fatal("the flag dropped before the owed reopen finished")
	}
	execCatalog(t, db, "DROP TRIGGER refuse_catalog")
	// Bounded: a watchdog that never finishes fails here, not the package.
	wctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	svc.watchMaintenance(wctx, svc.suspendGen.Load(), 10*time.Millisecond)
	if svc.Maintenance() || resyncs.Load() != 1 {
		t.Errorf("maintenance %v with %d resyncs after the watchdog, want the owed reopen finished",
			svc.Maintenance(), resyncs.Load())
	}
}

// A watchdog reopens only a catalog that answers: never the store a
// hand-off holds suspended, its own or a later one's.
func TestTheWatchdogNeverReopensASuspendedStore(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, _ := openServiceAt(t, dataDir, nil)
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	earlier := svc.suspendGen.Load()
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if svc.finishOwedReopen(ctx, earlier) {
		t.Error("an earlier hand-off's watchdog kept watching the next one")
	}
	if !svc.finishOwedReopen(ctx, svc.suspendGen.Load()) {
		t.Error("the watchdog gave up on the hand-off in progress")
	}
	if _, err := svc.lib.Libraries(ctx); KindOf(err) != KindMaintenance {
		t.Fatalf("a read after the watchdog passes answered %v, want the store still suspended", err)
	}
	backup := backupOf(t, func(ctx context.Context, lib *waxbin.Library) {
		if _, err := lib.CreateUser(ctx, "from-the-backup"); err != nil {
			t.Fatal(err)
		}
	})
	if err := port.Restore(ctx, backup, filepath.Join(dataDir, "waxbin.db"), true); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	users, err := svc.lib.Users(ctx)
	if err != nil || !slices.ContainsFunc(users, func(u *model.User) bool { return u.Name == "from-the-backup" }) {
		t.Errorf("users after the restore = %v (%v), want the backup's", users, err)
	}
}

func execCatalog(t *testing.T, path, stmt string) {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(stmt); err != nil {
		t.Fatal(err)
	}
}

// The key the caches and Subsonic's lastModified read only grows: across
// a restart, and across a catalog replaced while the server was down.
func TestTheCatalogKeyGrowsAcrossOpens(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, _, stop := openServiceAt(t, dataDir, nil)
	for i := range 20 {
		if _, err := svc.lib.CreateUser(ctx, fmt.Sprintf("user-%d", i)); err != nil {
			t.Fatal(err)
		}
	}
	waitFor(t, func() bool {
		head, err := svc.lib.LatestChangeSeq(ctx)
		return err == nil && feedTail(svc) == head
	}, "the feed at the head")
	first := svc.CatalogTailSeq()
	stop()

	_, svc, _, stop = openServiceAt(t, dataDir, nil)
	restarted := svc.CatalogTailSeq()
	stop()
	if restarted < first {
		t.Errorf("key after a restart = %d, want at least %d", restarted, first)
	}

	backup := backupOf(t, func(context.Context, *waxbin.Library) {})
	if err := port.Restore(context.Background(), backup, filepath.Join(dataDir, "waxbin.db"), true); err != nil {
		t.Fatal(err)
	}
	_, svc, _, _ = openServiceAt(t, dataDir, nil)
	if replaced := svc.CatalogTailSeq(); replaced <= restarted {
		t.Errorf("key over a shorter replaced catalog = %d, want more than %d", replaced, restarted)
	}
}

// A cursor past the feed's head is a replaced catalog: startup mints a
// generation, a client's delta is told to re-mirror, and the sweeps
// rewind rather than fail.
func TestACursorPastTheHeadIsAReplacedCatalog(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	gen := feedGen(svc)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	past := head + 100
	epoch, err := svc.grantEpoch(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SyncCatalogDelta(ctx, uc, encodeCatalogCursor(gen, epoch, past), 10); KindOf(err) != KindGone {
		t.Errorf("a delta past the head answered %q (%v), want sync-reset", KindOf(err), err)
	}
	for _, k := range []string{genreSweepCursorKey, discoveryCursorKey} {
		if err := svc.db.SyncStateSet(ctx, k, strconv.FormatInt(past, 10)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.SweepGenres(ctx); err != nil {
		t.Errorf("genre sweep past the head: %v", err)
	}
	if _, err := svc.SweepDiscoveries(ctx); err != nil {
		t.Errorf("discovery sweep past the head: %v", err)
	}
	now, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := svc.db.SyncStateGet(ctx, discoveryCursorKey)
	if at, err := strconv.ParseInt(raw, 10, 64); err != nil || at < head || at > now {
		t.Errorf("discovery cursor = %q, want the head (%d..%d)", raw, head, now)
	}
	if raw, _ := svc.db.SyncStateGet(ctx, genreSweepCursorKey); raw == strconv.FormatInt(past, 10) {
		t.Errorf("genre cursor stayed past the head at %s", raw)
	}
	stop()

	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SyncStateSet(context.Background(), syncKeyCatalogCursor, fmt.Sprintf("%d|%d", past, 1)); err != nil {
		t.Fatal(err)
	}
	store.Close()
	_, svc, _, _ = openServiceAt(t, dataDir, nil)
	if feedGen(svc) == gen {
		t.Error("startup over a cursor past the head kept the generation")
	}
}

// The durable queues wait out a hand-off rather than burn an attempt,
// and the health sweep keeps a pending request for after it.
func TestTheQueuesWaitOutAHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	task := newToolTask(uc, taskTypeHealthFix, "", toolTaskParams{Rule: ruleMissingLyrics}, "{}")
	if err := svc.db.InsertToolTask(ctx, task); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.EnqueueRetention(ctx, "pc-show", 1); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.SettingSet(ctx, healthSweepReqKey, uc.ID+"@1", 1); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if svc.DrainHealthFixes(ctx) || svc.DrainToolTasks(ctx) || svc.DrainMatchQueue(ctx) || svc.DrainFetchQueue(ctx) {
		t.Error("a queue drained during the hand-off")
	}
	svc.SweepRetention(ctx)
	if svc.HealthSweepDue(ctx) {
		t.Error("the health sweep came due during the hand-off")
	}
	svc.sweepEnded(ctx, uc.ID+"@1", &Error{Kind: KindMaintenance})
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if row, err := svc.db.ToolTaskByID(ctx, task.ID); err != nil || row.State != "queued" || row.Attempts != 0 {
		t.Errorf("task = %+v (%v), want it queued and unattempted", row, err)
	}
	if shows, err := svc.db.TakeRetentionQueue(ctx); err != nil || len(shows) != 1 {
		t.Errorf("retention queue = %v (%v), want the show still queued", shows, err)
	}
	if !svc.SweepRequested(ctx) || svc.sweepFailed.Load() {
		t.Error("a sweep cut short by the hand-off answered its request or read as failed")
	}
}

// A user mapping that failed with the replacement is retried by the settle
// rather than left on the old catalog's users.
func TestAFailedUserMappingIsRetried(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if err := svc.reconcileCatalogUsers(ctx); err == nil {
		t.Fatal("the mapping read a suspended catalog")
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return !svc.usersUnmapped.Load() }, "the settle mapping the accounts again")
}

// A hook that panics still ends the hand-off: the catalog's own goroutine
// has no recover, and the flag would stay up.
func TestAPanickingHookEndsTheHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	svc.SetCatalogResyncer(func() { panic("resync") })
	svc.suspendHook = func(context.Context) { panic("suspend") }
	svc.onSuspend(ctx)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.onReopen(ctx, waxbin.ReopenEvent{Seq: head, Replaced: true})
	if svc.Maintenance() {
		t.Error("the flag stayed up after a panicking reopen hook")
	}
}

// A catalog left closed with nothing holding it, a reopen that failed
// outright, is reopened by the watchdog once the hand-off has gone quiet.
func TestTheWatchdogReopensAnAbandonedCatalog(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	svc.maintenanceStuckPasses = 2
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	gen := svc.suspendGen.Load()
	if !svc.finishOwedReopen(ctx, gen) || !svc.Maintenance() {
		t.Fatal("the watchdog reopened on its first quiet pass")
	}
	svc.finishOwedReopen(ctx, gen)
	if svc.Maintenance() {
		t.Error("the watchdog left an abandoned catalog closed")
	}
}

// A staged restore keeps the catalog key growing past both databases'
// mint counts, and drops the rest of the stream positions.
func TestARestoreKeepsTheMintCountGrowing(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	for k, v := range map[string]string{syncKeyCatalogMints: "5", syncKeyCatalogCursor: "9|9"} {
		if err := store.SyncStateSet(ctx, k, v); err != nil {
			t.Fatal(err)
		}
	}
	store.Close()
	live := PeekCatalogMints(dataDir)
	store, err = wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	if err := store.SyncStateSet(ctx, syncKeyCatalogMints, "2"); err != nil {
		t.Fatal(err)
	}
	if err := ResetSyncAfterRestore(ctx, store, live); err != nil {
		t.Fatal(err)
	}
	mints, _ := store.SyncStateGet(ctx, syncKeyCatalogMints)
	cursor, _ := store.SyncStateGet(ctx, syncKeyCatalogCursor)
	if live != 5 || mints != "5" || cursor != "" {
		t.Errorf("live %d, mints %q, cursor %q; want the live count kept and the cursor dropped", live, mints, cursor)
	}
}

// The background sweeps skip a tick while the catalog is handed off,
// rather than logging its closed store as their failure.
func TestTheSweepsSkipATickDuringAHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), func(c *Config) { c.WorkerAPIConfigured = true })
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := svc.lib.EndMaintenance(ctx); err != nil {
			t.Fatal(err)
		}
	}()
	if _, err := svc.SweepGenres(ctx); err != nil {
		t.Errorf("genre sweep: %v", err)
	}
	if _, err := svc.SweepDiscoveries(ctx); err != nil {
		t.Errorf("discovery sweep: %v", err)
	}
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Errorf("similarity sweep: %v", err)
	}
	if err := svc.db.SettingSet(ctx, settingTrashRetention, "1", 1); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SweepTrashRetention(ctx); err != nil {
		t.Errorf("trash retention sweep: %v", err)
	}
}
