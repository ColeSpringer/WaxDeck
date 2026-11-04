package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
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
//
// What the watcher keeps true:
//   - Coverage: every directory under a present root that the kernel lets
//     it watch is in the watch table under its current path, and nothing
//     outside a present root outlives the answer of the look that added it.
//   - No stale paths: a rename drops the old path's entry and every entry
//     under it before the new path is armed.
//   - Gaps are caught up: what lands in a directory while it has no watch
//     is covered by a scan started after its watch exists - the note a
//     newly armed directory gets, or its root's owed catch-up.
//   - The loop never looks at the filesystem: it keeps the watch table,
//     the queue and its own state; every stat, walk and mount-table read
//     is a look on a worker of its own, one at a time per root.
//   - A root delays only itself: a pass skips a root whose look is out and
//     waits for its own looks to a bound; only a look whose stat has not
//     answered is said not to answer.
//   - Nothing loops: a recheck runs a pass only for a change since the
//     last look, and the pass clears what triggered it.
//   - What is owed: the process's first pass owes nothing; every later
//     take-up, a supervised restart's included, owes its root a catch-up.
//   - No lock cycle: fsnotify sends its errors holding its own lock, so a
//     worker drains them and the loop never waits on that lock while
//     fsnotify waits on the loop.

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
	// cover it instead: once its watch was armed.
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
//
// One kernel watcher serves every pass, so a root already watched keeps
// its watches while a pass takes another up or lets one go: a re-arm
// never leaves it blind. This loop keeps the books only - the watch
// table, the queue, the state below. Every stat, walk and mount-table
// read is a look at one root on a worker of its own, one at a time per
// root, so a root whose folder stops answering, as a hard network mount
// whose server is gone does, holds only its own look.
func (l *Library) watchLibraries(ctx context.Context) error {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		// No event facility here at all: permanent, so degrade for good
		// rather than restarting into the same refusal.
		l.log.Warn("library watch unavailable; use manual rescans or the scan schedule", "err", err)
		return nil
	}
	defer w.Close()
	l.watcher.Store(w)
	// A look still out when this run ends drops its answer.
	runCtx, stop := context.WithCancel(ctx)
	defer stop()
	arms := newWatchArms(runCtx, w)
	// fsnotify's reader sends an error holding its lock, which every table
	// call (and Close) waits for: a worker of this run's own takes every
	// error at once, so the lock is always let go. It ends when Close ends
	// the stream. Only an overflow reaches the loop, coalesced.
	overflow, errsClosed := make(chan struct{}, 1), make(chan struct{})
	if !l.workers.GoOnce(runCtx, "library-watch-errors", func(context.Context) error {
		defer close(errsClosed)
		for err := range w.Errors {
			if errors.Is(err, fsnotify.ErrEventOverflow) {
				select {
				case overflow <- struct{}{}:
				default:
				}
				continue
			}
			l.log.Warn("filesystem watcher error; watching goes on", "err", err)
		}
		return nil
	}) {
		return nil
	}
	select {
	case <-l.watchReady:
		// The supervisor's restart after a failure: nothing was watched
		// in between, so every root this one takes up is owed a catch-up.
		arms.owes = true
	default:
	}
	recheck := time.NewTicker(cmp.Or(l.watchRecheck, watchRecheckDefault))
	defer recheck.Stop()
	sweep := time.NewTicker(watchSweepEvery)
	defer sweep.Stop()
	if err := l.armWatches(arms, false); err != nil {
		return err
	}
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-l.watchNudge:
			if err := l.armWatches(arms, false); err != nil {
				return err
			}
		case ev, ok := <-w.Events:
			if !ok {
				return errors.New("the filesystem event stream closed")
			}
			if ev.Op.Has(fsnotify.Rename) {
				l.lookHook("drop", ev.Name)
			}
			if created := takeWatchEvent(w, l.watchQueue, ev, arms.wasDir); created != "" {
				l.queueCreated(arms, created)
			}
		case <-errsClosed:
			return errors.New("the filesystem event stream closed")
		case <-overflow:
			// An overflow means events were missed - creates and renames
			// included, so both the catalog and the watch table are stale.
			// Queue a whole-root catch-up scan and walk every root again,
			// which is what picks up directories born inside the gap and
			// lets go of paths renamed in it.
			l.log.Warn("filesystem events dropped; scheduling a catch-up scan")
			now := time.Now()
			for _, root := range l.libraryRoots() {
				l.watchQueue.note(root.Path, now)
			}
			if err := l.armWatches(arms, true); err != nil {
				return err
			}
		case <-sweep.C:
			l.dispatchWatchScans()
		case <-recheck.C:
			if len(arms.absent) > 0 {
				l.log.Debug("looking again for missing library roots", "missing", len(arms.absent))
			}
			l.recheckRoots(arms)
		case look := <-arms.checks:
			if err := l.rechecked(arms, look); err != nil {
				return err
			}
		case look := <-arms.takes:
			// A pass's look that answered after the pass stopped waiting.
			if err := l.sayArmed(arms, l.tookUp(arms, look)); err != nil {
				return err
			}
		}
	}
}

// watchLookWait bounds how long a pass waits for its looks at the roots;
// a look that answers later is taken in then.
const watchLookWait = 5 * time.Second

// lookWait is watchLookWait, or a test's.
func (l *Library) lookWait() time.Duration {
	return cmp.Or(time.Duration(l.watchLookWait.Load()), watchLookWait)
}

// watchArms is the watcher's state across its passes, kept by its loop.
type watchArms struct {
	w   *fsnotify.Watcher
	ctx context.Context
	// checks carries the answers of the looks a recheck or a create sends
	// out, takes those of a pass's.
	checks, takes chan rootLook
	// owes is whether a root taken up owes a catch-up: false through the
	// process's first pass only.
	owes bool
	// looking are the roots with a look out.
	looking map[string]*lookOut
	// absent are the roots said to be missing, so an outage is said once;
	// taken those whose folder was there at their last look and is
	// watched.
	absent, taken map[string]bool
	// held are the roots whose own folder is watched under their path,
	// alias those whose folder the kernel watches under another path: the
	// same folder by a second path (a symlinked parent, a bind mount),
	// which is never a lost watch.
	held, alias map[string]bool
	// relost are the roots owed a walk and a catch-up because a directory
	// inside lost its watch with its folder staying, or the mounts under
	// them changed; remounted are the mount points that changed, whose
	// watches hold the folder that was there before.
	relost    map[string]bool
	remounted map[string][]string
	// created are the paths created under each root, in event order, that
	// its next look arms or notes; arming are those handed to a look out.
	created map[string][]string
	arming  map[string]bool
	// known is the watch table at the last recheck or pass, which tells
	// the directories that left it since.
	known map[string]bool
	// mounts are the mount points under each root at its last look, each
	// with what was mounted there; resolved the folder each root resolved
	// to (a root that is a symlink, or lies under one, names another).
	mounts   map[string]map[string]string
	resolved map[string]string
}

func newWatchArms(ctx context.Context, w *fsnotify.Watcher) *watchArms {
	return &watchArms{
		w: w, ctx: ctx, checks: make(chan rootLook), takes: make(chan rootLook),
		looking: map[string]*lookOut{}, absent: map[string]bool{}, taken: map[string]bool{},
		held: map[string]bool{}, alias: map[string]bool{},
		relost: map[string]bool{}, remounted: map[string][]string{},
		created: map[string][]string{}, arming: map[string]bool{},
		known: map[string]bool{}, mounts: map[string]map[string]string{}, resolved: map[string]string{},
	}
}

// lookOut is a look that is out: since when, and whether its stat of the
// root has answered.
type lookOut struct {
	since   time.Time
	statted atomic.Bool
	warned  bool
}

// lookKind is what a look at a root is for.
type lookKind int

const (
	// lookCheck is a recheck's: whether the root moved away from what is
	// watched.
	lookCheck lookKind = iota
	// lookPass is a pass's: a check, and a walk when walk asks.
	lookPass
	// lookArm only arms and notes what was created under the root.
	lookArm
)

// rootLook is a look at one root off the loop: what to look at, then
// what it found.
type rootLook struct {
	kind       lookKind
	root, name string
	out        *lookOut
	// created are the paths created under the root to arm or note first.
	created []string
	// walk asks a pass's look to walk the root when its folder is there,
	// owing a catch-up when owe asks. rewalk (after an overflow) lets go
	// first of the watches whose path no longer holds a directory, and of
	// those at remounted, which hold a covered folder.
	walk, owe, rewalk bool
	remounted         []string
	// lost are the directories under the root that left the watch table
	// since the last look.
	lost []string
	// present is whether the root's folder is there, resolved the folder
	// its path resolves to, stayed those of lost whose folder is there,
	// and mounts the mount points under the root, read before the walk
	// (nil where there is no mount table). armed are the directories its
	// creates armed.
	present  bool
	resolved string
	stayed   []string
	mounts   map[string]string
	armed    []string
	// walked is whether the walk ran, failed what it could not watch,
	// held and alias how the root's own folder is watched, and at when
	// the walk ended.
	walked      bool
	failed      int
	held, alias bool
	at          time.Time
}

// look sends a look at a root out on a worker, which answers the loop.
// Every look takes the root's queued creates with it.
func (l *Library) look(arms *watchArms, look rootLook) bool {
	answers := arms.checks
	if look.kind == lookPass {
		answers = arms.takes
	}
	look.out = &lookOut{since: time.Now()}
	look.created = arms.created[look.root]
	started := l.workers.GoOnce(arms.ctx, "library-watch-look", func(ctx context.Context) error {
		look := l.lookAtRoot(arms.w, look)
		select {
		case answers <- look:
		case <-ctx.Done():
		}
		return nil
	})
	if started {
		arms.looking[look.root] = look.out
		delete(arms.created, look.root)
		for _, p := range look.created {
			arms.arming[p] = true
		}
	}
	return started
}

// lookAtRoot is a look at a root, on its worker.
func (l *Library) lookAtRoot(w *fsnotify.Watcher, look rootLook) rootLook {
	answered := func() { look.out.statted.Store(true) }
	if look.kind != lookArm {
		l.lookHook("stat", look.root)
		st, err := os.Stat(look.root)
		look.present = err == nil && st.IsDir()
		answered()
		if look.present {
			look.resolved, _ = filepath.EvalSymlinks(look.root)
			look.mounts = l.mountsUnder(look.root, look.resolved)
		}
	}
	// An arm-only look has answered once its first create has.
	for _, path := range look.created {
		l.lookHook("arm", path)
		look.armed = append(look.armed, armCreated(w, l.watchQueue, path, answered)...)
	}
	if !look.present {
		return look
	}
	for _, dir := range look.lost {
		if st, err := os.Stat(dir); err == nil && st.IsDir() {
			look.stayed = append(look.stayed, dir)
		}
	}
	if !look.walk {
		return look
	}
	l.lookHook("walk", look.root)
	for _, mount := range look.remounted {
		dropWatches(w, mount, true)
	}
	if look.rewalk {
		for _, p := range w.WatchList() {
			if !underRoot(p, look.root) {
				continue
			}
			l.lookHook("prune", p)
			if st, err := os.Lstat(p); err != nil || !st.IsDir() {
				_ = w.Remove(p)
			}
		}
	}
	_, look.failed, look.held = watchRoot(w, look.root)
	look.walked, look.at = true, time.Now()
	if look.held && !slices.Contains(w.WatchList(), look.root) {
		// The kernel watched this folder already, under another path: it
		// is listed there, and events come by that path.
		look.held, look.alias = false, true
	}
	return look
}

// lookHook runs a test's hook at a stage of a look.
func (l *Library) lookHook(stage, path string) {
	if hook := l.watchLookHook.Load(); hook != nil {
		(*hook)(stage, path)
	}
}

// mountsUnder answers the mount points at or under the folder root
// resolves to, under root's own path, each with what is mounted there,
// from Linux's mount table. Other platforms have none to read and answer
// nil: a mount there that raises no event (a first mount on a directory,
// a remount) waits for the scheduled scan.
func (l *Library) mountsUnder(root, resolved string) map[string]string {
	folder := cmp.Or(resolved, root)
	read := readMountTable
	if hook := l.watchMountsHook.Load(); hook != nil {
		read = *hook
	}
	table, err := read()
	if err != nil {
		return nil
	}
	out := map[string]string{}
	for _, line := range strings.Split(table, "\n") {
		// mount ID, parent ID, major:minor, root, mount point, ...
		f := strings.Fields(line)
		if len(f) < 5 {
			continue
		}
		if point := unescapeMountPath(f[4]); underRoot(point, folder) {
			rel, _ := filepath.Rel(folder, point)
			out[filepath.Join(root, rel)] = f[0] + " " + f[2] + " " + f[3]
		}
	}
	return out
}

func readMountTable() (string, error) {
	b, err := os.ReadFile("/proc/self/mountinfo")
	return string(b), err
}

// unescapeMountPath undoes the mount table's octal escapes (\040 for a
// space, \011, \012, \134).
func unescapeMountPath(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			if n, err := strconv.ParseUint(s[i+1:i+4], 8, 8); err == nil {
				b.WriteByte(byte(n))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// moved takes a look in and answers what moved under its root since the
// last look: the root itself when it resolves to another folder (a
// retargeted symlink), and the mount points that appeared, went or
// changed. A walk that followed the look sets the marks without asking.
func (a *watchArms) moved(look rootLook) []string {
	var moved []string
	if look.resolved != "" {
		if was, seen := a.resolved[look.root]; seen && was != look.resolved && !look.walked {
			moved = append(moved, look.root)
		}
		a.resolved[look.root] = look.resolved
	}
	if look.walked {
		if look.mounts != nil {
			a.mounts[look.root] = look.mounts
		}
		return moved
	}
	return append(moved, a.mountsMoved(look.root, look.mounts)...)
}

// mountsMoved takes a look's mount table in and answers the mount points
// under the root that appeared, went or changed since the last look; the
// first look, and one with no mount table, answers none.
func (a *watchArms) mountsMoved(root string, now map[string]string) []string {
	if now == nil {
		return nil
	}
	was, seen := a.mounts[root]
	a.mounts[root] = now
	if !seen {
		return nil
	}
	var moved []string
	for point, what := range now {
		if was[point] != what {
			moved = append(moved, point)
		}
	}
	for point := range was {
		if _, ok := now[point]; !ok {
			moved = append(moved, point)
		}
	}
	return moved
}

// lost reports whether the watch on a root's own folder is gone: its
// folder removed or unmounted, which the kernel drops without a word. A
// folder watched under another path is never lost.
func (a *watchArms) lost(root string, live map[string]bool) bool {
	return a.held[root] && !live[root]
}

// live is the set of directories the kernel watcher holds.
func (a *watchArms) live() map[string]bool {
	list := a.w.WatchList()
	out := make(map[string]bool, len(list))
	for _, p := range list {
		out[p] = true
	}
	return out
}

// wasDir reports whether path was a watched directory at the last
// recheck or pass. A file's rename, the common case, costs no walk of
// the table.
func (a *watchArms) wasDir(path string) bool {
	return a.known[path]
}

// beingArmed reports whether a create at path is queued or out to be
// armed.
func (a *watchArms) beingArmed(root, path string) bool {
	return a.arming[path] || slices.Contains(a.created[root], path)
}

// queueCreated hands a path created under a root to the root's next
// look, sending one out when none is.
func (l *Library) queueCreated(arms *watchArms, path string) {
	root := rootHolding(path, l.libraryRoots())
	if root == "" {
		l.watchQueue.note(filepath.Dir(path), time.Now())
		return
	}
	arms.created[root] = append(arms.created[root], path)
	l.sendCreated(arms, root)
}

// sendCreated sends a root's queued creates out when no look is.
func (l *Library) sendCreated(arms *watchArms, root string) {
	if arms.looking[root] == nil && len(arms.created[root]) > 0 {
		l.look(arms, rootLook{kind: lookArm, root: root})
	}
}

// recheckRoots sends a look out at every root without one out: whether
// its folder is there, whether the directories that left the watch table
// since the last recheck are still there, which a deletion never leaves
// and an unmount does, and the mounts under it.
func (l *Library) recheckRoots(arms *watchArms) {
	roots := l.libraryRoots()
	live := arms.live()
	lost := map[string][]string{}
	for dir := range arms.known {
		if live[dir] {
			continue
		}
		root := rootHolding(dir, roots)
		switch {
		case root == "" || arms.beingArmed(root, dir):
		case arms.looking[root] != nil:
			// Asked about once its root's look is back.
			live[dir] = true
		default:
			lost[root] = append(lost[root], dir)
		}
	}
	arms.known = live
	for _, root := range roots {
		if arms.looking[root.Path] != nil {
			continue
		}
		look := rootLook{kind: lookCheck, root: root.Path, name: root.Name, lost: lost[root.Path]}
		if arms.lost(root.Path, live) && !slices.Contains(look.lost, root.Path) {
			look.lost = append(look.lost, root.Path)
		}
		l.look(arms, look)
	}
}

// rootHolding is the root dir lies in, the deepest if several hold it,
// or "" for none.
func rootHolding(dir string, roots []Root) string {
	held := ""
	for _, root := range roots {
		if underRoot(dir, root.Path) && len(root.Path) > len(held) {
			held = root.Path
		}
	}
	return held
}

// inTable reports whether root is in the root table.
func (l *Library) inTable(root string) bool {
	return slices.ContainsFunc(l.libraryRoots(), func(r Root) bool { return r.Path == root })
}

// answered takes in what every look's answer carries: the look is no
// longer out, and its creates are armed. A root that left the table
// meanwhile lets go of whatever its look added that no root still
// covers; it answers false for that.
func (l *Library) answered(arms *watchArms, look rootLook) bool {
	delete(arms.looking, look.root)
	for _, p := range look.created {
		delete(arms.arming, p)
	}
	// What a create armed is a directory the loop knows of, so a move out
	// of every root drops its subtree even when fsnotify let go of its own
	// watch first.
	for _, p := range look.armed {
		arms.known[p] = true
	}
	if l.inTable(look.root) {
		return true
	}
	keep := map[string]bool{}
	for _, root := range l.libraryRoots() {
		if !arms.absent[root.Path] {
			keep[root.Path] = true
		}
	}
	for _, p := range arms.w.WatchList() {
		if underRoot(p, look.root) && !underAnyRoot(p, keep) {
			_ = arms.w.Remove(p)
		}
	}
	return false
}

// rechecked takes a recheck's or a create's look in. A recheck's runs a
// pass when the root moved away from what is watched: its folder came or
// went, its watch or a directory's inside was lost with the folder
// staying and no arm on the way, or the mounts under it changed.
func (l *Library) rechecked(arms *watchArms, look rootLook) error {
	var err error
	if l.answered(arms, look) && look.kind == lookCheck {
		if moved := arms.moved(look); len(moved) > 0 {
			arms.relost[look.root] = true
			arms.remounted[look.root] = append(arms.remounted[look.root], moved...)
		}
		if l.stillLost(arms, look.root, look.stayed) {
			arms.relost[look.root] = true
		}
		if look.present != arms.taken[look.root] || (look.present && arms.relost[look.root]) {
			err = l.armWatches(arms, false)
		}
	}
	l.lookDone(arms, look.root)
	return err
}

// lookDone sends a root's queued creates out once its look is in.
func (l *Library) lookDone(arms *watchArms, root string) {
	l.sendCreated(arms, root)
	if hook := l.watchCheckHook.Load(); hook != nil {
		(*hook)(root)
	}
}

// stillLost reports whether one of the directories a look found there
// is still out of the watch table with no arm on the way: a lost watch,
// not a folder recreated whose create is being armed.
func (l *Library) stillLost(arms *watchArms, root string, stayed []string) bool {
	if len(stayed) == 0 {
		return false
	}
	live := arms.live()
	return slices.ContainsFunc(stayed, func(dir string) bool {
		return !live[dir] && !arms.beingArmed(root, dir)
	})
}

// armWatches is one pass over the root table: it takes up the roots it
// does not watch yet, those whose watch was lost, and those owed a walk
// for a directory inside, and lets go of the watches of roots gone. A
// root it keeps is not walked again unless rewalk asks (after an
// overflow). It waits for its looks a while; one that answers later is
// taken in then. It errs when nothing could be armed, for the supervisor
// to retry with backoff.
func (l *Library) armWatches(arms *watchArms, rewalk bool) error {
	if hook := l.watchArmHook.Load(); hook != nil {
		(*hook)(false)
	}
	roots := l.libraryRoots()
	inTable := map[string]bool{}
	for _, root := range roots {
		inTable[root.Path] = true
	}
	for _, m := range []map[string]bool{arms.absent, arms.taken, arms.held, arms.alias, arms.relost} {
		maps.DeleteFunc(m, func(root string, _ bool) bool { return !inTable[root] })
	}
	maps.DeleteFunc(arms.remounted, func(root string, _ []string) bool { return !inTable[root] })
	maps.DeleteFunc(arms.mounts, func(root string, _ map[string]string) bool { return !inTable[root] })
	maps.DeleteFunc(arms.resolved, func(root string, _ string) bool { return !inTable[root] })
	maps.DeleteFunc(arms.created, func(root string, _ []string) bool { return !inTable[root] })
	// Roots gone from the table or from disk let go of their watches; a
	// directory another root still covers keeps its own. A folder a root
	// watched for another one, by another path, may be among them.
	keep := map[string]bool{}
	for root := range inTable {
		if !arms.absent[root] {
			keep[root] = true
		}
	}
	dropped := false
	for _, p := range arms.w.WatchList() {
		if !underAnyRoot(p, keep) {
			_ = arms.w.Remove(p)
			delete(arms.known, p)
			dropped = true
		}
	}
	live := arms.live()
	wait := l.lookWait()
	waiting := map[string]bool{}
	for _, root := range roots {
		p := root.Path
		if out := arms.looking[p]; out != nil {
			// Its look answers when its folder does.
			l.warnUnanswered(out, root, wait)
			continue
		}
		lost := arms.lost(p, live)
		// A root taken up after the first pass - one added since, back
		// from an outage, its watch lost, a directory inside it lost or
		// mounted over, or taken up by a restarted watcher - may hold
		// files no scan saw and no event will announce: what landed
		// before its watch existed. Only a catalog scan started once it
		// is armed covers that, so a create's scan that ran first leaves
		// it owed. The first pass owes nothing.
		owed := !arms.taken[p] || lost || arms.relost[p] || (dropped && arms.alias[p])
		look := rootLook{kind: lookPass, root: p, name: root.Name, walk: owed || rewalk,
			owe: arms.owes && owed, rewalk: rewalk, remounted: arms.remounted[p]}
		if l.look(arms, look) {
			waiting[p] = true
		}
	}
	failed := 0
	timer := time.NewTimer(wait)
	defer timer.Stop()
	for len(waiting) > 0 {
		select {
		case look := <-arms.takes:
			delete(waiting, look.root)
			failed += l.tookUp(arms, look)
		case <-timer.C:
			for _, root := range roots {
				if out := arms.looking[root.Path]; waiting[root.Path] && out != nil {
					if !l.warnUnanswered(out, root, wait) {
						l.log.Debug("library root is still being walked; it is taken in when done", "path", root.Path)
					}
				}
			}
			clear(waiting)
		case <-arms.ctx.Done():
			return nil
		}
	}
	arms.owes = true
	// A directory that left the table before this pass stays known until
	// a recheck has looked at it.
	maps.Copy(arms.known, arms.live())
	if err := l.sayArmed(arms, failed); err != nil {
		return err
	}
	if hook := l.watchArmHook.Load(); hook != nil {
		(*hook)(true)
	}
	return nil
}

// warnUnanswered says once that a root has not answered its look, when
// its stat has been out the whole wait; a slow walk is no silence. It
// answers whether the root has not answered.
func (l *Library) warnUnanswered(out *lookOut, root Root, wait time.Duration) bool {
	if out.statted.Load() || time.Since(out.since) < wait {
		return false
	}
	if !out.warned {
		out.warned = true
		l.log.Warn("library root does not answer; it is watched once it does", "library", root.Name, "path", root.Path)
	}
	return true
}

// tookUp takes a pass's look in, answering how many directories its walk
// could not watch.
func (l *Library) tookUp(arms *watchArms, look rootLook) int {
	defer l.lookDone(arms, look.root)
	if !l.answered(arms, look) {
		return 0
	}
	if !look.present {
		if !arms.absent[look.root] {
			arms.absent[look.root] = true
			l.log.Warn("library root is not present; not watched", "library", look.name, "path", look.root)
		}
		delete(arms.taken, look.root)
		return 0
	}
	if arms.absent[look.root] {
		delete(arms.absent, look.root)
		l.log.Info("library root is present again; watching it", "library", look.name, "path", look.root)
	}
	arms.taken[look.root] = true
	// A kept root owes a walk for what moved under it since its last look;
	// a walk followed what its look read.
	if moved := arms.moved(look); len(moved) > 0 {
		arms.relost[look.root] = true
		arms.remounted[look.root] = append(arms.remounted[look.root], moved...)
	}
	if !look.walked {
		return look.failed
	}
	delete(arms.relost, look.root)
	delete(arms.remounted, look.root)
	if look.alias && !arms.alias[look.root] {
		l.log.Warn("library root is a folder another library holds by another path; it is watched once",
			"library", look.name, "path", look.root)
	}
	arms.held[look.root], arms.alias[look.root] = look.held, look.alias
	if (look.held || look.alias) && look.owe {
		l.watchQueue.owe(look.root, look.at.UnixNano(), look.at)
	}
	return look.failed
}

// sayArmed logs what is watched after a pass or a late look, and errs
// when nothing could be armed and no look is still out.
func (l *Library) sayArmed(arms *watchArms, failed int) error {
	total := len(arms.w.WatchList())
	switch {
	case total == 0 && failed == 0:
		// No root's folder is there: nothing to arm until one is.
	case total == 0 && len(arms.looking) == 0:
		// Nothing armable right now - a bind mount that is not up yet,
		// or an exhausted inotify budget. Both can heal, so hand the
		// supervisor an error and retry with its backoff rather than
		// degrading for good.
		l.log.Warn("no library directory could be watched; retrying, or use manual rescans or the scan schedule",
			"failed", failed, "hint", watchExhaustionHint)
		return errors.New("no library directory could be watched")
	case failed > 0:
		l.log.Warn("some library directories are not watched; the scan schedule covers what events miss",
			"watched", total, "unwatched", failed, "hint", watchExhaustionHint)
	default:
		l.log.Info("watching library roots for manual changes", "dirs", total)
	}
	if total > 0 {
		l.noteWatchArmed()
	}
	return nil
}

// underAnyRoot reports whether path is one of roots or lies under one.
func underAnyRoot(path string, roots map[string]bool) bool {
	for root := range roots {
		if underRoot(path, root) {
			return true
		}
	}
	return false
}

// underRoot reports whether path is root or lies under it.
func underRoot(path, root string) bool {
	return path == root || strings.HasPrefix(path, root+string(filepath.Separator))
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

// takeWatchEvent takes one event in on the loop, without touching the
// filesystem: it answers a created path for its root's look to arm (a
// directory, walked and scheduled itself, since files can land in it
// before its watch exists) or note (a file), and notes any other event's
// directory. A rename lets go first of the watches at the old path and
// under it, before the create that pairs with it is armed: fsnotify
// keeps a folder under the first path it was added by, so the new path
// would otherwise never be listed. wasDir, nil for none, tells a path
// that was a directory whose own watch fsnotify may have let go first,
// as it does for one moved out of every watched directory.
func takeWatchEvent(w *fsnotify.Watcher, pending *watchPending, ev fsnotify.Event, wasDir func(string) bool) string {
	if underWatchTrash(ev.Name) || strings.HasPrefix(filepath.Base(ev.Name), writeProbePrefix) {
		return ""
	}
	if ev.Op.Has(fsnotify.Rename) {
		dropWatches(w, ev.Name, wasDir != nil && wasDir(ev.Name))
	}
	if ev.Op.Has(fsnotify.Create) {
		return ev.Name
	}
	pending.note(filepath.Dir(ev.Name), time.Now())
	return ""
}

// armCreated arms and schedules a created directory, or notes a created
// file's directory, answering the directories it armed; on a look's
// worker. answered, when not nil, runs once the Lstat has answered.
func armCreated(w *fsnotify.Watcher, pending *watchPending, path string, answered func()) []string {
	info, err := os.Lstat(path)
	if answered != nil {
		answered()
	}
	if err != nil || !info.IsDir() {
		pending.note(filepath.Dir(path), time.Now())
		return nil
	}
	var armed []string
	walkWatch(w, path, func(dir string) { armed = append(armed, dir) })
	pending.note(path, time.Now())
	return armed
}

// dropWatches lets go of the watch at path and, when there was one or
// path was a directory, of every watch under it.
func dropWatches(w *fsnotify.Watcher, path string, wasDir bool) {
	if w.Remove(path) != nil && !wasDir {
		return
	}
	for _, p := range w.WatchList() {
		if underRoot(p, path) {
			_ = w.Remove(p)
		}
	}
}

// watchTree arms a watch on every directory under root. inotify is per
// directory, so a recursive watch is a walk; a directory that refuses
// (the kernel watch budget, permissions) or cannot be read at all is
// counted and skipped, and stays covered by scheduled scans only. The
// trash directory is left out on purpose.
func watchTree(w *fsnotify.Watcher, root string) (armed, failed int) {
	armed, failed, _ = walkWatch(w, root, nil)
	return armed, failed
}

// watchRoot is watchTree, also reporting whether root's own folder is
// watched.
func watchRoot(w *fsnotify.Watcher, root string) (armed, failed int, held bool) {
	return walkWatch(w, root, nil)
}

// walkWatch is the walk behind watchTree. It descends the folder root
// resolves to - a root that is a symlink, or lies under one, is walked
// all the same - and adds each directory under root's own path, so the
// table and the events keep that path. each, when not nil, is told every
// directory armed.
func walkWatch(w *fsnotify.Watcher, root string, each func(dir string)) (armed, failed int, held bool) {
	folder, err := filepath.EvalSymlinks(root)
	if err != nil {
		return 0, 1, false
	}
	filepath.WalkDir(folder, func(path string, d fs.DirEntry, err error) error {
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
		at := root
		if rel, err := filepath.Rel(folder, path); err == nil && rel != "." {
			at = filepath.Join(root, rel)
		}
		if err := w.Add(at); err != nil {
			failed++
			return nil
		}
		armed++
		held = held || at == root
		if each != nil {
			each(at)
		}
		return nil
	})
	return armed, failed, held
}

// noteWatchArmed closes the ready channel once, so a test can drop its
// file only after the watches exist.
func (l *Library) noteWatchArmed() {
	l.watchReadyOnce.Do(func() { close(l.watchReady) })
}
