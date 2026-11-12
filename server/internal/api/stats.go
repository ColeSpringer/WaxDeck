package api

import (
	"context"
	"net/url"
	"strings"

	openapi_types "github.com/oapi-codegen/runtime/types"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Listening statistics and the year in review.

func (s *Server) GetListeningStats(ctx context.Context, req GetListeningStatsRequestObject) (GetListeningStatsResponseObject, error) {
	uc := userCtx(ctx)
	rng, bucket := "30d", "day"
	if req.Params.Range != nil {
		rng = string(*req.Params.Range)
	}
	if req.Params.Bucket != nil {
		bucket = string(*req.Params.Bucket)
	}
	res, err := s.svc.Reads.ListeningStats(ctx, uc, rng, bucket)
	if err != nil {
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
			MediaType: StatsMediaType(m.MediaType), Ms: m.Ms, Sessions: m.Sessions,
		})
	}
	return GetListeningStats200JSONResponse(out), nil
}

func (s *Server) GetListeningHeatmap(ctx context.Context, req GetListeningHeatmapRequestObject) (GetListeningHeatmapResponseObject, error) {
	uc := userCtx(ctx)
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.Reads.ListeningHeatmap(ctx, uc, year)
	if err != nil {
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
	uc := userCtx(ctx)
	rng := "30d"
	if req.Params.Range != nil {
		rng = string(*req.Params.Range)
	}
	limit, err := pageLimit(req.Params.Limit, 10, 100)
	if err != nil {
		return nil, err
	}
	res, err := s.svc.Reads.TopListFor(ctx, uc, string(req.Params.Kind), rng, limit)
	if err != nil {
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
			// A station's picture comes from the logo proxy, not from
			// the item store: it is not a catalog item, and the item
			// art route would answer 404 for every entry in a Top
			// stations list.
			if strings.HasPrefix(e.ArtItemPID, service.PrefixRadioStation+"-") {
				te.ArtUrl = ptr("/api/v1/radio/stations/" + url.PathEscape(e.ArtItemPID) + "/logo")
			} else {
				te.ArtUrl = ptr("/api/v1/items/" + url.PathEscape(e.ArtItemPID) + "/art")
			}
		}
		out = append(out, te)
	}
	return out
}

func (s *Server) ListListenLog(ctx context.Context, req ListListenLogRequestObject) (ListListenLogResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 50, 200)
	if err != nil {
		return nil, err
	}
	res, err := s.svc.Reads.ListenLog(ctx, uc, deref(req.Params.Client), deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	out := ListenLogPage{Sessions: []ListenLogEntry{}}
	for _, e := range res.Sessions {
		entry := ListenLogEntry{
			Pid:       e.PID,
			MediaType: StatsMediaType(e.MediaType),
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
	uc := userCtx(ctx)
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.Reads.UserYearInReview(ctx, uc, year)
	if err != nil {
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
			MediaType: StatsMediaType(m.MediaType), Ms: m.Ms, Sessions: m.Sessions,
		})
	}
	return GetYearInReview200JSONResponse(out), nil
}

func (s *Server) GetServerYearInReview(ctx context.Context, req GetServerYearInReviewRequestObject) (GetServerYearInReviewResponseObject, error) {
	uc := userCtx(ctx)
	year := 0
	if req.Params.Year != nil {
		year = *req.Params.Year
	}
	res, err := s.svc.Reads.ServerWideYearInReview(ctx, uc, year)
	if err != nil {
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
