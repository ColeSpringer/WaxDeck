package api

import (
	"context"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func (s *Server) ListPlaylists(ctx context.Context, req ListPlaylistsRequestObject) (ListPlaylistsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 100
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	contains := ""
	if req.Params.ContainsItem != nil {
		contains = *req.Params.ContainsItem
	}
	page, err := s.svc.Playlists(ctx, uc, contains, cursor, limit)
	if err != nil {
		return nil, err
	}
	out := PlaylistPage{Playlists: make([]Playlist, 0, len(page.Playlists))}
	for _, pl := range page.Playlists {
		out.Playlists = append(out.Playlists, playlistJSON(pl))
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListPlaylists200JSONResponse(out), nil
}

func (s *Server) CreatePlaylist(ctx context.Context, req CreatePlaylistRequestObject) (CreatePlaylistResponseObject, error) {
	if req.Body == nil {
		return CreatePlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	create := service.PlaylistCreate{
		Name: req.Body.Name,
		Kind: req.Body.Kind,
	}
	if req.Body.Visibility != nil {
		create.Visibility = *req.Body.Visibility
	}
	if req.Body.Rule != nil {
		r := ruleFromWire(*req.Body.Rule)
		create.Rule = &r
	}
	if req.Body.ItemPids != nil {
		create.ItemPIDs = *req.Body.ItemPids
	}
	pl, err := s.svc.CreatePlaylist(ctx, uc, create)
	if err != nil {
		return nil, err
	}
	return CreatePlaylist201JSONResponse(playlistJSON(pl)), nil
}

func (s *Server) GetPlaylist(ctx context.Context, req GetPlaylistRequestObject) (GetPlaylistResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	pl, err := s.svc.PlaylistByPID(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	return GetPlaylist200JSONResponse(playlistJSON(pl)), nil
}

func (s *Server) UpdatePlaylist(ctx context.Context, req UpdatePlaylistRequestObject) (UpdatePlaylistResponseObject, error) {
	if req.Body == nil {
		return UpdatePlaylist400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	upd := service.PlaylistUpdate{
		Name:       req.Body.Name,
		Visibility: req.Body.Visibility,
	}
	if req.Body.Rule != nil {
		r := ruleFromWire(*req.Body.Rule)
		upd.Rule = &r
	}
	pl, err := s.svc.UpdatePlaylist(ctx, uc, req.Pid, upd)
	if err != nil {
		return nil, err
	}
	return UpdatePlaylist200JSONResponse(playlistJSON(pl)), nil
}

func (s *Server) DeletePlaylist(ctx context.Context, req DeletePlaylistRequestObject) (DeletePlaylistResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeletePlaylist(ctx, uc, req.Pid); err != nil {
		return nil, err
	}
	return DeletePlaylist204Response{}, nil
}

func (s *Server) ListPlaylistItems(ctx context.Context, req ListPlaylistItemsRequestObject) (ListPlaylistItemsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 100
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	cursor := ""
	if req.Params.Cursor != nil {
		cursor = *req.Params.Cursor
	}
	page, err := s.svc.PlaylistItems(ctx, uc, req.Pid, cursor, limit)
	if err != nil {
		return nil, err
	}
	out := PlaylistItemsPage{Entries: make([]PlaylistEntry, 0, len(page.Entries))}
	for _, e := range page.Entries {
		out.Entries = append(out.Entries, PlaylistEntry{Position: e.Position, Item: summaryJSON(e.Item)})
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListPlaylistItems200JSONResponse(out), nil
}

func (s *Server) ReplacePlaylistItems(ctx context.Context, req ReplacePlaylistItemsRequestObject) (ReplacePlaylistItemsResponseObject, error) {
	if req.Body == nil {
		return ReplacePlaylistItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.ReplacePlaylistItems(ctx, uc, req.Pid, req.Body.ItemPids, req.Body.BaseUpdatedAt); err != nil {
		return nil, err
	}
	return ReplacePlaylistItems204Response{}, nil
}

func (s *Server) AddPlaylistItems(ctx context.Context, req AddPlaylistItemsRequestObject) (AddPlaylistItemsResponseObject, error) {
	if req.Body == nil {
		return AddPlaylistItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.AddPlaylistItems(ctx, uc, req.Pid, req.Body.ItemPids); err != nil {
		return nil, err
	}
	return AddPlaylistItems204Response{}, nil
}

func (s *Server) RemovePlaylistItemAt(ctx context.Context, req RemovePlaylistItemAtRequestObject) (RemovePlaylistItemAtResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.RemovePlaylistItemAt(ctx, uc, req.Pid, req.Position); err != nil {
		return nil, err
	}
	return RemovePlaylistItemAt204Response{}, nil
}

func (s *Server) PreviewSmartRule(ctx context.Context, req PreviewSmartRuleRequestObject) (PreviewSmartRuleResponseObject, error) {
	if req.Body == nil {
		return PreviewSmartRule400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit := 50
	if req.Params.Limit != nil {
		limit = *req.Params.Limit
	}
	prev, err := s.svc.PreviewRule(ctx, uc, ruleFromWire(*req.Body), limit)
	if err != nil {
		return nil, err
	}
	out := PlaylistPreview{Items: make([]ItemSummary, 0, len(prev.Items)), Total: prev.Total}
	for _, it := range prev.Items {
		out.Items = append(out.Items, summaryJSON(it))
	}
	return PreviewSmartRule200JSONResponse(out), nil
}

func (s *Server) GetRuleFields(ctx context.Context, _ GetRuleFieldsRequestObject) (GetRuleFieldsResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	vocab, err := s.svc.RuleVocabulary(ctx)
	if err != nil {
		return nil, err
	}
	out := RuleFields{
		Fields:  make([]RuleField, 0, len(vocab.Fields)),
		TagKeys: make([]RuleTagKey, 0, len(vocab.TagKeys)),
	}
	for _, f := range vocab.Fields {
		rf := RuleField{
			Name:      f.Name,
			Kind:      f.Kind,
			Ops:       f.Ops,
			UserState: f.UserState,
			Sortable:  f.Sortable,
		}
		if f.Description != "" {
			rf.Description = ptr(f.Description)
		}
		out.Fields = append(out.Fields, rf)
	}
	for _, k := range vocab.TagKeys {
		out.TagKeys = append(out.TagKeys, RuleTagKey{Key: k.Key, ItemCount: k.ItemCount})
	}
	return GetRuleFields200JSONResponse(out), nil
}

func (s *Server) ExportPlaylistM3u(ctx context.Context, req ExportPlaylistM3uRequestObject) (ExportPlaylistM3uResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	doc, err := s.svc.ExportPlaylistM3U(ctx, uc, req.Pid)
	if err != nil {
		return nil, err
	}
	return ExportPlaylistM3u200AudioxMpegurlResponse{
		Body:          strings.NewReader(doc),
		ContentLength: int64(len(doc)),
	}, nil
}

func (s *Server) ImportPlaylistM3u(ctx context.Context, req ImportPlaylistM3uRequestObject) (ImportPlaylistM3uResponseObject, error) {
	if req.Body == nil {
		return ImportPlaylistM3u400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	vis := ""
	if req.Body.Visibility != nil {
		vis = *req.Body.Visibility
	}
	res, err := s.svc.ImportPlaylistM3U(ctx, uc, req.Body.Name, vis, req.Body.Content)
	if err != nil {
		return nil, err
	}
	out := M3uImportResult{
		Playlist:  playlistJSON(res.Playlist),
		Matched:   res.Matched,
		Unmatched: res.Unmatched,
	}
	if len(res.UnmatchedPaths) > 0 {
		out.UnmatchedPaths = ptr(res.UnmatchedPaths)
	}
	return ImportPlaylistM3u201JSONResponse(out), nil
}

// --- wire conversion --------------------------------------------------------------

func playlistJSON(pl service.Playlist) Playlist {
	out := Playlist{
		Pid:        pl.PID,
		Name:       pl.Name,
		Kind:       pl.Kind,
		Visibility: pl.Visibility,
		OwnerName:  pl.OwnerName,
		IsOwner:    pl.IsOwner,
		ItemCount:  pl.ItemCount,
		CreatedAt:  pl.CreatedAt,
		UpdatedAt:  pl.UpdatedAt,
	}
	if pl.PreviousPID != "" {
		out.PreviousPid = ptr(pl.PreviousPID)
	}
	if pl.Rule != nil {
		r := ruleToWire(*pl.Rule)
		out.Rule = &r
	}
	return out
}

func ruleFromWire(r SmartRule) service.SmartRule {
	out := service.SmartRule{Root: ruleNodeFromWire(r.Root)}
	if r.Limit != nil {
		out.Limit = *r.Limit
	}
	if r.Sorts != nil {
		for _, s := range *r.Sorts {
			rs := service.RuleSort{Field: s.Field}
			if s.Desc != nil {
				rs.Desc = *s.Desc
			}
			out.Sorts = append(out.Sorts, rs)
		}
	}
	return out
}

func ruleNodeFromWire(n RuleNode) service.RuleNode {
	out := service.RuleNode{Type: n.Type}
	if n.Nodes != nil {
		for _, c := range *n.Nodes {
			out.Nodes = append(out.Nodes, ruleNodeFromWire(c))
		}
	}
	if n.Node != nil {
		child := ruleNodeFromWire(*n.Node)
		out.Node = &child
	}
	if n.Field != nil {
		out.Field = *n.Field
	}
	if n.Op != nil {
		out.Op = *n.Op
	}
	if n.Value != nil {
		out.Value = *n.Value
	}
	if n.Values != nil {
		out.Values = *n.Values
	}
	return out
}

func ruleToWire(r service.SmartRule) SmartRule {
	out := SmartRule{Root: ruleNodeToWire(r.Root)}
	if r.Limit > 0 {
		out.Limit = ptr(r.Limit)
	}
	if len(r.Sorts) > 0 {
		sorts := make([]RuleSort, 0, len(r.Sorts))
		for _, s := range r.Sorts {
			ws := RuleSort{Field: s.Field}
			if s.Desc {
				ws.Desc = ptr(true)
			}
			sorts = append(sorts, ws)
		}
		out.Sorts = &sorts
	}
	return out
}

func ruleNodeToWire(n service.RuleNode) RuleNode {
	out := RuleNode{Type: n.Type}
	if len(n.Nodes) > 0 {
		nodes := make([]RuleNode, 0, len(n.Nodes))
		for _, c := range n.Nodes {
			nodes = append(nodes, ruleNodeToWire(c))
		}
		out.Nodes = &nodes
	}
	if n.Node != nil {
		child := ruleNodeToWire(*n.Node)
		out.Node = &child
	}
	if n.Field != "" {
		out.Field = ptr(n.Field)
	}
	if n.Op != "" {
		out.Op = ptr(n.Op)
	}
	if n.Value != "" {
		out.Value = ptr(n.Value)
	}
	if len(n.Values) > 0 {
		out.Values = ptr(n.Values)
	}
	return out
}
