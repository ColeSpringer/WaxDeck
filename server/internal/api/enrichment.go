package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Enrichment handlers: provider status, the whole-library pass, and the
// per-item fetch.

func (s *Server) GetEnrichmentStatus(ctx context.Context, _ GetEnrichmentStatusRequestObject) (GetEnrichmentStatusResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	st, err := s.svc.EnrichmentStatusFor(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return GetEnrichmentStatus403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	out := EnrichmentStatus{
		Running:    st.Running,
		Configured: st.Configured,
		Providers:  make([]EnrichmentProvider, 0, len(st.Providers)),
		Coverage: EnrichmentCoverage{
			Artists:       CoverageCount{Enriched: st.Coverage.Artists.Enriched, Total: st.Coverage.Artists.Total},
			ReleaseGroups: CoverageCount{Enriched: st.Coverage.ReleaseGroups.Enriched, Total: st.Coverage.ReleaseGroups.Total},
			Books:         CoverageCount{Enriched: st.Coverage.Books.Enriched, Total: st.Coverage.Books.Total},
			Lyrics:        CoverageCount{Enriched: st.Coverage.Lyrics.Enriched, Total: st.Coverage.Lyrics.Total},
		},
	}
	if r := st.LastRun; r != nil {
		last := EnrichmentLastRun{
			AlbumsSearched:    r.AlbumsSearched,
			AlbumsMatched:     r.AlbumsMatched,
			TagsWritten:       r.TagsWritten,
			TagsFailed:        r.TagsFailed,
			TagsUnrepresented: r.TagsUnrepresented,
			TagsSkipped:       r.TagsSkipped,
		}
		if r.FinishedAtNS > 0 {
			last.FinishedAt = ptr(time.Unix(0, r.FinishedAtNS).UTC())
		}
		out.LastRun = &last
	}
	for _, p := range st.Providers {
		caps := p.Capabilities
		if caps == nil {
			caps = []string{}
		}
		out.Providers = append(out.Providers, EnrichmentProvider{
			Name:         p.Name,
			Capabilities: caps,
			Configured:   p.Configured,
			Builtin:      p.Builtin,
		})
	}
	return GetEnrichmentStatus200JSONResponse(out), nil
}

func (s *Server) RunEnrichment(ctx context.Context, req RunEnrichmentRequestObject) (RunEnrichmentResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	force := req.Body != nil && derefBool(req.Body.Force)
	jobPid, err := s.svc.RunEnrichment(ctx, uc, force)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindForbidden:
			return RunEnrichment403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindConflict:
			return RunEnrichment409JSONResponse{ConflictJSONResponse(errObj("conflict", "a conflicting catalog job is already running"))}, nil
		case service.KindUnsupported:
			return RunEnrichment501JSONResponse{SourceUnavailableJSONResponse(errObj("source-unavailable", err.Error()))}, nil
		}
		return nil, err
	}
	return RunEnrichment202JSONResponse(EnrichmentRunResult{JobPid: jobPid}), nil
}

func (s *Server) EnrichItem(ctx context.Context, req EnrichItemRequestObject) (EnrichItemResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil || len(req.Body.Want) == 0 {
		return EnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "want is required"))}, nil
	}
	wants := make([]string, 0, len(req.Body.Want))
	for _, w := range req.Body.Want {
		if !w.Valid() {
			return EnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown want "+string(w)))}, nil
		}
		wants = append(wants, string(w))
	}
	applied, skipped, err := s.svc.EnrichItemFor(ctx, uc, string(req.Pid), wants, enrichProposalDTO(req.Body.Proposal))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return EnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return EnrichItem403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return EnrichItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	if applied == nil {
		applied = []string{}
	}
	if skipped == nil {
		skipped = []string{}
	}
	return EnrichItem200JSONResponse(EnrichItemResult{Applied: applied, Skipped: skipped}), nil
}

func (s *Server) PreviewEnrichItem(ctx context.Context, req PreviewEnrichItemRequestObject) (PreviewEnrichItemResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil || len(req.Body.Want) == 0 {
		return PreviewEnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "want is required"))}, nil
	}
	wants := make([]string, 0, len(req.Body.Want))
	for _, w := range req.Body.Want {
		if !w.Valid() {
			return PreviewEnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown want "+string(w)))}, nil
		}
		wants = append(wants, string(w))
	}
	preview, err := s.svc.EnrichPreviewFor(ctx, uc, string(req.Pid), wants)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PreviewEnrichItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return PreviewEnrichItem403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return PreviewEnrichItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	out := EnrichPreview{
		Fields:  make([]EnrichFieldProposal, 0, len(preview.Fields)),
		Skipped: preview.Skipped,
	}
	if out.Skipped == nil {
		out.Skipped = []string{}
	}
	for _, f := range preview.Fields {
		out.Fields = append(out.Fields, enrichFieldProposalJSON(f))
	}
	if c := preview.Cover; c != nil {
		out.Cover = enrichCoverProposalJSON(*c)
	}
	return PreviewEnrichItem200JSONResponse(out), nil
}

// enrichProposalDTO maps the wire proposal onto the service's shape;
// nil stays nil, which is what selects the fetching path.
func enrichProposalDTO(p *EnrichProposal) *service.EnrichProposalDTO {
	if p == nil {
		return nil
	}
	out := &service.EnrichProposalDTO{}
	if p.Fields != nil {
		out.Fields = make([]service.EnrichFieldProposalDTO, 0, len(*p.Fields))
		for _, f := range *p.Fields {
			out.Fields = append(out.Fields, service.EnrichFieldProposalDTO{
				Name: f.Name, Current: deref(f.Current), Proposed: f.Proposed, Provider: f.Provider,
			})
		}
	}
	if c := p.Cover; c != nil {
		out.Cover = &service.EnrichCoverProposalDTO{
			Provider: c.Provider, Format: deref(c.Format), SourceURL: deref(c.SourceUrl), Data: c.Data,
		}
	}
	return out
}

func enrichFieldProposalJSON(f service.EnrichFieldProposalDTO) EnrichFieldProposal {
	out := EnrichFieldProposal{Name: f.Name, Proposed: f.Proposed, Provider: f.Provider}
	// Empty today by construction (enrichment only fills empty fields),
	// but mapped rather than assumed so a future replace mode cannot
	// silently report a wrong diff.
	out.Current = ptr(f.Current)
	return out
}

func enrichCoverProposalJSON(c service.EnrichCoverProposalDTO) *EnrichCoverProposal {
	out := &EnrichCoverProposal{Provider: c.Provider, Data: c.Data}
	if c.Format != "" {
		out.Format = ptr(c.Format)
	}
	if c.SourceURL != "" {
		out.SourceUrl = ptr(c.SourceURL)
	}
	return out
}
