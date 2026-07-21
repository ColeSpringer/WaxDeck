package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Organize handlers: profile listing, dry-run previews, and applies.

func (s *Server) ListOrganizeProfiles(ctx context.Context, _ ListOrganizeProfilesRequestObject) (ListOrganizeProfilesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	profiles, err := s.svc.OrganizeProfilesFor(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return ListOrganizeProfiles403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := OrganizeProfiles{Profiles: make([]OrganizeProfile, 0, len(profiles))}
	for _, p := range profiles {
		// Templates and the tag-write flag are not readable through the
		// catalog facade, so the listing carries names only.
		out.Profiles = append(out.Profiles, OrganizeProfile{Name: p.Name})
	}
	return ListOrganizeProfiles200JSONResponse(out), nil
}

func (s *Server) PreviewOrganize(ctx context.Context, req PreviewOrganizeRequestObject) (PreviewOrganizeResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PreviewOrganize400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an organize body is required"))}, nil
	}
	var pids []string
	if req.Body.ItemPids != nil {
		pids = *req.Body.ItemPids
	}
	plan, err := s.svc.PreviewOrganize(ctx, uc, req.Body.Profile, pids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PreviewOrganize400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return PreviewOrganize403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := OrganizePlan{
		Profile:      plan.Profile,
		TotalActions: plan.TotalActions,
		TagWrite:     ptr(plan.TagWrite),
		Actions:      make([]OrganizeAction, 0, len(plan.Actions)),
	}
	for _, a := range plan.Actions {
		out.Actions = append(out.Actions, OrganizeAction{ItemPid: a.ItemPID, From: a.From, To: a.To})
	}
	return PreviewOrganize200JSONResponse(out), nil
}

func (s *Server) ApplyOrganize(ctx context.Context, req ApplyOrganizeRequestObject) (ApplyOrganizeResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return ApplyOrganize400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an organize body is required"))}, nil
	}
	var pids []string
	if req.Body.ItemPids != nil {
		pids = *req.Body.ItemPids
	}
	rep, err := s.svc.ApplyOrganize(ctx, uc, req.Body.Profile, pids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ApplyOrganize400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return ApplyOrganize403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := OrganizeReport{Moved: rep.Moved, Skipped: rep.Skipped, Failed: rep.Failed}
	if len(rep.Failures) > 0 {
		failures := make([]OrganizeFailure, 0, len(rep.Failures))
		for _, f := range rep.Failures {
			failures = append(failures, OrganizeFailure{Path: f.Path, Reason: f.Reason})
		}
		out.Failures = ptr(failures)
	}
	return ApplyOrganize200JSONResponse(out), nil
}
