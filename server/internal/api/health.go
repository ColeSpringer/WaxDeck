package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Library health handlers: the summary, the issues worklist, sweeps,
// bulk fixes, duplicates, and quality upgrades.

func (s *Server) GetLibraryHealth(ctx context.Context, _ GetLibraryHealthRequestObject) (GetLibraryHealthResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	sum, err := s.svc.HealthSummaryFor(ctx)
	if err != nil {
		return nil, err
	}
	out := HealthSummary{
		Score:          sum.Score,
		TotalItems:     sum.TotalItems,
		EvaluatedItems: sum.EvaluatedItems,
		WarmingUp:      sum.WarmingUp,
		Rules:          make([]HealthRuleCount, 0, len(sum.Rules)),
	}
	if !sum.SweptAt.IsZero() {
		out.SweptAt = ptr(sum.SweptAt)
	}
	for _, r := range sum.Rules {
		rc := HealthRuleCount{Rule: r.Rule, Failing: r.Failing, Fixable: r.Fixable}
		if r.Label != "" {
			rc.Label = ptr(r.Label)
		}
		out.Rules = append(out.Rules, rc)
	}
	return GetLibraryHealth200JSONResponse(out), nil
}

func (s *Server) ListHealthIssues(ctx context.Context, req ListHealthIssuesRequestObject) (ListHealthIssuesResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return ListHealthIssues400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	items, next, err := s.svc.ListHealthIssuesFor(ctx, deref(req.Params.Rule), deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListHealthIssues400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	page := HealthIssuePage{Items: make([]HealthIssue, 0, len(items))}
	for _, it := range items {
		hi := HealthIssue{
			Pid:       it.PID,
			MediaType: MediaType(it.MediaType),
			Title:     it.Title,
			Rules:     it.Rules,
		}
		if hi.Rules == nil {
			hi.Rules = []string{}
		}
		if it.Artist != "" {
			hi.Artist = ptr(it.Artist)
		}
		page.Items = append(page.Items, hi)
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	return ListHealthIssues200JSONResponse(page), nil
}

func (s *Server) SweepLibraryHealth(ctx context.Context, _ SweepLibraryHealthRequestObject) (SweepLibraryHealthResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.QueueHealthSweep(ctx, uc); err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return SweepLibraryHealth403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return SweepLibraryHealth202Response{}, nil
}

func (s *Server) FixHealthIssues(ctx context.Context, req FixHealthIssuesRequestObject) (FixHealthIssuesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return FixHealthIssues400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a fix body is required"))}, nil
	}
	var pids []string
	if req.Body.ItemPids != nil {
		pids = *req.Body.ItemPids
	}
	queued, err := s.svc.QueueHealthFix(ctx, uc, req.Body.Rule, pids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return FixHealthIssues400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return FixHealthIssues403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return FixHealthIssues202JSONResponse(HealthFixResult{Queued: queued}), nil
}

func (s *Server) ListDuplicates(ctx context.Context, _ ListDuplicatesRequestObject) (ListDuplicatesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	groups, err := s.svc.ListDuplicateGroups(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return ListDuplicates403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := DuplicateGroups{Groups: make([]DuplicateGroup, 0, len(groups))}
	for _, g := range groups {
		dg := DuplicateGroup{
			EntityType: g.EntityType,
			Survivor:   DuplicateEntity{Pid: g.Survivor.PID, Name: g.Survivor.Name},
			Losers:     make([]DuplicateEntity, 0, len(g.Losers)),
		}
		if g.Detail != "" {
			dg.Detail = ptr(g.Detail)
		}
		for _, m := range g.Losers {
			dg.Losers = append(dg.Losers, DuplicateEntity{Pid: m.PID, Name: m.Name})
		}
		out.Groups = append(out.Groups, dg)
	}
	return ListDuplicates200JSONResponse(out), nil
}

func (s *Server) MergeDuplicates(ctx context.Context, req MergeDuplicatesRequestObject) (MergeDuplicatesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return MergeDuplicates400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a merge body is required"))}, nil
	}
	if !req.Body.EntityType.Valid() {
		return MergeDuplicates400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown entity type"))}, nil
	}
	res, err := s.svc.MergeDuplicates(ctx, uc, string(req.Body.EntityType), req.Body.SurvivorPid, req.Body.LoserPids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return MergeDuplicates400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return MergeDuplicates403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return MergeDuplicates404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such entity"))}, nil
		}
		return nil, err
	}
	return MergeDuplicates200JSONResponse(MergeResult{Merged: res.Merged, ChildrenMoved: res.ChildrenMoved}), nil
}

func (s *Server) ListUpgrades(ctx context.Context, _ ListUpgradesRequestObject) (ListUpgradesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	groups, err := s.svc.ListUpgradeGroups(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return ListUpgrades403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := UpgradeGroups{Groups: make([]UpgradeGroup, 0, len(groups))}
	for _, g := range groups {
		ug := UpgradeGroup{Members: make([]UpgradeMember, 0, len(g.Members))}
		for _, m := range g.Members {
			um := UpgradeMember{
				ItemPid:  m.ItemPID,
				Title:    m.Title,
				Codec:    m.Codec,
				Lossless: m.Lossless,
				Best:     m.Best,
			}
			if m.Artist != "" {
				um.Artist = ptr(m.Artist)
			}
			if m.Bitrate > 0 {
				um.Bitrate = ptr(m.Bitrate)
			}
			if m.SampleRate > 0 {
				um.SampleRate = ptr(m.SampleRate)
			}
			if m.BitDepth > 0 {
				um.BitDepth = ptr(m.BitDepth)
			}
			ug.Members = append(ug.Members, um)
		}
		out.Groups = append(out.Groups, ug)
	}
	return ListUpgrades200JSONResponse(out), nil
}

func (s *Server) ResolveUpgrade(ctx context.Context, req ResolveUpgradeRequestObject) (ResolveUpgradeResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return ResolveUpgrade400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a resolve body is required"))}, nil
	}
	trashed, err := s.svc.ResolveUpgrade(ctx, uc, req.Body.KeepItemPid, req.Body.RemoveItemPids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ResolveUpgrade400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return ResolveUpgrade403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return ResolveUpgrade404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such item"))}, nil
		}
		return nil, err
	}
	return ResolveUpgrade200JSONResponse(UpgradeResolveResult{Trashed: trashed}), nil
}
