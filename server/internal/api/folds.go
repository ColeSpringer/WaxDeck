package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Entity fold handlers: the names merges folded into an entity, and
// releasing them.

func (s *Server) ListEntityFolds(ctx context.Context, req ListEntityFoldsRequestObject) (ListEntityFoldsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return ListEntityFolds400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	folds, next, err := s.svc.ListEntityFolds(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ListEntityFolds400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return ListEntityFolds403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	page := EntityFoldPage{Folds: make([]EntityFold, 0, len(folds))}
	for _, f := range folds {
		fold := EntityFold{
			EntityType: f.EntityType, Key: f.Key, Spelling: f.Spelling,
			EntityPid: f.EntityPID, EntityName: f.EntityName, CreatedAt: f.CreatedAt,
		}
		if f.Facet != "" {
			fold.Facet = ptr(f.Facet)
		}
		if f.Folder != "" {
			fold.Folder = ptr(f.Folder)
		}
		if f.Library != "" {
			fold.Library = ptr(f.Library)
		}
		page.Folds = append(page.Folds, fold)
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	return ListEntityFolds200JSONResponse(page), nil
}

func (s *Server) UnfoldEntities(ctx context.Context, req UnfoldEntitiesRequestObject) (UnfoldEntitiesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return UnfoldEntities400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an unfold body is required"))}, nil
	}
	if !req.Body.EntityType.Valid() {
		return UnfoldEntities400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown entity type"))}, nil
	}
	if err := s.svc.UnfoldEntities(ctx, uc, string(req.Body.EntityType), req.Body.Keys); err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return UnfoldEntities400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return UnfoldEntities403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return UnfoldEntities404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		}
		return nil, err
	}
	return UnfoldEntities204Response{}, nil
}
