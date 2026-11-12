package service

import (
	"context"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// EditItemMetadata applies scalar field edits to one item's catalog
// row, optionally mirroring them into the backing file's tags.
func (l *Editor) EditItemMetadata(ctx context.Context, uc *UserCtx, apiPID string, fields map[string]string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateFieldEdits(it, fields, p.WriteBack); err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	err = l.lib.EditFields(ctx, it.PID, fields, waxbin.EditOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	return editOutcomeFromWriteBack(err)
}

// BulkEditMetadata applies the same scalar edits to many items in one
// atomic catalog batch. With skipLocked, items whose target fields are
// locked are reported instead of failing the batch; write-back failures
// are per item and never undo the catalog batch.
func (l *Editor) BulkEditMetadata(ctx context.Context, uc *UserCtx, apiPIDs []string, fields map[string]string, writeBack, skipLocked, force bool) (BulkEditOutcomeDTO, error) {
	if len(apiPIDs) == 0 {
		return BulkEditOutcomeDTO{}, errInvalid("at least one item is required")
	}
	if len(apiPIDs) > 1000 {
		return BulkEditOutcomeDTO{}, errInvalid("at most 1000 items per bulk edit")
	}
	if skipLocked && force {
		return BulkEditOutcomeDTO{}, errInvalid("skipLocked and force are mutually exclusive")
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	apiByBare := make(map[model.PID]string, len(apiPIDs))
	for _, apiPID := range apiPIDs {
		it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			return BulkEditOutcomeDTO{}, err
		}
		if err := validateFieldEdits(it, fields, writeBack); err != nil {
			return BulkEditOutcomeDTO{}, err
		}
		if writeBack {
			if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
				return BulkEditOutcomeDTO{}, err
			}
		}
		if _, seen := apiByBare[it.PID]; seen {
			continue
		}
		pids = append(pids, it.PID)
		apiByBare[it.PID] = apiPID
	}
	res, err := l.lib.EditManyFields(ctx, pids, fields, waxbin.EditOptions{
		WriteBack: writeBack, Force: force, SkipLocked: skipLocked,
		Lock: model.LockOn,
	})
	if err != nil {
		return BulkEditOutcomeDTO{}, classify(err)
	}
	out := BulkEditOutcomeDTO{Edited: []string{}, Skipped: []string{}}
	for _, pid := range res.Edited {
		out.Edited = append(out.Edited, apiByBare[pid])
	}
	for _, pid := range res.Skipped {
		out.Skipped = append(out.Skipped, apiByBare[pid])
	}
	for _, wbe := range res.WriteBackErrors {
		out.Failures = append(out.Failures, writeBackFailures(wbe)...)
	}
	out.ResultingAlbumPID = l.resultingAlbum(ctx, fields, res.Edited)
	return out, nil
}

// resultingAlbum reports the one album the edited items landed on after
// an edit that rewrote a release-keying field. WaxBin re-resolves
// entities inside the edit transaction and the album key is built from
// the normalized album/album-artist names and the folder (a year keys
// nothing: the album's follows its tracks), but a rename pre-pass runs
// first: a batch covering every member of the album rewrites the entity
// in place and the pid stands, while a partial batch forks the edited
// members onto a fresh al- pid
// (TestBulkEditAlbumFieldsRenamesInPlaceOnFullCoverage and
// ...RegroupsOnPartialCoverage pin the two). Either way the caller who
// asked for the rename needs to know where its tracks are. Empty when
// no keying field was edited, when nothing was edited, or when the
// edited items split across releases (folder is part of the key, so a
// batch spanning directories can).
func (l *Editor) resultingAlbum(ctx context.Context, fields map[string]string, edited []model.PID) string {
	keyed := false
	for _, field := range []string{"album", "album_artist"} {
		if _, ok := fields[field]; ok {
			keyed = true
			break
		}
	}
	if !keyed || len(edited) == 0 {
		return ""
	}
	// One batch read, not a point read per item: this runs on the
	// request path after the edit already read every item once.
	views, err := l.lib.GetMany(ctx, edited)
	if err != nil || len(views) != len(edited) {
		// Absent reads as "no regroup" to the caller, so a failed
		// resolve is at least on record.
		l.log.Warn("bulk edit could not resolve the resulting album", "err", err)
		return ""
	}
	album := model.PID("")
	for i, it := range views {
		if it.AlbumPID == "" {
			return ""
		}
		if i == 0 {
			album = it.AlbumPID
			continue
		}
		if it.AlbumPID != album {
			return ""
		}
	}
	return entityAPIPID(PrefixAlbum, album)
}
