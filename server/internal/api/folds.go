package api

import (
	"context"
	"net/http"
)

// Entity fold handlers: the names merges folded into an entity, and
// releasing them.

func (s *Server) ListEntityFolds(ctx context.Context, req ListEntityFoldsRequestObject) (ListEntityFoldsResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
	}
	folds, next, err := s.svc.Reads.ListEntityFolds(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
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
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	if !req.Body.EntityType.Valid() {
		return nil, refuse(http.StatusBadRequest, "invalid-request", "unknown entity type")
	}
	if err := s.svc.Reads.UnfoldEntities(ctx, uc, string(req.Body.EntityType), req.Body.Keys); err != nil {
		return nil, err
	}
	return UnfoldEntities204Response{}, nil
}
