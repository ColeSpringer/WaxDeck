package service

import (
	"cmp"
	"context"
	"encoding/json"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// removalFacts is what a library removal's end needs that its job does
// not keep, recorded with its origin when it starts: the catalog drops the
// library's row, and a job that does not finish keeps no report.
type removalFacts struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

// flowUnmountKey prefixes, in settings, the root name of a removed library
// the streaming bridge has still to let go of; the value is its folder.
const flowUnmountKey = "flow-unmount:"

// rootRemovals holds, by library pid, the removals this process started:
// their facts, who asked, and whether their end is left to the starter's
// settle, which the follower then leaves alone. followed holds the removal
// jobs already followed up, with whether their library had gone, and
// follow keeps one follow-up at a time, so the follower and a settle do it
// once.
type rootRemovals struct {
	mu       sync.Mutex
	follow   sync.Mutex
	seq      uint64
	byLib    map[model.PID]removal
	followed map[model.PID]bool
}

type removal struct {
	name, path, userID string
	// starter is the removal's end being the starter's to settle.
	starter bool
	seq     uint64
}

// begin records a removal about to start, answering its number; one
// already under way keeps its record, and the answer is zero.
func (r *rootRemovals) begin(lib model.PID, rm removal) uint64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.byLib == nil {
		r.byLib = map[model.PID]removal{}
	}
	if cur, ok := r.byLib[lib]; ok && cur.starter {
		return 0
	}
	r.seq++
	rm.seq, rm.starter = r.seq, true
	r.byLib[lib] = rm
	return rm.seq
}

// abandon forgets a removal that did not start.
func (r *rootRemovals) abandon(lib model.PID, seq uint64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if seq != 0 && r.byLib[lib].seq == seq {
		delete(r.byLib, lib)
	}
}

// unrecord hands a removal whose origin was not recorded to the follower.
func (r *rootRemovals) unrecord(lib model.PID) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if rm, ok := r.byLib[lib]; ok {
		rm.starter = false
		r.byLib[lib] = rm
	}
}

// leftToStarter reports whether a removal's end is its starter's to settle.
func (r *rootRemovals) leftToStarter(lib model.PID) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.byLib[lib].starter
}

func (r *rootRemovals) facts(lib model.PID) removal {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.byLib[lib]
}

// forget drops a removal whose library stayed, so another can begin.
func (r *rootRemovals) forget(lib model.PID) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.byLib, lib)
}

// named keeps the name a removed library went by, for its job's target.
func (r *rootRemovals) named(lib model.PID, name, path string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.byLib == nil {
		r.byLib = map[model.PID]removal{}
	}
	rm := r.byLib[lib]
	rm.name, rm.path, rm.starter = name, path, false
	r.byLib[lib] = rm
}

// name is the name a library removed by this process went by.
func (r *rootRemovals) name(lib model.PID) string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.byLib[lib].name
}

// outcome answers a job already followed up, with whether its library had
// gone. The caller holds follow.
func (r *rootRemovals) outcome(job model.PID) (removed, ok bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	removed, ok = r.followed[job]
	return removed, ok
}

func (r *rootRemovals) settle(job model.PID, removed bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.followed == nil {
		r.followed = map[model.PID]bool{}
	}
	r.followed[job] = removed
}

// followRootRemoval drops what WaxDeck keeps of a library its removal took
// out of the catalog, answering whether the library went. The job's state
// does not say: the catalog lets the library go before the job ends, and
// the job can still end crashed, canceled or failed after that. A library
// the catalog still holds keeps all of it. o is the job's origin, with
// what the console recorded at the start. An error leaves the rest for a
// repeat, which every step allows: the audit is written once per library.
func (l *Library) followRootRemoval(ctx context.Context, j *model.Job, o wdb.JobOrigin) (bool, error) {
	if j.Kind != "remove-root" || j.State == model.JobRunning || j.TargetPID == "" {
		return false, nil
	}
	l.removals.follow.Lock()
	defer l.removals.follow.Unlock()
	if removed, ok := l.removals.outcome(j.PID); ok {
		return removed, nil
	}
	ctx = context.WithoutCancel(ctx)
	switch _, err := l.libraryByPID(ctx, j.TargetPID); {
	case err == nil:
		l.removals.settle(j.PID, false)
		l.removals.forget(j.TargetPID)
		if l.keptLibraryWantsScan(j) {
			l.rescanKeptLibrary(j.TargetPID)
		}
		return false, nil
	case KindOf(err) != KindNotFound:
		return false, err
	}
	facts := l.removalFactsOf(ctx, j, o)
	if err := l.dropLibrarySettings(ctx, j.TargetPID); err != nil {
		return false, err
	}
	l.refreshLibraryState(ctx)
	kept, err := l.dropRemovedName(ctx, j.TargetPID, facts)
	if err != nil {
		return false, err
	}
	detail := map[string]any{"name": facts.Name, "path": facts.Path}
	var rep model.RemoveRootReport
	if j.Result != "" && json.Unmarshal([]byte(j.Result), &rep) == nil {
		detail["filesDetached"], detail["itemsArchived"], detail["trashRowsDropped"] =
			rep.FilesDetached, rep.ItemsArchived, rep.TrashRowsDropped
	}
	if facts.Name != "" && !kept {
		if warning := l.unmountFlowRoot(ctx, facts.Name, facts.Path); warning != "" {
			detail["streamingWarning"] = warning
		}
		// A library in another folder going by the name is taught again,
		// under its own folder.
		if slices.ContainsFunc(l.libraryRoots(), func(r Root) bool { return r.Name == facts.Name }) {
			l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
				l.syncFlowRoots(ctx)
				return nil
			})
		}
	}
	apiLib := apiPID(PrefixLibrary, j.TargetPID)
	prior, err := l.db.ListAudit(ctx, wdb.AuditFilter{Action: "library.remove", TargetPID: apiLib}, 0, 1)
	if err != nil {
		return false, err
	}
	if len(prior) == 0 {
		var actor *UserCtx
		if id := cmp.Or(o.UserID, l.removals.facts(j.TargetPID).userID); id != "" {
			actor = &UserCtx{ID: id}
		}
		l.Audit(ctx, actor, "library.remove", AuditTarget{Kind: "library", PID: apiLib, Name: facts.Name}, detail)
	}
	l.removals.named(j.TargetPID, facts.Name, facts.Path)
	l.removals.settle(j.PID, true)
	return true, nil
}

// keptLibraryWantsScan reports whether a library its removal left wants
// a scan: when the job let go of files, or left no report to say it did
// not. One the last stop cut short is left to this start's scan of every
// library, when it runs one: a scan of the library alone would race it
// for the catalog, and fail it by winning.
func (l *Library) keptLibraryWantsScan(j *model.Job) bool {
	if l.startupScan && j.FinishedAt < l.openedAtNS {
		return false
	}
	var rep model.RemoveRootReport
	if j.Result == "" || json.Unmarshal([]byte(j.Result), &rep) != nil {
		return true
	}
	return rep.FilesDetached > 0
}

// removedLibraryName is the name a removal's audit row gives a library
// it took out, which outlasts the process that ran it; "" when none does.
func (l *Library) removedLibraryName(ctx context.Context, apiLib string) string {
	rows, err := l.db.ListAudit(ctx, wdb.AuditFilter{Action: "library.remove", TargetPID: apiLib}, 0, 1)
	if err != nil {
		l.log.Warn("reading a removed library's name", "library", apiLib, "err", err)
		return ""
	}
	if len(rows) == 0 {
		return ""
	}
	return rows[0].TargetName
}

// rescanKeptLibrary scans a library a removal left in the catalog: the
// batches the job ran before it stopped let go of their files, which a
// scan takes back. A catalog busy with another job leaves them to the
// library's next scan.
func (l *Library) rescanKeptLibrary(lib model.PID) {
	pid, err := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{LibraryPID: lib})
	if err != nil {
		l.log.Warn("scanning a library a removal left; its next scan takes back what the removal let go of",
			"library", apiPID(PrefixLibrary, lib), "err", err)
		return
	}
	l.followJob(pid)
}

// settleUnrecordedRemoval follows up a removal no origin records: the
// CLI's, or one whose record failed. One the console started is left to
// its starter's settle. It first records an origin of no one's with what
// is known of the library, read while its stored name still stands, and
// settles that as the console's are settled: a stop or a failure anywhere
// in the follow-up leaves the next start the row, and the facts, to
// repeat it from.
func (l *Library) settleUnrecordedRemoval(ctx context.Context, j *model.Job) {
	if l.removals.leftToStarter(j.TargetPID) {
		return
	}
	ctx = context.WithoutCancel(ctx)
	o := wdb.JobOrigin{PID: string(j.PID), CreatedAtNS: time.Now().UnixNano()}
	if raw, err := json.Marshal(l.removalFactsOf(ctx, j, o)); err == nil {
		o.Detail = string(raw)
	}
	if err := l.db.InsertJobOrigin(ctx, o); err != nil {
		l.log.Warn("keeping a library removal's follow-up for a repeat", "job", string(j.PID), "err", err)
		if _, err := l.followRootRemoval(ctx, j, o); err != nil {
			l.log.Warn("following up a library's removal", "job", string(j.PID), "err", err)
		}
		return
	}
	l.settleJobOrigin(ctx, j)
}

// removalFactsOf is what is known of a removed library: what its origin
// recorded, else what this process kept at the start, else its report's
// root and the name that root went by.
func (l *Library) removalFactsOf(ctx context.Context, j *model.Job, o wdb.JobOrigin) removalFacts {
	var f removalFacts
	if o.Detail != "" && json.Unmarshal([]byte(o.Detail), &f) != nil {
		l.log.Warn("reading a library removal's record", "job", string(j.PID))
	}
	rm := l.removals.facts(j.TargetPID)
	f.Name, f.Path = cmp.Or(f.Name, rm.name), cmp.Or(f.Path, rm.path)
	if f.Path == "" && j.Result != "" {
		var rep model.RemoveRootReport
		if json.Unmarshal([]byte(j.Result), &rep) == nil {
			f.Path = rep.Root
		}
	}
	if f.Name == "" && f.Path != "" {
		f.Name = l.rootNameAt(ctx, f.Path)
	}
	return f
}

// dropRemovedName drops a removed library's stored name, unless another
// library holds its folder again by now, whose name the row is; and
// answers whether the mount under the removed one's name is another
// root's now (mountKept), and so stays. It holds the table's lock, as a
// create storing a name does, so neither lands between the other's read
// and write.
func (l *Library) dropRemovedName(ctx context.Context, removed model.PID, f removalFacts) (bool, error) {
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	others := slices.DeleteFunc(slices.Clone(l.roots), func(r Root) bool { return r.PID == string(removed) })
	kept := l.mountKept(others, f.Name, f.Path)
	if f.Path == "" {
		return kept, nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return kept, classify(err)
	}
	if slices.ContainsFunc(libs, func(lib *model.Library) bool { return samePath(rootKey(lib.DisplayRoot), rootKey(f.Path)) }) {
		return kept, nil
	}
	rows, err := l.db.LibraryRootsList(ctx)
	if err != nil {
		return kept, err
	}
	for _, r := range rows {
		if samePath(rootKey(r.Path), rootKey(f.Path)) && (f.Name == "" || r.Name == f.Name) {
			if err := l.db.LibraryRootsDelete(ctx, r.Path); err != nil {
				return kept, err
			}
		}
	}
	return kept, nil
}

// rootNameAt is the name the root at path went by: the configuration's,
// else the stored one, else its directory's.
func (l *Library) rootNameAt(ctx context.Context, path string) string {
	for _, r := range l.configRoots {
		if samePath(rootKey(r.Path), rootKey(path)) {
			return r.Name
		}
	}
	if rows, err := l.db.LibraryRootsList(ctx); err == nil {
		for _, r := range rows {
			if samePath(rootKey(r.Path), rootKey(path)) {
				return r.Name
			}
		}
	}
	return filepath.Base(path)
}

// unmountFlowRoot takes a removed library's root off the bridge and the
// sidecar, and forgets the bridge refusing it. A bridge not wired yet, or
// whose sidecar does not let go, owes it to its next sync; a server with
// no streaming engine has nothing to take off. The returned string is
// empty unless the sidecar kept the root, and then says so.
func (l *Library) unmountFlowRoot(ctx context.Context, name, path string) string {
	l.flowSyncMu.Lock()
	defer l.flowSyncMu.Unlock()
	delete(l.flowRefused, name)
	p := l.flowRoots.Load()
	if p != nil && *p == nil {
		return ""
	}
	var warning string
	if p != nil {
		err := (*p).RemoveRoot(ctx, name)
		if err == nil {
			return ""
		}
		l.log.Warn("the streaming sidecar did not let go of a removed library's root", "library", name, "err", err)
		warning = "the streaming sidecar still serves this library's folder: " + err.Error()
	}
	if err := l.oweUnmount(ctx, name, path); err != nil {
		l.log.Warn("keeping a removed library's root for the streaming bridge to let go of", "library", name, "err", err)
	}
	return warning
}

// oweUnmount keeps a removed library's root for the bridge's next sync to
// take off.
func (l *Library) oweUnmount(ctx context.Context, name, path string) error {
	return l.db.SettingSet(context.WithoutCancel(ctx), flowUnmountKey+name, path, time.Now().UnixNano())
}

// unmountOwed takes off the bridge the roots of libraries removed while it
// could not be told: before it was wired, or while its sidecar would not
// let go. A mount another root holds now (mountKept) stays; a library
// going by the name from another folder is taught again by the sync that
// runs this. With no streaming engine there is nothing to take off. The
// caller holds flowSyncMu.
func (l *Library) unmountOwed(ctx context.Context, flow FlowRootSync) {
	owed, err := l.db.SettingsWithPrefix(ctx, flowUnmountKey)
	if err != nil {
		l.log.Warn("reading the removed libraries' roots the streaming bridge has still to let go of", "err", err)
		return
	}
	for key, path := range owed {
		name := strings.TrimPrefix(key, flowUnmountKey)
		if flow != nil && !l.mountKept(l.libraryRoots(), name, path) {
			delete(l.flowRefused, name)
			if err := flow.RemoveRoot(ctx, name); err != nil {
				l.log.Warn("the streaming sidecar did not let go of a removed library's root", "library", name, "path", path, "err", err)
				continue
			}
		}
		if err := l.db.SettingDeleteIf(ctx, key, path); err != nil {
			l.log.Warn("dropping a removed library's root the streaming bridge let go of", "library", name, "err", err)
		}
	}
}

// mountKept reports whether the sidecar's entry under a removed library's
// name is another root's now: a library of the table or a configured root
// going by the name from the removed library's own folder, or the podcast
// download dir, which only a restart mounts again. A library going by the
// name from another folder does not keep it: the entry still names the
// removed folder, so it comes off and that library is taught anew.
func (l *Library) mountKept(roots []Root, name, folder string) bool {
	if name == l.podcastRootName {
		return true
	}
	at := func(r Root) bool { return r.Name == name && samePath(rootKey(r.Path), rootKey(folder)) }
	return slices.ContainsFunc(roots, at) || slices.ContainsFunc(l.configRoots, at)
}

// libraryMatchingKeys prefix a library's matching settings, by bare pid
// (LibraryMatchingMode, LibrarySinglesAutoApply).
var libraryMatchingKeys = []string{"matching:", "matching-singles:"}

// dropLibrarySettings drops what WaxDeck keeps under a removed library's
// pid: the grants naming it, on accounts and invites, and its matching
// settings.
func (l *Library) dropLibrarySettings(ctx context.Context, pid model.PID) error {
	if err := l.db.PruneLibraryGrants(ctx, string(pid)); err != nil {
		return err
	}
	for _, prefix := range libraryMatchingKeys {
		if err := l.db.SettingDelete(ctx, prefix+string(pid)); err != nil {
			return err
		}
	}
	return nil
}

// leftover is what WaxDeck keeps of a library the catalog no longer holds:
// what it keeps under its pids (dropLibrarySettings), and the name stored
// for its folder.
type leftover struct {
	pids       []model.PID
	name, path string
	stored     bool
}

// reconcileRemovedLibraries drops at startup what WaxDeck keeps of each
// library the catalog no longer holds, whatever removed it (the CLI while
// the server was down, a crash before the removal's origin was recorded):
// its stored name, the grants naming it, its matching settings, and its
// streaming mount, owed to the bridge until it is wired. A library the
// catalog holds, a newer one at the same folder included, keeps all of it,
// as does a configured root. Only a removal this server started is
// audited, when its origin settles.
func (l *Library) reconcileRemovedLibraries(ctx context.Context) {
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		l.log.Warn("looking for what removed libraries left behind", "err", err)
		return
	}
	rows, err := l.db.LibraryRootsList(ctx)
	if err != nil {
		l.log.Warn("looking for what removed libraries left behind", "err", err)
		return
	}
	pids, err := l.pidsKeptUnder(ctx)
	if err != nil {
		l.log.Warn("looking for what removed libraries left behind", "err", err)
		return
	}
	held := map[model.PID]bool{}
	var heldPaths []string
	for _, lib := range libs {
		held[lib.PID] = true
		heldPaths = append(heldPaths, rootKey(lib.DisplayRoot))
	}
	for _, r := range l.configRoots {
		heldPaths = append(heldPaths, rootKey(r.Path))
	}
	var gone []*leftover
	for _, r := range rows {
		if !slices.ContainsFunc(heldPaths, func(p string) bool { return samePath(p, rootKey(r.Path)) }) {
			gone = append(gone, &leftover{name: r.Name, path: r.Path, stored: true})
		}
	}
	folders := l.removedFolders(ctx, held)
	for _, pid := range pids {
		if held[pid] {
			continue
		}
		folder := folders[pid]
		i := slices.IndexFunc(gone, func(g *leftover) bool { return folder != "" && samePath(rootKey(g.path), rootKey(folder)) })
		if i < 0 {
			gone = append(gone, &leftover{pids: []model.PID{pid}, path: folder})
			continue
		}
		gone[i].pids = append(gone[i].pids, pid)
	}
	for _, g := range gone {
		if err := l.dropLeftover(ctx, g); err != nil {
			l.log.Warn("cleaning up after a library the catalog no longer holds; the next start repeats it", "library", g.name, "path", g.path, "err", err)
			continue
		}
		name := g.name
		if name == "" && len(g.pids) > 0 {
			name = apiPID(PrefixLibrary, g.pids[0])
		}
		attrs := []any{"library", name}
		if g.path != "" {
			attrs = append(attrs, "path", g.path)
		}
		l.log.Info("cleaned up after a library the catalog no longer holds", attrs...)
	}
}

// removedFolders maps each library the catalog's recent removal jobs took
// out to the folder it held, from the job's report.
func (l *Library) removedFolders(ctx context.Context, held map[model.PID]bool) map[model.PID]string {
	out := map[model.PID]string{}
	jobs, err := l.lib.Jobs(ctx, 256)
	if err != nil {
		return out
	}
	for _, j := range jobs {
		if j.Kind != "remove-root" || held[j.TargetPID] || j.Result == "" {
			continue
		}
		var rep model.RemoveRootReport
		if json.Unmarshal([]byte(j.Result), &rep) == nil && rep.Root != "" {
			out[j.TargetPID] = rep.Root
		}
	}
	return out
}

// pidsKeptUnder lists every library pid WaxDeck keeps something under: a
// grant, on an account or an invite, or a matching setting.
func (l *Library) pidsKeptUnder(ctx context.Context) ([]model.PID, error) {
	granted, err := l.db.GrantedLibraryPIDs(ctx)
	if err != nil {
		return nil, err
	}
	var pids []model.PID
	for _, pid := range granted {
		pids = append(pids, model.PID(pid))
	}
	for _, prefix := range libraryMatchingKeys {
		set, err := l.db.SettingsWithPrefix(ctx, prefix)
		if err != nil {
			return nil, err
		}
		for key := range set {
			pids = append(pids, model.PID(strings.TrimPrefix(key, prefix)))
		}
	}
	slices.Sort(pids)
	return slices.Compact(pids), nil
}

// dropLeftover drops what WaxDeck keeps of one removed library, owing the
// bridge its mount unless another root holds it now (mountKept). The
// caller holds rootsMu.
func (l *Library) dropLeftover(ctx context.Context, g *leftover) error {
	for _, pid := range g.pids {
		if err := l.dropLibrarySettings(ctx, pid); err != nil {
			return err
		}
	}
	if !g.stored {
		return nil
	}
	if g.name != "" && !l.mountKept(l.roots, g.name, g.path) {
		if err := l.oweUnmount(ctx, g.name, g.path); err != nil {
			return err
		}
	}
	return l.db.LibraryRootsDelete(ctx, g.path)
}
