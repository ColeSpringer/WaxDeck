package service

import (
	"context"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/colespringer/waxbin/model"

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
	// have it); UploadQuotaBytes caps live uploads, 0 meaning no cap.
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

// UserCtx assembles the per-request user context from an account row.
func (l *Library) UserCtx(ctx context.Context, u *wdb.User) (*UserCtx, error) {
	uc := &UserCtx{
		ID:               u.ID,
		CatalogPID:       u.WaxbinUserPID,
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

// libraryDirs is the path→library attribution table: every library
// root, longest path first so nested roots (the podcast dir under a
// media mount) attribute to the deepest match.
type libraryDirs struct {
	mu   sync.Mutex
	dirs []libraryDir
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
	l.libDirs.dirs = nil
	l.libDirs.mu.Unlock()
}

// attribution returns the attribution table, loading it on first use.
// forceReload refreshes it (a miss may mean a library appeared since).
func (l *Library) attribution(ctx context.Context, forceReload bool) ([]libraryDir, error) {
	l.libDirs.mu.Lock()
	defer l.libDirs.mu.Unlock()
	if l.libDirs.dirs != nil && !forceReload {
		return l.libDirs.dirs, nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	dirs := make([]libraryDir, 0, len(libs))
	for _, lib := range libs {
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
	l.libDirs.dirs = dirs
	return dirs, nil
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
// whose file cannot be located (a missing or stream-only item)
// fails closed for restricted users.
func (l *Library) itemVisible(ctx context.Context, uc *UserCtx, pid model.PID) bool {
	if uc.AllLibraries {
		return true
	}
	loc, err := l.paths.Locate(ctx, pid)
	if err != nil {
		return false
	}
	libPID, err := l.libraryForPath(ctx, loc.Path)
	if err != nil || libPID == "" {
		return false
	}
	return uc.Libraries[libPID]
}

// viewVisible is itemVisible for callers already holding a fresh item
// view: it attributes the view's own primary path, bypassing the
// located-path cache. The sync paths need this because the cache
// invalidates on a poll, and a delta racing that poll would decide a
// tombstone from a stale path.
func (l *Library) viewVisible(ctx context.Context, uc *UserCtx, it *model.ItemView) bool {
	if uc.AllLibraries {
		return true
	}
	if len(it.Path) == 0 {
		return false
	}
	libPID, err := l.libraryForPath(ctx, string(it.Path))
	if err != nil || libPID == "" {
		return false
	}
	return uc.Libraries[libPID]
}

// podcastsVisible reports whether the caller can see the podcast
// library (shows are not items, so show surfaces gate on the library
// itself). Servers without a podcast dir have nothing to show.
func (l *Library) podcastsVisible(ctx context.Context, uc *UserCtx) bool {
	if uc.AllLibraries {
		return true
	}
	if l.podcastDir == "" {
		return false
	}
	libPID, err := l.libraryForPath(ctx, l.podcastDir)
	if err != nil || libPID == "" {
		return false
	}
	return uc.Libraries[libPID]
}

// getVisibleItem is getItem plus the visibility check: an item outside
// the caller's scope behaves exactly as if it did not exist.
func (l *Library) getVisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) (*model.ItemView, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return nil, err
	}
	if !l.itemVisible(ctx, uc, it.PID) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	if !l.allowedByContent(ctx, uc, it) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	return it, nil
}

// VisibleItem verifies the caller can see the item (play-info calls it
// before minting stream URLs).
func (l *Library) VisibleItem(ctx context.Context, uc *UserCtx, apiItemPID string) error {
	_, err := l.getVisibleItem(ctx, uc, apiItemPID)
	return err
}

// LibraryInfo is one catalog library for the admin surface.
type LibraryInfo struct {
	PID   string
	Name  string
	Media string
}

// Libraries lists the catalog's libraries with their configured root
// names (falling back to the root directory's base name).
func (l *Library) Libraries(ctx context.Context) ([]LibraryInfo, error) {
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	roots := l.libraryRoots()
	byPath := make(map[string]string, len(roots))
	for _, r := range roots {
		byPath[filepath.Clean(r.Path)] = r.Name
	}
	out := make([]LibraryInfo, 0, len(libs))
	for _, lib := range libs {
		name := byPath[filepath.Clean(lib.DisplayRoot)]
		if name == "" {
			name = filepath.Base(lib.DisplayRoot)
		}
		out = append(out, LibraryInfo{
			PID:   apiPID(PrefixLibrary, lib.PID),
			Name:  name,
			Media: string(lib.MediaType()),
		})
	}
	return out, nil
}
