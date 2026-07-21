package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Review queue handlers: listing, evidence, decisions, calibration.

func reviewEntryJSON(e service.ReviewEntryDTO) ReviewEntry {
	out := ReviewEntry{
		Id:          e.ID,
		Kind:        e.Kind,
		Status:      e.Status,
		MediaType:   MediaType(e.MediaType),
		Origin:      e.Origin,
		TrackCount:  e.TrackCount,
		Identifying: e.Identifying,
		CreatedAt:   e.CreatedAt,
	}
	if e.Title != "" {
		out.Title = ptr(e.Title)
	}
	if e.Artist != "" {
		out.Artist = ptr(e.Artist)
	}
	if e.LibraryPID != "" {
		out.LibraryPid = ptr(e.LibraryPID)
	}
	if e.UploadedBy != "" {
		out.UploadedBy = ptr(e.UploadedBy)
	}
	if e.AppliedMBID != "" {
		out.AppliedMbid = ptr(e.AppliedMBID)
	}
	if !e.DecidedAt.IsZero() {
		out.DecidedAt = ptr(e.DecidedAt)
	}
	if e.DecidedBy != "" {
		out.DecidedBy = ptr(e.DecidedBy)
	}
	if e.Best != nil {
		out.Best = &CandidateSummary{
			Mbid: e.Best.MBID, Title: e.Best.Title, Artist: e.Best.Artist,
			SimilarityPct: e.Best.SimilarityPct,
		}
		if e.Best.Year > 0 {
			out.Best.Year = ptr(e.Best.Year)
		}
	}
	return out
}

func (s *Server) ListReviewQueue(ctx context.Context, req ListReviewQueueRequestObject) (ListReviewQueueResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListReviewQueue400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	entries, next, err := s.svc.ListReviewQueue(ctx, uc, deref(req.Params.Status), deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListReviewQueue400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	page := ReviewEntryPage{Entries: make([]ReviewEntry, 0, len(entries))}
	for _, e := range entries {
		page.Entries = append(page.Entries, reviewEntryJSON(e))
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	return ListReviewQueue200JSONResponse(page), nil
}

func (s *Server) GetReviewEntry(ctx context.Context, req GetReviewEntryRequestObject) (GetReviewEntryResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	detail, err := s.svc.GetReviewEntry(ctx, uc, string(req.EntryId))
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetReviewEntry404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such review entry"))}, nil
		}
		return nil, err
	}
	return GetReviewEntry200JSONResponse(reviewDetailJSON(detail)), nil
}

func reviewDetailJSON(d service.ReviewDetailDTO) ReviewEntryDetail {
	base := reviewEntryJSON(d.ReviewEntryDTO)
	out := ReviewEntryDetail{
		Id: base.Id, Kind: base.Kind, Status: base.Status, MediaType: base.MediaType,
		Origin: base.Origin, TrackCount: base.TrackCount, Identifying: base.Identifying,
		CreatedAt: base.CreatedAt, Title: base.Title, Artist: base.Artist,
		LibraryPid: base.LibraryPid, UploadedBy: base.UploadedBy, AppliedMbid: base.AppliedMbid,
		DecidedAt: base.DecidedAt, DecidedBy: base.DecidedBy, Best: base.Best,
		Tracks:     make([]ReviewTrack, 0, len(d.Tracks)),
		Candidates: make([]ReviewCandidate, 0, len(d.Candidates)),
	}
	for _, t := range d.Tracks {
		rt := ReviewTrack{Path: t.Path, Title: t.Title, DurationMs: t.DurationMS}
		if t.PID != "" {
			rt.Pid = ptr(t.PID)
		}
		if t.Artist != "" {
			rt.Artist = ptr(t.Artist)
		}
		if t.TrackNo > 0 {
			rt.TrackNo = ptr(t.TrackNo)
		}
		if t.DiscNo > 0 {
			rt.DiscNo = ptr(t.DiscNo)
		}
		out.Tracks = append(out.Tracks, rt)
	}
	for _, c := range d.Candidates {
		rc := ReviewCandidate{
			Mbid: c.MBID, Title: c.Title, Artist: c.Artist, SimilarityPct: c.SimilarityPct,
			Pairings: make([]CandidatePairing, 0, len(c.Pairings)),
		}
		if c.ReleaseGroupMBID != "" {
			rc.ReleaseGroupMbid = ptr(c.ReleaseGroupMBID)
		}
		if c.Year > 0 {
			rc.Year = ptr(c.Year)
		}
		if c.MediaCount > 0 {
			rc.MediaCount = ptr(c.MediaCount)
		}
		if c.TrackCount > 0 {
			rc.TrackCount = ptr(c.TrackCount)
		}
		if c.Country != "" {
			rc.Country = ptr(c.Country)
		}
		if c.Label != "" {
			rc.Label = ptr(c.Label)
		}
		if c.CatalogNumber != "" {
			rc.CatalogNumber = ptr(c.CatalogNumber)
		}
		if c.Compilation {
			rc.Compilation = ptr(true)
		}
		if len(c.Components) > 0 {
			comps := make([]CandidateComponent, 0, len(c.Components))
			for _, comp := range c.Components {
				comps = append(comps, CandidateComponent{
					Name: comp.Name, Distance: comp.Distance, Weight: comp.Weight,
				})
			}
			rc.Components = ptr(comps)
		}
		for _, p := range c.Pairings {
			cp := CandidatePairing{
				TrackIndex: p.TrackIndex, Position: p.Position, Title: p.Title, Distance: p.Distance,
			}
			if p.Disc > 0 {
				cp.Disc = ptr(p.Disc)
			}
			if p.Artist != "" {
				cp.Artist = ptr(p.Artist)
			}
			if p.DurationMS > 0 {
				cp.DurationMs = ptr(p.DurationMS)
			}
			if p.RecordingMBID != "" {
				cp.RecordingMbid = ptr(p.RecordingMBID)
			}
			rc.Pairings = append(rc.Pairings, cp)
		}
		if len(c.MissingTitles) > 0 {
			rc.MissingTitles = ptr(append([]string{}, c.MissingTitles...))
		}
		if len(c.ExtraIndexes) > 0 {
			rc.ExtraTrackIndexes = ptr(append([]int{}, c.ExtraIndexes...))
		}
		out.Candidates = append(out.Candidates, rc)
	}
	return out
}

func (s *Server) DecideReviewEntry(ctx context.Context, req DecideReviewEntryRequestObject) (DecideReviewEntryResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return DecideReviewEntry400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a decision body is required"))}, nil
	}
	entry, warnings, err := s.svc.DecideReviewEntry(ctx, uc, string(req.EntryId),
		string(req.Body.Action), deref(req.Body.CandidateMbid))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return DecideReviewEntry400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return DecideReviewEntry403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return DecideReviewEntry404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such review entry"))}, nil
		case service.KindConflict:
			return DecideReviewEntry409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	result := ReviewDecideResult{Entry: reviewEntryJSON(entry)}
	if len(warnings) > 0 {
		result.Warnings = ptr(warnings)
	}
	return DecideReviewEntry200JSONResponse(result), nil
}

func (s *Server) RevertReviewEntry(ctx context.Context, req RevertReviewEntryRequestObject) (RevertReviewEntryResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	entry, err := s.svc.RevertReviewEntry(ctx, uc, string(req.EntryId))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindForbidden:
			return RevertReviewEntry403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return RevertReviewEntry404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such review entry"))}, nil
		case service.KindConflict:
			return RevertReviewEntry409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return RevertReviewEntry200JSONResponse(reviewEntryJSON(entry)), nil
}

func (s *Server) DecideReviewBulk(ctx context.Context, req DecideReviewBulkRequestObject) (DecideReviewBulkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil || len(req.Body.EntryIds) == 0 {
		return DecideReviewBulk400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "entryIds are required"))}, nil
	}
	if len(req.Body.EntryIds) > 200 {
		return DecideReviewBulk400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 200 entries per bulk decision"))}, nil
	}
	outcomes := s.svc.DecideReviewBulk(ctx, uc, req.Body.EntryIds, string(req.Body.Action))
	result := ReviewBulkResult{Results: make([]ReviewBulkOutcome, 0, len(outcomes))}
	for _, o := range outcomes {
		ro := ReviewBulkOutcome{EntryId: o.EntryID, Ok: o.OK}
		if o.Error != "" {
			ro.Error = ptr(o.Error)
		}
		result.Results = append(result.Results, ro)
	}
	return DecideReviewBulk200JSONResponse(result), nil
}

func (s *Server) GetReviewStats(ctx context.Context, _ GetReviewStatsRequestObject) (GetReviewStatsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	_ = uc
	stats, err := s.svc.ReviewStatsFor(ctx)
	if err != nil {
		return nil, err
	}
	out := ReviewStats{
		Pending:             stats.Pending,
		Applied:             stats.Applied,
		AutoApplied:         stats.AutoApplied,
		Reverted:            stats.Reverted,
		RevertedAutoApplied: stats.RevertedAutoApplied,
	}
	if stats.Identifying > 0 {
		out.Identifying = ptr(stats.Identifying)
	}
	if stats.AsIs > 0 {
		out.AsIs = ptr(stats.AsIs)
	}
	if stats.Unofficial > 0 {
		out.Unofficial = ptr(stats.Unofficial)
	}
	if stats.Skipped > 0 {
		out.Skipped = ptr(stats.Skipped)
	}
	return GetReviewStats200JSONResponse(out), nil
}

func (s *Server) GetLibraryMatching(ctx context.Context, req GetLibraryMatchingRequestObject) (GetLibraryMatchingResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	mode, err := s.svc.LibraryMatchingFor(ctx, uc, string(req.Pid))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindForbidden:
			return GetLibraryMatching403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return GetLibraryMatching404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such library"))}, nil
		}
		return nil, err
	}
	return GetLibraryMatching200JSONResponse(LibraryMatching{Mode: LibraryMatchingMode(mode)}), nil
}

func (s *Server) SetLibraryMatching(ctx context.Context, req SetLibraryMatchingRequestObject) (SetLibraryMatchingResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return SetLibraryMatching400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a mode body is required"))}, nil
	}
	if err := s.svc.SetLibraryMatchingMode(ctx, uc, string(req.Pid), string(req.Body.Mode)); err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetLibraryMatching400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return SetLibraryMatching403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return SetLibraryMatching404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such library"))}, nil
		}
		return nil, err
	}
	return SetLibraryMatching200JSONResponse(LibraryMatching{Mode: req.Body.Mode}), nil
}
