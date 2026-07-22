package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Discovery: similar tracks, instant mixes, and sonic paths.

func (s *Server) GetSimilarTracks(ctx context.Context, req GetSimilarTracksRequestObject) (GetSimilarTracksResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 20, 100)
	if !ok {
		return GetSimilarTracks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 100"))}, nil
	}
	res, err := s.svc.SimilarTracksFor(ctx, uc, req.Pid, limit)
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return GetSimilarTracks404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindInvalid:
		return GetSimilarTracks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
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
		return CreateInstantMix400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	in := service.InstantMixInput{
		SeedPID:         deref(req.Body.SeedPid),
		Genre:           deref(req.Body.Genre),
		Adventurousness: 0.4,
	}
	if req.Body.Adventurousness != nil {
		in.Adventurousness = float64(*req.Body.Adventurousness)
		if in.Adventurousness < 0 || in.Adventurousness > 1 {
			return CreateInstantMix400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "adventurousness must be between 0 and 1"))}, nil
		}
	}
	if req.Body.Size != nil {
		in.Size = *req.Body.Size
		if in.Size < 1 || in.Size > 200 {
			return CreateInstantMix400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "size must be between 1 and 200"))}, nil
		}
	}
	if req.Body.ExcludePids != nil {
		if len(*req.Body.ExcludePids) > 500 {
			return CreateInstantMix400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 500 excludePids"))}, nil
		}
		in.ExcludePIDs = *req.Body.ExcludePids
	}
	res, err := s.svc.InstantMix(ctx, uc, in)
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return CreateInstantMix404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindInvalid:
		return CreateInstantMix400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := InstantMix{Basis: MixBasis(res.Basis), Items: []ItemSummary{}}
	for _, it := range res.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return CreateInstantMix200JSONResponse(out), nil
}

func (s *Server) GetSonicPath(ctx context.Context, req GetSonicPathRequestObject) (GetSonicPathResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	length := 12
	if req.Params.Length != nil {
		length = *req.Params.Length
		if length < 3 || length > 50 {
			return GetSonicPath400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "length must be between 3 and 50"))}, nil
		}
	}
	res, err := s.svc.SonicPathFor(ctx, uc, req.Params.From, req.Params.To, length)
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return GetSonicPath404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindInvalid:
		return GetSonicPath400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	case service.KindFeature:
		return GetSonicPath501JSONResponse{FeatureUnavailableJSONResponse(errObj("feature-unavailable", err.Error()))}, nil
	default:
		return nil, err
	}
	out := SonicPath{Complete: res.Complete, Items: []ItemSummary{}}
	for _, it := range res.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return GetSonicPath200JSONResponse(out), nil
}
