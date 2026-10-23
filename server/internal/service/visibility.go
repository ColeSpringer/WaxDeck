package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// UserCtx is the acting user as the catalog surfaces need it: the
// WaxDeck identity, the catalog user its playback state binds to, and
// the library-visibility scope. Handlers build one per request from the
// authenticated principal.
type UserCtx struct {
	ID         string // WaxDeck user id (us-...)
	CatalogPID string // bare WaxBin user PID
	Admin      bool
	// AllLibraries short-circuits visibility: admins and mode=all
	// accounts see everything.
	AllLibraries bool
	// Libraries is the granted set (bare library PIDs) when
	// AllLibraries is false.
	Libraries map[string]bool
	// UploadEnabled grants the upload surface (administrators always
	// have it); UploadQuotaBytes caps what may sit in upload staging at
	// once, 0 meaning no cap.
	UploadEnabled    bool
	UploadQuotaBytes int64
	// Granular permission toggles; administrators hold all of them.
	Download       bool
	Delete         bool
	Explicit       bool
	SharedOutputs  bool
	ManagePodcasts bool
	// MaxTranscodeKbps caps the caller's transcode bitrate; 0 means the
	// server default applies. Administrators are uncapped.
	MaxTranscodeKbps int64
	// TagAllow and TagDeny are the caller's content rules; empty for
	// administrators and unrestricted accounts.
	TagAllow []TagRule
	TagDeny  []TagRule
}

// ContentUnrestricted reports whether content filtering can be skipped
// entirely for this caller: explicit content allowed and no tag rules.
func (uc *UserCtx) ContentUnrestricted() bool {
	return uc.Explicit && len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0
}

// ScopeKey fingerprints everything that narrows what the caller sees -
// role, library grants, the explicit toggle, tag rules - so a cache of
// caller-scoped answers misses the moment any of it changes.
func (uc *UserCtx) ScopeKey() string {
	libs := make([]string, 0, len(uc.Libraries))
	for lib := range uc.Libraries {
		libs = append(libs, lib)
	}
	sort.Strings(libs)
	raw, _ := json.Marshal(struct {
		Admin, All, Explicit bool
		Libs                 []string
		Allow, Deny          []TagRule
	}{uc.Admin, uc.AllLibraries, uc.Explicit, libs, uc.TagAllow, uc.TagDeny})
	// A digest, so a key stays one size however many grants and rules
	// it stands for.
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

// UserByName resolves an account row by its username, for the surfaces
// where the caller names somebody else - the Subsonic getUser view is
// the one such surface today. Answers KindNotFound for a name no
// account carries; the caller decides who may ask.
func (l *Library) UserByName(ctx context.Context, username string) (*wdb.User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, &Error{Kind: KindNotFound, Err: err}
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return u, nil
}

// UserCtx assembles the per-request user context from an account row.
func (l *Library) UserCtx(ctx context.Context, u *wdb.User) (*UserCtx, error) {
	uc := &UserCtx{
		ID:               u.ID,
		CatalogPID:       l.catalogPID(u),
		Admin:            hasRole(u.Roles, "admin"),
		UploadEnabled:    u.UploadEnabled,
		UploadQuotaBytes: u.UploadQuotaBytes,
	}
	uc.UploadEnabled = uc.UploadEnabled || uc.Admin
	perms := permissionsOf(u)
	if uc.Admin {
		perms = Permissions{Download: true, Delete: true, Explicit: true,
			SharedOutputs: true, ManagePodcasts: true}
	}
	uc.Download = perms.Download
	uc.Delete = perms.Delete
	uc.Explicit = perms.Explicit
	uc.SharedOutputs = perms.SharedOutputs
	uc.ManagePodcasts = perms.ManagePodcasts
	uc.MaxTranscodeKbps = perms.MaxTranscodeKbps
	uc.TagAllow, uc.TagDeny = perms.TagAllow, perms.TagDeny
	uc.AllLibraries = uc.Admin || u.LibraryAccess != "granted"
	if !uc.AllLibraries {
		pids, err := l.db.LibraryGrants(ctx, u.ID)
		if err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		uc.Libraries = make(map[string]bool, len(pids))
		for _, pid := range pids {
			uc.Libraries[pid] = true
		}
	}
	return uc, nil
}

// libraryDirs is the path-to-library attribution table: every library
// root, longest path first so nested roots (the podcast dir under a
// media mount) attribute to the deepest match.
type libraryDirs struct {
	mu   sync.Mutex
	dirs []libraryDir
	// podcast is the podcast library's bare PID, recorded as the table
	// loads; empty while there is none. podcastAtRoot says it is the one
	// at the configured directory rather than one an earlier directory
	// left.
	podcast       string
	podcastAtRoot bool
	// podcasts is every podcast-mode library, an earlier directory's
	// included.
	podcasts []string
	// missed is when podcastLibrary last reloaded the table without
	// finding the podcast library; zero when it has not. missFailed says
	// that reload failed and no load has worked since, so the table is of
	// unknown age.
	missed     time.Time
	missFailed bool
}

type libraryDir struct {
	path string // clean absolute root path with trailing separator
	pid  string // bare library PID
}

// invalidateAttribution drops the path-to-library attribution cache so the
// next lookup rebuilds it. A miss already forces a reload, so this is not
// required for correctness; it makes a runtime library add take effect at
// once rather than on the first cache miss under the new root.
func (l *Library) invalidateAttribution() {
	l.libDirs.mu.Lock()
	l.libDirs.dirs, l.libDirs.podcast, l.libDirs.podcastAtRoot, l.libDirs.missed = nil, "", false, time.Time{}
	l.libDirs.podcasts, l.libDirs.missFailed = nil, false
	l.libDirs.mu.Unlock()
}

// attribution returns the attribution table, loading it on first use.
// forceReload refreshes it (a miss may mean a library appeared since).
func (l *Library) attribution(ctx context.Context, forceReload bool) ([]libraryDir, error) {
	dirs, _, _, err := l.attributionTable(ctx, forceReload)
	return dirs, err
}

// attributionTable is attribution with the podcast library's PID, known
// by its mode rather than by matching the configured directory against
// the stored root: where the platform folds case the catalog keeps the
// spelling it first saw. A server that changed its podcast directory has
// the old library too, and the one at the configured root, by the rule
// the catalog matches roots with, is the one downloads land in now;
// atRoot says the one recorded is that one.
func (l *Library) attributionTable(ctx context.Context, forceReload bool) (dirs []libraryDir, podcast string, atRoot bool, err error) {
	l.libDirs.mu.Lock()
	defer l.libDirs.mu.Unlock()
	if l.libDirs.dirs != nil && !forceReload {
		return l.libDirs.dirs, l.libDirs.podcast, l.libDirs.podcastAtRoot, nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, "", false, classify(err)
	}
	dirs = make([]libraryDir, 0, len(libs))
	var podcasts []string
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast {
			here := samePath(rootKey(lib.DisplayRoot), rootKey(l.podcastDir))
			if podcast == "" || (here && !atRoot) {
				podcast, atRoot = string(lib.PID), here
			}
			podcasts = append(podcasts, string(lib.PID))
		}
		root := lib.DisplayRoot
		if root == "" {
			continue
		}
		dirs = append(dirs, libraryDir{
			path: strings.TrimSuffix(filepath.Clean(root), string(filepath.Separator)) + string(filepath.Separator),
			pid:  string(lib.PID),
		})
	}
	sort.Slice(dirs, func(i, j int) bool { return len(dirs[i].path) > len(dirs[j].path) })
	l.libDirs.dirs, l.libDirs.podcast, l.libDirs.podcastAtRoot = dirs, podcast, atRoot
	l.libDirs.podcasts, l.libDirs.missFailed = podcasts, false
	return dirs, podcast, atRoot, nil
}

// podcastLibraries answers every podcast-mode library: the one at the
// configured directory, and any an earlier directory left, which still
// holds the episodes fetched while it was configured.
func (l *Library) podcastLibraries(ctx context.Context) ([]string, error) {
	if _, _, _, err := l.attributionTable(ctx, false); err != nil {
		return nil, err
	}
	l.libDirs.mu.Lock()
	defer l.libDirs.mu.Unlock()
	return slices.Clone(l.libDirs.podcasts), nil
}

// libraryForPath attributes a file path to its library PID, or "" when
// no library contains it.
func (l *Library) libraryForPath(ctx context.Context, path string) (string, error) {
	dirs, err := l.attribution(ctx, false)
	if err != nil {
		return "", err
	}
	if pid := matchDir(dirs, path); pid != "" {
		return pid, nil
	}
	// A miss may mean a library was added since the table loaded.
	if dirs, err = l.attribution(ctx, true); err != nil {
		return "", err
	}
	return matchDir(dirs, path), nil
}

func matchDir(dirs []libraryDir, path string) string {
	clean := filepath.Clean(path)
	for _, d := range dirs {
		// The stored root carries a trailing separator so a sibling root
		// sharing a name prefix (music vs music-hd) can never match; the
		// equality check keeps the root directory itself attributable
		// (Clean strips its trailing separator).
		if strings.HasPrefix(clean, d.path) ||
			clean == strings.TrimSuffix(d.path, string(filepath.Separator)) {
			return d.pid
		}
	}
	return ""
}

// itemVisible reports whether the item is inside the user's visible
// libraries. Full-visibility users skip attribution entirely. An item
// with no file (missing, stream-only) is attributed to no library and
// so fails closed for restricted users, except an episode: it belongs to
// the podcast library whether or not it has a file (viewVisible's rule).
//
// The located record carries the library handle, so this reads it
// rather than re-deriving it from the path. That is also the more
// durable of the two: a relocate rewrites every root's paths and leaves
// the library pids alone.
func (l *Library) itemVisible(ctx context.Context, uc *UserCtx, pid model.PID) bool {
	if uc.AllLibraries {
		return true
	}
	if loc, err := l.paths.Locate(ctx, pid); err == nil && loc.LibraryPID != "" {
		return uc.Libraries[string(loc.LibraryPID)]
	}
	// The record does not say what a fileless item is, so the catalog is
	// asked, for the one kind that can still be visible.
	it, err := l.lib.Get(ctx, pid)
	return err == nil && it.Kind == model.KindEpisode && l.podcastsVisible(ctx, uc)
}

// viewVisible is itemVisible for callers already holding a fresh item
// view: it reads the view's own library handle, bypassing the located
// -path cache. The sync paths need this because the cache invalidates
// on a poll, and a delta racing that poll would decide a tombstone from
// a stale attribution.
//
// An episode is visible exactly when the podcast library is: it belongs
// to that library whether or not it has a file, and an unfetched one has
// none to attribute. Every episode file is bound to the podcast library,
// so for a fetched one the two answers are the same.
func (l *Library) viewVisible(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
	if uc.AllLibraries {
		return true
	}
	if it.Kind == model.KindEpisode {
		return l.podcastsVisible(ctx, uc)
	}
	if it.LibraryPID == "" {
		return false
	}
	return uc.Libraries[string(it.LibraryPID)]
}

// grantNode is viewVisible's rule as a query node, for a caller granted
// libraries by pid: the libraries granted, and every episode for a caller
// granted the podcast library, since an unfetched episode's library
// column is empty. Nil for a caller who sees every library.
//
// An allow-list, so `in`: it seeks the index and an empty grant compiles
// to `1=0`. Deliberately not `notIn` over the complement - that is an
// anti-join scanning the catalog, and it keeps every fileless item.
// Sorted so the compiled SQL is stable across map iteration orders, and
// chunked (inSet), since the engine takes at most 500 values in one
// membership test.
func (l *Library) grantNode(ctx context.Context, uc *UserCtx) query.Node {
	if uc.AllLibraries {
		return nil
	}
	libs := make([]string, 0, len(uc.Libraries))
	for lib := range uc.Libraries {
		libs = append(libs, lib)
	}
	sort.Strings(libs)
	granted := inSet("library", libs)
	if !l.podcastsVisible(ctx, uc) {
		return granted
	}
	return query.Or{Nodes: []query.Node{
		granted,
		query.Cond{Field: "kind", Op: query.OpIs, Value: string(model.KindEpisode)},
	}}
}

// podcastsVisible reports whether the caller can see the podcast
// library (shows are not items, so show surfaces gate on the library
// itself). Servers without a podcast dir have nothing to show.
func (l *Library) podcastsVisible(ctx context.Context, uc *UserCtx) bool {
	visible, judged := l.podcastsJudged(ctx, uc)
	if !judged {
		// A no standing on a library list that could not be read.
		noteDegraded(ctx)
	}
	return visible
}

// podcastsJudged is podcastsVisible saying whether its answer is a
// judgment: a false that stands on a podcast library which could not be
// read is not one.
func (l *Library) podcastsJudged(ctx context.Context, uc *UserCtx) (visible, judged bool) {
	if uc.AllLibraries {
		return true, true
	}
	libPID, read := l.podcastLibrary(ctx)
	visible = libPID != "" && uc.Libraries[libPID]
	return visible, visible || read
}

// podcastLibrary answers the podcast library's pid, empty without a
// podcast dir and until the catalog creates the library, which it does on
// the first episode download, and whether the table read it stands on
// worked: false when a load failed and none has worked since, the pid then
// being what an earlier load left, if anything. A miss, no library or only
// one an earlier podcast directory left, reloads the attribution table at
// most once a second rather than on every call: every episode offered a
// restricted reader asks, and on a server that has fetched nothing every
// ask misses. The earlier directory's library stands in meanwhile.
func (l *Library) podcastLibrary(ctx context.Context) (pid string, read bool) {
	if l.podcastDir == "" {
		return "", true
	}
	_, pid, atRoot, err := l.attributionTable(ctx, false)
	if err != nil {
		return "", false
	}
	if atRoot {
		return pid, true
	}
	// On the monotonic clock: a wall clock stepped back would otherwise
	// hold the next reload off for the length of the step.
	l.libDirs.mu.Lock()
	due := l.libDirs.missed.IsZero() || time.Since(l.libDirs.missed) >= time.Second
	if due {
		l.libDirs.missed = time.Now()
	}
	failed := l.libDirs.missFailed
	l.libDirs.mu.Unlock()
	if !due {
		return pid, !failed
	}
	_, fresh, _, err := l.attributionTable(ctx, true)
	if err != nil {
		l.libDirs.mu.Lock()
		l.libDirs.missFailed = true
		l.libDirs.mu.Unlock()
		return pid, false
	}
	return fresh, true
}

// getVisibleItem is getItem plus the visibility check: an item outside
// the caller's scope behaves exactly as if it did not exist.
func (l *Library) getVisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) (*model.ItemView, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return nil, err
	}
	// The fresh view's own library handle rather than the located-path
	// cache: no second read whose failure could pass for "not visible".
	if !l.viewVisible(ctx, uc, it) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	if !l.allowedByContent(ctx, uc, it) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	return it, nil
}

// offers reports whether a listing may offer a hydrated item view to
// this reader: not in the trash, inside the reader's grants, and allowed
// by their content rules. For views read by pid or from a catalog call
// that takes no query node, where nothing upstream applied any of the
// three. viewVisible, not itemVisible: the view carries its library, and
// the located-path cache invalidates on a scan poll, which would drop an
// item out for the length of one. allowedByContent, not advisoryAllows:
// the tag rules are what nothing upstream applied.
func (l *Library) offers(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
	return l.offersWith(ctx, uc, nil, it)
}

// offersWith is offers taking the tag rules' verdicts from a batch read
// beforehand (tagVerdicts); nil asks per item.
func (l *Library) offersWith(ctx context.Context, uc *UserCtx, verdicts map[model.PID]bool, it *model.ItemView) bool {
	return !archived(it) && l.viewVisible(ctx, uc, it) && l.contentAllows(ctx, uc, verdicts, it)
}

// contentAllows is allowedByContent answered from a batch of tag
// verdicts where one was read. An episode stays per item, its advisory
// flags being fields on the view, and so does a trashed item, which the
// batch query leaves out.
func (l *Library) contentAllows(ctx context.Context, uc *UserCtx, verdicts map[model.PID]bool, it *model.ItemView) bool {
	if verdicts != nil && it.Kind != model.KindEpisode && !archived(it) {
		return verdicts[it.PID]
	}
	return l.allowedByContent(ctx, uc, it)
}

// VisibleItem verifies the caller can see the item (play-info calls it
// before minting stream URLs).
func (l *Library) VisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) error {
	_, err := l.getVisibleItem(ctx, uc, apiItemPID)
	return err
}

// VisibleBook is VisibleItem answering, off the same read, whether the
// item is a book, the one kind that can lay out in parts: a caller about
// to ask for a book's layout asks nothing of anything else. The kind is
// the catalog's, never the pid's prefix, since a track's pid names the
// book it became.
func (l *Library) VisibleBook(ctx context.Context, uc *UserCtx, apiItemPID string) (bool, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return false, err
	}
	return it.Kind == model.KindBook, nil
}

// LibraryInfo is one catalog library for the admin surface.
type LibraryInfo struct {
	PID   string
	Name  string
	Media string
	// MediaDeclared is the configuration naming what the root holds, which
	// SetLibraryMedia then refuses to change.
	MediaDeclared bool
	// Path is the root directory, for the screen that manages it. Empty
	// where the catalog holds a path it cannot render as text.
	Path string
	// ItemCount is what the catalog holds under the root, counted at read
	// time. Only Libraries fills it; a create has nothing there yet.
	ItemCount int64
	// StreamingWarning is set by AddLibrary when the root exists but the
	// streaming sidecar did not take it.
	StreamingWarning string
	// ScanStarted is AddLibrary's scan starting; false when another job
	// held the catalog, so the root waits for the next scan.
	ScanStarted bool
	// ReadOnly, FolderFallback, Managed and Profile are the catalog's
	// policy for the root.
	ReadOnly       bool
	FolderFallback bool
	Managed        bool
	Profile        string
	// Configured is the server's configuration naming the root, which
	// only a configuration change takes away. Unreachable is its folder
	// missing at its last scan. Writable is a managed root taking the
	// server's writes when last probed; nil where the server does not
	// probe: an in-place root, or one it treats as read-only.
	Configured  bool
	Unreachable bool
	Writable    *bool
}

// Libraries lists the catalog's libraries with their configured root
// names (falling back to the root directory's base name) and their
// paths. Cheap: no counting.
//
// The Subsonic surface calls this on every getMusicFolders, which
// clients issue on connect, so nothing here may touch the catalog's
// item tables. LibrariesWithCounts is the variant that does, and only
// the administrative listing asks for it.
func (l *Library) Libraries(ctx context.Context) ([]LibraryInfo, error) {
	return l.libraries(ctx, false)
}

// LibrariesWithCounts is Libraries plus how much each root holds: one
// indexed count per library. It is the administrators' listing, which
// says what the last write probe found and writes nothing itself.
func (l *Library) LibrariesWithCounts(ctx context.Context) ([]LibraryInfo, error) {
	return l.libraries(ctx, true)
}

func (l *Library) libraries(ctx context.Context, counts bool) ([]LibraryInfo, error) {
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]LibraryInfo, 0, len(libs))
	for _, lib := range libs {
		info := l.libraryInfo(lib)
		if counts {
			info.ItemCount = l.libraryItemCount(ctx, lib.PID)
		}
		out = append(out, info)
	}
	return out, nil
}

// libraryInfo maps a catalog library, named as the root table names it.
// The catalog stores no media for the podcast library.
func (l *Library) libraryInfo(lib *model.Library) LibraryInfo {
	name, writable := filepath.Base(lib.DisplayRoot), true
	for _, r := range l.libraryRoots() {
		if rootKey(r.Path) == rootKey(lib.DisplayRoot) {
			name, writable = r.Name, !r.Unwritable
		}
	}
	var probed *bool
	if l.probesRoot(lib.Mode == model.ModeManaged, lib.ReadOnly) {
		probed = &writable
	}
	media := string(lib.MediaType())
	if lib.Mode == model.ModePodcast {
		media = "podcast"
	}
	return LibraryInfo{
		PID:            apiPID(PrefixLibrary, lib.PID),
		Name:           name,
		Media:          media,
		MediaDeclared:  l.declaredMedia(lib) != "",
		Path:           lib.DisplayRoot,
		ReadOnly:       lib.ReadOnly,
		FolderFallback: lib.FolderFallback,
		Managed:        lib.Mode == model.ModeManaged,
		Profile:        lib.Profile,
		Configured:     l.configuredRoot(lib.DisplayRoot),
		Unreachable:    l.rootReach.unreachable(lib.PID),
		Writable:       probed,
	}
}

// libraryItemCount counts the playable items a root holds, keyed on the
// catalog's own library dimension: an indexed integer comparison, not
// the path-prefix scan this used to be. The old form compiled
// `startsWith` to `LIKE ? ESCAPE '\'`, and SQLite turns its LIKE
// optimization off whenever an ESCAPE clause is present.
//
// A count that cannot be taken reports zero rather than failing the
// listing - the number is a caption on an administrative table, and
// losing the table over it would be the worse answer.
func (l *Library) libraryItemCount(ctx context.Context, libraryPID model.PID) int64 {
	if libraryPID == "" {
		return 0
	}
	q := query.New(query.EntityItems).Where("library", query.OpIs, string(libraryPID)).Build()
	n, err := l.lib.Count(ctx, q, "")
	if err != nil {
		l.log.Warn("counting a library's items", "library", libraryPID, "err", err)
		return 0
	}
	return int64(n)
}
