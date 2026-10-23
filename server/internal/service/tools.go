package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/scan"
	"github.com/colespringer/waxbin/trash"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// File tooling: audiobook merge to a chaptered single file, chapter
// split into per-chapter files, and CUE rip split into real per-track
// files, all cut by the streaming engine's jobs surface. A book's new
// files are written beside it in its own library and scanned in; a rip's
// pieces enter through the catalog's own planner. Tasks persist in
// tool_tasks and run on the supervised drain worker; lifecycle changes
// fan out on the task event kind to the owner and every administrator.

const (
	taskTypeBookMerge = "book-merge"
	taskTypeBookSplit = "book-split"
	taskTypeCueSplit  = "cue-split"

	taskStateQueued  = "queued"
	taskStateRunning = "running"
	taskStateDone    = "done"
	taskStateFailed  = "failed"
	// taskStateParked is a task stopped for good, its runs having kept
	// ending with the server: finished and failed, it is not run again,
	// and it holds its book or rip until it is cleared.
	taskStateParked = "parked"

	// toolTaskLease bounds one attempt between renewals; a run renews
	// it for as long as it holds the task (holdToolTask), so the lease
	// only expires when the worker dies.
	toolTaskLease       = 5 * time.Minute
	toolTaskMaxAttempts = 3
	toolLeaseRenew      = time.Minute
	toolPollInterval    = 2 * time.Second
	// toolRunTimeout bounds one whole attempt; a wedged engine job
	// surfaces as a transient failure and the attempts machinery
	// retries or retires the task.
	toolRunTimeout = 30 * time.Minute
)

// toolRunTimeoutFor is one attempt's bound for a task type.
func toolRunTimeoutFor(typ string) time.Duration {
	if typ == taskTypeHealthFix {
		return healthFixTimeout
	}
	return toolRunTimeout
}

// errToolPermanent marks a task failure retrying cannot fix (invalid
// input, an engine 4xx, a job the engine itself failed). Transport
// trouble stays transient: the leased row re-runs when the lease
// expires, until the attempts budget retires it.
var errToolPermanent = errors.New("permanent tool task failure")

// ToolTaskDTO is one tool task for the API layer.
type ToolTaskDTO struct {
	ID          string
	Type        string
	State       string
	ItemPID     string
	ItemTitle   string
	ProgressPct float64
	Error       string
	ResultPIDs  []string
	// Summary is the task-type-specific result document once finished.
	Summary      map[string]any
	CreatedAtNS  int64
	FinishedAtNS int64
	// WaitReason says why a running task waits to try again, at
	// RetryAtNS; empty when it does not.
	WaitReason string
	RetryAtNS  int64
	// BookInTrash says a book merge's or split's sources are in the
	// trash until the task finishes.
	BookInTrash bool
}

// toolTaskParams is the persisted work order, captured at creation so
// the worker never depends on catalog state that may shift under it.
type toolTaskParams struct {
	KeepOriginals bool `json:"keepOriginals"`
	// Merge fields.
	Titles          []string `json:"titles,omitempty"`
	PartPaths       []string `json:"partPaths,omitempty"`
	PartDurationsMS []int64  `json:"partDurationsMs,omitempty"`
	// PartFilePIDs are the catalog's files of the parts, one per path:
	// with the originals going, the only files the merge's trash takes.
	PartFilePIDs []string `json:"partFilePids,omitempty"`
	// SourceIdents is what a book tool knows each file it works from by,
	// in source order, whatever the catalog calls the file now: recorded
	// when the task is queued and again as the run's trash takes it.
	SourceIdents []fileIdent `json:"sourceIdents,omitempty"`
	// Split fields (book and cue).
	SrcPath     string   `json:"srcPath,omitempty"`
	Format      string   `json:"format,omitempty"`
	Cuts        []int64  `json:"cuts,omitempty"`
	PieceTitles []string `json:"pieceTitles,omitempty"`
	CuePath     string   `json:"cuePath,omitempty"`
	// SrcFilePID is a book split's file in the catalog, the only file
	// its trash takes, or a CUE split's rip.
	SrcFilePID string `json:"srcFilePid,omitempty"`
	// Dir is the folder a book tool's outputs go in, chosen from where
	// its files were when it first staged them.
	Dir string `json:"dir,omitempty"`
	// Step is how far a file tool's run has gone (the toolStep values),
	// recorded before the run takes it; Waits counts the waits in a row
	// since the last step, which set the next wait's length, and
	// WaitFromNS is when that run of waits began, which caps it.
	Step       string `json:"step,omitempty"`
	Waits      int    `json:"waits,omitempty"`
	WaitFromNS int64  `json:"waitFromNs,omitempty"`
	// RunsStarted and RunsEnded count the runs begun and the runs that
	// came back; the difference is runs that ended with the process.
	RunsStarted int `json:"runsStarted,omitempty"`
	RunsEnded   int `json:"runsEnded,omitempty"`
	// The files a book tool's run made in the library, by exact path:
	// its staged outputs and their temporaries, the folder it made for
	// them, and the outputs that took their names. Nothing else is ever
	// removed by the run.
	Created []string `json:"created,omitempty"`
	MadeDir string   `json:"madeDir,omitempty"`
	Placed  []string `json:"placed,omitempty"`
	// Idents is what the run recorded of each file it wrote, by path, to
	// know it again before removing it.
	Idents map[string]fileIdent `json:"idents,omitempty"`
	// TrashedFrom is where each source was, in source order, when the
	// run's trash took it ("" for one it has not taken); Forward says the
	// run can only go on, what its trash took being gone from the trash;
	// StrandWaits counts the waits on a source missing from its place.
	TrashedFrom []string `json:"trashedFrom,omitempty"`
	Forward     bool     `json:"forward,omitempty"`
	StrandWaits int      `json:"strandWaits,omitempty"`
	// A book tool's run: when its trash started (what a put-back takes
	// back is what the trash took from then on), the names its outputs
	// take, the book the scan made of them, and the failure an undo ends
	// the run with.
	TrashFromNS int64    `json:"trashFromNs,omitempty"`
	Names       []string `json:"names,omitempty"`
	ResultPID   string   `json:"resultPid,omitempty"`
	Failure     string   `json:"failure,omitempty"`
	// A CUE split's run: the pieces it cut, by their place in its
	// workspace, where the import puts each and the audio of each, and
	// the tracks it made.
	PieceNames    []string `json:"pieceNames,omitempty"`
	PieceDests    []string `json:"pieceDests,omitempty"`
	PieceEssences []string `json:"pieceEssences,omitempty"`
	PiecePIDs     []string `json:"piecePids,omitempty"`
	// Acquisition fields.
	URL        string `json:"url,omitempty"`
	MediaType  string `json:"mediaType,omitempty"`
	LibraryPID string `json:"libraryPid,omitempty"`
	// IdentifyDeclined carries the submission's identification choice to
	// the review entries the download opens. Stored as the decline so a
	// task queued before the field existed decodes as "identify".
	IdentifyDeclined bool `json:"identifyDeclined,omitempty"`
	// Playlist-sync field: the API pid of the bound playlist to sync.
	PlaylistPID string `json:"playlistPid,omitempty"`
	// Health-fix fields: the rule, and the bare item pids to fix (none
	// is every item failing it when the task runs). PathFix is how far a
	// path fix has gone.
	Rule     string           `json:"rule,omitempty"`
	ItemPIDs []string         `json:"itemPids,omitempty"`
	PathFix  *pathFixProgress `json:"pathFix,omitempty"`
}

// StartBookMerge queues a merge of a multi-file audiobook into one
// chaptered file. Administrators only.
func (l *Library) StartBookMerge(ctx context.Context, uc *UserCtx, apiBookPID string, titles []string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.needsEngine("book merging")
	}
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
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
func (l *Library) StartBookSplit(ctx context.Context, uc *UserCtx, apiBookPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.needsEngine("book splitting")
	}
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
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
func (l *Library) refuseHeld(ctx context.Context, lock, what string) error {
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
func (l *Library) heldRefusal(ctx context.Context, what, task string) error {
	if t, err := l.db.ToolTaskByID(ctx, task); err == nil && t.State == taskStateParked {
		return toolRefusal(refusalTaskParked, what+" stopped and needs attention: clear it in Tasks, then try again", "task", task)
	}
	return toolRefusal(refusalTaskRunning, what+" has not finished yet", "task", task)
}

// refuseHeldBook refuses a merge or split of a book another one is at
// work on, or that a parked one holds.
func (l *Library) refuseHeldBook(ctx context.Context, book model.PID) error {
	return l.refuseHeld(ctx, bookToolLock(book), "a merge or split of this book")
}

// refusePartsInTrash refuses a merge or split of a book an earlier one
// left part of in the trash, naming those files: from what remains it
// would make a book that looks whole without them, and the trash would
// lose them at its next purge. Restored, they are the book's again.
func (l *Library) refusePartsInTrash(ctx context.Context, book model.PID) error {
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
			names = append(names, l.scrubStoragePaths(e.OrigDisplay))
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
func (l *Library) queueBookTool(ctx context.Context, uc *UserCtx, typ string, bd *model.BookDetail, p toolTaskParams) (ToolTaskDTO, error) {
	t := newToolTask(uc, typ, apiPID(PrefixBook, bd.Item.PID), p, "")
	t.ItemTitle, t.LockKey = bd.Item.Title, bookToolLock(bd.Item.PID)
	return l.queueLockedToolTask(ctx, t, "a merge or split of this book")
}

// queueLockedToolTask persists a queued task holding its lock key and
// notifies its audience, or refuses it, naming the task holding it; what
// names that task's kind.
func (l *Library) queueLockedToolTask(ctx context.Context, t wdb.ToolTask, what string) (ToolTaskDTO, error) {
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
func (l *Library) StartCueSplit(ctx context.Context, uc *UserCtx, apiTrackPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, l.needsEngine("cue splitting")
	}
	it, err := l.getVisibleItem(ctx, uc, apiTrackPID)
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
	if err := l.checkPathWritable(ctx, loc.Path); err != nil {
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
func (l *Library) ListToolTasksFor(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]ToolTaskDTO, string, error) {
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
		out = append(out, l.toolTaskFor(uc, r))
	}
	next := ""
	if len(rows) == limit {
		last := rows[len(rows)-1]
		next = encodeTimeCursor(last.CreatedAtNS, last.ID)
	}
	return out, next, nil
}

// GetToolTaskFor reads one task with the owner-or-admin visibility rule.
func (l *Library) GetToolTaskFor(ctx context.Context, uc *UserCtx, taskID string) (ToolTaskDTO, error) {
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
	return l.toolTaskFor(uc, t), nil
}

// DeleteToolTaskFor removes one finished task (parked included, which
// frees the book or rip it held) under the same owner-or-admin
// visibility the read has; a task still queued or running answers
// conflict, because deleting a row out from under a worker leases
// nothing back.
func (l *Library) DeleteToolTaskFor(ctx context.Context, uc *UserCtx, taskID string) error {
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
func (l *Library) ClearFinishedToolTasksFor(ctx context.Context, uc *UserCtx, scope ToolTaskScope) (deleted, kept int, err error) {
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
func (l *Library) settleClearedTask(ctx context.Context, uc *UserCtx, t wdb.ToolTask) error {
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
			l.Audit(ctx, uc, b.action(), b.target(), detail)
		} else {
			l.auditToolTask(ctx, &t, b.action(), b.target(), detail)
		}
	}
	if len(out.stuck) == 0 {
		audit()
		return nil
	}
	folder := l.scrubStoragePaths(b.dir)
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

// DrainToolTasks retires exhausted tasks and works one leased task other
// than a health fix; false means the queue is idle so the caller can
// sleep.
func (l *Library) DrainToolTasks(ctx context.Context) bool {
	return l.drainToolTasks(ctx, wdb.TaskTypes{Except: taskTypeHealthFix})
}

// DrainHealthFixes is DrainToolTasks for health fixes, which get a
// worker of their own: one can run for hours, and an acquisition or a
// sync queued behind it would wait as long.
func (l *Library) DrainHealthFixes(ctx context.Context) bool {
	return l.drainToolTasks(ctx, wdb.TaskTypes{Only: taskTypeHealthFix})
}

func (l *Library) drainToolTasks(ctx context.Context, types wdb.TaskTypes) bool {
	return l.drainToolTasksAt(ctx, types, time.Now().UnixNano())
}

// drainToolTasksAt is drainToolTasks as of now, which a test sets past
// the leases it holds.
func (l *Library) drainToolTasksAt(ctx context.Context, types wdb.TaskTypes, now int64) bool {
	// A task run against a suspended catalog spends an attempt on nothing.
	if l.Maintenance() {
		return false
	}
	l.retireExhaustedToolTasks(ctx, now)
	row, err := l.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, types)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing tool task", "err", err)
		}
		return false
	}
	// Only the first lease is a state change (queued -> running); a re-lease
	// after a transient failure leaves the task running, so re-notifying would
	// make every curation client refetch on each retry for no change. Terminal
	// transitions notify separately (completion below, exhaustion above).
	if row.Attempts <= 1 {
		l.notifyToolTask(ctx, row.ID)
	}
	runCtx, cancel := context.WithTimeout(ctx, toolRunTimeoutFor(row.Type))
	err = l.runToolTask(runCtx, &row)
	cancel()
	if err != nil {
		var wait *toolRetry
		switch {
		case errors.Is(err, errToolParked):
			// The run parked its task, which says why; nothing to record.
		case errors.As(err, &wait):
			l.deferToolTask(ctx, &row, wait)
		case permanentToolErr(err):
			l.failToolTask(ctx, &row, err)
		case ctx.Err() != nil:
			// The server is stopping, which is no failure of the task's:
			// the lease runs out and the task runs again once it is back.
		case row.Attempts >= toolTaskMaxAttempts && !row.Resumable:
			// A task whose run must be finished ends only by its run's own
			// endings, never by a count of attempts: its lease runs out
			// and it runs again, as the lease and the retire pass allow.
			l.failToolTask(ctx, &row, err)
		default:
			// Transient (a timeout, an engine request cut off): the row
			// stays leased and untouched; the lease expires and the
			// attempts machinery re-runs it, or FailExhaustedToolTasks
			// retires it.
			l.log.Warn("tool task attempt failed", "task", row.ID, "type", row.Type,
				"attempt", row.Attempts, "err", err)
		}
	}
	return true
}

// toolRetry is a failure a run waits out rather than fails on: what it
// put in the library stays as it is, and the task comes back after the
// delay, the attempt not counted. reason names the wait for a client.
type toolRetry struct {
	after  time.Duration
	err    error
	reason string
}

// errToolParked is a run that parked its task rather than run again.
var errToolParked = errors.New("the task is parked")

// ToolTaskFinished reports whether a task state is terminal: done,
// failed, or parked, which counts as failed. A finished task is never
// run again, and only a finished one may be deleted, swept or pruned.
func ToolTaskFinished(state string) bool {
	return state == taskStateDone || state == taskStateFailed || state == taskStateParked
}

func (r *toolRetry) Error() string { return r.err.Error() }
func (r *toolRetry) Unwrap() error { return r.err }

// toolBackoff is how long a run waits after its nth wait in a row: a
// quarter minute, doubling, at most half an hour.
func toolBackoff(n int) time.Duration {
	d := 15 * time.Second
	for i := 1; i < n && d < 30*time.Minute; i++ {
		d *= 2
	}
	return min(d, 30*time.Minute)
}

// deferToolTask hands a waiting task back until its delay is out, counted
// from when the run ended, saying why it waits, and tells its watchers.
func (l *Library) deferToolTask(ctx context.Context, t *wdb.ToolTask, wait *toolRetry) {
	ctx = context.WithoutCancel(ctx)
	l.log.Info("tool task waits", "task", t.ID, "type", t.Type, "for", wait.after, "err", wait.err)
	until := time.Now().Add(wait.after).UnixNano()
	if err := l.db.DeferToolTask(ctx, t.ID, until, toolFailure(wait.err).Msg, cmp.Or(wait.reason, "other")); err != nil {
		l.log.Warn("deferring tool task", "task", t.ID, "err", err)
	}
	l.notifyToolTaskProgress(ctx, t.ID)
}

// holdToolTask marks a task as one a run in this process holds, which the
// retire pass leaves, and renews its lease until the returned release:
// the lease covers the whole run, every step and every wait in it.
func (l *Library) holdToolTask(taskID string) func() {
	l.toolRunsMu.Lock()
	if l.toolRuns == nil {
		l.toolRuns = map[string]int{}
	}
	l.toolRuns[taskID]++
	l.toolRunsMu.Unlock()
	every := l.toolLeaseEvery
	if every <= 0 {
		every = toolLeaseRenew
	}
	stop, done := make(chan struct{}), make(chan struct{})
	started := l.workers != nil && l.procCtx != nil && l.workers.GoOnce(l.procCtx, "tool-lease", func(ctx context.Context) error {
		defer close(done)
		tick := time.NewTicker(every)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-stop:
				return nil
			case <-tick.C:
				until := time.Now().Add(toolTaskLease).UnixNano()
				if err := l.db.RenewToolTaskLease(ctx, taskID, until); err != nil {
					l.log.Warn("renewing tool task lease", "task", taskID, "err", err)
				}
			}
		}
	})
	return func() {
		close(stop)
		if started {
			<-done
		}
		l.toolRunsMu.Lock()
		if l.toolRuns[taskID]--; l.toolRuns[taskID] <= 0 {
			delete(l.toolRuns, taskID)
		}
		l.toolRunsMu.Unlock()
	}
}

// heldToolTasks are the tasks a run in this process holds.
func (l *Library) heldToolTasks() []string {
	l.toolRunsMu.Lock()
	defer l.toolRunsMu.Unlock()
	out := make([]string, 0, len(l.toolRuns))
	for id := range l.toolRuns {
		out = append(out, id)
	}
	return out
}

// retireExhaustedToolTasks fails every task whose attempts ran out with
// its last lease, as of now, but for those a run holds and those whose
// run must be finished, which the lease keeps taking.
func (l *Library) retireExhaustedToolTasks(ctx context.Context, now int64) {
	ids, err := l.db.FailExhaustedToolTasks(ctx, now, toolTaskMaxAttempts, l.heldToolTasks())
	if err != nil {
		l.log.Warn("retiring exhausted tool tasks", "err", err)
		return
	}
	for _, id := range ids {
		t, err := l.db.ToolTaskByID(ctx, id)
		if err == nil {
			l.settleRetired(ctx, &t)
		}
		l.settleMigrationExport(ctx, id)
		l.scrubTaskSecrets(ctx, id)
		l.notifyToolTask(ctx, id)
		if err == nil {
			l.notifyFileToolEnd(ctx, &t)
			l.toolTaskEnded(ctx, &t)
		}
	}
}

// runToolTask executes one leased task to completion.
func (l *Library) runToolTask(ctx context.Context, t *wdb.ToolTask) error {
	defer l.holdToolTask(t.ID)()
	// What a wait said is old news once the task runs again.
	t.Error = ""
	var p toolTaskParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
		return fmt.Errorf("%w: bad task params: %v", errToolPermanent, err)
	}
	var results []string
	var err error
	switch {
	case t.Type == taskTypeBookMerge:
		results, err = l.runBookMerge(ctx, t, p)
	case t.Type == taskTypeBookSplit:
		results, err = l.runBookSplit(ctx, t, p)
	case t.Type == taskTypeCueSplit:
		results, err = l.runCueSplit(ctx, t, p)
	case t.Type == taskTypeAcquire:
		results, err = l.runAcquire(ctx, t, p)
	case t.Type == taskTypePlaylistSync:
		results, err = l.runPlaylistSync(ctx, t, p)
	case t.Type == taskTypeGenreNormalize:
		err = l.runGenreNormalize(ctx, t)
	case t.Type == taskTypeHealthFix:
		err = l.runHealthFixTask(ctx, t, p)
	case strings.HasPrefix(t.Type, taskTypeMigratePrefix):
		err = l.runMigrationTask(ctx, t)
	default:
		err = fmt.Errorf("%w: unknown task type %q", errToolPermanent, t.Type)
	}
	if err != nil {
		return err
	}
	// Recorded whatever happens to the attempt now: the work is done.
	ctx = context.WithoutCancel(ctx)
	l.recordToolTaskDone(ctx, t, results)
	// Before the scrub, which drops an export id once the upload it
	// names is gone: settling is what makes that true.
	l.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	l.toolTaskEnded(ctx, t)
	return nil
}

// errEngineAway is the streaming engine gone since the task was queued.
var errEngineAway = errors.New("streaming engine unavailable")

// engineAwayErr reports a failure that is the streaming engine being
// away, which passes once it answers again.
func engineAwayErr(err error) bool {
	return errors.Is(err, errEngineAway) || errors.Is(err, flow.ErrEngineDown)
}

// errNoEngine is a tool's engine work on a server that now runs without
// one: no engine is coming back to wait on.
var errNoEngine = &Error{Kind: KindFeature, Err: errToolPermanent,
	Msg: "this needs the streaming engine, which this server runs without"}

// toolEngineUp gates a tool's engine work. An engine configured but away
// comes back, which the run waits out without spending an attempt
// (engineAwayErr); a server started without one fails the work at once.
// Only the engine work waits on it: a book tool whose outputs are already
// staged finishes without it.
func (l *Library) toolEngineUp() error {
	if l.flowJobs == nil {
		return errNoEngine
	}
	if !l.flowJobs.JobsSupported() {
		return errEngineAway
	}
	return nil
}

// runBookMerge joins a multi-file book into one chaptered M4B, written
// beside the parts in the book's own library, so who can see it does not
// change.
func (l *Library) runBookMerge(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	b, err := l.bookToolFor(ctx, t, &p)
	if err != nil {
		return nil, err
	}
	return b.runOnce(ctx, func(ctx context.Context, ws string) ([]string, error) {
		if err := l.toolEngineUp(); err != nil {
			return nil, err
		}
		bd, err := l.lib.Book(ctx, b.book)
		if err != nil {
			return nil, classify(err)
		}
		// Format aac on purpose: any mix of part codecs merges, and the
		// resolved flat MP4 form is the one that carries the chapter
		// track. The cost is a transcode even when every part is already
		// AAC; the bridge documents the trade. The parts are read where
		// the catalog has them now, which follows a move since the queue.
		jobID, err := l.flowJobs.CreateMergeJob(ctx, b.partPaths(ctx), p.Titles, "aac")
		if err != nil {
			return nil, err
		}
		if _, err := l.pollToolJob(ctx, t, jobID, 1); err != nil {
			return nil, err
		}
		merged := filepath.Join(ws, b.names[0])
		if err := l.flowJobs.DownloadJobResult(ctx, jobID, 0, merged, b.mode); err != nil {
			return nil, err
		}
		// The engine deliberately carries no source tags, so the book's
		// richer identity and its cover are stamped in a post-pass.
		if err := l.tagToolBookFile(ctx, merged, bd, b.label, b.label, 0); err != nil {
			return nil, err
		}
		return []string{merged}, nil
	})
}

// runBookSplit cuts a single-file book at its chapter marks and writes
// the pieces as one multi-file book in the book's own library. The pieces
// bypass the import planner on purpose: its audiobook layout renders one
// title-named destination per book, so a second part of the same book
// always collides and quarantines. They are placed with the multi-part
// folder convention (a folder named for the book, parts ordered by file
// name) and cataloged by a scan of the library.
func (l *Library) runBookSplit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	b, err := l.bookToolFor(ctx, t, &p)
	if err != nil {
		return nil, err
	}
	return b.runOnce(ctx, func(ctx context.Context, ws string) ([]string, error) {
		if err := l.toolEngineUp(); err != nil {
			return nil, err
		}
		bd, err := l.lib.Book(ctx, b.book)
		if err != nil {
			return nil, classify(err)
		}
		jobID, err := l.flowJobs.CreateSplitJob(ctx, b.partPaths(ctx)[0], p.Cuts, "", p.Format)
		if err != nil {
			return nil, err
		}
		outs, err := l.pollToolJob(ctx, t, jobID, len(b.names))
		if err != nil {
			return nil, err
		}
		pieces := make([]string, 0, outs)
		for i := range outs {
			dst := filepath.Join(ws, b.names[i])
			if err := l.flowJobs.DownloadJobResult(ctx, jobID, i, dst, b.mode); err != nil {
				return nil, err
			}
			if err := l.tagToolBookFile(ctx, dst, bd, b.label, b.pieceTitle(i), i+1); err != nil {
				return nil, err
			}
			pieces = append(pieces, dst)
		}
		return pieces, nil
	})
}

// pollToolJob polls one engine job to completion, mirroring the
// task's progress and renewing the lease as it goes. wantOutputs > 0
// asserts the finished output count.
func (l *Library) pollToolJob(ctx context.Context, t *wdb.ToolTask, jobID string, wantOutputs int) (int, error) {
	lastPct := -1.0
	for {
		state, pct, outs, errMsg, err := l.flowJobs.JobStatus(ctx, jobID)
		if err != nil {
			return 0, err
		}
		switch state {
		case "done":
			if wantOutputs > 0 && outs != wantOutputs {
				return 0, fmt.Errorf("%w: engine job %s produced %d outputs, want %d",
					errToolPermanent, jobID, outs, wantOutputs)
			}
			return outs, nil
		case "queued", "running":
		default:
			if errMsg == "" {
				errMsg = state
			}
			return 0, fmt.Errorf("%w: engine job %s: %s", errToolPermanent, jobID, errMsg)
		}
		// The engine's percent maps onto 0..90; the import and remap
		// tail owns the rest.
		if scaled := pct * 0.9; scaled-lastPct >= 5 {
			lastPct = scaled
			t.ProgressPct = scaled
			if uerr := l.db.UpdateToolTask(ctx, *t); uerr != nil {
				l.log.Warn("recording tool task progress", "task", t.ID, "err", uerr)
			}
			l.notifyToolTaskProgress(ctx, t.ID)
		}
		select {
		case <-ctx.Done():
			return 0, ctx.Err()
		case <-time.After(toolPollInterval):
		}
	}
}

// tagToolBookFile stamps a merge output or split piece with the book's
// identity: album/title, contributors, genre, year, and the cover when
// the catalog resolves one. trackNo > 0 marks a split piece.
func (l *Library) tagToolBookFile(ctx context.Context, path string, bd *model.BookDetail, album, title string, trackNo int) error {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return fmt.Errorf("%w: parsing tool output %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	ed := doc.Edit().Set(tag.Album, album).Set(tag.Title, title)
	author := bd.Item.Artist
	if len(bd.Authors) > 0 {
		author = bd.Authors[0]
	}
	if author != "" {
		ed.Set(tag.Artist, author).Set(tag.AlbumArtist, author)
	}
	if len(bd.Narrators) > 0 {
		ed.Set(tag.Narrator, strings.Join(bd.Narrators, "; "))
	}
	if bd.Item.Genre != "" {
		ed.Set(tag.Genre, bd.Item.Genre)
	}
	if bd.Item.Year > 0 {
		ed.Set(tag.RecordingDate, strconv.Itoa(bd.Item.Year))
	}
	if trackNo > 0 {
		ed.Set(tag.TrackNumber, strconv.Itoa(trackNo))
	}
	l.addToolCover(ctx, ed, bd.Item.PID)
	return l.executeToolTagPlan(ctx, ed, path)
}

// tagToolTrackFile stamps one cue split piece from its virtual track's
// metadata.
func (l *Library) tagToolTrackFile(ctx context.Context, path string, seed *model.ItemView, title, artist string, trackNo int) error {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return fmt.Errorf("%w: parsing tool output %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	ed := doc.Edit().Set(tag.Title, title).Set(tag.TrackNumber, strconv.Itoa(trackNo))
	if artist != "" {
		ed.Set(tag.Artist, artist)
	}
	if seed.Album != "" {
		ed.Set(tag.Album, seed.Album)
	}
	if aa := firstNonEmpty(seed.AlbumArtist, seed.Artist); aa != "" {
		ed.Set(tag.AlbumArtist, aa)
	}
	if seed.Genre != "" {
		ed.Set(tag.Genre, seed.Genre)
	}
	if seed.Year > 0 {
		ed.Set(tag.RecordingDate, strconv.Itoa(seed.Year))
	}
	l.addToolCover(ctx, ed, seed.PID)
	return l.executeToolTagPlan(ctx, ed, path)
}

// toolCoverRung is the box a non-displayable cover is re-resolved at
// before it goes into a file: [ArtSizeToolCover], the ladder's top
// rung, so the embedded picture is the largest the resolver will
// re-encode rather than a thumbnail.
const toolCoverRung = ArtSizeToolCover

// addToolCover attaches the item's resolved cover art, best effort.
//
// The stored original is what goes in when a player can paint it. When
// it cannot - a TIFF, which the catalog decodes and no player draws -
// the resolve is asked for a rung instead, because a sized resolve
// re-encodes a non-displayable source into one that paints. What comes
// back still unpaintable is an exotic nothing could decode either, and
// that stays out of the file: a frame holding bytes the player renders
// as a broken image is worse than a file with no cover.
//
// Which of the two to ask for is decided before either is asked for.
// `ArtProvenance` answers what a resolve would return without loading
// the picture, and follows the same fallback chain, so the format is a
// row read rather than a stored original - up to sixteen megabytes -
// pulled and decoded only to be thrown away. This runs once per file a
// split writes, so on a library of TIFF covers that discarded read was
// per track.
func (l *Library) addToolCover(ctx context.Context, ed *waxlabel.Editor, pid model.PID) {
	ref := model.EntityRef{Type: model.ArtTrack, PID: pid}
	prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil || prov == nil {
		return
	}
	// Zero asks for the stored bytes; a rung asks for the re-encode.
	size := 0
	if !waxart.Displayable(prov.Format) {
		size = toolCoverRung
	}
	blob, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, size)
	if err != nil || blob == nil || len(blob.Bytes) == 0 {
		return
	}
	// Re-checked on what came back rather than trusted from the
	// provenance: a source the resolver could not re-encode comes back
	// as itself, and that is the exotic nothing can decode.
	if !waxart.Displayable(blob.Format) {
		return
	}
	// A cover artMime cannot name (an SVG a provider slipped in) stays
	// out of the file: octet-stream in a picture frame helps nobody.
	mime := artMime(blob.Format)
	if mime == "application/octet-stream" {
		return
	}
	ed.AddPicture(waxlabel.Picture{
		Type: waxlabel.PicFrontCover, MIME: mime,
		Width: blob.Width, Height: blob.Height, Data: blob.Bytes,
	})
}

// writeLanded says whether a SaveBack write reached the file. Committed is
// what answers that, not the error: an error with Committed set is a landed
// write whose post-commit step failed, so the bytes are in place and the plan
// is spent. A clean run with Committed clear is a no-op plan, which writes
// nothing by contract and is not a failure either.
func writeLanded(res waxlabel.SaveResult, err error) bool {
	return err == nil || res.Committed
}

func (l *Library) executeToolTagPlan(ctx context.Context, ed *waxlabel.Editor, path string) error {
	plan, err := ed.Prepare()
	if err != nil {
		return fmt.Errorf("%w: preparing tags for %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	if _, res, err := plan.Execute(ctx, waxlabel.SaveBack()); err != nil {
		if !writeLanded(res, err) {
			return fmt.Errorf("%w: writing tags to %s: %v", errToolPermanent, filepath.Base(path), err)
		}
		// The tags are on disk and the plan is spent, so wrapping this in
		// errToolPermanent would report a durable success as a dead task.
		l.log.Warn("tool tags written; post-commit step failed",
			"file", filepath.Base(path), "err", err)
	}
	return nil
}

// scanToolOutputs catalogs a book tool's outputs, placed in dir, each by
// its own path, so the scan catalogs them and nothing else, then resolves
// the book they formed: the one holding the first's exact bytes, else the
// original item when the identity key revived it (the kept-originals
// marker changes the key, so the copy stays its own book), else the book
// the (possibly marked) title names. A shutdown or a busy catalog ends it
// as it found it; any other failure comes after the files are in place,
// which no retry should repeat, since their sources may be in the trash.
func (l *Library) scanToolOutputs(ctx context.Context, dir string, files []string, oldPID model.PID, title string) (model.PID, error) {
	for _, file := range files {
		req := waxbin.ScanRequest{SubPath: file}
		if libPID, err := l.libraryForPath(ctx, file); err == nil && libPID != "" {
			req.LibraryPID = model.PID(libPID)
		}
		if err := l.toolScan(ctx, req); err != nil {
			if e := classifyMutation(err); catalogWaits(e) || ctx.Err() != nil {
				return "", e
			}
			return "", l.uncataloged(dir, "and the next scan of the library will catalog them: "+l.failureCause(classify(err).Error()))
		}
	}
	if hash, err := identity.ContentHash(files[0]); err == nil {
		if items, err := l.lib.ItemsByContentHash(ctx, hash); err == nil {
			for _, it := range items {
				if it.Kind == model.KindBook {
					return it.PID, nil
				}
			}
		}
	}
	if bd, err := l.lib.Book(ctx, oldPID); err == nil && len(bd.Files) == len(files) {
		return oldPID, nil
	}
	// Visible books only: the original the run trashed carries the same
	// title and is no answer.
	b := visibleItems().
		Where("kind", query.OpIs, string(model.KindBook)).
		Where("title", query.OpIs, title).Limit(1)
	items, err := l.lib.Query(ctx, b.Build(), "")
	if err != nil {
		if e := classify(err); catalogWaits(e) || ctx.Err() != nil {
			return "", e
		}
		return "", l.uncataloged(dir, "and were scanned, but their book could not be found: "+l.failureCause(classify(err).Error()))
	}
	if len(items) == 0 {
		return "", l.uncataloged(dir, "but the scan made no book of them")
	}
	return items[0].PID, nil
}

// toolItemFiles is a tool's read of an item's files, or what a test's
// mutateHook answers in its place.
func (l *Library) toolItemFiles(ctx context.Context, item model.PID) ([]model.ItemFileRef, error) {
	if l.mutateHook != nil {
		if err := l.mutateHook("files"); err != nil {
			return nil, err
		}
	}
	return l.lib.ItemFiles(ctx, item)
}

// toolScan is a tool's scan of a library, or what a test's mutateHook
// answers in its place.
func (l *Library) toolScan(ctx context.Context, req waxbin.ScanRequest) error {
	if l.mutateHook != nil {
		if err := l.mutateHook("scan"); err != nil {
			return err
		}
	}
	_, err := l.lib.Scan(ctx, req)
	return err
}

// catalogWaits reports whether a catalog failure passes on its own: a
// conflicting job holding the catalog, the catalog suspended for
// maintenance, or the attempt's own deadline or stop.
func catalogWaits(err error) bool {
	switch KindOf(err) {
	case KindCatalogBusy, KindMaintenance:
		return true
	}
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}

// uncataloged is a failure after a tool's files took their names in dir,
// saying what became of them.
func (l *Library) uncataloged(dir, what string) error {
	return fmt.Errorf("%w: the new files are in %s, %s", errToolPermanent, l.scrubStoragePaths(dir), what)
}

// toolCrashPoint is where a test may end a book tool's run, as a crash
// or a shutdown would.
func (l *Library) toolCrashPoint(step string) error {
	if l.toolStepHook != nil {
		return l.toolStepHook(step)
	}
	return nil
}

// toolWriteErr is a failed write of a tool's output into the library: a
// folder that refused it is the library's to fix, else the server's.
// Nothing was placed, so neither is worth a retry.
func (l *Library) toolWriteErr(err error) error {
	if cause := l.storageRefused(err.Error()); cause != "" {
		e := errStorageUnwritable(cause)
		e.Err = errToolPermanent
		return e
	}
	return &Error{Kind: KindInternal, Msg: "writing into the library failed: " + l.failureCause(err.Error()), Err: errToolPermanent}
}

// toolBookFolder is the folder a book tool writes title's files into,
// for a book named book whose files are in dir, in the library rooted at
// root: dir itself when it is named for the book and title is that name,
// else a folder named for title in the folder that holds the book's - the
// parent of a folder named for the book, or dir itself - which keeps a
// marked copy out of the original's folder and never leaves the library.
func toolBookFolder(root, dir, book, title string) string {
	home := dir
	if !samePath(dir, root) && strings.EqualFold(filepath.Base(dir), safeFileName(book)) {
		if strings.EqualFold(filepath.Base(dir), safeFileName(title)) {
			return dir
		}
		home = filepath.Dir(dir)
	}
	return filepath.Join(home, safeFileName(title))
}

// partsFolder is the deepest folder holding every part of a book, in the
// library rooted at root: the book's own folder above disc folders. Parts
// that share no folder inside the library answer the first part's.
func partsFolder(root string, parts []string) string {
	first := filepath.Dir(parts[0])
	if root == "" {
		root = first
	}
	dir := first
	for _, p := range parts[1:] {
		for !pathsOverlap(dir, p) {
			if samePath(dir, root) || dir == filepath.Dir(dir) {
				return first
			}
			dir = filepath.Dir(dir)
		}
	}
	return dir
}

// libraryNameOf is the name of the library holding path, or "".
func (l *Library) libraryNameOf(path string) string {
	root := l.storageRootFor(path)
	for _, r := range l.libraryRoots() {
		if root != "" && filepath.Clean(r.Path) == root {
			return r.Name
		}
	}
	return ""
}

// mergeFolder is where a book merge writes: beside the parts, or with the
// originals kept, a folder of its own beside the book.
func (l *Library) mergeFolder(parts []string, book string, keepOriginals bool) string {
	root := l.storageRootFor(parts[0])
	dir := partsFolder(root, parts)
	if !keepOriginals {
		return dir
	}
	return toolBookFolder(root, dir, book, book+mergedMark)
}

// splitFolder is where a book split writes its pieces: the book's folder
// when one is named for it, else a new folder named for the book beside
// its file, or with the original kept, a folder of their own beside it.
func (l *Library) splitFolder(src, book string, keepOriginals bool) string {
	title := book
	if keepOriginals {
		title += splitMark
	}
	return toolBookFolder(l.storageRootFor(src), filepath.Dir(src), book, title)
}

// The marks a kept original's copy carries in its title. The catalog
// identifies a book by author and title, so an unmarked copy would join
// the surviving original as more parts of the same item.
const (
	mergedMark = " (Merged)"
	splitMark  = " (Split)"
)

// probeToolFolders refuses a book tool when a folder it writes in will
// not take a file, before the task is queued and again before its trash
// runs: each folder named, or for one not made yet, the folder it would
// be made in.
func (l *Library) probeToolFolders(dirs ...string) error {
	seen := map[string]bool{}
	for _, dir := range dirs {
		for {
			if _, err := os.Stat(dir); !errors.Is(err, os.ErrNotExist) || dir == filepath.Dir(dir) {
				break
			}
			dir = filepath.Dir(dir)
		}
		if seen[dir] {
			continue
		}
		seen[dir] = true
		// Permanent for a task that probes as it runs: a folder that will
		// not take a file does not mend between attempts.
		if err := probeWritable(dir); err != nil {
			if cause := l.storageRefused(err.Error()); cause != "" {
				e := errStorageUnwritable(cause)
				e.Err = errToolPermanent
				return e
			}
			return &Error{Kind: KindInternal, Err: errToolPermanent,
				Msg: "the book's folder could not be written: " + l.failureCause(err.Error())}
		}
	}
	return nil
}

// resolveToolImport finds the item an applied plan produced for one
// staged path, through the plan action's essence (the same pattern the
// upload import uses).
func (l *Library) resolveToolImport(ctx context.Context, plan *inbox.Plan, src string) (model.PID, error) {
	essence := ""
	for _, a := range plan.Actions {
		if a.Src == src {
			essence = a.Essence
			break
		}
	}
	if essence == "" {
		return "", fmt.Errorf("%w: no essence recorded for %s", errToolPermanent, filepath.Base(src))
	}
	it, _, err := l.lib.ResolveRef(ctx, model.PortableRef{Essence: essence})
	if err != nil {
		return "", classify(err)
	}
	if it == nil {
		return "", fmt.Errorf("%w: imported piece %s did not resolve", errToolPermanent, filepath.Base(src))
	}
	return it.PID, nil
}

// toolPosition is one account's saved place in an item, with the time
// the catalog last recorded progress there. The carry writes the place
// back at that time rather than now, so a merged or split book keeps
// its rank on the in-progress shelf instead of jumping to the top.
type toolPosition struct {
	positionMS int64
	atNS       int64
}

// collectToolPositions reads every account's saved position for the
// given items; zero positions are omitted.
func (l *Library) collectToolPositions(ctx context.Context, items []model.PID) map[model.PID]map[model.PID]toolPosition {
	out := map[model.PID]map[model.PID]toolPosition{}
	l.forEachCatalogUser(ctx, func(userPID model.PID) {
		for _, item := range items {
			st, err := l.lib.Playback().State(ctx, userPID, item)
			if err != nil || st == nil || st.PositionMS <= 0 {
				continue
			}
			m := out[userPID]
			if m == nil {
				m = map[model.PID]toolPosition{}
				out[userPID] = m
			}
			m[item] = toolPosition{positionMS: st.PositionMS, atNS: st.LastProgressAt}
		}
	})
	return out
}

// asOf projects a carried position's recorded time onto the catalog's
// as-of argument; a state with no recorded progress stamps now.
func (p toolPosition) asOf() *int64 {
	if p.atNS <= 0 {
		return nil
	}
	return &p.atNS
}

// forEachCatalogUser pages every WaxDeck account and hands the catalog
// user pid of each to fn.
func (l *Library) forEachCatalogUser(ctx context.Context, fn func(model.PID)) {
	err := l.db.EachUser(ctx, func(u *wdb.User) error {
		if pid := l.catalogPID(u); pid != "" {
			fn(model.PID(pid))
		}
		return nil
	})
	if err != nil {
		l.log.Warn("listing users for position carry-over", "err", err)
	}
}

// ripFileOf answers the file a carved track plays a window of.
func (l *Library) ripFileOf(ctx context.Context, track model.PID) (model.PID, error) {
	files, err := l.lib.ItemFiles(ctx, track)
	if err != nil {
		return "", classify(err)
	}
	for _, f := range files {
		if f.Virtual && f.Role == fileRolePrimary {
			return f.FilePID, nil
		}
	}
	return "", &Error{Kind: KindConflict, Err: errToolPermanent, Msg: "the track is no longer cut from a rip"}
}

// cueRip answers the file a carved track plays a window of and every
// track the catalog carves from it, in start order, which a delete plan of
// that file lists.
func (l *Library) cueRip(ctx context.Context, seed *model.ItemView) (model.PID, []*model.ItemView, error) {
	file, err := l.ripFileOf(ctx, seed.PID)
	if err != nil {
		return "", nil, err
	}
	plan, err := l.lib.PlanDeleteFiles(ctx, []model.PID{file}, model.DeleteTrash)
	if err != nil {
		return "", nil, classify(err)
	}
	var pids []model.PID
	for _, a := range plan.Actions {
		pids = append(pids, a.Tracks...)
	}
	items, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return "", nil, classify(err)
	}
	byPID := map[model.PID]*model.ItemView{}
	for _, it := range items {
		if it != nil {
			byPID[it.PID] = it
		}
	}
	sibs := make([]*model.ItemView, 0, len(pids))
	for _, pid := range pids {
		if it := byPID[pid]; it != nil {
			sibs = append(sibs, it)
		}
	}
	return file, sibs, nil
}

// trashRip moves a cue rip's file to the catalog's trash with the tracks
// it carves as they stand now, under the cue split's reason.
func (l *Library) trashRip(ctx context.Context, file model.PID) error {
	plan, err := l.lib.PlanDeleteFiles(ctx, []model.PID{file}, model.DeleteTrash, waxbin.DeleteReason(taskTypeCueSplit))
	if err != nil {
		return classify(err)
	}
	if _, e := l.applyToolTrash(ctx, plan); e != nil {
		e.Msg += ", so the rip stays beside the tracks split from it"
		return e
	}
	return nil
}

// trashSyncedItems moves the tracks a mirror sync dropped to the trash
// and answers the items a file of which stayed: a run that moved nothing
// and failed is refused as a delete is, and a copy a read-only library
// holds keeps its item, as a delete leaves one.
func (l *Library) trashSyncedItems(ctx context.Context, pids []model.PID) (map[model.PID]bool, error) {
	plan, err := l.lib.PlanDeletePIDs(ctx, pids, model.DeleteTrash)
	if err != nil {
		return nil, classify(err)
	}
	rep, stayedFiles, err := l.applyDeletion(ctx, plan)
	if err != nil {
		return nil, err
	}
	if refused := l.deletionRefused(ctx, plan, rep, stayedFiles); refused != nil {
		return nil, refused
	}
	stayed := map[model.PID]bool{}
	for _, a := range plan.Actions {
		if _, ok := stayedFiles[a.FilePID]; ok {
			stayed[a.ItemPID] = true
		}
	}
	return stayed, nil
}

// applyToolTrash applies a tool's trash plan and answers how many files
// went, or why one stayed, which ends the task: a file that stayed would
// join what the tool writes beside it as one more part of the same book.
// A plan that would leave a file refuses before anything moves. The run
// is not cut short between files, which would move files no failure then
// names.
func (l *Library) applyToolTrash(ctx context.Context, plan *trash.Plan) (int, *Error) {
	for _, a := range plan.Actions {
		if a.Skip {
			return 0, &Error{Kind: KindConflict, Err: errToolPermanent,
				Msg: fmt.Sprintf("%s would stay where it is (%s)", libraryPath(a), a.Reason)}
		}
	}
	rep, stayed, err := l.applyDeletion(ctx, plan)
	if err != nil {
		// A busy or suspended catalog refused the run before it moved
		// anything, which a later attempt gets past.
		e := &Error{Kind: KindOf(err), Msg: "the move to the trash failed: " + l.failureCause(err.Error()), Err: err}
		if !catalogWaits(err) {
			e.Err = errToolPermanent
		}
		return 0, e
	}
	if len(stayed) == 0 {
		return rep.Trashed, nil
	}
	first, cause := "", ""
	for _, a := range plan.Actions {
		if why, ok := stayed[a.FilePID]; ok {
			first, cause = libraryPath(a), why
			break
		}
	}
	kind := KindInternal
	switch refusal := storageRefusal(cause); {
	case refusal != "":
		kind, cause = KindStorageUnwritable, refusal
	case cause == "library is read-only":
		kind = KindReadOnly
	case strings.HasPrefix(cause, "the cue rip's tracks changed"):
		kind = KindConflict
	}
	return rep.Trashed, &Error{Kind: kind, Err: errToolPermanent, Msg: fmt.Sprintf(
		"%d of %d files could not be moved to the trash (%s: %s)", len(stayed), len(plan.Actions), first, cause)}
}

// auditToolTask records a file tool's run under the account that queued
// it, by id, as a failed migration is: an account disabled or deleted
// since still ordered the run.
func (l *Library) auditToolTask(ctx context.Context, t *wdb.ToolTask, action string, target AuditTarget, detail map[string]any) {
	if t.UserID == "" {
		return
	}
	l.Audit(context.WithoutCancel(ctx), &UserCtx{ID: t.UserID}, action, target, detail)
}

// insertToolTask persists a queued task and notifies its audience.
func (l *Library) insertToolTask(ctx context.Context, uc *UserCtx, typ, itemPID string, p toolTaskParams) (ToolTaskDTO, error) {
	return l.insertToolTaskWith(ctx, uc, typ, itemPID, p, "")
}

// insertToolTaskWith is insertToolTask with a summary the task carries
// from the start, so its row can say what it is before it runs.
func (l *Library) insertToolTaskWith(ctx context.Context, uc *UserCtx, typ, itemPID string, p toolTaskParams, summary string) (ToolTaskDTO, error) {
	return l.queueToolTask(ctx, newToolTask(uc, typ, itemPID, p, summary))
}

// queueToolTask persists a queued task and notifies its audience.
func (l *Library) queueToolTask(ctx context.Context, t wdb.ToolTask) (ToolTaskDTO, error) {
	if err := l.db.InsertToolTask(ctx, t); err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.notifyToolTask(ctx, t.ID)
	return toolTaskDTO(t), nil
}

// newToolTask is a queued task row for uc.
func newToolTask(uc *UserCtx, typ, itemPID string, p toolTaskParams, summary string) wdb.ToolTask {
	return wdb.ToolTask{
		ID:          "tk-" + ulid.Make().String(),
		Type:        typ,
		State:       taskStateQueued,
		ItemPID:     itemPID,
		UserID:      uc.ID,
		Params:      marshalJSON(p),
		Summary:     summary,
		ResultPIDs:  "[]",
		CreatedAtNS: time.Now().UnixNano(),
	}
}

// taskUserCtx resolves a task's owner so a runner can audit under it.
// Nil when the account is gone or disabled, in which case the run still
// completes and only goes unaudited: the work is server maintenance, not
// something the account's continued existence should gate.
func (l *Library) taskUserCtx(ctx context.Context, userID string) *UserCtx {
	user, err := l.db.UserByID(ctx, userID)
	if err != nil || user.Disabled {
		return nil
	}
	uc, err := l.UserCtx(ctx, user)
	if err != nil {
		return nil
	}
	return uc
}

// failToolTask records a terminal failure, which a shutdown does not
// keep from the record.
func (l *Library) failToolTask(ctx context.Context, t *wdb.ToolTask, cause error) {
	ctx = context.WithoutCancel(ctx)
	l.log.Warn("a tool task failed", "task", t.ID, "type", t.Type, "err", cause)
	t.State = taskStateFailed
	t.Error = taskFailureText(cause)
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.UpdateToolTask(ctx, *t); err != nil {
		l.log.Warn("recording tool task failure", "task", t.ID, "err", err)
	}
	l.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	l.notifyFileToolEnd(ctx, t)
	l.toolTaskEnded(ctx, t)
}

// fileToolNames are the file tools by task type, as their starters read
// them: the tasks that work on the library's files and can park.
var fileToolNames = map[string]string{
	taskTypeBookMerge: "Book merge",
	taskTypeBookSplit: "Book split",
	taskTypeCueSplit:  "CUE split",
}

// notifyFileToolEnd files a merge or split that failed, or parked, in its
// starter's inbox, as a failed job is. The recorded failure names the
// server's paths, which only an administrator reads.
func (l *Library) notifyFileToolEnd(ctx context.Context, t *wdb.ToolTask) {
	name, ok := fileToolNames[t.Type]
	if !ok || t.UserID == "" {
		return
	}
	title := name + " failed"
	if t.State == taskStateParked {
		title = name + " needs attention"
	}
	if t.ItemTitle != "" {
		title += ": " + t.ItemTitle
	}
	body := cmp.Or(t.Error, "no reason was recorded")
	u, err := l.db.UserByID(ctx, t.UserID)
	var uc *UserCtx
	if err == nil {
		uc, err = l.UserCtx(ctx, u)
	}
	switch {
	case err != nil:
		body = l.failureWordsFor(&UserCtx{}, body)
	case !uc.Admin:
		body = l.failureWordsFor(uc, body)
	}
	// The which-one goes in the body, as a failed job's does: a client
	// heads the row with its own words for the event.
	subject := name
	if t.ItemTitle != "" {
		subject += " of " + t.ItemTitle
	}
	l.EmitNotificationFor(ctx, "tool-task-failed", title, subject+": "+body, t.ID, []string{t.UserID})
}

// taskOpName is an operation name a library threads onto its errors: a
// dotted one ("jobs.Run", "meta.Writer.Apply") or a sibling's own.
var taskOpName = regexp.MustCompile(`^(?:[A-Za-z]\w*(?:\.\w+)+|waxtap|waxbin|waxflow|waxlabel|waxseal)$`)

// siblings are the libraries whose names begin their own operations'.
var siblings = map[string]bool{"waxtap": true, "waxbin": true, "waxflow": true, "waxlabel": true, "waxseal": true}

// namedEnds are the last parts that make a dotted name a file's or a
// host's, which say what failed: a file's extension or a domain's.
var namedEnds = map[string]bool{
	"jpg": true, "jpeg": true, "png": true, "gif": true, "webp": true, "bmp": true, "tif": true,
	"tiff": true, "avif": true, "heic": true, "svg": true, "cue": true, "lrc": true, "txt": true,
	"nfo": true, "json": true, "xml": true, "yaml": true, "yml": true, "m3u": true, "m3u8": true,
	"pls": true, "xspf": true, "log": true, "pdf": true, "epub": true, "sfv": true, "md5": true,
	"ffp": true, "accurip": true, "srt": true, "vtt": true, "zip": true, "rar": true, "7z": true,
	"tar": true, "gz": true, "part": true, "html": true, "htm": true, "csv": true,
	"com": true, "org": true, "net": true, "io": true, "fm": true, "dev": true, "app": true,
	"co": true, "uk": true, "de": true, "fr": true, "info": true, "tv": true, "me": true,
	"eu": true, "ca": true, "au": true, "nl": true, "jp": true,
}

// opName reports whether a part of a failure is an operation's name: a
// sibling's, or one shaped like it that names no file or host.
func opName(p string) bool {
	if !taskOpName.MatchString(p) {
		return false
	}
	first, _, dotted := strings.Cut(p, ".")
	if !dotted || siblings[first] {
		return true
	}
	return !scan.IsAudio(p) && !namedEnds[strings.ToLower(p[strings.LastIndexByte(p, '.')+1:])]
}

// taskFailureText is what a failed task records: the failure's own
// words, without the operation names a library threads onto it or the
// permanence marker. The server's paths stay for an administrator to
// read; toolTaskFor cuts them for anyone else.
func taskFailureText(cause error) string {
	s := waxDetail(cause)
	if s == "" {
		s = strings.TrimPrefix(cause.Error(), errToolPermanent.Error()+": ")
	}
	return withoutOpNames(s)
}

// withoutOpNames drops the operation names leading s or any part of it
// after a ": ". A file's or a host's name reads like one ("part1.mp3:
// ...", "example.com: ...") and stays: it says what failed. The last
// part is the message itself.
func withoutOpNames(s string) string {
	parts := strings.Split(s, ": ")
	out := parts[:0]
	for i, p := range parts {
		if i < len(parts)-1 && opName(p) {
			continue
		}
		out = append(out, p)
	}
	return strings.Join(out, ": ")
}

// failureWords is a recorded failure's text for someone who is not an
// administrator: without the operation names a library threads onto it
// and without the server's storage paths.
func (l *Library) failureWords(s string) string {
	return l.scrubStoragePaths(withoutOpNames(s))
}

// toolTaskFor is a task as the caller may read it: its recorded failure
// names the server's paths, which only an administrator reads.
func (l *Library) toolTaskFor(uc *UserCtx, t wdb.ToolTask) ToolTaskDTO {
	dto := toolTaskDTO(t)
	if !uc.Admin {
		dto.Error = l.failureWords(dto.Error)
	}
	return dto
}

// toolTaskEnded is what a task's end tells beyond its own marker, once
// the end is recorded.
func (l *Library) toolTaskEnded(ctx context.Context, t *wdb.ToolTask) {
	if t.Type == taskTypeHealthFix {
		l.healthFixTaskEnded(ctx, t)
	}
}

// scrubTaskSecrets drops sealed credentials from a terminal task's
// params: a finished import has no further use for them, and holding
// them indefinitely widens what a database-plus-keyfile exposure leaks.
// Sealed rows are unreadable without the key either way; this bounds
// the lifetime to the task's own, which is what the API documents.
func (l *Library) scrubTaskSecrets(ctx context.Context, taskID string) {
	t, err := l.db.ToolTaskByID(ctx, taskID)
	if err != nil || !strings.HasPrefix(t.Type, taskTypeMigratePrefix) {
		return
	}
	var params map[string]any
	if err := json.Unmarshal([]byte(t.Params), &params); err != nil {
		return
	}
	_, sealed := params["secretSealed"]
	// The export id goes only once the archive it names is gone. A task
	// naming an upload that was deleted reads as a thing somebody could
	// still act on; a task naming one that is still there is the only
	// handle left on it, because the screen that ordered the import let
	// go of its own as soon as the task was accepted. A dry run keeps
	// the archive on purpose, and so does a failure and a run told to
	// read only half of it - scrubbing the id from those stranded a
	// household's listening history until its day was up.
	dropExport := false
	if id, ok := params["exportId"].(string); ok && id != "" {
		_, err := l.db.MigrationExportByID(ctx, id)
		dropExport = errors.Is(err, wdb.ErrNotFound)
	}
	if !sealed && !dropExport {
		return
	}
	delete(params, "secretSealed")
	if dropExport {
		delete(params, "exportId")
	}
	raw, err := json.Marshal(params)
	if err != nil {
		return
	}
	if err := l.db.UpdateToolTaskParams(ctx, t.ID, string(raw)); err != nil {
		l.log.Warn("scrubbing task credentials", "task", t.ID, "err", err)
	}
}

// notifyToolTask fans a task lifecycle change out to its owner and
// every enabled administrator, deduplicated by account.
func (l *Library) notifyToolTask(ctx context.Context, taskID string) {
	l.markToolTask(ctx, taskID, eventTask)
}

// notifyToolTaskProgress tells the same watchers a task's progress moved,
// which refreshes their lists and is not news.
func (l *Library) notifyToolTaskProgress(ctx context.Context, taskID string) {
	l.markToolTask(ctx, taskID, eventTaskProgress)
}

func (l *Library) markToolTask(ctx context.Context, taskID, kind string) {
	seen := map[string]bool{}
	if t, err := l.db.ToolTaskByID(ctx, taskID); err == nil && t.UserID != "" {
		seen[t.UserID] = true
		l.emitUserEvent(ctx, t.UserID, kind, taskID)
	}
	admins, err := l.db.EnabledAdminIDs(ctx)
	if err != nil {
		return
	}
	for _, id := range admins {
		if !seen[id] {
			seen[id] = true
			l.emitUserEvent(ctx, id, kind, taskID)
		}
	}
}

// toolProgress mirrors a task's progress to the store in five percent
// steps, telling the task's watchers each time. The run's hold on the
// task keeps its lease.
type toolProgress struct {
	l       *Library
	t       *wdb.ToolTask
	lastPct float64
}

func newToolProgress(l *Library, t *wdb.ToolTask) *toolProgress {
	return &toolProgress{l: l, t: t}
}

func (tp *toolProgress) report(ctx context.Context, pct float64) {
	if pct-tp.lastPct >= 5 {
		tp.lastPct = pct
		tp.t.ProgressPct = pct
		if err := tp.l.db.UpdateToolTask(ctx, *tp.t); err != nil {
			tp.l.log.Warn("recording tool task progress", "task", tp.t.ID, "err", err)
		} else {
			tp.l.notifyToolTaskProgress(ctx, tp.t.ID)
		}
	}
}

// toolWorkspace creates the task's scratch directory under staging.
func (l *Library) toolWorkspace(taskID string) (string, error) {
	dir := filepath.Join(l.stagingDir, "tools", taskID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	return dir, nil
}

// permanentToolErr reports whether a failure is worth retrying: engine
// refusals (4xx), catalog validation errors, and job-level failures are
// permanent; transport trouble and timeouts are not.
func permanentToolErr(err error) bool {
	if errors.Is(err, errToolPermanent) {
		return true
	}
	if flow.PermanentJobErr(err) {
		return true
	}
	switch KindOf(err) {
	case KindInvalid, KindConflict, KindNotFound, KindFormat:
		return true
	}
	return false
}

func toolTaskDTO(t wdb.ToolTask) ToolTaskDTO {
	var results []string
	if t.ResultPIDs != "" {
		_ = json.Unmarshal([]byte(t.ResultPIDs), &results)
	}
	var summary map[string]any
	if t.Summary != "" {
		_ = json.Unmarshal([]byte(t.Summary), &summary)
	}
	dto := ToolTaskDTO{
		ID: t.ID, Type: t.Type, State: t.State, ItemPID: t.ItemPID, ItemTitle: t.ItemTitle,
		ProgressPct: t.ProgressPct, Error: t.Error, ResultPIDs: results,
		Summary:     summary,
		CreatedAtNS: t.CreatedAtNS, FinishedAtNS: t.FinishedAtNS,
	}
	if t.State == taskStateRunning && t.WaitReason != "" {
		dto.WaitReason, dto.RetryAtNS = t.WaitReason, t.LeaseUntilNS
	}
	if (t.Type == taskTypeBookMerge || t.Type == taskTypeBookSplit) && (t.State == taskStateRunning || t.State == taskStateParked) {
		// While the run's trash holds the book: from its trash to its new
		// files cataloged, or put back. Kept originals never went, and
		// sources gone from the trash for good are in it no longer.
		var p toolTaskParams
		if json.Unmarshal([]byte(t.Params), &p) == nil && !p.KeepOriginals && p.TrashFromNS != 0 && !p.Forward {
			switch p.Step {
			case toolStepTrashing, toolStepPlacing, toolStepUndoing:
				dto.BookInTrash = true
			}
		}
	}
	return dto
}

// chapterTitle falls back to a generated name for an unnamed chapter.
func chapterTitle(title string, index int) string {
	if strings.TrimSpace(title) != "" {
		return title
	}
	return fmt.Sprintf("Chapter %d", index+1)
}

// toolSplitFormat picks the engine output format that keeps a split as
// faithful as possible: the source codec when the engine can write it,
// else FLAC (lossless in the decoded samples for any source).
//
// WavPack and Monkey's Audio are here even though neither streams: a
// split is a job that writes a file, and APE's want of a live form only
// rules it out of the delivery ladder.
func toolSplitFormat(codec string) string {
	switch c := strings.ToLower(codec); c {
	case "flac", "alac", "aac", "mp3", "opus", "wav", "wavpack", "ape":
		return c
	default:
		return "flac"
	}
}

// toolSplitExt is the file extension a split piece takes for one output
// format. Most format names are the extension, but not all - WavPack
// writes .wv - and a piece named for the format instead lands outside
// the scanner's extension set, so the import that follows finds nothing
// and the whole job fails permanently after encoding every piece.
//
// The mp4 family is the other exception, in the other direction: aac
// and alac pieces of a book take .m4b so the rescan classifies them as
// audiobook parts. Callers splitting a track pass that off.
func toolSplitExt(format string, mp4AsBook bool) string {
	if mp4AsBook && (format == "aac" || format == "alac") {
		return "m4b"
	}
	switch format {
	case "wavpack":
		return "wv"
	default:
		return format
	}
}

// ownCueSheet is the sheet of a rip's own name beside it, the only one
// the catalog carves the rip by, and whether it is there.
func ownCueSheet(rip string) (string, bool) {
	cue := strings.TrimSuffix(rip, filepath.Ext(rip)) + ".cue"
	_, err := os.Stat(cue)
	return cue, err == nil
}

// safeFileName keeps a display title usable as a file name.
func safeFileName(s string) string {
	s = strings.Map(func(r rune) rune {
		switch r {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|':
			return '_'
		}
		if r < 0x20 {
			return -1
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if s == "" {
		return "untitled"
	}
	const maxName = 120
	if len(s) > maxName {
		s = s[:maxName]
	}
	return s
}
