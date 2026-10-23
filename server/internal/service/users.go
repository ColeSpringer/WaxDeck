package service

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
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
	// UploadEnabled grants the upload surface; UploadQuotaBytes caps it
	// (0 means no per-user cap).
	UploadEnabled    bool
	UploadQuotaBytes int64
	// Permissions is the granular toggle set; nil applies the defaults.
	Permissions *Permissions
	// Pending lands the account as a signup request awaiting approval
	// (the self-serve path); admin-created accounts are never pending.
	Pending bool
}

// AccountUpdate is a partial account update; nil fields are unchanged.
type AccountUpdate struct {
	DisplayName *string
	Roles       []string
	Disabled    *bool
	AccessMode  *string
	LibraryPIDs []string // meaningful only when AccessMode is set to "granted"
	// UploadEnabled grants or revokes uploads; UploadQuotaBytes replaces
	// the cap (0 removes it).
	UploadEnabled    *bool
	UploadQuotaBytes *int64
	// Permissions replaces the whole granular toggle set.
	Permissions *Permissions
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
		UploadEnabled: in.UploadEnabled,
		Pending:       in.Pending,
	}
	if in.UploadQuotaBytes > 0 {
		u.UploadQuotaBytes = in.UploadQuotaBytes
	}
	perms := DefaultPermissions()
	if in.Permissions != nil {
		perms = *in.Permissions
	}
	if err := validatePermissions(perms); err != nil {
		return nil, err
	}
	if err := applyPermissions(u, perms); err != nil {
		return nil, err
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
	// The starter playlists, so a first sign-in lands on something
	// rather than an empty grid. Every way an account is made comes
	// through here - an admin create, a signup, an OIDC provision, and
	// the bootstrap - except approval, which turns a pending row into an
	// account of its own and seeds there.
	l.seedStartersFor(ctx, u)
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
	// What the account may do, before anything is applied. Compared
	// whole afterwards rather than tracked per field: a right added to
	// the row is then covered by construction, where a forgotten clause
	// would silently drop the marker this whole path exists to send.
	before := rightsOf(u)
	// Grants are written to their own table rather than onto the row,
	// so they are the one change the comparison cannot see.
	grantsWritten := false
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
	if upd.UploadEnabled != nil {
		u.UploadEnabled = *upd.UploadEnabled
	}
	if upd.UploadQuotaBytes != nil {
		if *upd.UploadQuotaBytes < 0 {
			return nil, errInvalid("uploadQuotaBytes must not be negative")
		}
		u.UploadQuotaBytes = *upd.UploadQuotaBytes
	}
	if upd.Permissions != nil {
		if err := validatePermissions(*upd.Permissions); err != nil {
			return nil, err
		}
		prior := permissionsOf(u)
		if err := applyPermissions(u, *upd.Permissions); err != nil {
			return nil, err
		}
		// Content rules scope what a mirror may hold, exactly like
		// library grants: retiring outstanding cursors makes the next
		// delta answer sync-reset and the re-snapshot reflect the rules.
		if contentRulesChanged(prior, *upd.Permissions) {
			visibilityChanged = true
		}
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
		grantsWritten = true
	}
	// A display name is not a right: it changes what the account is
	// called, not what it may do, and every surface that shows it is a
	// live read anyway.
	rightsChanged := grantsWritten || !sameRights(before, rightsOf(u))
	err = l.db.UpdateUser(ctx, u, losesAdmin)
	if visibilityChanged && (err == nil || grantsWritten) {
		// Outstanding catalog sync cursors are scoped to the old grant
		// set; retiring them makes the next delta answer sync-reset and
		// the re-snapshot reflect the new visibility. Timelines minted
		// under the old reach end with it. After the write, and every
		// reader takes an epoch before the rules (TimelineReach, a
		// snapshot's first page), so nothing read under the old rules
		// carries the new epochs; the grants are written before it, so
		// they count even when it fails.
		l.reachChanged(ctx, u.ID)
	}
	if err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return nil, &Error{Kind: KindConflict, Msg: "this is the last enabled administrator"}
		}
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, errNotFound("no user with id " + id)
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if rightsChanged {
		l.emitUserEvent(ctx, u.ID, eventAccount, "")
	}
	return l.accountFor(ctx, u)
}

// AccountChanges is what an edit changed between two reads of one
// account, as the audit log records it: each changed field under its API
// name with the value before and after. The permission toggles and the
// library grant are fields of their own, so an edit of one lists that
// one. A save that changed nothing answers an empty map, and no
// credential is among the fields.
func AccountChanges(before, after *Account) map[string]map[string]any {
	changes := map[string]map[string]any{}
	record := func(field string, same bool, from, to any) {
		if !same {
			changes[field] = map[string]any{"from": from, "to": to}
		}
	}
	// Lists answer [] rather than null, so an empty grant reads as empty.
	list := func(s []string) []string { return append([]string{}, s...) }
	rules := func(s []TagRule) []TagRule { return append([]TagRule{}, s...) }
	sameSet := func(a, b []string) bool {
		a, b = slices.Sorted(slices.Values(a)), slices.Sorted(slices.Values(b))
		return slices.Equal(a, b)
	}

	b, a := before.User, after.User
	record("displayName", b.DisplayName == a.DisplayName, b.DisplayName, a.DisplayName)
	record("roles", sameRoles(b.Roles, a.Roles), list(b.Roles), list(a.Roles))
	record("disabled", b.Disabled == a.Disabled, b.Disabled, a.Disabled)
	record("uploadEnabled", b.UploadEnabled == a.UploadEnabled, b.UploadEnabled, a.UploadEnabled)
	record("uploadQuotaBytes", b.UploadQuotaBytes == a.UploadQuotaBytes, b.UploadQuotaBytes, a.UploadQuotaBytes)
	record("libraryAccess.mode", b.LibraryAccess == a.LibraryAccess, b.LibraryAccess, a.LibraryAccess)
	record("libraryAccess.libraryPids", sameSet(before.LibraryPIDs, after.LibraryPIDs),
		list(before.LibraryPIDs), list(after.LibraryPIDs))
	pb, pa := permissionsOf(b), permissionsOf(a)
	record("permissions.download", pb.Download == pa.Download, pb.Download, pa.Download)
	record("permissions.delete", pb.Delete == pa.Delete, pb.Delete, pa.Delete)
	record("permissions.explicitContent", pb.Explicit == pa.Explicit, pb.Explicit, pa.Explicit)
	record("permissions.sharedOutputs", pb.SharedOutputs == pa.SharedOutputs, pb.SharedOutputs, pa.SharedOutputs)
	record("permissions.managePodcasts", pb.ManagePodcasts == pa.ManagePodcasts, pb.ManagePodcasts, pa.ManagePodcasts)
	record("permissions.maxTranscodeKbps", pb.MaxTranscodeKbps == pa.MaxTranscodeKbps,
		pb.MaxTranscodeKbps, pa.MaxTranscodeKbps)
	record("permissions.tagAllow", slices.Equal(pb.TagAllow, pa.TagAllow), rules(pb.TagAllow), rules(pa.TagAllow))
	record("permissions.tagDeny", slices.Equal(pb.TagDeny, pa.TagDeny), rules(pb.TagDeny), rules(pa.TagDeny))
	return changes
}

// What becomes of the playlists an account owns when it is deleted.
const (
	PlaylistsTransfer = "transfer"
	PlaylistsDelete   = "delete"
)

// AccountDeletion says what DeleteAccount does with the account's
// playlists.
type AccountDeletion struct {
	// Playlists is PlaylistsTransfer (the default) or PlaylistsDelete.
	Playlists string
	// TransferTo is the account id that takes the shared playlists; empty
	// is the acting administrator.
	TransferTo string
}

// AccountDeleted is what a deletion did, or had done when it stopped.
type AccountDeleted struct {
	PlaylistsTransferred int
	PlaylistsDeleted     int
	// PlaylistsFixed counts the transferred playlists that went over as
	// fixed lists of the tracks they held, because their rules read the
	// deleted account's own stars, ratings or plays, or name a private
	// playlist that goes with it.
	PlaylistsFixed int
	// TransferredTo is the username of the account that took the shared
	// playlists; empty when none moved.
	TransferredTo string
	// LinksEnded counts the public share links the account had serving,
	// of its playlists and of anything else, which end with it.
	LinksEnded int
	// FixedCopiesRemoved and FixedCopiesKept are the API pids of the fixed
	// copies of playlists that an earlier attempt left and this one dealt
	// with: removed with the rest of the account's playlists, or, when the
	// list they were made from has been deleted since, kept for the account
	// that took the playlists. A copy that took its playlist's place in
	// this attempt is not among them, it is a playlist handed over.
	FixedCopiesRemoved []string
	FixedCopiesKept    []string
	// Disabled says this call disabled the account. A deletion that stops
	// part-way leaves it disabled, for a retry to finish.
	Disabled bool
}

// Changed says whether the call changed anything before it stopped or
// finished: disabled the account, handed over or deleted a playlist, or
// dealt with a copy an earlier attempt left.
func (d AccountDeleted) Changed() bool {
	return d.Disabled || d.PlaylistsTransferred > 0 || d.PlaylistsDeleted > 0 ||
		len(d.FixedCopiesRemoved) > 0 || len(d.FixedCopiesKept) > 0
}

// DeleteAccount removes the account, after handing its shared playlists to
// another account or deleting them, as opts says; its private ones are
// deleted either way, since nobody else could see them. The catalog user
// and its listening history are orphaned, not destroyed: history survives
// an accidental delete-and-recreate, and an admin purge can reap orphans
// later.
//
// The account is disabled first, by the update that refuses to disable
// the last enabled administrator. That refusal therefore lands before a
// playlist is touched, atomically, and the account can start nothing new
// while its playlists, listed again once it is disabled, are settled. The
// playlists go before the account, so a failure leaves a disabled account
// that a retry can finish rather than playlists nobody can reach; the
// result says what was done even when the error is not nil. Only one
// deletion of an account runs at a time. The account's public share links
// are not handed to anyone: they end with it.
func (l *Library) DeleteAccount(ctx context.Context, actor *UserCtx, id string, opts AccountDeletion) (AccountDeleted, error) {
	if _, running := l.deletingAccounts.LoadOrStore(id, struct{}{}); running {
		return AccountDeleted{}, &Error{Kind: KindConflict, Msg: "this account is already being deleted"}
	}
	defer l.deletingAccounts.Delete(id)
	u, err := l.db.UserByID(ctx, id)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return AccountDeleted{}, errNotFound("no user with id " + id)
		}
		return AccountDeleted{}, &Error{Kind: KindInternal, Err: err}
	}
	owned, err := l.ownedPlaylists(ctx, u)
	if err != nil {
		return AccountDeleted{}, err
	}
	taker, err := l.playlistTaker(ctx, actor, u, opts)
	if err != nil {
		return AccountDeleted{}, err
	}
	if taker == nil && opts.Playlists != PlaylistsDelete && slices.ContainsFunc(owned, sharedPlaylist) {
		return AccountDeleted{}, errInvalid("name the account that takes the shared playlists")
	}
	removesAdmin := hasRole(u.Roles, "admin") && !u.Disabled
	disabledHere := false
	if !u.Disabled {
		off := true
		if _, err := l.UpdateAccount(ctx, id, AccountUpdate{Disabled: &off}); err != nil {
			return AccountDeleted{}, err
		}
		disabledHere = true
	}
	if l.accountDisabledHook != nil {
		l.accountDisabledHook(ctx)
	}
	// Listed again now the account can start nothing new: one made since
	// the first look is settled with the rest.
	if owned, err = l.ownedPlaylists(ctx, u); err != nil {
		return AccountDeleted{Disabled: disabledHere}, err
	}
	if taker == nil && opts.Playlists != PlaylistsDelete && slices.ContainsFunc(owned, sharedPlaylist) {
		return AccountDeleted{Disabled: disabledHere}, errInvalid("name the account that takes the shared playlists")
	}
	settled, err := l.settlePlaylists(ctx, u, owned, taker)
	settled.Disabled = disabledHere
	if err != nil {
		return settled, err
	}
	// Counted before the rows go: the account's public links end with it,
	// whatever they pointed at, and the record says how many.
	ended, err := l.db.CountLiveShares(ctx, id, time.Now())
	if err != nil {
		return settled, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.DeleteUser(ctx, id, removesAdmin); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return settled, &Error{Kind: KindConflict, Msg: "this is the last enabled administrator"}
		}
		if errors.Is(err, wdb.ErrNotFound) {
			return settled, errNotFound("no user with id " + id)
		}
		return settled, &Error{Kind: KindInternal, Err: err}
	}
	settled.LinksEnded = ended
	if err := l.db.DeletePlaylistHandoversOf(ctx, id); err != nil {
		l.log.Warn("clearing a deleted account's playlist handover records", "user", id, "err", err)
	}
	return settled, nil
}

func sharedPlaylist(pl *model.Playlist) bool { return pl.Visibility == model.VisibilityShared }

// ownedPlaylists lists the playlists the catalog says the account owns.
func (l *Library) ownedPlaylists(ctx context.Context, u *wdb.User) ([]*model.Playlist, error) {
	// An empty pid names the catalog's default user, whose playlists are
	// nobody's to take.
	catalogUser := l.catalogPID(u)
	if catalogUser == "" {
		return nil, nil
	}
	all, err := l.lib.Playlists().List(ctx, model.PID(catalogUser))
	if err != nil {
		// A catalog user the catalog never made owns nothing.
		if KindOf(classify(err)) == KindNotFound {
			return nil, nil
		}
		return nil, classify(err)
	}
	return slices.DeleteFunc(all, func(pl *model.Playlist) bool {
		return string(pl.OwnerPID) != catalogUser
	}), nil
}

// playlistTaker resolves the account that takes a deleted account's
// shared playlists: the one named, else the actor. Nil when the playlists
// are deleted instead, and when there is no actor and nobody named, which
// DeleteAccount refuses if there is anything to hand over.
func (l *Library) playlistTaker(ctx context.Context, actor *UserCtx, victim *wdb.User, opts AccountDeletion) (*wdb.User, error) {
	switch opts.Playlists {
	case "", PlaylistsTransfer:
	case PlaylistsDelete:
		if opts.TransferTo != "" {
			return nil, errInvalid("transferTo applies only when the playlists are transferred")
		}
		return nil, nil
	default:
		return nil, errInvalid("playlists must be transfer or delete")
	}
	takerID := opts.TransferTo
	if takerID == "" && actor != nil {
		takerID = actor.ID
	}
	if takerID == "" {
		return nil, nil
	}
	if takerID == victim.ID {
		return nil, errInvalid("the playlists cannot go to the account being deleted")
	}
	taker, err := l.db.UserByID(ctx, takerID)
	switch {
	case errors.Is(err, wdb.ErrNotFound):
		return nil, errInvalid("no account with id " + takerID)
	case err != nil:
		return nil, &Error{Kind: KindInternal, Err: err}
	case taker.Disabled:
		return nil, errInvalid("that account is disabled")
	case taker.Pending:
		return nil, errInvalid("that signup has not been approved yet")
	}
	switch known, err := l.hasCatalogUser(ctx, taker); {
	case err != nil:
		return nil, err
	case !known:
		return nil, errInvalid("that account has no library user to own playlists")
	}
	return taker, nil
}

// settlePlaylists hands the shared playlists to taker, or deletes them
// when taker is nil, and deletes the private ones. The handing over comes
// first, while every playlist a rule of theirs might name still exists. A
// shared playlist changing hands or going is news to every other account's
// stream. A playlist someone else deleted meanwhile has nothing left to
// settle. The result says what was done even when the error is not nil.
func (l *Library) settlePlaylists(ctx context.Context, victim *wdb.User, owned []*model.Playlist, taker *wdb.User) (AccountDeleted, error) {
	var out AccountDeleted
	var handed, removed []*model.Playlist
	leaving := map[model.PID]bool{}
	for _, pl := range owned {
		if taker != nil && sharedPlaylist(pl) {
			handed = append(handed, pl)
			continue
		}
		removed = append(removed, pl)
		leaving[pl.PID] = true
	}
	for _, pl := range handed {
		fixed, err := l.handOverPlaylist(ctx, victim, taker, pl, leaving)
		if err != nil {
			if err = l.unlessGone(ctx, pl, err); err != nil {
				return out, err
			}
			continue
		}
		out.PlaylistsTransferred++
		out.TransferredTo = taker.Username
		l.announcePlaylist(ctx, victim.ID, string(pl.PID))
		if fixed != "" {
			out.PlaylistsFixed++
			l.announcePlaylist(ctx, victim.ID, string(fixed))
		}
	}
	for _, pl := range removed {
		if err := l.removePlaylist(ctx, pl); err != nil {
			if err = l.unlessGone(ctx, pl, err); err != nil {
				return out, err
			}
			continue
		}
		out.PlaylistsDeleted++
		if sharedPlaylist(pl) {
			l.announcePlaylist(ctx, victim.ID, string(pl.PID))
		}
	}
	// What earlier attempts left of playlists that are not handed over now.
	if err := l.settleHandoverLeftovers(ctx, victim, taker, &out); err != nil {
		return out, err
	}
	return out, nil
}

// unlessGone drops the error for a playlist someone else deleted while an
// account's were being settled. A not-found about a playlist that is still
// there is about an account the catalog does not know, which is not the
// account being deleted, whatever it says.
func (l *Library) unlessGone(ctx context.Context, pl *model.Playlist, err error) error {
	if KindOf(err) != KindNotFound {
		return err
	}
	if l.playlistGone(ctx, pl.PID) {
		return nil
	}
	return &Error{Kind: KindInternal, Err: err}
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
	if u.PasswordHash == "" || u.Disabled || u.Pending {
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
		if u.Pending {
			return nil, &Error{Kind: KindConflict, Msg: "this account is waiting for approval"}
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
			} else {
				// Admin status short-circuits visibility, so moving in or
				// out of it is a visibility change, as UpdateAccount
				// counts it: cursors and timelines from before end.
				if hasRole(prevRoles, "admin") != hasRole(u.Roles, "admin") {
					l.reachChanged(ctx, u.ID)
				}
				// The IdP moved this account's roles under whatever
				// sessions it already has open; they re-read the session
				// rather than waiting for a relaunch.
				l.emitUserEvent(ctx, u.ID, eventAccount, "")
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

// accountRights is everything about an account row that changes what
// its open sessions may do.
//
// A projection rather than a field-by-field diff of the row: the
// display name, the password hash and the timestamps are deliberately
// absent, and everything else is here by construction.
type accountRights struct {
	roles       []string
	disabled    bool
	upload      bool
	quota       int64
	access      string
	permissions Permissions
}

func rightsOf(u *wdb.User) accountRights {
	return accountRights{
		roles:       slices.Clone(u.Roles),
		disabled:    u.Disabled,
		upload:      u.UploadEnabled,
		quota:       u.UploadQuotaBytes,
		access:      u.LibraryAccess,
		permissions: permissionsOf(u),
	}
}

func sameRights(a, b accountRights) bool {
	return sameRoles(a.roles, b.roles) && a.disabled == b.disabled &&
		a.upload == b.upload && a.quota == b.quota && a.access == b.access &&
		samePermissions(a.permissions, b.permissions)
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
