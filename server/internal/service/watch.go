package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/scan"
)

// The library watcher notices files placed into the roots by hand - not
// through a client - and catalogs them without waiting for a manual
// rescan or the scan schedule. Events coalesce to their directory and
// wait out a settle window, so a multi-file album copy lands as one
// scoped incremental scan of a finished directory rather than a scan
// per file; the scan is the ordinary waxbin fast-path, so the
// organizer's own moves and upload imports ride the same debounce and
// cost a stat pass. The scans run on their own worker, never on the
// event loop: a long scan with the kernel queue undrained would drop
// the very events it was scanning for. Filesystem events are unreliable
// on network mounts (NFS, SMB, 9p), which is what the opt-in scan
// schedule remains for; the watcher degrades to that advice rather than
// dying.

const (
	// watchSettleDefault is how long a directory must stay event-quiet
	// before its rescan fires: long enough for a slow album copy to
	// finish, short enough that a dropped file appears while the person
	// who dropped it is still looking.
	watchSettleDefault = 10 * time.Second
	// watchSweepEvery paces the settle sweep; it bounds how stale a
	// quiet-check can be, not how fast events are noticed.
	watchSweepEvery = time.Second
	// watchLibraryDirCap collapses a flood of pending directories under
	// one library (a deep tree move) into a single whole-library scan
	// rather than a scan job per directory.
	watchLibraryDirCap = 8
	// watchRecheckDefault is how often a root folder that was not there
	// is looked for again: a drive mounted later is watched once it is.
	watchRecheckDefault = time.Minute
)

// writeProbePrefix begins the name of the file probeWritable makes and
// removes in a managed root.
const writeProbePrefix = ".waxdeck-write-probe-"

// watchExhaustionHint makes a degraded warning actionable: on Linux the
// usual cause of a refused watch is the per-user inotify budget.
const watchExhaustionHint = "raise fs.inotify.max_user_watches, or enable the daily scan schedule"

// watchPending tracks event-touched directories until they have been
// quiet for the settle window. The event loop notes and sweeps; the
// scan worker requeues what it could not run - hence the lock.
type watchPending struct {
	settle time.Duration
	mu     sync.Mutex
	dirs   map[string]time.Time // directory -> last event
	// owed are the roots pending only for the catch-up a root the watcher
	// takes up is owed, each with when a catalog scan must have started to
	// cover it instead (zero: any scan of it since it was registered).
	owed map[string]int64
}

func newWatchPending(settle time.Duration) *watchPending {
	if settle <= 0 {
		settle = watchSettleDefault
	}
	return &watchPending{settle: settle, dirs: map[string]time.Time{}, owed: map[string]int64{}}
}

// note records an event; a directory already pending has its quiet
// window restarted, and is scanned whatever covered it.
func (p *watchPending) note(dir string, now time.Time) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.dirs[dir] = now
	delete(p.owed, dir)
}

// owe pends a root's catch-up, which a catalog scan started at or after
// since covers. A root pending for an event stays owed its scan.
func (p *watchPending) owe(root string, since int64, now time.Time) {
	p.mu.Lock()
	defer p.mu.Unlock()
	prev, owed := p.owed[root]
	if _, pending := p.dirs[root]; !pending || owed {
		p.owed[root] = max(prev, since)
	}
	p.dirs[root] = now
}

// renote is note for work taken but not run: each waits the window out
// again, owing what it owed.
func (p *watchPending) renote(dirs []string, now time.Time) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, dir := range dirs {
		p.dirs[dir] = now
	}
}

// owedSince reports whether dir is pending only as a root's catch-up, and
// since when a catalog scan covers it.
func (p *watchPending) owedSince(dir string) (int64, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	since, ok := p.owed[dir]
	return since, ok
}

// paid forgets the catch-up dir owed since since, scanned or covered; one
// owed again meanwhile stays.
func (p *watchPending) paid(dir string, since int64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if prev, ok := p.owed[dir]; ok && prev == since {
		delete(p.owed, dir)
	}
}

// due removes and returns every directory quiet for the settle window,
// in a stable order.
func (p *watchPending) due(now time.Time) []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	var out []string
	for dir, last := range p.dirs {
		if now.Sub(last) >= p.settle {
			out = append(out, dir)
			delete(p.dirs, dir)
		}
	}
	sort.Strings(out)
	return out
}

// restore puts an undispatched batch back as already settled, so the
// next sweep offers it again without a fresh quiet window. For work
// that was taken but could not run, use note: that one waits the full
// window out.
func (p *watchPending) restore(dirs []string, now time.Time) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, dir := range dirs {
		p.dirs[dir] = now.Add(-p.settle)
	}
}

// watchLibraries runs the live watcher until ctx ends. Spawned by Open
// under the supervised group; an error return restarts it with backoff,
// a nil return - no event facility at all - degrades to the scan
// schedule for good. Pending directories live on the Library and so
// survive a re-arm: a runtime library create cannot drop changes the
// other roots had already noticed.
func (l *Library) watchLibraries(ctx context.Context) error {
	arms := &watchArms{absent: map[string]bool{}}
	for {
		rearm, err := l.watchOnce(ctx, arms)
		if err != nil || !rearm {
			return err
		}
	}
}

// watchArms is what one arm pass leaves the next: the roots said to be
// missing, so an outage is said once, and the roots watched, nil before
// the first pass.
type watchArms struct {
	absent  map[string]bool
	watched map[string]bool
}

// watchOnce arms watches over the current roots and services events
// until ctx ends (false), the root table or watch coverage goes stale
// (true: re-arm fresh), or the event stream breaks (an error, so the
// supervisor restarts it with backoff). A root whose folder is missing
// is left out and looked for again.
func (l *Library) watchOnce(ctx context.Context, arms *watchArms) (rearm bool, err error) {
	roots := l.libraryRoots()
	if len(roots) == 0 {
		// Nothing to watch yet. Hold for a runtime library create
		// instead of giving up: an install whose roots are added in the
		// console gets the watcher the moment the first one lands.
		arms.watched = map[string]bool{}
		select {
		case <-ctx.Done():
			return false, nil
		case <-l.watchNudge:
			return true, nil
		}
	}
	w, err := fsnotify.NewWatcher()
	if err != nil {
		// No event facility here at all: permanent, so degrade for good
		// rather than restarting into the same refusal.
		l.log.Warn("library watch unavailable; use manual rescans or the scan schedule", "err", err)
		return false, nil
	}
	defer w.Close()

	armed, failed := 0, 0
	var missing []string
	watched := map[string]bool{}
	for _, root := range roots {
		if !rootPresent(root.Path) {
			missing = append(missing, root.Path)
			if !arms.absent[root.Path] {
				arms.absent[root.Path] = true
				l.log.Warn("library root is not present; not watched", "library", root.Name, "path", root.Path)
			}
			continue
		}
		back := arms.absent[root.Path]
		if back {
			delete(arms.absent, root.Path)
			l.log.Info("library root is present again; watching it", "library", root.Name, "path", root.Path)
		}
		// A root taken up after the first pass may hold files its last scan
		// never saw and no event will announce: one added since, unless a
		// catalog scan of it (its create's) covers it, and one back from an
		// outage, unless a scan started after it came back does.
		if arms.watched != nil && !arms.watched[root.Path] {
			now := time.Now()
			var since int64
			if back {
				since = now.UnixNano()
			}
			l.watchQueue.owe(root.Path, since, now)
		}
		watched[root.Path] = true
		a, f := watchTree(w, root.Path)
		armed, failed = armed+a, failed+f
	}
	arms.watched = watched
	var recheck <-chan time.Time
	if len(missing) > 0 {
		tick := time.NewTicker(cmp.Or(l.watchRecheck, watchRecheckDefault))
		defer tick.Stop()
		recheck = tick.C
	}
	switch {
	case armed == 0 && failed == 0:
		// Every root's folder is missing: nothing to arm until one is there.
		for {
			select {
			case <-ctx.Done():
				return false, nil
			case <-l.watchNudge:
				return true, nil
			case <-recheck:
				l.log.Debug("looking again for missing library roots", "missing", len(missing))
				if slices.ContainsFunc(missing, rootPresent) {
					return true, nil
				}
			}
		}
	case armed == 0:
		// Nothing armable right now - a bind mount that is not up yet,
		// or an exhausted inotify budget. Both can heal, so hand the
		// supervisor an error and retry with its backoff rather than
		// degrading for good.
		l.log.Warn("no library directory could be watched; retrying, or use manual rescans or the scan schedule",
			"failed", failed, "hint", watchExhaustionHint)
		return false, errors.New("no library directory could be watched")
	case failed > 0:
		l.log.Warn("some library directories are not watched; the scan schedule covers what events miss",
			"watched", armed, "unwatched", failed, "hint", watchExhaustionHint)
	default:
		l.log.Info("watching library roots for manual changes", "dirs", armed)
	}
	l.noteWatchArmed()

	sweep := time.NewTicker(watchSweepEvery)
	defer sweep.Stop()
	for {
		select {
		case <-ctx.Done():
			return false, nil
		case <-l.watchNudge:
			return true, nil
		case ev, ok := <-w.Events:
			if !ok {
				return false, errors.New("the filesystem event stream closed")
			}
			noteWatchEvent(w, l.watchQueue, ev)
		case werr, ok := <-w.Errors:
			if !ok {
				return false, errors.New("the filesystem event stream closed")
			}
			// An overflow means events were missed - creates included, so
			// both the catalog and the watch table are stale. Queue a
			// whole-root catch-up scan and re-arm from scratch, which is
			// what picks up directories born inside the gap.
			l.log.Warn("filesystem events dropped; scheduling a catch-up scan", "err", werr)
			now := time.Now()
			for _, root := range l.libraryRoots() {
				l.watchQueue.note(root.Path, now)
			}
			return true, nil
		case <-sweep.C:
			l.dispatchWatchScans()
		case <-recheck:
			l.log.Debug("looking again for missing library roots", "missing", len(missing))
			if slices.ContainsFunc(missing, rootPresent) {
				return true, nil
			}
		}
	}
}

// scannedSince reports whether a scan the catalog keeps, started at or
// after since, walked the folder of the library pid.
func (l *Library) scannedSince(ctx context.Context, pid string, since int64) bool {
	jobs, err := l.lib.Jobs(ctx, reachSeedWindow)
	if err != nil {
		return false
	}
	for _, j := range jobs {
		if j.Kind != "scan" || j.State != model.JobDone || j.StartedAt < since {
			continue
		}
		var r struct{ Runs []scan.Result }
		if json.Unmarshal([]byte(j.Result), &r) != nil {
			continue
		}
		if slices.ContainsFunc(r.Runs, func(run scan.Result) bool {
			return string(run.LibraryPID) == pid && !run.RootUnreachable
		}) {
			return true
		}
	}
	return false
}

// rootPresent reports whether a root's folder is there to watch.
func rootPresent(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.IsDir()
}

// dispatchWatchScans hands the settled directories to the scan worker.
// It never blocks: a scan can run minutes on a big drop, and this loop
// is what keeps the kernel's event queue drained meanwhile - the reason
// the worker exists at all. A busy worker leaves the batch settled for
// the next sweep.
func (l *Library) dispatchWatchScans() {
	now := time.Now()
	due := l.watchQueue.due(now)
	if len(due) == 0 {
		return
	}
	select {
	case l.watchScans <- due:
	default:
		l.watchQueue.restore(due, now)
	}
}

// watchScanWorker runs the scans the watcher schedules, off the event
// loop. Spawned by Open beside watchLibraries.
func (l *Library) watchScanWorker(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return nil
		case dirs := <-l.watchScans:
			l.runWatchScans(ctx, dirs)
		}
	}
}

// runWatchScans scans one settled batch. It defers whole while a
// catalog job runs, the way SweepDiscoveries does: a scan mid-import
// would only lose the shared filesystem lease.
func (l *Library) runWatchScans(ctx context.Context, due []string) {
	// Deferred work is re-noted at the moment the competing job was
	// seen, so it waits a whole settle window out before retrying
	// rather than hammering the lease at sweep cadence.
	requeue := func(dirs []string) {
		l.watchQueue.renote(dirs, time.Now())
	}
	if running, err := l.catalogJobRunning(ctx); err != nil || running {
		requeue(due)
		return
	}
	byLib := map[string][]string{}
	// owed is what each root's catch-up in the batch was owed since.
	owed := map[string]int64{}
	for _, dir := range due {
		pid, err := l.libraryForPath(ctx, dir)
		if err != nil {
			requeue([]string{dir})
			continue
		}
		since, isOwed := l.watchQueue.owedSince(dir)
		if pid == "" {
			l.watchQueue.paid(dir, since)
			continue // outside every root by the time it settled
		}
		if isOwed {
			if l.scannedSince(ctx, pid, since) {
				l.watchQueue.paid(dir, since)
				if l.watchScanHook != nil {
					l.watchScanHook(dir, false)
				}
				continue
			}
			owed[dir] = since
		}
		byLib[pid] = append(byLib[pid], dir)
	}
	for pid, dirs := range byLib {
		scanDirs := dirs
		collapsed := false
		if len(dirs) > watchLibraryDirCap {
			scanDirs = []string{""}
			collapsed = true
		}
		for i, dir := range scanDirs {
			if ctx.Err() != nil {
				return
			}
			res, err := l.lib.Scan(ctx, waxbin.ScanRequest{LibraryPID: model.PID(pid), SubPath: dir})
			if err != nil {
				serr := classify(err)
				if KindOf(serr) == KindConflict {
					// Another filesystem mutator took the lease since the
					// check above; wait it out and settle again. Only what
					// has not scanned yet goes back.
					if collapsed {
						requeue(dirs)
					} else {
						requeue(dirs[i:])
					}
					break
				}
				l.log.Warn("library watch scan", "library", pid, "dir", dir, "err", serr)
				continue
			}
			// No job keeps this scan's runs, and a folder back from an
			// outage is first scanned here.
			l.noteReach(ctx, res.Runs, time.Now().UnixNano())
			scanned := []string{dir}
			if collapsed {
				scanned = dirs
			}
			for _, d := range scanned {
				if since, ok := owed[d]; ok {
					l.watchQueue.paid(d, since)
				}
			}
			if l.watchScanHook != nil {
				l.watchScanHook(dir, true)
			}
		}
	}
}

// underWatchTrash reports whether path has a trash directory anywhere
// on it. The catalog trashes into <root>/.waxbin-trash/, inside the
// tree the watcher covers, and a delete fires create events there;
// watching or scanning under it would re-catalog the very file the
// delete just removed.
func underWatchTrash(path string) bool {
	for _, part := range strings.Split(filepath.ToSlash(path), "/") {
		if part == model.TrashDirName {
			return true
		}
	}
	return false
}

// noteWatchEvent coalesces one event to its directory. A directory
// created inside a watched tree is armed immediately - inotify watches
// are per directory - and scheduled itself, since files can land in it
// before its watch exists.
func noteWatchEvent(w *fsnotify.Watcher, pending *watchPending, ev fsnotify.Event) {
	if underWatchTrash(ev.Name) || strings.HasPrefix(filepath.Base(ev.Name), writeProbePrefix) {
		return
	}
	now := time.Now()
	if ev.Op.Has(fsnotify.Create) {
		if info, err := os.Lstat(ev.Name); err == nil && info.IsDir() {
			watchTree(w, ev.Name)
			pending.note(ev.Name, now)
			return
		}
	}
	pending.note(filepath.Dir(ev.Name), now)
}

// watchTree arms a watch on every directory under root. inotify is per
// directory, so a recursive watch is a walk; a directory that refuses
// (the kernel watch budget, permissions) or cannot be read at all is
// counted and skipped, and stays covered by scheduled scans only. The
// trash directory is left out on purpose.
func watchTree(w *fsnotify.Watcher, root string) (armed, failed int) {
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			failed++
			return nil
		}
		if !d.IsDir() {
			return nil
		}
		if d.Name() == model.TrashDirName {
			return fs.SkipDir
		}
		if err := w.Add(path); err != nil {
			failed++
			return nil
		}
		armed++
		return nil
	})
	return armed, failed
}

// noteWatchArmed closes the ready channel once, so a test can drop its
// file only after the watches exist.
func (l *Library) noteWatchArmed() {
	l.watchReadyOnce.Do(func() { close(l.watchReady) })
}
