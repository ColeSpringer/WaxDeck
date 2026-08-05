package service

import (
	"context"
	"strings"

	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
)

// libraryRoots returns a snapshot of the service's root table. Callers
// range over it without retaining; AddLibrary swaps the slice under
// rootsMu, so a snapshot taken here stays consistent even as a concurrent
// create grows the table.
func (l *Library) libraryRoots() []Root {
	l.rootsMu.RLock()
	defer l.rootsMu.RUnlock()
	return l.roots
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

// SetFlowRoots wires the bridge's runtime-root surface.
func (l *Library) SetFlowRoots(s FlowRootSync) { l.flowRoots = s }

// AddLibrary registers a new library root at runtime. It catalogs the root
// through the facade (which validates the path is absolute and does not
// overlap an existing root, the inbox, or the podcast dir), adopts it into
// the service's own root table so the configured name and managed policy
// take effect without a restart, teaches the streaming sidecar the same
// root, and kicks a background scan. Browsing and downloading the new
// root's files work once the scan indexes them; streaming works as soon as
// the sidecar reconciles, and degrades to needing a sidecar restart when
// it cannot - which the returned StreamingWarning reports. Administrators
// only.
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
	lib, err := l.registerRoot(ctx, name, path, mode, media, in.Managed)
	if err != nil {
		return LibraryInfo{}, err
	}
	// Drop the path-to-library attribution cache so a lookup under the new
	// root resolves immediately instead of waiting for the first miss.
	l.invalidateAttribution()
	streamWarning := l.syncFlowRoot(ctx, name, path)
	// Scan the new root in the background. A scan (or other catalog job)
	// already in flight was snapshotted before this root existed and will not
	// cover it, so on a conflict the root waits for the next scan; log that so
	// the gap is visible rather than silently swallowed.
	if _, err := l.Rescan(ctx); err != nil {
		if KindOf(err) == KindConflict {
			l.log.Warn("library created while a catalog job is running; its root will index on the next scan, or rescan manually",
				"library", name)
		} else {
			l.log.Warn("scan after library create failed", "library", name, "err", err)
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
	return LibraryInfo{
		PID:   apiLibPID,
		Name:  name,
		Media: string(lib.MediaType()),
		Path:  path,
		// The 201 carries it as well as the audit entry now: the
		// administrator who made the change is looking at the response,
		// and asking them to go and read the log for the half that
		// degraded is how a silent partial success happens.
		StreamingWarning: streamWarning,
	}, nil
}

// syncFlowRoot brings the streaming sidecar to the new root. It
// degrades rather than fails: the library is already created, and
// browsing, downloading, and direct playback never depended on the
// sidecar. The returned string is empty when streaming works now, and
// otherwise says what an administrator still has to do.
func (l *Library) syncFlowRoot(ctx context.Context, name, path string) string {
	if l.flowRoots == nil {
		return ""
	}
	err := l.flowRoots.SyncRoot(ctx, name, path)
	if err == nil {
		return ""
	}
	l.log.Warn("the streaming sidecar did not take the new library's root",
		"library", name, "err", err)
	return "streaming from this library is not available yet: " + err.Error()
}

// registerRoot holds rootsMu across the name-uniqueness check, the facade add,
// and the table append, so two concurrent same-name creates cannot both pass
// the check and both append (the copy-on-write append alone leaves that
// window open). The name is WaxDeck's WaxFlow root-mapping key, so a duplicate
// would make stream-ref resolution ambiguous. AddRoot is a bounded catalog
// write and does not re-enter the service, so holding the lock across it only
// serializes the rare runtime library create.
//
// The check covers every name the streaming bridge maps, not only this
// table. The podcast download dir is appended to the bridge separately
// and never enters l.roots, so a library named after it would pass a
// table-only check and then shadow the sidecar's podcast root, which is
// the exact ambiguity this check exists to prevent.
func (l *Library) registerRoot(ctx context.Context, name, path string, mode model.Mode, media model.MediaType, managed bool) (*model.Library, error) {
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	taken := make([]string, 0, len(l.roots)+1)
	for _, r := range l.roots {
		taken = append(taken, r.Name)
	}
	if l.flowRoots != nil {
		taken = append(taken, l.flowRoots.RootNames()...)
	} else if l.podcastRootName != "" {
		// Without a bridge the podcast root has no other registry, but the
		// name is still reserved: a sidecar configured later mounts it.
		taken = append(taken, l.podcastRootName)
	}
	for _, n := range taken {
		if n == name {
			return nil, &Error{Kind: KindConflict, Msg: "a library named " + name + " already exists"}
		}
	}
	lib, err := l.lib.AddRoot(ctx, config.Root{Path: path, Mode: mode, Media: media})
	if err != nil {
		return nil, classify(err)
	}
	// Copy-on-write so a reader ranging over an earlier snapshot never sees a
	// torn append.
	l.roots = append(append([]Root(nil), l.roots...), Root{Name: name, Path: path, Managed: managed})
	return lib, nil
}
