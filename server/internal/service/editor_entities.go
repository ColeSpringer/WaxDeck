package service

import (
	"context"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// EditEntity applies curation edits to a shared artist, release group,
// or album; genre entities support artwork only.
func (l *Editor) EditEntity(ctx context.Context, entityType, apiEntityPID string, edits map[string]string, p MetadataEditParams) (EditOutcomeDTO, error) {
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if !model.EntityEditable(et) {
		return EditOutcomeDTO{}, errInvalid("genre entities support artwork only; they carry no editable fields")
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if len(edits) == 0 {
		return EditOutcomeDTO{}, errInvalid("at least one field edit is required")
	}
	for name, value := range edits {
		if !model.IsEntityEditField(et, name) {
			return EditOutcomeDTO{}, errInvalid("field " + name + " is not editable on a " + entityType + " entity")
		}
		if err := validateIdentifierField(name, value); err != nil {
			return EditOutcomeDTO{}, err
		}
		if name == "type" && value != "" && !model.ValidReleaseGroupType(value) {
			return EditOutcomeDTO{}, errInvalid("type is not a recognized release-group type: " + value)
		}
	}
	if p.WriteBack {
		if err := l.Settings.CheckWritable(ctx, ""); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	rep, err := l.lib.EditEntity(ctx, et, pid, edits, waxbin.EntityEditOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	out, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return EditOutcomeDTO{}, entityMiss(err, entityType, apiEntityPID)
	}
	// The report survives a write-back error: the catalog re-key
	// committed, so a caller still following the old pid needs the
	// survivor even when the member files went unwritten.
	if rep != nil {
		out.MergedInto = entityAPIPID(entityPrefixForType(entityType), rep.MergedInto)
		for _, moved := range rep.MovedAlbums {
			out.MovedAlbums = append(out.MovedAlbums, apiPID(PrefixAlbum, moved))
		}
	}
	return out, nil
}

// EntityRenameOutcomeDTO reports what an entity rename did.
type EntityRenameOutcomeDTO struct {
	EntityPID   string
	Outcome     string
	MergedInto  string
	MovedAlbums []string
	Members     int
	Credits     int
	Failures    []WriteBackFailureDTO
}

// RenameEntity moves a whole album, release group, or artist onto new
// keying values, keeping the row. Upstream owns the field vocabulary
// and every refusal that guards coverage (an empty name, a locked or
// archived member, members that would land apart), so this validates
// only what it knows first: that the entity type has keying fields at
// all, and that the pid parses.
//
// The rename is the entity-rung answer to a bulk item edit, which moves
// only the members it covers and leaves the rest behind on the old key.
func (l *Editor) RenameEntity(ctx context.Context, entityType, apiEntityPID string, fields map[string]string, p MetadataEditParams) (EntityRenameOutcomeDTO, error) {
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return EntityRenameOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if !model.EntityRenamable(et) {
		return EntityRenameOutcomeDTO{}, errInvalid(entityType + " entities carry no keying fields to rename")
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EntityRenameOutcomeDTO{}, err
	}
	if len(fields) == 0 {
		return EntityRenameOutcomeDTO{}, errInvalid("at least one field is required")
	}
	// The catalog refuses it too, in words naming its own vocabulary;
	// this one says where a year is edited.
	if _, ok := fields["year"]; ok && (et == model.MergeAlbum || et == model.MergeReleaseGroup) {
		return EntityRenameOutcomeDTO{}, errInvalid("an album's year follows its tracks rather than keying it; edit the tracks' year instead")
	}
	if p.WriteBack {
		if err := l.Settings.CheckWritable(ctx, ""); err != nil {
			return EntityRenameOutcomeDTO{}, err
		}
	}
	rep, err := l.lib.RenameEntity(ctx, et, pid, fields, waxbin.RenameOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	// A write-back failure leaves the rename standing, so the report is
	// still the answer and the failed files ride along in it.
	out, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return EntityRenameOutcomeDTO{}, entityMiss(err, entityType, apiEntityPID)
	}
	if rep == nil {
		return EntityRenameOutcomeDTO{}, &Error{Kind: KindInternal, Msg: "the rename committed without reporting what it did"}
	}
	prefix := entityPrefixForType(entityType)
	res := EntityRenameOutcomeDTO{
		EntityPID:  apiPID(prefix, rep.EntityPID),
		Outcome:    string(rep.Outcome),
		MergedInto: entityAPIPID(prefix, rep.MergedInto),
		Members:    rep.Members,
		Credits:    rep.Credits,
		Failures:   out.Failures,
	}
	for _, moved := range rep.MovedAlbums {
		res.MovedAlbums = append(res.MovedAlbums, apiPID(PrefixAlbum, moved))
	}
	return res, nil
}

// EntityCurationFor reads an entity's curated fields with provenance,
// behind the gate the entity's detail keeps (entityReached).
func (l *Editor) EntityCurationFor(ctx context.Context, uc *UserCtx, entityType, apiEntityPID string) ([]EntityCuratedFieldDTO, error) {
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return nil, errInvalid("unknown entity type " + entityType)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return nil, err
	}
	if reached, err := l.Reads.entityReached(ctx, uc, et, pid); err != nil {
		return nil, err
	} else if !reached {
		return nil, errNotFound("no " + entityType + " with pid " + apiEntityPID)
	}
	rows, err := l.lib.EntityCuration(ctx, et, pid)
	if err != nil {
		return nil, entityMiss(classify(err), entityType, apiEntityPID)
	}
	out := make([]EntityCuratedFieldDTO, 0, len(rows))
	for _, r := range rows {
		dto := EntityCuratedFieldDTO{
			Field: r.Field, Value: r.Value, Source: string(r.Source), Locked: r.Locked,
		}
		if r.UpdatedAt > 0 {
			dto.UpdatedAt = time.Unix(0, r.UpdatedAt).UTC()
		}
		out = append(out, dto)
	}
	return out, nil
}

// DetachOutcomeDTO reports where a detached track came from and where
// it landed.
type DetachOutcomeDTO struct {
	ItemPID            string
	OldAlbumPID        string
	NewAlbumPID        string
	NewReleaseGroupPID string
	Failures           []WriteBackFailureDTO
}

// DetachItem pulls one track off an mbid-pinned album chain and onto
// the heuristic one its own tags imply. Every refusal is upstream's -
// a non-track, a track on no album, a chain with no MusicBrainz id, an
// album's last member - and each arrives as a sentence worth passing
// through, so nothing is re-checked here.
func (l *Editor) DetachItem(ctx context.Context, uc *UserCtx, apiPID string, writeBack bool) (DetachOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return DetachOutcomeDTO{}, err
	}
	if writeBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return DetachOutcomeDTO{}, err
		}
	}
	rep, err := l.lib.Detach(ctx, it.PID, waxbin.DetachOptions{WriteBack: writeBack})
	// A write-back failure leaves the detach standing, so the report is
	// still the answer and the failed file rides along in it.
	out, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return DetachOutcomeDTO{}, err
	}
	if rep == nil {
		return DetachOutcomeDTO{}, &Error{Kind: KindInternal, Msg: "the detach committed without reporting what it did"}
	}
	return DetachOutcomeDTO{
		ItemPID:            apiPID,
		OldAlbumPID:        entityAPIPID(PrefixAlbum, rep.OldAlbumPID),
		NewAlbumPID:        entityAPIPID(PrefixAlbum, rep.NewAlbumPID),
		NewReleaseGroupPID: entityAPIPID(PrefixReleaseGroup, rep.NewReleaseGroupPID),
		Failures:           out.Failures,
	}, nil
}
