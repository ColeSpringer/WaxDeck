package service

import (
	"context"
	"os"
	"path/filepath"

	"github.com/colespringer/waxbin/model"
)

// TrashEntryDTO is one deletion undo-journal row for the admin surface.
type TrashEntryDTO struct {
	ID          string
	ItemPID     string
	Name        string
	Reason      string
	SizeBytes   int64
	TrashedAtNS int64
	RestoredNS  int64
}

// TrashEmptyDTO reports an empty-trash pass.
type TrashEmptyDTO struct {
	Purged         int
	Errored        int
	ReclaimedBytes int64
}

// TrashEntries lists the catalog trash, newest first. Administrators
// only (the journal spans every library).
func (l *Library) TrashEntries(ctx context.Context, uc *UserCtx, includeRestored bool, limit int) ([]TrashEntryDTO, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	entries, err := l.lib.Trash(ctx, includeRestored, limit)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]TrashEntryDTO, 0, len(entries))
	for _, e := range entries {
		dto := TrashEntryDTO{
			ID:          apiPID(PrefixTrash, e.PID),
			Name:        e.OrigDisplay,
			Reason:      e.Reason,
			SizeBytes:   e.Size,
			TrashedAtNS: e.TrashedAt,
			RestoredNS:  e.RestoredAt,
		}
		if string(e.ItemPID) != "" {
			// The trashed file's item kind is not journaled; resolve it
			// for a correct API prefix, falling back to the track prefix
			// for items the catalog no longer serves.
			if it, err := l.lib.Get(ctx, e.ItemPID); err == nil {
				dto.ItemPID = itemAPIPID(it)
			} else {
				dto.ItemPID = apiPID(PrefixTrack, e.ItemPID)
			}
		}
		out = append(out, dto)
	}
	return out, nil
}

// RestoreTrashEntry moves a trashed file back and re-catalogs it.
func (l *Library) RestoreTrashEntry(ctx context.Context, uc *UserCtx, apiTrashID string) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiTrashID)
	if !ok || prefix != PrefixTrash {
		return errInvalid("bad trash id " + apiTrashID)
	}
	if err := l.lib.RestoreTrash(ctx, pid); err != nil {
		return classify(err)
	}
	l.Audit(ctx, uc, "trash.restore", AuditTarget{Kind: "trash", PID: apiTrashID}, nil)
	return nil
}

// EmptyTrash permanently purges every active trashed file.
func (l *Library) EmptyTrash(ctx context.Context, uc *UserCtx) (TrashEmptyDTO, error) {
	if !uc.Admin {
		return TrashEmptyDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	rep, err := l.lib.EmptyTrash(ctx)
	if err != nil {
		return TrashEmptyDTO{}, classify(err)
	}
	out := TrashEmptyDTO{Purged: rep.Purged, Errored: rep.Errored, ReclaimedBytes: rep.ReclaimedBytes}
	l.Audit(ctx, uc, "trash.empty", AuditTarget{Kind: "trash"},
		map[string]any{"purged": out.Purged, "errored": out.Errored, "reclaimedBytes": out.ReclaimedBytes})
	return out, nil
}

// DeletePlanDTO is one item's share of a deletion.
type DeletePlanDTO struct {
	PID   string
	Name  string
	Files int
	Bytes int64
}

// DeleteItemsResultDTO is the plan (dry run) or the applied outcome.
type DeleteItemsResultDTO struct {
	Applied bool
	Mode    string
	Entries []DeletePlanDTO
}

// DeleteItems deletes items' files, to the trash by default. Callers
// need the delete permission or the admin role; permanent mode is
// admin-only. Every pid must be visible to the caller, and every
// touched library must be writable.
func (l *Library) DeleteItems(ctx context.Context, uc *UserCtx, apiPIDs []string, mode string, dryRun bool) (DeleteItemsResultDTO, error) {
	if !uc.Admin && !uc.Delete {
		return DeleteItemsResultDTO{}, &Error{Kind: KindForbidden, Msg: "this account cannot delete library items"}
	}
	var dm model.DeleteMode
	switch mode {
	case "", "trash":
		dm, mode = model.DeleteTrash, "trash"
	case "permanent":
		if !uc.Admin {
			return DeleteItemsResultDTO{}, &Error{Kind: KindForbidden, Msg: "permanent deletion is administrators only"}
		}
		dm = model.DeletePermanent
	default:
		return DeleteItemsResultDTO{}, errInvalid("mode must be trash or permanent")
	}
	if len(apiPIDs) == 0 {
		return DeleteItemsResultDTO{}, errInvalid("pids are required")
	}
	if len(apiPIDs) > 500 {
		return DeleteItemsResultDTO{}, errInvalid("at most 500 pids per call")
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	names := map[string]string{}
	apiByBare := map[string]string{}
	for _, p := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, p)
		if err != nil {
			return DeleteItemsResultDTO{}, err
		}
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return DeleteItemsResultDTO{}, err
		}
		pids = append(pids, it.PID)
		names[string(it.PID)] = it.Title
		apiByBare[string(it.PID)] = p
	}
	plan, err := l.lib.PlanDeletePIDs(ctx, pids, dm)
	if err != nil {
		return DeleteItemsResultDTO{}, classify(err)
	}
	// The plan is per file; the API reports per item.
	perItem := map[string]*DeletePlanDTO{}
	order := []string{}
	for _, a := range plan.Actions {
		if a.Skip {
			continue
		}
		bare := string(a.ItemPID)
		dto, ok := perItem[bare]
		if !ok {
			dto = &DeletePlanDTO{PID: apiByBare[bare], Name: names[bare]}
			if dto.Name == "" {
				dto.Name = filepath.Base(a.Src)
			}
			perItem[bare] = dto
			order = append(order, bare)
		}
		dto.Files++
		if st, err := os.Stat(a.Src); err == nil {
			dto.Bytes += st.Size()
		}
	}
	out := DeleteItemsResultDTO{Mode: mode}
	for _, bare := range order {
		out.Entries = append(out.Entries, *perItem[bare])
	}
	if dryRun {
		return out, nil
	}
	if _, err := l.lib.ApplyDelete(ctx, plan); err != nil {
		return DeleteItemsResultDTO{}, classify(err)
	}
	out.Applied = true
	l.Audit(ctx, uc, "items.delete", AuditTarget{Kind: "item"},
		map[string]any{"mode": mode, "count": len(out.Entries), "pids": apiPIDs})
	return out, nil
}
