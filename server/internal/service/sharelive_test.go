package service

import (
	"testing"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The check a running stream repeats on its link: live until the link is
// revoked or expires, or its owner can no longer sign in.
func TestShareLiveFollowsTheLinkAndItsOwner(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	ownerID, owner := shareOwner(t, ctx, svc, "publisher")
	mint := func() (bare, apiID string) {
		t.Helper()
		sh, err := svc.CreateShare(ctx, owner, track, 0, false, 0)
		if err != nil {
			t.Fatal(err)
		}
		_, id, _ := parseAPIPID(sh.ID)
		return string(id), sh.ID
	}
	gone := func(id, what string) {
		t.Helper()
		if err := svc.ShareLive(ctx, id); KindOf(err) != KindNotFound {
			t.Errorf("%s: %v, want not-found", what, err)
		}
	}

	live, _ := mint()
	if err := svc.ShareLive(ctx, live); err != nil {
		t.Fatalf("a fresh link: %v", err)
	}
	revoked, apiID := mint()
	if err := svc.RevokeShare(ctx, owner, apiID); err != nil {
		t.Fatal(err)
	}
	gone(revoked, "a revoked link")
	expired := ulid.Make().String()
	if err := svc.db.InsertShare(ctx, wdb.Share{
		ID: expired, UserID: ownerID, TargetPID: track, TargetKind: "track",
		CreatedAt: time.Now().Add(-2 * time.Hour), ExpiresAt: time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	gone(expired, "an expired link")
	gone(ulid.Make().String(), "a link that never was")

	disabled := true
	if _, err := svc.UpdateAccount(ctx, ownerID, AccountUpdate{Disabled: &disabled}); err != nil {
		t.Fatal(err)
	}
	gone(live, "the link of an owner who can no longer sign in")
}
