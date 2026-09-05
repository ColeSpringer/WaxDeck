package service

import (
	"testing"
)

// A rights change under an open session is only useful if the session
// hears about it, and the delta builder's switch is the whole
// mechanism: a kind missing from it is dropped without a sound.
func TestAccountUpdateEmitsOnlyForRightsChanges(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)

	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "listener", Password: "correct-horse",
	})
	if err != nil {
		t.Fatalf("creating the account: %v", err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatalf("building a user context: %v", err)
	}

	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatalf("minting a cursor: %v", err)
	}
	if _, err := svc.UpdateAccount(ctx, acct.User.ID, AccountUpdate{
		Roles: []string{"admin"},
	}); err != nil {
		t.Fatalf("granting the role: %v", err)
	}
	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatalf("reading the delta: %v", err)
	}
	if len(delta.Events) != 1 || delta.Events[0].Kind != eventAccount {
		t.Fatalf("events = %+v, want one account marker", delta.Events)
	}
	if delta.Events[0].PID != "" {
		t.Fatalf("the account marker carried pid %q, want none", delta.Events[0].PID)
	}

	// A display name is not a right: nothing gates on it, so nothing
	// re-reads the session for it.
	since = delta.NextSince
	name := "Listener"
	if _, err := svc.UpdateAccount(ctx, acct.User.ID, AccountUpdate{
		DisplayName: &name,
	}); err != nil {
		t.Fatalf("renaming: %v", err)
	}
	delta, err = svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatalf("reading the delta: %v", err)
	}
	if len(delta.Events) != 0 {
		t.Fatalf("a rename emitted %+v, want nothing", delta.Events)
	}

	// Writing the same roles back changes nothing either.
	since = delta.NextSince
	if _, err := svc.UpdateAccount(ctx, acct.User.ID, AccountUpdate{
		Roles: []string{"admin"},
	}); err != nil {
		t.Fatalf("re-granting the role: %v", err)
	}
	delta, err = svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatalf("reading the delta: %v", err)
	}
	if len(delta.Events) != 0 {
		t.Fatalf("a value-identical role write emitted %+v, want nothing", delta.Events)
	}

	// The permission toggles are rights too.
	since = delta.NextSince
	perms := DefaultPermissions()
	perms.Download = false
	if _, err := svc.UpdateAccount(ctx, acct.User.ID, AccountUpdate{
		Permissions: &perms,
	}); err != nil {
		t.Fatalf("revoking downloads: %v", err)
	}
	delta, err = svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatalf("reading the delta: %v", err)
	}
	if len(delta.Events) != 1 || delta.Events[0].Kind != eventAccount {
		t.Fatalf("events = %+v, want one account marker", delta.Events)
	}
}
