package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// File tooling: audiobook merge to a chaptered single file, chapter
// split into per-chapter files, and CUE rip split into real per-track
// files, all cut by the streaming engine's jobs surface and re-imported
// through the catalog's own planner. Tasks persist in tool_tasks and
// run on the supervised drain worker; lifecycle changes fan out on the
// task event kind to the owner and every administrator.

const (
	taskTypeBookMerge = "book-merge"
	taskTypeBookSplit = "book-split"
	taskTypeCueSplit  = "cue-split"

	taskStateQueued = "queued"
	taskStateDone   = "done"
	taskStateFailed = "failed"

	// toolTaskLease bounds one attempt between renewals; the poll loop
	// renews while a long engine job runs, so the lease only expires
	// when the worker dies.
	toolTaskLease       = 5 * time.Minute
	toolTaskMaxAttempts = 3
	toolLeaseRenew      = time.Minute
	toolPollInterval    = 2 * time.Second
	// toolRunTimeout bounds one whole attempt; a wedged engine job
	// surfaces as a transient failure and the attempts machinery
	// retries or retires the task.
	toolRunTimeout = 30 * time.Minute
)

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
	ProgressPct float64
	Error       string
	ResultPIDs  []string
	// Summary is the task-type-specific result document once finished.
	Summary      map[string]any
	CreatedAtNS  int64
	FinishedAtNS int64
}

// toolTaskParams is the persisted work order, captured at creation so
// the worker never depends on catalog state that may shift under it.
type toolTaskParams struct {
	KeepOriginals bool `json:"keepOriginals"`
	// Merge fields.
	Titles          []string `json:"titles,omitempty"`
	PartPaths       []string `json:"partPaths,omitempty"`
	PartDurationsMS []int64  `json:"partDurationsMs,omitempty"`
	// Split fields (book and cue).
	SrcPath     string   `json:"srcPath,omitempty"`
	Format      string   `json:"format,omitempty"`
	Cuts        []int64  `json:"cuts,omitempty"`
	PieceTitles []string `json:"pieceTitles,omitempty"`
	CuePath     string   `json:"cuePath,omitempty"`
	// Acquisition fields.
	URL        string `json:"url,omitempty"`
	MediaType  string `json:"mediaType,omitempty"`
	LibraryPID string `json:"libraryPid,omitempty"`
}

// StartBookMerge queues a merge of a multi-file audiobook into one
// chaptered file. Administrators only.
func (l *Library) StartBookMerge(ctx context.Context, uc *UserCtx, apiBookPID string, titles []string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, &Error{Kind: KindFeature, Msg: "book merging needs the streaming engine"}
	}
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if len(bd.Files) < 2 {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "the book is already a single file"}
	}
	if len(titles) > 0 && len(titles) != len(bd.Files) {
		return ToolTaskDTO{}, errInvalid(fmt.Sprintf(
			"titles has %d entries for %d parts; one per part, or none", len(titles), len(bd.Files)))
	}
	paths := make([]string, len(bd.Files))
	durs := make([]int64, len(bd.Files))
	for i, f := range bd.Files {
		file, err := l.lib.File(ctx, f.FilePID)
		if err != nil {
			return ToolTaskDTO{}, classify(err)
		}
		paths[i] = string(file.Path)
		durs[i] = f.DurationMS
	}
	if err := l.checkPathWritable(ctx, paths[0]); err != nil {
		return ToolTaskDTO{}, err
	}
	return l.insertToolTask(ctx, uc, taskTypeBookMerge, apiPID(PrefixBook, bd.Item.PID), toolTaskParams{
		KeepOriginals: keepOriginals, Titles: titles, PartPaths: paths, PartDurationsMS: durs,
	})
}

// StartBookSplit queues a split of a single-file audiobook at its
// chapter marks. Administrators only.
func (l *Library) StartBookSplit(ctx context.Context, uc *UserCtx, apiBookPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, &Error{Kind: KindFeature, Msg: "book splitting needs the streaming engine"}
	}
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if len(bd.Files) >= 2 {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "the book is already split across files; merge it first"}
	}
	if len(bd.Chapters) == 0 {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "the book has no chapters to split at"}
	}
	loc, err := l.paths.Locate(ctx, bd.Item.PID)
	if err != nil {
		return ToolTaskDTO{}, classify(err)
	}
	if err := l.checkPathWritable(ctx, loc.Path); err != nil {
		return ToolTaskDTO{}, err
	}
	rate := loc.SampleRate
	if rate <= 0 {
		rate = bd.Item.SampleRate
	}
	if rate <= 0 {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "the file declares no sample rate to place cuts by"}
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
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: "the chapter marks yield no interior cut points"}
	}
	return l.insertToolTask(ctx, uc, taskTypeBookSplit, apiPID(PrefixBook, bd.Item.PID), toolTaskParams{
		KeepOriginals: keepOriginals, SrcPath: loc.Path,
		Format: toolSplitFormat(bd.Item.Codec), Cuts: cuts, PieceTitles: titles,
	})
}

// StartCueSplit queues a physical split of the single-file rip behind a
// CUE-carved album; the pid may be any of the rip's virtual tracks.
// Administrators only.
func (l *Library) StartCueSplit(ctx context.Context, uc *UserCtx, apiTrackPID string, keepOriginals bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return ToolTaskDTO{}, &Error{Kind: KindFeature, Msg: "cue splitting needs the streaming engine"}
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
	cue, err := findCueSheet(loc.Path)
	if err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindConflict, Msg: err.Error()}
	}
	if err := l.checkPathWritable(ctx, loc.Path); err != nil {
		return ToolTaskDTO{}, err
	}
	return l.insertToolTask(ctx, uc, taskTypeCueSplit, apiPID(PrefixTrack, it.PID), toolTaskParams{
		KeepOriginals: keepOriginals, SrcPath: loc.Path, CuePath: cue,
		Format: toolSplitFormat(it.Codec),
	})
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
		out = append(out, toolTaskDTO(r))
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
	return toolTaskDTO(t), nil
}

// DrainToolTasks retires exhausted tasks and works one leased task;
// false means the queue is idle so the caller can sleep.
func (l *Library) DrainToolTasks(ctx context.Context) bool {
	now := time.Now().UnixNano()
	if ids, err := l.db.FailExhaustedToolTasks(ctx, now, toolTaskMaxAttempts); err != nil {
		l.log.Warn("retiring exhausted tool tasks", "err", err)
	} else {
		for _, id := range ids {
			l.scrubTaskSecrets(ctx, id)
			l.notifyToolTask(ctx, id)
		}
	}
	row, err := l.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts)
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
	runCtx, cancel := context.WithTimeout(ctx, toolRunTimeout)
	err = l.runToolTask(runCtx, &row)
	cancel()
	if err != nil {
		if permanentToolErr(err) || row.Attempts >= toolTaskMaxAttempts {
			l.failToolTask(ctx, &row, err)
		} else {
			// Transient (engine unreachable, timeout): the row stays
			// leased and untouched; the lease expires and the attempts
			// machinery re-runs it, or FailExhaustedToolTasks retires it.
			l.log.Warn("tool task attempt failed", "task", row.ID, "type", row.Type,
				"attempt", row.Attempts, "err", err)
		}
	}
	return true
}

// runToolTask executes one leased task to completion.
func (l *Library) runToolTask(ctx context.Context, t *wdb.ToolTask) error {
	var p toolTaskParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
		return fmt.Errorf("%w: bad task params: %v", errToolPermanent, err)
	}
	switch t.Type {
	case taskTypeBookMerge, taskTypeBookSplit, taskTypeCueSplit:
		if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
			// Transient by design: the engine was present at creation
			// and may come back before the attempts budget runs out.
			// Acquisitions never need the engine, so the gate is
			// per-type.
			return errors.New("streaming engine unavailable")
		}
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
	case t.Type == taskTypeGenreNormalize:
		err = l.runGenreNormalize(ctx, t)
	case strings.HasPrefix(t.Type, taskTypeMigratePrefix):
		err = l.runMigrationTask(ctx, t)
	default:
		err = fmt.Errorf("%w: unknown task type %q", errToolPermanent, t.Type)
	}
	if err != nil {
		return err
	}
	t.State = taskStateDone
	t.ProgressPct = 100
	t.Error = ""
	t.ResultPIDs = marshalJSON(results)
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.UpdateToolTask(ctx, *t); err != nil {
		l.log.Warn("recording tool task completion", "task", t.ID, "err", err)
	}
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	return nil
}

// runBookMerge joins a multi-file book into one chaptered M4B.
func (l *Library) runBookMerge(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	_, oldPID, ok := parseAPIPID(t.ItemPID)
	if !ok {
		return nil, fmt.Errorf("%w: bad item pid %q", errToolPermanent, t.ItemPID)
	}
	bd, err := l.lib.Book(ctx, oldPID)
	if err != nil {
		return nil, classify(err)
	}
	// Format aac on purpose: any mix of part codecs merges, and the
	// resolved flat MP4 form is the one that carries the chapter track.
	// The cost is a transcode even when every part is already AAC; the
	// bridge documents the trade.
	jobID, err := l.flowJobs.CreateMergeJob(ctx, p.PartPaths, p.Titles, "aac")
	if err != nil {
		return nil, err
	}
	if _, err := l.pollToolJob(ctx, t, jobID, 1); err != nil {
		return nil, err
	}
	ws, err := l.toolWorkspace(t.ID)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(ws)
	title := bd.Item.Title
	if p.KeepOriginals {
		// The catalog identifies a book by author and title (plus any
		// ASIN/ISBN/edition). An unmarked merged copy would join the
		// surviving original as one more part of the same item, so the
		// kept-originals form gets a visible marker instead.
		title += " (Merged)"
	}
	merged := filepath.Join(ws, safeFileName(title)+".m4b")
	if err := l.flowJobs.DownloadJobResult(ctx, jobID, 0, merged); err != nil {
		return nil, err
	}
	// The engine deliberately carries no source tags, so the book's
	// richer identity and its cover are stamped in a post-pass.
	if err := l.tagToolBookFile(ctx, merged, bd, title, title, 0); err != nil {
		return nil, err
	}
	// Read every user's resume point before anything moves: a
	// multi-file book's position is already a book-timeline millisecond
	// by the catalog's contract, so it carries onto the merged single
	// file unchanged.
	positions := l.collectToolPositions(ctx, []model.PID{oldPID})
	if !p.KeepOriginals {
		// Trash before import: the merged file shares the original's
		// identity key, and importing first would attach it to the old
		// item as an extra part. A post-trash import failure leaves the
		// originals restorable from the trash journal.
		if err := l.trashToolItems(ctx, []model.PID{oldPID}); err != nil {
			return nil, err
		}
	}
	newPID, err := l.importToolFile(ctx, merged, model.KindBook)
	if err != nil {
		return nil, err
	}
	for userPID, byItem := range positions {
		if pos := byItem[oldPID]; pos > 0 {
			if err := l.lib.Playback().Checkpoint(ctx, userPID, newPID, pos); err != nil {
				l.log.Warn("carrying merge resume position", "user", string(userPID), "err", err)
			}
		}
	}
	return []string{apiPID(PrefixBook, newPID)}, nil
}

// runBookSplit cuts a single-file book at its chapter marks and imports
// the pieces as one multi-file book.
func (l *Library) runBookSplit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	_, oldPID, ok := parseAPIPID(t.ItemPID)
	if !ok {
		return nil, fmt.Errorf("%w: bad item pid %q", errToolPermanent, t.ItemPID)
	}
	bd, err := l.lib.Book(ctx, oldPID)
	if err != nil {
		return nil, classify(err)
	}
	jobID, err := l.flowJobs.CreateSplitJob(ctx, p.SrcPath, p.Cuts, "", p.Format)
	if err != nil {
		return nil, err
	}
	outs, err := l.pollToolJob(ctx, t, jobID, len(p.Cuts)+1)
	if err != nil {
		return nil, err
	}
	ws, err := l.toolWorkspace(t.ID)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(ws)
	title := bd.Item.Title
	if p.KeepOriginals {
		// Same identity-key rule as the merge: unmarked pieces would
		// join the surviving single-file original as extra parts.
		title += " (Split)"
	}
	bookDir := filepath.Join(ws, safeFileName(title))
	if err := os.MkdirAll(bookDir, 0o755); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// Pieces of an mp4-family split keep the .m4b extension so the
	// rescan classifies them as audiobook parts; other codecs rely on
	// the narrator tag stamped below.
	ext := "." + p.Format
	if p.Format == "aac" || p.Format == "alac" {
		ext = ".m4b"
	}
	pieces := make([]string, 0, outs)
	for i := 0; i < outs; i++ {
		pieceTitle := chapterTitle("", i)
		if i < len(p.PieceTitles) {
			pieceTitle = p.PieceTitles[i]
		}
		dst := filepath.Join(bookDir, fmt.Sprintf("%02d - %s%s", i+1, safeFileName(pieceTitle), ext))
		if err := l.flowJobs.DownloadJobResult(ctx, jobID, i, dst); err != nil {
			return nil, err
		}
		if err := l.tagToolBookFile(ctx, dst, bd, title, pieceTitle, i+1); err != nil {
			return nil, err
		}
		pieces = append(pieces, dst)
	}
	positions := l.collectToolPositions(ctx, []model.PID{oldPID})
	if !p.KeepOriginals {
		if err := l.trashToolItems(ctx, []model.PID{oldPID}); err != nil {
			return nil, err
		}
	}
	// The pieces bypass the import planner on purpose: its audiobook
	// layout renders one title-named destination per BOOK, so a second
	// part of the same book always collides and quarantines. They are
	// placed directly with the multi-part directory convention (a
	// folder named for the book, parts ordered by file name) and
	// cataloged by a scoped synchronous scan.
	destDir := filepath.Join(filepath.Dir(p.SrcPath), safeFileName(title))
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	for _, piece := range pieces {
		if err := copyToolFile(piece, filepath.Join(destDir, filepath.Base(piece))); err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
	}
	bookPID, err := l.scanToolBookDir(ctx, destDir, oldPID, title, len(pieces))
	if err != nil {
		return nil, err
	}
	// The pieces group into one multi-file book by identity key, whose
	// position is a book-timeline millisecond spanning the parts: the
	// old single-file position is the same number on the new timeline,
	// so one checkpoint per user carries the resume point.
	for userPID, byItem := range positions {
		if pos := byItem[oldPID]; pos > 0 {
			if err := l.lib.Playback().Checkpoint(ctx, userPID, bookPID, pos); err != nil {
				l.log.Warn("carrying split resume position", "user", string(userPID), "err", err)
			}
		}
	}
	return []string{apiPID(PrefixBook, bookPID)}, nil
}

// runCueSplit cuts a shared album rip at its cue sheet's boundaries and
// imports one real file per virtual track.
func (l *Library) runCueSplit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	_, seedPID, ok := parseAPIPID(t.ItemPID)
	if !ok {
		return nil, fmt.Errorf("%w: bad item pid %q", errToolPermanent, t.ItemPID)
	}
	seed, err := l.lib.Get(ctx, seedPID)
	if err != nil {
		return nil, classify(err)
	}
	sibs := l.cueSiblings(ctx, seed, p.SrcPath)
	jobID, err := l.flowJobs.CreateSplitJob(ctx, p.SrcPath, nil, p.CuePath, p.Format)
	if err != nil {
		return nil, err
	}
	outs, err := l.pollToolJob(ctx, t, jobID, 0)
	if err != nil {
		return nil, err
	}
	if outs != len(sibs) {
		// Tag what aligns and log the mismatch rather than failing a
		// finished cut; the extra pieces get generated names.
		l.log.Warn("cue split piece count differs from virtual tracks",
			"task", t.ID, "pieces", outs, "tracks", len(sibs))
	}
	ws, err := l.toolWorkspace(t.ID)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(ws)
	albumDir := filepath.Join(ws, safeFileName(firstNonEmpty(seed.Album, "Split Album")))
	if err := os.MkdirAll(albumDir, 0o755); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	pieces := make([]string, 0, outs)
	for i := 0; i < outs; i++ {
		title := fmt.Sprintf("Track %02d", i+1)
		trackNo := i + 1
		artist := seed.Artist
		if i < len(sibs) {
			title = firstNonEmpty(sibs[i].Title, title)
			if sibs[i].TrackNo > 0 {
				trackNo = sibs[i].TrackNo
			}
			artist = firstNonEmpty(sibs[i].Artist, artist)
		}
		dst := filepath.Join(albumDir, fmt.Sprintf("%02d - %s.%s", i+1, safeFileName(title), p.Format))
		if err := l.flowJobs.DownloadJobResult(ctx, jobID, i, dst); err != nil {
			return nil, err
		}
		if err := l.tagToolTrackFile(ctx, dst, seed, title, artist, trackNo); err != nil {
			return nil, err
		}
		pieces = append(pieces, dst)
	}
	// Import first, trash after: track items carry no shared identity
	// key, so the pieces and the virtual originals coexist while play
	// state is copied across.
	sibPIDs := make([]model.PID, len(sibs))
	for i, s := range sibs {
		sibPIDs[i] = s.PID
	}
	piecePIDs, err := l.importToolDir(ctx, albumDir, pieces)
	if err != nil {
		return nil, err
	}
	positions := l.collectToolPositions(ctx, sibPIDs)
	for userPID, byItem := range positions {
		for i, sib := range sibPIDs {
			if pos := byItem[sib]; pos > 0 && i < len(piecePIDs) && piecePIDs[i] != "" {
				if err := l.lib.Playback().Checkpoint(ctx, userPID, piecePIDs[i], pos); err != nil {
					l.log.Warn("carrying cue split position", "user", string(userPID), "err", err)
				}
			}
		}
	}
	if !p.KeepOriginals {
		// Trashing every virtual track retires the shared rip through
		// the catalog's own trash journal. The sheet is not an item the
		// journal can carry, and without its rip it names nothing, so
		// it is removed outright.
		if err := l.trashToolItems(ctx, sibPIDs); err != nil {
			return nil, err
		}
		if err := os.Remove(p.CuePath); err != nil && !errors.Is(err, os.ErrNotExist) {
			l.log.Warn("removing cue sheet", "path", p.CuePath, "err", err)
		}
	}
	results := make([]string, 0, len(piecePIDs))
	for _, pid := range piecePIDs {
		if pid != "" {
			results = append(results, apiPID(PrefixTrack, pid))
		}
	}
	return results, nil
}

// pollToolJob polls one engine job to completion, mirroring the
// task's progress and renewing the lease as it goes. wantOutputs > 0
// asserts the finished output count.
func (l *Library) pollToolJob(ctx context.Context, t *wdb.ToolTask, jobID string, wantOutputs int) (int, error) {
	lastRenew := time.Now()
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
			l.notifyToolTask(ctx, t.ID)
		}
		if time.Since(lastRenew) >= toolLeaseRenew {
			lastRenew = time.Now()
			until := time.Now().Add(toolTaskLease).UnixNano()
			if rerr := l.db.RenewToolTaskLease(ctx, t.ID, until); rerr != nil {
				l.log.Warn("renewing tool task lease", "task", t.ID, "err", rerr)
			}
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
	return executeToolTagPlan(ctx, ed, path)
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
	return executeToolTagPlan(ctx, ed, path)
}

// addToolCover attaches the item's resolved cover art, best effort.
func (l *Library) addToolCover(ctx context.Context, ed *waxlabel.Editor, pid model.PID) {
	blob, err := l.lib.ResolveArt(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, model.ArtRoleFront, 0)
	if err != nil || blob == nil || len(blob.Bytes) == 0 {
		return
	}
	mime := blob.Format
	if mime != "" && !strings.HasPrefix(mime, "image/") {
		mime = "image/" + mime
	}
	ed.AddPicture(waxlabel.Picture{
		Type: waxlabel.PicFrontCover, MIME: mime,
		Width: blob.Width, Height: blob.Height, Data: blob.Bytes,
	})
}

func executeToolTagPlan(ctx context.Context, ed *waxlabel.Editor, path string) error {
	plan, err := ed.Prepare()
	if err != nil {
		return fmt.Errorf("%w: preparing tags for %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	if _, _, err := plan.Execute(ctx, waxlabel.SaveBack()); err != nil {
		return fmt.Errorf("%w: writing tags to %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	return nil
}

// importToolFile moves one finished file into the library through the
// acquired-import path and resolves the item it produced.
func (l *Library) importToolFile(ctx context.Context, path string, kind model.Kind) (model.PID, error) {
	res, err := l.lib.ImportAcquired(ctx, waxbin.AcquiredFile{Path: path}, kind, waxbin.AcquiredMeta{
		SourceType: model.SourceManual, Copy: false, DupPolicy: model.DupAllow,
	})
	if err != nil {
		return "", classify(err)
	}
	if res.Plan == nil {
		return "", fmt.Errorf("%w: the import planner produced no plan", errToolPermanent)
	}
	report, err := l.lib.ApplyImport(ctx, res.Plan)
	if err != nil {
		return "", classify(err)
	}
	if report.Imported == 0 {
		return "", fmt.Errorf("%w: the import did not land the result: %s", errToolPermanent,
			l.scrubStoragePaths(importFailureReason(res.Plan, report)))
	}
	return l.resolveToolImport(ctx, res.Plan, path)
}

// importToolDir imports a workspace directory of finished pieces as one
// batch and resolves each piece's item in input order. A piece can
// legitimately fail to resolve alone: essence resolution finds an item
// through its primary file, and every non-primary part of a multi-file
// book answers nothing. Those entries come back empty; only a batch
// where nothing resolves is an error.
func (l *Library) importToolDir(ctx context.Context, dir string, srcs []string) ([]model.PID, error) {
	plan, err := l.lib.PlanImport(ctx, waxbin.ImportRequest{Source: dir, DupPolicy: model.DupAllow})
	if err != nil {
		return nil, classify(err)
	}
	report, err := l.lib.ApplyImport(ctx, plan)
	if err != nil {
		return nil, classify(err)
	}
	if report.Imported == 0 {
		return nil, fmt.Errorf("%w: the import landed no piece: %s", errToolPermanent,
			l.scrubStoragePaths(importFailureReason(plan, report)))
	}
	pids := make([]model.PID, len(srcs))
	resolved := 0
	for i, src := range srcs {
		pid, err := l.resolveToolImport(ctx, plan, src)
		if err != nil {
			l.log.Warn("tool import piece did not resolve", "piece", filepath.Base(src), "err", err)
			continue
		}
		pids[i] = pid
		resolved++
	}
	if resolved == 0 {
		return nil, fmt.Errorf("%w: no imported piece resolved to an item", errToolPermanent)
	}
	return pids, nil
}

// scanToolBookDir catalogs a directly-placed book directory with a
// synchronous scan scoped to its library, then resolves the book the
// pieces formed: the original item when the identity key revived it
// (the kept-originals marker changes the key, so the copy stays its own
// book), else the book the (possibly marked) title names.
func (l *Library) scanToolBookDir(ctx context.Context, dir string, oldPID model.PID, title string, pieceCount int) (model.PID, error) {
	req := waxbin.ScanRequest{}
	if libPID, err := l.libraryForPath(ctx, dir); err == nil && libPID != "" {
		req.LibraryPID = model.PID(libPID)
	}
	if _, err := l.lib.Scan(ctx, req); err != nil {
		return "", classify(err)
	}
	if bd, err := l.lib.Book(ctx, oldPID); err == nil && len(bd.Files) == pieceCount {
		return oldPID, nil
	}
	b := query.New(query.EntityItems).
		Where("kind", query.OpIs, string(model.KindBook)).
		Where("title", query.OpIs, title).Limit(1)
	items, err := l.lib.Query(ctx, b.Build(), "")
	if err != nil {
		return "", classify(err)
	}
	if len(items) == 0 {
		return "", fmt.Errorf("%w: the scanned pieces produced no book", errToolPermanent)
	}
	return items[0].PID, nil
}

// copyToolFile copies a staged piece into the library with the repo's
// crash-safe write discipline; staging may sit on another filesystem,
// so a plain rename cannot carry it.
func copyToolFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".waxdeck-piece-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := io.Copy(tmp, in); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, dst); err != nil {
		os.Remove(tmpName)
		return err
	}
	if d, err := os.Open(filepath.Dir(dst)); err == nil {
		_ = d.Sync()
		d.Close()
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

// collectToolPositions reads every account's saved position for the
// given items; zero positions are omitted.
func (l *Library) collectToolPositions(ctx context.Context, items []model.PID) map[model.PID]map[model.PID]int64 {
	out := map[model.PID]map[model.PID]int64{}
	l.forEachCatalogUser(ctx, func(userPID model.PID) {
		for _, item := range items {
			st, err := l.lib.Playback().State(ctx, userPID, item)
			if err != nil || st == nil || st.PositionMS <= 0 {
				continue
			}
			m := out[userPID]
			if m == nil {
				m = map[model.PID]int64{}
				out[userPID] = m
			}
			m[item] = st.PositionMS
		}
	})
	return out
}

// forEachCatalogUser pages every WaxDeck account and hands the catalog
// user pid of each to fn.
func (l *Library) forEachCatalogUser(ctx context.Context, fn func(model.PID)) {
	after := ""
	for {
		users, err := l.db.ListUsers(ctx, after, 200)
		if err != nil {
			l.log.Warn("listing users for position carry-over", "err", err)
			return
		}
		if len(users) == 0 {
			return
		}
		for _, u := range users {
			after = strings.ToLower(u.Username)
			if u.WaxbinUserPID != "" {
				fn(model.PID(u.WaxbinUserPID))
			}
		}
		if len(users) < 200 {
			return
		}
	}
}

// cueSiblings collects every virtual track carved from the same backing
// file, in rip order. It always includes at least the seed.
func (l *Library) cueSiblings(ctx context.Context, seed *model.ItemView, srcPath string) []*model.ItemView {
	var sibs []*model.ItemView
	b := query.New(query.EntityItems).Where("kind", query.OpIs, string(model.KindTrack)).Limit(1000)
	if seed.Album != "" {
		b = b.Where("album", query.OpIs, seed.Album)
	}
	items, err := l.lib.Query(ctx, b.Build(), "")
	if err != nil {
		l.log.Warn("listing cue siblings", "err", err)
		items = nil
	}
	for _, cand := range items {
		if !cand.Virtual {
			continue
		}
		loc, err := l.paths.Locate(ctx, cand.PID)
		if err != nil || loc.Path != srcPath {
			continue
		}
		sibs = append(sibs, cand)
	}
	sort.Slice(sibs, func(i, j int) bool { return sibs[i].StartFrames < sibs[j].StartFrames })
	if len(sibs) == 0 {
		sibs = []*model.ItemView{seed}
	}
	return sibs
}

// trashToolItems moves items to the catalog's reversible trash.
func (l *Library) trashToolItems(ctx context.Context, pids []model.PID) error {
	plan, err := l.lib.PlanDeletePIDs(ctx, pids, model.DeleteTrash)
	if err != nil {
		return classify(err)
	}
	if _, err := l.lib.ApplyDelete(ctx, plan); err != nil {
		return classify(err)
	}
	return nil
}

// insertToolTask persists a queued task and notifies its audience.
func (l *Library) insertToolTask(ctx context.Context, uc *UserCtx, typ, itemPID string, p toolTaskParams) (ToolTaskDTO, error) {
	t := wdb.ToolTask{
		ID:          "tk-" + ulid.Make().String(),
		Type:        typ,
		State:       taskStateQueued,
		ItemPID:     itemPID,
		UserID:      uc.ID,
		Params:      marshalJSON(p),
		ResultPIDs:  "[]",
		CreatedAtNS: time.Now().UnixNano(),
	}
	if err := l.db.InsertToolTask(ctx, t); err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.notifyToolTask(ctx, t.ID)
	return toolTaskDTO(t), nil
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

// failToolTask records a terminal failure.
func (l *Library) failToolTask(ctx context.Context, t *wdb.ToolTask, cause error) {
	t.State = taskStateFailed
	t.Error = strings.TrimPrefix(cause.Error(), errToolPermanent.Error()+": ")
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.UpdateToolTask(ctx, *t); err != nil {
		l.log.Warn("recording tool task failure", "task", t.ID, "err", err)
	}
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
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
	if _, held := params["secretSealed"]; !held {
		return
	}
	delete(params, "secretSealed")
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
	seen := map[string]bool{}
	if t, err := l.db.ToolTaskByID(ctx, taskID); err == nil && t.UserID != "" {
		seen[t.UserID] = true
		l.emitUserEvent(ctx, t.UserID, eventTask, taskID)
	}
	admins, err := l.db.EnabledAdminIDs(ctx)
	if err != nil {
		return
	}
	for _, id := range admins {
		if !seen[id] {
			seen[id] = true
			l.emitUserEvent(ctx, id, eventTask, taskID)
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
	return ToolTaskDTO{
		ID: t.ID, Type: t.Type, State: t.State, ItemPID: t.ItemPID,
		ProgressPct: t.ProgressPct, Error: t.Error, ResultPIDs: results,
		Summary:     summary,
		CreatedAtNS: t.CreatedAtNS, FinishedAtNS: t.FinishedAtNS,
	}
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
func toolSplitFormat(codec string) string {
	switch c := strings.ToLower(codec); c {
	case "flac", "alac", "aac", "mp3", "opus", "wav":
		return c
	default:
		return "flac"
	}
}

// findCueSheet locates the sheet describing a rip: the same-basename
// .cue first, else the directory's single .cue.
func findCueSheet(srcPath string) (string, error) {
	base := strings.TrimSuffix(srcPath, filepath.Ext(srcPath)) + ".cue"
	if _, err := os.Stat(base); err == nil {
		return base, nil
	}
	entries, err := os.ReadDir(filepath.Dir(srcPath))
	if err != nil {
		return "", fmt.Errorf("no cue sheet found beside the rip")
	}
	var found []string
	for _, e := range entries {
		if !e.IsDir() && strings.EqualFold(filepath.Ext(e.Name()), ".cue") {
			found = append(found, filepath.Join(filepath.Dir(srcPath), e.Name()))
		}
	}
	if len(found) != 1 {
		return "", fmt.Errorf("no single cue sheet found beside the rip")
	}
	return found[0], nil
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
