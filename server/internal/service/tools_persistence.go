package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A tool task's records: the row, its audit and failure marks, its
// progress, and the notices that tell its audience.

// auditToolTask records a task's run under the account that queued it,
// by id, as a failed migration is: an account disabled or deleted since
// still ordered the run.
func (l *Tools) auditToolTask(ctx context.Context, t *wdb.ToolTask, action string, target AuditTarget, detail map[string]any) {
	if t.UserID == "" {
		return
	}
	l.Audit.Record(context.WithoutCancel(ctx), &UserCtx{ID: t.UserID}, action, target, detail)
}

// queueToolTask persists a queued task and notifies its audience.
func (l *Tools) queueToolTask(ctx context.Context, t wdb.ToolTask) (ToolTaskDTO, error) {
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

// taskParamsOf reads a task's params as they stand; none reads empty.
func taskParamsOf(t *wdb.ToolTask) toolTaskParams {
	var p toolTaskParams
	if t.Params != "" {
		_ = json.Unmarshal([]byte(t.Params), &p)
	}
	return p
}

// editTaskParams changes a running task's params as they stand and records
// them, whatever happens to the run.
func (l *Tools) editTaskParams(ctx context.Context, t *wdb.ToolTask, edit func(*toolTaskParams)) error {
	var p toolTaskParams
	if t.Params != "" {
		if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
			return err
		}
	}
	edit(&p)
	raw := marshalJSON(p)
	if err := l.db.UpdateToolTaskParams(context.WithoutCancel(ctx), t.ID, raw); err != nil {
		return err
	}
	t.Params = raw
	return nil
}

// keepAttemptSummary records what an attempt that stopped short counted,
// as the task's summary, whatever becomes of the attempt.
func (l *Tools) keepAttemptSummary(ctx context.Context, t *wdb.ToolTask, sum any) {
	t.Summary = marshalJSON(sum)
	if err := l.db.UpdateToolTask(context.WithoutCancel(ctx), *t); err != nil && !errors.Is(err, wdb.ErrNotFound) {
		l.log.Warn("recording a task's counts", "task", t.ID, "err", err)
	}
}

// nameToolTask names what an untitled task works on, once its run learns
// it, and tells the task's watchers.
func (l *Tools) nameToolTask(ctx context.Context, t *wdb.ToolTask, title string) {
	title = strings.TrimSpace(title)
	if title == "" || t.ItemTitle != "" {
		return
	}
	if err := l.db.SetToolTaskItemTitle(context.WithoutCancel(ctx), t.ID, title); err != nil {
		l.log.Warn("naming a tool task", "task", t.ID, "err", err)
		return
	}
	t.ItemTitle = title
	l.notifyToolTaskProgress(context.WithoutCancel(ctx), t.ID)
}

// failToolTask records a terminal failure, which a shutdown does not
// keep from the record. A task canceled first stays canceled, and its
// failure is no news: logged only once the record says failed. An
// acquisition or sync first opens the entries of what an earlier run
// staged, as its run would have, had it got that far. All of it runs
// under the task's settle lock, so a cancel's settle of the task never
// opens the same entries alongside.
func (l *Tools) failToolTask(ctx context.Context, t *wdb.ToolTask, cause error) {
	ctx = context.WithoutCancel(ctx)
	release, err := l.settleLocks.acquire(ctx, t.ID)
	if err != nil {
		return
	}
	defer release()
	opened := false
	if t.Type == taskTypeAcquire || t.Type == taskTypePlaylistSync {
		// As a settle that held the lock left them.
		if row, err := l.db.ToolTaskByID(ctx, t.ID); err == nil {
			t.Params = row.Params
		}
		before := len(taskParamsOf(t).Entries)
		if err := l.Ingest.openStrandedEntries(ctx, t); err != nil {
			l.log.Warn("opening a failed task's stranded entries", "task", t.ID, "err", err)
		}
		opened = len(taskParamsOf(t).Entries) > before
	}
	t.State = taskStateFailed
	if t.Type == taskTypeAcquire {
		t.ResultPIDs = l.keptEntries(t)
		if opened {
			t.Summary = l.Ingest.acquireSummary(ctx, t)
		}
	}
	t.Error = taskFailureText(cause)
	t.ErrorCode, t.ErrorParams = taskFailureCode(cause)
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.FinishToolTask(ctx, *t); errors.Is(err, wdb.ErrNotFound) {
		l.log.Info("a canceled tool task's run failed after its cancel", "task", t.ID, "type", t.Type, "err", cause)
		return
	} else if err != nil {
		l.log.Warn("recording tool task failure", "task", t.ID, "err", err)
	}
	l.log.Warn("a tool task failed", "task", t.ID, "type", t.Type, "err", cause)
	l.runEnded(ctx, t, !errors.Is(cause, errSyncTargetGone))
}

// runEnded takes a run's own end steps once its terminal state is
// recorded (FinishToolTask), under the task's settle lock, and then ends
// the marker that write set, so the startup pass takes again what a stop
// cut off. Each step is safe to take again. notice files a failure, or a
// park, in its starter's inbox.
func (l *Tools) runEnded(ctx context.Context, t *wdb.ToolTask, notice bool) {
	if t.ParkEndPending {
		l.parkEnded(ctx, t)
	}
	l.holdLeftovers(ctx, t)
	// Before the scrub, which drops an export id once the upload it names
	// is gone: settling is what makes that true.
	l.Migrate.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	if notice && t.State != taskStateDone {
		l.notifyToolTaskEnd(ctx, t)
	}
	l.taskEnded(ctx, t)
	l.endSettle(ctx, t)
}

// endSettle ends a task's settle marker, its end's last step.
func (l *Tools) endSettle(ctx context.Context, t *wdb.ToolTask) {
	if err := l.db.EndToolTaskSettle(ctx, t.ID); err != nil {
		l.log.Warn("ending a tool task's settle", "task", t.ID, "err", err)
		return
	}
	t.SettlePending, t.RunEndPending, t.ParkEndPending = false, false, false
}

// holdLeftovers parks a failed book merge or split whose run gave up files
// it could not remove, so it holds its book, as a parked task does, until
// it is cleared.
func (l *Tools) holdLeftovers(ctx context.Context, t *wdb.ToolTask) {
	if t.State != taskStateFailed || (t.Type != taskTypeBookMerge && t.Type != taskTypeBookSplit) {
		return
	}
	row, err := l.db.ToolTaskByID(ctx, t.ID)
	if err != nil {
		return
	}
	if p := taskParamsOf(&row); !p.Discarded || len(p.Created) == 0 {
		return
	}
	if err := l.db.HoldFinishedToolTask(ctx, t.ID); err != nil {
		l.log.Warn("holding a failed task's book", "task", t.ID, "err", err)
		return
	}
	t.State = taskStateParked
}

// cancelToolTask records a task canceled, keeping the results and the
// counts its runs left, settles what a run of it made as the retire pass
// does one its attempts ran out on, and tells its audience; it files no
// notification. A task that finished, was canceled already or is
// resumable stays as it is.
func (l *Tools) cancelToolTask(ctx context.Context, t *wdb.ToolTask) {
	ctx = context.WithoutCancel(ctx)
	results, summary := t.ResultPIDs, t.Summary
	if t.Type == taskTypeAcquire || t.Type == taskTypePlaylistSync {
		results = l.keptEntries(t)
	}
	if t.Type == taskTypeAcquire {
		summary = l.Ingest.acquireSummary(ctx, t)
	}
	at := time.Now().UnixNano()
	settled, err := l.db.SettleToolTaskCanceled(ctx, t.ID, at, results, summary)
	if err != nil {
		l.log.Warn("recording a canceled tool task", "task", t.ID, "err", err)
		return
	}
	if !settled {
		return
	}
	l.log.Info("a tool task was canceled", "task", t.ID, "type", t.Type)
	t.State, t.FinishedAtNS, t.ResultPIDs, t.Summary = taskStateCanceled, at, results, summary
	t.Error, t.ErrorCode, t.ErrorParams, t.WaitReason = "", "", "", ""
	if row, ok := l.finishSettle(ctx, t.ID); ok {
		*t = row
	}
	l.notifyToolTask(ctx, t.ID)
}

// finishSettle does what a canceled or retired task's end settles beyond
// its row, or a run's own end steps (runEnded), unless that is done. A
// canceled or retired task's: an acquisition's or sync's stranded entries
// opened, a file tool's outputs discarded and what stays named, the book or
// rip it holds kept for its leftovers or let go, an import's export settled
// and its credentials dropped, a retired task's failure notice filed, and
// what its end tells beyond (taskEnded). Each step is safe to take again
// and the marker ends after the last, so the startup pass finishes a
// settle a stop cut short. It answers the task as it then stands, false
// when it cannot be read.
func (l *Tools) finishSettle(ctx context.Context, id string) (wdb.ToolTask, bool) {
	ctx = context.WithoutCancel(ctx)
	release, err := l.settleLocks.acquire(ctx, id)
	if err != nil {
		return wdb.ToolTask{}, false
	}
	defer release()
	t, err := l.db.ToolTaskByID(ctx, id)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("reading a tool task to settle", "task", id, "err", err)
		}
		return t, false
	}
	if !t.SettlePending {
		return t, true
	}
	if l.settleHook != nil {
		l.settleHook(id)
	}
	if t.RunEndPending {
		l.runEnded(ctx, &t, true)
		return t, true
	}
	if t.Type == taskTypeAcquire || t.Type == taskTypePlaylistSync {
		l.keepStrandedEntries(ctx, &t)
	}
	if t.State == taskStateFailed {
		l.listRetiredEntries(ctx, &t)
	}
	left := l.settleRetired(ctx, &t)
	l.keepLeftOver(ctx, &t, left)
	switch {
	case t.State == taskStateFailed:
		l.holdLeftovers(ctx, &t)
	case t.State == taskStateCanceled && left == "" && t.LockKey != "":
		// One that left files keeps its book or rip, as a parked task
		// does, until it is cleared.
		if err := l.db.ReleaseToolTaskLock(ctx, t.ID); err != nil {
			l.log.Warn("releasing a canceled tool task's lock", "task", t.ID, "err", err)
		}
		t.LockKey = ""
	}
	l.Migrate.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	if t.State != taskStateCanceled {
		// Retired: failed, or parked for its leftovers.
		l.notifyToolTaskEnd(ctx, &t)
	}
	l.taskEnded(ctx, &t)
	l.endSettle(ctx, &t)
	return t, true
}

// keptEntries are the review entries an acquisition's or sync's runs
// opened, which it lists however it ends, as a done one does.
func (l *Tools) keptEntries(t *wdb.ToolTask) string {
	return marshalJSON(append([]string{}, taskParamsOf(t).Entries...))
}

// listRetiredEntries has an acquisition its attempts ran out on list the
// review entries its runs opened, in its results and its summary.
func (l *Tools) listRetiredEntries(ctx context.Context, t *wdb.ToolTask) {
	if t.Type != taskTypeAcquire {
		return
	}
	t.ResultPIDs, t.Summary = l.keptEntries(t), l.Ingest.acquireSummary(ctx, t)
	if err := l.db.UpdateToolTask(ctx, *t); err != nil {
		l.log.Warn("listing a retired task's entries", "task", t.ID, "err", err)
	}
}

// keepStrandedEntries opens the review entries of what an earlier run of
// a canceled or retired acquisition or sync staged and never gave one, as
// its next run would have, and lists them with the task's.
func (l *Tools) keepStrandedEntries(ctx context.Context, t *wdb.ToolTask) {
	before := len(taskParamsOf(t).Entries)
	if err := l.Ingest.openStrandedEntries(ctx, t); err != nil {
		l.log.Warn("opening a canceled task's stranded entries", "task", t.ID, "err", err)
	}
	if entries := taskParamsOf(t).Entries; len(entries) > before {
		// A failed sync lists none, as its runs' own failures do not.
		if t.Type == taskTypeAcquire || t.State == taskStateCanceled {
			t.ResultPIDs = marshalJSON(entries)
		}
		if t.Type == taskTypeAcquire {
			t.Summary = l.Ingest.acquireSummary(ctx, t)
		}
		if err := l.db.UpdateToolTask(ctx, *t); err != nil {
			l.log.Warn("listing a canceled task's entries", "task", t.ID, "err", err)
		}
	}
}

// failureNoticeNames are the tasks whose failure tells their starter, by
// type, as the starters read them: the file tools, which can park too, and
// URL downloads and playlist syncs (those the person started: a scheduled
// one's failures end in the suspension notice instead).
var failureNoticeNames = map[string]string{
	taskTypeBookMerge:    "Book merge",
	taskTypeBookSplit:    "Book split",
	taskTypeCueSplit:     "CUE split",
	taskTypeAcquire:      "URL download",
	taskTypePlaylistSync: "Playlist sync",
}

// notifyToolTaskEnd files a task that failed, or a file tool that parked,
// in its starter's inbox, as a failed job is, naming what it worked on: an
// untitled download by its link. The recorded failure names the server's
// paths, which only an administrator reads. A task ends once, so a notice
// already filed for it is not filed again. A sync whose playlist or
// binding the person removed, whenever in its run, files none.
func (l *Tools) notifyToolTaskEnd(ctx context.Context, t *wdb.ToolTask) {
	name, ok := failureNoticeNames[t.Type]
	if !ok || t.UserID == "" {
		return
	}
	if t.Type == taskTypePlaylistSync {
		if p := taskParamsOf(t); !p.Asked || l.Playlists.syncTargetRemoved(ctx, p.PlaylistPID) {
			return
		}
	}
	what := t.ItemTitle
	if what == "" && t.Type == taskTypeAcquire {
		what = taskParamsOf(t).URL
	}
	title := name + " failed"
	if t.State == taskStateParked {
		title = name + " needs attention"
	}
	if what != "" {
		title += ": " + what
	}
	body := cmp.Or(t.Error, "no reason was recorded")
	u, err := l.db.UserByID(ctx, t.UserID)
	var uc *UserCtx
	if err == nil {
		uc, err = l.Grants.UserCtx(ctx, u)
	}
	switch {
	case err != nil:
		body = l.Jobs.failureWordsFor(&UserCtx{}, body)
	case !uc.Admin:
		body = l.Jobs.failureWordsFor(uc, body)
	}
	// The which-one goes in the body, as a failed job's does: a client
	// heads the row with its own words for the event.
	subject := name
	if what != "" {
		subject += " of " + what
	}
	l.Integrations.EmitNotificationFor(ctx, "tool-task-failed", title, subject+": "+body, t.ID, []string{t.UserID}, notifyOnce())
}

// taskEnded is what a task's end tells beyond its own marker, once
// the end is recorded.
func (l *Tools) taskEnded(ctx context.Context, t *wdb.ToolTask) {
	switch t.Type {
	case taskTypeHealthFix:
		l.Health.fixTaskEnded(ctx, t)
	case taskTypeCatalogRepair:
		l.library.catalogRepairEnded(ctx, t)
	}
}

// scrubTaskSecrets drops sealed credentials from a terminal task's
// params: a finished import has no further use for them, and holding
// them indefinitely widens what a database-plus-keyfile exposure leaks.
// Sealed rows are unreadable without the key either way; this bounds
// the lifetime to the task's own, which is what the API documents.
func (l *Tools) scrubTaskSecrets(ctx context.Context, taskID string) {
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
func (l *Tools) notifyToolTask(ctx context.Context, taskID string) {
	l.markToolTask(ctx, taskID, eventTask)
}

// notifyToolTaskProgress tells the same watchers a task's progress moved,
// which refreshes their lists and is not news.
func (l *Tools) notifyToolTaskProgress(ctx context.Context, taskID string) {
	l.markToolTask(ctx, taskID, eventTaskProgress)
}

func (l *Tools) markToolTask(ctx context.Context, taskID, kind string) {
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
	l       *Tools
	t       *wdb.ToolTask
	lastPct float64
}

func newToolProgress(l *Tools, t *wdb.ToolTask) *toolProgress {
	return &toolProgress{l: l, t: t}
}

// items says the run is in phase with done of total items, total 0 when
// it is not known.
func (tp *toolProgress) items(ctx context.Context, phase string, done, total int) {
	tp.l.noteActivity(ctx, tp.t.ID, func(a *ToolTaskActivity) { a.Phase, a.ItemsDone, a.ItemsTotal = phase, done, total })
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
