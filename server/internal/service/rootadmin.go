package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// libraryRoots returns a snapshot of the service's root table. Callers
// range over it without retaining; the table is replaced whole under
// rootsMu, so a snapshot taken here stays consistent.
func (l *Library) libraryRoots() []Root {
	l.rootsMu.RLock()
	defer l.rootsMu.RUnlock()
	return l.roots
}

// rootKey is a root path as the catalog stores it, absolute and clean.
func rootKey(path string) string {
	if abs, err := filepath.Abs(path); err == nil {
		return abs
	}
	return filepath.Clean(path)
}

// samePath reports whether two cleaned absolute paths name one location by
// the rule the catalog matches roots with: filepath.Rel's, which folds case
// on Windows only.
func samePath(a, b string) bool {
	rel, err := filepath.Rel(a, b)
	return err == nil && rel == "."
}

// refreshLibraryState rebuilds the root table from the catalog's libraries,
// naming each root uniquely and keeping the name: it is the streaming
// engine's address for the root.
func (l *Library) refreshLibraryState(ctx context.Context) {
	l.refreshMu.Lock()
	defer l.refreshMu.Unlock()
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		l.log.Warn("reading the catalog's libraries", "err", err)
		return
	}
	libs = slices.DeleteFunc(libs, func(lib *model.Library) bool {
		return lib.Mode == model.ModePodcast || lib.DisplayRoot == ""
	})
	names := l.rootNames(ctx, libs)
	roots := make([]Root, 0, len(libs))
	for _, lib := range libs {
		roots = append(roots, Root{
			Name: names[lib.PID], Path: lib.DisplayRoot, Managed: lib.Mode == model.ModeManaged,
			Media: string(lib.MediaType()), PID: string(lib.PID), Profile: lib.Profile, ReadOnly: lib.ReadOnly,
			FolderFallback: lib.FolderFallback,
		})
	}
	if l.refreshHook != nil {
		l.refreshHook()
	}
	l.rootsMu.Lock()
	// A root keeps its last probe, read under the lock a probe pass stores
	// its answer under: a refresh writes nothing into a folder, and never
	// puts back an answer a pass changed while it read the catalog.
	unwritable := map[string]bool{}
	for _, r := range l.roots {
		unwritable[r.Path] = r.Unwritable
	}
	for i := range roots {
		roots[i].Unwritable = roots[i].Managed && unwritable[roots[i].Path]
	}
	// The first build arms the watcher itself; a re-arm drops events.
	first := !l.rootsBuilt
	moved := !first && !slices.EqualFunc(l.roots, roots, func(a, b Root) bool { return a.Path == b.Path })
	changed := !first && !slices.Equal(l.roots, roots)
	// A managed root coming into the probed set (added elsewhere, its
	// read-only flag lifted) has no answer of its own yet; the start's
	// probe answers the first build.
	var entering []string
	if changed {
		probed := map[string]bool{}
		for _, r := range l.roots {
			probed[r.Path] = l.probesRoot(r.Managed, r.ReadOnly)
		}
		for _, r := range roots {
			if l.probesRoot(r.Managed, r.ReadOnly) && !probed[r.Path] {
				entering = append(entering, r.Path)
			}
		}
	}
	l.roots, l.rootsBuilt = roots, true
	l.rootsMu.Unlock()
	if paths := l.rootProbe.unprobed(entering); len(paths) > 0 {
		l.probeRoots(paths...)
	}
	if first || changed {
		l.invalidateAttribution()
	}
	if moved {
		l.nudgeWatcher()
		// A root added elsewhere (the CLI, a restore) streams once taught.
		l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
			l.syncFlowRoots(ctx)
			return nil
		})
	}
	if changed {
		l.emitEveryoneEvent(ctx, eventLibraries)
	}
}

// rootNames names each library: configured names first, then stored ones,
// then the directory's, numbered past any name taken and stored.
func (l *Library) rootNames(ctx context.Context, libs []*model.Library) map[model.PID]string {
	stored := map[string]string{}
	if rows, err := l.db.LibraryRootsList(ctx); err != nil {
		l.log.Warn("reading library root names", "err", err)
	} else {
		for _, r := range rows {
			stored[rootKey(r.Path)] = r.Name
		}
	}
	configured := map[string]string{}
	for _, r := range l.configRoots {
		configured[rootKey(r.Path)] = r.Name
	}
	taken := map[string]bool{}
	if l.podcastRootName != "" {
		taken[l.podcastRootName] = true
	}
	out := make(map[model.PID]string, len(libs))
	for _, source := range []map[string]string{configured, stored} {
		for _, lib := range libs {
			if name := source[rootKey(lib.DisplayRoot)]; out[lib.PID] == "" && name != "" && !taken[name] {
				out[lib.PID], taken[name] = name, true
			}
		}
	}
	// A configured name is stored too: a root taken out of the
	// configuration keeps the name the streaming sidecar mounts it under.
	for _, lib := range libs {
		key := rootKey(lib.DisplayRoot)
		if name := configured[key]; name != "" && out[lib.PID] == name && stored[key] != name {
			if err := l.db.LibraryRootsUpsert(ctx, wdb.LibraryRoot{
				Path: lib.DisplayRoot, Name: name, CreatedAtNS: time.Now().UnixNano(),
			}); err != nil {
				l.log.Warn("storing a configured library's name", "library", name, "err", err)
			}
		}
	}
	for _, lib := range libs {
		if out[lib.PID] != "" {
			continue
		}
		base := filepath.Base(lib.DisplayRoot)
		name := base
		for n := 2; taken[name]; n++ {
			name = fmt.Sprintf("%s-%d", base, n)
		}
		out[lib.PID], taken[name] = name, true
		if err := l.db.LibraryRootsUpsert(ctx, wdb.LibraryRoot{
			Path: lib.DisplayRoot, Name: name, CreatedAtNS: time.Now().UnixNano(),
		}); err != nil {
			l.log.Warn("storing a library's name", "library", name, "err", err)
		}
	}
	return out
}

// libraryReadOnly reports whether the catalog flags a library read-only.
func (l *Library) libraryReadOnly(bareLibraryPID string) bool {
	for _, r := range l.libraryRoots() {
		if r.PID == bareLibraryPID {
			return r.ReadOnly
		}
	}
	return false
}

// nudgeWatcher re-arms the library watcher over the current root table;
// a no-op when the watcher is off.
func (l *Library) nudgeWatcher() {
	select {
	case l.watchNudge <- struct{}{}:
	default:
	}
}

// RootTable is the service's root table: every library root the catalog
// holds, named.
func (l *Library) RootTable() []Root { return slices.Clone(l.libraryRoots()) }

// flowRootSync is the wired bridge, nil before SetFlowRoots and on a
// server with no streaming engine.
func (l *Library) flowRootSync() FlowRootSync {
	if p := l.flowRoots.Load(); p != nil {
		return *p
	}
	return nil
}

// syncFlowRoots brings the streaming bridge to the root table once it is
// wired: the mounts of libraries removed while it could not be told are
// taken off, and the roots it does not map, as a restore or the CLI
// brings, are taught, passing over one it refused at the same path.
func (l *Library) syncFlowRoots(ctx context.Context) {
	p := l.flowRoots.Load()
	if p == nil {
		return
	}
	flow := *p
	l.flowSyncMu.Lock()
	defer l.flowSyncMu.Unlock()
	l.unmountOwed(ctx, flow)
	if flow == nil {
		return
	}
	known := flow.RootNames()
	for _, r := range l.libraryRoots() {
		if !slices.Contains(known, r.Name) && l.flowRefused[r.Name].path != r.Path {
			l.teachFlowRoot(ctx, flow, r.Name, r.Path)
		}
	}
}

// settleRoots brings the catalog's roots to what the server runs with:
// defined profiles, the configured roots, the table rebuilt, and what the
// last scans found of their folders.
func (l *Library) settleRoots(ctx context.Context) error {
	l.defaultUndefinedProfiles(ctx)
	if err := l.registerConfiguredRoots(ctx); err != nil {
		return err
	}
	l.refreshLibraryState(ctx)
	l.seedRootReach(ctx)
	return nil
}

// registerConfiguredRoots registers a configured root the catalog lacks or
// holds in another mode, or holding other media than the configuration
// declares, leaving the rest alone so no settle races an edit.
// One the catalog refuses (an overlap) is left out: the app removes nothing.
func (l *Library) registerConfiguredRoots(ctx context.Context) error {
	if len(l.configRoots) == 0 {
		return nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return classify(err)
	}
	rows := make(map[string]*model.Library, len(libs))
	for _, lib := range libs {
		rows[rootKey(lib.DisplayRoot)] = lib
	}
	for _, r := range l.configRoots {
		spec := config.Root{Path: r.Path, Mode: model.ModeInPlace}
		if r.Managed {
			spec.Mode = model.ModeManaged
		}
		// A declared media is the configuration's to keep; an undeclared
		// one is whatever the root holds now.
		declared := model.MediaType(r.Media)
		row := rows[rootKey(r.Path)]
		if row != nil && row.Mode == spec.Mode && (declared == "" || row.MediaType() == declared) {
			continue
		}
		if row != nil {
			spec.Media, spec.Profile = row.Media, row.Profile
		}
		if declared != "" {
			spec.Media = declared
		}
		// A folder not there yet (a drive mounted later, or the first boot
		// of a catalog a reset just recreated) registers and scans as
		// unreachable rather than staying out until a restart. Logged first,
		// since the catalog stats the folder and a hung mount never answers.
		l.log.Info("registering a configured library root", "root", r.Path)
		_, err := l.lib.AddRoot(ctx, spec, waxbin.AllowAbsent())
		if waxerr.Is(err, waxerr.CodeInvalid) {
			if _, warned := l.rootsLeftOut.LoadOrStore(rootKey(r.Path), true); !warned {
				l.log.Warn("a configured library root is left out; change the configuration to resolve it",
					"root", r.Path, "err", err)
			}
			continue
		}
		if err != nil {
			return fmt.Errorf("registering %s: %w", r.Path, err)
		}
	}
	return nil
}

// overlappingRoots names two configured roots one of which holds the other.
func overlappingRoots(roots []Root) (string, string, bool) {
	for i := range roots {
		for j := i + 1; j < len(roots); j++ {
			a, b := rootKey(roots[i].Path), rootKey(roots[j].Path)
			if a == b || strings.HasPrefix(a, b+string(filepath.Separator)) || strings.HasPrefix(b, a+string(filepath.Separator)) {
				return roots[i].Path, roots[j].Path, true
			}
		}
	}
	return "", "", false
}

// defaultUndefinedProfiles moves a library naming a profile the catalog
// does not define (a restored or runtime one) to the default, which
// organizing and imports would otherwise refuse.
func (l *Library) defaultUndefinedProfiles(ctx context.Context) {
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		l.log.Warn("reading the libraries' organize profiles", "err", err)
		return
	}
	defined := map[string]bool{}
	for _, p := range l.lib.Profiles() {
		defined[p.Name] = true
	}
	// Named as the table names them, which a start has not built yet.
	var names map[model.PID]string
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast || lib.Profile == "" || defined[lib.Profile] {
			continue
		}
		if names == nil {
			names = l.rootNames(ctx, slices.DeleteFunc(slices.Clone(libs), func(lib *model.Library) bool {
				return lib.Mode == model.ModePodcast || lib.DisplayRoot == ""
			}))
		}
		l.log.Warn("a library names an organize profile that is not defined; it uses the default",
			"root", lib.DisplayRoot, "profile", lib.Profile)
		spec := config.Root{Path: lib.DisplayRoot, Mode: lib.Mode, Media: lib.Media}
		if _, err := l.lib.AddRoot(ctx, spec, waxbin.AllowAbsent()); err != nil {
			l.log.Warn("moving a library to the default profile", "root", lib.DisplayRoot, "err", err)
			continue
		}
		l.Audit(ctx, nil, "library.profile", AuditTarget{Kind: "library", PID: apiPID(PrefixLibrary, lib.PID), Name: names[lib.PID]},
			map[string]any{"profile": organize.DefaultProfileName, "undefined": lib.Profile})
	}
}

// declaredMedia is what the configuration says a root holds, or empty
// where it says nothing.
func (l *Library) declaredMedia(lib *model.Library) model.MediaType {
	for _, r := range l.configRoots {
		if r.Media != "" && samePath(rootKey(r.Path), rootKey(lib.DisplayRoot)) {
			return model.MediaType(r.Media)
		}
	}
	return ""
}

// SetLibraryMedia changes what a library holds in place and starts the
// scan that applies it to the files already there: an ordinary one onto
// audiobook (the scan re-reads an unlocked track an audiobook root owes
// a book), a forced one otherwise (music and mixed classify by tags,
// which only a read checks, so unchanged files are read again only when
// forced). The podcast library, and a root the configuration declares,
// refuse.
func (l *Library) SetLibraryMedia(ctx context.Context, uc *UserCtx, apiLibraryPID, media string) (LibraryInfo, error) {
	if !uc.Admin {
		return LibraryInfo{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return LibraryInfo{}, errNotFound("no library with pid " + apiLibraryPID)
	}
	lib, err := l.libraryByPID(ctx, pid)
	if KindOf(err) == KindNotFound {
		return LibraryInfo{}, errNotFound("no library with pid " + apiLibraryPID)
	} else if err != nil {
		return LibraryInfo{}, err
	}
	if lib.Mode == model.ModePodcast {
		return LibraryInfo{}, errInvalid("the podcast library holds podcasts")
	}
	to := model.MediaType(media)
	switch to {
	case model.MediaMusic, model.MediaAudiobook, model.MediaMixed:
	default:
		return LibraryInfo{}, errInvalid("a library holds music, audiobook or mixed")
	}
	if declared := l.declaredMedia(lib); declared != "" && declared != to {
		return LibraryInfo{}, errInvalid("WAXDECK_AUDIOBOOK_ROOTS declares what this library holds; change the configuration instead")
	}
	from := lib.MediaType()
	if from == to {
		// Nothing to apply, so no scan.
		return l.libraryInfo(lib), nil
	}
	// An existing library's folder may be unmounted; what it holds is
	// policy. Mode and profile ride along, or the re-add resets them.
	updated, err := l.lib.AddRoot(ctx, config.Root{Path: lib.DisplayRoot, Mode: lib.Mode, Media: to, Profile: lib.Profile},
		waxbin.AllowAbsent())
	if err != nil {
		return LibraryInfo{}, classify(err)
	}
	l.refreshLibraryState(ctx)
	force := to != model.MediaAudiobook
	jobPID, scanErr := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{LibraryPID: pid, Force: force})
	if scanErr == nil {
		l.followStarted(ctx, jobPID, uc.ID)
	} else {
		l.log.Warn("a library's media changed while a catalog job is running; rescan it once the job ends",
			"library", apiLibraryPID, "force", force, "err", scanErr)
	}
	l.Audit(ctx, uc, "library.media", AuditTarget{Kind: "library", PID: apiLibraryPID, Name: l.libraryInfo(lib).Name},
		map[string]any{"media": string(to), "from": string(from), "scanStarted": scanErr == nil})
	info := l.libraryInfo(updated)
	info.ScanStarted = scanErr == nil
	return info, nil
}

// AddLibraryInput describes a runtime library-root creation. AllowAbsent
// registers a folder that is not there yet, a drive mounted later.
type AddLibraryInput struct {
	Name        string
	Path        string
	Media       string // music|audiobook|mixed; empty defaults to mixed
	Managed     bool
	AllowAbsent bool
}

// FlowRootSync is the streaming bridge's runtime-root surface, wired
// after construction like FlowJobs (the bridge needs this service as its
// resolver). A nil sync means no sidecar is configured, or one whose
// roots are pinned at startup; either way a runtime-added root browses
// and downloads normally and streams once the sidecar learns it.
type FlowRootSync interface {
	// RootNames lists every root name the bridge maps. It is wider than
	// the service's own table: the podcast download dir is a bridge root
	// and never enters it.
	RootNames() []string
	// SyncRoot teaches the bridge the new root and brings the sidecar to
	// the same set. Both halves are needed: reloading the sidecar alone
	// leaves streaming broken, because stream-ref resolution walks the
	// bridge's own table. A nil error means streaming works now; any
	// error says what an administrator still has to do.
	SyncRoot(ctx context.Context, name, path string) error
	// RemoveRoot unmounts a removed library's root from the bridge and
	// the sidecar alike; a name neither maps is no error. A non-nil
	// error says what the sidecar still serves.
	RemoveRoot(ctx context.Context, name string) error
}

// SetFlowRoots wires the bridge's runtime-root surface, and brings it to
// the root table (syncFlowRoots). Nil says no streaming engine is
// configured: there is no sidecar to tell anything.
func (l *Library) SetFlowRoots(s FlowRootSync) {
	l.flowRoots.Store(&s)
	l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
		l.syncFlowRoots(ctx)
		return nil
	})
}

// AddLibrary catalogs a new root, names it, teaches the streaming sidecar and
// kicks a scan. A sidecar that cannot take the root leaves streaming for its
// restart, which StreamingWarning reports. Administrators only.
func (l *Library) AddLibrary(ctx context.Context, uc *UserCtx, in AddLibraryInput) (LibraryInfo, error) {
	if !uc.Admin {
		return LibraryInfo{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return LibraryInfo{}, errInvalid("a library name is required")
	}
	if strings.ContainsAny(name, `/\`) {
		return LibraryInfo{}, errInvalid("a library name cannot contain a path separator")
	}
	path := strings.TrimSpace(in.Path)
	if path == "" {
		return LibraryInfo{}, errInvalid("a library path is required")
	}
	if !filepath.IsAbs(path) {
		return LibraryInfo{}, errInvalid("the library path must be absolute")
	}
	path = rootKey(path)
	var media model.MediaType
	switch in.Media {
	case "", string(model.MediaMixed):
		media = model.MediaMixed
	case string(model.MediaMusic):
		media = model.MediaMusic
	case string(model.MediaAudiobook):
		media = model.MediaAudiobook
	default:
		return LibraryInfo{}, errInvalid("media must be music, audiobook, or mixed")
	}
	mode := model.ModeInPlace
	if in.Managed {
		mode = model.ModeManaged
	}
	lib, err := l.registerRoot(ctx, name, path, mode, media, in.AllowAbsent)
	if err != nil {
		return LibraryInfo{}, err
	}
	// Neither the path attribution nor the watcher waits for the feed's
	// library row.
	l.refreshLibraryState(ctx)
	streamWarning := l.syncFlowRoot(ctx, name, path)
	// Scan the new root in the background. A scan (or other catalog job)
	// already in flight was snapshotted before this root existed and will not
	// cover it, so on a conflict the root waits for the next scan; log that so
	// the gap is visible rather than silently swallowed.
	_, scanErr := l.Rescan(ctx, false)
	if scanErr != nil {
		if KindOf(scanErr) == KindConflict {
			l.log.Warn("library created while a catalog job is running; its root will index on the next scan, or rescan manually",
				"library", name)
		} else {
			l.log.Warn("scan after library create failed", "library", name, "err", scanErr)
		}
	}
	apiLibPID := apiPID(PrefixLibrary, lib.PID)
	detail := map[string]any{"name": name, "path": path, "media": string(media), "managed": in.Managed}
	if streamWarning != "" {
		// The reload error is the verification that the sidecar can see the
		// path (it opens each root with os.Root while reconciling), so it
		// belongs where the administrator who made the change will find it,
		// not only in the server log.
		detail["streamingWarning"] = streamWarning
	}
	l.Audit(ctx, uc, "library.create", AuditTarget{Kind: "library", PID: apiLibPID, Name: name}, detail)
	info := l.libraryInfo(lib)
	// The response carries the warning too: the administrator who made the
	// change reads it, not the log.
	info.StreamingWarning, info.ScanStarted = streamWarning, scanErr == nil
	return info, nil
}

// syncFlowRoot brings the streaming sidecar to the new root. It
// degrades rather than fails: the library is already created, and
// browsing, downloading, and direct playback never depended on the
// sidecar. The returned string is empty when streaming works now, and
// otherwise says what an administrator still has to do.
func (l *Library) syncFlowRoot(ctx context.Context, name, path string) string {
	flow := l.flowRootSync()
	if flow == nil {
		return ""
	}
	l.flowSyncMu.Lock()
	defer l.flowSyncMu.Unlock()
	warning := ""
	if !slices.Contains(flow.RootNames(), name) {
		warning = l.teachFlowRoot(ctx, flow, name, path)
	}
	// A root taken while the engine is away is written for the sidecar and
	// reloaded when the engine answers: nothing refused it, and nothing
	// streams from it yet.
	if warning == "" && l.engineAway() {
		return "streaming from this library starts when the streaming engine answers again"
	}
	return warning
}

// flowRefusal is a root the bridge refused at its path, with how many
// times the engine had gone away when it was offered: the answer that
// ends a later outage offers it again.
type flowRefusal struct {
	path    string
	outages uint64
}

// teachFlowRoot offers the bridge one root, remembering a refusal. The
// caller holds flowSyncMu.
func (l *Library) teachFlowRoot(ctx context.Context, flow FlowRootSync, name, path string) string {
	outages := l.flowOutages.Load()
	err := flow.SyncRoot(ctx, name, path)
	if err == nil {
		delete(l.flowRefused, name)
		return ""
	}
	if l.flowRefused == nil {
		l.flowRefused = map[string]flowRefusal{}
	}
	l.flowRefused[name] = flowRefusal{path: path, outages: outages}
	l.log.Warn("the streaming sidecar did not take a library's root", "library", name, "err", err)
	return "streaming from this library is not available yet: " + err.Error()
}

// registerRoot catalogs a root at a free path under a name nothing uses,
// the bridge's included (it mounts the podcast dir). A taken path or name
// is answered first, and the create then holds both (claimRoot) while its
// folder is looked at off every lock, within a bound, so a mount that
// stopped answering fails this create alone; the write probe goes only
// into a folder no library holds, never on a read-only server. path is
// absolute and clean; allowAbsent takes a folder that does not answer yet.
func (l *Library) registerRoot(ctx context.Context, name, path string, mode model.Mode, media model.MediaType, allowAbsent bool) (*model.Library, error) {
	claim, release, err := l.claimRoot(ctx, name, path, mode == model.ModeManaged)
	if err != nil {
		return nil, err
	}
	defer release()
	probed, err := l.lookAtFolder(ctx, claim, allowAbsent)
	if err != nil {
		return nil, err
	}
	if err := l.rootStillFree(ctx, name, path); err != nil {
		return nil, err
	}
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	key := rootKey(path)
	// The catalog keeps the root and its policy; the name is WaxDeck's, and
	// it goes in first. The feed refreshes the table the moment the root
	// lands, naming any root without a stored name after its directory,
	// and the bridge would be taught that name beside this one.
	if err := l.db.LibraryRootsUpsert(ctx, wdb.LibraryRoot{
		Path: key, Name: name, CreatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	var opts []waxbin.RootOption
	if allowAbsent {
		opts = append(opts, waxbin.AllowAbsent())
	}
	// The look's probe is this root's first answer; the refresh that takes
	// it in asks for no other.
	l.rootProbe.createdAt(path, probed)
	lib, err := l.lib.AddRoot(ctx, config.Root{Path: path, Mode: mode, Media: media}, opts...)
	if err != nil {
		l.rootProbe.createdAt(path, false)
		// Not on the request's context: a client gone mid-create is a likely
		// reason the add failed, and the name must not outlive it.
		if derr := l.db.LibraryRootsDelete(context.WithoutCancel(ctx), key); derr != nil {
			l.log.Warn("dropping the name of a library the catalog refused", "library", name, "err", derr)
		}
		return nil, classify(err)
	}
	return lib, nil
}

// RemoveLibrary takes a library out of the catalog, its files staying on
// disk, and answers the job doing it; the job's end drops what WaxDeck
// keeps of it (followRootRemoval). A root the configuration names comes
// back at every start, so it is refused, as is the podcast library.
// Administrators only.
func (l *Library) RemoveLibrary(ctx context.Context, uc *UserCtx, apiLibraryPID string) (Job, error) {
	if !uc.Admin {
		return Job{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return Job{}, errNotFound("no library with pid " + apiLibraryPID)
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return Job{}, err
	}
	lib, err := l.libraryByPID(ctx, pid)
	if KindOf(err) == KindNotFound {
		return Job{}, errNotFound("no library with pid " + apiLibraryPID)
	} else if err != nil {
		return Job{}, err
	}
	if lib.Mode == model.ModePodcast {
		return Job{}, errInvalid("the podcast library follows the podcast download folder and cannot be removed")
	}
	if l.configuredRoot(lib.DisplayRoot) {
		return Job{}, &Error{Kind: KindConflict,
			Msg: "this library is configured in WAXDECK_LIBRARY_ROOTS; take it out of the configuration and restart, then remove it here"}
	}
	facts := removalFacts{Name: l.libraryInfo(lib).Name, Path: lib.DisplayRoot}
	detail, err := json.Marshal(facts)
	if err != nil {
		return Job{}, &Error{Kind: KindInternal, Err: err}
	}
	// Kept before the start: the job can end before its origin lands.
	seq := l.removals.begin(pid, removal{name: facts.Name, path: facts.Path, userID: uc.ID})
	jobPID, err := l.lib.StartRemoveRoot(l.procCtx, pid, waxbin.RemoveRootOptions{})
	if err != nil {
		l.removals.abandon(pid, seq)
		return Job{}, classifyMutation(err)
	}
	if err := l.adoptJobWith(ctx, wdb.JobOrigin{PID: string(jobPID), UserID: uc.ID, Detail: string(detail)}); err != nil {
		// No origin holds it, so its end is the follower's, now or when seen.
		l.removals.unrecord(pid)
		if j, err := l.lib.Job(ctx, jobPID); err == nil && j.State != model.JobRunning {
			l.settleLater(func(ctx context.Context) { l.settleUnrecordedRemoval(ctx, j) })
		}
	}
	return l.JobStatus(ctx, apiPID(PrefixJob, jobPID))
}

// rootTaken refuses a create at a folder a library holds, or under a name
// a root goes by.
func (l *Library) rootTaken(ctx context.Context, name, path string, libs []*model.Library) error {
	held := map[string]bool{}
	for _, lib := range libs {
		key := rootKey(lib.DisplayRoot)
		if samePath(key, path) {
			return &Error{Kind: KindConflict, Msg: "a library at " + path + " already exists"}
		}
		held[key] = true
	}
	taken := []string{l.podcastRootName}
	for _, r := range l.libraryRoots() {
		taken = append(taken, r.Name)
	}
	for _, r := range l.configRoots {
		taken = append(taken, r.Name)
	}
	if stored, err := l.db.LibraryRootsList(ctx); err == nil {
		for _, r := range stored {
			if held[rootKey(r.Path)] {
				taken = append(taken, r.Name)
			}
		}
	}
	if flow := l.flowRootSync(); flow != nil {
		taken = append(taken, flow.RootNames()...)
	}
	if slices.Contains(taken, name) {
		return &Error{Kind: KindConflict, Msg: "a library named " + name + " already exists"}
	}
	return nil
}

// pathsOverlap reports whether one of two clean absolute paths holds the
// other, or both name one folder.
func pathsOverlap(a, b string) bool {
	holds := func(root, path string) bool {
		rel, err := filepath.Rel(root, path)
		return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
	}
	return holds(a, b) || holds(b, a)
}

// folderAnswer is what a look at a new library's folder found.
type folderAnswer int

const (
	// folderBroken is a look that ended without an answer.
	folderBroken folderAnswer = iota
	folderListed
	folderIsFile
	// folderUnlisted is a folder whose names the server cannot read.
	folderUnlisted
	// folderForbidden is a path its parents keep the server out of.
	folderForbidden
	folderMissing
	// folderUnreadable is any other error.
	folderUnreadable
)

// lookAt looks at the folder at path: a stat, then one name read.
func lookAt(path string) folderAnswer {
	switch st, err := os.Stat(path); {
	case err == nil && !st.IsDir():
		return folderIsFile
	case err == nil && !folderListable(path):
		return folderUnlisted
	case err == nil:
		return folderListed
	case errors.Is(err, fs.ErrPermission):
		return folderForbidden
	case errors.Is(err, fs.ErrNotExist) || errors.Is(err, syscall.ENOTDIR):
		return folderMissing
	default:
		return folderUnreadable
	}
}

// folderRefusal is why the folder a look found cannot be a new library,
// or nil; allowAbsent takes one that is not there yet.
func folderRefusal(path string, found folderAnswer, allowAbsent bool) error {
	switch {
	case found == folderListed:
		return nil
	case found == folderIsFile:
		return errInvalid(path + " is a file, not a folder")
	case found == folderBroken || found == folderUnlisted || found == folderForbidden:
		// Mounting there later would not change what its parents allow.
		return errInvalid("the server cannot read the library path")
	case allowAbsent:
		// Mounted later, as asked: its scans say unreachable until then.
		return nil
	case found == folderMissing:
		return errInvalid("there is no folder at " + path + " on the server")
	default:
		return errInvalid("the server cannot read the library path")
	}
}

// folderListable reports whether the server can list a folder's names: a
// stat needs only its parents searchable, and every scan reads names.
func folderListable(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	_, err = f.Readdirnames(1)
	return err == nil || errors.Is(err, io.EOF)
}
