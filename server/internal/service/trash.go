package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/trash"
	"github.com/colespringer/waxbin/waxerr"
)

// TrashEntryDTO is one deletion undo-journal row for the admin surface.
// LibraryPID is the library the file was trashed from, empty when the
// journal names none, and LibraryName its root's name.
type TrashEntryDTO struct {
	ID          string
	ItemPID     string
	Name        string
	Reason      string
	SizeBytes   int64
	TrashedAtNS int64
	RestoredNS  int64
	LibraryPID  string
	LibraryName string
}

// TrashEmptyDTO reports an empty-trash pass; SkippedReadOnly counts the
// entries a read-only library kept.
type TrashEmptyDTO struct {
	Purged          int
	Errored         int
	ReclaimedBytes  int64
	SkippedReadOnly int
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
	names := map[string]string{}
	for _, r := range l.libraryRoots() {
		names[r.PID] = r.Name
	}
	out := make([]TrashEntryDTO, 0, len(entries))
	for _, e := range entries {
		dto := TrashEntryDTO{
			ID:          apiPID(PrefixTrash, e.PID),
			Name:        l.trashEntryName(e),
			Reason:      e.Reason,
			SizeBytes:   e.Size,
			TrashedAtNS: e.TrashedAt,
			RestoredNS:  e.RestoredAt,
		}
		if e.LibraryPID != "" {
			dto.LibraryPID = apiPID(PrefixLibrary, e.LibraryPID)
			dto.LibraryName = names[string(e.LibraryPID)]
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

// trashEntryName is a trashed file's name: its place in its library, as
// the contract says, never the server's folders.
func (l *Library) trashEntryName(e model.TrashEntry) string {
	for _, r := range l.libraryRoots() {
		root := cleanRootPath(r.Path)
		if r.PID != string(e.LibraryPID) || !pathsOverlap(root, e.OrigDisplay) {
			continue
		}
		if rel, err := filepath.Rel(root, e.OrigDisplay); err == nil && rel != "." {
			return filepath.ToSlash(rel)
		}
	}
	// A library the server no longer holds leaves no root to name it
	// against, and its folders are the server's.
	return filepath.Base(e.OrigDisplay)
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
	if err := l.CheckWritable(ctx, ""); err != nil {
		return err
	}
	target, detail := l.trashRestoreAudit(ctx, apiTrashID, pid)
	if err := l.lib.RestoreTrash(ctx, pid); err != nil {
		// A folder that will not take the file back is the library's to
		// fix, as on the way into the trash.
		if cause := l.storageRefused(err.Error()); cause != "" {
			e := errStorageUnwritable(cause)
			e.Err = err
			return e
		}
		return classify(err)
	}
	l.Audit(ctx, uc, "trash.restore", target, detail)
	return nil
}

// EmptyTrash permanently purges every active trashed file.
func (l *Library) EmptyTrash(ctx context.Context, uc *UserCtx) (TrashEmptyDTO, error) {
	if !uc.Admin {
		return TrashEmptyDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return TrashEmptyDTO{}, err
	}
	rep, err := l.lib.EmptyTrash(ctx, waxbin.EmptyTrashOptions{})
	if err != nil {
		return TrashEmptyDTO{}, classify(err)
	}
	out := trashEmptyDTO(rep)
	l.Audit(ctx, uc, "trash.empty", AuditTarget{Kind: "trash"},
		map[string]any{"purged": out.Purged, "errored": out.Errored, "reclaimedBytes": out.ReclaimedBytes,
			"skippedReadOnly": out.SkippedReadOnly})
	l.EmitNotificationFor(ctx, "job-finished", jobTitle("empty-trash", false), trashBody(out), "", []string{uc.ID})
	return out, nil
}

// PurgeTrashEntry permanently purges one trashed file and reports the
// bytes it reclaimed. Administrators only.
func (l *Library) PurgeTrashEntry(ctx context.Context, uc *UserCtx, apiTrashID string) (int64, error) {
	if !uc.Admin {
		return 0, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiTrashID)
	if !ok || prefix != PrefixTrash {
		return 0, errInvalid("bad trash id " + apiTrashID)
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return 0, err
	}
	reclaimed, err := l.lib.PurgeTrash(ctx, pid)
	if err != nil {
		return 0, classify(err)
	}
	l.Audit(ctx, uc, "trash.purge", AuditTarget{Kind: "trash", PID: apiTrashID},
		map[string]any{"reclaimedBytes": reclaimed})
	return reclaimed, nil
}

// PurgeTrashOlderThan purges trashed files trashed longer ago than the
// given age, backing the retention sweeper. A zero or negative age is a
// no-op rather than an empty-everything, so a disabled policy (0 days) or
// a misconfigured caller never wipes the whole undo journal.
func (l *Library) PurgeTrashOlderThan(ctx context.Context, olderThan time.Duration) (TrashEmptyDTO, error) {
	if olderThan <= 0 {
		return TrashEmptyDTO{}, nil
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		if KindOf(err) == KindReadOnly {
			return TrashEmptyDTO{}, nil
		}
		return TrashEmptyDTO{}, err
	}
	rep, err := l.lib.EmptyTrash(ctx, waxbin.EmptyTrashOptions{OlderThan: olderThan})
	if err != nil {
		return TrashEmptyDTO{}, classify(err)
	}
	out := trashEmptyDTO(rep)
	// The retention sweep has no human actor; audit it with a nil actor the
	// way backup retention does, but only when it actually reclaimed
	// something so a routine no-op pass never floods the log.
	if out.Purged > 0 || out.Errored > 0 {
		l.Audit(ctx, nil, "trash.retention", AuditTarget{Kind: "trash"},
			map[string]any{"purged": out.Purged, "errored": out.Errored, "reclaimedBytes": out.ReclaimedBytes})
	}
	return out, nil
}

// SweepTrashRetention runs one retention pass using the configured
// policy. It is the entry point for the supervised background sweeper;
// when retention is disabled (0 days) it purges nothing.
func (l *Library) SweepTrashRetention(ctx context.Context) (TrashEmptyDTO, error) {
	days := l.TrashRetentionDays(ctx)
	if days <= 0 || l.Maintenance() {
		return TrashEmptyDTO{}, nil
	}
	return l.PurgeTrashOlderThan(ctx, time.Duration(days)*24*time.Hour)
}

func trashEmptyDTO(rep *waxbin.EmptyReport) TrashEmptyDTO {
	return TrashEmptyDTO{Purged: rep.Purged, Errored: rep.Errored, ReclaimedBytes: rep.ReclaimedBytes,
		SkippedReadOnly: rep.SkippedReadOnly}
}

// DeletePlanDTO is one item's share of a deletion: the files it loses,
// by name and by path in their library, whether it keeps one, and how
// many of its files a run could not remove and why.
type DeletePlanDTO struct {
	PID          string
	Name         string
	Files        int
	Bytes        int64
	FileList     []DeletePlanFileDTO
	Paths        []string
	ItemSurvives bool
	Failed       int
	Error        string
}

// DeletePlanFileDTO is one file a deletion removes.
type DeletePlanFileDTO struct {
	FilePID   string
	Name      string
	SizeBytes int64
	Role      string
}

// DeleteItemsResultDTO is the plan (dry run) or the applied outcome, with
// what the deletion did beside removing files and, once applied, its
// totals.
type DeleteItemsResultDTO struct {
	Applied        bool
	Mode           string
	Entries        []DeletePlanDTO
	Warnings       []string
	Trashed        int
	Deleted        int
	Failed         int
	DirsPruned     int
	ReclaimedBytes int64
}

// errEpisodeNotDeletable refuses a podcast episode on a delete surface.
// The podcast download tree owns its own files, so the catalog's delete
// does not reach into it; removing a download is a different contract
// anyway - no undo journal, gated on a subscription - which is why these
// paths refuse rather than quietly routing to it.
func errEpisodeNotDeletable() error {
	return errInvalid("podcast episodes cannot be deleted here; remove the episode's download instead")
}

// ErrCueRipPart marks a delete naming some of a cue rip's tracks and not
// the rest, which the catalog refuses since their file goes whole.
var ErrCueRipPart = errors.New("part of a cue rip")

// CueRipTracks is ErrCueRipPart with every track of the rips the delete
// named some of, as the API names them and in the order they play, for a
// caller to offer them together.
type CueRipTracks struct{ Tracks []string }

func (e *CueRipTracks) Error() string        { return ErrCueRipPart.Error() }
func (e *CueRipTracks) Is(target error) bool { return target == ErrCueRipPart }

// DeleteItems deletes items' files, to the trash by default. Callers
// need the delete permission or the admin role; permanent mode is
// admin-only. Every pid must be visible to the caller, every touched
// library must be writable, and no pid may name a podcast episode.
// The whole list is refused when one does, matching the catalog. An
// item's copies go with it, except one in a library the caller cannot
// see, which stays and keeps the item, as one in a read-only library
// does. A run whose every move failed is refused, and one that moved
// some files answers what went and what stayed.
func (l *Library) DeleteItems(ctx context.Context, uc *UserCtx, apiPIDs []string, mode string, dryRun bool) (DeleteItemsResultDTO, error) {
	dm, mode, err := deleteModeFor(uc, mode)
	if err != nil {
		return DeleteItemsResultDTO{}, err
	}
	if len(apiPIDs) == 0 {
		return DeleteItemsResultDTO{}, errInvalid("pids are required")
	}
	if len(apiPIDs) > 500 {
		return DeleteItemsResultDTO{}, errInvalid("at most 500 pids per call")
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	d := newDeletion(uc)
	var carved []*model.ItemView
	for _, p := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, p)
		if err != nil {
			return DeleteItemsResultDTO{}, err
		}
		if it.Kind == model.KindEpisode {
			return DeleteItemsResultDTO{}, errEpisodeNotDeletable()
		}
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return DeleteItemsResultDTO{}, err
		}
		if err := d.add(ctx, l, it, p); err != nil {
			return DeleteItemsResultDTO{}, err
		}
		pids = append(pids, it.PID)
		if it.Virtual {
			carved = append(carved, it)
		}
	}
	if l.deletePlanHook != nil {
		l.deletePlanHook(ctx)
	}
	plan, err := l.lib.PlanDeletePIDs(ctx, pids, dm)
	if err != nil {
		// Episodes and modes are refused above.
		refusal := planRefusal(err, len(carved) > 0)
		if errors.Is(refusal, ErrCueRipPart) {
			refusal = errCueRipPart(l.ripTracks(ctx, carved)...)
		}
		return DeleteItemsResultDTO{}, refusal
	}
	d.keepUnseen(plan)
	out := DeleteItemsResultDTO{Mode: mode, Entries: d.entries(plan)}
	if dryRun {
		return out, nil
	}
	// A started delete finishes and is recorded, whatever happens to the
	// request that asked for it.
	ctx = context.WithoutCancel(ctx)
	rep, stayed, err := l.applyDeletion(ctx, plan)
	if err != nil {
		return DeleteItemsResultDTO{}, err
	}
	if refused := l.deletionRefused(plan, rep, stayed); refused != nil {
		l.Audit(ctx, uc, "items.delete.refused", AuditTarget{Kind: "item"},
			map[string]any{"mode": mode, "pids": apiPIDs, "error": refused.Msg})
		return DeleteItemsResultDTO{}, refused
	}
	d.settle(&out, plan, rep, stayed, true)
	// An item a copy kept names the copy, under the item's name, since
	// one call can keep several.
	if len(rep.Promoted) > 0 {
		kept := map[string]bool{}
		for _, e := range out.Entries {
			kept[e.PID] = e.ItemSurvives
		}
		for _, pid := range pids {
			if !kept[d.apiPIDs[pid]] {
				continue
			}
			for _, w := range l.promotedWarnings(ctx, uc, pid, rep.Promoted) {
				out.Warnings = append(out.Warnings, d.names[pid]+": "+w)
			}
		}
	}
	l.Audit(ctx, uc, "items.delete", AuditTarget{Kind: "item"},
		d.auditDetail(map[string]any{"mode": mode, "count": itemsTaken(out.Entries), "pids": apiPIDs}, plan, rep, stayed))
	return out, nil
}

// itemsTaken counts the items a delete took files of, or that went with
// a rip that did: an item none of whose files moved is not one.
func itemsTaken(entries []DeletePlanDTO) int {
	n := 0
	for _, e := range entries {
		if e.Files > 0 || e.Failed == 0 {
			n++
		}
	}
	return n
}

// DeleteItemFiles deletes some of one visible item's files, to the trash
// by default, under DeleteItems' rights. A copy goes alone; the primary
// or a part gives its place to a copy when the item has one, which a
// warning names. Every file must be one the caller sees in ItemFiles, in
// a writable library, and the file of a cue rip only goes with every
// track it plays, which this surface cannot name.
func (l *Library) DeleteItemFiles(ctx context.Context, uc *UserCtx, apiItemPID string, filePIDs []string, mode string, dryRun bool) (DeleteItemsResultDTO, error) {
	dm, mode, err := deleteModeFor(uc, mode)
	if err != nil {
		return DeleteItemsResultDTO{}, err
	}
	if len(filePIDs) == 0 {
		return DeleteItemsResultDTO{}, errInvalid("filePids are required")
	}
	if len(filePIDs) > 100 {
		return DeleteItemsResultDTO{}, errInvalid("at most 100 files per call")
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return DeleteItemsResultDTO{}, err
	}
	if it.Kind == model.KindEpisode {
		return DeleteItemsResultDTO{}, errEpisodeNotDeletable()
	}
	d := newDeletion(uc)
	if err := d.add(ctx, l, it, apiItemPID); err != nil {
		return DeleteItemsResultDTO{}, err
	}
	own := d.files[it.PID]
	var pids []model.PID
	for _, fp := range filePIDs {
		ref, ok := own[model.PID(fp)]
		if !ok || !libraryGranted(uc, ref.LibraryPID) {
			return DeleteItemsResultDTO{}, errNotFound("item " + apiItemPID + " has no file " + FileAPIPID(fp))
		}
		if slices.Contains(pids, ref.FilePID) {
			continue
		}
		if err := l.CheckWritable(ctx, string(ref.LibraryPID)); err != nil {
			return DeleteItemsResultDTO{}, err
		}
		pids = append(pids, ref.FilePID)
	}
	plan, err := l.lib.PlanDeleteFiles(ctx, pids, dm)
	if err != nil {
		return DeleteItemsResultDTO{}, classify(err)
	}
	for _, a := range plan.Actions {
		if ripPlaysOthers(a, it.PID) {
			tracks := make([]string, 0, len(a.Tracks))
			for _, track := range a.Tracks {
				tracks = append(tracks, apiPID(PrefixTrack, track))
			}
			return DeleteItemsResultDTO{}, errCueRipPart(tracks...)
		}
	}
	out := DeleteItemsResultDTO{Mode: mode, Entries: d.entries(plan)}
	if dryRun {
		return out, nil
	}
	ctx = context.WithoutCancel(ctx)
	rep, stayed, err := l.applyDeletion(ctx, plan)
	if err != nil {
		return DeleteItemsResultDTO{}, err
	}
	if refused := l.deletionRefused(plan, rep, stayed); refused != nil {
		l.Audit(ctx, uc, "items.delete-files.refused", AuditTarget{Kind: "item", PID: apiItemPID},
			map[string]any{"mode": mode, "filePids": filePIDs, "error": refused.Msg})
		return DeleteItemsResultDTO{}, refused
	}
	d.settle(&out, plan, rep, stayed, false)
	out.Warnings = append(out.Warnings, l.promotedWarnings(ctx, uc, it.PID, rep.Promoted)...)
	l.Audit(ctx, uc, "items.delete-files", AuditTarget{Kind: "item", PID: apiItemPID},
		d.auditDetail(map[string]any{"mode": mode, "count": len(pids) - len(stayed), "filePids": filePIDs}, plan, rep, stayed))
	return out, nil
}

// applyDeletion applies a delete plan and maps each planned file that
// stayed to why, in words: the run goes on past a move it could not
// make, and skips an action whose library was flagged read-only, or whose
// cue rip's tracks changed, since the plan, so the plan alone would
// report the file gone.
func (l *Library) applyDeletion(ctx context.Context, plan *trash.Plan) (*trash.Report, map[model.PID]string, error) {
	if l.deleteApplyHook != nil {
		l.deleteApplyHook(ctx)
	}
	// Not cut short between files: a run stopped half way moves files
	// that nothing then records.
	rep, err := l.applyDelete(context.WithoutCancel(ctx), plan)
	if err != nil {
		return nil, nil, classifyMutation(err)
	}
	stayed := make(map[model.PID]string, len(rep.Failures))
	refused := false
	for _, f := range rep.Failures {
		stayed[f.FilePID] = l.failureCause(f.Err)
		refused = refused || l.storageRefused(f.Err) != ""
	}
	planned := 0
	for _, a := range plan.Actions {
		if a.Skip {
			planned++
		}
	}
	if rep.Skipped > planned {
		l.skippedAsItRan(ctx, plan, stayed)
	}
	return rep, stayed, nil
}

// applyDelete is the catalog's apply of a delete plan, or what a test's
// mutateHook answers in its place.
func (l *Library) applyDelete(ctx context.Context, plan *trash.Plan) (*trash.Report, error) {
	if l.mutateHook != nil {
		if err := l.mutateHook("trash"); err != nil {
			return nil, err
		}
	}
	return l.lib.ApplyDelete(ctx, plan)
}

// skippedAsItRan adds to stayed each file the catalog skipped as the
// delete ran, which its report counts and does not name: a file its item
// still holds after the run did not go.
func (l *Library) skippedAsItRan(ctx context.Context, plan *trash.Plan, stayed map[model.PID]string) {
	readOnly := map[model.PID]bool{}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		l.log.Warn("reading the libraries a delete skipped in", "err", err)
	}
	for _, lib := range libs {
		readOnly[lib.PID] = lib.ReadOnly
	}
	held := map[model.PID]map[model.PID]model.ItemFileRef{}
	for _, a := range plan.Actions {
		if _, ok := stayed[a.FilePID]; a.Skip || ok {
			continue
		}
		files, read := held[a.ItemPID]
		if !read {
			refs, err := l.lib.ItemFiles(ctx, a.ItemPID)
			if err != nil {
				l.log.Warn("reading the files a delete skipped", "item", string(a.ItemPID), "err", err)
			}
			files = make(map[model.PID]model.ItemFileRef, len(refs))
			for _, ref := range refs {
				files[ref.FilePID] = ref
			}
			held[a.ItemPID] = files
		}
		if ref, kept := files[a.FilePID]; kept {
			stayed[a.FilePID] = "the cue rip's tracks changed since the plan"
			if readOnly[ref.LibraryPID] {
				stayed[a.FilePID] = "library is read-only"
			}
		}
	}
}

// errNothingDeleted marks the refusal of an applied delete that moved no
// file, which every caller records as a refused delete.
var errNothingDeleted = errors.New("nothing was deleted")

// deletionRefused is the refusal of an applied delete that moved no file
// while one was due to go: a folder that would not take the move is the
// library's to fix, a library flagged read-only or a cue rip changed since
// the plan is said as such, anything else is the server's. Nil once a
// file went.
func (l *Library) deletionRefused(plan *trash.Plan, rep *trash.Report, stayed map[model.PID]string) *Error {
	if rep.Trashed+rep.Deleted > 0 {
		return nil
	}
	for _, f := range rep.Failures {
		if cause := storageRefusal(f.Err); cause != "" {
			e := errStorageUnwritable(cause)
			e.Err = errNothingDeleted
			return e
		}
	}
	if len(rep.Failures) > 0 {
		return &Error{Kind: KindInternal, Err: errNothingDeleted,
			Msg: "the delete failed: " + l.failureCause(rep.Failures[0].Err)}
	}
	// Skipped as it ran: the reasons are the ones skippedAsItRan wrote.
	readOnly, changed := false, false
	for _, a := range plan.Actions {
		switch why, ok := stayed[a.FilePID]; {
		case !ok || a.Skip:
		case why == "library is read-only":
			readOnly = true
		default:
			changed = true
		}
	}
	switch {
	case readOnly:
		return &Error{Kind: KindReadOnly, Msg: errReadOnly("this library").Error(), Err: errNothingDeleted}
	case changed:
		return &Error{Kind: KindConflict, Err: errNothingDeleted,
			Msg: "the cue rip's tracks changed since the delete was planned, so nothing was deleted; try again"}
	}
	return nil
}

// failedFiles are the files an applied plan tried to remove and could
// not, as against the ones it skipped.
func failedFiles(rep *trash.Report) map[model.PID]bool {
	out := make(map[model.PID]bool, len(rep.Failures))
	for _, f := range rep.Failures {
		out[f.FilePID] = true
	}
	return out
}

// libraryPath is where a planned file is, relative to its library's root
// and in forward slashes; its name alone where the plan carries no root,
// so the server's folders never reach the caller.
func libraryPath(a trash.Action) string {
	if a.Root != "" {
		rel, err := filepath.Rel(a.Root, a.Src)
		if err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return filepath.ToSlash(rel)
		}
	}
	return filepath.Base(a.Src)
}

// failureCause is the innermost reason of an error's text, the part
// after its last ": ", with storage roots scrubbed.
func (l *Library) failureCause(msg string) string {
	if i := strings.LastIndex(msg, ": "); i >= 0 {
		msg = msg[i+2:]
	}
	return l.scrubStoragePaths(msg)
}

// deleteModeFor reads a delete mode for the caller: trash for anyone
// holding the delete right, permanent for administrators.
func deleteModeFor(uc *UserCtx, mode string) (model.DeleteMode, string, error) {
	if !uc.Admin && !uc.Delete {
		return "", "", &Error{Kind: KindForbidden, Msg: "this account cannot delete library items"}
	}
	switch mode {
	case "", "trash":
		return model.DeleteTrash, "trash", nil
	case "permanent":
		if !uc.Admin {
			return "", "", &Error{Kind: KindForbidden, Msg: "permanent deletion is administrators only"}
		}
		return model.DeletePermanent, mode, nil
	}
	return "", "", errInvalid("mode must be trash or permanent")
}

// errCueRipPart refuses a delete that would take a cue rip's file from
// under tracks the caller did not name, naming the rip's tracks when
// they are known.
func errCueRipPart(tracks ...string) error {
	var cause error = ErrCueRipPart
	if len(tracks) > 0 {
		cause = &CueRipTracks{Tracks: tracks}
	}
	return &Error{Kind: KindInvalid, Err: cause,
		Msg: "a cue rip's tracks share one file, so they are deleted together or not at all; name every track of the rip"}
}

// ripTracks is every track of the rips the carved items are cut from, as
// the API names them, each rip's in the order they play.
func (l *Library) ripTracks(ctx context.Context, carved []*model.ItemView) []string {
	var out []string
	seen := map[model.PID]bool{}
	for _, it := range carved {
		if seen[it.PID] {
			continue
		}
		_, sibs, err := l.cueRip(ctx, it)
		if err != nil {
			l.log.Warn("reading the tracks of a cue rip a delete named", "item", string(it.PID), "err", err)
			continue
		}
		for _, sib := range sibs {
			if !seen[sib.PID] {
				seen[sib.PID] = true
				out = append(out, apiPID(PrefixTrack, sib.PID))
			}
		}
	}
	return out
}

// ripPlaysOthers reports whether a planned deletion takes a cue rip's
// file from under tracks besides item.
func ripPlaysOthers(a trash.Action, item model.PID) bool {
	return len(a.Tracks) > 1 || (len(a.Tracks) == 1 && a.Tracks[0] != item)
}

// planRefusal is an item delete plan's refusal: an invalid plan with a
// carved track named is the catalog's whole-rip rule.
func planRefusal(err error, carved bool) error {
	if carved && waxerr.Is(err, waxerr.CodeInvalid) {
		return errCueRipPart()
	}
	return classify(err)
}

// deletion is what a delete knows of the items it names: their API pids
// and names, every file behind each, seen or not, and the size of each
// file the plan takes, measured at its first report, before the apply
// moves it.
type deletion struct {
	uc      *UserCtx
	names   map[model.PID]string
	apiPIDs map[model.PID]string
	files   map[model.PID]map[model.PID]model.ItemFileRef
	sizes   map[model.PID]int64
}

func newDeletion(uc *UserCtx) *deletion {
	return &deletion{uc: uc, names: map[model.PID]string{}, apiPIDs: map[model.PID]string{},
		files: map[model.PID]map[model.PID]model.ItemFileRef{}, sizes: map[model.PID]int64{}}
}

// add records one item the delete names.
func (d *deletion) add(ctx context.Context, l *Library, it *model.ItemView, apiPID string) error {
	refs, err := l.lib.ItemFiles(ctx, it.PID)
	if err != nil {
		return classify(err)
	}
	files := make(map[model.PID]model.ItemFileRef, len(refs))
	for _, ref := range refs {
		files[ref.FilePID] = ref
	}
	d.names[it.PID], d.apiPIDs[it.PID], d.files[it.PID] = it.Title, apiPID, files
	return nil
}

// keepUnseen leaves in place every file the plan would delete that the
// caller was not shown: a copy in a library they cannot see is not
// theirs to remove, nor is one that joined the item after its files were
// read, so the item keeps it.
func (d *deletion) keepUnseen(plan *trash.Plan) {
	for i := range plan.Actions {
		a := &plan.Actions[i]
		if a.Skip {
			continue
		}
		switch ref, seen := d.files[a.ItemPID][a.FilePID]; {
		case !seen:
			a.Skip, a.Reason = true, "joined the item after the delete read its files"
		case !libraryGranted(d.uc, ref.LibraryPID):
			a.Skip, a.Reason = true, "in a library outside the caller's reach"
		}
	}
}

// entries reports a plan per item, as the API does. A cue rip's file
// plays every track it lists, so each gets an entry, and the file counts
// once, under the item the plan names it for.
func (d *deletion) entries(plan *trash.Plan) []DeletePlanDTO {
	return d.entriesWithout(plan, nil, nil)
}

// entriesWithout is entries less the files that stayed. An item a
// skipped or staying file holds survives, and one the run failed to
// remove counts against its item with why.
func (d *deletion) entriesWithout(plan *trash.Plan, stayed map[model.PID]string, failed map[model.PID]bool) []DeletePlanDTO {
	perItem := map[model.PID]*DeletePlanDTO{}
	var order []model.PID
	going := map[model.PID]bool{}
	kept := map[model.PID]bool{}
	entry := func(item model.PID, src string) *DeletePlanDTO {
		dto, ok := perItem[item]
		if !ok {
			dto = &DeletePlanDTO{PID: d.apiPIDs[item], Name: d.names[item]}
			if dto.Name == "" {
				dto.Name = filepath.Base(src)
			}
			perItem[item] = dto
			order = append(order, item)
		}
		return dto
	}
	for _, a := range plan.Actions {
		if why, ok := stayed[a.FilePID]; a.Skip || ok {
			kept[a.ItemPID] = true
			for _, track := range a.Tracks {
				kept[track] = true
			}
			if failed[a.FilePID] {
				dto := entry(a.ItemPID, a.Src)
				dto.Failed++
				if dto.Error == "" {
					dto.Error = why
				}
			}
			continue
		}
		going[a.FilePID] = true
		dto := entry(a.ItemPID, a.Src)
		dto.Paths = append(dto.Paths, libraryPath(a))
		f := DeletePlanFileDTO{FilePID: string(a.FilePID), Name: filepath.Base(a.Src), Role: d.files[a.ItemPID][a.FilePID].Role}
		size, measured := d.sizes[a.FilePID]
		if !measured {
			if st, err := os.Stat(a.Src); err == nil {
				size = st.Size()
			}
			d.sizes[a.FilePID] = size
		}
		f.SizeBytes = size
		dto.Files++
		dto.Bytes += f.SizeBytes
		dto.FileList = append(dto.FileList, f)
		for _, track := range a.Tracks {
			entry(track, a.Src)
		}
	}
	out := make([]DeletePlanDTO, 0, len(order))
	for _, item := range order {
		dto := perItem[item]
		dto.ItemSurvives = kept[item]
		for file := range d.files[item] {
			if !going[file] {
				dto.ItemSurvives = true
			}
		}
		out = append(out, *dto)
	}
	return out
}

// settle reports an applied plan into out: its totals, and what went,
// less the files that stayed, each named in a warning, under its item's
// name for a call that names items.
func (d *deletion) settle(out *DeleteItemsResultDTO, plan *trash.Plan, rep *trash.Report, stayed map[model.PID]string, byItem bool) {
	out.Applied = true
	out.Trashed, out.Deleted, out.Failed = rep.Trashed, rep.Deleted, rep.Errored
	out.DirsPruned, out.ReclaimedBytes = rep.DirsPruned, rep.ReclaimedBytes
	if len(stayed) > 0 {
		out.Entries = d.entriesWithout(plan, stayed, failedFiles(rep))
	}
	for _, a := range plan.Actions {
		why, ok := stayed[a.FilePID]
		if !ok {
			continue
		}
		w := stayedWarning(plan.Mode, a.Src, why)
		if byItem {
			w = d.names[a.ItemPID] + ": " + w
		}
		out.Warnings = append(out.Warnings, w)
	}
}

// stayedWarning says what became of a planned file the delete reports
// failed: it stayed, unless a permanent delete removed it from the disk
// before the catalog refused to let go of it.
func stayedWarning(mode model.DeleteMode, src, why string) string {
	name := filepath.Base(src)
	if mode.BypassesTrash() {
		if _, err := os.Lstat(src); errors.Is(err, os.ErrNotExist) {
			return name + " was deleted, but the catalog still lists it: " + why
		}
	}
	return name + " stayed: " + why
}

// auditDetail is a delete's audit detail with the run's totals and, for
// each file it failed to remove, the item, the file's name and why.
func (d *deletion) auditDetail(detail map[string]any, plan *trash.Plan, rep *trash.Report, stayed map[model.PID]string) map[string]any {
	detail["trashed"], detail["deleted"], detail["failed"] = rep.Trashed, rep.Deleted, rep.Errored
	failed := failedFiles(rep)
	var failures []map[string]string
	for _, a := range plan.Actions {
		if failed[a.FilePID] {
			failures = append(failures, map[string]string{
				"pid": d.apiPIDs[a.ItemPID], "file": filepath.Base(a.Src), "reason": stayed[a.FilePID]})
		}
	}
	if len(failures) > 0 {
		detail["failures"] = failures
	}
	return detail
}

// promotedWarnings names each copy a deletion moved into a removed
// file's place, by the place it now holds; one the caller cannot see is
// left unsaid.
func (l *Library) promotedWarnings(ctx context.Context, uc *UserCtx, item model.PID, promoted []model.PromotedFile) []string {
	if len(promoted) == 0 {
		return nil
	}
	refs, err := l.lib.ItemFiles(ctx, item)
	if err != nil {
		l.log.Warn("reading the files a deletion promoted", "item", string(item), "err", err)
		return nil
	}
	var out []string
	for _, p := range promoted {
		for _, ref := range refs {
			if ref.FilePID != p.FilePID || !libraryGranted(uc, ref.LibraryPID) {
				continue
			}
			name := filepath.Base(ref.DisplayPath)
			if ref.Role == fileRolePrimary {
				out = append(out, name+" is now the item's main file")
			} else {
				out = append(out, name+" now takes the place of the deleted part")
			}
		}
	}
	return out
}
