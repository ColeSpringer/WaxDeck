package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// enumStr renders an optional generated query-param enum (a defined string
// type) as its string value, empty when the param is absent.
func enumStr[T ~string](p *T) string {
	if p == nil {
		return ""
	}
	return string(*p)
}

func (s *Server) ListFileDiagnostics(ctx context.Context, req ListFileDiagnosticsRequestObject) (ListFileDiagnosticsResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ListFileDiagnostics403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, ok := pageLimit(req.Params.Limit, 100, 500)
	if !ok {
		return ListFileDiagnostics400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	in := service.DiagnosticFilterInput{
		Origin:     enumStr(req.Params.Origin),
		Code:       enumStr(req.Params.Code),
		Severity:   enumStr(req.Params.Severity),
		LibraryPID: enumStr(req.Params.Library),
	}
	rows, next, err := s.svc.FileDiagnostics(ctx, uc, in, deref(req.Params.Cursor), limit)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ListFileDiagnostics400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return ListFileDiagnostics404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		}
		return nil, err
	}
	out := FileDiagnosticPage{Diagnostics: make([]FileDiagnostic, 0, len(rows))}
	for _, d := range rows {
		out.Diagnostics = append(out.Diagnostics, fileDiagnosticJSON(d))
	}
	if next != "" {
		out.NextCursor = ptr(next)
	}
	return ListFileDiagnostics200JSONResponse(out), nil
}

func (s *Server) GetDiagnosticSummary(ctx context.Context, req GetDiagnosticSummaryRequestObject) (GetDiagnosticSummaryResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return GetDiagnosticSummary403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	in := service.DiagnosticFilterInput{
		Origin:     enumStr(req.Params.Origin),
		Code:       enumStr(req.Params.Code),
		Severity:   enumStr(req.Params.Severity),
		LibraryPID: enumStr(req.Params.Library),
	}
	counts, err := s.svc.DiagnosticSummary(ctx, uc, in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return GetDiagnosticSummary400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return GetDiagnosticSummary404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		}
		return nil, err
	}
	out := DiagnosticSummary{Counts: make([]DiagnosticCount, 0, len(counts))}
	for _, c := range counts {
		out.Counts = append(out.Counts, DiagnosticCount{
			Origin:   c.Origin,
			Code:     c.Code,
			Severity: c.Severity,
			Count:    c.Count,
		})
	}
	return GetDiagnosticSummary200JSONResponse(out), nil
}

func fileDiagnosticJSON(d service.FileDiagnosticDTO) FileDiagnostic {
	out := FileDiagnostic{
		Path:     d.Path,
		Origin:   d.Origin,
		Code:     d.Code,
		Severity: d.Severity,
		SeenAt:   time.Unix(0, d.SeenAtNS).UTC(),
	}
	if d.TagKey != "" {
		out.TagKey = ptr(d.TagKey)
	}
	if d.Detail != "" {
		out.Detail = ptr(d.Detail)
	}
	return out
}
