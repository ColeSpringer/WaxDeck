package service

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
)

// Tools is file tooling: book merges and splits, CUE splits, skip maps
// and the trash, and the task queue every long server task runs on.
type Tools struct {
	*core
	// deletePlanHook runs between a delete's read of its items' files
	// and its plan, and deleteApplyHook between a plan and its apply, in
	// a test; nothing in the server sets them.
	deletePlanHook  func(context.Context)
	deleteApplyHook func(context.Context)
	// toolStepHook runs as a book tool passes each step of a run, and an
	// error it answers ends the run there, as a crash or a shutdown would,
	// in a test; nothing in the server sets it.
	toolStepHook func(step string) error
	// mutateHook stands in for the answer of a tool's catalog mutation
	// (its trash, its scan, its import) in a test, a busy catalog say;
	// nil lets the call through. Nothing in the server sets it.
	mutateHook func(op string) error
	// toolLeaseEvery is how often a run renews its task's lease; zero is
	// toolLeaseRenew. A test shortens it.
	toolLeaseEvery time.Duration
	// toolRunBound stands in for the bound of every attempt that has one,
	// in a test; zero keeps each type's. Nothing in the server sets it.
	toolRunBound time.Duration
	// toolRuns are the runs this process holds on each task, which the
	// retire pass leaves whatever their leases say, and what each is doing.
	toolRunsMu sync.Mutex
	toolRuns   map[string]*taskRun
	// settleLocks keep two settles of one ended task (its cancel or
	// retire, the startup pass, a clear) from running side by side, one
	// lock a task, so no settle waits on another task's.
	settleLocks sessionLocks
	// settleHook runs as a settle of a task starts its steps, in a test;
	// nothing in the server sets it.
	settleHook func(taskID string)
	// activityHook sees each activity a run here records, in a test;
	// nothing in the server sets it.
	activityHook func(taskID string, a ToolTaskActivity)
	// drainHook runs as the drain passes a point of a task's run, "leased"
	// before the run holds it and "ran" once the run let it go, in a test;
	// nothing in the server sets it.
	drainHook func(point, taskID string)
	// markHook runs as a marker scheduled off a source's report is sent,
	// in a test; nothing in the server sets it.
	markHook func(taskID string)
	// markWake wakes the marker worker (RunTaskMarkers) when a marker
	// waits.
	markWake chan struct{}
	// flowJobs is the streaming sidecar's analysis surface, wired after
	// construction (the bridge needs this service as its resolver).
	flowJobs FlowJobs
	// markMissingHook stands in for the catalog's mark-missing of an item
	// whose audio the analysis worker found gone, in a test; nothing in
	// the server sets it.
	markMissingHook func(context.Context, model.PID) (model.MarkMissingOutcome, error)
}

func newTools(c *core, _ Config) *Tools { return &Tools{core: c, markWake: make(chan struct{}, 1)} }

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
	// taskStateCanceled is a task stopped because it was asked to, which
	// finished as a failed one did.
	taskStateCanceled = "canceled"

	// toolTaskLease bounds one attempt between renewals; a run renews
	// it for as long as it holds the task (holdToolTask), so the lease
	// only expires when the worker dies.
	toolTaskLease       = 5 * time.Minute
	toolTaskMaxAttempts = 3
	toolLeaseRenew      = time.Minute
	toolPollInterval    = 2 * time.Second
	// toolRunTimeout bounds one whole attempt; a wedged engine job
	// surfaces as a transient failure and the attempts machinery
	// retries or retires the task. An acquisition's or a sync's listing
	// takes the same bound.
	toolRunTimeout = 30 * time.Minute
	// toolSourceWaits is how often an acquisition or a sync waits on its
	// source before it fails.
	toolSourceWaits = 3
)

// toolRunTimeoutFor is one attempt's bound for a task type; zero for an
// acquisition or a sync, whose listing and each item are bounded instead.
func toolRunTimeoutFor(typ string) time.Duration {
	switch typ {
	case taskTypeHealthFix:
		return healthFixTimeout
	case taskTypeCatalogRepair:
		return catalogRepairTimeout
	case taskTypeAcquire, taskTypePlaylistSync:
		return 0
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
	// ErrorCode and ErrorParams say why a failed task failed as a client
	// words it: an API error code and its params.
	ErrorCode   string
	ErrorParams map[string]string
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
	// Activity is what a running task is doing, while this process runs
	// it; nil otherwise.
	Activity *ToolTaskActivity
	// CancelRequested says a running task was asked to cancel and winds
	// down.
	CancelRequested bool
}

// ToolTaskActivity is what a running task is doing right now: its phase,
// its items done of all it has, the item in hand and that item's bytes,
// and when it last did anything.
type ToolTaskActivity struct {
	Phase      string
	ItemsDone  int
	ItemsTotal int
	ItemTitle  string
	BytesDone  int64
	BytesTotal int64
	AtNS       int64
	// pctShare is the share of progressPct a run's items fill, for one
	// whose progress is its items plus the bytes of the item in hand.
	pctShare float64
}

// fetchedItem is an item an acquisition or a sync staged: the source's
// entry id (the item's link when it has none) and its upload session.
// Dropped is a download the person removed before its entry opened, which
// no later run fetches again.
type fetchedItem struct {
	Key     string `json:"key"`
	Upload  string `json:"upload"`
	Dropped bool   `json:"dropped,omitempty"`
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
	// Discarded is set once the run gave up what it made: whatever of it
	// stays (in Created) is removed by a clear, never named.
	Discarded bool `json:"discarded,omitempty"`
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
	// AcceptBest carries whether those entries take their best match
	// without review.
	AcceptBest bool `json:"acceptBest,omitempty"`
	// Shape is what the check before queuing decided the link names (a
	// syncsource shape), and the path the run takes; empty for a provider
	// that cannot check. Playlist is the request's choice of the list over
	// the video, and SourceTitle the title the check read.
	Shape       string `json:"shape,omitempty"`
	Playlist    bool   `json:"playlist,omitempty"`
	SourceTitle string `json:"sourceTitle,omitempty"`
	// SourceWaits counts the waits on the source an acquisition or a sync
	// took; Fetched is what its runs staged, which a later run skips;
	// Entries are the review entries they opened, and ListTitle the title
	// of the list they fetched from. Truncated says an acquisition's
	// listing ran past the cap.
	SourceWaits int           `json:"sourceWaits,omitempty"`
	Fetched     []fetchedItem `json:"fetched,omitempty"`
	Entries     []string      `json:"entries,omitempty"`
	ListTitle   string        `json:"listTitle,omitempty"`
	Truncated   bool          `json:"truncated,omitempty"`
	// Playlist-sync field: the API pid of the bound playlist to sync.
	PlaylistPID string `json:"playlistPid,omitempty"`
	// Asked marks a sync the person started (Sync now), not the sweep: only
	// its failure tells them.
	Asked bool `json:"asked,omitempty"`
	// Health-fix fields: the rule, and the bare item pids to fix (none
	// is every item failing it when the task runs). PathFix is how far a
	// path fix has gone.
	Rule     string           `json:"rule,omitempty"`
	ItemPIDs []string         `json:"itemPids,omitempty"`
	PathFix  *pathFixProgress `json:"pathFix,omitempty"`
}
