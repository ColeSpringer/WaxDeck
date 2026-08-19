package api

import (
	"context"
	"io"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Metadata editor handlers: field vocabulary, full item reads, scalar
// and bulk edits, credits, lyrics, chapters, artwork, custom tags,
// locks, entity curation, and release status. Reads are open to any
// user who can see the item; mutations require admin.

// artworkByteLimit mirrors the service's 16 MiB artwork cap; one extra
// byte is read so the service can tell "at the cap" from "over it".
const artworkByteLimit = 16 << 20

// boolOr dereferences an optional flag with its spec default.
func boolOr(p *bool, def bool) bool {
	if p == nil {
		return def
	}
	return *p
}

func editParams(writeBack, lock, force *bool) service.MetadataEditParams {
	return service.MetadataEditParams{
		WriteBack: boolOr(writeBack, false),
		Lock:      boolOr(lock, true),
		Force:     boolOr(force, false),
	}
}

func editResultJSON(o service.EditOutcomeDTO) MetadataEditResult {
	out := MetadataEditResult{Applied: true}
	if len(o.Failures) > 0 {
		fs := writeBackFailuresJSON(o.Failures)
		out.WriteBackFailures = &fs
	}
	if len(o.Warnings) > 0 {
		ws := append([]string{}, o.Warnings...)
		out.Warnings = &ws
	}
	return out
}

func writeBackFailuresJSON(failures []service.WriteBackFailureDTO) []WriteBackFailure {
	out := make([]WriteBackFailure, 0, len(failures))
	for _, f := range failures {
		wf := WriteBackFailure{FilePid: f.FilePID, Reason: f.Reason}
		if f.Path != "" {
			wf.Path = ptr(f.Path)
		}
		out = append(out, wf)
	}
	return out
}

func editableFieldsJSON(fields []service.EditableFieldDTO) []EditableField {
	out := make([]EditableField, 0, len(fields))
	for _, f := range fields {
		out = append(out, EditableField{Name: f.Name, WriteBack: f.WriteBack})
	}
	return out
}

func chapterMarksJSON(chapters []service.ChapterMark) []ChapterMark {
	out := make([]ChapterMark, 0, len(chapters))
	for _, ch := range chapters {
		cm := ChapterMark{Index: ch.Index, StartMs: ch.StartMS}
		if ch.Title != "" {
			cm.Title = ptr(ch.Title)
		}
		if ch.EndMS > 0 {
			cm.EndMs = ptr(ch.EndMS)
		}
		out = append(out, cm)
	}
	return out
}

func itemMetadataJSON(d service.ItemMetadataDTO) ItemMetadata {
	out := ItemMetadata{
		Pid:             d.PID,
		MediaType:       MediaType(d.MediaType),
		Fields:          d.Fields,
		LockedFields:    d.LockedFields,
		Provenance:      make([]FieldProvenance, 0, len(d.Provenance)),
		Credits:         make([]Credit, 0, len(d.Credits)),
		CustomTags:      make([]CustomTag, 0, len(d.CustomTags)),
		Unofficial:      d.Unofficial,
		VirtualTrack:    d.VirtualTrack,
		HasArtwork:      d.HasArtwork,
		HasOwnArtwork:   d.HasOwnArtwork,
		WriteBackIssues: make([]WriteBackIssue, 0, len(d.WriteBackIssues)),
		MayCurate:       d.MayCurate,
	}
	setOpt(&out.ArtistPid, d.ArtistPID)
	setOpt(&out.AlbumPid, d.AlbumPID)
	setOpt(&out.ReleaseGroupPid, d.ReleaseGroupPID)
	for _, p := range d.Provenance {
		fp := FieldProvenance{Field: p.Field, Source: p.Source, Locked: p.Locked}
		if p.Provider != "" {
			fp.Provider = ptr(p.Provider)
		}
		if !p.UpdatedAt.IsZero() {
			fp.UpdatedAt = ptr(p.UpdatedAt)
		}
		out.Provenance = append(out.Provenance, fp)
	}
	for _, c := range d.Credits {
		out.Credits = append(out.Credits, Credit{Role: c.Role, Names: c.Names})
	}
	for _, tg := range d.CustomTags {
		out.CustomTags = append(out.CustomTags, CustomTag{Key: tg.Key, Values: tg.Values})
	}
	for _, w := range d.WriteBackIssues {
		wi := WriteBackIssue{FilePid: w.FilePID, Code: w.Code}
		if w.TagKey != "" {
			wi.TagKey = ptr(w.TagKey)
		}
		if w.Detail != "" {
			wi.Detail = ptr(w.Detail)
		}
		out.WriteBackIssues = append(out.WriteBackIssues, wi)
	}
	if d.Lyrics != nil {
		ls := LyricsState{Synced: d.Lyrics.Synced, Source: d.Lyrics.Source}
		if d.Lyrics.LRC != "" {
			ls.Lrc = ptr(d.Lyrics.LRC)
		}
		out.Lyrics = &ls
	}
	if len(d.Chapters) > 0 {
		chs := chapterMarksJSON(d.Chapters)
		out.Chapters = &chs
	}
	return out
}

// --- vocabulary and reads ---------------------------------------------------------

func (s *Server) GetMetadataFields(ctx context.Context, _ GetMetadataFieldsRequestObject) (GetMetadataFieldsResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	vocab := s.svc.MetadataFieldVocabulary()
	out := MetadataFields{
		Kinds:       make([]KindFields, 0, len(vocab.Kinds)),
		EntityTypes: make([]EntityTypeFields, 0, len(vocab.EntityTypes)),
	}
	for _, k := range vocab.Kinds {
		out.Kinds = append(out.Kinds, KindFields{
			Kind:        MediaType(k.Kind),
			Fields:      editableFieldsJSON(k.Fields),
			CreditRoles: editableFieldsJSON(k.CreditRoles),
		})
	}
	for _, e := range vocab.EntityTypes {
		out.EntityTypes = append(out.EntityTypes, EntityTypeFields{
			EntityType: e.EntityType,
			Fields:     editableFieldsJSON(e.Fields),
		})
	}
	return GetMetadataFields200JSONResponse(out), nil
}

func (s *Server) GetItemMetadata(ctx context.Context, req GetItemMetadataRequestObject) (GetItemMetadataResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	d, err := s.svc.ItemMetadataFor(ctx, uc, req.Pid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetItemMetadata404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetItemMetadata200JSONResponse(itemMetadataJSON(d)), nil
}

// --- scalar edits -----------------------------------------------------------------

func (s *Server) EditItemMetadata(ctx context.Context, req EditItemMetadataRequestObject) (EditItemMetadataResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return EditItemMetadata403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil || len(req.Body.Fields) == 0 {
		return EditItemMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a fields body is required"))}, nil
	}
	out, err := s.svc.EditItemMetadata(ctx, uc, req.Pid, req.Body.Fields,
		editParams(req.Body.WriteBack, req.Body.Lock, req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return EditItemMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return EditItemMetadata404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return EditItemMetadata409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return EditItemMetadata200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) BulkEditMetadata(ctx context.Context, req BulkEditMetadataRequestObject) (BulkEditMetadataResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !uc.Admin {
		return BulkEditMetadata403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil || len(req.Body.ItemPids) == 0 || len(req.Body.Fields) == 0 {
		return BulkEditMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "itemPids and fields are required"))}, nil
	}
	out, err := s.svc.BulkEditMetadata(ctx, uc, req.Body.ItemPids, req.Body.Fields,
		derefBool(req.Body.WriteBack), derefBool(req.Body.SkipLocked), derefBool(req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return BulkEditMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return BulkEditMetadata404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		case service.KindLocked:
			return BulkEditMetadata409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	result := BulkEditResult{Edited: out.Edited, Skipped: out.Skipped}
	if len(out.Failures) > 0 {
		fs := writeBackFailuresJSON(out.Failures)
		result.WriteBackFailures = &fs
	}
	return BulkEditMetadata200JSONResponse(result), nil
}

// --- credits ----------------------------------------------------------------------

func (s *Server) SetItemCredits(ctx context.Context, req SetItemCreditsRequestObject) (SetItemCreditsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemCredits403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil || req.Body.Role == "" {
		return SetItemCredits400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a role body is required"))}, nil
	}
	out, err := s.svc.SetItemCredits(ctx, uc, req.Pid, req.Body.Role, req.Body.Names,
		editParams(req.Body.WriteBack, req.Body.Lock, req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemCredits400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemCredits404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetItemCredits409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetItemCredits200JSONResponse(editResultJSON(out)), nil
}

// --- lyrics -----------------------------------------------------------------------

func (s *Server) SetItemLyrics(ctx context.Context, req SetItemLyricsRequestObject) (SetItemLyricsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemLyrics403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return SetItemLyrics400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a lyrics body is required"))}, nil
	}
	out, err := s.svc.SetItemLyrics(ctx, uc, req.Pid, deref(req.Body.Lrc), deref(req.Body.Plain),
		editParams(req.Body.WriteBack, req.Body.Lock, req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemLyrics400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemLyrics404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetItemLyrics409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetItemLyrics200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) ClearItemLyrics(ctx context.Context, req ClearItemLyricsRequestObject) (ClearItemLyricsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return ClearItemLyrics403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if err := s.svc.ClearItemLyrics(ctx, uc, req.Pid); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return ClearItemLyrics404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return ClearItemLyrics204Response{}, nil
}

// --- chapters ---------------------------------------------------------------------

func (s *Server) SetBookChapters(ctx context.Context, req SetBookChaptersRequestObject) (SetBookChaptersResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetBookChapters403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return SetBookChapters400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a chapters body is required"))}, nil
	}
	chapters := make([]service.ChapterMark, 0, len(req.Body.Chapters))
	for _, ch := range req.Body.Chapters {
		chapters = append(chapters, service.ChapterMark{
			Index:   ch.Index,
			Title:   deref(ch.Title),
			StartMS: ch.StartMs,
			EndMS:   derefInt64(ch.EndMs),
		})
	}
	out, err := s.svc.SetBookChapters(ctx, uc, req.Pid, chapters,
		boolOr(req.Body.Lock, true), derefBool(req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetBookChapters400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetBookChapters404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no book with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetBookChapters409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetBookChapters200JSONResponse(editResultJSON(out)), nil
}

// --- artwork ----------------------------------------------------------------------

// readArtworkBody buffers the raw image body, one byte past the cap so
// the service can reject oversize uploads without unbounded buffering.
func readArtworkBody(body io.Reader) ([]byte, error) {
	if body == nil {
		return nil, nil
	}
	return io.ReadAll(io.LimitReader(body, artworkByteLimit+1))
}

func (s *Server) SetItemArtwork(ctx context.Context, req SetItemArtworkRequestObject) (SetItemArtworkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	// Reject a bad role before buffering up to 16 MiB of image body.
	if req.Params.Role != nil && !req.Params.Role.Valid() {
		return SetItemArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown art role"))}, nil
	}
	raw, err := readArtworkBody(req.Body)
	if err != nil {
		return SetItemArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "reading the image body failed"))}, nil
	}
	out, err := s.svc.SetItemArtwork(ctx, uc, req.Pid, enumStr(req.Params.Role), raw,
		derefBool(req.Params.WriteBack), boolOr(req.Params.Lock, true))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindFormat:
			return SetItemArtwork415JSONResponse{UnsupportedFormatJSONResponse(errObj("unsupported-format", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemArtwork404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetItemArtwork409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetItemArtwork200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) ClearItemArtwork(ctx context.Context, req ClearItemArtworkRequestObject) (ClearItemArtworkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return ClearItemArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if err := s.svc.ClearItemArtwork(ctx, uc, req.Pid, enumStr(req.Params.Role)); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return ClearItemArtwork404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindInvalid:
			return ClearItemArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return ClearItemArtwork204Response{}, nil
}

func (s *Server) SetEntityArtwork(ctx context.Context, req SetEntityArtworkRequestObject) (SetEntityArtworkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	// A playlist cover is its owner's, not the catalog's, so it is the one
	// entity type here that is not administrators-only; the service
	// enforces ownership.
	if !uc.Admin && !service.EntityArtworkOwned(string(req.EntityType)) {
		return SetEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	// Reject a bad role before buffering up to 16 MiB of image body.
	if req.Params.Role != nil && !req.Params.Role.Valid() {
		return SetEntityArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown art role"))}, nil
	}
	raw, err := readArtworkBody(req.Body)
	if err != nil {
		return SetEntityArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "reading the image body failed"))}, nil
	}
	out, err := s.svc.SetEntityArtwork(ctx, uc, string(req.EntityType), req.EntityPid, enumStr(req.Params.Role), raw,
		derefBool(req.Params.WriteBack))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetEntityArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindFormat:
			return SetEntityArtwork415JSONResponse{UnsupportedFormatJSONResponse(errObj("unsupported-format", err.Error()))}, nil
		case service.KindForbidden:
			return SetEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return SetEntityArtwork404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		}
		return nil, err
	}
	return SetEntityArtwork200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) ClearEntityArtwork(ctx context.Context, req ClearEntityArtworkRequestObject) (ClearEntityArtworkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !uc.Admin && !service.EntityArtworkOwned(string(req.EntityType)) {
		return ClearEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Params.Role != nil && !req.Params.Role.Valid() {
		return ClearEntityArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "unknown art role"))}, nil
	}
	if err := s.svc.ClearEntityArtwork(ctx, uc, string(req.EntityType), req.EntityPid, enumStr(req.Params.Role)); err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ClearEntityArtwork400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return ClearEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return ClearEntityArtwork404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		}
		return nil, err
	}
	return ClearEntityArtwork204Response{}, nil
}

// --- custom tags ------------------------------------------------------------------

func (s *Server) SetItemTag(ctx context.Context, req SetItemTagRequestObject) (SetItemTagResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemTag403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return SetItemTag400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a values body is required"))}, nil
	}
	out, err := s.svc.SetItemTag(ctx, uc, req.Pid, req.Key, req.Body.Values,
		boolOr(req.Body.Lock, true), derefBool(req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemTag400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemTag404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetItemTag409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetItemTag200JSONResponse(TagEditResult{Key: out.Key, Stored: out.Stored}), nil
}

func (s *Server) ClearItemTag(ctx context.Context, req ClearItemTagRequestObject) (ClearItemTagResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return ClearItemTag403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if err := s.svc.ClearItemTag(ctx, uc, req.Pid, req.Key); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return ClearItemTag404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return ClearItemTag204Response{}, nil
}

// --- locks ------------------------------------------------------------------------

func (s *Server) SetItemLocks(ctx context.Context, req SetItemLocksRequestObject) (SetItemLocksResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemLocks403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil || len(req.Body.Fields) == 0 {
		return SetItemLocks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a fields body is required"))}, nil
	}
	locked, err := s.svc.SetItemLocks(ctx, uc, req.Pid, req.Body.Fields, req.Body.Locked)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemLocks400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemLocks404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return SetItemLocks200JSONResponse(LocksResult{LockedFields: locked}), nil
}

// --- entity curation --------------------------------------------------------------

func (s *Server) EditEntity(ctx context.Context, req EditEntityRequestObject) (EditEntityResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !uc.Admin {
		return EditEntity403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil || len(req.Body.Edits) == 0 {
		return EditEntity400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an edits body is required"))}, nil
	}
	out, err := s.svc.EditEntity(ctx, string(req.EntityType), req.EntityPid, req.Body.Edits,
		editParams(req.Body.WriteBack, req.Body.Lock, req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return EditEntity400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return EditEntity404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		case service.KindLocked:
			return EditEntity409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return EditEntity200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) GetEntityCuration(ctx context.Context, req GetEntityCurationRequestObject) (GetEntityCurationResponseObject, error) {
	if _, _, err := s.requireUserCtx(ctx); err != nil {
		return nil, err
	}
	rows, err := s.svc.EntityCurationFor(ctx, string(req.EntityType), req.EntityPid)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetEntityCuration404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		}
		return nil, err
	}
	out := EntityCuration{Curated: make([]EntityCuratedField, 0, len(rows))}
	for _, r := range rows {
		cf := EntityCuratedField{Field: r.Field, Source: r.Source, Locked: r.Locked}
		if r.Value != "" {
			cf.Value = ptr(r.Value)
		}
		if !r.UpdatedAt.IsZero() {
			cf.UpdatedAt = ptr(r.UpdatedAt)
		}
		out.Curated = append(out.Curated, cf)
	}
	return GetEntityCuration200JSONResponse(out), nil
}

// --- release status ---------------------------------------------------------------

func (s *Server) SetReleaseStatus(ctx context.Context, req SetReleaseStatusRequestObject) (SetReleaseStatusResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetReleaseStatus403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return SetReleaseStatus400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an unofficial body is required"))}, nil
	}
	if err := s.svc.SetReleaseStatus(ctx, uc, req.Pid, req.Body.Unofficial); err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetReleaseStatus400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetReleaseStatus404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return SetReleaseStatus200JSONResponse(MetadataEditResult{Applied: true}), nil
}
