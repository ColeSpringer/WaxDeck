package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Upload session handlers: create, chunked data, complete, inspect.

func uploadJSON(u service.UploadDTO) Upload {
	out := Upload{
		Id:            u.ID,
		FileName:      u.FileName,
		SizeBytes:     u.SizeBytes,
		ReceivedBytes: u.ReceivedBytes,
		IdleMs:        u.Idle.Milliseconds(),
		MediaType:     MediaType(u.MediaType),
		State:         u.State,
		CreatedAt:     u.CreatedAt,
	}
	if u.LibraryPID != "" {
		out.LibraryPid = ptr(u.LibraryPID)
	}
	if u.BatchID != "" {
		out.BatchId = ptr(u.BatchID)
	}
	if u.ReviewEntryID != "" {
		out.ReviewEntryId = ptr(u.ReviewEntryID)
	}
	if u.UploadedBy != "" {
		out.UploadedBy = ptr(u.UploadedBy)
	}
	if !u.ExpiresAt.IsZero() {
		out.ExpiresAt = ptr(u.ExpiresAt)
	}
	out.Duplicate = duplicateJSON(u.Duplicate)
	return out
}

// duplicateJSON is a duplicate warning in the spec's words; the item is
// named only where the service named it.
func duplicateJSON(d *service.DuplicateDTO) *DuplicateWarning {
	if d == nil {
		return nil
	}
	out := &DuplicateWarning{Kind: d.Kind}
	if d.ItemPID != "" {
		out.ItemPid = ptr(d.ItemPID)
	}
	if d.Title != "" {
		out.Title = ptr(d.Title)
	}
	if d.Artist != "" {
		out.Artist = ptr(d.Artist)
	}
	return out
}

// tooFast reports whether the caller has spent this account's share of
// the upload surface for now. See uploadbounds.go for what is charged
// and what is deliberately not.
func (s *Server) tooFast(uc *service.UserCtx) bool {
	return !s.uploads.allow(uc.ID)
}

// pacedOut is the refusal every paced endpoint answers with, so the next
// one added reaches for this rather than pasting the sentence again.
func pacedOut() error {
	return refuse(http.StatusTooManyRequests, "rate-limited", "too many upload requests; retry shortly")
}

func (s *Server) ListUploads(ctx context.Context, req ListUploadsRequestObject) (ListUploadsResponseObject, error) {
	uc := userCtx(ctx)
	limit, err := pageLimit(req.Params.Limit, 50, 200)
	if err != nil {
		return nil, err
	}
	uploads, next, quota, err := s.svc.ListUploadsPage(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	page := UploadPage{Uploads: make([]Upload, 0, len(uploads))}
	for _, u := range uploads {
		page.Uploads = append(page.Uploads, uploadJSON(u))
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	q := UploadQuota{BytesInUse: quota.BytesInUse}
	if quota.QuotaBytes > 0 {
		q.QuotaBytes = ptr(quota.QuotaBytes)
	}
	page.Quota = &q
	return ListUploads200JSONResponse(page), nil
}

// ListUploadTargets answers the destination picker: the libraries this
// caller may name, with no paths and no counts. Gated by upload rights
// rather than by admin, which is why it is its own narrow operation and
// not a relaxed listLibraries.
func (s *Server) ListUploadTargets(ctx context.Context, _ ListUploadTargetsRequestObject) (ListUploadTargetsResponseObject, error) {
	uc := userCtx(ctx)
	targets, err := s.svc.UploadTargets(ctx, uc)
	if err != nil {
		return nil, err
	}
	out := UploadTargets{Targets: make([]UploadTarget, 0, len(targets))}
	for _, t := range targets {
		media := make([]MediaType, 0, len(t.MediaTypes))
		for _, m := range t.MediaTypes {
			media = append(media, MediaType(m))
		}
		out.Targets = append(out.Targets, UploadTarget{
			Pid: t.PID, Name: t.Name, MediaTypes: media, Managed: t.Managed,
		})
	}
	return ListUploadTargets200JSONResponse(out), nil
}

func (s *Server) CreateUpload(ctx context.Context, req CreateUploadRequestObject) (CreateUploadResponseObject, error) {
	uc := userCtx(ctx)
	if s.tooFast(uc) {
		return nil, pacedOut()
	}
	if req.Body == nil {
		return nil, errNoBody()
	}
	u, err := s.svc.CreateUpload(ctx, uc, service.UploadCreateParams{
		FileName:   req.Body.FileName,
		SizeBytes:  req.Body.SizeBytes,
		MediaType:  string(req.Body.MediaType),
		LibraryPID: deref(req.Body.LibraryPid),
		SHA256:     deref(req.Body.Sha256),
		BatchID:    deref(req.Body.BatchId),
		BatchPath:  deref(req.Body.BatchPath),
		Identify:   req.Body.Identify,
	})
	if err != nil {
		if k := service.KindOf(err); k == service.KindInvalid || k == service.KindNotFound {
			return nil, refuse(http.StatusBadRequest, "invalid-request", serviceMessage(err))
		}
		return nil, err
	}
	return CreateUpload201JSONResponse(uploadJSON(u)), nil
}

func (s *Server) GetUpload(ctx context.Context, req GetUploadRequestObject) (GetUploadResponseObject, error) {
	uc := userCtx(ctx)
	u, err := s.svc.GetUpload(ctx, uc, string(req.UploadId))
	if err != nil {
		return nil, err
	}
	return GetUpload200JSONResponse(uploadJSON(u)), nil
}

func (s *Server) DeleteUpload(ctx context.Context, req DeleteUploadRequestObject) (DeleteUploadResponseObject, error) {
	uc := userCtx(ctx)
	if err := s.svc.DeleteUpload(ctx, uc, string(req.UploadId)); err != nil {
		return nil, err
	}
	return DeleteUpload204Response{}, nil
}

func (s *Server) PutUploadData(ctx context.Context, req PutUploadDataRequestObject) (PutUploadDataResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	// Refused at the header, where refusing is free. Reading an
	// over-cap body to find out how big it is writes a chunk's worth to
	// the very volume the staging check protects and then throws it
	// away - and the answer would not arrive either, since a caller
	// still streaming hundreds of megabytes is cut off long before the
	// server's own drain gives up on the rest of the body.
	if n := declaredBodyBytes(ctx); n > service.MaxUploadChunk {
		return nil, refuse(http.StatusBadRequest, "invalid-request", fmt.Sprintf(
			"a chunk may carry at most %d bytes; this one declares %d", service.MaxUploadChunk, n))
	}
	u, err := s.svc.AppendUploadData(ctx, uc, string(req.UploadId), req.Params.Offset, req.Body)
	if err != nil {
		return nil, err
	}
	return PutUploadData200JSONResponse(uploadJSON(u)), nil
}

func (s *Server) CompleteUpload(ctx context.Context, req CompleteUploadRequestObject) (CompleteUploadResponseObject, error) {
	uc := userCtx(ctx)
	if s.tooFast(uc) {
		return nil, pacedOut()
	}
	u, err := s.svc.CompleteUpload(ctx, uc, string(req.UploadId))
	if err != nil {
		kind := service.KindOf(err)
		if kind == service.KindConflict && errors.Is(err, service.ErrChecksumMismatch) {
			return nil, refuseParams(http.StatusConflict, "conflict", serviceMessage(err), map[string]string{"reason": "checksum-mismatch"})
		}
		if kind == service.KindFormat && errors.Is(err, service.ErrUnreadableUpload) {
			return nil, refuseParams(http.StatusUnsupportedMediaType, "unsupported-format", serviceMessage(err), map[string]string{"reason": "unreadable"})
		}
		return nil, err
	}
	return CompleteUpload200JSONResponse(uploadJSON(u)), nil
}

func uploadBatchJSON(b service.UploadBatchDTO) UploadBatch {
	out := UploadBatch{
		Id:        b.ID,
		Grouping:  UploadGrouping(b.Grouping),
		MediaType: MediaType(b.MediaType),
		State:     b.State,
		// Required in the schema: an entry-less batch answers [].
		ReviewEntryIds: make([]string, 0, len(b.ReviewEntryIDs)),
		CreatedAt:      b.CreatedAt,
		ExpiresAt:      b.ExpiresAt,
	}
	out.ReviewEntryIds = append(out.ReviewEntryIds, b.ReviewEntryIDs...)
	if b.LibraryPID != "" {
		out.LibraryPid = ptr(b.LibraryPID)
	}
	return out
}

func (s *Server) CreateUploadBatch(ctx context.Context, req CreateUploadBatchRequestObject) (CreateUploadBatchResponseObject, error) {
	uc := userCtx(ctx)
	if s.tooFast(uc) {
		return nil, pacedOut()
	}
	if req.Body == nil {
		return nil, errNoBody()
	}
	b, err := s.svc.CreateUploadBatch(ctx, uc, service.UploadBatchCreateParams{
		Grouping:   string(req.Body.Grouping),
		MediaType:  string(req.Body.MediaType),
		LibraryPID: deref(req.Body.LibraryPid),
		Identify:   req.Body.Identify,
	})
	if err != nil {
		if k := service.KindOf(err); k == service.KindInvalid || k == service.KindNotFound {
			return nil, refuse(http.StatusBadRequest, "invalid-request", serviceMessage(err))
		}
		return nil, err
	}
	return CreateUploadBatch201JSONResponse(uploadBatchJSON(b)), nil
}

func (s *Server) CompleteUploadBatch(ctx context.Context, req CompleteUploadBatchRequestObject) (CompleteUploadBatchResponseObject, error) {
	uc := userCtx(ctx)
	if s.tooFast(uc) {
		return nil, pacedOut()
	}
	b, err := s.svc.CompleteUploadBatch(ctx, uc, string(req.BatchId))
	if err != nil {
		return nil, err
	}
	return CompleteUploadBatch200JSONResponse(uploadBatchJSON(b)), nil
}

func (s *Server) CreateAcquisition(ctx context.Context, req CreateAcquisitionRequestObject) (CreateAcquisitionResponseObject, error) {
	uc := userCtx(ctx)
	if s.tooFast(uc) {
		return nil, pacedOut()
	}
	if req.Body == nil {
		return nil, errNoBody()
	}
	format := ""
	if req.Body.Format != nil {
		format = string(*req.Body.Format)
	}
	task, err := s.svc.StartAcquisition(ctx, uc, req.Body.Url, string(req.Body.MediaType), deref(req.Body.LibraryPid), format, req.Body.Identify)
	if err != nil {
		if k := service.KindOf(err); k == service.KindInvalid || k == service.KindNotFound {
			return nil, refuse(http.StatusBadRequest, "invalid-request", serviceMessage(err))
		}
		return nil, err
	}
	return CreateAcquisition202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) RematchItem(ctx context.Context, req RematchItemRequestObject) (RematchItemResponseObject, error) {
	uc := userCtx(ctx)
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return nil, refuse(http.StatusForbidden, "forbidden", "administrators, or the user whose upload brought the item in")
	}
	entryID, err := s.svc.RematchItem(ctx, uc, string(req.Pid))
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return nil, refuse(http.StatusConflict, "conflict", serviceMessage(err))
		}
		return nil, err
	}
	return RematchItem202JSONResponse(RematchResult{ReviewEntryId: entryID}), nil
}
