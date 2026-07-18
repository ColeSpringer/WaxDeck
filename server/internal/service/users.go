package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Account is one account with its server-side extras: granted library
// PIDs (API-prefixed) and linked identities.
type Account struct {
	User        *wdb.User
	LibraryPIDs []string
	Identities  []wdb.Identity
}

// AccountPage is one keyset page of accounts.
type AccountPage struct {
	Accounts []Account
	Next     string
}

// AccountCreate is the input for a new local account.
type AccountCreate struct {
	Username    string
	Password    string
	DisplayName string
	Roles       []string
	AccessMode  string   // "all" or "granted"
	LibraryPIDs []string // API-prefixed, granted mode
}

// AccountUpdate is a partial account update; nil fields are unchanged.
type AccountUpdate struct {
	DisplayName *string
	Roles       []string
	Disabled    *bool
	AccessMode  *string
	LibraryPIDs []string // meaningful only when AccessMode is set to "granted"
}

// validRoles is the role vocabulary.
var validRoles = map[string]bool{"admin": true, "user": true}

// BootstrapRequired reports whether the server still lacks an enabled
// administrator. Keying on administrators rather than accounts means
// an OIDC login that provisioned a plain account first never closes
// the setup door on an adminless server.
func (l *Library) BootstrapRequired(ctx context.Context) (bool, error) {
	n, err := l.db.CountEnabledAdmins(ctx)
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	return n == 0, nil
}

// Bootstrap creates an administrator while none exists, then the door
// closes forever. The one-shot property lives in the insert itself,
// which is guarded on "no enabled administrator exists" in a single
// atomic statement: two concurrent bootstraps with different usernames
// both pass any separate count, but only one guarded insert applies.
func (l *Library) Bootstrap(ctx context.Context, username, password, displayName string) (*Account, error) {
	acct, err := l.createAccount(ctx, AccountCreate{
		Username:    username,
		Password:    password,
		DisplayName: displayName,
		Roles:       []string{"admin"},
		AccessMode:  "all",
	}, true)
	if err != nil && KindOf(err) == KindConflict {
		// Disambiguate for the caller: the door being closed reads
		// differently from a taken username.
		if required, rerr := l.BootstrapRequired(ctx); rerr == nil && !required {
			return nil, &Error{Kind: KindConflict, Msg: "the server already has an administrator"}
		}
	}
	return acct, err
}

// CreateAccount provisions a local account: a users row plus its catalog
// user (the WaxBin user is named by the WaxDeck user id, which never
// collides). The catalog user is created first; if the username then
// turns out taken, the catalog row is orphaned, which the pre-check
// makes rare and the dangling-tolerant design makes harmless.
func (l *Library) CreateAccount(ctx context.Context, in AccountCreate) (*Account, error) {
	return l.createAccount(ctx, in, false)
}

// createAccount is CreateAccount plus the bootstrap door's atomic
// only-while-adminless guard.
func (l *Library) createAccount(ctx context.Context, in AccountCreate, onlyIfNoAdmin bool) (*Account, error) {
	username := strings.TrimSpace(in.Username)
	if username == "" || username != in.Username {
		return nil, errInvalid("username must not be empty or carry surrounding whitespace")
	}
	if len(username) > 64 {
		return nil, errInvalid("username must be at most 64 characters")
	}
	roles, err := normalizeRoles(in.Roles)
	if err != nil {
		return nil, err
	}
	mode, grants, err := normalizeAccess(in.AccessMode, in.LibraryPIDs)
	if err != nil {
		return nil, err
	}
	if _, err := l.db.UserByUsername(ctx, username); err == nil {
		return nil, &Error{Kind: KindConflict, Msg: "username is taken"}
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	hash := ""
	if in.Password != "" {
		if hash, err = auth.HashPassword(in.Password); err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
	}
	id := "us-" + ulid.Make().String()
	catalogUser, err := l.lib.CreateUser(ctx, id)
	if err != nil {
		return nil, classify(err)
	}
	u := &wdb.User{
		ID:            id,
		Username:      username,
		DisplayName:   strings.TrimSpace(in.DisplayName),
		PasswordHash:  hash,
		Roles:         roles,
		LibraryAccess: mode,
		WaxbinUserPID: string(catalogUser.PID),
	}
	if err := l.db.CreateUser(ctx, u, onlyIfNoAdmin); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return nil, &Error{Kind: KindConflict, Msg: "username is taken"}
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if len(grants) > 0 {
		if err := l.db.SetLibraryGrants(ctx, u.ID, grants); err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
	}
	return l.accountFor(ctx, u)
}

// Account fetches one account with its extras.
func (l *Library) Account(ctx context.Context, id string) (*Account, error) {
	u, err := l.db.UserByID(ctx, id)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, errNotFound("no user with id " + id)
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return l.accountFor(ctx, u)
}

// Accounts pages all accounts by username. The cursor is the previous
// page's last lowercased username, opaque to callers.
func (l *Library) Accounts(ctx context.Context, cursor string, limit int) (AccountPage, error) {
	users, err := l.db.ListUsers(ctx, cursor, limit+1)
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
		page.Next = strings.ToLower(users[len(users)-1].Username)
	}
	return page, nil
}

// UpdateAccount applies a partial update. Demoting or disabling the
// last enabled administrator conflicts, so the server can never lock
// every admin out; the guard rides the update statement itself, so two
// concurrent admin-removing updates cannot both pass a stale count.
func (l *Library) UpdateAccount(ctx context.Context, id string, upd AccountUpdate) (*Account, error) {
	u, err := l.db.UserByID(ctx, id)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, errNotFound("no user with id " + id)
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	losesAdmin := false
	visibilityChanged := false
	if upd.Roles != nil {
		roles, err := normalizeRoles(upd.Roles)
		if err != nil {
			return nil, err
		}
		losesAdmin = hasRole(u.Roles, "admin") && !hasRole(roles, "admin")
		// Admin status short-circuits library visibility, so a role
		// change is a visibility change.
		visibilityChanged = hasRole(u.Roles, "admin") != hasRole(roles, "admin")
		u.Roles = roles
	}
	if upd.Disabled != nil {
		if *upd.Disabled && !u.Disabled && hasRole(u.Roles, "admin") {
			losesAdmin = true
		}
		u.Disabled = *upd.Disabled
	}
	if upd.DisplayName != nil {
		u.DisplayName = strings.TrimSpace(*upd.DisplayName)
	}
	if upd.AccessMode != nil {
		mode, grants, err := normalizeAccess(*upd.AccessMode, upd.LibraryPIDs)
		if err != nil {
			return nil, err
		}
		u.LibraryAccess = mode
		if err := l.db.SetLibraryGrants(ctx, u.ID, grants); err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		visibilityChanged = true
	}
	if visibilityChanged {
		// Outstanding catalog sync cursors are scoped to the old grant
		// set; retiring them makes the next delta answer sync-reset and
		// the re-snapshot reflect the new visibility.
		l.bumpGrantEpoch(ctx, u.ID)
	}
	if err := l.db.UpdateUser(ctx, u, losesAdmin); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return nil, &Error{Kind: KindConflict, Msg: "this is the last enabled administrator"}
		}
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, errNotFound("no user with id " + id)
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return l.accountFor(ctx, u)
}

// DeleteAccount removes the account. The catalog user and its listening
// history are orphaned, not destroyed: history survives an accidental
// delete-and-recreate, and an admin purge can reap orphans later.
// Deleting the last enabled administrator conflicts, guarded on the
// delete statement itself.
func (l *Library) DeleteAccount(ctx context.Context, id string) error {
	u, err := l.db.UserByID(ctx, id)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no user with id " + id)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	removesAdmin := hasRole(u.Roles, "admin") && !u.Disabled
	if err := l.db.DeleteUser(ctx, id, removesAdmin); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return &Error{Kind: KindConflict, Msg: "this is the last enabled administrator"}
		}
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no user with id " + id)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// SetAccountPassword replaces the account's password hash.
func (l *Library) SetAccountPassword(ctx context.Context, id, newPassword string) error {
	u, err := l.db.UserByID(ctx, id)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("no user with id " + id)
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	hash, err := auth.HashPassword(newPassword)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	u.PasswordHash = hash
	if err := l.db.UpdateUser(ctx, u, false); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// VerifyLocalLogin checks username+password against local accounts.
// It returns nil, nil on any failure (unknown user, no local password,
// wrong password, disabled account): callers answer 401 without
// distinguishing, so the response never confirms an account exists. A
// dummy verification keeps the timing of "unknown user" and "wrong
// password" alike.
func (l *Library) VerifyLocalLogin(ctx context.Context, username, password string) (*wdb.User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			auth.VerifyPassword(dummyHash, password)
			return nil, nil
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.PasswordHash == "" || u.Disabled {
		auth.VerifyPassword(dummyHash, password)
		return nil, nil
	}
	if !auth.VerifyPassword(u.PasswordHash, password) {
		return nil, nil
	}
	return u, nil
}

// dummyHash burns the same argon2 work as a real verification when the
// account cannot match, keeping response timing flat.
var dummyHash = func() string {
	h, err := auth.HashPassword("waxdeck-timing-equalizer")
	if err != nil {
		panic(err) // crypto/rand failure at init is not recoverable
	}
	return h
}()

// OidcIdentity is a verified provider identity as the OIDC broker
// hands it over.
type OidcIdentity struct {
	Provider string
	Subject  string
	Email    string
	Username string
	Name     string
	// Roles is the group-claim role mapping; nil means the provider
	// carries none and locally assigned roles stand.
	Roles []string
}

// ResolveOidcAccount maps a verified identity to an account, creating
// one on first login. Resolution is by (provider, subject) only: a new
// identity NEVER links onto an existing local account by username or
// email (silent merges are an account-takeover class); a taken
// username is disambiguated with a numeric suffix. When the provider
// carries a group-claim role mapping, every login re-applies it, so
// the IdP stays authoritative over OIDC accounts' roles.
func (l *Library) ResolveOidcAccount(ctx context.Context, ident OidcIdentity) (*Account, error) {
	existing, err := l.db.IdentityBySubject(ctx, ident.Provider, ident.Subject)
	if err == nil {
		u, err := l.db.UserByID(ctx, existing.UserID)
		if err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		if u.Disabled {
			return nil, &Error{Kind: KindConflict, Msg: "this account is disabled"}
		}
		if ident.Roles != nil && !sameRoles(u.Roles, ident.Roles) {
			// The IdP's mapping applies on every login, but never demotes
			// the last enabled administrator: the guard rides the update
			// statement, and a refusal just keeps the current roles (the
			// server must stay administrable even against a misconfigured
			// claim).
			demotes := hasRole(u.Roles, "admin") && !hasRole(ident.Roles, "admin")
			prevRoles := u.Roles
			u.Roles = ident.Roles
			if err := l.db.UpdateUser(ctx, u, demotes); err != nil {
				if !errors.Is(err, wdb.ErrConflict) {
					return nil, &Error{Kind: KindInternal, Err: err}
				}
				u.Roles = prevRoles
				l.log.Warn("group claim would demote the last administrator; keeping roles",
					"user", u.ID)
			}
		}
		if ident.Email != existing.Email {
			if err := l.db.LinkIdentity(ctx, wdb.Identity{
				UserID: u.ID, Provider: ident.Provider, Subject: ident.Subject, Email: ident.Email,
			}); err != nil {
				return nil, &Error{Kind: KindInternal, Err: err}
			}
		}
		return l.accountFor(ctx, u)
	}
	if !errors.Is(err, wdb.ErrNotFound) {
		return nil, &Error{Kind: KindInternal, Err: err}
	}

	// First login: provision a fresh account.
	base := usernameHint(ident)
	roles := ident.Roles
	if roles == nil {
		roles = []string{"user"}
	}
	var acct *Account
	for attempt := 0; attempt < 20; attempt++ {
		name := base
		if attempt > 0 {
			name = fmt.Sprintf("%s%d", base, attempt+1)
		}
		acct, err = l.CreateAccount(ctx, AccountCreate{
			Username:    name,
			DisplayName: ident.Name,
			Roles:       roles,
			AccessMode:  "all",
		})
		if err == nil {
			break
		}
		if KindOf(err) != KindConflict {
			return nil, err
		}
	}
	if acct == nil {
		return nil, &Error{Kind: KindConflict, Msg: "could not find a free username for " + base}
	}
	if err := l.db.LinkIdentity(ctx, wdb.Identity{
		UserID: acct.User.ID, Provider: ident.Provider, Subject: ident.Subject, Email: ident.Email,
	}); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return l.Account(ctx, acct.User.ID)
}

// usernameHint derives a base username from the identity's claims.
func usernameHint(ident OidcIdentity) string {
	name := ident.Username
	if name == "" && ident.Email != "" {
		name, _, _ = strings.Cut(ident.Email, "@")
	}
	if name == "" {
		name = ident.Subject
	}
	name = truncateUTF8(strings.TrimSpace(name), 60)
	if name == "" {
		name = "sso-user"
	}
	return name
}

// truncateUTF8 bounds s to maxBytes without splitting a rune, so a
// multi-byte name never persists as invalid UTF-8.
func truncateUTF8(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	s = s[:maxBytes]
	for len(s) > 0 && !utf8.ValidString(s) {
		s = s[:len(s)-1]
	}
	return s
}

func sameRoles(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	set := make(map[string]bool, len(a))
	for _, r := range a {
		set[r] = true
	}
	for _, r := range b {
		if !set[r] {
			return false
		}
	}
	return true
}

// accountFor assembles the account DTO.
func (l *Library) accountFor(ctx context.Context, u *wdb.User) (*Account, error) {
	acct := &Account{User: u}
	if u.LibraryAccess == "granted" {
		pids, err := l.db.LibraryGrants(ctx, u.ID)
		if err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		for _, pid := range pids {
			acct.LibraryPIDs = append(acct.LibraryPIDs, PrefixLibrary+"-"+pid)
		}
	}
	idents, err := l.db.IdentitiesByUser(ctx, u.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	acct.Identities = idents
	return acct, nil
}

func normalizeRoles(roles []string) ([]string, error) {
	if len(roles) == 0 {
		return []string{"user"}, nil
	}
	seen := map[string]bool{}
	out := make([]string, 0, len(roles))
	for _, r := range roles {
		if !validRoles[r] {
			return nil, errInvalid("unknown role " + r)
		}
		if !seen[r] {
			seen[r] = true
			out = append(out, r)
		}
	}
	return out, nil
}

// normalizeAccess validates the access mode and strips grant PIDs down
// to bare catalog PIDs for storage.
func normalizeAccess(mode string, apiPIDs []string) (string, []string, error) {
	switch mode {
	case "", "all":
		return "all", nil, nil
	case "granted":
		grants := make([]string, 0, len(apiPIDs))
		for _, p := range apiPIDs {
			prefix, pid, ok := parseAPIPID(p)
			if !ok || prefix != PrefixLibrary {
				return "", nil, errInvalid("bad library pid " + p)
			}
			grants = append(grants, string(pid))
		}
		return "granted", grants, nil
	default:
		return "", nil, errInvalid("libraryAccess mode must be all or granted")
	}
}

func hasRole(roles []string, want string) bool {
	for _, r := range roles {
		if r == want {
			return true
		}
	}
	return false
}
