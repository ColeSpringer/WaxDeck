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
	out := OrganizeProfiles{
		Profiles:         make([]OrganizeProfile, 0, len(profiles.Profiles)),
		ManagedLibraries: profiles.ManagedLibraries,
	}
	for _, p := range profiles.Profiles {
		out.Profiles = append(out.Profiles, organizeProfileJSON(p))
	}
	return ListOrganizeProfiles200JSONResponse(out), nil
}

func organizeProfileJSON(p service.OrganizeProfileDTO) OrganizeProfile {
	out := OrganizeProfile{
		Name: p.Name, MusicTemplate: p.Music, AudiobookTemplate: p.Audiobook, PodcastTemplate: p.Podcast,
		TagWrite: p.TagWrite, BuiltIn: p.BuiltIn, Sample: organizeSampleJSON(p.Sample),
	}
	if p.Saved != nil {
		out.Saved = &OrganizeTemplates{MusicTemplate: p.Saved.Music, AudiobookTemplate: p.Saved.Audiobook,
			PodcastTemplate: p.Saved.Podcast}
	}
	return out
}

func organizeSampleJSON(s service.OrganizeSampleDTO) OrganizeSample {
	return OrganizeSample{Music: s.Music, Audiobook: s.Audiobook, Podcast: s.Podcast}
}

func (s *Server) PutOrganizeProfile(ctx context.Context, req PutOrganizeProfileRequestObject) (PutOrganizeProfileResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PutOrganizeProfile400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a profile body is required"))}, nil
	}
	in := service.OrganizeProfileInput{
		Music: deref(req.Body.MusicTemplate), Audiobook: deref(req.Body.AudiobookTemplate),
		Podcast: deref(req.Body.PodcastTemplate), TagWrite: derefBool(req.Body.TagWrite),
	}
	p, err := s.svc.PutOrganizeProfile(ctx, uc, req.Name, in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PutOrganizeProfile400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return PutOrganizeProfile403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return PutOrganizeProfile200JSONResponse(organizeProfileJSON(p)), nil
}

func (s *Server) DeleteOrganizeProfile(ctx context.Context, req DeleteOrganizeProfileRequestObject) (DeleteOrganizeProfileResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeleteOrganizeProfile(ctx, uc, req.Name); err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return DeleteOrganizeProfile400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return DeleteOrganizeProfile403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return DeleteOrganizeProfile404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		case service.KindConflict:
			return DeleteOrganizeProfile409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return DeleteOrganizeProfile204Response{}, nil
}

func (s *Server) PreviewOrganizeProfile(ctx context.Context, req PreviewOrganizeProfileRequestObject) (PreviewOrganizeProfileResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PreviewOrganizeProfile400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a profile body is required"))}, nil
	}
	in := service.OrganizeProfileInput{
		Music: deref(req.Body.MusicTemplate), Audiobook: deref(req.Body.AudiobookTemplate),
		Podcast: deref(req.Body.PodcastTemplate), TagWrite: derefBool(req.Body.TagWrite),
	}
	sample, err := s.svc.PreviewOrganizeProfile(ctx, uc, deref(req.Body.Name), in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PreviewOrganizeProfile400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return PreviewOrganizeProfile403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return PreviewOrganizeProfile200JSONResponse(organizeSampleJSON(sample)), nil
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
	plan, err := s.svc.PreviewOrganize(ctx, uc, deref(req.Body.Profile), pids)
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
		Profile:           plan.Profile,
		TotalActions:      plan.TotalActions,
		Held:              plan.Held,
		ReadOnlyLibraries: plan.ReadOnlyLibraries,
		TagWrite:          ptr(plan.TagWrite),
		Actions:           make([]OrganizeAction, 0, len(plan.Actions)),
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
	rep, err := s.svc.ApplyOrganize(ctx, uc, deref(req.Body.Profile), pids)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ApplyOrganize400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return ApplyOrganize403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := OrganizeReport{Moved: rep.Moved, Skipped: rep.Skipped, Held: rep.Held,
		ReadOnlyLibraries: rep.ReadOnlyLibraries, Failed: rep.Failed}
	if len(rep.Failures) > 0 {
		failures := make([]OrganizeFailure, 0, len(rep.Failures))
		for _, f := range rep.Failures {
			failures = append(failures, OrganizeFailure{Path: f.Path, Reason: f.Reason})
		}
		out.Failures = ptr(failures)
	}
	return ApplyOrganize200JSONResponse(out), nil
}
