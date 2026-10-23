package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	var titles []string
	keep := false
	if req.Body != nil {
		if req.Body.Titles != nil {
			titles = *req.Body.Titles
		}
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.StartBookMerge(ctx, uc, string(req.Pid), titles, keep)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return MergeBook400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return MergeBook403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return MergeBook404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such book"))}, nil
		case service.KindConflict, service.KindReadOnly, service.KindStorageUnwritable:
			return MergeBook409JSONResponse(toolRefusalObj(err)), nil
		case service.KindFeature:
			if s.engineIsAway() {
				return MergeBook503JSONResponse{toolEngineAway(err)}, nil
			}
			return MergeBook501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", err.Error()))}, nil
		}
		return nil, err
	}
	return MergeBook202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) SplitBook(ctx context.Context, req SplitBookRequestObject) (SplitBookResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	keep := false
	if req.Body != nil {
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.StartBookSplit(ctx, uc, string(req.Pid), keep)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SplitBook400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return SplitBook403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return SplitBook404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such book"))}, nil
		case service.KindConflict, service.KindReadOnly, service.KindStorageUnwritable:
			return SplitBook409JSONResponse(toolRefusalObj(err)), nil
		case service.KindFeature:
			if s.engineIsAway() {
				return SplitBook503JSONResponse{toolEngineAway(err)}, nil
			}
			return SplitBook501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", err.Error()))}, nil
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
func toolEngineAway(err error) EngineAwayOrMaintenanceJSONResponse {
	e := errObj("feature-unavailable", err.Error())
	e.Params = &map[string]string{"feature": flow.FeatureStreamingEngine}
	return EngineAwayOrMaintenanceJSONResponse{Body: e, Headers: EngineAwayOrMaintenanceResponseHeaders{RetryAfter: ptr(flow.EngineRetrySeconds)}}
}

// toolRefusalObj is a file tool refused before it was queued: its code,
// the service's sentence, and the reason it carries for a client to word.
func toolRefusalObj(err error) Error {
	e := errObj(string(service.KindOf(err)), err.Error())
	if p := service.RefusalParams(err); len(p) > 0 {
		e.Params = &p
	}
	return e
}

func (s *Server) SplitCueRip(ctx context.Context, req SplitCueRipRequestObject) (SplitCueRipResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	keep := false
	if req.Body != nil {
		keep = derefBool(req.Body.KeepOriginals)
	}
	task, err := s.svc.StartCueSplit(ctx, uc, string(req.Pid), keep)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SplitCueRip400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return SplitCueRip403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return SplitCueRip404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such item"))}, nil
		case service.KindConflict, service.KindReadOnly:
			return SplitCueRip409JSONResponse(toolRefusalObj(err)), nil
		case service.KindFeature:
			if s.engineIsAway() {
				return SplitCueRip503JSONResponse{toolEngineAway(err)}, nil
			}
			return SplitCueRip501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", err.Error()))}, nil
		}
		return nil, err
	}
	return SplitCueRip202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) ListToolTasks(ctx context.Context, req ListToolTasksRequestObject) (ListToolTasksResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListToolTasks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	tasks, next, err := s.svc.ListToolTasksFor(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListToolTasks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
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
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	task, err := s.svc.GetToolTaskFor(ctx, uc, string(req.TaskId))
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetToolTask404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such task"))}, nil
		}
		return nil, err
	}
	return GetToolTask200JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) DeleteToolTask(ctx context.Context, req DeleteToolTaskRequestObject) (DeleteToolTaskResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeleteToolTaskFor(ctx, uc, string(req.TaskId)); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return DeleteToolTask404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such task"))}, nil
		case service.KindConflict:
			// A clear kept for the files it could not settle names the
			// reason, for a client to word.
			return DeleteToolTask409JSONResponse{ConflictJSONResponse(toolRefusalObj(err))}, nil
		}
		return nil, err
	}
	return DeleteToolTask204Response{}, nil
}

func (s *Server) ClearFinishedToolTasks(ctx context.Context, req ClearFinishedToolTasksRequestObject) (ClearFinishedToolTasksResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	scope := service.ToolTasksMine
	if req.Body != nil && req.Body.Scope != nil {
		if !req.Body.Scope.Valid() {
			return ClearFinishedToolTasks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "scope must be mine or all"))}, nil
		}
		scope = service.ToolTaskScope(*req.Body.Scope)
	}
	deleted, kept, err := s.svc.ClearFinishedToolTasksFor(ctx, uc, scope)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return ClearFinishedToolTasks403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return ClearFinishedToolTasks200JSONResponse(ToolTasksCleared{Deleted: deleted, Kept: kept}), nil
}
