package service

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"time"

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
		})
	}
	l.rootsMu.Lock()
	// The first build arms the watcher itself; a re-arm drops events.
	first := !l.rootsBuilt
	moved := !first && !slices.EqualFunc(l.roots, roots, func(a, b Root) bool { return a.Path == b.Path })
	changed := !first && !slices.Equal(l.roots, roots)
	l.roots, l.rootsBuilt = roots, true
	l.rootsMu.Unlock()
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

// flowRootSync is the wired bridge, nil before SetFlowRoots.
func (l *Library) flowRootSync() FlowRootSync {
	if p := l.flowRoots.Load(); p != nil {
		return *p
	}
	return nil
}

// syncFlowRoots teaches the streaming bridge the roots it does not map,
// as a restore or the CLI brings, passing over one it refused at the
// same path.
func (l *Library) syncFlowRoots(ctx context.Context) {
	flow := l.flowRootSync()
	if flow == nil {
		return
	}
	l.flowSyncMu.Lock()
	defer l.flowSyncMu.Unlock()
	known := flow.RootNames()
	for _, r := range l.libraryRoots() {
		if !slices.Contains(known, r.Name) && l.flowRefused[r.Name] != r.Path {
			l.teachFlowRoot(ctx, flow, r.Name, r.Path)
		}
	}
}

// settleRoots brings the catalog's roots to what the server runs with:
// defined profiles, the configured roots, and the table rebuilt.
func (l *Library) settleRoots(ctx context.Context) error {
	l.defaultUndefinedProfiles(ctx)
	if err := l.registerConfiguredRoots(ctx); err != nil {
		return err
	}
	l.refreshLibraryState(ctx)
	return nil
}

// registerConfiguredRoots registers a configured root the catalog lacks or
// holds in another mode, leaving the rest alone so no settle races an edit.
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
		row := rows[rootKey(r.Path)]
		if row != nil && row.Mode == spec.Mode {
			continue
		}
		if row != nil {
			spec.Media, spec.Profile = row.Media, row.Profile
		}
		_, err := l.lib.AddRoot(ctx, spec)
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
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast || lib.Profile == "" || defined[lib.Profile] {
			continue
		}
		l.log.Warn("a library names an organize profile that is not defined; it uses the default",
			"root", lib.DisplayRoot, "profile", lib.Profile)
		spec := config.Root{Path: lib.DisplayRoot, Mode: lib.Mode, Media: lib.Media}
		if _, err := l.lib.AddRoot(ctx, spec); err != nil {
			l.log.Warn("moving a library to the default profile", "root", lib.DisplayRoot, "err", err)
			continue
		}
		l.Audit(ctx, nil, "library.profile", AuditTarget{Kind: "library", PID: apiPID(PrefixLibrary, lib.PID)},
			map[string]any{"profile": organize.DefaultProfileName, "undefined": lib.Profile})
	}
}

// AddLibraryInput describes a runtime library-root creation.
type AddLibraryInput struct {
	Name    string
	Path    string
	Media   string // music|audiobook|mixed; empty defaults to mixed
	Managed bool
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
}

// SetFlowRoots wires the bridge's runtime-root surface, and teaches it
// the roots added while it was being wired.
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
	lib, err := l.registerRoot(ctx, name, path, mode, media)
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
	l.Audit(ctx, uc, "library.create", AuditTarget{Kind: "library", PID: apiLibPID}, detail)
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
	if slices.Contains(flow.RootNames(), name) {
		return ""
	}
	return l.teachFlowRoot(ctx, flow, name, path)
}

// teachFlowRoot offers the bridge one root, remembering a refusal. The
// caller holds flowSyncMu.
func (l *Library) teachFlowRoot(ctx context.Context, flow FlowRootSync, name, path string) string {
	err := flow.SyncRoot(ctx, name, path)
	if err == nil {
		delete(l.flowRefused, name)
		return ""
	}
	if l.flowRefused == nil {
		l.flowRefused = map[string]string{}
	}
	l.flowRefused[name] = path
	l.log.Warn("the streaming sidecar did not take a library's root", "library", name, "err", err)
	return "streaming from this library is not available yet: " + err.Error()
}

// registerRoot catalogs a root at a free path under a name nothing uses,
// the bridge's included (it mounts the podcast dir). rootsMu spans the
// checks, the add and the stored name, so two creates cannot both pass.
func (l *Library) registerRoot(ctx context.Context, name, path string, mode model.Mode, media model.MediaType) (*model.Library, error) {
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	held := map[string]bool{}
	for _, lib := range libs {
		held[rootKey(lib.DisplayRoot)] = true
	}
	if held[rootKey(path)] {
		return nil, &Error{Kind: KindConflict, Msg: "a library at " + path + " already exists"}
	}
	taken := []string{l.podcastRootName}
	for _, r := range l.roots {
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
		return nil, &Error{Kind: KindConflict, Msg: "a library named " + name + " already exists"}
	}
	lib, err := l.lib.AddRoot(ctx, config.Root{Path: path, Mode: mode, Media: media})
	if err != nil {
		return nil, classify(err)
	}
	// The catalog keeps the root and its policy; the name is WaxDeck's.
	if err := l.db.LibraryRootsUpsert(ctx, wdb.LibraryRoot{
		Path: lib.DisplayRoot, Name: name, CreatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		l.log.Warn("storing a library's name failed; it reads as its directory",
			"library", name, "err", err)
	}
	return lib, nil
}
