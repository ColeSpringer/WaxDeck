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

// insertToolTask persists a queued task and notifies its audience.
func (l *Tools) insertToolTask(ctx context.Context, uc *UserCtx, typ, itemPID string, p toolTaskParams) (ToolTaskDTO, error) {
	return l.insertToolTaskWith(ctx, uc, typ, itemPID, p, "")
}

// insertToolTaskWith is insertToolTask with a summary the task carries
// from the start, so its row can say what it is before it runs.
func (l *Tools) insertToolTaskWith(ctx context.Context, uc *UserCtx, typ, itemPID string, p toolTaskParams, summary string) (ToolTaskDTO, error) {
	return l.queueToolTask(ctx, newToolTask(uc, typ, itemPID, p, summary))
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

// failToolTask records a terminal failure, which a shutdown does not
// keep from the record.
func (l *Tools) failToolTask(ctx context.Context, t *wdb.ToolTask, cause error) {
	ctx = context.WithoutCancel(ctx)
	l.log.Warn("a tool task failed", "task", t.ID, "type", t.Type, "err", cause)
	t.State = taskStateFailed
	t.Error = taskFailureText(cause)
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.UpdateToolTask(ctx, *t); err != nil {
		l.log.Warn("recording tool task failure", "task", t.ID, "err", err)
	}
	l.Migrate.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	l.notifyFileToolEnd(ctx, t)
	l.taskEnded(ctx, t)
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
func (l *Tools) notifyFileToolEnd(ctx context.Context, t *wdb.ToolTask) {
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
	if t.ItemTitle != "" {
		subject += " of " + t.ItemTitle
	}
	l.Integrations.EmitNotificationFor(ctx, "tool-task-failed", title, subject+": "+body, t.ID, []string{t.UserID})
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
