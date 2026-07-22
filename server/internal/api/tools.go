package api

import (
	"context"
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
		case service.KindConflict:
			return MergeBook409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindFeature:
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
		case service.KindConflict:
			return SplitBook409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindFeature:
			return SplitBook501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", err.Error()))}, nil
		}
		return nil, err
	}
	return SplitBook202JSONResponse(toolTaskJSON(task)), nil
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
		case service.KindConflict:
			return SplitCueRip409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindFeature:
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
