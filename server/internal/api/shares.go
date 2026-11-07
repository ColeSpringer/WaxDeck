package api

import (
	"context"
	"net/http"
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
	if info.OwnerName != "" {
		out.Owner = ptr(info.OwnerName)
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
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 50, 200)
	if err != nil {
		return nil, err
	}
	res, err := s.svc.Shares(ctx, uc, derefBool(req.Params.All), deref(req.Params.Cursor), limit)
	if err != nil {
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
		return nil, errNoBody()
	}
	uc := userCtx(ctx)
	var expiresIn time.Duration
	if req.Body.ExpiresInHours != nil {
		if *req.Body.ExpiresInHours < 1 || *req.Body.ExpiresInHours > 8760 {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "expiresInHours must be between 1 and 8760")
		}
		expiresIn = time.Duration(*req.Body.ExpiresInHours) * time.Hour
	}
	info, err := s.svc.CreateShare(ctx, uc, req.Body.Pid, expiresIn,
		derefBool(req.Body.AllowDownload), derefInt64(req.Body.PositionMs))
	if err != nil {
		return nil, err
	}
	return CreateShare201JSONResponse(s.shareJSON(info)), nil
}

func (s *Server) RevokeShare(ctx context.Context, req RevokeShareRequestObject) (RevokeShareResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.RevokeShare(ctx, uc, req.ShareId); err != nil {
		return nil, err
	}
	s.shareTransfers.end(barePID(req.ShareId))
	return RevokeShare204Response{}, nil
}
