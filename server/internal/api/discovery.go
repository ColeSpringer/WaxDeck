package api

import (
	"context"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Discovery: similar tracks, instant mixes, and sonic paths.

func (s *Server) GetSimilarTracks(ctx context.Context, req GetSimilarTracksRequestObject) (GetSimilarTracksResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 20, 100)
	if err != nil {
		return nil, err
	}
	res, err := s.svc.SimilarTracksFor(ctx, uc, req.Pid, limit)
	if err != nil {
		return nil, err
	}
	out := SimilarTracks{Basis: MixBasis(res.Basis), Items: []ItemSummary{}}
	for _, it := range res.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return GetSimilarTracks200JSONResponse(out), nil
}

func (s *Server) CreateInstantMix(ctx context.Context, req CreateInstantMixRequestObject) (CreateInstantMixResponseObject, error) {
	if req.Body == nil {
		return nil, errNoBody()
	}
	uc := userCtx(ctx)
	in := service.InstantMixInput{
		SeedPID:         deref(req.Body.SeedPid),
		Genre:           deref(req.Body.Genre),
		Adventurousness: 0.4,
	}
	if req.Body.Adventurousness != nil {
		in.Adventurousness = float64(*req.Body.Adventurousness)
		if in.Adventurousness < 0 || in.Adventurousness > 1 {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "adventurousness must be between 0 and 1")
		}
	}
	if req.Body.Size != nil {
		in.Size = *req.Body.Size
		if in.Size < 1 || in.Size > 200 {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "size must be between 1 and 200")
		}
	}
	if req.Body.ExcludePids != nil {
		if len(*req.Body.ExcludePids) > 500 {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "at most 500 excludePids")
		}
		in.ExcludePIDs = *req.Body.ExcludePids
	}
	res, err := s.svc.InstantMix(ctx, uc, in)
	if err != nil {
		return nil, err
	}
	out := InstantMix{Basis: MixBasis(res.Basis), Items: []ItemSummary{}, Excluded: &res.Excluded}
	for _, it := range res.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return CreateInstantMix200JSONResponse(out), nil
}

func (s *Server) GetSonicPath(ctx context.Context, req GetSonicPathRequestObject) (GetSonicPathResponseObject, error) {
	uc := userCtx(ctx)
	length := 12
	if req.Params.Length != nil {
		length = *req.Params.Length
		if length < 3 || length > 50 {
			return nil, refuse(http.StatusBadRequest, "invalid-request", "length must be between 3 and 50")
		}
	}
	res, err := s.svc.SonicPathFor(ctx, uc, req.Params.From, req.Params.To, length)
	if err != nil {
		return nil, err
	}
	out := SonicPath{Complete: res.Complete, Items: []ItemSummary{}}
	for _, it := range res.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return GetSonicPath200JSONResponse(out), nil
}
