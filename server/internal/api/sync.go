package api

import (
	"context"
	"net/url"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// --- delta sync --------------------------------------------------------------

func (s *Server) SyncCatalog(ctx context.Context, req SyncCatalogRequestObject) (SyncCatalogResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 500, 1000)
	if !ok {
		return SyncCatalog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 1000"))}, nil
	}
	if req.Params.Since != nil && req.Params.Cursor != nil {
		return SyncCatalog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "since and cursor are mutually exclusive"))}, nil
	}

	if req.Params.Since != nil {
		delta, err := s.svc.SyncCatalogDelta(ctx, uc, *req.Params.Since, limit)
		if err != nil {
			switch service.KindOf(err) {
			case service.KindGone:
				return SyncCatalog410JSONResponse{SyncResetJSONResponse(errObj("sync-reset", err.Error()))}, nil
			case service.KindInvalid:
				return SyncCatalog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
			}
			return nil, err
		}
		out := CatalogSyncPage{
			Entries:   catalogEntriesJSON(delta.Entries),
			NextSince: delta.NextSince,
		}
		if delta.More {
			out.More = ptr(true)
		}
		return SyncCatalog200JSONResponse(out), nil
	}

	cursor := deref(req.Params.Cursor)
	page, err := s.svc.SyncCatalogSnapshot(ctx, uc, cursor, limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return SyncCatalog400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := CatalogSyncPage{
		Entries:   catalogEntriesJSON(page.Entries),
		NextSince: page.NextSince,
	}
	if page.NextCursor != "" {
		out.NextCursor = ptr(page.NextCursor)
	}
	return SyncCatalog200JSONResponse(out), nil
}

func catalogEntriesJSON(entries []service.CatalogSyncEntry) []CatalogSyncEntry {
	out := make([]CatalogSyncEntry, 0, len(entries))
	for _, e := range entries {
		je := CatalogSyncEntry{Op: e.Op, Pid: e.PID}
		if e.Item != nil {
			item := summaryJSON(*e.Item)
			je.Item = &item
		}
		if e.Episode != nil {
			ep := episodeSummaryJSON(*e.Episode)
			je.Episode = &ep
		}
		if e.Show != nil {
			show := showJSON(*e.Show)
			je.Show = &show
		}
		out = append(out, je)
	}
	return out
}

func (s *Server) SyncServer(ctx context.Context, req SyncServerRequestObject) (SyncServerResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 500, 1000)
	if !ok {
		return SyncServer400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 1000"))}, nil
	}

	if req.Params.Since == nil {
		cursor, err := s.svc.MintServerCursor(ctx)
		if err != nil {
			return nil, err
		}
		return SyncServer200JSONResponse(ServerSyncPage{
			Events: []ServerSyncEvent{}, NextSince: cursor,
		}), nil
	}

	delta, err := s.svc.SyncServerDelta(ctx, uc, *req.Params.Since, limit)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindGone:
			return SyncServer410JSONResponse{SyncResetJSONResponse(errObj("sync-reset", err.Error()))}, nil
		case service.KindInvalid:
			return SyncServer400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := ServerSyncPage{Events: make([]ServerSyncEvent, 0, len(delta.Events)), NextSince: delta.NextSince}
	if delta.More {
		out.More = ptr(true)
	}
	for _, e := range delta.Events {
		je := ServerSyncEvent{Kind: e.Kind}
		if e.PID != "" {
			je.Pid = ptr(e.PID)
		}
		if e.PlayState != nil {
			st := playStateJSON(*e.PlayState)
			je.PlayState = &st
		}
		if e.Prefs != nil {
			p := prefsJSON(*e.Prefs)
			je.Prefs = &p
		}
		if e.Subscription != nil {
			sub := subscriptionJSON(*e.Subscription)
			je.Subscription = &sub
		}
		if e.BookSettings != nil {
			bs := bookSettingsJSON(*e.BookSettings)
			je.BookSettings = &bs
		}
		out.Events = append(out.Events, je)
	}
	return SyncServer200JSONResponse(out), nil
}

// --- batch play states -------------------------------------------------------

func (s *Server) ListPlayStates(ctx context.Context, req ListPlayStatesRequestObject) (ListPlayStatesResponseObject, error) {
	if req.Body == nil || len(req.Body.Pids) == 0 {
		return ListPlayStates400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "pids must not be empty"))}, nil
	}
	if len(req.Body.Pids) > 500 {
		return ListPlayStates400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "at most 500 pids per request"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	states, err := s.svc.PlayStates(ctx, uc, req.Body.Pids)
	if err != nil {
		return nil, err
	}
	out := PlayStateList{States: make([]PlayState, 0, len(states))}
	for _, st := range states {
		out.States = append(out.States, playStateJSON(st))
	}
	return ListPlayStates200JSONResponse(out), nil
}

// --- download info -----------------------------------------------------------

func (s *Server) GetDownloadInfo(ctx context.Context, req GetDownloadInfoRequestObject) (GetDownloadInfoResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if s.media == nil {
		return nil, errStreamingUnavailable
	}
	res, err := s.svc.DownloadInfo(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetDownloadInfo404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	token, exp := s.media.Mint(uc.ID, req.Pid)
	out := DownloadInfo{Pid: req.Pid, ExpiresAt: exp, Files: make([]DownloadFile, 0, len(res.Files))}
	for _, f := range res.Files {
		out.Files = append(out.Files, DownloadFile{
			Url: "/media/download?pid=" + url.QueryEscape(req.Pid) +
				"&mt=" + url.QueryEscape(token) +
				"&f=" + url.QueryEscape(f.FilePID) +
				"&id=" + url.QueryEscape(f.ETag),
			MimeType:    f.MimeType,
			SizeBytes:   f.Size,
			FileName:    f.FileName,
			EssenceHash: f.EssenceHash,
			Etag:        f.ETag,
		})
	}
	if res.HasSpan {
		out.SpanStartMs = ptr(res.SpanStartMS)
		out.SpanEndMs = ptr(res.SpanEndMS)
	}
	return GetDownloadInfo200JSONResponse(out), nil
}

// --- app passwords -----------------------------------------------------------

func (s *Server) ListAppPasswords(ctx context.Context, _ ListAppPasswordsRequestObject) (ListAppPasswordsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.svc.AppPasswords(ctx, uc)
	if err != nil {
		return nil, err
	}
	out := AppPasswordList{AppPasswords: make([]AppPassword, 0, len(rows))}
	for _, ap := range rows {
		out.AppPasswords = append(out.AppPasswords, appPasswordJSON(ap))
	}
	return ListAppPasswords200JSONResponse(out), nil
}

func (s *Server) CreateAppPassword(ctx context.Context, req CreateAppPasswordRequestObject) (CreateAppPasswordResponseObject, error) {
	if req.Body == nil {
		return CreateAppPassword400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	created, err := s.svc.CreateAppPassword(ctx, uc, req.Body.Label)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return CreateAppPassword400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindConflict:
			return CreateAppPassword409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	base := appPasswordJSON(created.AppPassword)
	return CreateAppPassword201JSONResponse(AppPasswordCreated{
		Id: base.Id, Label: base.Label, CreatedAt: base.CreatedAt,
		LastUsedAt: base.LastUsedAt, Secret: created.Secret,
	}), nil
}

func (s *Server) RevokeAppPassword(ctx context.Context, req RevokeAppPasswordRequestObject) (RevokeAppPasswordResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.RevokeAppPassword(ctx, uc, req.AppPasswordId); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return RevokeAppPassword404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no app password with id "+req.AppPasswordId))}, nil
		}
		return nil, err
	}
	return RevokeAppPassword204Response{}, nil
}

func appPasswordJSON(ap service.AppPassword) AppPassword {
	out := AppPassword{Id: ap.ID, Label: ap.Label, CreatedAt: ap.CreatedAt}
	if !ap.LastUsedAt.IsZero() {
		out.LastUsedAt = &ap.LastUsedAt
	}
	return out
}
