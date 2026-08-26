package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Streaming-service playlist import and portable export.

func (s *Server) ImportPlaylist(ctx context.Context, req ImportPlaylistRequestObject) (ImportPlaylistResponseObject, error) {
	if req.Body == nil {
		return ImportPlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a request body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	in := service.PlaylistImportInput{
		Source:  string(req.Body.Source),
		Name:    deref(req.Body.Name),
		Payload: deref(req.Body.Payload),
	}
	if len(in.Payload) > 4000000 {
		return ImportPlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "payload must be at most 4000000 characters"))}, nil
	}
	if req.Body.Refs != nil {
		if len(*req.Body.Refs) > 10000 {
			return ImportPlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 10000 refs"))}, nil
		}
		in.Refs = make([]service.PortableRefDTO, 0, len(*req.Body.Refs))
		for _, r := range *req.Body.Refs {
			in.Refs = append(in.Refs, refDTOFromWire(r))
		}
	}
	res, err := s.svc.ImportStreamingPlaylist(ctx, uc, in)
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		return ImportPlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
	default:
		return nil, err
	}
	out := PlaylistImportResult{
		Name:      res.Name,
		Requested: res.Requested,
		Resolved:  res.Resolved,
		Missing:   []PlaylistImportMiss{},
		Rungs: ResolveRungCounts{
			Essence:     res.Rungs.Essence,
			StrongId:    res.Rungs.StrongID,
			Fingerprint: res.Rungs.Fingerprint,
			Descriptive: res.Rungs.Descriptive,
		},
	}
	if res.PlaylistPID != "" {
		out.PlaylistPid = ptr(res.PlaylistPID)
	}
	for _, m := range res.Missing {
		out.Missing = append(out.Missing, importMissJSON(m))
	}
	return ImportPlaylist200JSONResponse(out), nil
}

func (s *Server) ExportPlaylistPortable(ctx context.Context, req ExportPlaylistPortableRequestObject) (ExportPlaylistPortableResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	name, refs, err := s.svc.ExportPlaylistPortable(ctx, uc, req.Pid)
	switch service.KindOf(err) {
	case "":
	case service.KindNotFound:
		return ExportPlaylistPortable404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	default:
		return nil, err
	}
	out := PortablePlaylist{Name: name, Refs: []PortableRef{}}
	for _, r := range refs {
		out.Refs = append(out.Refs, refDTOToWire(r))
	}
	return ExportPlaylistPortable200JSONResponse(out), nil
}

// importMissJSON renders one unmatched entry for the wire, shared by
// the import report and the sync preview so a field added to the miss
// lands on both.
func importMissJSON(m service.ImportMiss) PlaylistImportMiss {
	miss := PlaylistImportMiss{Title: m.Title}
	if m.Artist != "" {
		miss.Artist = ptr(m.Artist)
	}
	if m.Album != "" {
		miss.Album = ptr(m.Album)
	}
	if m.DurationMs > 0 {
		miss.DurationMs = ptr(m.DurationMs)
	}
	return miss
}

func refDTOFromWire(r PortableRef) service.PortableRefDTO {
	out := service.PortableRefDTO{
		Kind:       string(r.Kind),
		Essence:    deref(r.Essence),
		MBID:       deref(r.Mbid),
		ASIN:       deref(r.Asin),
		ISBN:       deref(r.Isbn),
		ISRC:       deref(r.Isrc),
		Artist:     deref(r.Artist),
		Title:      r.Title,
		Album:      deref(r.Album),
		DurationMs: derefInt64(r.DurationMs),
	}
	if r.Fingerprint != nil {
		out.Fingerprint = *r.Fingerprint
	}
	if r.FingerprintAlgo != nil {
		out.FingerprintAlgo = *r.FingerprintAlgo
	}
	return out
}

func refDTOToWire(r service.PortableRefDTO) PortableRef {
	out := PortableRef{Kind: PortableRefKind(r.Kind), Title: r.Title}
	if r.Essence != "" {
		out.Essence = ptr(r.Essence)
	}
	if len(r.Fingerprint) > 0 {
		out.Fingerprint = &r.Fingerprint
	}
	if r.FingerprintAlgo != 0 {
		out.FingerprintAlgo = ptr(r.FingerprintAlgo)
	}
	if r.MBID != "" {
		out.Mbid = ptr(r.MBID)
	}
	if r.ASIN != "" {
		out.Asin = ptr(r.ASIN)
	}
	if r.ISBN != "" {
		out.Isbn = ptr(r.ISBN)
	}
	if r.Artist != "" {
		out.Artist = ptr(r.Artist)
	}
	if r.Album != "" {
		out.Album = ptr(r.Album)
	}
	if r.DurationMs > 0 {
		out.DurationMs = ptr(r.DurationMs)
	}
	return out
}
