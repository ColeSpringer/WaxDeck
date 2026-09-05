package service

import (
	"context"
	"testing"
)

// starterOf returns the account's seeded Most played playlist, or the
// zero value when there is none.
func starterOf(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) Playlist {
	t.Helper()
	page, err := svc.Playlists(ctx, uc, "", "", 50)
	if err != nil {
		t.Fatalf("listing playlists: %v", err)
	}
	var found []Playlist
	for _, pl := range page.Playlists {
		if pl.Name == starterMostPlayedName {
			found = append(found, pl)
		}
	}
	if len(found) > 1 {
		t.Fatalf("%d playlists named %q, want at most one", len(found), starterMostPlayedName)
	}
	if len(found) == 0 {
		return Playlist{}
	}
	return found[0]
}

// TestStarterPlaylistSeededAtAccountCreation pins the shape of the one
// list every account starts with. It is an ordinary owned smart
// playlist, so the whole rule has to round-trip through the read: an
// editor that cannot render it is a list the owner cannot change.
func TestStarterPlaylistSeededAtAccountCreation(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	pl := starterOf(t, ctx, svc, uc)
	if pl.PID == "" {
		t.Fatal("a created account holds no starter playlist")
	}
	if pl.Kind != "smart" || pl.Visibility != "private" || !pl.IsOwner {
		t.Fatalf("starter = %+v, want a private owned smart playlist", pl)
	}
	if pl.Rule == nil {
		t.Fatal("the starter carries no rule")
	}
	want := starterMostPlayedRule()
	got := *pl.Rule
	// The mode is compared as the engine reads it: a plain member cap
	// is spelled "count" on the way in and comes back as the empty
	// default, which the wire contract says is the same thing.
	if got.Limit != want.Limit || limitModeToEngine[got.LimitMode] != limitModeToEngine[want.LimitMode] {
		t.Fatalf("limit = %d/%q, want %d/%q", got.Limit, got.LimitMode, want.Limit, want.LimitMode)
	}
	if len(got.Sorts) != len(want.Sorts) {
		t.Fatalf("sorts = %+v, want %+v", got.Sorts, want.Sorts)
	}
	for i, s := range want.Sorts {
		if got.Sorts[i] != s {
			t.Fatalf("sort %d = %+v, want %+v", i, got.Sorts[i], s)
		}
	}
	if got.Root.Type != "all" || len(got.Root.Nodes) != 2 {
		t.Fatalf("root = %+v, want two conditions under all", got.Root)
	}
	for i, c := range want.Root.Nodes {
		n := got.Root.Nodes[i]
		if n.Type != c.Type || n.Field != c.Field || n.Op != c.Op || n.Value != c.Value {
			t.Fatalf("condition %d = %+v, want %+v", i, n, c)
		}
	}
}

// TestStarterPlaylistDeletionSticks is the whole point of the
// starter_playlists row: a boot reconcile that only asked the catalog
// would mint the list again on the next start, which is a playlist
// somebody has to delete once per restart.
func TestStarterPlaylistDeletionSticks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	pl := starterOf(t, ctx, svc, uc)
	if pl.PID == "" {
		t.Fatal("a created account holds no starter playlist")
	}
	if err := svc.DeletePlaylist(ctx, uc, pl.PID); err != nil {
		t.Fatalf("deleting the starter: %v", err)
	}
	if err := svc.reconcileStarterPlaylists(ctx); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if again := starterOf(t, ctx, svc, uc); again.PID != "" {
		t.Fatalf("the reconcile re-seeded a deleted starter as %s", again.PID)
	}
}

// TestStarterPlaylistReconcileFillsGaps covers the two cases account
// creation cannot: an account that predates the starters, and a catalog
// reset that drops the playlist while the row naming it survives.
func TestStarterPlaylistReconcileFillsGaps(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	seeded := starterOf(t, ctx, svc, uc)
	if seeded.PID == "" {
		t.Fatal("a created account holds no starter playlist")
	}

	// An account from before the starters existed: no row, no playlist.
	if err := svc.DeletePlaylist(ctx, uc, seeded.PID); err != nil {
		t.Fatalf("deleting the starter: %v", err)
	}
	if _, err := svc.db.Writer().ExecContext(ctx,
		`DELETE FROM starter_playlists WHERE user_id = ?`, uc.ID); err != nil {
		t.Fatalf("clearing the starter row: %v", err)
	}
	if err := svc.reconcileStarterPlaylists(ctx); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	reseeded := starterOf(t, ctx, svc, uc)
	if reseeded.PID == "" {
		t.Fatal("the reconcile left an account with no starter row unseeded")
	}

	// A catalog reset: the row still names a playlist the catalog no
	// longer holds, and nobody dismissed it. The stored pid is the
	// catalog's own, bare, as the cover and source rows beside it are.
	if _, err := svc.db.Writer().ExecContext(ctx,
		`UPDATE starter_playlists SET playlist_pid = '01ARZ3NDEKTSV4RRFFQ69G5FAV'
		 WHERE user_id = ?`, uc.ID); err != nil {
		t.Fatalf("pointing the row at a missing playlist: %v", err)
	}
	if err := svc.DeletePlaylist(ctx, uc, reseeded.PID); err != nil {
		t.Fatalf("deleting the re-seeded starter: %v", err)
	}
	if err := svc.reconcileStarterPlaylists(ctx); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if rebuilt := starterOf(t, ctx, svc, uc); rebuilt.PID == "" {
		t.Fatal("the reconcile left a rebuilt catalog without its starter")
	}
}

// TestStarterPlaylistIsOrdinary pins what the decision said it is: a
// playlist the owner can rename and re-rule like any other, with no
// second copy appearing behind the rename.
func TestStarterPlaylistIsOrdinary(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	pl := starterOf(t, ctx, svc, uc)
	if pl.PID == "" {
		t.Fatal("a created account holds no starter playlist")
	}
	name := "On repeat"
	renamed, err := svc.UpdatePlaylist(ctx, uc, pl.PID, PlaylistUpdate{Name: &name})
	if err != nil {
		t.Fatalf("renaming the starter: %v", err)
	}
	if renamed.Name != name || renamed.PID != pl.PID {
		t.Fatalf("rename = %+v, want %s under the same pid", renamed, name)
	}
	if err := svc.reconcileStarterPlaylists(ctx); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if again := starterOf(t, ctx, svc, uc); again.PID != "" {
		t.Fatalf("the reconcile minted a second starter beside the renamed one (%s)", again.PID)
	}
}

// TestStarterPlaylistFollowsApproval covers the path account creation
// does not: a signup is pending when it is made, so approval is where
// its starter lands - and an approval of a row somebody disabled
// meanwhile is not an account that should hold one.
func TestStarterPlaylistFollowsApproval(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{SignupEnabled: true}); err != nil {
		t.Fatal(err)
	}
	pending, _, err := svc.Signup(ctx, "sam", "password123", "Sam", "")
	if err != nil {
		t.Fatalf("signup: %v", err)
	}
	sam := starterUserCtx(t, ctx, svc, pending.User.ID)
	if pl := starterOf(t, ctx, svc, sam); pl.PID != "" {
		t.Fatalf("a pending signup holds a starter (%s)", pl.PID)
	}
	if _, err := svc.ApproveSignup(ctx, admin, pending.User.ID, SignupApproval{}); err != nil {
		t.Fatalf("approving: %v", err)
	}
	if pl := starterOf(t, ctx, svc, sam); pl.PID == "" {
		t.Fatal("an approved signup holds no starter")
	}

	// Disabled before approval: still not an account anybody signs into,
	// so it gets no starter, on this path or the boot pass.
	blocked, _, err := svc.Signup(ctx, "kim", "password123", "Kim", "")
	if err != nil {
		t.Fatalf("signup: %v", err)
	}
	disabled := true
	if _, err := svc.UpdateAccount(ctx, blocked.User.ID, AccountUpdate{Disabled: &disabled}); err != nil {
		t.Fatalf("disabling: %v", err)
	}
	if _, err := svc.ApproveSignup(ctx, admin, blocked.User.ID, SignupApproval{}); err != nil {
		t.Fatalf("approving: %v", err)
	}
	if err := svc.reconcileStarterPlaylists(ctx); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	kim := starterUserCtx(t, ctx, svc, blocked.User.ID)
	if pl := starterOf(t, ctx, svc, kim); pl.PID != "" {
		t.Fatalf("a disabled account holds a starter (%s)", pl.PID)
	}
}

// starterUserCtx is one account's own context, for reading its
// playlists as itself rather than as the admin that made it.
func starterUserCtx(t *testing.T, ctx context.Context, svc *Library, userID string) *UserCtx {
	t.Helper()
	uc, err := svc.UserCtxByID(ctx, userID)
	if err != nil {
		t.Fatalf("user context for %s: %v", userID, err)
	}
	return uc
}
