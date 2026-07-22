package api

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func (s *Server) Signup(ctx context.Context, req SignupRequestObject) (SignupResponseObject, error) {
	if req.Body == nil || req.Body.Username == "" || req.Body.Password == "" {
		return Signup400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "username and password are required"))}, nil
	}
	if msg := passwordPolicy(req.Body.Password); msg != "" {
		return Signup400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
	}
	// One shared per-address budget covers open signups and invite
	// probes alike; failures burn it, successes do not.
	ip := remoteIPFromContext(ctx)
	ipKey := "signup-ip:" + ip
	if !s.limiter.Allowed(ipKey) {
		return Signup429JSONResponse{RateLimitedJSONResponse(errObj("rate-limited", "too many signup attempts; retry later"))}, nil
	}
	_, state, err := s.svc.Signup(ctx, req.Body.Username, req.Body.Password,
		deref(req.Body.DisplayName), deref(req.Body.InviteToken))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindForbidden:
			s.limiter.Failure(ipKey)
			s.log.Warn(authFailureLog, "user", req.Body.Username, "ip", ip, "path", "signup")
			return Signup403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", err.Error()))}, nil
		case service.KindConflict:
			s.limiter.Failure(ipKey)
			return Signup409JSONResponse{ConflictJSONResponse(errObj("conflict", "username is taken"))}, nil
		case service.KindInvalid:
			return Signup400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	// Success consumes budget too: the limiter otherwise bounds only
	// failed probes, and account creation is the expensive outcome. A
	// NAT'd household admitting a handful of members stays under the
	// threshold; a script farming accounts does not.
	s.limiter.Failure(ipKey)
	return Signup201JSONResponse(SignupResult{State: SignupResultState(state)}), nil
}

func (s *Server) ListSignupRequests(ctx context.Context, req ListSignupRequestsRequestObject) (ListSignupRequestsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListSignupRequests403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, okLimit := pageLimit(req.Params.Limit, 100, 500)
	if !okLimit {
		return ListSignupRequests400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	page, err := s.svc.PendingAccounts(ctx, deref(req.Params.Cursor), limit)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return ListSignupRequests400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := UserPage{Users: make([]UserAccount, 0, len(page.Accounts))}
	for _, acct := range page.Accounts {
		out.Users = append(out.Users, userAccountJSON(acct))
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListSignupRequests200JSONResponse(out), nil
}

func (s *Server) ApproveSignupRequest(ctx context.Context, req ApproveSignupRequestRequestObject) (ApproveSignupRequestResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return ApproveSignupRequest403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	ap := service.SignupApproval{}
	if req.Body != nil {
		ap.Roles = roleStrings(req.Body.Roles)
		ap.UploadEnabled = req.Body.UploadEnabled
		ap.UploadQuotaBytes = req.Body.UploadQuotaBytes
		if req.Body.LibraryAccess != nil {
			ap.AccessMode = string(req.Body.LibraryAccess.Mode)
			if req.Body.LibraryAccess.LibraryPids != nil {
				ap.LibraryPIDs = *req.Body.LibraryAccess.LibraryPids
			}
		}
		if req.Body.Permissions != nil {
			perms := permissionsFromGen(*req.Body.Permissions)
			ap.Permissions = &perms
		}
	}
	acct, err := s.svc.ApproveSignup(ctx, uc, req.UserId, ap)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return ApproveSignupRequest404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		case service.KindConflict:
			return ApproveSignupRequest409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindInvalid:
			return ApproveSignupRequest400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return ApproveSignupRequest200JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) RejectSignupRequest(ctx context.Context, req RejectSignupRequestRequestObject) (RejectSignupRequestResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return RejectSignupRequest403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.RejectSignup(ctx, uc, req.UserId); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return RejectSignupRequest404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		case service.KindConflict:
			return RejectSignupRequest409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return RejectSignupRequest204Response{}, nil
}

func (s *Server) ListInvites(ctx context.Context, _ ListInvitesRequestObject) (ListInvitesResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListInvites403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	invites, err := s.svc.Invites(ctx)
	if err != nil {
		return nil, err
	}
	out := InviteList{Invites: make([]Invite, 0, len(invites))}
	for _, iv := range invites {
		out.Invites = append(out.Invites, inviteJSON(iv))
	}
	return ListInvites200JSONResponse(out), nil
}

func (s *Server) CreateInvite(ctx context.Context, req CreateInviteRequestObject) (CreateInviteResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return CreateInvite403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	in := service.InviteCreate{MaxUses: 1}
	if req.Body != nil {
		in.Note = deref(req.Body.Note)
		in.Roles = roleStrings(req.Body.Roles)
		if req.Body.LibraryAccess != nil {
			in.AccessMode = string(req.Body.LibraryAccess.Mode)
			if req.Body.LibraryAccess.LibraryPids != nil {
				in.LibraryPIDs = *req.Body.LibraryAccess.LibraryPids
			}
		}
		if req.Body.Permissions != nil {
			perms := permissionsFromGen(*req.Body.Permissions)
			in.Permissions = &perms
		}
		if req.Body.UploadEnabled != nil {
			in.UploadEnabled = *req.Body.UploadEnabled
		}
		if req.Body.MaxUses != nil {
			in.MaxUses = *req.Body.MaxUses
		}
		if req.Body.ExpiresAt != nil {
			in.ExpiresAtNS = req.Body.ExpiresAt.UnixNano()
		}
	}
	iv, err := s.svc.CreateInvite(ctx, uc, in)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return CreateInvite400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	out := InviteCreated{Token: iv.Token}
	base := inviteJSON(iv)
	out.Id = base.Id
	out.Note = base.Note
	out.Roles = base.Roles
	out.LibraryAccess = base.LibraryAccess
	out.Permissions = base.Permissions
	out.UploadEnabled = base.UploadEnabled
	out.MaxUses = base.MaxUses
	out.UsedCount = base.UsedCount
	out.Revoked = base.Revoked
	out.ExpiresAt = base.ExpiresAt
	out.CreatedAt = base.CreatedAt
	out.CreatedBy = base.CreatedBy
	return CreateInvite201JSONResponse(out), nil
}

func (s *Server) RevokeInvite(ctx context.Context, req RevokeInviteRequestObject) (RevokeInviteResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return RevokeInvite403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if err := s.svc.RevokeInvite(ctx, uc, req.InviteId); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return RevokeInvite404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no invite with id "+req.InviteId))}, nil
		}
		return nil, err
	}
	return RevokeInvite204Response{}, nil
}

// permissionsFromGen maps the wire permission object to the service's.
func permissionsFromGen(p Permissions) service.Permissions {
	out := service.Permissions{
		Download:       p.Download,
		Delete:         p.Delete,
		Explicit:       p.ExplicitContent,
		SharedOutputs:  p.SharedOutputs,
		ManagePodcasts: p.ManagePodcasts,
	}
	if p.MaxTranscodeKbps != nil {
		out.MaxTranscodeKbps = int64(*p.MaxTranscodeKbps)
	}
	if p.TagAllow != nil {
		for _, r := range *p.TagAllow {
			out.TagAllow = append(out.TagAllow, service.TagRule{Key: r.Key, Value: deref(r.Value)})
		}
	}
	if p.TagDeny != nil {
		for _, r := range *p.TagDeny {
			out.TagDeny = append(out.TagDeny, service.TagRule{Key: r.Key, Value: deref(r.Value)})
		}
	}
	return out
}

// permissionsJSON maps the service permission set to the wire object.
func permissionsJSON(p service.Permissions) Permissions {
	out := Permissions{
		Download:        p.Download,
		Delete:          p.Delete,
		ExplicitContent: p.Explicit,
		SharedOutputs:   p.SharedOutputs,
		ManagePodcasts:  p.ManagePodcasts,
	}
	if p.MaxTranscodeKbps > 0 {
		out.MaxTranscodeKbps = ptr(int(p.MaxTranscodeKbps))
	}
	if len(p.TagAllow) > 0 {
		rules := tagRulesJSON(p.TagAllow)
		out.TagAllow = &rules
	}
	if len(p.TagDeny) > 0 {
		rules := tagRulesJSON(p.TagDeny)
		out.TagDeny = &rules
	}
	return out
}

func tagRulesJSON(rules []service.TagRule) []TagRule {
	out := make([]TagRule, 0, len(rules))
	for _, r := range rules {
		tr := TagRule{Key: r.Key}
		if r.Value != "" {
			tr.Value = ptr(r.Value)
		}
		out = append(out, tr)
	}
	return out
}

func inviteJSON(iv service.InviteDTO) Invite {
	out := Invite{
		Id:            iv.ID,
		Roles:         make([]Role, 0, len(iv.Roles)),
		UploadEnabled: iv.UploadEnabled,
		MaxUses:       iv.MaxUses,
		UsedCount:     iv.UsedCount,
		Revoked:       iv.Revoked,
		CreatedAt:     time.Unix(0, iv.CreatedAtNS).UTC(),
	}
	for _, r := range iv.Roles {
		out.Roles = append(out.Roles, Role(r))
	}
	if iv.Note != "" {
		out.Note = ptr(iv.Note)
	}
	if iv.CreatedBy != "" {
		out.CreatedBy = ptr(iv.CreatedBy)
	}
	if iv.ExpiresAtNS != 0 {
		out.ExpiresAt = ptr(time.Unix(0, iv.ExpiresAtNS).UTC())
	}
	if iv.AccessMode != "" {
		la := LibraryAccess{Mode: LibraryAccessMode(iv.AccessMode)}
		if iv.AccessMode == "granted" {
			pids := iv.LibraryPIDs
			if pids == nil {
				pids = []string{}
			}
			la.LibraryPids = &pids
		}
		out.LibraryAccess = &la
	}
	if iv.Permissions != nil {
		perms := permissionsJSON(*iv.Permissions)
		out.Permissions = &perms
	}
	return out
}
