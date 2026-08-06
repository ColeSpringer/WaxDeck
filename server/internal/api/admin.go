package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// --- audit -------------------------------------------------------------------------

func (s *Server) ListAuditEvents(ctx context.Context, req ListAuditEventsRequestObject) (ListAuditEventsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListAuditEvents403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, okLimit := pageLimit(req.Params.Limit, 100, 500)
	if !okLimit {
		return ListAuditEvents400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	filter := wdb.AuditFilter{
		Action:    deref(req.Params.Action),
		ActorID:   deref(req.Params.ActorId),
		TargetPID: deref(req.Params.TargetPid),
	}
	page, err := s.svc.AuditEvents(ctx, filter, deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListAuditEvents400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := AuditEventPage{Events: make([]AuditEvent, 0, len(page.Events))}
	for _, e := range page.Events {
		out.Events = append(out.Events, auditEventJSON(e))
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListAuditEvents200JSONResponse(out), nil
}

func auditEventJSON(e service.AuditEventDTO) AuditEvent {
	out := AuditEvent{
		Id:        e.ID,
		Action:    e.Action,
		CreatedAt: time.Unix(0, e.CreatedAtNS).UTC(),
	}
	if e.ActorID != "" {
		out.ActorId = ptr(e.ActorID)
	}
	if e.ActorName != "" {
		out.ActorName = ptr(e.ActorName)
	}
	if e.TargetKind != "" {
		out.TargetKind = ptr(e.TargetKind)
	}
	if e.TargetPID != "" {
		out.TargetPid = ptr(e.TargetPID)
	}
	if e.TargetName != "" {
		out.TargetName = ptr(e.TargetName)
	}
	if len(e.Detail) > 0 {
		detail := e.Detail
		out.Detail = &detail
	}
	return out
}

// --- runtime settings --------------------------------------------------------------

func (s *Server) GetAdminSettings(ctx context.Context, _ GetAdminSettingsRequestObject) (GetAdminSettingsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetAdminSettings403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	st, err := s.svc.AdminSettingsGet(ctx)
	if err != nil {
		return nil, err
	}
	return GetAdminSettings200JSONResponse(adminSettingsJSON(st)), nil
}

func (s *Server) PutAdminSettings(ctx context.Context, req PutAdminSettingsRequestObject) (PutAdminSettingsResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutAdminSettings403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return PutAdminSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	// Absent keeps the current value: a settings writer predating either
	// field must never flip analysis off or clear retention by omission.
	sonic := s.svc.SonicAnalysisEnabled()
	if req.Body.SonicAnalysis != nil {
		sonic = *req.Body.SonicAnalysis
	}
	retentionDays := s.svc.TrashRetentionDays(ctx)
	if req.Body.TrashRetentionDays != nil {
		retentionDays = *req.Body.TrashRetentionDays
	}
	taskDays := s.svc.TaskRetentionDays(ctx)
	if req.Body.TaskRetentionDays != nil {
		taskDays = *req.Body.TaskRetentionDays
	}
	st, err := s.svc.AdminSettingsPut(ctx, uc, service.AdminSettings{
		SignupEnabled:      req.Body.SignupEnabled,
		ReadOnly:           req.Body.ReadOnly,
		SonicAnalysis:      sonic,
		BackupKeepCount:    req.Body.BackupKeepCount,
		BackupKeepBytes:    req.Body.BackupKeepBytes,
		TrashRetentionDays: retentionDays,
		TaskRetentionDays:  taskDays,
	})
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return PutAdminSettings400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return PutAdminSettings200JSONResponse(adminSettingsJSON(st)), nil
}

func adminSettingsJSON(st service.AdminSettings) AdminSettings {
	return AdminSettings{
		SignupEnabled:      st.SignupEnabled,
		ReadOnly:           st.ReadOnly,
		SonicAnalysis:      ptr(st.SonicAnalysis),
		BackupKeepCount:    st.BackupKeepCount,
		BackupKeepBytes:    st.BackupKeepBytes,
		TrashRetentionDays: ptr(st.TrashRetentionDays),
		TaskRetentionDays:  ptr(st.TaskRetentionDays),
	}
}

// --- transcoding limits ------------------------------------------------------------

func (s *Server) GetTranscodingLimits(ctx context.Context, _ GetTranscodingLimitsRequestObject) (GetTranscodingLimitsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetTranscodingLimits403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	lim := s.svc.TranscodingLimitsGet(ctx)
	return GetTranscodingLimits200JSONResponse(transcodingLimitsJSON(lim)), nil
}

func (s *Server) PutTranscodingLimits(ctx context.Context, req PutTranscodingLimitsRequestObject) (PutTranscodingLimitsResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutTranscodingLimits403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return PutTranscodingLimits400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	lim, err := s.svc.TranscodingLimitsPut(ctx, uc, service.TranscodingLimits{
		MaxConcurrent:         req.Body.MaxConcurrent,
		MaxConcurrentPerUser:  req.Body.MaxConcurrentPerUser,
		DefaultMaxBitrateKbps: req.Body.DefaultMaxBitrateKbps,
	})
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return PutTranscodingLimits400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return PutTranscodingLimits200JSONResponse(transcodingLimitsJSON(lim)), nil
}

func transcodingLimitsJSON(lim service.TranscodingLimits) TranscodingLimits {
	return TranscodingLimits{
		MaxConcurrent:         lim.MaxConcurrent,
		MaxConcurrentPerUser:  lim.MaxConcurrentPerUser,
		DefaultMaxBitrateKbps: lim.DefaultMaxBitrateKbps,
	}
}

// --- schedules ---------------------------------------------------------------------

func (s *Server) ListSchedules(ctx context.Context, _ ListSchedulesRequestObject) (ListSchedulesResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListSchedules403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	rows := s.svc.Schedules(ctx)
	out := ScheduleList{Schedules: make([]Schedule, 0, len(rows))}
	for _, row := range rows {
		out.Schedules = append(out.Schedules, scheduleJSON(row))
	}
	return ListSchedules200JSONResponse(out), nil
}

func (s *Server) PutSchedule(ctx context.Context, req PutScheduleRequestObject) (PutScheduleResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutSchedule403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return PutSchedule400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	row, err := s.svc.PutSchedule(ctx, uc, string(req.Kind), req.Body.Cron, req.Body.Enabled)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return PutSchedule400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return PutSchedule200JSONResponse(scheduleJSON(row)), nil
}

func scheduleJSON(row service.ScheduleDTO) Schedule {
	out := Schedule{
		Kind:    ScheduleKind(row.Kind),
		Cron:    row.Cron,
		Enabled: row.Enabled,
	}
	if row.LastRunNS > 0 {
		out.LastRunAt = ptr(time.Unix(0, row.LastRunNS).UTC())
	}
	if row.LastStatus != "" {
		out.LastStatus = ptr(row.LastStatus)
	}
	if row.LastError != "" {
		out.LastError = ptr(row.LastError)
	}
	if row.NextRunNS > 0 {
		out.NextRunAt = ptr(time.Unix(0, row.NextRunNS).UTC())
	}
	return out
}

// --- trash -------------------------------------------------------------------------

func (s *Server) ListTrash(ctx context.Context, req ListTrashRequestObject) (ListTrashResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ListTrash403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, okLimit := pageLimit(req.Params.Limit, 200, 1000)
	if !okLimit {
		return ListTrash400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 1000"))}, nil
	}
	entries, err := s.svc.TrashEntries(ctx, uc, derefBool(req.Params.IncludeRestored), limit)
	if err != nil {
		return nil, err
	}
	out := TrashList{Entries: make([]TrashEntry, 0, len(entries))}
	for _, e := range entries {
		row := TrashEntry{
			Id:        e.ID,
			Name:      e.Name,
			Reason:    e.Reason,
			SizeBytes: e.SizeBytes,
			TrashedAt: time.Unix(0, e.TrashedAtNS).UTC(),
		}
		if e.ItemPID != "" {
			row.ItemPid = ptr(e.ItemPID)
		}
		if e.RestoredNS > 0 {
			row.RestoredAt = ptr(time.Unix(0, e.RestoredNS).UTC())
		}
		out.Entries = append(out.Entries, row)
	}
	return ListTrash200JSONResponse(out), nil
}

func (s *Server) RestoreTrashEntry(ctx context.Context, req RestoreTrashEntryRequestObject) (RestoreTrashEntryResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return RestoreTrashEntry403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.RestoreTrashEntry(ctx, uc, string(req.TrashId)); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return RestoreTrashEntry404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no trash entry with id "+string(req.TrashId)))}, nil
		case service.KindConflict, service.KindInvalid:
			return RestoreTrashEntry409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return RestoreTrashEntry204Response{}, nil
}

func (s *Server) EmptyTrash(ctx context.Context, _ EmptyTrashRequestObject) (EmptyTrashResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return EmptyTrash403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	rep, err := s.svc.EmptyTrash(ctx, uc)
	if err != nil {
		return nil, err
	}
	return EmptyTrash200JSONResponse(TrashEmptyResult{
		Purged:         rep.Purged,
		Errored:        rep.Errored,
		ReclaimedBytes: rep.ReclaimedBytes,
	}), nil
}

func (s *Server) PurgeTrashEntry(ctx context.Context, req PurgeTrashEntryRequestObject) (PurgeTrashEntryResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PurgeTrashEntry403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	reclaimed, err := s.svc.PurgeTrashEntry(ctx, uc, string(req.TrashId))
	if err != nil {
		// A malformed or unknown trash id both read as "no such entry".
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			return PurgeTrashEntry404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no trash entry with id "+string(req.TrashId)))}, nil
		}
		return nil, err
	}
	return PurgeTrashEntry200JSONResponse(TrashPurgeResult{ReclaimedBytes: reclaimed}), nil
}

// --- deletion ----------------------------------------------------------------------

func (s *Server) DeleteLibraryItems(ctx context.Context, req DeleteLibraryItemsRequestObject) (DeleteLibraryItemsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return DeleteLibraryItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	mode := ""
	if req.Body.Mode != nil {
		mode = string(*req.Body.Mode)
	}
	res, err := s.svc.DeleteItems(ctx, uc, req.Body.Pids, mode, derefBool(req.Body.DryRun))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return DeleteLibraryItems400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return DeleteLibraryItems403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindNotFound:
			return DeleteLibraryItems404JSONResponse{NotFoundJSONResponse(errObj("not-found", err.Error()))}, nil
		case service.KindReadOnly:
			return DeleteLibraryItems409JSONResponse(errObj("read-only", err.Error())), nil
		case service.KindCatalogBusy:
			return DeleteLibraryItems409JSONResponse(errObj(string(service.KindCatalogBusy), err.Error())), nil
		}
		return nil, err
	}
	out := DeleteItemsResult{Applied: res.Applied, Mode: res.Mode,
		Entries: make([]DeletePlanEntry, 0, len(res.Entries))}
	for _, e := range res.Entries {
		row := DeletePlanEntry{Pid: e.PID, Files: e.Files, Bytes: e.Bytes}
		if e.Name != "" {
			row.Name = ptr(e.Name)
		}
		out.Entries = append(out.Entries, row)
	}
	return DeleteLibraryItems200JSONResponse(out), nil
}

// --- catalog jobs ------------------------------------------------------------------

func (s *Server) ListJobs(ctx context.Context, req ListJobsRequestObject) (ListJobsResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ListJobs403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, okLimit := pageLimit(req.Params.Limit, 50, 200)
	if !okLimit {
		return ListJobs400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 200"))}, nil
	}
	jobs, err := s.svc.Jobs(ctx, uc, limit)
	if err != nil {
		return nil, err
	}
	out := JobList{Jobs: make([]Job, 0, len(jobs))}
	for _, job := range jobs {
		out.Jobs = append(out.Jobs, jobJSON(job))
	}
	return ListJobs200JSONResponse(out), nil
}

// --- library read-only -------------------------------------------------------------

func (s *Server) GetLibraryReadOnly(ctx context.Context, req GetLibraryReadOnlyRequestObject) (GetLibraryReadOnlyResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetLibraryReadOnly403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	ro, err := s.svc.LibraryReadOnlyGet(ctx, req.Pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			return GetLibraryReadOnly404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no library with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return GetLibraryReadOnly200JSONResponse(LibraryReadOnly{ReadOnly: ro, LibraryPid: ptr(req.Pid)}), nil
}

func (s *Server) SetLibraryReadOnly(ctx context.Context, req SetLibraryReadOnlyRequestObject) (SetLibraryReadOnlyResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return SetLibraryReadOnly403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return SetLibraryReadOnly400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	if err := s.svc.LibraryReadOnlySet(ctx, uc, req.Pid, req.Body.ReadOnly); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			return SetLibraryReadOnly404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no library with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return SetLibraryReadOnly200JSONResponse(LibraryReadOnly{ReadOnly: req.Body.ReadOnly, LibraryPid: ptr(req.Pid)}), nil
}

func (s *Server) CreateLibrary(ctx context.Context, req CreateLibraryRequestObject) (CreateLibraryResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateLibrary403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return CreateLibrary400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	in := service.AddLibraryInput{
		Name:    req.Body.Name,
		Path:    req.Body.Path,
		Managed: derefBool(req.Body.Managed),
	}
	if req.Body.Media != nil {
		in.Media = string(*req.Body.Media)
	}
	lib, err := s.svc.AddLibrary(ctx, uc, in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return CreateLibrary400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindConflict:
			return CreateLibrary409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindForbidden:
			return CreateLibrary403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	// The generators flatten the allOf, so this is Library's fields plus
	// the warning rather than an embedded value.
	base := libraryDTO(lib)
	out := LibraryCreated{
		Pid:       base.Pid,
		Name:      base.Name,
		Media:     base.Media,
		Path:      base.Path,
		ItemCount: base.ItemCount,
	}
	if lib.StreamingWarning != "" {
		out.StreamingWarning = ptr(lib.StreamingWarning)
	}
	return CreateLibrary201JSONResponse(out), nil
}

// libraryDTO renders a catalog library for the admin surface. The count
// is omitted rather than sent as zero where nothing counted it (a
// create), so a client can tell "nothing here yet" from "not asked".
func libraryDTO(lib service.LibraryInfo) Library {
	out := Library{Pid: lib.PID, Name: lib.Name}
	if lib.Media != "" {
		out.Media = ptr(lib.Media)
	}
	if lib.Path != "" {
		out.Path = ptr(lib.Path)
	}
	if lib.ItemCount > 0 {
		out.ItemCount = ptr(lib.ItemCount)
	}
	return out
}

// --- migration ---------------------------------------------------------------------

func (s *Server) CreateMigration(ctx context.Context, req CreateMigrationRequestObject) (CreateMigrationResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateMigration403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return CreateMigration400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	in := service.MigrationRequest{
		Source:    req.Body.Source,
		ServerURL: req.Body.ServerUrl,
		Username:  deref(req.Body.Username),
		Password:  deref(req.Body.Password),
		Token:     deref(req.Body.Token),
		Stars:     true, Ratings: true, History: true, Progress: true,
		DryRun: derefBool(req.Body.DryRun),
	}
	if o := req.Body.Options; o != nil {
		if o.Stars != nil {
			in.Stars = *o.Stars
		}
		if o.Ratings != nil {
			in.Ratings = *o.Ratings
		}
		if o.History != nil {
			in.History = *o.History
		}
		if o.Progress != nil {
			in.Progress = *o.Progress
		}
	}
	task, err := s.svc.StartMigration(ctx, uc, in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return CreateMigration400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return CreateMigration403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return CreateMigration202JSONResponse(toolTaskJSON(task)), nil
}

// --- genre vocabulary --------------------------------------------------------------

// genreTreeJSON renders the service's vocabulary DTO.
func genreTreeJSON(d service.GenreTreeDTO) GenreTree {
	out := GenreTree{
		Source: GenreTreeSource(d.Source),
		Genres: make([]GenreNode, 0, len(d.Genres)),
	}
	for _, n := range d.Genres {
		node := GenreNode{Name: n.Name}
		if n.Parent != "" {
			node.Parent = ptr(n.Parent)
		}
		if len(n.Aliases) > 0 {
			node.Aliases = ptr(append([]string{}, n.Aliases...))
		}
		out.Genres = append(out.Genres, node)
	}
	return out
}

func (s *Server) GetGenreTree(ctx context.Context, req GetGenreTreeRequestObject) (GetGenreTreeResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return GetGenreTree403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	tree, err := s.svc.GenreTreeFor(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindForbidden {
			return GetGenreTree403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return GetGenreTree200JSONResponse(genreTreeJSON(tree)), nil
}

func (s *Server) PutGenreTree(ctx context.Context, req PutGenreTreeRequestObject) (PutGenreTreeResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutGenreTree403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return PutGenreTree400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	nodes := make([]service.GenreNodeDTO, 0, len(req.Body.Genres))
	for _, n := range req.Body.Genres {
		node := service.GenreNodeDTO{Name: n.Name, Parent: deref(n.Parent)}
		if n.Aliases != nil {
			node.Aliases = *n.Aliases
		}
		nodes = append(nodes, node)
	}
	tree, err := s.svc.PutGenreTree(ctx, uc, nodes)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return PutGenreTree400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return PutGenreTree403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return PutGenreTree200JSONResponse(genreTreeJSON(tree)), nil
}

func (s *Server) CreateGenreNormalization(ctx context.Context, req CreateGenreNormalizationRequestObject) (CreateGenreNormalizationResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateGenreNormalization403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	dryRun := false
	if req.Body != nil {
		dryRun = derefBool(req.Body.DryRun)
	}
	task, err := s.svc.StartGenreNormalize(ctx, uc, dryRun)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return CreateGenreNormalization400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindForbidden:
			return CreateGenreNormalization403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		}
		return nil, err
	}
	return CreateGenreNormalization202JSONResponse(toolTaskJSON(task)), nil
}

// --- task event stream -------------------------------------------------------------

// StreamToolTaskEvents serves one task's progress as server-sent
// events. The stream is a pull-based reader: each Read polls the task
// and blocks until it changes, so no goroutine is spawned and the
// generated response writer's copy loop drives the pacing.
func (s *Server) StreamToolTaskEvents(ctx context.Context, req StreamToolTaskEventsRequestObject) (StreamToolTaskEventsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	task, err := s.svc.GetToolTaskFor(ctx, uc, string(req.TaskId))
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return StreamToolTaskEvents404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no such task"))}, nil
		}
		return nil, err
	}
	return StreamToolTaskEvents200TexteventStreamResponse{
		Body: &taskEventStream{ctx: ctx, s: s, uc: uc, taskID: string(req.TaskId), last: task},
	}, nil
}

// taskEventStream produces SSE frames on demand. The first Read emits
// the current state; later Reads poll until the task changes, then emit
// it; a terminal state emits a final done event and then EOF.
type taskEventStream struct {
	ctx     context.Context
	s       *Server
	uc      *service.UserCtx
	taskID  string
	last    service.ToolTaskDTO
	started bool
	done    bool
	buf     []byte
}

func (t *taskEventStream) Read(p []byte) (int, error) {
	for len(t.buf) == 0 {
		if t.done {
			return 0, io.EOF
		}
		if !t.started {
			t.started = true
			t.stage(t.last)
			continue
		}
		if terminalTaskState(t.last.State) {
			t.buf = append(t.buf, "event: done\ndata: {}\n\n"...)
			t.done = true
			continue
		}
		select {
		case <-t.ctx.Done():
			return 0, t.ctx.Err()
		case <-time.After(time.Second):
		}
		cur, err := t.s.svc.GetToolTaskFor(t.ctx, t.uc, t.taskID)
		if err != nil {
			return 0, io.EOF
		}
		if taskChanged(t.last, cur) {
			t.last = cur
			t.stage(cur)
		}
	}
	n := copy(p, t.buf)
	t.buf = t.buf[n:]
	return n, nil
}

// stage buffers one task event frame.
func (t *taskEventStream) stage(task service.ToolTaskDTO) {
	payload, err := json.Marshal(toolTaskJSON(task))
	if err != nil {
		payload = []byte("{}")
	}
	t.buf = append(t.buf, fmt.Sprintf("event: task\ndata: %s\n\n", payload)...)
}

func terminalTaskState(state string) bool {
	return state == "done" || state == "failed"
}

func taskChanged(a, b service.ToolTaskDTO) bool {
	return a.State != b.State || a.ProgressPct != b.ProgressPct || a.Error != b.Error
}

// --- backups -----------------------------------------------------------------------

func (s *Server) ListBackups(ctx context.Context, _ ListBackupsRequestObject) (ListBackupsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListBackups403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	rows, err := s.backups.List(ctx)
	if err != nil {
		return nil, err
	}
	out := BackupList{Backups: make([]Backup, 0, len(rows))}
	for _, b := range rows {
		out.Backups = append(out.Backups, backupJSON(b))
	}
	return ListBackups200JSONResponse(out), nil
}

func (s *Server) CreateBackup(ctx context.Context, _ CreateBackupRequestObject) (CreateBackupResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateBackup403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	row, err := s.backups.Create(ctx, uc, "manual")
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return CreateBackup409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	// The runner loop in main drains this; a full channel is fine (the
	// loop also sweeps for claimed-but-unrun rows).
	if s.backupWake != nil {
		select {
		case s.backupWake <- row.ID:
		default:
		}
	}
	return CreateBackup202JSONResponse(backupJSON(row)), nil
}

func (s *Server) GetBackup(ctx context.Context, req GetBackupRequestObject) (GetBackupResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetBackup403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	row, err := s.backups.Get(ctx, string(req.BackupId))
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetBackup404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no backup with id "+string(req.BackupId)))}, nil
		}
		return nil, err
	}
	return GetBackup200JSONResponse(backupJSON(row)), nil
}

func (s *Server) DeleteBackup(ctx context.Context, req DeleteBackupRequestObject) (DeleteBackupResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return DeleteBackup403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.backups.Delete(ctx, uc, string(req.BackupId)); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return DeleteBackup404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no backup with id "+string(req.BackupId)))}, nil
		case service.KindConflict:
			return DeleteBackup409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return DeleteBackup204Response{}, nil
}

// DownloadBackup is unreachable: ServeBackupArchive owns BackupArchiveRoute
// on the outer mux, and an exact pattern wins over the generated router's
// /api/v1/ prefix. The method stays because the generated strict
// interface requires one for every declared operation, and the
// operation stays declared so clients keep generating against it. The
// generated response shape streams a whole body and cannot serve
// ranges, which is exactly why the raw handler exists.
//
// Reaching this means a mux registered the generated router without
// BackupArchiveRoute beside it, so the error names that rather than
// pretending to be a server fault.
func (s *Server) DownloadBackup(ctx context.Context, req DownloadBackupRequestObject) (DownloadBackupResponseObject, error) {
	return nil, errors.New("api: the backup archive is served outside the generated router; this mux is missing api.BackupArchiveRoute")
}

func (s *Server) ImportBackup(ctx context.Context, req ImportBackupRequestObject) (ImportBackupResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ImportBackup403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return ImportBackup400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "an archive body is required"))}, nil
	}
	const maxImportBytes = 16 << 30
	row, err := s.backups.Import(ctx, uc, req.Body, maxImportBytes)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindInvalid:
			return ImportBackup400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		case service.KindQuota:
			return ImportBackup413JSONResponse(errObj("quota-exceeded", err.Error())), nil
		}
		return nil, err
	}
	return ImportBackup201JSONResponse(backupJSON(row)), nil
}

func (s *Server) StageRestore(ctx context.Context, req StageRestoreRequestObject) (StageRestoreResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return StageRestore403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	plan, err := s.backups.StageRestore(ctx, uc, string(req.BackupId))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return StageRestore404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no backup with id "+string(req.BackupId)))}, nil
		case service.KindConflict:
			return StageRestore409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return StageRestore200JSONResponse(restorePlanJSON(plan)), nil
}

func (s *Server) GetStagedRestore(ctx context.Context, _ GetStagedRestoreRequestObject) (GetStagedRestoreResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetStagedRestore403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	plan, err := s.backups.StagedRestore(ctx)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetStagedRestore404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no restore is staged"))}, nil
		}
		return nil, err
	}
	return GetStagedRestore200JSONResponse(restorePlanJSON(plan)), nil
}

func (s *Server) CancelStagedRestore(ctx context.Context, _ CancelStagedRestoreRequestObject) (CancelStagedRestoreResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CancelStagedRestore403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.backups.CancelStagedRestore(ctx, uc); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return CancelStagedRestore404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no restore is staged"))}, nil
		}
		return nil, err
	}
	return CancelStagedRestore204Response{}, nil
}

func backupJSON(b wdb.Backup) Backup {
	out := Backup{
		Id:        b.ID,
		State:     b.State,
		Trigger:   b.Origin,
		FileName:  b.FileName,
		CreatedAt: time.Unix(0, b.CreatedAtNS).UTC(),
	}
	if b.SizeBytes > 0 {
		out.SizeBytes = ptr(b.SizeBytes)
	}
	if b.Error != "" {
		out.Error = ptr(b.Error)
	}
	if b.FinishedAtNS > 0 {
		out.FinishedAt = ptr(time.Unix(0, b.FinishedAtNS).UTC())
	}
	return out
}

func restorePlanJSON(plan service.RestorePlan) RestorePlan {
	out := RestorePlan{
		BackupId:         plan.BackupID,
		StagedAt:         time.Unix(0, plan.StagedAtNS).UTC(),
		KeyfilePresent:   plan.KeyfilePresent,
		KeyfileMatches:   plan.KeyfileMatches,
		SealedCasualties: make([]SealedCasualty, 0, len(plan.SealedCasualties)),
		Warnings:         plan.Warnings,
	}
	if out.Warnings == nil {
		out.Warnings = []string{}
	}
	for _, c := range plan.SealedCasualties {
		out.SealedCasualties = append(out.SealedCasualties, SealedCasualty{Kind: c.Kind, Name: c.Name})
	}
	return out
}

// --- scrobbling credentials ----------------------------------------------------

func (s *Server) GetScrobblingConfig(ctx context.Context, _ GetScrobblingConfigRequestObject) (GetScrobblingConfigResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return GetScrobblingConfig403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	return GetScrobblingConfig200JSONResponse(scrobblingConfigJSON(s.svc.LastfmConfigGet(ctx))), nil
}

func (s *Server) PutScrobblingConfig(ctx context.Context, req PutScrobblingConfigRequestObject) (PutScrobblingConfigResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return PutScrobblingConfig403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return PutScrobblingConfig400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	cfg, err := s.svc.LastfmConfigPut(ctx, uc, req.Body.LastfmApiKey, req.Body.LastfmSecret)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return PutScrobblingConfig400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return PutScrobblingConfig200JSONResponse(scrobblingConfigJSON(cfg)), nil
}

func scrobblingConfigJSON(cfg service.LastfmServerConfig) ScrobblingAdminConfig {
	out := ScrobblingAdminConfig{
		LastfmConfigured: cfg.Configured,
		LastfmSource:     cfg.Source,
		LastfmSecretSet:  cfg.SecretSet,
	}
	if cfg.Configured {
		out.LastfmApiKey = ptr(cfg.APIKey)
	}
	return out
}
