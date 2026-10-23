package service

import (
	"context"
	"slices"
	"testing"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// playlistMember opens an account and its context.
func playlistMember(t *testing.T, ctx context.Context, svc *Library, name string) (*Account, *UserCtx) {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: name, Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return acct, uc
}

// playlistAs creates a static playlist of the given visibility.
func playlistAs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name, visibility string, pids []string) string {
	t.Helper()
	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: name, Kind: "static", Visibility: visibility, ItemPIDs: pids,
	})
	if err != nil {
		t.Fatalf("creating %q: %v", name, err)
	}
	return pl.PID
}

// ownedBy is what the catalog says a catalog user owns, whoever the
// account behind it is or was.
func ownedBy(t *testing.T, ctx context.Context, svc *Library, catalogPID string) []string {
	t.Helper()
	all, err := svc.lib.Playlists().List(ctx, model.PID(catalogPID))
	if err != nil {
		t.Fatalf("listing playlists: %v", err)
	}
	var out []string
	for _, pl := range all {
		if string(pl.OwnerPID) == catalogPID {
			out = append(out, pl.Name)
		}
	}
	slices.Sort(out)
	return out
}

func catalogHas(ctx context.Context, svc *Library, apiPID string) bool {
	_, bare, _ := parseAPIPID(apiPID)
	_, err := svc.lib.Playlists().Get(ctx, bare)
	return err == nil
}

// A deleted member's playlists are not left owned by a catalog user
// nobody can sign in as, listed under the raw id of a person who is gone
// and uneditable by anyone. The shared ones go to the administrator who
// deleted them, entries and all, and the private ones, which only that
// member could see, go with the member.
func TestDeletingAnAccountHandsItsSharedPlaylistsOver(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:3]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, bystander := playlistMember(t, ctx, svc, "bystander")

	roadTrip := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	guilty := playlistAs(t, ctx, svc, samCtx, "Guilty pleasures", "private", pids[:1])
	mine := playlistAs(t, ctx, svc, admin, "Mine", "private", pids[:2])
	theirs := playlistAs(t, ctx, svc, bystander, "Theirs", "shared", pids[:1])
	privateBefore := len(ownedBy(t, ctx, svc, sam.User.WaxbinUserPID)) - 1
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsTransferred != 1 || got.PlaylistsDeleted != privateBefore || got.TransferredTo != "admin" {
		t.Fatalf("result = %+v, want 1 handed to admin and %d private ones deleted", got, privateBefore)
	}
	if _, err := svc.Account(ctx, sam.User.ID); KindOf(err) != KindNotFound {
		t.Fatalf("the account after its deletion = %v, want not found", err)
	}

	// The shared playlist is the administrator's now: same entries, new
	// owner shown, theirs to edit.
	pl, err := svc.PlaylistByPID(ctx, admin, roadTrip)
	if err != nil {
		t.Fatalf("the handed-over playlist: %v", err)
	}
	if !pl.IsOwner || pl.OwnerName != "admin" || pl.Visibility != "shared" || pl.Name != "Road trip" {
		t.Errorf("handed-over playlist = %+v, want admin's, still shared and named", pl)
	}
	if members := memberPIDs(t, ctx, svc, admin, roadTrip); !slices.Equal(members, pids) {
		t.Errorf("members = %v, want its entries %v kept", members, pids)
	}
	newName := "Road trip (kept)"
	if _, err := svc.UpdatePlaylist(ctx, admin, roadTrip, PlaylistUpdate{Name: &newName}); err != nil {
		t.Errorf("the administrator cannot edit what they were handed: %v", err)
	}
	seen, err := svc.PlaylistByPID(ctx, bystander, roadTrip)
	if err != nil || seen.IsOwner || seen.OwnerName != "admin" {
		t.Errorf("another member sees %+v (%v), want it listed under the administrator", seen, err)
	}

	// Their private ones are gone, and nobody else's was touched.
	if catalogHas(ctx, svc, guilty) {
		t.Error("a private playlist of the deleted member survived")
	}
	if left := ownedBy(t, ctx, svc, sam.User.WaxbinUserPID); len(left) != 0 {
		t.Errorf("the deleted member's catalog user still owns %v", left)
	}
	for _, other := range []string{mine, theirs} {
		if !catalogHas(ctx, svc, other) {
			t.Errorf("playlist %s of another account was deleted", other)
		}
	}

	// Everyone's streams hear it: the handed-over playlist is news with
	// its new owner on it.
	delta, err := svc.SyncServerDelta(ctx, bystander, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	var announced *Playlist
	for _, e := range delta.Events {
		if e.Kind == eventPlaylist && e.PID == roadTrip {
			announced = e.Playlist
		}
	}
	if announced == nil || announced.OwnerName != "admin" {
		t.Errorf("the bystander's stream carried %+v for the handed-over playlist, want it under admin", announced)
	}
}

// The other answer: nothing of theirs stays, shared or not.
func TestDeletingAnAccountCanDeleteItsPlaylistsInstead(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	roadTrip := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	guilty := playlistAs(t, ctx, svc, samCtx, "Guilty pleasures", "private", pids)
	owned := len(ownedBy(t, ctx, svc, sam.User.WaxbinUserPID))

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{Playlists: PlaylistsDelete})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsTransferred != 0 || got.PlaylistsDeleted != owned || got.TransferredTo != "" {
		t.Fatalf("result = %+v, want all %d deleted and none handed over", got, owned)
	}
	for _, gone := range []string{roadTrip, guilty} {
		if catalogHas(ctx, svc, gone) {
			t.Errorf("playlist %s survived", gone)
		}
	}
	if left := ownedBy(t, ctx, svc, admin.CatalogPID); len(left) != 0 && slices.Contains(left, "Road trip") {
		t.Errorf("the administrator was handed %v despite the delete answer", left)
	}
}

// The recipient can be another member, and the sweep takes the side
// tables a deleted playlist leaves with it: its cover's provenance and
// its sync binding.
func TestDeletingAnAccountCanHandItsPlaylistsToAnotherMember(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	pat, patCtx := playlistMember(t, ctx, svc, "pat")
	roadTrip := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	doomed := playlistAs(t, ctx, svc, samCtx, "Doomed", "private", pids)
	_, doomedBare, _ := parseAPIPID(doomed)
	if err := svc.db.PutPlaylistCover(ctx, wdb.PlaylistCover{PlaylistPID: string(doomedBare), Origin: "custom"}); err != nil {
		t.Fatal(err)
	}
	// Both lists are synced from a source; the binding belongs to the
	// playlist, so it goes with a deleted one and stays with a handed-over one.
	_, keptBare, _ := parseAPIPID(roadTrip)
	for _, pid := range []string{string(doomedBare), string(keptBare)} {
		if err := svc.db.PutPlaylistSource(ctx, wdb.PlaylistSourceRow{
			PlaylistPID: pid, Source: "youtube", Mode: "append", IdentityKey: "yt:" + pid, CreatedAtNS: 1, UpdatedAtNS: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{TransferTo: pat.User.ID})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsTransferred != 1 || got.TransferredTo != "pat" {
		t.Fatalf("result = %+v, want one playlist handed to pat", got)
	}
	pl, err := svc.PlaylistByPID(ctx, patCtx, roadTrip)
	if err != nil || !pl.IsOwner || pl.OwnerName != "pat" {
		t.Errorf("pat sees %+v (%v), want it as theirs", pl, err)
	}
	if _, err := svc.db.PlaylistCoverFor(ctx, string(doomedBare)); err == nil {
		t.Error("a deleted playlist's cover provenance was left behind")
	}
	if _, err := svc.db.PlaylistSourceFor(ctx, string(doomedBare)); err == nil {
		t.Error("a deleted playlist's sync binding was left behind")
	}
	if _, err := svc.db.PlaylistSourceFor(ctx, string(keptBare)); err != nil {
		t.Errorf("the handed-over playlist's sync binding = %v, want it kept", err)
	}
}

// Anything that cannot take the playlists is refused before anything
// changes: the account, its playlists, and the other accounts stay as
// they were.
func TestAccountDeletionRefusesWhatCannotTakeThePlaylists(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:1]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	away, _ := playlistMember(t, ctx, svc, "away")
	off := true
	if _, err := svc.UpdateAccount(ctx, away.User.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	pending, err := svc.CreateAccount(ctx, AccountCreate{Username: "applicant", Password: "correct-horse", Pending: true})
	if err != nil {
		t.Fatal(err)
	}
	roadTrip := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)

	for name, opts := range map[string]AccountDeletion{
		"an unknown mode":           {Playlists: "keep"},
		"a recipient with delete":   {Playlists: PlaylistsDelete, TransferTo: admin.ID},
		"an unknown recipient":      {TransferTo: "us-01JZX5N8QW3F4V9T2B7KDNOBODY"},
		"the account being deleted": {TransferTo: sam.User.ID},
		"a disabled recipient":      {TransferTo: away.User.ID},
		"a pending recipient":       {TransferTo: pending.User.ID},
	} {
		if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, opts); KindOf(err) != KindInvalid {
			t.Errorf("%s: err = %v (kind %q), want invalid", name, err, KindOf(err))
		}
	}
	if _, err := svc.Account(ctx, sam.User.ID); err != nil {
		t.Errorf("a refused deletion removed the account: %v", err)
	}
	if pl, err := svc.PlaylistByPID(ctx, samCtx, roadTrip); err != nil || !pl.IsOwner {
		t.Errorf("a refused deletion disturbed the playlist: %+v (%v)", pl, err)
	}
	if _, err := svc.DeleteAccount(ctx, admin, "us-01JZX5N8QW3F4V9T2B7KDNOBODY", AccountDeletion{}); KindOf(err) != KindNotFound {
		t.Errorf("deleting an unknown account = %v, want not found", err)
	}
}

// The last administrator cannot be deleted, and the refusal comes before
// anything of theirs is deleted or handed over.
func TestRefusedAccountDeletionLeavesItsPlaylists(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:1]
	mine := playlistAs(t, ctx, svc, admin, "Mine", "private", pids)
	shared := playlistAs(t, ctx, svc, admin, "Ours", "shared", pids)

	if _, err := svc.DeleteAccount(ctx, admin, admin.ID, AccountDeletion{Playlists: PlaylistsDelete}); KindOf(err) != KindConflict {
		t.Fatalf("deleting the last administrator = %v, want a conflict", err)
	}
	for _, kept := range []string{mine, shared} {
		if !catalogHas(ctx, svc, kept) {
			t.Errorf("playlist %s went with a deletion that was refused", kept)
		}
	}
}
