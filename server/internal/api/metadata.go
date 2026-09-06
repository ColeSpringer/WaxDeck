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
	if o.MergedInto != "" {
		out.MergedInto = ptr(o.MergedInto)
	}
	if len(o.MovedAlbums) > 0 {
		moved := append([]string{}, o.MovedAlbums...)
		out.MovedAlbums = &moved
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
	if a := d.Acquisition; a != nil {
		acq := ItemAcquisition{SourceType: a.SourceType}
		if !a.AcquiredAt.IsZero() {
			acq.AcquiredAt = ptr(a.AcquiredAt)
		}
		if a.SourceURL != "" {
			acq.SourceUrl = ptr(a.SourceURL)
		}
		if a.SourceID != "" {
			acq.SourceId = ptr(a.SourceID)
		}
		if a.Provider != "" {
			acq.Provider = ptr(a.Provider)
		}
		if a.Locked {
			acq.Locked = ptr(true)
		}
		out.Acquisition = &acq
	}
	for _, p := range d.Provenance {
		fp := FieldProvenance{Field: p.Field, Source: p.Source, Locked: p.Locked}
		if p.Provider != "" {
			fp.Provider = ptr(p.Provider)
		}
		if p.SourceURL != "" {
			fp.SourceUrl = ptr(p.SourceURL)
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
		if d.Lyrics.Provider != "" {
			ls.Provider = ptr(d.Lyrics.Provider)
		}
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
	if len(vocab.ReservedTagKeys) > 0 {
		keys := append([]string{}, vocab.ReservedTagKeys...)
		out.ReservedTagKeys = &keys
	}
	return GetMetadataFields200JSONResponse(out), nil
}

func (s *Server) GetItemPermissions(ctx context.Context, req GetItemPermissionsRequestObject) (GetItemPermissionsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	may, err := s.svc.MayCurateItem(ctx, uc, string(req.Pid))
	if err != nil {
		return nil, err
	}
	return GetItemPermissions200JSONResponse(ItemPermissions{MayCurate: may}), nil
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

// CommitItemMetadata runs a whole staged editor draft in one request.
//
// Gated per item exactly like the sequential parts it orchestrates:
// administrators, or the user whose upload brought the item in. It is
// not the bulk edit and does not carry that operation's admin-only
// gate.
//
// A part refused mid-way is a 200 carrying that part's refusal, not a
// 4xx: the write-back failures the earlier parts accumulated are what
// the editor's banner is made of, and a status code would discard them.
// The refusals below are for a request that commits nothing at all.
func (s *Server) CommitItemMetadata(ctx context.Context, req CommitItemMetadataRequestObject) (CommitItemMetadataResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return CommitItemMetadata403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return CommitItemMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	out, err := s.svc.CommitItemMetadata(ctx, uc, req.Pid, metadataCommitDTO(*req.Body))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return CommitItemMetadata400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return CommitItemMetadata404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return CommitItemMetadata200JSONResponse(commitResultJSON(out)), nil
}

// metadataCommitDTO reads the wire body into the service's staged-parts
// shape. The pointer fields stay pointers: an absent chapter list and an
// empty one mean different things, and so do an absent release status
// and a cleared one.
func metadataCommitDTO(b MetadataCommit) service.MetadataCommitDTO {
	out := service.MetadataCommitDTO{
		ClearLyrics: derefBool(b.ClearLyrics),
		Unofficial:  b.Unofficial,
		Params:      editParams(b.WriteBack, b.Lock, b.Force),
	}
	if b.Fields != nil {
		out.Fields = *b.Fields
	}
	if b.Credits != nil {
		for _, c := range *b.Credits {
			out.Credits = append(out.Credits, service.CommitCreditsDTO{Role: c.Role, Names: c.Names})
		}
	}
	if b.Lyrics != nil {
		out.Lyrics = &service.CommitLyricsDTO{
			LRC: deref(b.Lyrics.Lrc), Plain: deref(b.Lyrics.Plain),
		}
	}
	if b.Chapters != nil {
		marks := make([]service.ChapterMark, 0, len(*b.Chapters))
		for _, ch := range *b.Chapters {
			marks = append(marks, chapterMarkDTO(ch))
		}
		out.Chapters = &marks
	}
	if b.TagSets != nil {
		out.TagSets = *b.TagSets
	}
	if b.TagRemoves != nil {
		out.TagRemoves = *b.TagRemoves
	}
	return out
}

// commitResultJSON is the compound commit's envelope, assembled the way
// the bulk edit's is.
func commitResultJSON(out service.MetadataCommitOutcomeDTO) MetadataCommitResult {
	result := MetadataCommitResult{Parts: make([]MetadataCommitPart, 0, len(out.Parts))}
	for _, p := range out.Parts {
		part := MetadataCommitPart{
			Part:   MetadataCommitPartPart(p.Part),
			Status: MetadataCommitPartStatus(p.Status),
		}
		if p.Detail != "" {
			part.Detail = ptr(p.Detail)
		}
		if p.Refusal != nil {
			refusal := partRefusal(p.Refusal)
			part.Refusal = &refusal
		}
		result.Parts = append(result.Parts, part)
	}
	if len(out.Failures) > 0 {
		fs := writeBackFailuresJSON(out.Failures)
		result.WriteBackFailures = &fs
	}
	if len(out.Warnings) > 0 {
		result.Warnings = &out.Warnings
	}
	return result
}

// chapterMarkDTO reads one wire chapter into the service's form. Shared
// by the chapters endpoint and the compound commit, so the two cannot
// read a chapter differently.
func chapterMarkDTO(ch ChapterMark) service.ChapterMark {
	return service.ChapterMark{
		Index:   ch.Index,
		Title:   deref(ch.Title),
		StartMS: ch.StartMs,
		EndMS:   derefInt64(ch.EndMs),
	}
}

// partRefusal projects a service error onto the Error one refused part
// carries. The service's error kinds are the contract's own codes, so
// this adds none: it is the same table ResponseErrorHandler uses, minus
// the status.
//
// The message is the error's own, exactly as the per-part endpoints
// send it (`errObj("field-locked", err.Error())` and its siblings) -
// the catalog's sentence names which field is locked, and the editor
// draws it in front of the person who typed the value. A generic
// fallback here would have the same refusal read differently depending
// on which save path the session took, which is the property the
// sequential fallback rests on. Internal is the exception: nothing
// wrapped is surfaced there, because it may name internals.
func partRefusal(err error) Error {
	kind := service.KindOf(err)
	if kind == "" || kind == service.KindInternal {
		return errObj("internal", kindMessage(err, "internal server error"))
	}
	return errObj(string(kind), err.Error())
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
	if out.ResultingAlbumPID != "" {
		result.ResultingAlbumPid = &out.ResultingAlbumPID
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
		chapters = append(chapters, chapterMarkDTO(ch))
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

// entityArtworkPermitted is the API-side gate on the entity-artwork
// surface, one answer for the set, clear, and pin endpoints. Catalog
// entities are administrators-only, with two exceptions: a playlist
// cover is its owner's (the service enforces ownership, and the pin
// endpoints refuse the type outright with the documented
// invalid-request, so nothing owner-pinnable leaks through the wider
// gate), and a podcast show's cover belongs to whoever curates shows,
// which is ManagePodcasts as well as administrators - pin included,
// because the pin is what keeps a hand-set cover from being refetched
// by the next feed sync.
func entityArtworkPermitted(uc *service.UserCtx, entityType string) bool {
	switch {
	case uc.Admin:
		return true
	case service.EntityArtworkOwned(entityType):
		return true
	case entityType == "podcast":
		return uc.ManagePodcasts
	}
	return false
}

// entityArtworkRefusal names who the entity-artwork gate admits for
// the type, for the forbidden body.
func entityArtworkRefusal(entityType string) string {
	if entityType == "podcast" {
		return "administrators, or an account that may manage podcasts"
	}
	return "administrators only"
}

func (s *Server) SetEntityArtwork(ctx context.Context, req SetEntityArtworkRequestObject) (SetEntityArtworkResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !entityArtworkPermitted(uc, string(req.EntityType)) {
		return SetEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", entityArtworkRefusal(string(req.EntityType))))}, nil
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
	if !entityArtworkPermitted(uc, string(req.EntityType)) {
		return ClearEntityArtwork403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", entityArtworkRefusal(string(req.EntityType))))}, nil
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

// GetEntityArtworkLock and SetEntityArtworkLock share the entity-
// artwork gate deliberately: the podcast arm carries into the pin, and
// the playlist exemption it also admits is refused outright by the
// service (the documented invalid-request), so no owner ever pins.

func (s *Server) GetEntityArtworkLock(ctx context.Context, req GetEntityArtworkLockRequestObject) (GetEntityArtworkLockResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !entityArtworkPermitted(uc, string(req.EntityType)) {
		return GetEntityArtworkLock403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", entityArtworkRefusal(string(req.EntityType))))}, nil
	}
	locked, err := s.svc.EntityArtworkLock(ctx, string(req.EntityType), req.EntityPid, enumStr(req.Params.Role))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return GetEntityArtworkLock400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return GetEntityArtworkLock404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		}
		return nil, err
	}
	return GetEntityArtworkLock200JSONResponse(ArtworkLock{
		Locked:     locked.Locked,
		RoleLocked: ptr(locked.RoleLocked),
	}), nil
}

func (s *Server) SetEntityArtworkLock(ctx context.Context, req SetEntityArtworkLockRequestObject) (SetEntityArtworkLockResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !entityArtworkPermitted(uc, string(req.EntityType)) {
		return SetEntityArtworkLock403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", entityArtworkRefusal(string(req.EntityType))))}, nil
	}
	if req.Body == nil {
		return SetEntityArtworkLock400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a locked body is required"))}, nil
	}
	locked, err := s.svc.SetEntityArtworkLock(ctx, string(req.EntityType), req.EntityPid, enumStr(req.Params.Role), req.Body.Locked)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetEntityArtworkLock400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetEntityArtworkLock404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		}
		return nil, err
	}
	return SetEntityArtworkLock200JSONResponse(ArtworkLock{
		Locked:     locked.Locked,
		RoleLocked: ptr(locked.RoleLocked),
	}), nil
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

// --- acquisition ------------------------------------------------------------------

// The origin verbs mirror the custom-tag pair beside them: the same
// curate gate, the same not-found sentence, and the same field-locked
// arm, because the origin is one more curated field with a lock of its
// own. What differs is the replacement rule the schema documents - the
// four editable columns are written as sent, absent meaning cleared -
// which is the whole reason a correction is possible at all.

func (s *Server) SetItemAcquisition(ctx context.Context, req SetItemAcquisitionRequestObject) (SetItemAcquisitionResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return SetItemAcquisition403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	if req.Body == nil {
		return SetItemAcquisition400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a sourceType body is required"))}, nil
	}
	edit := service.AcquisitionEdit{
		SourceType: req.Body.SourceType,
		SourceURL:  req.Body.SourceUrl,
		SourceID:   deref(req.Body.SourceId),
		Provider:   deref(req.Body.Provider),
	}
	if req.Body.AcquiredAt != nil {
		edit.AcquiredAt = *req.Body.AcquiredAt
	}
	out, err := s.svc.SetItemAcquisition(ctx, uc, req.Pid, edit, service.MetadataEditParams{
		WriteBack: derefBool(req.Body.WriteBack),
		Lock:      boolOr(req.Body.Lock, true),
		Force:     derefBool(req.Body.Force),
	})
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return SetItemAcquisition400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return SetItemAcquisition404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return SetItemAcquisition409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return SetItemAcquisition200JSONResponse(editResultJSON(out)), nil
}

func (s *Server) ClearItemAcquisition(ctx context.Context, req ClearItemAcquisitionRequestObject) (ClearItemAcquisitionResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return ClearItemAcquisition403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	err = s.svc.ClearItemAcquisition(ctx, uc, req.Pid, service.MetadataEditParams{
		WriteBack: derefBool(req.Params.WriteBack),
		Lock:      boolOr(req.Params.Lock, true),
		Force:     derefBool(req.Params.Force),
	})
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ClearItemAcquisition400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return ClearItemAcquisition404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindLocked:
			return ClearItemAcquisition409JSONResponse{FieldLockedJSONResponse(errObj("field-locked", err.Error()))}, nil
		}
		return nil, err
	}
	return ClearItemAcquisition204Response{}, nil
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

// RenameEntity moves a whole entity onto new keying values. The
// refusals are upstream's and arrive as sentences worth showing: a
// field outside the rung's vocabulary and an empty name as 400, a
// locked member as 409 field-locked, and the coverage refusals (members
// landing apart, an archived member, a group titled apart) as 409
// conflict.
func (s *Server) RenameEntity(ctx context.Context, req RenameEntityRequestObject) (RenameEntityResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !uc.Admin {
		return RenameEntity403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil || len(req.Body.Fields) == 0 {
		return RenameEntity400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a fields body is required"))}, nil
	}
	out, err := s.svc.RenameEntity(ctx, string(req.EntityType), req.EntityPid, req.Body.Fields,
		editParams(req.Body.WriteBack, req.Body.Lock, req.Body.Force))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return RenameEntity400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return RenameEntity404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no "+string(req.EntityType)+" with pid "+req.EntityPid))}, nil
		case service.KindLocked:
			return RenameEntity409JSONResponse(errObj("field-locked", err.Error())), nil
		case service.KindConflict:
			return RenameEntity409JSONResponse(errObj("conflict", err.Error())), nil
		}
		return nil, err
	}
	res := EntityRenameResult{
		EntityPid: out.EntityPID,
		Outcome:   EntityRenameResultOutcome(out.Outcome),
		Members:   out.Members,
		Credits:   out.Credits,
	}
	if out.MergedInto != "" {
		res.MergedInto = ptr(out.MergedInto)
	}
	if len(out.MovedAlbums) > 0 {
		moved := append([]string{}, out.MovedAlbums...)
		res.MovedAlbums = &moved
	}
	if len(out.Failures) > 0 {
		fs := writeBackFailuresJSON(out.Failures)
		res.Failures = &fs
	}
	return RenameEntity200JSONResponse(res), nil
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

// --- detach -------------------------------------------------------------------------

// DetachItem pulls one track off its mbid-pinned release. Curate-gated
// like every item mutation beside it; the refusals are upstream's own
// sentences, which name the case (a non-track, a chain with no id, an
// album's last member).
func (s *Server) DetachItem(ctx context.Context, req DetachItemRequestObject) (DetachItemResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return DetachItem403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	writeBack := false
	if req.Body != nil {
		writeBack = boolOr(req.Body.WriteBack, false)
	}
	out, err := s.svc.DetachItem(ctx, uc, req.Pid, writeBack)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return DetachItem400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return DetachItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	res := DetachResult{ItemPid: out.ItemPID, OldAlbumPid: out.OldAlbumPID}
	if out.NewAlbumPID != "" {
		res.NewAlbumPid = ptr(out.NewAlbumPID)
	}
	if out.NewReleaseGroupPID != "" {
		res.NewReleaseGroupPid = ptr(out.NewReleaseGroupPID)
	}
	if len(out.Failures) > 0 {
		fs := writeBackFailuresJSON(out.Failures)
		res.Failures = &fs
	}
	return DetachItem200JSONResponse(res), nil
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
