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

// Grants is who may see what: library grants, permissions and the
// visibility the catalog queries filter by, and with them a caller's
// context built from an account and which library holds a path.
type Grants struct {
	*core
	// libDirs caches path-to-library attribution: which library holds a
	// path, for visibility checks and every other caller of libraryForPath.
	libDirs libraryDirs
}

func newGrants(c *core, _ Config) *Grants { return &Grants{core: c} }

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

// seesEverything reports whether every item read answers this caller:
// every library, explicit content, and no tag rules, which every
// administrator holds. Not fullReach, which leaves the explicit toggle
// out: a surface that can hold episodes asks this.
func seesEverything(uc *UserCtx) bool {
	return uc.AllLibraries && uc.ContentUnrestricted()
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

// UserByName resolves an account by its username, for the surfaces
// where the caller names somebody else - the Subsonic getUser view is
// the one such surface today. Answers KindNotFound for a name no
// account carries; the caller decides who may ask.
func (l *Grants) UserByName(ctx context.Context, username string) (*User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, &Error{Kind: KindNotFound, Err: err}
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return userOf(u), nil
}

// UserCtxFor is UserCtx for an account the service answered as a User,
// for callers that hold the User rather than its row.
func (l *Grants) UserCtxFor(ctx context.Context, u *User) (*UserCtx, error) {
	row, err := u.held()
	if err != nil {
		return nil, err
	}
	return l.UserCtx(ctx, row)
}

// UserCtx assembles the per-request user context from an account row.
func (l *Grants) UserCtx(ctx context.Context, u *wdb.User) (*UserCtx, error) {
	uc := &UserCtx{
		ID:               u.ID,
		CatalogPID:       l.Identity.catalogPID(u),
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
func (l *Grants) invalidateAttribution() {
	l.libDirs.mu.Lock()
	l.libDirs.dirs, l.libDirs.podcast, l.libDirs.podcastAtRoot, l.libDirs.missed = nil, "", false, time.Time{}
	l.libDirs.podcasts, l.libDirs.missFailed = nil, false
	l.libDirs.mu.Unlock()
}

// attribution returns the attribution table, loading it on first use.
// forceReload refreshes it (a miss may mean a library appeared since).
func (l *Grants) attribution(ctx context.Context, forceReload bool) ([]libraryDir, error) {
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
func (l *Grants) attributionTable(ctx context.Context, forceReload bool) (dirs []libraryDir, podcast string, atRoot bool, err error) {
	l.libDirs.mu.Lock()
	defer l.libDirs.mu.Unlock()
	if err = l.loadLibraryDirs(ctx, forceReload); err != nil {
		return nil, "", false, err
	}
	return l.libDirs.dirs, l.libDirs.podcast, l.libDirs.podcastAtRoot, nil
}

// loadLibraryDirs reads the attribution table into libDirs, unless it
// holds one and forceReload is false. libDirs.mu is held.
func (l *Grants) loadLibraryDirs(ctx context.Context, forceReload bool) error {
	if l.libDirs.dirs != nil && !forceReload {
		return nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return classify(err)
	}
	dirs := make([]libraryDir, 0, len(libs))
	var podcast string
	var atRoot bool
	var podcasts []string
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast {
			here := samePath(rootKey(lib.DisplayRoot), rootKey(l.Podcasts.podcastDir))
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
	return nil
}

// podcastLibraries answers every podcast-mode library: the one at the
// configured directory, and any an earlier directory left, which still
// holds the episodes fetched while it was configured. Read under the lock
// that loads the table: a table dropped in between would answer none.
func (l *Grants) podcastLibraries(ctx context.Context) ([]string, error) {
	l.libDirs.mu.Lock()
	defer l.libDirs.mu.Unlock()
	if err := l.loadLibraryDirs(ctx, false); err != nil {
		return nil, err
	}
	return slices.Clone(l.libDirs.podcasts), nil
}

// libraryForPath attributes a file path to its library PID, or "" when
// no library contains it.
func (l *Grants) libraryForPath(ctx context.Context, path string) (string, error) {
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
func (l *Grants) itemVisible(ctx context.Context, uc *UserCtx, pid model.PID) bool {
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
func (l *Grants) viewVisible(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
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

// node is viewVisible's rule as a query node, for a caller granted
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
func (l *Grants) node(ctx context.Context, uc *UserCtx) query.Node {
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

// scopedTo narrows a builder to what the caller may enumerate: their tag
// rules and their library grants.
func (l *Grants) scopedTo(ctx context.Context, uc *UserCtx, b *query.Builder) *query.Builder {
	// The caller's tag rules, as a node rather than the per-item pass
	// that used to be their only home: a bucket count that ignored them
	// read higher than the list it opened, and an "Appears on" card could
	// open onto nothing.
	b = b.WhereNode(l.contentRuleNode(ctx, uc))
	if grants := l.node(ctx, uc); grants != nil {
		b = b.WhereNode(grants)
	}
	return b
}

// podcastsVisible reports whether the caller can see the podcast
// library (shows are not items, so show surfaces gate on the library
// itself). Servers without a podcast dir have nothing to show.
func (l *Grants) podcastsVisible(ctx context.Context, uc *UserCtx) bool {
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
func (l *Grants) podcastsJudged(ctx context.Context, uc *UserCtx) (visible, judged bool) {
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
func (l *Grants) podcastLibrary(ctx context.Context) (pid string, read bool) {
	if l.Podcasts.podcastDir == "" {
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

// podcastLibraryMayHaveLanded drops a library table that does not hold
// the podcast library at the configured directory, so the next lookup
// reloads it at once: the catalog creates that library on the first
// download, and a miss holds the table's next reload off for a second,
// which would tell every request meanwhile there is none.
func (l *Grants) podcastLibraryMayHaveLanded() {
	if l.Podcasts.podcastDir == "" {
		return
	}
	l.libDirs.mu.Lock()
	known := l.libDirs.podcastAtRoot
	l.libDirs.mu.Unlock()
	if !known {
		l.invalidateAttribution()
	}
}

// getVisibleItem is getItem plus the visibility check: an item outside
// the caller's scope behaves exactly as if it did not exist.
func (l *Grants) getVisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) (*model.ItemView, error) {
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
func (l *Grants) offers(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
	return l.offersWith(ctx, uc, nil, it)
}

// offersWith is offers taking the tag rules' verdicts from a batch read
// beforehand (tagVerdicts); nil asks per item.
func (l *Grants) offersWith(ctx context.Context, uc *UserCtx, verdicts map[model.PID]bool, it *model.ItemView) bool {
	return !archived(it) && l.viewVisible(ctx, uc, it) && l.contentAllows(ctx, uc, verdicts, it)
}

// contentAllows is allowedByContent answered from a batch of tag
// verdicts where one was read. An episode stays per item, its advisory
// flags being fields on the view, and so does a trashed item, which the
// batch query leaves out.
func (l *Grants) contentAllows(ctx context.Context, uc *UserCtx, verdicts map[model.PID]bool, it *model.ItemView) bool {
	if verdicts != nil && it.Kind != model.KindEpisode && !archived(it) {
		return verdicts[it.PID]
	}
	return l.allowedByContent(ctx, uc, it)
}

// VisibleItem verifies the caller can see the item (play-info calls it
// before minting stream URLs).
func (l *Grants) VisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) error {
	_, err := l.getVisibleItem(ctx, uc, apiItemPID)
	return err
}

// VisibleBook is VisibleItem answering, off the same read, whether the
// item is a book, the one kind that can lay out in parts: a caller about
// to ask for a book's layout asks nothing of anything else. The kind is
// the catalog's, never the pid's prefix, since a track's pid names the
// book it became.
func (l *Grants) VisibleBook(ctx context.Context, uc *UserCtx, apiItemPID string) (bool, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return false, err
	}
	return it.Kind == model.KindBook, nil
}

// grantEpoch reads the user's current visibility epoch (0 until ever
// bumped).
func (l *Grants) grantEpoch(ctx context.Context, userID string) (int64, error) {
	return l.Identity.epoch(ctx, syncKeyGrantEpoch+userID)
}

// bumpGrantEpoch retires the user's outstanding catalog cursors after a
// visibility change; their next delta answers sync-reset and the
// re-snapshot reflects the new grants.
func (l *Grants) bumpGrantEpoch(ctx context.Context, userID string) {
	l.Identity.bumpEpoch(ctx, syncKeyGrantEpoch+userID)
}

// UserCtxByID rebuilds a user context from a bare user id, for the paths
// that carry ids rather than principals: the connect core, a media
// capability, a share, a queued task. It refuses a disabled or pending
// account as if it did not exist: every caller acts for an account that
// has to be able to sign in. A read that failed is not an answer, so it
// stays an internal error.
func (l *Grants) UserCtxByID(ctx context.Context, userID string) (*UserCtx, error) {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil && !errors.Is(err, wdb.ErrNotFound) {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u == nil || u.Disabled || u.Pending {
		return nil, errNotFound("no such user")
	}
	return l.UserCtx(ctx, u)
}
