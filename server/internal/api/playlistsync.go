package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Synced external playlists: the source binding, its dry-run preview,
// and the manual sync trigger.

func (s *Server) GetPlaylistSource(ctx context.Context, req GetPlaylistSourceRequestObject) (GetPlaylistSourceResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	src, err := s.svc.GetPlaylistSource(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	return GetPlaylistSource200JSONResponse(playlistSourceJSON(src)), nil
}

func (s *Server) SetPlaylistSource(ctx context.Context, req SetPlaylistSourceRequestObject) (SetPlaylistSourceResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return SetPlaylistSource400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	src, err := s.svc.SetPlaylistSource(ctx, uc, req.Pid, playlistSourceUpdateFromWire(*req.Body))
	if err != nil {
		return nil, err
	}
	return SetPlaylistSource200JSONResponse(playlistSourceJSON(src)), nil
}

func (s *Server) UnbindPlaylistSource(ctx context.Context, req UnbindPlaylistSourceRequestObject) (UnbindPlaylistSourceResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.UnbindPlaylistSource(ctx, uc, req.Pid); err != nil {
		return nil, err
	}
	return UnbindPlaylistSource204Response{}, nil
}

func (s *Server) PreviewPlaylistSync(ctx context.Context, req PreviewPlaylistSyncRequestObject) (PreviewPlaylistSyncResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	var in *service.PlaylistSourceUpdateDTO
	// A JSON `null` body decodes to the zero value; either spelling of
	// "no body" previews the stored binding. Field-wise rather than a
	// struct compare: the generated type's optionals are pointers, so
	// `{"url": ""}` would otherwise read as prospective settings, and
	// one non-comparable field added to it would break the build.
	if req.Body != nil && playlistSourceUpdateHasFields(*req.Body) {
		dto := playlistSourceUpdateFromWire(*req.Body)
		in = &dto
	}
	preview, err := s.svc.PreviewPlaylistSync(ctx, uc, req.Pid, in)
	if err != nil {
		return nil, err
	}
	return PreviewPlaylistSync200JSONResponse(playlistSyncPreviewJSON(preview)), nil
}

func (s *Server) SyncPlaylistSource(ctx context.Context, req SyncPlaylistSourceRequestObject) (SyncPlaylistSourceResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	task, err := s.svc.SyncPlaylistSourceNow(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	return SyncPlaylistSource202JSONResponse(toolTaskJSON(task)), nil
}

// playlistSourceUpdateHasFields reports whether a decoded preview body
// actually says anything - the empty object and JSON null both mean
// "the stored binding". A field set to its zero value still counts:
// `{"mode": ""}` is a malformed request to refuse, not an absent one.
func playlistSourceUpdateHasFields(b PlaylistSourceUpdate) bool {
	return b.Mode != "" || b.Url != nil || b.Source != nil ||
		b.Payload != nil || b.Refs != nil || b.IntervalHours != nil
}

// --- wire conversion -------------------------------------------------------------

func playlistSourceJSON(src service.PlaylistSourceDTO) PlaylistSource {
	out := PlaylistSource{
		Source:              src.Source,
		Live:                src.Live,
		Mode:                src.Mode,
		Disabled:            src.Disabled,
		ConsecutiveFailures: src.ConsecutiveFailures,
	}
	if src.URL != "" {
		out.Url = ptr(src.URL)
	}
	if src.Title != "" {
		out.Title = ptr(src.Title)
	}
	if src.Live {
		out.IntervalHours = ptr(src.IntervalHours)
	} else {
		out.RefCount = ptr(src.RefCount)
	}
	if src.LastError != "" {
		out.LastError = ptr(src.LastError)
	}
	if src.LastAttemptNS > 0 {
		out.LastAttemptAt = ptr(time.Unix(0, src.LastAttemptNS).UTC())
	}
	if src.LastSyncedNS > 0 {
		out.LastSyncedAt = ptr(time.Unix(0, src.LastSyncedNS).UTC())
	}
	if src.HasRun {
		out.LastRun = &PlaylistSyncCounts{
			Added:       src.LastCounts.Added,
			Removed:     src.LastCounts.Removed,
			Trashed:     src.LastCounts.Trashed,
			Queued:      src.LastCounts.Queued,
			Unavailable: src.LastCounts.Unavailable,
			Missing:     src.LastCounts.Missing,
		}
	}
	return out
}

func playlistSourceUpdateFromWire(b PlaylistSourceUpdate) service.PlaylistSourceUpdateDTO {
	in := service.PlaylistSourceUpdateDTO{
		Mode:    string(b.Mode),
		URL:     deref(b.Url),
		Payload: deref(b.Payload),
		// Presence, not emptiness: the settings-only form is a body that
		// names no source *field*, and `"url": ""` names one badly. A
		// client that clears its URL box asks to rebind and gets the
		// refusal it always got, rather than silently re-saving settings
		// onto the binding it was trying to replace.
		NamesSource: b.Url != nil || b.Source != nil || b.Payload != nil || b.Refs != nil,
	}
	if b.Source != nil {
		in.Source = string(*b.Source)
	}
	if b.IntervalHours != nil {
		in.IntervalHours = *b.IntervalHours
	}
	if b.Refs != nil {
		for _, r := range *b.Refs {
			in.Refs = append(in.Refs, refDTOFromWire(r))
		}
	}
	return in
}

func playlistSyncPreviewJSON(p service.PlaylistSyncPreviewDTO) PlaylistSyncPreview {
	out := PlaylistSyncPreview{
		Entries:       p.Entries,
		WouldAdd:      p.WouldAdd,
		WouldDownload: p.WouldDownload,
		WouldRemove:   p.WouldRemove,
		WouldTrash:    p.WouldTrash,
		Pending:       p.Pending,
		Unavailable:   p.Unavailable,
		Missing:       p.Missing,
	}
	if len(p.Misses) > 0 {
		misses := make([]PlaylistImportMiss, 0, len(p.Misses))
		for _, m := range p.Misses {
			misses = append(misses, importMissJSON(m))
		}
		out.Misses = &misses
	}
	return out
}
