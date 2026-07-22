package api

import (
	"context"
	"net/url"

	openapi_types "github.com/oapi-codegen/runtime/types"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Listening statistics and the year in review.

func (s *Server) GetListeningStats(ctx context.Context, req GetListeningStatsRequestObject) (GetListeningStatsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rng, bucket := "30d", "day"
	if req.Params.Range != nil {
		rng = string(*req.Params.Range)
	}
	if req.Params.Bucket != nil {
		bucket = string(*req.Params.Bucket)
	}
	res, err := s.svc.ListeningStats(ctx, uc, rng, bucket)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return GetListeningStats400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := ListeningStats{
		Range:       ListeningStatsRange(res.Range),
		Bucket:      ListeningStatsBucket(res.Bucket),
		Timezone:    res.Timezone,
		TotalMs:     res.TotalMs,
		Sessions:    res.Sessions,
		TimeSavedMs: res.TimeSavedMs,
		Buckets:     []ListeningBucket{},
		ByMediaType: []MediaTypeListening{},
	}
	for _, b := range res.Buckets {
		out.Buckets = append(out.Buckets, ListeningBucket{
			Start:    openapi_types.Date{Time: b.Start},
			Ms:       b.Ms,
			Sessions: b.Sessions,
		})
	}
	for _, m := range res.ByMediaType {
		out.ByMediaType = append(out.ByMediaType, MediaTypeListening{
			MediaType: MediaType(m.MediaType), Ms: m.Ms, Sessions: m.Sessions,
		})
	}
	return GetListeningStats200JSONResponse(out), nil
}

func (s *Server) GetListeningHeatmap(ctx context.Context, req GetListeningHeatmapRequestObject) (GetListeningHeatmapResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.ListeningHeatmap(ctx, uc, year)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return GetListeningHeatmap400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := ListeningHeatmap{
		Year:              res.Year,
		Timezone:          res.Timezone,
		Days:              []HeatmapDay{},
		CurrentStreakDays: res.CurrentStreakDays,
		LongestStreakDays: res.LongestStreakDays,
	}
	for _, d := range res.Days {
		out.Days = append(out.Days, HeatmapDay{
			Date:     openapi_types.Date{Time: d.Date},
			Ms:       d.Ms,
			Sessions: d.Sessions,
		})
	}
	return GetListeningHeatmap200JSONResponse(out), nil
}

func (s *Server) GetTopList(ctx context.Context, req GetTopListRequestObject) (GetTopListResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rng := "30d"
	if req.Params.Range != nil {
		rng = string(*req.Params.Range)
	}
	limit, ok := pageLimit(req.Params.Limit, 10, 100)
	if !ok {
		return GetTopList400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 100"))}, nil
	}
	res, err := s.svc.TopListFor(ctx, uc, string(req.Params.Kind), rng, limit)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return GetTopList400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	return GetTopList200JSONResponse(TopList{
		Kind:    TopListKind(res.Kind),
		Range:   TopListRange(res.Range),
		Entries: topEntriesJSON(res.Entries),
	}), nil
}

func topEntriesJSON(entries []service.TopEntry) []TopEntry {
	out := make([]TopEntry, 0, len(entries))
	for _, e := range entries {
		te := TopEntry{Name: e.Name, Plays: e.Plays, Ms: e.Ms}
		if e.PID != "" {
			te.Pid = ptr(e.PID)
		}
		if e.ArtItemPID != "" {
			te.ArtUrl = ptr("/api/v1/items/" + url.PathEscape(e.ArtItemPID) + "/art")
		}
		out = append(out, te)
	}
	return out
}

func (s *Server) ListListenLog(ctx context.Context, req ListListenLogRequestObject) (ListListenLogResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListListenLog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 200"))}, nil
	}
	res, err := s.svc.ListenLog(ctx, uc, deref(req.Params.Client), deref(req.Params.Cursor), limit)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return ListListenLog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := ListenLogPage{Sessions: []ListenLogEntry{}}
	for _, e := range res.Sessions {
		entry := ListenLogEntry{
			Pid:       e.PID,
			MediaType: MediaType(e.MediaType),
			StartedAt: e.StartedAt,
			MsPlayed:  e.MsPlayed,
			Finished:  e.Finished,
			Client:    e.Client,
			Source:    ListenLogEntrySource(e.Source),
		}
		if e.Title != "" {
			entry.Title = ptr(e.Title)
		}
		if e.Artist != "" {
			entry.Artist = ptr(e.Artist)
		}
		if e.SkippedMs != 0 {
			entry.SkippedMs = ptr(e.SkippedMs)
		}
		out.Sessions = append(out.Sessions, entry)
	}
	if res.Next != "" {
		out.NextCursor = ptr(res.Next)
	}
	return ListListenLog200JSONResponse(out), nil
}

func (s *Server) GetYearInReview(ctx context.Context, req GetYearInReviewRequestObject) (GetYearInReviewResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.UserYearInReview(ctx, uc, year)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return GetYearInReview400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := YearInReview{
		Year:              res.Year,
		Timezone:          res.Timezone,
		TotalMs:           res.TotalMs,
		Sessions:          res.Sessions,
		DistinctItems:     res.DistinctItems,
		NewInLibrary:      res.NewInLibrary,
		TimeSavedMs:       res.TimeSavedMs,
		LongestStreakDays: res.LongestStreakDays,
		ByMonth:           []MonthListening{},
		ByMediaType:       []MediaTypeListening{},
		TopArtists:        topEntriesJSON(res.TopArtists),
		TopTracks:         topEntriesJSON(res.TopTracks),
		TopGenres:         topEntriesJSON(res.TopGenres),
		TopShows:          topEntriesJSON(res.TopShows),
	}
	for _, m := range res.ByMonth {
		out.ByMonth = append(out.ByMonth, MonthListening{Month: m.Month, Ms: m.Ms, Sessions: m.Sessions})
	}
	for _, m := range res.ByMediaType {
		out.ByMediaType = append(out.ByMediaType, MediaTypeListening{
			MediaType: MediaType(m.MediaType), Ms: m.Ms, Sessions: m.Sessions,
		})
	}
	return GetYearInReview200JSONResponse(out), nil
}

func (s *Server) GetServerYearInReview(ctx context.Context, req GetServerYearInReviewRequestObject) (GetServerYearInReviewResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.ServerWideYearInReview(ctx, year)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return GetServerYearInReview400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	return GetServerYearInReview200JSONResponse(ServerYearInReview{
		Year:         res.Year,
		Participants: res.Participants,
		TotalMs:      res.TotalMs,
		Sessions:     res.Sessions,
		TopArtists:   topEntriesJSON(res.TopArtists),
		TopTracks:    topEntriesJSON(res.TopTracks),
		TopGenres:    topEntriesJSON(res.TopGenres),
	}), nil
}
