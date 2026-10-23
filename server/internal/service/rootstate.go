package service

// What the console says of each root beyond the catalog's own policy:
// whether its folder was there at its last scan, and whether the server
// can write a managed one.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"slices"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/scan"
)

// reachSeedWindow is how many of the catalog's newest jobs a start reads
// for each library's last scan.
const reachSeedWindow = 64

// rootReach is whether each library's folder was missing at its last
// scan, by library pid, with that scan's end, so an older scan read late
// never lands over a newer one.
type rootReach struct {
	mu    sync.Mutex
	byLib map[model.PID]reachAt
}

type reachAt struct {
	unreachable bool
	atNS        int64
}

func (r *rootReach) unreachable(pid model.PID) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.byLib[pid].unreachable
}

// reachNews is what one scan changed: the runs whose library went
// unreachable, those whose library came back, those whose library it
// found reachable the first time this process saw one, and whether any
// library's flag moved.
type reachNews struct {
	gone, back, first []scan.Result
	moved             bool
}

// note takes one scan's runs.
func (r *rootReach) note(runs []scan.Result, atNS int64) reachNews {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.byLib == nil {
		r.byLib = map[model.PID]reachAt{}
	}
	var news reachNews
	for _, run := range runs {
		prev, seen := r.byLib[run.LibraryPID]
		if run.LibraryPID == "" || (seen && prev.atNS > atNS) {
			continue
		}
		r.byLib[run.LibraryPID] = reachAt{unreachable: run.RootUnreachable, atNS: atNS}
		switch {
		case !seen && !run.RootUnreachable:
			news.first = append(news.first, run)
		case prev.unreachable && !run.RootUnreachable:
			news.back = append(news.back, run)
		}
		if prev.unreachable != run.RootUnreachable {
			news.moved = true
			if run.RootUnreachable {
				news.gone = append(news.gone, run)
			}
		}
	}
	return news
}

// noteScanReach keeps what a finished scan job found of each library it
// walked.
func (l *Library) noteScanReach(ctx context.Context, j *model.Job) {
	if j.Kind != "scan" || j.State == model.JobRunning || j.Result == "" {
		return
	}
	var r struct{ Runs []scan.Result }
	if json.Unmarshal([]byte(j.Result), &r) != nil {
		return
	}
	l.noteReach(ctx, r.Runs, j.FinishedAt)
}

// noteReach keeps what a scan's runs, ended at atNS, found of each
// library's folder, logs a library whose folder they found gone once for
// the outage, offers the sidecar again a root whose folder is back, and
// tells every account when a library's flag moved.
func (l *Library) noteReach(ctx context.Context, runs []scan.Result, atNS int64) {
	news := l.rootReach.note(runs, atNS)
	rootOf := func(run scan.Result) (Root, bool) {
		for _, root := range l.libraryRoots() {
			if root.PID == string(run.LibraryPID) {
				return root, true
			}
		}
		return Root{}, false
	}
	for _, run := range news.gone {
		root, _ := rootOf(run)
		l.log.Warn("library root is not reachable; its items stay listed and play once it is back",
			"library", root.Name, "path", cmp.Or(root.Path, run.LibraryName))
	}
	for _, run := range news.back {
		if root, ok := rootOf(run); ok {
			l.offerFlowRootAgain(root.Name, root.Path)
		}
	}
	// First seen reachable, after a refusal no scan saw the reason for.
	for _, run := range news.first {
		if root, ok := rootOf(run); ok && l.flowRefusedAt(root.Name, root.Path) {
			l.offerFlowRootAgain(root.Name, root.Path)
		}
	}
	if news.moved {
		l.emitEveryoneEvent(ctx, eventLibraries)
	}
}

// flowRefusedAt reports whether the sidecar refused the root name at path.
func (l *Library) flowRefusedAt(name, path string) bool {
	l.flowSyncMu.Lock()
	defer l.flowSyncMu.Unlock()
	return l.flowRefused[name].path == path
}

// offerFlowRootAgain forgets the sidecar refusing a root whose folder is
// back, which it refused while the folder was missing, and offers it the
// root again, off the caller. An engine that is away is offered nothing,
// so no refusal is remembered or warned of: its return offers every root.
func (l *Library) offerFlowRootAgain(name, path string) {
	l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
		flow := l.flowRootSync()
		away := flowEngineAway(flow)
		l.flowSyncMu.Lock()
		if l.flowRefused[name].path == path {
			delete(l.flowRefused, name)
		}
		l.flowSyncMu.Unlock()
		if !away {
			l.syncFlowRoot(ctx, name, path)
		}
		return nil
	})
}

// flowEngineAway reports a bridge whose engine is not reachable now, as one
// that can tell says so.
func flowEngineAway(flow FlowRootSync) bool {
	engine, ok := flow.(interface{ Up() bool })
	return ok && !engine.Up()
}

// seedRootReach reads each library's last scan from the jobs the catalog
// kept, so a start knows a folder that was missing before it.
func (l *Library) seedRootReach(ctx context.Context) {
	jobs, err := l.lib.Jobs(ctx, reachSeedWindow)
	if err != nil {
		l.log.Warn("reading the last scans of the libraries", "err", err)
		return
	}
	for _, j := range jobs {
		l.noteScanReach(ctx, j)
	}
}

// rootProbeEvery is how often the managed roots are probed for writes
// again: what notices a folder whose ownership was changed by hand. The
// probe also runs at the start, after a write a folder refused, and for a
// root coming into the probed set (added elsewhere, a read-only flag or
// the server's lifted), and a console create probes its folder itself.
// Nothing else writes a probe, since each one can wake a sleeping disk
// and moves the folder's time.
const rootProbeEvery = 30 * time.Minute

// rootProbe tests the managed roots for writes, one pass at a time: what
// is asked for during a pass, every root (all) or the roots at some paths,
// the next pass probes. created are the folders a console create's own
// look probed, which the refresh that takes the new root in leaves alone.
// warned holds the roots warned of as unwritable, until one takes a write
// again.
type rootProbe struct {
	mu      sync.Mutex
	running bool
	all     bool
	some    map[string]bool
	created map[string]bool
	warned  map[string]bool
	// step runs as a pass's worker reaches each point of its life ("pass",
	// "let-go", "exit") in a test; nothing in the server sets it.
	step func(string)
}

// at is the worker reaching step.
func (p *rootProbe) at(step string) {
	p.mu.Lock()
	fn := p.step
	p.mu.Unlock()
	if fn != nil {
		fn(step)
	}
}

// begin asks for a pass over the roots at paths, every managed root when
// there are none, and claims it, or leaves it to the pass running.
func (p *rootProbe) begin(paths []string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(paths) == 0 {
		p.all = true
	}
	for _, path := range paths {
		if p.some == nil {
			p.some = map[string]bool{}
		}
		p.some[path] = true
	}
	if p.running {
		return false
	}
	p.running = true
	return true
}

// take hands a pass what was asked of it.
func (p *rootProbe) take() (all bool, some map[string]bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	all, some = p.all, p.some
	p.all, p.some = false, nil
	return all, some
}

// more reports whether another pass was asked for, and lets go when not.
func (p *rootProbe) more() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.all || len(p.some) > 0 {
		return true
	}
	p.running = false
	return false
}

func (p *rootProbe) stop() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.running, p.all, p.some = false, false, nil
}

// createdAt records whether a create's own look probed the folder at path.
func (p *rootProbe) createdAt(path string, probed bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !probed {
		delete(p.created, path)
		return
	}
	if p.created == nil {
		p.created = map[string]bool{}
	}
	p.created[path] = true
}

// unprobed is the roots at paths that need a probe of their own: all but
// those a create's look probed, whose record this uses up.
func (p *rootProbe) unprobed(paths []string) []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	var out []string
	for _, path := range paths {
		if p.created[path] {
			delete(p.created, path)
			continue
		}
		out = append(out, path)
	}
	return out
}

func (p *rootProbe) idle() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return !p.running
}

// warn reports whether an unwritable root is news, and forgets a root
// that takes writes again.
func (p *rootProbe) warn(key string, unwritable bool) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !unwritable {
		delete(p.warned, key)
		return false
	}
	if p.warned[key] {
		return false
	}
	if p.warned == nil {
		p.warned = map[string]bool{}
	}
	p.warned[key] = true
	return true
}

// probeRoots tests the managed roots at paths for writes, every one when
// there are none, off the caller, which can be the catalog feed: a hung
// mount never answers.
func (l *Library) probeRoots(paths ...string) {
	p := &l.rootProbe
	if !p.begin(paths) {
		return
	}
	started := l.workers.GoOnce(l.procCtx, "root-probe", func(ctx context.Context) error {
		// A pass that ends lets go in more(), and the next can start at
		// once: only one that panicked still holds the flags here.
		held := true
		defer func() {
			if held {
				p.stop()
			}
			p.at("exit")
		}()
		for {
			all, some := p.take()
			p.at("pass")
			l.probeRootsOnce(ctx, all, some)
			if !p.more() {
				held = false
				p.at("let-go")
				return nil
			}
		}
	})
	if !started {
		p.stop()
	}
}

// probeRootsEvery probes the managed roots again on the slow timer.
func (l *Library) probeRootsEvery(ctx context.Context) error {
	tick := time.NewTicker(cmp.Or(l.rootProbeEvery, rootProbeEvery))
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-tick.C:
			l.probeRoots()
		}
	}
}

// storageRefused is storageRefusal for a write the server just tried: a
// folder that refused it has the managed roots probed again, so the
// libraries say so without waiting for the timer.
func (l *Library) storageRefused(msg string) string {
	cause := storageRefusal(msg)
	if cause != "" {
		l.probeRoots()
	}
	return cause
}

// noteRefusedMoves is storageRefused for an organize run or undo that
// ended with moves a folder refused.
func (l *Library) noteRefusedMoves(j *model.Job) {
	if j.Kind != "organize" && j.Kind != "organize-undo" {
		return
	}
	res := organizeRunResult(j)
	if res == nil {
		return
	}
	for _, f := range res.Report.Failures {
		if l.storageRefused(f.Err) != "" {
			return
		}
	}
}

// probeRootsOnce is one pass over every managed root, or those at the
// paths in some: each one's flag set in the table, a root that stops
// taking writes warned of, and every account told when a flag moved. A
// folder that is not there is the scan's to report.
func (l *Library) probeRootsOnce(ctx context.Context, all bool, some map[string]bool) {
	refused := map[string]error{}
	for _, r := range l.libraryRoots() {
		if !l.probesRoot(r.Managed, r.ReadOnly) || !all && !some[r.Path] {
			continue
		}
		err := probeWritable(r.Path)
		if errors.Is(err, fs.ErrNotExist) {
			err = nil
		}
		refused[r.Path] = err
	}
	l.rootsMu.Lock()
	next := slices.Clone(l.roots)
	moved := false
	for i := range next {
		if err, probed := refused[next[i].Path]; probed && next[i].Unwritable != (err != nil) {
			next[i].Unwritable, moved = err != nil, true
		}
	}
	if moved {
		l.roots = next
	}
	l.rootsMu.Unlock()
	for _, r := range next {
		err, probed := refused[r.Path]
		if probed && l.rootProbe.warn(rootKey(r.Path), err != nil) {
			l.log.Warn("a managed library root is not writable by the server; uploads, organize moves and deletes into it will fail",
				"library", r.Name, "path", r.Path, "err", err)
		}
	}
	if moved {
		l.emitEveryoneEvent(ctx, eventLibraries)
	}
}

// configuredRoot reports whether the server's configuration names the
// root at path.
func (l *Library) configuredRoot(path string) bool {
	for _, r := range l.configRoots {
		if samePath(rootKey(r.Path), rootKey(path)) {
			return true
		}
	}
	return false
}

// probesRoot reports whether the probe writes into a root: a managed one
// the server does not treat as read-only, by its own flag or the whole
// server's. Nothing of WaxDeck's writes into the others.
func (l *Library) probesRoot(managed, readOnly bool) bool {
	return managed && !readOnly && !l.currentToggles().readOnly
}
