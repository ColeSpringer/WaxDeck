package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Share link management (the public pages live in sharepage.go).

func (s *Server) shareJSON(info service.ShareInfo) Share {
	out := Share{
		Pid:           info.ID,
		Url:           "/s/" + s.shares.Mint(barePID(info.ID)),
		TargetPid:     info.TargetPID,
		TargetKind:    info.TargetKind,
		TargetTitle:   info.TargetTitle,
		AllowDownload: info.AllowDownload,
		CreatedAt:     info.CreatedAt,
		Plays:         info.Plays,
	}
	if info.PositionMs > 0 {
		out.PositionMs = ptr(info.PositionMs)
	}
	if !info.ExpiresAt.IsZero() {
		out.ExpiresAt = ptr(info.ExpiresAt)
	}
	return out
}

// barePID strips the two-letter API prefix.
func barePID(apiPID string) string {
	if len(apiPID) > 3 {
		return apiPID[3:]
	}
	return apiPID
}

func (s *Server) ListShares(ctx context.Context, req ListSharesRequestObject) (ListSharesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListShares400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 200"))}, nil
	}
	res, err := s.svc.Shares(ctx, uc, derefBool(req.Params.All), deref(req.Params.Cursor), limit)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return ListShares400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	case service.KindForbidden:
		return ListShares403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
	default:
		return nil, err
	}
	out := SharePage{Shares: []Share{}}
	for _, sh := range res.Shares {
		out.Shares = append(out.Shares, s.shareJSON(sh))
	}
	if res.Next != "" {
		out.NextCursor = ptr(res.Next)
	}
	return ListShares200JSONResponse(out), nil
}

func (s *Server) CreateShare(ctx context.Context, req CreateShareRequestObject) (CreateShareResponseObject, error) {
	if req.Body == nil {
		return CreateShare400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	var expiresIn time.Duration
	if req.Body.ExpiresInHours != nil {
		if *req.Body.ExpiresInHours < 1 || *req.Body.ExpiresInHours > 8760 {
			return CreateShare400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "expiresInHours must be between 1 and 8760"))}, nil
		}
		expiresIn = time.Duration(*req.Body.ExpiresInHours) * time.Hour
	}
	info, err := s.svc.CreateShare(ctx, uc, req.Body.Pid, expiresIn,
		derefBool(req.Body.AllowDownload), derefInt64(req.Body.PositionMs))
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return CreateShare404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindInvalid:
		return CreateShare400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	case service.KindForbidden:
		return CreateShare403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
	default:
		return nil, err
	}
	return CreateShare201JSONResponse(s.shareJSON(info)), nil
}

func (s *Server) RevokeShare(ctx context.Context, req RevokeShareRequestObject) (RevokeShareResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	err = s.svc.RevokeShare(ctx, uc, req.ShareId)
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return RevokeShare404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindForbidden:
		return RevokeShare403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
	default:
		return nil, err
	}
	return RevokeShare204Response{}, nil
}
