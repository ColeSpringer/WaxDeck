package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// Upload session handlers: create, chunked data, complete, inspect.

func uploadJSON(u service.UploadDTO) Upload {
	out := Upload{
		Id:            u.ID,
		FileName:      u.FileName,
		SizeBytes:     u.SizeBytes,
		ReceivedBytes: u.ReceivedBytes,
		MediaType:     MediaType(u.MediaType),
		State:         u.State,
		CreatedAt:     u.CreatedAt,
	}
	if u.LibraryPID != "" {
		out.LibraryPid = ptr(u.LibraryPID)
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
	if u.Duplicate != nil {
		out.Duplicate = &DuplicateWarning{ItemPid: u.Duplicate.ItemPID, Kind: u.Duplicate.Kind}
		if u.Duplicate.Title != "" {
			out.Duplicate.Title = ptr(u.Duplicate.Title)
		}
		if u.Duplicate.Artist != "" {
			out.Duplicate.Artist = ptr(u.Duplicate.Artist)
		}
	}
	return out
}

func (s *Server) ListUploads(ctx context.Context, req ListUploadsRequestObject) (ListUploadsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	limit, ok := pageLimit(req.Params.Limit, 50, 200)
	if !ok {
		return ListUploads400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit out of range"))}, nil
	}
	uploads, next, err := s.svc.ListUploadsPage(ctx, uc, deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListUploads400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	page := UploadPage{Uploads: make([]Upload, 0, len(uploads))}
	for _, u := range uploads {
		page.Uploads = append(page.Uploads, uploadJSON(u))
	}
	if next != "" {
		page.NextCursor = ptr(next)
	}
	return ListUploads200JSONResponse(page), nil
}

func (s *Server) CreateUpload(ctx context.Context, req CreateUploadRequestObject) (CreateUploadResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return CreateUpload400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an upload body is required"))}, nil
	}
	u, err := s.svc.CreateUpload(ctx, uc, service.UploadCreateParams{
		FileName:   req.Body.FileName,
		SizeBytes:  req.Body.SizeBytes,
		MediaType:  string(req.Body.MediaType),
		LibraryPID: deref(req.Body.LibraryPid),
		SHA256:     deref(req.Body.Sha256),
	})
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid, service.KindNotFound:
			return CreateUpload400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return CreateUpload403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindQuota:
			return CreateUpload413JSONResponse{QuotaExceededJSONResponse(errObj("quota-exceeded", err.Error()))}, nil
		case service.KindFormat:
			return CreateUpload415JSONResponse{UnsupportedFormatJSONResponse(errObj("unsupported-format", err.Error()))}, nil
		}
		return nil, err
	}
	return CreateUpload201JSONResponse(uploadJSON(u)), nil
}

func (s *Server) GetUpload(ctx context.Context, req GetUploadRequestObject) (GetUploadResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	u, err := s.svc.GetUpload(ctx, uc, string(req.UploadId))
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetUpload404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such upload"))}, nil
		}
		return nil, err
	}
	return GetUpload200JSONResponse(uploadJSON(u)), nil
}

func (s *Server) DeleteUpload(ctx context.Context, req DeleteUploadRequestObject) (DeleteUploadResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.svc.DeleteUpload(ctx, uc, string(req.UploadId)); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return DeleteUpload404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such upload"))}, nil
		case service.KindConflict:
			return DeleteUpload409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return DeleteUpload204Response{}, nil
}

func (s *Server) PutUploadData(ctx context.Context, req PutUploadDataRequestObject) (PutUploadDataResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PutUploadData400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a chunk body is required"))}, nil
	}
	u, err := s.svc.AppendUploadData(ctx, uc, string(req.UploadId), req.Params.Offset, req.Body)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PutUploadData400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindNotFound:
			return PutUploadData404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such upload"))}, nil
		case service.KindConflict:
			return PutUploadData409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return PutUploadData200JSONResponse(uploadJSON(u)), nil
}

func (s *Server) CompleteUpload(ctx context.Context, req CompleteUploadRequestObject) (CompleteUploadResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	u, err := s.svc.CompleteUpload(ctx, uc, string(req.UploadId))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return CompleteUpload404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such upload"))}, nil
		case service.KindConflict:
			return CompleteUpload409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindFormat:
			return CompleteUpload415JSONResponse{UnsupportedFormatJSONResponse(errObj("unsupported-format", err.Error()))}, nil
		}
		return nil, err
	}
	return CompleteUpload200JSONResponse(uploadJSON(u)), nil
}

func (s *Server) CreateAcquisition(ctx context.Context, req CreateAcquisitionRequestObject) (CreateAcquisitionResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return CreateAcquisition400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an acquisition body is required"))}, nil
	}
	format := ""
	if req.Body.Format != nil {
		format = string(*req.Body.Format)
	}
	task, err := s.svc.StartAcquisition(ctx, uc, req.Body.Url, string(req.Body.MediaType), deref(req.Body.LibraryPid), format)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid, service.KindNotFound:
			return CreateAcquisition400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return CreateAcquisition403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindUnsupported:
			return CreateAcquisition501JSONResponse{SourceUnavailableJSONResponse(errObj("source-unavailable", err.Error()))}, nil
		}
		return nil, err
	}
	return CreateAcquisition202JSONResponse(toolTaskJSON(task)), nil
}

func (s *Server) RematchItem(ctx context.Context, req RematchItemRequestObject) (RematchItemResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !s.svc.CanCurateItem(ctx, uc, string(req.Pid)) {
		return RematchItem403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators, or the user whose upload brought the item in"))}, nil
	}
	entryID, err := s.svc.RematchItem(ctx, uc, string(req.Pid))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return RematchItem404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such item"))}, nil
		case service.KindConflict:
			return RematchItem409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindInvalid:
			return RematchItem409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return RematchItem202JSONResponse(RematchResult{ReviewEntryId: entryID}), nil
}
