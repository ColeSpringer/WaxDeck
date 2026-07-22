package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// SignupState is what a registration produced: pending awaits approval,
// active (invited) can log in immediately.
type SignupState string

const (
	SignupPending SignupState = "pending"
	SignupActive  SignupState = "active"
)

// InviteDTO is one invite for the admin surface; Token is set only on
// the create response.
type InviteDTO struct {
	ID               string
	Token            string
	Note             string
	Roles            []string
	AccessMode       string
	LibraryPIDs      []string
	Permissions      *Permissions
	UploadEnabled    bool
	UploadQuotaBytes int64
	MaxUses          int
	UsedCount        int
	Revoked          bool
	ExpiresAtNS      int64
	CreatedBy        string
	CreatedAtNS      int64
}

// InviteCreate is a new invite; absent fields use the registration
// defaults (the user role, access to every library, default
// permissions, one use, no expiry).
type InviteCreate struct {
	Note             string
	Roles            []string
	AccessMode       string
	LibraryPIDs      []string
	Permissions      *Permissions
	UploadEnabled    bool
	UploadQuotaBytes int64
	MaxUses          int
	ExpiresAtNS      int64
}

// SignupApproval is what an approved account becomes; nil and empty
// fields keep the registration defaults.
type SignupApproval struct {
	Roles            []string
	AccessMode       string
	LibraryPIDs      []string
	Permissions      *Permissions
	UploadEnabled    *bool
	UploadQuotaBytes *int64
}

// settingSignupEnabled is the settings key for open self-serve signup.
const settingSignupEnabled = "signup:enabled"

// SignupEnabled reports whether open self-serve registration is on.
// Invites work regardless.
func (l *Library) SignupEnabled(ctx context.Context) bool {
	v, err := l.db.SettingGet(ctx, settingSignupEnabled)
	return err == nil && v == "true"
}

// Signup handles self-serve registration. Without a token it requires
// open signup and lands a pending account; with a valid invite token
// the account activates immediately with the invite's shape. Invalid
// tokens of every flavor answer the same forbidden, so the endpoint
// never confirms whether a token exists.
func (l *Library) Signup(ctx context.Context, username, password, displayName, inviteToken string) (*Account, SignupState, error) {
	if password == "" {
		return nil, "", errInvalid("password is required")
	}
	// Pasted tokens routinely arrive with a stray newline or space;
	// trimming beats telling the user their valid invite is invalid.
	inviteToken = strings.TrimSpace(inviteToken)
	if inviteToken == "" {
		if !l.SignupEnabled(ctx) {
			return nil, "", &Error{Kind: KindForbidden, Msg: "self-serve signup is disabled on this server"}
		}
		acct, err := l.CreateAccount(ctx, AccountCreate{
			Username:    username,
			Password:    password,
			DisplayName: displayName,
			Pending:     true,
		})
		if err != nil {
			return nil, "", err
		}
		l.notifyAdminsOfSignup(ctx, acct)
		return acct, SignupPending, nil
	}

	// The username pre-check runs before the invite is consumed so the
	// common refusal (a taken name) never touches the use count; the
	// guarded consume below still owns the admission race. A crash
	// between consume and create can strand one use — accepted: account
	// creation spans both databases (ADR-0003 rules out one transaction)
	// and the recovery is an administrator re-issuing an invite.
	if _, err := l.db.UserByUsername(ctx, strings.TrimSpace(username)); err == nil {
		return nil, "", &Error{Kind: KindConflict, Msg: "username is taken"}
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	sum := sha256.Sum256([]byte(inviteToken))
	iv, err := l.db.ConsumeInvite(ctx, sum[:])
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, "", &Error{Kind: KindForbidden, Msg: "this invite is not valid"}
		}
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	in := AccountCreate{
		Username:         username,
		Password:         password,
		DisplayName:      displayName,
		Roles:            iv.Roles,
		AccessMode:       iv.LibraryAccess,
		UploadEnabled:    iv.UploadEnabled,
		UploadQuotaBytes: iv.UploadQuotaBytes,
	}
	if iv.LibraryAccess == "granted" {
		var grants []string
		if err := json.Unmarshal([]byte(iv.LibraryGrants), &grants); err == nil {
			for _, g := range grants {
				in.LibraryPIDs = append(in.LibraryPIDs, PrefixLibrary+"-"+g)
			}
		}
	}
	if iv.Perms != "" {
		var p Permissions
		if err := json.Unmarshal([]byte(iv.Perms), &p); err == nil {
			in.Permissions = &p
		}
	}
	acct, err := l.CreateAccount(ctx, in)
	if err != nil {
		// The claimed use goes back so a typo'd username does not burn
		// the invite.
		l.db.UnconsumeInvite(ctx, iv.ID)
		return nil, "", err
	}
	l.Audit(ctx, nil, "user.signup", AuditTarget{Kind: "user", PID: acct.User.ID, Name: acct.User.Username},
		map[string]any{"invite": iv.ID, "inviteNote": iv.Note})
	return acct, SignupActive, nil
}

// notifyAdminsOfSignup announces a new pending registration.
func (l *Library) notifyAdminsOfSignup(ctx context.Context, acct *Account) {
	admins, err := l.db.EnabledAdminIDs(ctx)
	if err != nil {
		l.log.Warn("listing admins for signup notification", "err", err)
		admins = nil
	}
	l.EmitNotification(ctx, "signup-requested",
		"New account request",
		acct.User.Username+" requested an account and is waiting for approval.",
		admins)
	l.Audit(ctx, nil, "user.request", AuditTarget{Kind: "user", PID: acct.User.ID, Name: acct.User.Username}, nil)
}

// PendingAccounts pages pending registrations, oldest first. The cursor
// is the previous page's last (createdNS, id) pair.
func (l *Library) PendingAccounts(ctx context.Context, cursor string, limit int) (AccountPage, error) {
	var afterNS int64
	var afterID string
	if cursor != "" {
		ns, id, ok := strings.Cut(cursor, "|")
		if !ok {
			return AccountPage{}, errInvalid("bad cursor")
		}
		parsed, err := strconv.ParseInt(ns, 10, 64)
		if err != nil {
			return AccountPage{}, errInvalid("bad cursor")
		}
		afterNS, afterID = parsed, id
	}
	users, err := l.db.ListPendingUsers(ctx, afterNS, afterID, limit+1)
	if err != nil {
		return AccountPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page := AccountPage{}
	more := len(users) > limit
	if more {
		users = users[:limit]
	}
	for _, u := range users {
		acct, err := l.accountFor(ctx, u)
		if err != nil {
			return AccountPage{}, err
		}
		page.Accounts = append(page.Accounts, *acct)
	}
	if more && len(users) > 0 {
		last := users[len(users)-1]
		page.Next = strconv.FormatInt(last.CreatedAt.UnixNano(), 10) + "|" + last.ID
	}
	return page, nil
}

// ApproveSignup activates a pending account, assigning its shape in the
// same step. A user that is not pending conflicts.
func (l *Library) ApproveSignup(ctx context.Context, actor *UserCtx, userID string, ap SignupApproval) (*Account, error) {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, errNotFound("no user with id " + userID)
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if !u.Pending {
		return nil, &Error{Kind: KindConflict, Msg: "this account is not a pending request"}
	}
	upd := AccountUpdate{Roles: ap.Roles, Permissions: ap.Permissions,
		UploadEnabled: ap.UploadEnabled, UploadQuotaBytes: ap.UploadQuotaBytes}
	if ap.AccessMode != "" {
		upd.AccessMode = &ap.AccessMode
		upd.LibraryPIDs = ap.LibraryPIDs
	}
	if _, err := l.UpdateAccount(ctx, userID, upd); err != nil {
		return nil, err
	}
	u, err = l.db.UserByID(ctx, userID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	u.Pending = false
	if err := l.db.UpdateUser(ctx, u, false); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, actor, "user.approve", AuditTarget{Kind: "user", PID: u.ID, Name: u.Username}, nil)
	return l.accountFor(ctx, u)
}

// RejectSignup deletes a pending account; reject never deletes an
// active one.
func (l *Library) RejectSignup(ctx context.Context, actor *UserCtx, userID string) error {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no user with id " + userID)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	if !u.Pending {
		return &Error{Kind: KindConflict, Msg: "this account is not a pending request"}
	}
	if err := l.db.DeleteUser(ctx, userID, false); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, actor, "user.reject", AuditTarget{Kind: "user", PID: u.ID, Name: u.Username}, nil)
	return nil
}

// CreateInvite mints an invite token. The token appears only in the
// returned DTO; the row stores its hash.
func (l *Library) CreateInvite(ctx context.Context, actor *UserCtx, in InviteCreate) (InviteDTO, error) {
	roles, err := normalizeRoles(in.Roles)
	if err != nil {
		return InviteDTO{}, err
	}
	mode, grants, err := normalizeAccess(in.AccessMode, in.LibraryPIDs)
	if err != nil {
		return InviteDTO{}, err
	}
	if in.MaxUses < 0 {
		return InviteDTO{}, errInvalid("maxUses must not be negative")
	}
	if in.ExpiresAtNS != 0 && in.ExpiresAtNS < time.Now().UnixNano() {
		return InviteDTO{}, errInvalid("expiresAt is in the past")
	}
	perms := ""
	if in.Permissions != nil {
		if err := validatePermissions(*in.Permissions); err != nil {
			return InviteDTO{}, err
		}
		raw, err := json.Marshal(in.Permissions)
		if err != nil {
			return InviteDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		perms = string(raw)
	}
	grantsJSON, err := json.Marshal(grants)
	if err != nil {
		return InviteDTO{}, &Error{Kind: KindInternal, Err: err}
	}

	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return InviteDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	token := "wxi_" + base64.RawURLEncoding.EncodeToString(raw)
	sum := sha256.Sum256([]byte(token))

	iv := wdb.Invite{
		ID:               PrefixInvite + "-" + ulid.Make().String(),
		TokenHash:        sum[:],
		Note:             strings.TrimSpace(in.Note),
		Roles:            roles,
		LibraryAccess:    mode,
		LibraryGrants:    string(grantsJSON),
		Perms:            perms,
		UploadEnabled:    in.UploadEnabled,
		UploadQuotaBytes: in.UploadQuotaBytes,
		MaxUses:          in.MaxUses,
		ExpiresAtNS:      in.ExpiresAtNS,
		CreatedBy:        l.usernameOf(ctx, actorName(actor)),
		CreatedAtNS:      time.Now().UnixNano(),
	}
	if err := l.db.InsertInvite(ctx, iv); err != nil {
		return InviteDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, actor, "invite.create", AuditTarget{Kind: "invite", PID: iv.ID, Name: iv.Note},
		map[string]any{"roles": roles, "maxUses": in.MaxUses})
	out := l.inviteDTO(iv)
	out.Token = token
	return out, nil
}

// Invites lists every invite, newest first, without tokens.
func (l *Library) Invites(ctx context.Context) ([]InviteDTO, error) {
	rows, err := l.db.ListInvites(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]InviteDTO, 0, len(rows))
	for _, iv := range rows {
		out = append(out, l.inviteDTO(iv))
	}
	return out, nil
}

// RevokeInvite stops an invite's token from working; admitted accounts
// are unaffected.
func (l *Library) RevokeInvite(ctx context.Context, actor *UserCtx, id string) error {
	if err := l.db.RevokeInvite(ctx, id); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no invite with id " + id)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, actor, "invite.revoke", AuditTarget{Kind: "invite", PID: id}, nil)
	return nil
}

func (l *Library) inviteDTO(iv wdb.Invite) InviteDTO {
	out := InviteDTO{
		ID:               iv.ID,
		Note:             iv.Note,
		Roles:            iv.Roles,
		AccessMode:       iv.LibraryAccess,
		UploadEnabled:    iv.UploadEnabled,
		UploadQuotaBytes: iv.UploadQuotaBytes,
		MaxUses:          iv.MaxUses,
		UsedCount:        iv.UsedCount,
		Revoked:          iv.Revoked,
		ExpiresAtNS:      iv.ExpiresAtNS,
		CreatedBy:        iv.CreatedBy,
		CreatedAtNS:      iv.CreatedAtNS,
	}
	if iv.LibraryAccess == "granted" {
		var grants []string
		if err := json.Unmarshal([]byte(iv.LibraryGrants), &grants); err == nil {
			for _, g := range grants {
				out.LibraryPIDs = append(out.LibraryPIDs, PrefixLibrary+"-"+g)
			}
		}
	}
	if iv.Perms != "" {
		var p Permissions
		if err := json.Unmarshal([]byte(iv.Perms), &p); err == nil {
			out.Permissions = &p
		}
	}
	return out
}
