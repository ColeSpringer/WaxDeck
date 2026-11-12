package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// StartBookMerge queues a merge of a multi-file audiobook into one
// chaptered file. Administrators only.
func (l *Tools) StartBookMerge(ctx context.Context, uc *UserCtx, apiBookPID string, titles []string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.Roots.needsEngine("book merging")
	}
	bd, err := l.Reads.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.refuseHeldBook(ctx, bd.Item.PID); err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.refusePartsInTrash(ctx, bd.Item.PID); err != nil {
		return ToolTaskDTO{}, err
	}
	if len(bd.Files) < 2 {
		return ToolTaskDTO{}, toolRefusal(refusalSingleFile, "the book is already a single file")
	}
	if len(titles) > 0 && len(titles) != len(bd.Files) {
		return ToolTaskDTO{}, errInvalid(fmt.Sprintf(
			"titles has %d entries for %d parts; one per part, or none", len(titles), len(bd.Files)))
	}
	paths := make([]string, len(bd.Files))
	durs := make([]int64, len(bd.Files))
	files := make([]string, len(bd.Files))
	for i, f := range bd.Files {
		file, err := l.lib.File(ctx, f.FilePID)
		if err != nil {
			return ToolTaskDTO{}, classify(err)
		}
		paths[i] = string(file.Path)
		durs[i] = f.DurationMS
		files[i] = string(f.FilePID)
	}
	p := toolTaskParams{
		KeepOriginals: keepOriginals, Titles: titles, PartPaths: paths, PartDurationsMS: durs, PartFilePIDs: files,
		SourceIdents: identsOf(paths...),
	}
	if err := l.mergeTool(nil, &p, bd.Item.PID, bd.Item.Title, paths).check(ctx); err != nil {
		return ToolTaskDTO{}, err
	}
	return l.queueBookTool(ctx, uc, taskTypeBookMerge, bd, p)
}

// StartBookSplit queues a split of a single-file audiobook at its
// chapter marks. Administrators only.
func (l *Tools) StartBookSplit(ctx context.Context, uc *UserCtx, apiBookPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.Roots.needsEngine("book splitting")
	}
	bd, err := l.Reads.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.refuseHeldBook(ctx, bd.Item.PID); err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.refusePartsInTrash(ctx, bd.Item.PID); err != nil {
		return ToolTaskDTO{}, err
	}
	if len(bd.Files) >= 2 {
		return ToolTaskDTO{}, toolRefusal(refusalMultiFile, "the book is already split across files; merge it first")
	}
	if len(bd.Chapters) == 0 {
		return ToolTaskDTO{}, toolRefusal(refusalNoChapters, "the book has no chapters to split at")
	}
	if len(bd.Files) == 0 {
		return ToolTaskDTO{}, toolRefusal(refusalNoFile, "the book has no file to split")
	}
	loc, err := l.paths.Locate(ctx, bd.Item.PID)
	if err != nil {
		return ToolTaskDTO{}, classify(err)
	}
	rate := loc.SampleRate
	if rate <= 0 {
		rate = bd.Item.SampleRate
	}
	if rate <= 0 {
		return ToolTaskDTO{}, toolRefusal(refusalNoSampleRate, "the file declares no sample rate to place cuts by")
	}
	// The engine cuts at source sample offsets, strictly ascending and
	// interior: chapter zero's start is the implied cut at 0, and a
	// duplicate or non-advancing mark is dropped rather than refused
	// job-side. Piece titles stay aligned with the surviving cuts.
	titles := []string{chapterTitle(bd.Chapters[0].Title, 0)}
	var cuts []int64
	var last int64
	for i := 1; i < len(bd.Chapters); i++ {
		s := bd.Chapters[i].StartMS * int64(rate) / 1000
		if s <= last {
			continue
		}
		cuts = append(cuts, s)
		last = s
		titles = append(titles, chapterTitle(bd.Chapters[i].Title, i))
	}
	if len(cuts) == 0 {
		return ToolTaskDTO{}, toolRefusal(refusalNoCuts, "the chapter marks yield no interior cut points")
	}
	p := toolTaskParams{
		KeepOriginals: keepOriginals, SrcPath: loc.Path, SrcFilePID: string(bd.Files[0].FilePID),
		Format: toolSplitFormat(bd.Item.Codec), Cuts: cuts, PieceTitles: titles, SourceIdents: identsOf(loc.Path),
	}
	if err := l.splitTool(nil, &p, bd.Item.PID, bd.Item.Title, loc.Path).check(ctx); err != nil {
		return ToolTaskDTO{}, err
	}
	return l.queueBookTool(ctx, uc, taskTypeBookSplit, bd, p)
}

// The reasons a book tool is refused before it is queued, which a
// refusal's params carry for a client to word.
const (
	refusalSingleFile    = "single-file"
	refusalMultiFile     = "multi-file"
	refusalNoChapters    = "no-chapters"
	refusalNoCuts        = "no-cuts"
	refusalNoSampleRate  = "no-sample-rate"
	refusalNoFile        = "no-file"
	refusalNameTaken     = "name-taken"
	refusalCopyElsewhere = "copy-elsewhere"
	refusalTaskRunning   = "task-running"
	refusalTaskParked    = "task-parked"
	refusalPartsInTrash  = "parts-in-trash"
	refusalOutputsHidden = "outputs-hidden"
	refusalNoSheet       = "no-sheet"
)

// toolRefusal is a file tool refused before it is queued, for reason:
// conflict, with the reason and each key and value of params.
func toolRefusal(reason, msg string, params ...string) *Error {
	p := map[string]string{"reason": reason}
	for i := 0; i+1 < len(params); i += 2 {
		p[params[i]] = params[i+1]
	}
	return &Error{Kind: KindConflict, Msg: msg, Params: p}
}

// bookToolLock is what a merge or split of book holds while it is live:
// one at a time per book, since a second would take the first's parts.
func bookToolLock(book model.PID) string { return "book:" + string(book) }

// ripToolLock is what a CUE split of the rip in file holds while it is
// live: a second would import the rip's tracks again.
func ripToolLock(file model.PID) string { return "rip:" + string(file) }

// refuseHeld refuses a file tool over what a live task holds.
func (l *Tools) refuseHeld(ctx context.Context, lock, what string) error {
	held, err := l.db.ToolTaskHolding(ctx, lock)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if held != "" {
		return l.heldRefusal(ctx, what, held)
	}
	return nil
}

// heldRefusal refuses what task holds, what naming the task's kind: one
// parked never finishes by itself, so it is cleared in Tasks first; any
// other is still at work.
func (l *Tools) heldRefusal(ctx context.Context, what, task string) error {
	if t, err := l.db.ToolTaskByID(ctx, task); err == nil && t.State == taskStateParked {
		return toolRefusal(refusalTaskParked, what+" stopped and needs attention: clear it in Tasks, then try again", "task", task)
	}
	return toolRefusal(refusalTaskRunning, what+" has not finished yet", "task", task)
}

// refuseHeldBook refuses a merge or split of a book another one is at
// work on, or that a parked one holds.
func (l *Tools) refuseHeldBook(ctx context.Context, book model.PID) error {
	return l.refuseHeld(ctx, bookToolLock(book), "a merge or split of this book")
}

// refusePartsInTrash refuses a merge or split of a book an earlier one
// left part of in the trash, naming those files: from what remains it
// would make a book that looks whole without them, and the trash would
// lose them at its next purge. Restored, they are the book's again.
func (l *Tools) refusePartsInTrash(ctx context.Context, book model.PID) error {
	taken, err := l.db.ToolTrashOf(ctx, string(book))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if len(taken) == 0 {
		return nil
	}
	byItem, err := l.lib.RestorableTrash(ctx, []model.PID{book})
	if err != nil {
		return classify(err)
	}
	inTrash := map[string]model.TrashEntry{}
	for _, e := range byItem[book] {
		if e.Reason == taskTypeBookMerge || e.Reason == taskTypeBookSplit {
			inTrash[string(e.OrigPath)] = e
		}
	}
	var names, gone []string
	for _, p := range taken {
		if e, ok := inTrash[p]; ok {
			names = append(names, l.Ingest.scrubStoragePaths(e.OrigDisplay))
		} else {
			gone = append(gone, p)
		}
	}
	// Restored since, or purged: nothing of it left to restore.
	if len(gone) > 0 {
		if err := l.db.ForgetToolTrash(ctx, string(book), gone); err != nil {
			l.log.Warn("forgetting a tool's trash", "book", string(book), "err", err)
		}
	}
	if len(names) == 0 {
		return nil
	}
	return partsInTrashRefusal(names)
}

// partsInTrashNamed is how many of the files an unfinished run left in
// the trash its refusal names; the rest it counts.
const partsInTrashNamed = 5

// partsInTrashRefusal is the refusal naming the files a merge or split
// that did not finish left in the trash, a few of them and how many more,
// and how to finish what it started.
func partsInTrashRefusal(names []string) *Error {
	shown := names[:min(len(names), partsInTrashNamed)]
	more := len(names) - len(shown)
	files := strings.Join(shown, ", ")
	if more > 0 {
		files += fmt.Sprintf(", and %d more", more)
	}
	return toolRefusal(refusalPartsInTrash, fmt.Sprintf(
		"%d of the book's files went to the trash with a merge or split that did not finish (%s); restore them from the trash, then merge or split the book again",
		len(names), files),
		"count", strconv.Itoa(len(names)), "files", strings.Join(shown, ", "), "more", strconv.Itoa(more))
}

// queueBookTool persists a queued merge or split of bd, holding the
// book, unless another task took it since the check.
func (l *Tools) queueBookTool(ctx context.Context, uc *UserCtx, typ string, bd *model.BookDetail, p toolTaskParams) (ToolTaskDTO, error) {
	t := newToolTask(uc, typ, apiPID(PrefixBook, bd.Item.PID), p, "")
	t.ItemTitle, t.LockKey = bd.Item.Title, bookToolLock(bd.Item.PID)
	return l.queueLockedToolTask(ctx, t, "a merge or split of this book")
}

// queueLockedToolTask persists a queued task holding its lock key and
// notifies its audience, or refuses it, naming the task holding it; what
// names that task's kind.
func (l *Tools) queueLockedToolTask(ctx context.Context, t wdb.ToolTask, what string) (ToolTaskDTO, error) {
	holder, err := l.db.InsertLockedToolTask(ctx, t)
	if err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if holder != "" {
		return ToolTaskDTO{}, l.heldRefusal(ctx, what, holder)
	}
	l.notifyToolTask(ctx, t.ID)
	return toolTaskDTO(t), nil
}

// StartCueSplit queues a physical split of the single-file rip behind a
// CUE-carved album; the pid may be any of the rip's virtual tracks.
// Administrators only.
func (l *Tools) StartCueSplit(ctx context.Context, uc *UserCtx, apiTrackPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.Roots.needsEngine("cue splitting")
	}
	it, err := l.Grants.getVisibleItem(ctx, uc, apiTrackPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if it.Kind != model.KindTrack || !it.Virtual {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "not a cue-carved track"}
	}
	loc, err := l.paths.Locate(ctx, it.PID)
	if err != nil {
		return ToolTaskDTO{}, classify(err)
	}
	rip, err := l.ripFileOf(ctx, it.PID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	const held = "a split of this rip"
	if err := l.refuseHeld(ctx, ripToolLock(rip), held); err != nil {
		return ToolTaskDTO{}, err
	}
	cue, ok := ownCueSheet(loc.Path)
	if !ok {
		return ToolTaskDTO{}, toolRefusal(refusalNoSheet, "the rip has no cue sheet of its own name beside it")
	}
	if err := l.Settings.checkPathWritable(ctx, loc.Path); err != nil {
		return ToolTaskDTO{}, err
	}
	t := newToolTask(uc, taskTypeCueSplit, apiPID(PrefixTrack, it.PID), toolTaskParams{
		KeepOriginals: keepOriginals, SrcPath: loc.Path, CuePath: cue, SrcFilePID: string(rip),
		Format: toolSplitFormat(it.Codec),
	}, "")
	t.ItemTitle, t.LockKey = firstNonEmpty(it.Album, it.Title), ripToolLock(rip)
	return l.queueLockedToolTask(ctx, t, held)
}

// ListToolTasksFor pages tool tasks newest first: everyone's for an
// administrator, the caller's own otherwise.
func (l *Tools) ListToolTasksFor(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]ToolTaskDTO, string, error) {
	owner := uc.ID
	if uc.Admin {
		owner = ""
	}
	beforeNS, beforeID, err := decodeTimeCursor(cursor)
	if err != nil {
		return nil, "", errInvalid("bad cursor")
	}
	rows, err := l.db.ListToolTasks(ctx, owner, beforeNS, beforeID, limit)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	out := make([]ToolTaskDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, l.taskFor(uc, r))
	}
	next := ""
	if len(rows) == limit {
		last := rows[len(rows)-1]
		next = encodeTimeCursor(last.CreatedAtNS, last.ID)
	}
	return out, next, nil
}

// GetToolTaskFor reads one task with the owner-or-admin visibility rule.
func (l *Tools) GetToolTaskFor(ctx context.Context, uc *UserCtx, taskID string) (ToolTaskDTO, error) {
	t, err := l.db.ToolTaskByID(ctx, taskID)
	if errors.Is(err, wdb.ErrNotFound) {
		return ToolTaskDTO{}, errNotFound("no task with id " + taskID)
	}
	if err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if t.UserID != uc.ID && !uc.Admin {
		return ToolTaskDTO{}, errNotFound("no task with id " + taskID)
	}
	return l.taskFor(uc, t), nil
}

// DeleteToolTaskFor removes one finished task (parked included, which
// frees the book or rip it held) under the same owner-or-admin
// visibility the read has; a task still queued or running answers
// conflict, because deleting a row out from under a worker leases
// nothing back.
func (l *Tools) DeleteToolTaskFor(ctx context.Context, uc *UserCtx, taskID string) error {
	t, err := l.db.ToolTaskByID(ctx, taskID)
	if errors.Is(err, wdb.ErrNotFound) {
		return errNotFound("no task with id " + taskID)
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if t.UserID != uc.ID && !uc.Admin {
		// The read's answer, not "forbidden": that would confirm the
		// row exists.
		return errNotFound("no task with id " + taskID)
	}
	if !ToolTaskFinished(t.State) {
		return &Error{Kind: KindConflict, Msg: "the task has not finished"}
	}
	if err := l.settleClearedTask(ctx, uc, t); err != nil {
		return err
	}
	// The statement re-checks ownership: empty scopes an administrator
	// to any row, the convention the listing uses.
	owner := uc.ID
	if uc.Admin {
		owner = ""
	}
	deleted, err := l.db.DeleteToolTask(ctx, taskID, owner)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if !deleted {
		// The row moved under us between the read and the guarded
		// delete; terminal states are final, so the only way is gone.
		return errNotFound("no task with id " + taskID)
	}
	// No task event, deliberately: the marker announces a task's state
	// changing, and a dismissal changes none. Emitted, it undid the
	// dismissing client's own in-place removal (the fan-out refetches
	// the list back to page one) and rang the bell for housekeeping.
	// Another device's stale row answers 404 on its own dismiss, which
	// the client reads as already gone.
	return nil
}

// ToolTaskScope is whose finished tasks a sweep takes.
type ToolTaskScope string

const (
	// ToolTasksMine is the caller's own, for everyone and administrators
	// too: a member's unread report is theirs to clear.
	ToolTasksMine ToolTaskScope = "mine"
	// ToolTasksAll is every account's, and an administrator's alone.
	ToolTasksAll ToolTaskScope = "all"
)

// ClearFinishedToolTasksFor deletes the caller's finished tasks, or with
// ToolTasksAll every account's, and answers how many went and how many
// stayed. No task event, for the reason DeleteToolTaskFor gives.
func (l *Tools) ClearFinishedToolTasksFor(ctx context.Context, uc *UserCtx, scope ToolTaskScope) (deleted, kept int, err error) {
	everyone := false
	switch scope {
	case "", ToolTasksMine:
	case ToolTasksAll:
		if !uc.Admin {
			return 0, 0, &Error{Kind: KindForbidden, Msg: "administrators only"}
		}
		everyone = true
	default:
		return 0, 0, errInvalid("unknown scope " + string(scope))
	}
	// The rows read first, so each is settled before it goes, and only
	// those go: a task that ends meanwhile waits for the next sweep.
	finished, err := l.db.FinishedToolTasks(ctx, uc.ID, everyone, 0)
	if err != nil {
		return 0, 0, &Error{Kind: KindInternal, Err: err}
	}
	ids := make([]string, 0, len(finished))
	for _, t := range finished {
		// A task whose hidden files could not be named or removed stays,
		// and is counted.
		if l.settleClearedTask(ctx, uc, t) != nil {
			kept++
			continue
		}
		ids = append(ids, t.ID)
	}
	deleted, err = l.db.DeleteToolTasksByID(ctx, ids)
	if err != nil {
		return deleted, kept, &Error{Kind: KindInternal, Err: err}
	}
	return deleted, kept, nil
}

// settleClearedTask settles what a finished merge or split left hidden in
// the library as its task is cleared (see bookTool.settleCleared), and
// records the clear, saying what became of those files, under uc, or the
// task's starter for the prune. A hidden file that could not take its
// name keeps the task, its error saying so, and answers the refusal the
// clear meets; other tasks leave nothing to settle.
func (l *Tools) settleClearedTask(ctx context.Context, uc *UserCtx, t wdb.ToolTask) error {
	if t.Type != taskTypeBookMerge && t.Type != taskTypeBookSplit {
		return nil
	}
	var p toolTaskParams
	if json.Unmarshal([]byte(t.Params), &p) != nil {
		return nil
	}
	b, err := l.bookToolFor(ctx, &t, &p)
	if err != nil {
		return nil
	}
	ctx = context.WithoutCancel(ctx)
	out := b.settleCleared(ctx)
	if out.outputs == "" {
		return nil
	}
	detail := map[string]any{"task": t.ID, "result": "cleared", "outputs": out.outputs, "library": l.libraryNameOf(b.dir)}
	if len(out.named) > 0 {
		detail["files"] = out.named
	}
	audit := func() {
		if uc != nil {
			l.Audit.Record(ctx, uc, b.action(), b.target(), detail)
		} else {
			l.auditToolTask(ctx, &t, b.action(), b.target(), detail)
		}
	}
	if len(out.stuck) == 0 {
		audit()
		return nil
	}
	folder := l.Ingest.scrubStoragePaths(b.dir)
	why := fmt.Sprintf("clearing it could not give %s their names in %s (%s), so the task stays",
		strings.Join(out.stuck, ", "), folder, out.cause)
	if out.outputs == "removed" {
		why = fmt.Sprintf("clearing it could not remove %s from %s (%s), so the task stays",
			strings.Join(out.stuck, ", "), folder, out.cause)
	}
	// Recorded, audited and told once for the cause: the prune tries the
	// clear again every night, and a cause that holds is no news.
	if !strings.Contains(t.Error, why) {
		t.Error = strings.TrimPrefix(t.Error+"; "+why, "; ")
		if err := l.db.UpdateToolTask(ctx, t); err != nil {
			l.log.Warn("recording a kept clear", "task", t.ID, "err", err)
		}
		detail["result"], detail["hidden"], detail["error"] = "kept", out.stuck, out.cause
		audit()
		l.notifyToolTask(ctx, t.ID)
	}
	// Kept, it holds its book as a parked task does until it can be
	// cleared: a merge into a folder that refuses the server would fail
	// as this one did.
	if t.State == taskStateFailed {
		if err := l.db.HoldFinishedToolTask(ctx, t.ID); err != nil {
			l.log.Warn("holding a kept task's book", "task", t.ID, "err", err)
		}
	}
	return toolRefusal(refusalOutputsHidden, why, "folder", folder, "cause", out.cause)
}
