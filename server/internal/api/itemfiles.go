package api

import (
	"context"
	"errors"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func (s *Server) GetItemFiles(ctx context.Context, req GetItemFilesRequestObject) (GetItemFilesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	files, err := s.svc.ItemFiles(ctx, uc, req.Pid)
	switch service.KindOf(err) {
	case "":
	case service.KindForbidden:
		return GetItemFiles403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
	case service.KindNotFound:
		return GetItemFiles404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
	default:
		return nil, err
	}
	out := ItemFiles{Files: make([]ItemFile, 0, len(files))}
	for _, f := range files {
		out.Files = append(out.Files, itemFileJSON(f))
	}
	return GetItemFiles200JSONResponse(out), nil
}

// itemFileJSON maps one of an item's files, leaving out each fact the
// catalog could not read.
func itemFileJSON(f service.ItemFileDTO) ItemFile {
	row := ItemFile{FilePid: service.FileAPIPID(f.FilePID), Role: f.Role, Name: f.Name}
	if f.SizeBytes > 0 {
		row.SizeBytes = ptr(f.SizeBytes)
	}
	if f.Path != "" {
		row.Path = ptr(f.Path)
	}
	if f.Codec != "" {
		row.Codec = ptr(f.Codec)
	}
	if f.Container != "" {
		row.Container = ptr(f.Container)
	}
	if f.Bitrate > 0 {
		row.Bitrate = ptr(f.Bitrate)
	}
	if f.SampleRate > 0 {
		row.SampleRate = ptr(f.SampleRate)
	}
	if f.BitDepth > 0 {
		row.BitDepth = ptr(f.BitDepth)
	}
	if f.DurationMS > 0 {
		row.DurationMs = ptr(f.DurationMS)
	}
	if f.LibraryPID != "" {
		row.LibraryPid = ptr(f.LibraryPID)
	}
	if f.Reason != "" {
		row.Reason = ptr(f.Reason)
	}
	return row
}

func (s *Server) DeleteItemFiles(ctx context.Context, req DeleteItemFilesRequestObject) (DeleteItemFilesResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return DeleteItemFiles400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	mode := ""
	if req.Body.Mode != nil {
		mode = string(*req.Body.Mode)
	}
	filePIDs, bad := bareFilePIDs(req.Body.FilePids)
	if bad != "" {
		return DeleteItemFiles400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "bad file pid "+bad))}, nil
	}
	res, err := s.svc.DeleteItemFiles(ctx, uc, req.Pid, filePIDs, mode, derefBool(req.Body.DryRun))
	switch service.KindOf(err) {
	case "":
	case service.KindInvalid:
		e := errObj("invalid-request", err.Error())
		if errors.Is(err, service.ErrCueRipPart) {
			e.Params = cueRipParams(err)
		}
		return DeleteItemFiles400JSONResponse{InvalidRequestJSONResponse(e)}, nil
	case service.KindForbidden:
		return DeleteItemFiles403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
	case service.KindNotFound:
		return DeleteItemFiles404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
	case service.KindReadOnly:
		return DeleteItemFiles409JSONResponse(errObj("read-only", err.Error())), nil
	case service.KindCatalogBusy, service.KindStorageUnwritable:
		return DeleteItemFiles409JSONResponse(errObj(string(service.KindOf(err)), err.Error())), nil
	default:
		return nil, err
	}
	return DeleteItemFiles200JSONResponse(deleteResultJSON(res)), nil
}

// cueRipParams are a partial cue rip delete's refusal params: the reason,
// and every track of the rip when the refusal names them.
func cueRipParams(err error) *map[string]string {
	params := map[string]string{"reason": "cue-rip"}
	var rip *service.CueRipTracks
	if errors.As(err, &rip) && len(rip.Tracks) > 0 {
		params["tracks"] = strings.Join(rip.Tracks, ",")
	}
	return &params
}

// bareFilePIDs reads the file pids a request names into the catalog's
// form, answering the first that is not one.
func bareFilePIDs(pids []string) ([]string, string) {
	out := make([]string, 0, len(pids))
	for _, p := range pids {
		bare, ok := service.ParseFilePID(p)
		if !ok {
			return nil, p
		}
		out = append(out, bare)
	}
	return out, ""
}
