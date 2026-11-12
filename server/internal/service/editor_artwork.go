package service

import (
	"context"

	"github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
)

// validateArtworkBytes enforces the size cap and that the body is a
// picture the catalog can recognize.
//
// The recognizer is the store's own: art.Describe decodes what there is
// a decoder for - JPEG, PNG, GIF, WebP, BMP, TIFF - and magic-sniffs the
// exotic ISOBMFF containers (AVIF, HEIC) it cannot decode, which is
// exactly the set the store will hold. Asking it here rather than
// letting the store refuse further in keeps a refusal a 415 with a
// sentence instead of a write that fails halfway, and it is the one
// check that cannot be talked out of: the store falls back to a
// caller-named format for bytes it does not recognize, so an nginx error
// page named as a TIFF would otherwise be stored as somebody's cover and
// embedded into every backing file behind it.
func validateArtworkBytes(raw []byte) error {
	if len(raw) == 0 {
		return errInvalid("an image body is required")
	}
	if len(raw) > maxArtworkBytes {
		return errInvalid("artwork is limited to 16 MiB")
	}
	if _, _, _, err := waxart.Probe(raw); err != nil {
		if _, ok := waxart.SniffExotic(raw); !ok {
			return &Error{Kind: KindFormat, Msg: "the body is not a recognized image"}
		}
	}
	return nil
}

// SetItemArtwork stores raw image bytes as the item's front cover.
// Force is implied on the catalog write: the caller chose the image, so
// an existing lock (set by an earlier artwork edit) never blocks the
// replacement, per the spec's no-silent-downgrade wording.
func (l *Editor) SetItemArtwork(ctx context.Context, uc *UserCtx, apiPID, role string, raw []byte, writeBack, lock bool) (EditOutcomeDTO, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown art role " + role)
	}
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Write-back embeds a front cover into the backing files; the auxiliary
	// slots are catalog-only, so a write-back request on one is ignored.
	writeBack = writeBack && art == model.ArtRoleFront
	if writeBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	out, err := editOutcomeFromWriteBack(l.lib.SetItemArt(ctx, it.PID, art, raw, waxbin.ArtEditOptions{
		WriteBack: writeBack, Lock: model.LockOf(lock), Force: true,
	}))
	if err == nil {
		// The catalog write committed (a write-back failure rides the
		// outcome, not the error). A generated playlist cover may have been
		// built from this item's old art, and a replacement in place moves
		// no membership, so the epoch is what tells those covers to rebuild.
		l.Playlists.noteArtworkChanged(ctx)
	}
	return out, err
}

// ClearItemArtwork removes the stored item art in one slot. A cleared front
// cover falls back to the entity chain; the other slots have no fallback.
// Files are untouched.
func (l *Editor) ClearItemArtwork(ctx context.Context, uc *UserCtx, apiPID, role string) error {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return errInvalid("unknown art role " + role)
	}
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	// The pin is left exactly as it stands, for the reason ClearEntityArtwork
	// leaves it: clearing says "there is no cover", not "refill this". Force
	// is what lets the clear through a pinned slot, which is the one action
	// the artwork manager offers there.
	if err := l.lib.SetItemArt(ctx, it.PID, art, nil, waxbin.ArtEditOptions{
		Lock: model.LockUnchanged, Force: true,
	}); err != nil {
		return classify(err)
	}
	l.Playlists.noteArtworkChanged(ctx)
	return nil
}

// ArtworkLockDTO is one artwork slot's two pins: the effective lock,
// and the slot's own. They differ only on an auxiliary role, where a
// standing whole-artwork pin holds a slot whose own pin is clear -
// which is what a per-role pin control has to know before it draws a
// toggle that would change nothing.
type ArtworkLockDTO struct {
	Locked     bool
	RoleLocked bool
}

// EntityArtworkLock reports how an entity's slot in one role is pinned;
// an empty role reads the front cover. It is what explains an entity
// that shows no cover and refuses every attempt to give it one: the
// cover was cleared and the pin left standing, which is the one artwork
// state nothing else surfaces.
//
// Both bits come from one ArtRoles read rather than from ArtLocked,
// which answers the effective lock alone. The catalog synthesizes a row
// for a pin with no image behind it - the whole-entity pin as a front
// row, a role's own pin as its own row - so the requested role's row
// carries both values whenever either pin is set. No row for the role
// means its own pin is clear, and the effective lock is then whatever
// the front row's own pin says, since that is the whole-artwork pin
// reaching across; no front row either means nothing is pinned at all.
func (l *Editor) EntityArtworkLock(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string) (ArtworkLockDTO, error) {
	ent, pid, artRole, err := lockableArtSlot(entityType, apiEntityPID, role)
	if err != nil {
		return ArtworkLockDTO{}, err
	}
	if err := l.showArtworkReached(ctx, uc, ent, pid, apiEntityPID); err != nil {
		return ArtworkLockDTO{}, err
	}
	locked, err := l.artworkLockFor(ctx, ent, pid, artRole)
	return locked, entityMiss(err, entityType, apiEntityPID)
}

// showArtworkReached refuses a show's artwork to a caller the show's
// detail does not answer (showReached), with the not-found every show
// read answers: managing podcasts is no reach of its own.
func (l *Editor) showArtworkReached(ctx context.Context, uc *UserCtx, ent model.ArtEntity, pid model.PID, apiEntityPID string) error {
	if ent != model.ArtPodcast {
		return nil
	}
	reached, err := l.Podcasts.showReached(ctx, uc, pid)
	if err != nil {
		return err
	}
	if !reached {
		return errNotFound("no podcast with pid " + apiEntityPID)
	}
	return nil
}

// artworkLockFor reads one slot's two pins from the entity's role list.
func (l *Editor) artworkLockFor(ctx context.Context, ent model.ArtEntity, pid model.PID, role model.ArtRole) (ArtworkLockDTO, error) {
	infos, err := l.lib.ArtRoles(ctx, model.EntityRef{Type: ent, PID: pid})
	if err != nil {
		return ArtworkLockDTO{}, classify(err)
	}
	var out ArtworkLockDTO
	for _, i := range infos {
		switch i.Role {
		case role:
			return ArtworkLockDTO{Locked: i.Locked, RoleLocked: i.RoleLocked}, nil
		case model.ArtRoleFront:
			// The front row's own pin is the whole-artwork pin, which
			// is the only thing that can hold a role with no row.
			out.Locked = i.RoleLocked
		}
	}
	return out, nil
}

// SetEntityArtworkLock pins or unpins one of an entity's artwork slots
// without touching the image, which setting artwork cannot express:
// that always writes the image slot too. Unpinning here is the way out
// of a cover that was cleared and left pinned. An empty role writes the
// front cover's pin, which also gates enrichment's fills in every other
// role; a named role writes that slot's own pin alone.
func (l *Editor) SetEntityArtworkLock(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string, lock bool) (ArtworkLockDTO, error) {
	ent, pid, artRole, err := lockableArtSlot(entityType, apiEntityPID, role)
	if err != nil {
		return ArtworkLockDTO{}, err
	}
	if err := l.showArtworkReached(ctx, uc, ent, pid, apiEntityPID); err != nil {
		return ArtworkLockDTO{}, err
	}
	was, err := l.lib.ArtLocked(ctx, ent, pid, artRole)
	if err != nil {
		return ArtworkLockDTO{}, entityMiss(classify(err), entityType, apiEntityPID)
	}
	// The write reports the effective lock after it, so the response
	// does not have to be a second read. That distinction matters on an
	// auxiliary role: unpinning one slot under a standing whole-artwork
	// pin leaves it locked, and answering "false" would have the caller
	// record a slot as open while enrichment is still held off it - the
	// read endpoint would then contradict the write. RoleLocked is the
	// requested value, since the write set exactly that pin.
	change, err := l.lib.SetArtLock(ctx, ent, pid, artRole, lock)
	if err != nil {
		return ArtworkLockDTO{}, entityMiss(classify(err), entityType, apiEntityPID)
	}
	// Only on a change, and on a change in the effective lock, which is
	// what both comparands are. The artwork epoch is what tells every
	// generated playlist cover to re-composite, and a pin moves no
	// bytes: bumping it for a lock that reads the same either side
	// would rebuild every mosaic in the library to record nothing.
	if was != change.StillLocked {
		l.Playlists.noteArtworkChanged(ctx)
	}
	return ArtworkLockDTO{Locked: change.StillLocked, RoleLocked: lock}, nil
}

// lockableArtSlot resolves an entity type, pid and art role for the pin
// surface. The role is the wire spelling, where empty means the front
// cover; anything outside the closed vocabulary is a refusal rather
// than a silent fall back to the front, which would pin the wrong slot.
func lockableArtSlot(entityType, apiEntityPID, role string) (model.ArtEntity, model.PID, model.ArtRole, error) {
	ent, pid, err := lockableArtEntity(entityType, apiEntityPID)
	if err != nil {
		return "", "", "", err
	}
	artRole, ok := model.ParseArtRole(role)
	if !ok {
		return "", "", "", errInvalid("unknown artwork role " + role)
	}
	return ent, pid, artRole, nil
}

// lockableArtEntity resolves an entity type and pid for the pin surface,
// refusing playlists.
//
// The refusal is structural rather than a matter of the three playlist
// art call sites agreeing forever. A playlist's cover authority is its
// own custom/generated origin marker; a pin standing on one makes the
// mosaic unwritable, and clearPlaylistArtwork deletes the origin marker
// before clearing the art, so the next read composites, is refused, and
// returns before recording the fingerprint. Every later read then
// re-resolves every member, composites again, and is refused again -
// permanently, on the read path.
func lockableArtEntity(entityType, apiEntityPID string) (model.ArtEntity, model.PID, error) {
	ent, ok := artEntityForType(entityType)
	if !ok {
		return "", "", errInvalid("unknown entity type " + entityType)
	}
	if ent == model.ArtPlaylist {
		return "", "", errInvalid("a playlist cover has no pin; clearing one hands the slot back to the generated mosaic")
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return "", "", err
	}
	return ent, pid, nil
}

// artEntityForType maps an API entity type to the art entity vocabulary.
func artEntityForType(entityType string) (model.ArtEntity, bool) {
	switch entityType {
	case "album":
		return model.ArtAlbum, true
	case "artist":
		return model.ArtArtist, true
	case "release-group":
		return model.ArtReleaseGroup, true
	case "genre":
		return model.ArtGenre, true
	case "playlist":
		return model.ArtPlaylist, true
	case "podcast":
		return model.ArtPodcast, true
	default:
		return "", false
	}
}

// EntityArtworkOwned reports whether an entity type's artwork belongs to
// a user rather than to the catalog. A playlist cover is the owner's;
// every catalog entity is administrators-only, which is what the API
// layer checks before it gets here.
func EntityArtworkOwned(entityType string) bool { return entityType == "playlist" }

// mergeEntityForType maps an API entity type to the curation entity
// vocabulary.
func mergeEntityForType(entityType string) (model.MergeEntity, bool) {
	switch entityType {
	case "album":
		return model.MergeAlbum, true
	case "artist":
		return model.MergeArtist, true
	case "release-group":
		return model.MergeReleaseGroup, true
	case "genre":
		return model.MergeGenre, true
	case "series":
		return model.MergeSeries, true
	default:
		return "", false
	}
}

// entityPrefixForType is the API pid prefix an entity type's own pids
// carry. It answers the entity types an edit or a rename accepts; a
// genre has no pid prefix of its own and neither verb reaches one.
func entityPrefixForType(entityType string) string {
	switch entityType {
	case "album":
		return PrefixAlbum
	case "artist":
		return PrefixArtist
	case "release-group":
		return PrefixReleaseGroup
	default:
		return ""
	}
}

// editorEntityPID parses an entity's API pid. Albums, artists, and
// podcasts carry established prefixes and are checked against them
// (podcasts enforced from the start: the type is new, so no client
// holds an unprefixed pid for one). Release groups mint `rg-` on reads
// now, but this stays permissive for them and for genres: both have
// accepted any well-formed prefix since before the read existed, and
// tightening it would refuse pids clients already hold.
func editorEntityPID(entityType, apiEntityPID string) (model.PID, error) {
	prefix, pid, ok := parseAPIPID(apiEntityPID)
	if !ok {
		return "", errNotFound("no " + entityType + " with pid " + apiEntityPID)
	}
	switch entityType {
	case "album":
		if prefix != PrefixAlbum {
			return "", errNotFound("no album with pid " + apiEntityPID)
		}
	case "artist":
		if prefix != PrefixArtist {
			return "", errNotFound("no artist with pid " + apiEntityPID)
		}
	case "podcast":
		if prefix != PrefixPodcast {
			return "", errNotFound("no podcast with pid " + apiEntityPID)
		}
	}
	return pid, nil
}

// entityMiss words a not-found from an entity route's own reads and
// writes as the route names the entity, passing any other error through.
func entityMiss(err error, entityType, apiEntityPID string) error {
	if KindOf(err) == KindNotFound {
		return errNotFound("no " + entityType + " with pid " + apiEntityPID)
	}
	return err
}

// SetEntityArtwork stores durable front-cover art on an entity. Albums
// may fan the cover into member files with writeBack; other entity
// types are catalog-only (the facade treats their write-back as a
// no-op). A playlist takes its owner's cover here, over the one the
// server generates from its members.
func (l *Editor) SetEntityArtwork(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string, raw []byte, writeBack bool) (EditOutcomeDTO, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown art role " + role)
	}
	ent, ok := artEntityForType(entityType)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	if ent == model.ArtPlaylist {
		out, err := l.setPlaylistArtwork(ctx, uc, apiEntityPID, art, raw)
		return out, entityMiss(err, entityType, apiEntityPID)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := l.showArtworkReached(ctx, uc, ent, pid, apiEntityPID); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Only a front cover fans into member files; the auxiliary slots are
	// catalog-only.
	writeBack = writeBack && art == model.ArtRoleFront
	if writeBack {
		if err := l.Settings.CheckWritable(ctx, ""); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	// Pin it, and override whatever pin stood before. The caller chose
	// this image, which is the same rule the item path states, and the
	// pin is what carries it through an enrichment run that would
	// otherwise refill the slot from a provider.
	out, err := editOutcomeFromWriteBack(l.lib.SetEntityArt(ctx, ent, pid, art, raw, waxbin.ArtEditOptions{
		WriteBack: writeBack, Lock: model.LockOn, Force: true,
	}))
	if err == nil {
		// An album or artist cover is what a member track resolves when it
		// carries none of its own, so this moves playlist covers too.
		l.Playlists.noteArtworkChanged(ctx)
	}
	return out, entityMiss(err, entityType, apiEntityPID)
}

// ClearEntityArtwork removes one artwork slot from an entity. Files
// already carrying an embedded cover keep it; this clears the catalog's
// copy. Clearing a playlist's uploaded cover hands the slot back to the
// generated mosaic rather than leaving the playlist bare.
func (l *Editor) ClearEntityArtwork(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string) error {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return errInvalid("unknown art role " + role)
	}
	ent, ok := artEntityForType(entityType)
	if !ok {
		return errInvalid("unknown entity type " + entityType)
	}
	if ent == model.ArtPlaylist {
		return entityMiss(l.clearPlaylistArtwork(ctx, uc, apiEntityPID, art), entityType, apiEntityPID)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return err
	}
	if err := l.showArtworkReached(ctx, uc, ent, pid, apiEntityPID); err != nil {
		return err
	}
	// No write-back on a clear: a cover already embedded in a file is the
	// file's, and stripping it is the organizer's business, not this
	// endpoint's.
	//
	// The pin is left exactly as it stands rather than dropped. Clearing a
	// catalog entity's cover says "there is no cover", not "give me the
	// default back", so a cleared-and-pinned cover is a real intent - do not
	// refill this - and it is a state ArtRoles reports and the lock endpoint
	// below can undo. Force skips the lock check and nothing else, so the
	// clear goes through a pinned slot without rewriting the pin.
	if err := l.lib.SetEntityArt(ctx, ent, pid, art, nil, waxbin.ArtEditOptions{
		Lock: model.LockUnchanged, Force: true,
	}); err != nil {
		return entityMiss(classify(err), entityType, apiEntityPID)
	}
	l.Playlists.noteArtworkChanged(ctx)
	return nil
}

// setPlaylistArtwork stores an owner's cover and records it as custom,
// so the member-derived mosaic stops overwriting it.
func (l *Editor) setPlaylistArtwork(ctx context.Context, uc *UserCtx, apiPlaylistPID string, role model.ArtRole, raw []byte) (EditOutcomeDTO, error) {
	pl, err := l.Playlists.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	// Claim the slot before storing the image, and fail the request if the
	// claim cannot be recorded. Both halves matter: with the image first,
	// a concurrent playlist read regenerates the mosaic over the upload in
	// the window between them, and with a best-effort claim the endpoint
	// answers 200 while the next read overwrites what the user just
	// uploaded. Only the front cover is the playlist's face; an auxiliary
	// slot does not displace the generated one.
	var undoClaim func()
	if role == model.ArtRoleFront {
		undo, err := l.Playlists.claimPlaylistCoverCustom(ctx, pl.PID)
		if err != nil {
			return EditOutcomeDTO{}, classify(err)
		}
		undoClaim = undo
	}
	// A playlist has no files to write a cover back into: it is a
	// terminal art level with no ancestry and no members of its own.
	//
	// Never pinned, here or in the two paths below. A playlist's cover
	// authority is WaxDeck's own playlist_cover origin marker, which
	// claimPlaylistCoverCustom just set; a pin would additionally make
	// the generated mosaic unwritable, and the generator retries on
	// every read.
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, role, raw, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true,
	}); err != nil {
		if undoClaim != nil {
			// Nothing was stored, so the claim has to go back the way it was
			// or the next read leaves the previous cover in place while
			// believing it is a custom one.
			undoClaim()
		}
		return EditOutcomeDTO{}, classify(err)
	}
	return EditOutcomeDTO{}, nil
}

// clearPlaylistArtwork drops an owner's cover and rebuilds the mosaic
// in its place, so clearing gives the default back rather than nothing.
func (l *Editor) clearPlaylistArtwork(ctx context.Context, uc *UserCtx, apiPlaylistPID string, role model.ArtRole) error {
	pl, err := l.Playlists.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	// Drop the provenance before the art, and fail on it. The other order
	// leaves the playlist bare with a custom marker on it, which no later
	// read repairs: the marker is exactly what stops regeneration.
	if role == model.ArtRoleFront {
		if err := l.db.DeletePlaylistCover(ctx, string(pl.PID)); err != nil {
			return classify(err)
		}
		pl.HasArt = false
	}
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, role, nil, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true,
	}); err != nil {
		return classify(err)
	}
	if role == model.ArtRoleFront {
		l.Playlists.refreshPlaylistCover(ctx, pl)
	}
	return nil
}

// bookOnlyHint ends a refusal of a book's own field or role on a track
// with the way a track becomes a book, which editing never is.
func bookOnlyHint(kind model.Kind, bookOnly bool) string {
	if kind != model.KindTrack || !bookOnly {
		return ""
	}
	return "; a track becomes an audiobook by changing its kind, not by editing this field"
}
