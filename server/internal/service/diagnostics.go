package service

import (
	"context"
	"encoding/base64"
	"strconv"

	"github.com/colespringer/waxbin/model"
)

// FileDiagnosticDTO is one persisted per-file diagnostic for the dashboard.
type FileDiagnosticDTO struct {
	Path     string
	Origin   string
	Code     string
	Severity string
	TagKey   string
	Detail   string
	SeenAtNS int64
}

// DiagnosticCountDTO is one grouped bucket of the diagnostic summary.
type DiagnosticCountDTO struct {
	Origin   string
	Code     string
	Severity string
	Count    int
}

// DiagnosticFilterInput narrows a diagnostics query; empty fields mean "any".
type DiagnosticFilterInput struct {
	Origin     string
	Code       string
	Severity   string
	LibraryPID string // api library pid (lb-...); empty for every library
}

// FileDiagnostics queries the persisted per-file diagnostics, paged over the
// facade's stable path order. Administrators only: the rows carry raw file
// paths across every library.
func (l *Library) FileDiagnostics(ctx context.Context, uc *UserCtx, in DiagnosticFilterInput, cursor string, limit int) ([]FileDiagnosticDTO, string, error) {
	if !uc.Admin {
		return nil, "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	filter, err := l.diagnosticFilter(in)
	if err != nil {
		return nil, "", err
	}
	offset, ok := decodeDiagnosticCursor(cursor)
	if !ok {
		return nil, "", errInvalid("bad diagnostics cursor")
	}
	filter.Limit = limit
	filter.Offset = offset
	rows, err := l.lib.FileDiagnostics(ctx, filter)
	if err != nil {
		return nil, "", classify(err)
	}
	out := make([]FileDiagnosticDTO, 0, len(rows))
	for _, d := range rows {
		out = append(out, FileDiagnosticDTO{
			Path:     d.DisplayPath,
			Origin:   string(d.Origin),
			Code:     string(d.Code),
			Severity: string(d.Severity),
			TagKey:   d.TagKey,
			Detail:   d.Detail,
			SeenAtNS: d.SeenAt,
		})
	}
	// A full page means the offset window filled, so there may be more.
	next := ""
	if limit > 0 && len(rows) == limit {
		next = encodeDiagnosticCursor(offset + limit)
	}
	return out, next, nil
}

// DiagnosticSummary groups the matching diagnostics by writer, code, and
// severity, most severe first. Administrators only.
func (l *Library) DiagnosticSummary(ctx context.Context, uc *UserCtx, in DiagnosticFilterInput) ([]DiagnosticCountDTO, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	filter, err := l.diagnosticFilter(in)
	if err != nil {
		return nil, err
	}
	rows, err := l.lib.DiagnosticSummary(ctx, filter)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]DiagnosticCountDTO, 0, len(rows))
	for _, c := range rows {
		out = append(out, DiagnosticCountDTO{
			Origin:   string(c.Origin),
			Code:     string(c.Code),
			Severity: string(c.Severity),
			Count:    c.Count,
		})
	}
	return out, nil
}

// diagnosticFilter maps the request filter onto the facade's, translating the
// api library pid to a bare catalog pid. Vocabulary validation stays with the
// facade, which rejects an unknown origin/code/severity as invalid and an
// unknown library as not-found.
func (l *Library) diagnosticFilter(in DiagnosticFilterInput) (model.DiagnosticFilter, error) {
	f := model.DiagnosticFilter{
		Origin:   model.DiagnosticOrigin(in.Origin),
		Code:     model.DiagnosticCode(in.Code),
		Severity: model.AuditSeverity(in.Severity),
	}
	if in.LibraryPID != "" {
		prefix, bare, ok := parseAPIPID(in.LibraryPID)
		if !ok || prefix != PrefixLibrary {
			return model.DiagnosticFilter{}, errInvalid("bad library id " + in.LibraryPID)
		}
		f.LibraryPID = model.PID(bare)
	}
	return f, nil
}

// Diagnostic cursors carry the facade's row offset. The facade pages this
// table by offset over a stable path order (there is no keyset cursor at its
// grain), so WaxDeck wraps the offset in an opaque cursor to keep the
// contract keyset-shaped.
func encodeDiagnosticCursor(offset int) string {
	return base64.RawURLEncoding.EncodeToString([]byte(strconv.Itoa(offset)))
}

func decodeDiagnosticCursor(s string) (int, bool) {
	if s == "" {
		return 0, true
	}
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, false
	}
	n, err := strconv.Atoi(string(raw))
	if err != nil || n < 0 {
		return 0, false
	}
	return n, true
}
