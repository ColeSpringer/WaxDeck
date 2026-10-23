package service

import (
	"context"
	"testing"
)

// A playlist the member makes while their account is being deleted, up to
// the moment it is disabled, is settled with the rest: a shared one is
// handed over, not left with a catalog user nobody can sign in as.
func TestAPlaylistMadeAsTheAccountIsDisabledIsHandedOver(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	var late string
	svc.accountDisabledHook = func(ctx context.Context) {
		late = playlistAs(t, ctx, svc, samCtx, "Late addition", "shared", pids)
	}
	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsTransferred != 1 {
		t.Errorf("result = %+v, want the late playlist handed over", got)
	}
	pl, err := svc.PlaylistByPID(ctx, admin, late)
	if err != nil || !pl.IsOwner || pl.OwnerName != "admin" {
		t.Fatalf("the late playlist = %+v (%v), want it the administrator's", pl, err)
	}
	if left := ownedBy(t, ctx, svc, sam.User.WaxbinUserPID); len(left) != 0 {
		t.Errorf("the deleted member's catalog user still owns %v", left)
	}
}
