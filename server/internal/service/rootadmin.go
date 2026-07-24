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

// AddLibrary registers a new library root at runtime. It catalogs the root
// through the facade (which validates the path is absolute and does not
// overlap an existing root, the inbox, or the podcast dir), adopts it into
// the service's own root table so the configured name and managed policy
// take effect without a restart, and kicks a background scan. Browsing and
// downloading the new root's files work once the scan indexes them;
// streaming through the WaxFlow sidecar additionally needs the sidecar to
// mount the same-named root. Administrators only.
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
	l.Audit(ctx, uc, "library.create", AuditTarget{Kind: "library", PID: apiLibPID},
		map[string]any{"name": name, "path": path, "media": string(media), "managed": in.Managed})
	return LibraryInfo{PID: apiLibPID, Name: name, Media: string(lib.MediaType())}, nil
}

// registerRoot holds rootsMu across the name-uniqueness check, the facade add,
// and the table append, so two concurrent same-name creates cannot both pass
// the check and both append (the copy-on-write append alone leaves that
// window open). The name is WaxDeck's WaxFlow root-mapping key, so a duplicate
// would make stream-ref resolution ambiguous. AddRoot is a bounded catalog
// write and does not re-enter the service, so holding the lock across it only
// serializes the rare runtime library create.
func (l *Library) registerRoot(ctx context.Context, name, path string, mode model.Mode, media model.MediaType, managed bool) (*model.Library, error) {
	l.rootsMu.Lock()
	defer l.rootsMu.Unlock()
	for _, r := range l.roots {
		if r.Name == name {
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
