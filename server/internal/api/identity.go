package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"unicode/utf8"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// --- bootstrap ---------------------------------------------------------------------

func (s *Server) GetBootstrapStatus(ctx context.Context, _ GetBootstrapStatusRequestObject) (GetBootstrapStatusResponseObject, error) {
	required, err := s.svc.BootstrapRequired(ctx)
	if err != nil {
		return nil, err
	}
	return GetBootstrapStatus200JSONResponse{
		Required:      required,
		SignupEnabled: ptr(s.svc.SignupEnabled(ctx)),
	}, nil
}

func (s *Server) Bootstrap(ctx context.Context, req BootstrapRequestObject) (BootstrapResponseObject, error) {
	if req.Body == nil {
		return nil, errNoBody()
	}
	if msg := passwordPolicy(req.Body.Password); msg != "" {
		return nil, refuse(http.StatusBadRequest, "invalid-request", msg)
	}
	acct, err := s.svc.Bootstrap(ctx, req.Body.Username, req.Body.Password, deref(req.Body.DisplayName))
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return nil, refuse(http.StatusConflict, "conflict", "the server already has accounts")
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
	p, _ := principalFromContext(ctx)
	if p.FromCookie {
		return nil, refuse(http.StatusBadRequest, "invalid-request", "cookie sessions have no bearer token to rotate")
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
	p, _ := principalFromContext(ctx)
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

// maxDeviceNameRunes is the device-name cap the spec declares, counted
// in characters. Runes and not bytes: the spec's maxLength counts
// characters, and device names are where emoji turn up.
const maxDeviceNameRunes = 128

// deviceNameFor trims a supplied device label and reports whether it is
// storable. Empty after trimming is not, since there is no way to spell
// "clear this label" and a blank row in a device list reads as a bug.
//
// The generated server does not enforce minLength or maxLength, so this
// is where the declared constraints become real - and the length one is
// measured on the value as sent, before the trim, because that is what
// the schema declares it on. Measuring the trimmed value instead would
// accept a 130-character name with two trailing spaces that a validating
// proxy or a generated client had already rejected, so the two would
// disagree about what is acceptable.
func deviceNameFor(raw string) (string, bool) {
	if utf8.RuneCountInString(raw) > maxDeviceNameRunes {
		return "", false
	}
	name := strings.TrimSpace(raw)
	if name == "" {
		return "", false
	}
	return name, true
}

// truncatedDeviceName is deviceNameFor for a login, which must never be
// refused over a label: an over-long or blank name is stored trimmed and
// cut to the cap rather than turned into a failed sign-in. Renaming is
// an explicit act and refuses instead, which is the whole difference.
func truncatedDeviceName(raw string) string {
	name := strings.TrimSpace(raw)
	if utf8.RuneCountInString(name) > maxDeviceNameRunes {
		name = string([]rune(name)[:maxDeviceNameRunes])
	}
	return name
}

func (s *Server) RenameSession(ctx context.Context, req RenameSessionRequestObject) (RenameSessionResponseObject, error) {
	p, _ := principalFromContext(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	name, ok := deviceNameFor(req.Body.DeviceName)
	if !ok {
		return nil, refuse(http.StatusBadRequest, "invalid-request",
			"deviceName must be 1 to 128 characters after trimming")
	}
	target, err := s.sessions.Get(ctx, req.SessionId)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, refuse(http.StatusNotFound, "not-found", "no session with id "+req.SessionId)
		}
		return nil, err
	}
	// A foreign session is indistinguishable from a missing one.
	if target.UserID != p.User.ID {
		return nil, refuse(http.StatusNotFound, "not-found", "no session with id "+req.SessionId)
	}
	if err := s.sessions.Rename(ctx, target.ID, name); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, refuse(http.StatusNotFound, "not-found", "no session with id "+req.SessionId)
		}
		return nil, err
	}
	target.DeviceName = name
	return RenameSession200JSONResponse(deviceSessionJSON(target, target.ID == p.Session.ID)), nil
}

func (s *Server) RevokeSession(ctx context.Context, req RevokeSessionRequestObject) (RevokeSessionResponseObject, error) {
	p, _ := principalFromContext(ctx)
	target, err := s.sessions.Get(ctx, req.SessionId)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, refuse(http.StatusNotFound, "not-found", "no session with id "+req.SessionId)
		}
		return nil, err
	}
	// A foreign session is indistinguishable from a missing one.
	if target.UserID != p.User.ID {
		return nil, refuse(http.StatusNotFound, "not-found", "no session with id "+req.SessionId)
	}
	if err := s.endSessions(ctx, p.User.ID, target.ID, ""); err != nil {
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
	p, _ := principalFromContext(ctx)
	if req.UserId != p.User.ID && !p.IsAdmin() {
		return nil, refuse(http.StatusForbidden, "forbidden", "administrators only")
	}
	acct, err := s.svc.Account(ctx, req.UserId)
	if err != nil {
		return nil, err
	}
	self := req.UserId == p.User.ID
	keep := ""
	if self {
		keep = p.Session.ID
	}
	if err := s.endSessions(ctx, req.UserId, "", keep); err != nil {
		return nil, err
	}
	// Signing an account out everywhere is a deliberate act on every
	// device it holds, so it is on the record whoever asked - once the
	// sessions are gone, whatever the gpodder half below answers.
	s.svc.Audit(ctx, userCtx(ctx), "user.sessions-revoke",
		service.AuditTarget{Kind: "user", PID: acct.User.ID, Name: acct.User.Username},
		map[string]any{"self": self, "kept": keep != ""})
	// Everywhere includes the podcast clients signed in over gpodder; a
	// failure here is reported so the caller tries again.
	if err := s.svc.EndGpodderSessions(ctx, req.UserId); err != nil {
		return nil, err
	}
	return RevokeUserSessions204Response{}, nil
}

// endSessions ends sessions through the session manager, so its revoke
// feed closes what they opened (a socket) with them: one session when
// sessionID is set, otherwise every session of userID but keepID.
func (s *Server) endSessions(ctx context.Context, userID, sessionID, keepID string) error {
	if sessionID != "" {
		return s.sessions.Revoke(ctx, sessionID)
	}
	return s.sessions.RevokeAllForUser(ctx, userID, keepID)
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
	// Summarized on the way out as well as on the way in, so a session
	// stored before this server learned to do it reads the same as one
	// stored after. Idempotent by construction: a summary carries no
	// browser token, so it falls through unchanged.
	if client := summarizeClient(row.Client); client != "" {
		out.Client = ptr(client)
	}
	if !row.LastSeenAt.IsZero() {
		out.LastSeenAt = ptr(row.LastSeenAt)
	}
	return out
}

// --- user administration -----------------------------------------------------------

func (s *Server) ListUsers(ctx context.Context, req ListUsersRequestObject) (ListUsersResponseObject, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}
	limit, err := pageLimit(req.Params.Limit, 100, 500)
	if err != nil {
		return nil, err
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
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}
	if req.Body == nil {
		return nil, errNoBody()
	}
	if msg := passwordPolicy(req.Body.Password); msg != "" {
		return nil, refuse(http.StatusBadRequest, "invalid-request", msg)
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
	if req.Body.Permissions != nil {
		perms := permissionsFromGen(*req.Body.Permissions)
		in.Permissions = &perms
	}
	acct, err := s.svc.CreateAccount(ctx, in)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return nil, refuse(http.StatusConflict, "conflict", "username is taken")
		}
		return nil, err
	}
	s.svc.Audit(ctx, userCtx(ctx), "user.create",
		service.AuditTarget{Kind: "user", PID: acct.User.ID, Name: acct.User.Username},
		map[string]any{"roles": acct.User.Roles})
	return CreateUser201JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) GetUser(ctx context.Context, req GetUserRequestObject) (GetUserResponseObject, error) {
	p, _ := principalFromContext(ctx)
	if req.UserId != p.User.ID && !p.IsAdmin() {
		return nil, refuse(http.StatusForbidden, "forbidden", "administrators only")
	}
	acct, err := s.svc.Account(ctx, req.UserId)
	if err != nil {
		return nil, err
	}
	return GetUser200JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) UpdateUser(ctx context.Context, req UpdateUserRequestObject) (UpdateUserResponseObject, error) {
	p, _ := principalFromContext(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	admin := p.IsAdmin()
	if req.UserId != p.User.ID && !admin {
		return nil, refuse(http.StatusForbidden, "forbidden", "administrators only")
	}
	// Non-administrators may change only their own display name; any
	// other supplied field is rejected loudly, never silently ignored.
	if !admin && (req.Body.Roles != nil || req.Body.Disabled != nil || req.Body.LibraryAccess != nil ||
		req.Body.UploadEnabled != nil || req.Body.UploadQuotaBytes != nil || req.Body.Permissions != nil) {
		return nil, refuse(http.StatusForbidden, "forbidden", "only displayName may be changed on your own account")
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
	if req.Body.Permissions != nil {
		perms := permissionsFromGen(*req.Body.Permissions)
		upd.Permissions = &perms
	}
	// Self displayName edits are routine, not audit-worthy; anything an
	// administrator can change on another account is. Read before the write
	// so the entry can say from what.
	//
	// A read that fails refuses the edit: going ahead would change an
	// account and leave nothing on the record. An account that is not
	// there is the update's own answer.
	var before *service.Account
	if admin && (req.UserId != p.User.ID || req.Body.Roles != nil || req.Body.Disabled != nil ||
		req.Body.LibraryAccess != nil || req.Body.Permissions != nil ||
		req.Body.UploadEnabled != nil || req.Body.UploadQuotaBytes != nil) {
		read, err := s.svc.Account(ctx, req.UserId)
		switch {
		case err == nil:
			before = read
		case service.KindOf(err) != service.KindNotFound:
			return nil, err
		}
	}
	acct, err := s.svc.UpdateAccount(ctx, req.UserId, upd)
	if err != nil {
		return nil, err
	}
	// Disabling ends the account's sessions and gpodder logins at once.
	// The account is disabled whatever this answers, but a session or
	// login a failed revoke left would sign straight back in on a
	// re-enable, so the failure is reported (after the audit entry, since
	// the update happened) and a retry finishes the revoke.
	var revokeErr error
	if req.Body.Disabled != nil && *req.Body.Disabled {
		revokeErr = errors.Join(s.endSessions(ctx, req.UserId, "", ""), s.svc.EndGpodderSessions(ctx, req.UserId))
	}
	if before != nil {
		// A save that changed nothing is not an event.
		if changes := service.AccountChanges(before, acct); len(changes) > 0 {
			s.svc.Audit(ctx, userCtx(ctx), "user.update",
				service.AuditTarget{Kind: "user", PID: acct.User.ID, Name: acct.User.Username},
				map[string]any{"changes": changes})
		}
	}
	if revokeErr != nil {
		return nil, fmt.Errorf("revoking a disabled account's sessions: %w", revokeErr)
	}
	return UpdateUser200JSONResponse(userAccountJSON(*acct)), nil
}

func (s *Server) DeleteUser(ctx context.Context, req DeleteUserRequestObject) (DeleteUserResponseObject, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}
	p, _ := principalFromContext(ctx)
	if req.UserId == p.User.ID {
		return nil, refuse(http.StatusConflict, "conflict", "you cannot delete the account you are signed in as")
	}
	uc := userCtx(ctx)
	opts := service.AccountDeletion{TransferTo: deref(req.Params.TransferTo)}
	if req.Params.Playlists != nil {
		opts.Playlists = string(*req.Params.Playlists)
	}
	victim, verr := s.svc.Account(ctx, req.UserId)
	deleted, err := s.svc.DeleteAccount(ctx, uc, req.UserId, opts)
	// A deletion that disabled the account is a disable whatever else it
	// did: its sessions and gpodder logins end now, or they would sign
	// straight back in if the account is enabled again. A request that has
	// gone away does not stop that, or the record of what was done.
	bg := context.WithoutCancel(ctx)
	if err != nil && deleted.Disabled {
		if rerr := errors.Join(s.endSessions(bg, req.UserId, "", ""), s.svc.EndGpodderSessions(bg, req.UserId)); rerr != nil {
			s.log.Warn("ending the sessions of an account whose deletion stopped", "user", req.UserId, "err", rerr)
		}
	}
	if verr == nil && (err == nil || deleted.Changed()) {
		auditCtx := ctx
		if err != nil {
			// What was done before the deletion stopped is on the record
			// too, so the retry's entry is not read as the whole of it.
			auditCtx = bg
		}
		s.svc.Audit(auditCtx, uc, "user.delete",
			service.AuditTarget{Kind: "user", PID: victim.User.ID, Name: victim.User.Username},
			userDeleteDetail(deleted, err))
	}
	if err != nil {
		return nil, err
	}
	// The rows went with the account (a cascade nothing announces); this
	// is what closes the sockets they opened.
	if err := s.endSessions(ctx, req.UserId, "", ""); err != nil {
		s.log.Warn("ending a deleted account's sessions", "user", req.UserId, "err", err)
	}
	return DeleteUser204Response{}, nil
}

// userDeleteDetail is what a `user.delete` entry records: what was handed
// over and what deleted, what became of the fixed copies an earlier attempt
// left, how many public links ended with the account, and, for a deletion
// that stopped, that it did, whether it left the account disabled, and why.
func userDeleteDetail(deleted service.AccountDeleted, err error) map[string]any {
	detail := map[string]any{
		"playlistsTransferred": deleted.PlaylistsTransferred,
		"playlistsDeleted":     deleted.PlaylistsDeleted,
	}
	if deleted.PlaylistsFixed > 0 {
		detail["playlistsFixed"] = deleted.PlaylistsFixed
	}
	if deleted.TransferredTo != "" {
		detail["transferredTo"] = deleted.TransferredTo
	}
	// What became of the fixed copies an earlier attempt left, which its own
	// entry named when it failed.
	if len(deleted.FixedCopiesRemoved) > 0 {
		detail["fixedCopiesRemoved"] = deleted.FixedCopiesRemoved
	}
	if len(deleted.FixedCopiesKept) > 0 {
		detail["fixedCopiesKept"] = deleted.FixedCopiesKept
	}
	if err == nil {
		// What ended with the account, which a deletion that stopped has
		// not yet ended.
		detail["linksEnded"] = deleted.LinksEnded
	}
	if err != nil {
		detail["failed"] = true
		detail["accountDisabled"] = deleted.Disabled
		// The sentence of a refusal is written for the person reading it;
		// an internal fault's text can carry paths and queries.
		detail["error"] = "internal error"
		if service.KindOf(err) != service.KindInternal {
			detail["error"] = serviceMessage(err)
		}
		// A copy of a playlist that the failure could not take back stays
		// in the catalog until the next attempt takes it up.
		var left leftCopier
		if errors.As(err, &left) {
			detail["fixedCopyLeft"] = left.LeftCopy()
		}
	}
	return detail
}

// leftCopier is what an error says when it left a fixed copy of a
// playlist in the catalog.
type leftCopier interface{ LeftCopy() string }

func (s *Server) SetPassword(ctx context.Context, req SetPasswordRequestObject) (SetPasswordResponseObject, error) {
	p, _ := principalFromContext(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	if msg := passwordPolicy(req.Body.NewPassword); msg != "" {
		return nil, refuse(http.StatusBadRequest, "invalid-request", msg)
	}
	self := req.UserId == p.User.ID
	if !self && !p.IsAdmin() {
		return nil, refuse(http.StatusForbidden, "forbidden", "administrators only")
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
			return nil, refuse(http.StatusForbidden, "forbidden", "wrong current password")
		}
	}
	if err := s.svc.SetAccountPassword(ctx, req.UserId, req.Body.NewPassword); err != nil {
		return nil, err
	}
	// Self-change spares the session making the request; an admin reset
	// of another account revokes every one of its sessions.
	keep := ""
	if self {
		keep = p.Session.ID
	}
	if err := s.endSessions(ctx, req.UserId, "", keep); err != nil {
		return nil, err
	}
	if !self {
		target := service.AuditTarget{Kind: "user", PID: req.UserId}
		if acct, err := s.svc.Account(ctx, req.UserId); err == nil {
			target.Name = acct.User.Username
		}
		s.svc.Audit(ctx, userCtx(ctx), "user.password-reset", target, nil)
	}
	return SetPassword204Response{}, nil
}

// --- prefs -------------------------------------------------------------------------

func (s *Server) GetPrefs(ctx context.Context, _ GetPrefsRequestObject) (GetPrefsResponseObject, error) {
	uc := userCtx(ctx)
	p, err := s.svc.Prefs(ctx, uc)
	if err != nil {
		return nil, err
	}
	return GetPrefs200JSONResponse(prefsJSON(p)), nil
}

func (s *Server) PutPrefs(ctx context.Context, req PutPrefsRequestObject) (PutPrefsResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	in := service.Prefs{
		Timezone:            deref(req.Body.Timezone),
		Locale:              deref(req.Body.Locale),
		SharedStatsOptOut:   derefBool(req.Body.SharedStatsOptOut),
		CrossfadeSeconds:    derefFloat(req.Body.CrossfadeSeconds),
		ReplayGain:          derefBool(req.Body.ReplayGain),
		RadioScrobbleOptOut: derefBool(req.Body.RadioScrobbleOptOut),
		IdentifyOptOut:      derefBool(req.Body.IdentifyOptOut),
		// Pointers, not flattened: absent and false differ, and the
		// document is replaced whole.
		BrowseShowUnknown: req.Body.BrowseShowUnknown,
		Autoplay:          req.Body.Autoplay,
	}
	if req.Body.Theme != nil {
		in.Theme = string(*req.Body.Theme)
	}
	if req.Body.RadioFavorites != nil {
		in.RadioFavorites = *req.Body.RadioFavorites
	}
	if req.Body.RadioScrobbleMutedStations != nil {
		in.RadioScrobbleMutedStations = *req.Body.RadioScrobbleMutedStations
	}
	if req.Body.Pinned != nil {
		in.Pinned = *req.Body.Pinned
	}
	if req.Body.BrowseSorts != nil {
		in.BrowseSorts = *req.Body.BrowseSorts
	}
	stored, err := s.svc.PutPrefs(ctx, uc, in)
	if err != nil {
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
	if p.SharedStatsOptOut {
		out.SharedStatsOptOut = ptr(true)
	}
	if len(p.RadioFavorites) > 0 {
		out.RadioFavorites = &p.RadioFavorites
	}
	if len(p.RadioScrobbleMutedStations) > 0 {
		out.RadioScrobbleMutedStations = &p.RadioScrobbleMutedStations
	}
	if len(p.Pinned) > 0 {
		out.Pinned = &p.Pinned
	}
	if p.CrossfadeSeconds > 0 {
		out.CrossfadeSeconds = ptr(p.CrossfadeSeconds)
	}
	if p.ReplayGain {
		out.ReplayGain = ptr(true)
	}
	if p.RadioScrobbleOptOut {
		out.RadioScrobbleOptOut = ptr(true)
	}
	if p.IdentifyOptOut {
		out.IdentifyOptOut = ptr(true)
	}
	out.BrowseShowUnknown = p.BrowseShowUnknown
	out.Autoplay = p.Autoplay
	if len(p.BrowseSorts) > 0 {
		out.BrowseSorts = &p.BrowseSorts
	}
	return out
}

// --- libraries ---------------------------------------------------------------------

func (s *Server) ListLibraries(ctx context.Context, req ListLibrariesRequestObject) (ListLibrariesResponseObject, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}
	// A count per library, taken only where it was asked for.
	libs, err := s.svc.Libraries(ctx)
	if derefBool(req.Params.Counts) {
		libs, err = s.svc.LibrariesWithCounts(ctx)
	}
	if err != nil {
		return nil, err
	}
	out := Libraries{Libraries: make([]Library, 0, len(libs))}
	for _, lib := range libs {
		out.Libraries = append(out.Libraries, libraryDTO(lib))
	}
	return ListLibraries200JSONResponse(out), nil
}

// --- stars & ratings ---------------------------------------------------------------

func (s *Server) SetStar(ctx context.Context, req SetStarRequestObject) (SetStarResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetStar(ctx, uc, req.Pid, req.Body.Starred, req.Body.RecordedAt)
	if err != nil {
		return nil, err
	}
	return SetStar200JSONResponse(playStateJSON(st)), nil
}

func (s *Server) SetPlayed(ctx context.Context, req SetPlayedRequestObject) (SetPlayedResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetPlayed(ctx, uc, req.Pid,
		req.Body.Played, req.Body.Finished, req.Body.PlayCount, req.Body.PositionMs, req.Body.RecordedAt)
	if err != nil {
		return nil, err
	}
	return SetPlayed200JSONResponse(playStateJSON(st)), nil
}

func (s *Server) SetRating(ctx context.Context, req SetRatingRequestObject) (SetRatingResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetRating(ctx, uc, req.Pid, req.Body.Rating, req.Body.RecordedAt)
	if err != nil {
		return nil, err
	}
	return SetRating200JSONResponse(playStateJSON(st)), nil
}

// --- entity stars & ratings --------------------------------------------------------
//
// Artists and albums carry their own star and rating, independent of
// their members: starring an album does not star its tracks. The four
// write paths and two reads all funnel through one service pair, which
// splits the prefix and authorizes the caller; the per-operation
// wrappers exist only because the generated request and response types
// are per-path.

func entityPlayStateJSON(st service.EntityPlayState) EntityPlayState {
	out := EntityPlayState{
		Pid:     st.PID,
		Starred: st.Starred,
		Rating:  st.Rating,
	}
	if !st.StarredAt.IsZero() {
		out.StarredAt = &st.StarredAt
	}
	if !st.UpdatedAt.IsZero() {
		out.UpdatedAt = &st.UpdatedAt
	}
	return out
}

// entityRouteMiss words a play-state route's not-found in the route's own
// noun: the service sees only the pid, which may name another kind of
// entity or none.
func entityRouteMiss(err error, noun, pid string) error {
	if service.KindOf(err) == service.KindNotFound {
		return refuse(http.StatusNotFound, "not-found", "no "+noun+" with pid "+pid)
	}
	return err
}

func (s *Server) GetArtistPlayState(ctx context.Context, req GetArtistPlayStateRequestObject) (GetArtistPlayStateResponseObject, error) {
	uc := userCtx(ctx)
	st, err := s.svc.EntityPlayStateFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, entityRouteMiss(err, "artist", req.Pid)
	}
	return GetArtistPlayState200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) SetArtistStar(ctx context.Context, req SetArtistStarRequestObject) (SetArtistStarResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetEntityStar(ctx, uc, req.Pid, req.Body.Starred, req.Body.RecordedAt)
	if err != nil {
		return nil, entityRouteMiss(err, "artist", req.Pid)
	}
	return SetArtistStar200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) SetArtistRating(ctx context.Context, req SetArtistRatingRequestObject) (SetArtistRatingResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetEntityRating(ctx, uc, req.Pid, req.Body.Rating, req.Body.RecordedAt)
	if err != nil {
		return nil, entityRouteMiss(err, "artist", req.Pid)
	}
	return SetArtistRating200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) GetAlbumPlayState(ctx context.Context, req GetAlbumPlayStateRequestObject) (GetAlbumPlayStateResponseObject, error) {
	uc := userCtx(ctx)
	st, err := s.svc.EntityPlayStateFor(ctx, uc, req.Pid)
	if err != nil {
		return nil, entityRouteMiss(err, "album", req.Pid)
	}
	return GetAlbumPlayState200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) SetAlbumStar(ctx context.Context, req SetAlbumStarRequestObject) (SetAlbumStarResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetEntityStar(ctx, uc, req.Pid, req.Body.Starred, req.Body.RecordedAt)
	if err != nil {
		return nil, entityRouteMiss(err, "album", req.Pid)
	}
	return SetAlbumStar200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) SetAlbumRating(ctx context.Context, req SetAlbumRatingRequestObject) (SetAlbumRatingResponseObject, error) {
	uc := userCtx(ctx)
	if req.Body == nil {
		return nil, errNoBody()
	}
	st, err := s.svc.SetEntityRating(ctx, uc, req.Pid, req.Body.Rating, req.Body.RecordedAt)
	if err != nil {
		return nil, entityRouteMiss(err, "album", req.Pid)
	}
	return SetAlbumRating200JSONResponse(entityPlayStateJSON(st)), nil
}

func (s *Server) ListStarredEntities(ctx context.Context, _ ListStarredEntitiesRequestObject) (ListStarredEntitiesResponseObject, error) {
	uc := userCtx(ctx)
	res, err := s.svc.StarredEntities(ctx, uc)
	if err != nil {
		return nil, err
	}
	return ListStarredEntities200JSONResponse(StarredEntities{
		Artists: searchHitsJSON(res.Artists),
		Albums:  searchHitsJSON(res.Albums),
	}), nil
}

// --- conversion helpers ------------------------------------------------------------

func userAccountJSON(acct service.Account) UserAccount {
	u := acct.User
	out := UserAccount{
		Id:            u.ID,
		Username:      u.Username,
		Roles:         u.Roles,
		Disabled:      u.Disabled,
		Pending:       u.Pending,
		CreatedAt:     u.CreatedAt,
		UploadEnabled: u.UploadEnabled,
		Permissions:   permissionsJSON(service.PermissionsOf(u)),
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
