package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Organize handlers: profile listing, dry-run previews, and applies.

func (s *Server) ListOrganizeProfiles(ctx context.Context, _ ListOrganizeProfilesRequestObject) (ListOrganizeProfilesResponseObject, error) {
	uc := userCtx(ctx)
	profiles, err := s.svc.Health.OrganizeProfilesFor(ctx, uc)
	if err != nil {
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
		TagWrite: p.TagWrite, CompilationFolder: p.CompilationFolder, BuiltIn: p.BuiltIn, Sample: organizeSampleJSON(p.Sample),
	}
	if p.Saved != nil {
		out.Saved = &OrganizeTemplates{MusicTemplate: p.Saved.Music, AudiobookTemplate: p.Saved.Audiobook,
			PodcastTemplate: p.Saved.Podcast}
	}
	return out
}

func organizeSampleJSON(s service.OrganizeSampleDTO) OrganizeSample {
	return OrganizeSample{Music: s.Music, Audiobook: s.Audiobook, Podcast: s.Podcast, Compilation: s.Compilation}
}

func (s *Server) PutOrganizeProfile(ctx context.Context, req PutOrganizeProfileRequestObject) (PutOrganizeProfileResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	in := service.OrganizeProfileInput{
		Music: deref(req.Body.MusicTemplate), Audiobook: deref(req.Body.AudiobookTemplate),
		Podcast: deref(req.Body.PodcastTemplate), TagWrite: derefBool(req.Body.TagWrite),
		CompilationFolder: req.Body.CompilationFolder,
	}
	p, err := s.svc.Health.PutOrganizeProfile(ctx, uc, req.Name, in)
	if err != nil {
		return nil, err
	}
	return PutOrganizeProfile200JSONResponse(organizeProfileJSON(p)), nil
}

func (s *Server) DeleteOrganizeProfile(ctx context.Context, req DeleteOrganizeProfileRequestObject) (DeleteOrganizeProfileResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.Health.DeleteOrganizeProfile(ctx, uc, req.Name); err != nil {
		return nil, err
	}
	return DeleteOrganizeProfile204Response{}, nil
}

func (s *Server) PreviewOrganizeProfile(ctx context.Context, req PreviewOrganizeProfileRequestObject) (PreviewOrganizeProfileResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	in := service.OrganizeProfileInput{
		Music: deref(req.Body.MusicTemplate), Audiobook: deref(req.Body.AudiobookTemplate),
		Podcast: deref(req.Body.PodcastTemplate), TagWrite: derefBool(req.Body.TagWrite),
		CompilationFolder: req.Body.CompilationFolder,
	}
	sample, err := s.svc.Health.PreviewOrganizeProfile(ctx, uc, deref(req.Body.Name), in)
	if err != nil {
		return nil, err
	}
	return PreviewOrganizeProfile200JSONResponse(organizeSampleJSON(sample)), nil
}

func (s *Server) PreviewOrganize(ctx context.Context, req PreviewOrganizeRequestObject) (PreviewOrganizeResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	var pids []string
	if req.Body.ItemPids != nil {
		pids = *req.Body.ItemPids
	}
	plan, err := s.svc.Health.PreviewOrganize(ctx, uc, deref(req.Body.Profile), pids)
	if err != nil {
		return nil, err
	}
	out := OrganizePlan{
		Profile:           plan.Profile,
		TotalActions:      plan.TotalActions,
		Held:              plan.Held,
		HeldByCode:        ptr(plan.HeldByCode),
		Holds:             organizeHoldsJSON(plan.Holds),
		ReadOnlyLibraries: plan.ReadOnlyLibraries,
		TagWrite:          ptr(plan.TagWrite),
		Actions:           make([]OrganizeAction, 0, len(plan.Actions)),
	}
	for _, a := range plan.Actions {
		out.Actions = append(out.Actions, OrganizeAction{ItemPid: a.ItemPID, From: a.From, To: a.To})
	}
	return PreviewOrganize200JSONResponse(out), nil
}

// organizeHoldsJSON is a plan's or a report's holds, absent when none.
func organizeHoldsJSON(holds []service.OrganizeHoldDTO) *[]OrganizeHold {
	if len(holds) == 0 {
		return nil
	}
	out := make([]OrganizeHold, 0, len(holds))
	for _, h := range holds {
		hold := OrganizeHold{From: h.From, Code: OrganizeHoldCode(h.Code), Reason: h.Reason}
		if h.ItemPID != "" {
			hold.ItemPid = ptr(h.ItemPID)
		}
		if h.To != "" {
			hold.To = ptr(h.To)
		}
		out = append(out, hold)
	}
	return &out
}

func (s *Server) ApplyOrganize(ctx context.Context, req ApplyOrganizeRequestObject) (ApplyOrganizeResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	var pids []string
	if req.Body.ItemPids != nil {
		pids = *req.Body.ItemPids
	}
	rep, err := s.svc.Health.ApplyOrganize(ctx, uc, deref(req.Body.Profile), pids)
	if err != nil {
		return nil, err
	}
	return ApplyOrganize200JSONResponse(organizeReportJSON(rep)), nil
}

func organizeReportJSON(rep service.OrganizeReportDTO) OrganizeReport {
	out := OrganizeReport{JobPid: rep.JobPID, Moved: rep.Moved, Skipped: rep.Skipped, Held: rep.Held,
		Holds: organizeHoldsJSON(rep.Holds), ReadOnlyLibraries: rep.ReadOnlyLibraries, Failed: rep.Failed,
		DirsPruned: ptr(rep.DirsPruned)}
	if len(rep.Failures) > 0 {
		failures := make([]OrganizeFailure, 0, len(rep.Failures))
		for _, f := range rep.Failures {
			failures = append(failures, OrganizeFailure{Path: f.Path, Reason: f.Reason})
		}
		out.Failures = ptr(failures)
	}
	return out
}

func (s *Server) ListOrganizeHistory(ctx context.Context, req ListOrganizeHistoryRequestObject) (ListOrganizeHistoryResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 20, 100)
	if err != nil {
		return nil, err
	}
	runs, next, err := s.svc.Health.OrganizeHistory(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	out := OrganizeHistory{Batches: make([]OrganizeBatch, 0, len(runs))}
	for _, r := range runs {
		b := OrganizeBatch{JobPid: r.JobPID, Kind: OrganizeBatchKind(r.Kind), State: r.State, StartedAt: r.StartedAt,
			Committed: r.Committed, RolledBack: r.RolledBack, Planned: r.Planned, Undoable: r.Undoable}
		if r.Profile != "" {
			b.Profile = ptr(r.Profile)
		}
		out.Batches = append(out.Batches, b)
	}
	if next != "" {
		out.NextCursor = ptr(next)
	}
	return ListOrganizeHistory200JSONResponse(out), nil
}

func (s *Server) UndoOrganize(ctx context.Context, req UndoOrganizeRequestObject) (UndoOrganizeResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	rep, err := s.svc.Health.UndoOrganize(ctx, uc, req.Body.JobPid)
	if err != nil {
		return nil, err
	}
	return UndoOrganize200JSONResponse(organizeReportJSON(rep)), nil
}
