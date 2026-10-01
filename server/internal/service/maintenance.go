package service

// The catalog's maintenance hand-off, WaxDeck's side of it. The catalog's
// suspend and reopen hooks bracket a CLI holding the catalog, and a
// replaced catalog (a restore) resets everything derived from the old one.

import (
	"cmp"
	"context"
	"runtime/debug"
	"strconv"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/oklog/ulid/v2"
)

const (
	// maintenanceWatchInterval is how often the watchdog asks whether a
	// reopen the catalog owes its hook can finish.
	maintenanceWatchInterval = 10 * time.Second
	// maintenanceStuckPasses is how many passes find the catalog closed
	// with no holder before the watchdog reopens it: longer than any
	// hand-off spends between one holder and the next.
	maintenanceStuckPasses = 6
)

// Maintenance reports a hand-off in progress: the catalog is suspended,
// or reopened with its reopen hook not yet run.
func (l *Library) Maintenance() bool { return l.maintenance.Load() }

// SetCatalogResyncer wires what tells every client to re-mirror the
// catalog; unset is a no-op.
func (l *Library) SetCatalogResyncer(f func()) { l.catalogResync.Store(&f) }

func (l *Library) fireCatalogResync() {
	if f := l.catalogResync.Load(); f != nil {
		(*f)()
	}
}

// onSuspend is the catalog's suspend hook. The store is closing, so it
// touches nothing of the catalog. It waits out a watchdog's reopen, so
// none can land inside the hand-off beginning here.
func (l *Library) onSuspend(ctx context.Context) {
	defer l.recoverHook("suspend")
	l.watchMu.Lock()
	l.maintenanceMu.Lock()
	gen := l.suspendGen.Add(1)
	l.maintenance.Store(true)
	l.unownedPasses = 0
	l.maintenanceMu.Unlock()
	l.watchMu.Unlock()
	every := cmp.Or(l.maintenanceWatchEvery, maintenanceWatchInterval)
	l.workers.GoOnce(l.procCtx, "maintenance-watch", func(ctx context.Context) error {
		l.watchMaintenance(ctx, gen, every)
		return nil
	})
	if l.suspendHook != nil {
		l.suspendHook(ctx)
	}
}

// endMaintenance drops the flag the suspend numbered gen raised, unless
// a later suspend has raised it again.
func (l *Library) endMaintenance(gen uint64) {
	l.maintenanceMu.Lock()
	defer l.maintenanceMu.Unlock()
	if l.suspendGen.Load() == gen {
		l.maintenance.Store(false)
	}
}

// watchMaintenance finishes a reopen whose last steps failed, which the
// catalog would otherwise leave to the next hand-off. It reopens only a
// catalog that answers, never the store a CLI holds.
func (l *Library) watchMaintenance(ctx context.Context, gen uint64, every time.Duration) {
	tick := time.NewTicker(every)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		if !l.finishOwedReopen(ctx, gen) {
			return
		}
	}
}

// finishOwedReopen runs one watchdog pass, reporting whether hand-off gen is
// still on. A catalog that answers owes only its hook; one closed with no
// holder for maintenanceStuckPasses is a failed reopen nothing else retries.
func (l *Library) finishOwedReopen(ctx context.Context, gen uint64) bool {
	l.watchMu.Lock()
	defer l.watchMu.Unlock()
	if !l.Maintenance() || l.suspendGen.Load() != gen {
		return false
	}
	if _, err := l.lib.LatestChangeSeq(ctx); err != nil {
		if _, held := waxbin.ReadLockOwner(l.catalogPath); held == nil {
			l.unownedPasses = 0
			return true
		}
		l.unownedPasses++
		if l.unownedPasses < cmp.Or(l.maintenanceStuckPasses, maintenanceStuckPasses) {
			return true
		}
		if l.unownedPasses == cmp.Or(l.maintenanceStuckPasses, maintenanceStuckPasses) {
			l.log.Warn("the catalog stayed closed after a hand-off with nothing holding it; reopening it")
		}
	}
	if err := l.lib.Reopen(ctx); err != nil {
		l.log.Warn("finishing the catalog's reopen after a hand-off", "err", err)
	}
	return l.Maintenance()
}

// onReopen is the catalog's reopen hook. Proxied clients wait on it, so it
// rebuilds what requests read and leaves the rest to a worker, and it
// never calls back through the proxy.
func (l *Library) onReopen(ctx context.Context, ev waxbin.ReopenEvent) {
	defer l.endMaintenance(l.suspendGen.Load())
	defer l.recoverHook("reopen")
	if ev.Replaced {
		l.catalogReplaced(ctx, ev.Seq, l.tsOf(ctx, ev.Seq))
		return
	}
	l.refreshLibraryState(ctx)
	l.settleAfterReopen()
}

// recoverHook keeps a panicking hook from taking the process down: the
// catalog runs its hooks on its own goroutines, outside supervise.
func (l *Library) recoverHook(name string) {
	if r := recover(); r != nil {
		l.log.Error("the catalog's "+name+" hook panicked", "panic", r, "stack", string(debug.Stack()))
	}
}

// settleAfterReopen registers the configured roots again, which a
// restored catalog may lack, maps accounts a failed mapping left out, and
// settles the origins of jobs it lost.
func (l *Library) settleAfterReopen() {
	l.workers.GoOnce(l.procCtx, "reopen-settle", func(ctx context.Context) error {
		for wait := time.Second; l.usersUnmapped.Load() && wait <= 16*time.Second; wait *= 2 {
			if err := l.reconcileCatalogUsers(ctx); err == nil {
				break
			}
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(wait):
			}
		}
		if err := l.settleRoots(ctx); err != nil {
			l.log.Warn("registering the configured roots after a reopen", "err", err)
		}
		l.syncFlowRoots(ctx)
		l.settleOrigins(ctx)
		return nil
	})
}

// tsOf reads the timestamp of the change row at seq; 0 when unreadable.
func (l *Library) tsOf(ctx context.Context, seq int64) int64 {
	if seq <= 0 {
		return 0
	}
	rows, err := l.lib.Changes(ctx, seq-1)
	if err != nil || len(rows) == 0 || rows[0].Seq != seq {
		return 0
	}
	return rows[0].TS
}

// catalogReplaced drops what was derived from a replaced catalog and
// resumes the feed from the new one's catalog row (seq, ts). The hook and
// the feed both report it; the pair makes the second a no-op.
func (l *Library) catalogReplaced(ctx context.Context, seq, ts int64) bool {
	l.resetMu.Lock()
	defer l.resetMu.Unlock()
	l.feed.mu.Lock()
	key := feedKey{seq: seq, ts: ts}
	if ts != 0 && l.feed.resetKey == key {
		l.feed.mu.Unlock()
		return false
	}
	gen := ulid.Make().String()
	l.feed.gen, l.feed.tail, l.feed.tailTS, l.feed.floor = gen, seq, ts, seq
	l.feed.resetKey, l.feed.bootTS = key, 0
	l.feed.mints++
	mints := l.feed.mints
	l.feed.mu.Unlock()
	l.log.Info("the catalog was replaced; resetting what was derived from it", "seq", seq)
	if err := l.persistGeneration(ctx, gen, mints); err != nil {
		l.log.Warn("persisting the catalog generation", "err", err)
	}
	l.persistFeedCursor(ctx, true)

	if err := l.reconcileCatalogUsers(ctx); err != nil {
		l.log.Warn("mapping accounts to the replaced catalog's users", "err", err)
	}
	l.refreshLibraryState(ctx)
	if err := l.paths.Poll(ctx); err != nil {
		l.log.Warn("dropping the replaced catalog's file locations", "err", err)
	}
	l.InvalidatePodpingFeeds()
	l.forgetNowPlayingMemos()
	if _, err := l.rewindGenreSweep(ctx); err != nil {
		l.log.Warn("rewinding the genre sweep over the replaced catalog", "err", err)
	}
	if err := l.rewindDiscoverySweep(ctx, seq); err != nil {
		l.log.Warn("rewinding the discovery sweep over the replaced catalog", "err", err)
	}
	l.jobs.forget()
	l.fireCatalogResync()
	l.settleAfterReopen()
	return true
}

// persistGeneration stores a newly minted generation and the mint count.
func (l *Library) persistGeneration(ctx context.Context, gen string, mints int64) error {
	if err := l.db.SyncStateSet(ctx, syncKeyCatalogGen, gen); err != nil {
		return err
	}
	return l.db.SyncStateSet(ctx, syncKeyCatalogMints, strconv.FormatInt(mints, 10))
}
