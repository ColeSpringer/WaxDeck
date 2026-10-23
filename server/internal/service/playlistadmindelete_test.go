package service

import (
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// An administrator may delete any shared playlist, which is what clears
// one whose owner is gone, and the entry says whose it was. Editing stays
// the owner's, and another account's private playlist reads as absent to
// an administrator as it does to anyone.
func TestAnAdministratorMayDeleteAnySharedPlaylist(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	_, samCtx := playlistMember(t, ctx, svc, "sam")
	_, patCtx := playlistMember(t, ctx, svc, "pat")
	shared := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	kept := playlistAs(t, ctx, svc, samCtx, "Kept", "shared", pids)
	private := playlistAs(t, ctx, svc, samCtx, "Guilty pleasures", "private", pids)

	if err := svc.DeletePlaylist(ctx, patCtx, shared); KindOf(err) != KindForbidden {
		t.Fatalf("another member deleting a shared playlist = %v, want forbidden", err)
	}
	if err := svc.DeletePlaylist(ctx, admin, private); KindOf(err) != KindNotFound {
		t.Fatalf("an administrator deleting a private playlist = %v, want not found", err)
	}
	rename := "Mine now"
	if _, err := svc.UpdatePlaylist(ctx, admin, kept, PlaylistUpdate{Name: &rename}); KindOf(err) != KindForbidden {
		t.Fatalf("an administrator editing a member's playlist = %v, want forbidden", err)
	}

	if err := svc.DeletePlaylist(ctx, admin, shared); err != nil {
		t.Fatalf("an administrator deleting a shared playlist: %v", err)
	}
	if catalogHas(ctx, svc, shared) {
		t.Error("the playlist survived its deletion")
	}
	for _, left := range []string{kept, private} {
		if !catalogHas(ctx, svc, left) {
			t.Errorf("playlist %s went with the one that was deleted", left)
		}
	}

	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "playlist.delete"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Events) != 1 {
		t.Fatalf("playlist.delete entries = %+v, want one", page.Events)
	}
	e := page.Events[0]
	if e.ActorID != admin.ID || e.TargetName != "Road trip" || e.Detail["owner"] != "sam" || e.Detail["shared"] != true {
		t.Errorf("entry = %+v, want the administrator deleting sam's shared Road trip", e)
	}
}

// A starter the owner threw away stays thrown away when somebody else
// deletes it: the dismissal is the owner's, not the deleter's, or the next
// boot would hand the starter back.
func TestAnAdministratorsDeleteDismissesTheOwnersStarter(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	var starter string
	page, err := svc.Playlists(ctx, samCtx, "", "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, pl := range page.Playlists {
		if pl.Name == starterMostPlayedName && pl.IsOwner {
			starter = pl.PID
		}
	}
	if starter == "" {
		t.Fatalf("a new account has no starter playlist: %+v", page.Playlists)
	}
	shared := "shared"
	if _, err := svc.UpdatePlaylist(ctx, samCtx, starter, PlaylistUpdate{Visibility: &shared}); err != nil {
		t.Fatal(err)
	}

	if err := svc.DeletePlaylist(ctx, admin, starter); err != nil {
		t.Fatal(err)
	}
	svc.seedStartersFor(ctx, sam.User)

	page, err = svc.Playlists(ctx, samCtx, "", "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, pl := range page.Playlists {
		if pl.Name == starterMostPlayedName {
			t.Errorf("the starter came back after an administrator deleted it: %+v", pl)
		}
	}
}
