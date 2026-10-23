package service

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// AuthorizeMedia is what makes a media token prove more than "this
// account could hear this item when the URL was minted": every fetch
// re-runs the mint's check, so a token stops with its account, its
// credential, and its account's reach.
func TestAuthorizeMediaFollowsTheAccount(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "listener", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	id := acct.User.ID
	stream := auth.MediaClaims{User: id, Purpose: auth.PurposeStream, PID: track}
	if err := svc.AuthorizeMedia(ctx, stream); err != nil {
		t.Fatalf("a live account: %v", err)
	}

	off, on := true, false
	if _, err := svc.UpdateAccount(ctx, id, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, stream); !errors.Is(err, auth.ErrMediaRevoked) {
		t.Errorf("a disabled account = %v, want the token revoked", err)
	}
	if _, err := svc.UpdateAccount(ctx, id, AccountUpdate{Disabled: &on}); err != nil {
		t.Fatal(err)
	}

	elsewhere, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	granted := "granted"
	if _, err := svc.UpdateAccount(ctx, id, AccountUpdate{AccessMode: &granted, LibraryPIDs: []string{elsewhere.PID}}); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, stream); KindOf(err) != KindNotFound {
		t.Errorf("an item outside the narrowed grant = %v, want not-found", err)
	}
	all := "all"
	if _, err := svc.UpdateAccount(ctx, id, AccountUpdate{AccessMode: &all}); err != nil {
		t.Fatal(err)
	}

	perms := DefaultPermissions()
	perms.Download = false
	if _, err := svc.UpdateAccount(ctx, id, AccountUpdate{Permissions: &perms}); err != nil {
		t.Fatal(err)
	}
	download := stream
	download.Purpose = auth.PurposeDownload
	if err := svc.AuthorizeMedia(ctx, download); KindOf(err) != KindForbidden {
		t.Errorf("a download without the right = %v, want forbidden", err)
	}
	if err := svc.AuthorizeMedia(ctx, stream); err != nil {
		t.Errorf("a stream without the download right: %v", err)
	}

	if _, err := svc.DeleteAccount(ctx, nil, id, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, stream); !errors.Is(err, auth.ErrMediaRevoked) {
		t.Errorf("a deleted account = %v, want the token revoked", err)
	}
}

// The credential a token was minted under has to be live too: a REST
// session, an app password, or the reach a timeline was minted for.
func TestAuthorizeMediaFollowsTheCredential(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	claims := func(cred string) auth.MediaClaims {
		return auth.MediaClaims{User: admin.ID, Cred: cred, Purpose: auth.PurposeStream, PID: track}
	}
	session := func(userID string, expires time.Time) string {
		t.Helper()
		s := &wdb.Session{ID: "se-" + ulid.Make().String(), UserID: userID, Kind: "web",
			TokenHash: []byte(ulid.Make().String()), CSRFToken: "x", ExpiresAt: expires}
		if err := svc.db.CreateSession(ctx, s); err != nil {
			t.Fatal(err)
		}
		return s.ID
	}

	live := session(admin.ID, time.Now().Add(time.Hour))
	if err := svc.AuthorizeMedia(ctx, claims("se:"+live)); err != nil {
		t.Errorf("a live session: %v", err)
	}
	if err := svc.db.DeleteSession(ctx, live); err != nil {
		t.Fatal(err)
	}
	expired := session(admin.ID, time.Now().Add(-time.Minute))
	other, err := svc.CreateAccount(ctx, AccountCreate{Username: "other", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	foreign := session(other.User.ID, time.Now().Add(time.Hour))
	for name, cred := range map[string]string{
		"a revoked session":        "se:" + live,
		"an expired session":       "se:" + expired,
		"another account's":        "se:" + foreign,
		"a credential of no kind":  "zz:" + live,
		"a revoked app password":   "ap:01JZX5N8QW3F4V9T2B7KDEXAMPL",
		"a reach the account left": "re:999",
	} {
		if err := svc.AuthorizeMedia(ctx, claims(cred)); !errors.Is(err, auth.ErrMediaRevoked) {
			t.Errorf("%s = %v, want the token revoked", name, err)
		}
	}

	// Stored directly: this fixture has no sealing key to mint one with.
	pw := &wdb.AppPassword{ID: ulid.Make().String(), UserID: admin.ID, Label: "client",
		SecretEnc: []byte("sealed"), SecretHash: []byte(ulid.Make().String())}
	if _, err := svc.db.InsertAppPassword(ctx, pw, 10); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, claims("ap:"+pw.ID)); err != nil {
		t.Errorf("a live app password: %v", err)
	}
	if err := svc.RevokeAppPassword(ctx, admin, apiPID(PrefixAppPassword, model.PID(pw.ID))); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, claims("ap:"+pw.ID)); !errors.Is(err, auth.ErrMediaRevoked) {
		t.Errorf("a revoked app password = %v, want the token revoked", err)
	}

	reach, _, err := svc.TimelineReach(ctx, admin.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, claims(reach)); err != nil {
		t.Errorf("the account's current reach: %v", err)
	}
	// A timeline the REST API minted names its session beside its reach,
	// and both have to hold.
	still := session(admin.ID, time.Now().Add(time.Hour))
	if err := svc.AuthorizeMedia(ctx, claims(reach+",se:"+still)); err != nil {
		t.Errorf("a live reach and session: %v", err)
	}
	for name, cred := range map[string]string{
		"a revoked session beside a live reach": reach + ",se:" + live,
		"an empty part beside a live reach":     reach + ",",
	} {
		if err := svc.AuthorizeMedia(ctx, claims(cred)); !errors.Is(err, auth.ErrMediaRevoked) {
			t.Errorf("%s = %v, want the token revoked", name, err)
		}
	}
	perms := DefaultPermissions()
	perms.TagDeny = []TagRule{{Key: "MOOD", Value: "calm"}}
	if _, err := svc.UpdateAccount(ctx, other.User.ID, AccountUpdate{Permissions: &perms}); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, claims(reach)); err != nil {
		t.Errorf("another account's rule change moved this one's reach: %v", err)
	}
	granted := "granted"
	if _, err := svc.UpdateAccount(ctx, admin.ID, AccountUpdate{Roles: []string{"admin"}, AccessMode: &granted}); err != nil {
		t.Fatal(err)
	}
	if err := svc.AuthorizeMedia(ctx, claims(reach)); !errors.Is(err, auth.ErrMediaRevoked) {
		t.Errorf("a reach the account has since changed = %v, want the token revoked", err)
	}
}

// Two account updates landing together each move the epochs: a bump
// that read an epoch beside another and wrote the same next value would
// let a timeline or sync cursor minted between them survive the second
// change.
func TestEpochsCountEveryBump(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	epochs := map[string]struct {
		bump func(context.Context, string)
		read func(context.Context, string) (int64, error)
	}{
		"reach": {svc.bumpReachEpoch, svc.reachEpoch},
		"grant": {svc.bumpGrantEpoch, svc.grantEpoch},
	}
	const bumps = 24
	for name, e := range epochs {
		var wg sync.WaitGroup
		for range bumps {
			wg.Add(1)
			go func() {
				defer wg.Done()
				e.bump(ctx, admin.ID)
			}()
		}
		wg.Wait()
		if got, err := e.read(ctx, admin.ID); err != nil || got != bumps {
			t.Errorf("%s epoch after %d bumps = %d (%v)", name, bumps, got, err)
		}
	}
}

// The epochs move after the account is written, so an update the store
// refuses (demoting the last administrator) leaves them where they were:
// nothing changed that a cursor or a timeline could have outlived.
func TestRefusedAccountUpdateMovesNoEpoch(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	reach, _ := svc.reachEpoch(ctx, admin.ID)
	grant, _ := svc.grantEpoch(ctx, admin.ID)
	if _, err := svc.UpdateAccount(ctx, admin.ID, AccountUpdate{Roles: []string{}}); KindOf(err) != KindConflict {
		t.Fatalf("demoting the last administrator = %v, want a conflict", err)
	}
	if got, _ := svc.reachEpoch(ctx, admin.ID); got != reach {
		t.Errorf("reach epoch = %d after a refused update, want %d", got, reach)
	}
	if got, _ := svc.grantEpoch(ctx, admin.ID); got != grant {
		t.Errorf("grant epoch = %d after a refused update, want %d", got, grant)
	}
}

// A check that could not be made is not a verdict: a failed read of the
// account or the session (the gate's deadline running out) is the
// server's trouble, which a player retries, never a revoked credential
// that would send it back to sign in.
func TestAuthorizeMediaDoesNotReadAFailedCheckAsRevoked(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	s := &wdb.Session{ID: "se-" + ulid.Make().String(), UserID: admin.ID, Kind: "web",
		TokenHash: []byte(ulid.Make().String()), CSRFToken: "x", ExpiresAt: time.Now().Add(time.Hour)}
	if err := svc.db.CreateSession(ctx, s); err != nil {
		t.Fatal(err)
	}
	stalled, cancel := context.WithCancel(ctx)
	cancel()
	err := svc.AuthorizeMedia(stalled, auth.MediaClaims{
		User: admin.ID, Cred: "se:" + s.ID, Purpose: auth.PurposeStream, PID: track,
	})
	if err == nil || errors.Is(err, auth.ErrMediaRevoked) || KindOf(err) == KindNotFound {
		t.Errorf("a stalled account read = %v, want a failure that is not a refusal", err)
	}
	if err := svc.credentialAlive(stalled, admin.ID, "se:"+s.ID); err == nil || errors.Is(err, auth.ErrMediaRevoked) {
		t.Errorf("a stalled session read = %v, want a failure that is not a refusal", err)
	}
}

// Every purpose is decided by name: a probe or a timeline opens nothing
// a per-item check could name and passes on its account and credential,
// and a purpose this check does not know is refused rather than waved
// through, so a route added later cannot inherit an open door.
func TestAuthorizeMediaDecidesEveryPurposeByName(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	for _, purpose := range []string{auth.PurposeProbe, auth.PurposeHLS} {
		if err := svc.AuthorizeMedia(ctx, auth.MediaClaims{User: admin.ID, Purpose: purpose, PID: "tl-x"}); err != nil {
			t.Errorf("%s = %v, want it admitted", purpose, err)
		}
	}
	if err := svc.AuthorizeMedia(ctx, auth.MediaClaims{User: admin.ID, Purpose: "unheard-of", PID: "tr-x"}); err == nil {
		t.Error("an unknown purpose was admitted")
	}
}

// One item's HLS rendering is that item's stream by another route, so
// each fetch re-checks the item as a stream's does.
func TestAuthorizeMediaChecksAnItemRenderingLikeItsStream(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	if err := svc.AuthorizeMedia(ctx, auth.MediaClaims{User: admin.ID, Purpose: auth.PurposeHLS, PID: track}); err != nil {
		t.Errorf("a visible item's rendering = %v, want it admitted", err)
	}
	err := svc.AuthorizeMedia(ctx, auth.MediaClaims{User: admin.ID, Purpose: auth.PurposeHLS, PID: "tr-01NOSUCHTRACK0000000000000"})
	if KindOf(err) != KindNotFound {
		t.Errorf("an unknown item's rendering = %v, want not found", err)
	}
}

// A group claim that moves an account in or out of the admin role on
// login changes what it may see, as the same change made by hand does:
// both epochs move, so its timelines and sync cursors from before end.
func TestOidcRoleChangeMovesTheEpochs(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	ident := OidcIdentity{Provider: "idp", Subject: "s-1", Username: "claimed", Roles: []string{"admin"}}
	acct, err := svc.ResolveOidcAccount(ctx, ident)
	if err != nil {
		t.Fatal(err)
	}
	reach, _ := svc.reachEpoch(ctx, acct.User.ID)
	grant, _ := svc.grantEpoch(ctx, acct.User.ID)
	ident.Roles = []string{"user"}
	if _, err := svc.ResolveOidcAccount(ctx, ident); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.reachEpoch(ctx, acct.User.ID); got == reach {
		t.Error("a claim demotion left the reach epoch where it was")
	}
	if got, _ := svc.grantEpoch(ctx, acct.User.ID); got == grant {
		t.Error("a claim demotion left the grant epoch where it was")
	}
}

// The gate puts the check's answers in the bridge's terms: an item the
// account cannot have is a refusal, and a catalog handed to maintenance
// is the catalog briefly away, which the bridge answers as the other
// media routes do rather than as a failure of its own.
func TestGateNamesMaintenanceForTheBridge(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, admin)[0]
	gate := svc.TranscodeGate()
	claims := auth.MediaClaims{User: admin.ID, Purpose: auth.PurposeStream, PID: track}
	if err := gate.AuthorizeMedia(ctx, auth.MediaClaims{User: admin.ID, Purpose: auth.PurposeStream, PID: "tr-01NOSUCHTRACK0000000000000"}); !errors.Is(err, flow.ErrMediaRefused) {
		t.Errorf("an unknown item = %v, want a refusal", err)
	}
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := svc.lib.EndMaintenance(ctx); err != nil {
			t.Fatal(err)
		}
	}()
	if err := gate.AuthorizeMedia(ctx, claims); !errors.Is(err, flow.ErrCatalogMaintenance) {
		t.Errorf("a check during maintenance = %v, want the maintenance sentinel", err)
	}
}

// An epoch the store cannot read back as a number is an error, never a
// zero: reading damage as 0 could make an old token or cursor match
// again once a bump writes 1.
func TestUnreadableEpochFailsClosed(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	for name, e := range map[string]struct {
		key  string
		read func(context.Context, string) (int64, error)
	}{
		"reach": {syncKeyReachEpoch, svc.reachEpoch},
		"grant": {syncKeyGrantEpoch, svc.grantEpoch},
	} {
		if err := svc.db.SyncStateSet(ctx, e.key+admin.ID, "not-a-number"); err != nil {
			t.Fatal(err)
		}
		if n, err := e.read(ctx, admin.ID); err == nil {
			t.Errorf("a damaged %s epoch read as %d", name, n)
		}
	}
}
