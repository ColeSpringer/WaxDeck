package api

import (
	"context"
	"errors"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// --- bootstrap ---------------------------------------------------------------------

func (s *Server) GetBootstrapStatus(ctx context.Context, _ GetBootstrapStatusRequestObject) (GetBootstrapStatusResponseObject, error) {
	required, err := s.svc.BootstrapRequired(ctx)
	if err != nil {
		return nil, err
	}
	return GetBootstrapStatus200JSONResponse{Required: required}, nil
}

func (s *Server) Bootstrap(ctx context.Context, req BootstrapRequestObject) (BootstrapResponseObject, error) {
	if req.Body == nil {
		return Bootstrap400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	if msg := passwordPolicy(req.Body.Password); msg != "" {
		return Bootstrap400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
	}
	acct, err := s.svc.Bootstrap(ctx, req.Body.Username, req.Body.Password, deref(req.Body.DisplayName))
	if err != nil {
		switch service.KindOf(err) {
		case service.KindConflict:
			return Bootstrap409JSONResponse{ConflictJSONResponse(errObj("conflict", "the server already has accounts"))}, nil
		case service.KindInvalid:
			return Bootstrap400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	s.log.Info("first administrator created", "user", acct.User.ID, "username", acct.User.Username)
	created, err := s.sessions.Create(ctx, acct.User.ID, "web", "", clientFromContext(ctx))
	if err != nil {
		return nil, err
	}
	setCookie := s.newSessionCookie(created.Token)
	return Bootstrap200JSONResponse{
		Body:    LoginResponse{User: userJSON(acct.User), Token: created.Token, CsrfToken: created.CSRFToken},
		Headers: Bootstrap200ResponseHeaders{SetCookie: &setCookie},
	}, nil
}

// --- session & device management ---------------------------------------------------

func (s *Server) RefreshToken(ctx context.Context, _ RefreshTokenRequestObject) (RefreshTokenResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return RefreshToken401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	if p.FromCookie {
		return RefreshToken400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "cookie sessions have no bearer token to rotate"))}, nil
	}
	token, err := s.sessions.Rotate(ctx, p.Session)
	if err != nil {
		return nil, err
	}
	return RefreshToken200JSONResponse(LoginResponse{
		User: userJSON(p.User), Token: token, CsrfToken: p.Session.CSRFToken,
	}), nil
}

func (s *Server) ListSessions(ctx context.Context, _ ListSessionsRequestObject) (ListSessionsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return ListSessions401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	rows, err := s.sessions.ListForUser(ctx, p.User.ID)
	if err != nil {
		return nil, err
	}
	out := SessionList{Sessions: make([]DeviceSession, 0, len(rows))}
	for _, row := range rows {
		out.Sessions = append(out.Sessions, deviceSessionJSON(row, row.ID == p.Session.ID))
	}
	return ListSessions200JSONResponse(out), nil
}

func (s *Server) RevokeSession(ctx context.Context, req RevokeSessionRequestObject) (RevokeSessionResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return RevokeSession401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	target, err := s.sessions.Get(ctx, req.SessionId)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return RevokeSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no session with id "+req.SessionId))}, nil
		}
		return nil, err
	}
	// A foreign session is indistinguishable from a missing one.
	if target.UserID != p.User.ID {
		return RevokeSession404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no session with id "+req.SessionId))}, nil
	}
	if err := s.sessions.Revoke(ctx, target.ID); err != nil {
		return nil, err
	}
	headers := RevokeSession204ResponseHeaders{}
	if target.ID == p.Session.ID && p.FromCookie {
		expired := s.expiredSessionCookie()
		headers.SetCookie = &expired
	}
	return RevokeSession204Response{Headers: headers}, nil
}

func (s *Server) RevokeUserSessions(ctx context.Context, req RevokeUserSessionsRequestObject) (RevokeUserSessionsResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return RevokeUserSessions401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	if req.UserId != p.User.ID && !p.IsAdmin() {
		return RevokeUserSessions403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if _, err := s.svc.Account(ctx, req.UserId); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return RevokeUserSessions404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		}
		return nil, err
	}
	keep := ""
	if req.UserId == p.User.ID {
		keep = p.Session.ID
	}
	if err := s.sessions.RevokeAllForUser(ctx, req.UserId, keep); err != nil {
		return nil, err
	}
	return RevokeUserSessions204Response{}, nil
}

func deviceSessionJSON(row *wdb.Session, current bool) DeviceSession {
	out := DeviceSession{
		Id:        row.ID,
		Kind:      DeviceSessionKind(row.Kind),
		CreatedAt: row.CreatedAt,
		Current:   current,
	}
	if row.DeviceName != "" {
		out.DeviceName = ptr(row.DeviceName)
	}
	if row.Client != "" {
		out.Client = ptr(row.Client)
	}
	if !row.LastSeenAt.IsZero() {
		out.LastSeenAt = ptr(row.LastSeenAt)
	}
	return out
}

// --- user administration -----------------------------------------------------------

func (s *Server) ListUsers(ctx context.Context, req ListUsersRequestObject) (ListUsersResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListUsers403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	limit, okLimit := pageLimit(req.Params.Limit, 100, 500)
	if !okLimit {
		return ListUsers400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "limit must be between 1 and 500"))}, nil
	}
	page, err := s.svc.Accounts(ctx, deref(req.Params.Cursor), limit)
	if err != nil {
		return nil, err
	}
	out := UserPage{Users: make([]UserAccount, 0, len(page.Accounts))}
	for _, acct := range page.Accounts {
		out.Users = append(out.Users, userAccountJSON(acct))
	}
	if page.Next != "" {
		out.NextCursor = ptr(page.Next)
	}
	return ListUsers200JSONResponse(out), nil
}

func (s *Server) CreateUser(ctx context.Context, req CreateUserRequestObject) (CreateUserResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return CreateUser403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.Body == nil {
		return CreateUser400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	if msg := passwordPolicy(req.Body.Password); msg != "" {
		return CreateUser400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
	}
	in := service.AccountCreate{
		Username:    req.Body.Username,
		Password:    req.Body.Password,
		DisplayName: deref(req.Body.DisplayName),
		Roles:       roleStrings(req.Body.Roles),
	}
	if req.Body.LibraryAccess != nil {
		in.AccessMode = string(req.Body.LibraryAccess.Mode)
		if req.Body.LibraryAccess.LibraryPids != nil {
			in.LibraryPIDs = *req.Body.LibraryAccess.LibraryPids
		}
	}
	if req.Body.UploadEnabled != nil {
		in.UploadEnabled = *req.Body.UploadEnabled
	}
	if req.Body.UploadQuotaBytes != nil {
		in.UploadQuotaBytes = *req.Body.UploadQuotaBytes
	}
	acct, err := s.svc.CreateAccount(ctx, in)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindConflict:
			return CreateUser409JSONResponse{ConflictJSONResponse(errObj("conflict", "username is taken"))}, nil
		case service.KindInvalid:
			return CreateUser400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return CreateUser201JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) GetUser(ctx context.Context, req GetUserRequestObject) (GetUserResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return GetUser401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	if req.UserId != p.User.ID && !p.IsAdmin() {
		return GetUser403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	acct, err := s.svc.Account(ctx, req.UserId)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return GetUser404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		}
		return nil, err
	}
	return GetUser200JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) UpdateUser(ctx context.Context, req UpdateUserRequestObject) (UpdateUserResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return UpdateUser401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	if req.Body == nil {
		return UpdateUser400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	admin := p.IsAdmin()
	if req.UserId != p.User.ID && !admin {
		return UpdateUser403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	// Non-administrators may change only their own display name; any
	// other supplied field is rejected loudly, never silently ignored.
	if !admin && (req.Body.Roles != nil || req.Body.Disabled != nil || req.Body.LibraryAccess != nil ||
		req.Body.UploadEnabled != nil || req.Body.UploadQuotaBytes != nil) {
		return UpdateUser403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "only displayName may be changed on your own account"))}, nil
	}
	upd := service.AccountUpdate{
		DisplayName:      req.Body.DisplayName,
		Disabled:         req.Body.Disabled,
		UploadEnabled:    req.Body.UploadEnabled,
		UploadQuotaBytes: req.Body.UploadQuotaBytes,
	}
	if req.Body.Roles != nil {
		upd.Roles = roleStrings(req.Body.Roles)
	}
	if req.Body.LibraryAccess != nil {
		mode := string(req.Body.LibraryAccess.Mode)
		upd.AccessMode = &mode
		if req.Body.LibraryAccess.LibraryPids != nil {
			upd.LibraryPIDs = *req.Body.LibraryAccess.LibraryPids
		}
	}
	acct, err := s.svc.UpdateAccount(ctx, req.UserId, upd)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return UpdateUser404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		case service.KindConflict:
			return UpdateUser409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		case service.KindInvalid:
			return UpdateUser400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	// Disabling revokes the account's sessions immediately.
	if req.Body.Disabled != nil && *req.Body.Disabled {
		if err := s.sessions.RevokeAllForUser(ctx, req.UserId, ""); err != nil {
			return nil, err
		}
	}
	return UpdateUser200JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) DeleteUser(ctx context.Context, req DeleteUserRequestObject) (DeleteUserResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return DeleteUser403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	if req.UserId == p.User.ID {
		return DeleteUser409JSONResponse{ConflictJSONResponse(errObj("conflict", "you cannot delete the account you are signed in as"))}, nil
	}
	if err := s.svc.DeleteAccount(ctx, req.UserId); err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return DeleteUser404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		case service.KindConflict:
			return DeleteUser409JSONResponse{ConflictJSONResponse(errObj("conflict", err.Error()))}, nil
		}
		return nil, err
	}
	return DeleteUser204Response{}, nil
}

func (s *Server) SetPassword(ctx context.Context, req SetPasswordRequestObject) (SetPasswordResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok {
		return SetPassword401JSONResponse{UnauthenticatedJSONResponse(errObj("unauthenticated", "no valid session or token was presented"))}, nil
	}
	if req.Body == nil {
		return SetPassword400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	if msg := passwordPolicy(req.Body.NewPassword); msg != "" {
		return SetPassword400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", msg))}, nil
	}
	self := req.UserId == p.User.ID
	if !self && !p.IsAdmin() {
		return SetPassword403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	// Changing your own password always proves possession of the current
	// one, administrators included; admin privilege only waives it for
	// other accounts.
	if self {
		current := deref(req.Body.CurrentPassword)
		verified, err := s.svc.VerifyLocalLogin(ctx, p.User.Username, current)
		if err != nil {
			return nil, err
		}
		hasPassword := p.User.PasswordHash != ""
		if hasPassword && (current == "" || verified == nil) {
			return SetPassword403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "wrong current password"))}, nil
		}
	}
	if err := s.svc.SetAccountPassword(ctx, req.UserId, req.Body.NewPassword); err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return SetPassword404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no user with id "+req.UserId))}, nil
		}
		return nil, err
	}
	// Self-change spares the session making the request; an admin reset
	// of another account revokes every one of its sessions.
	keep := ""
	if self {
		keep = p.Session.ID
	}
	if err := s.sessions.RevokeAllForUser(ctx, req.UserId, keep); err != nil {
		return nil, err
	}
	return SetPassword204Response{}, nil
}

// --- prefs -------------------------------------------------------------------------

func (s *Server) GetPrefs(ctx context.Context, _ GetPrefsRequestObject) (GetPrefsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	p, err := s.svc.Prefs(ctx, uc)
	if err != nil {
		return nil, err
	}
	return GetPrefs200JSONResponse(prefsJSON(p)), nil
}

func (s *Server) PutPrefs(ctx context.Context, req PutPrefsRequestObject) (PutPrefsResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return PutPrefs400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	in := service.Prefs{
		Timezone: deref(req.Body.Timezone),
		Locale:   deref(req.Body.Locale),
	}
	if req.Body.Theme != nil {
		in.Theme = string(*req.Body.Theme)
	}
	stored, err := s.svc.PutPrefs(ctx, uc, in)
	if err != nil {
		if service.KindOf(err) == service.KindInvalid {
			return PutPrefs400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return PutPrefs200JSONResponse(prefsJSON(stored)), nil
}

func prefsJSON(p service.Prefs) Prefs {
	out := Prefs{}
	if p.Timezone != "" {
		out.Timezone = ptr(p.Timezone)
	}
	if p.Locale != "" {
		out.Locale = ptr(p.Locale)
	}
	if p.Theme != "" {
		theme := PrefsTheme(p.Theme)
		out.Theme = &theme
	}
	return out
}

// --- libraries ---------------------------------------------------------------------

func (s *Server) ListLibraries(ctx context.Context, _ ListLibrariesRequestObject) (ListLibrariesResponseObject, error) {
	p, ok := principalFromContext(ctx)
	if !ok || !p.IsAdmin() {
		return ListLibraries403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	libs, err := s.svc.Libraries(ctx)
	if err != nil {
		return nil, err
	}
	out := Libraries{Libraries: make([]Library, 0, len(libs))}
	for _, lib := range libs {
		item := Library{Pid: lib.PID, Name: lib.Name}
		if lib.Media != "" {
			item.Media = ptr(lib.Media)
		}
		out.Libraries = append(out.Libraries, item)
	}
	return ListLibraries200JSONResponse(out), nil
}

// --- stars & ratings ---------------------------------------------------------------

func (s *Server) SetStar(ctx context.Context, req SetStarRequestObject) (SetStarResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return SetStar400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	st, err := s.svc.SetStar(ctx, uc, req.Pid, req.Body.Starred, req.Body.RecordedAt)
	if err != nil {
		if service.KindOf(err) == service.KindNotFound {
			return SetStar404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		}
		return nil, err
	}
	return SetStar200JSONResponse(playStateJSON(st)), nil
}

func (s *Server) SetRating(ctx context.Context, req SetRatingRequestObject) (SetRatingResponseObject, error) {
	uc, _, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if req.Body == nil {
		return SetRating400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", "a body is required"))}, nil
	}
	st, err := s.svc.SetRating(ctx, uc, req.Pid, req.Body.Rating, req.Body.RecordedAt)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound:
			return SetRating404JSONResponse{NotFoundJSONResponse(errObj("not-found", "no item with pid "+req.Pid))}, nil
		case service.KindInvalid:
			return SetRating400JSONResponse{InvalidRequestJSONResponse(errObj("invalid-request", err.Error()))}, nil
		}
		return nil, err
	}
	return SetRating200JSONResponse(playStateJSON(st)), nil
}

// --- conversion helpers ------------------------------------------------------------

func userAccountJSON(acct service.Account) UserAccount {
	u := acct.User
	out := UserAccount{
		Id:            u.ID,
		Username:      u.Username,
		Roles:         u.Roles,
		Disabled:      u.Disabled,
		CreatedAt:     u.CreatedAt,
		UploadEnabled: u.UploadEnabled,
		LibraryAccess: LibraryAccess{
			Mode: LibraryAccessMode(u.LibraryAccess),
		},
	}
	if u.UploadQuotaBytes > 0 {
		out.UploadQuotaBytes = ptr(u.UploadQuotaBytes)
	}
	if u.DisplayName != "" {
		out.DisplayName = ptr(u.DisplayName)
	}
	out.HasPassword = ptr(u.PasswordHash != "")
	if u.LibraryAccess == "granted" {
		pids := acct.LibraryPIDs
		if pids == nil {
			pids = []string{}
		}
		out.LibraryAccess.LibraryPids = &pids
	}
	if len(acct.Identities) > 0 {
		idents := make([]LinkedIdentity, 0, len(acct.Identities))
		for _, ident := range acct.Identities {
			li := LinkedIdentity{Provider: ident.Provider}
			if ident.Email != "" {
				li.Email = ptr(ident.Email)
			}
			idents = append(idents, li)
		}
		out.Identities = &idents
	}
	return out
}

// passwordPolicy enforces the spec's password floor; the generated
// binding does not enforce minLength.
func passwordPolicy(pw string) string {
	if len(pw) < 8 {
		return "password must be at least 8 characters"
	}
	if len(pw) > 1024 {
		return "password must be at most 1024 characters"
	}
	return ""
}

func roleStrings(roles *[]Role) []string {
	if roles == nil {
		return nil
	}
	out := make([]string, 0, len(*roles))
	for _, r := range *roles {
		out = append(out, string(r))
	}
	return out
}
