package api

import (
	"context"
	"net/http"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// File tooling handlers: book merge, chapter split, cue split, and the
// tool task log.

func toolTaskJSON(d service.ToolTaskDTO) ToolTask {
	out := ToolTask{
		Id:        d.ID,
		Type:      d.Type,
		State:     d.State,
		CreatedAt: time.Unix(0, d.CreatedAtNS).UTC(),
	}
	if len(d.Summary) > 0 {
		summary := d.Summary
		out.Summary = &summary
	}
	if d.ItemPID != "" {
		out.ItemPid = ptr(d.ItemPID)
	}
	if d.ItemTitle != "" {
		out.ItemTitle = ptr(d.ItemTitle)
	}
	if d.ProgressPct > 0 {
		out.ProgressPct = ptr(d.ProgressPct)
	}
	if d.Error != "" {
		out.Error = ptr(d.Error)
	}
	if len(d.ResultPIDs) > 0 {
		out.ResultPids = ptr(append([]string{}, d.ResultPIDs...))
	}
	if d.FinishedAtNS > 0 {
		out.FinishedAt = ptr(time.Unix(0, d.FinishedAtNS).UTC())
	}
	if d.WaitReason != "" {
		out.WaitReason = ptr(d.WaitReason)
		out.RetryAt = ptr(time.Unix(0, d.RetryAtNS).UTC())
	}
	if d.BookInTrash {
		out.BookInTrash = ptr(true)
	}
	return out
}

func (s *Server) MergeBook(ctx context.Context, req MergeBookRequestObject) (MergeBookResponseObject, error) {
	uc := userCtx(ctx)
	var titles []string
	keep := false
	if req.Body != nil {
		if req.Body.Titles != nil {
			titles = *req.Body.Titles
		}
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.Tools.StartBookMerge(ctx, uc, string(req.Pid), titles, keep)
	if err != nil {
		if service.KindOf(err) == service.KindFeature && s.engineIsAway() {
			return nil, toolEngineAway(err)
		}
		return nil, err
	}
	return MergeBook202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) SplitBook(ctx context.Context, req SplitBookRequestObject) (SplitBookResponseObject, error) {
	uc := userCtx(ctx)
	keep := false
	if req.Body != nil {
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.Tools.StartBookSplit(ctx, uc, string(req.Pid), keep)
	if err != nil {
		if service.KindOf(err) == service.KindFeature && s.engineIsAway() {
			return nil, toolEngineAway(err)
		}
		return nil, err
	}
	return SplitBook202JSONResponse(toolTaskJSON(task)), nil
}

// engineIsAway reports a configured streaming engine that is not answering,
// read off the bridge as /health reads it.
func (s *Server) engineIsAway() bool {
	return s.bridge != nil && !s.bridge.Status().Connected
}

// toolEngineAway is a file tool refused while its configured engine is
// away: the outage's answer, naming the engine and when to ask again,
// not the 501 of a server that has none.
func toolEngineAway(err error) error {
	return refuseEngineAway(serviceMessage(err), nil)
}

func (s *Server) SplitCueRip(ctx context.Context, req SplitCueRipRequestObject) (SplitCueRipResponseObject, error) {
	uc := userCtx(ctx)
	keep := false
	if req.Body != nil {
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.Tools.StartCueSplit(ctx, uc, string(req.Pid), keep)
	if err != nil {
		if service.KindOf(err) == service.KindFeature && s.engineIsAway() {
			return nil, toolEngineAway(err)
		}
		return nil, err
	}
	return SplitCueRip202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) ListToolTasks(ctx context.Context, req ListToolTasksRequestObject) (ListToolTasksResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 50, 200)
	if err != nil {
		return nil, err
	}
	tasks, next, err := s.svc.Tools.ListToolTasksFor(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	page := ToolTaskPage{Tasks: make([]ToolTask, 0, len(tasks))}
	for _, t := range tasks {
		page.Tasks = append(page.Tasks, toolTaskJSON(t))
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	return ListToolTasks200JSONResponse(page), nil
}

func (s *Server) GetToolTask(ctx context.Context, req GetToolTaskRequestObject) (GetToolTaskResponseObject, error) {
	uc := userCtx(ctx)
	task, err := s.svc.Tools.GetToolTaskFor(ctx, uc, string(req.TaskId))
	if err != nil {
		return nil, err
	}
	return GetToolTask200JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) DeleteToolTask(ctx context.Context, req DeleteToolTaskRequestObject) (DeleteToolTaskResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Tools.DeleteToolTaskFor(ctx, uc, string(req.TaskId)); err != nil {
		// A clear kept for the files it could not settle is the service's
		// conflict, and the table sends its params on: they name the
		// reason, for a client to word.
		return nil, err
	}
	return DeleteToolTask204Response{}, nil
}

func (s *Server) ClearFinishedToolTasks(ctx context.Context, req ClearFinishedToolTasksRequestObject) (ClearFinishedToolTasksResponseObject, error) {
	uc := userCtx(ctx)
	scope := service.ToolTasksMine
	if req.Body != nil && req.Body.Scope != nil {
		if !req.Body.Scope.Valid() {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "scope must be mine or all")
		}
		scope = service.ToolTaskScope(*req.Body.Scope)
	}
	deleted, kept, err := s.svc.Tools.ClearFinishedToolTasksFor(ctx, uc, scope)
	if err != nil {
		return nil, err
	}
	return ClearFinishedToolTasks200JSONResponse(ToolTasksCleared{Deleted: deleted, Kept: kept}), nil
}
