package auth

import (
	"context"
	"errors"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/db"
)

func openSessions(t *testing.T) (*Sessions, *db.DB) {
	t.Helper()
	d, err := db.Open(context.Background(), filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	return NewSessions(d), d
}

func addUser(t *testing.T, d *db.DB, id, username string) *db.User {
	t.Helper()
	u := &db.User{ID: id, Username: username, Roles: []string{"user"}, LibraryAccess: "all",
		WaxbinUserPID: "01JZX5N8QW3F4V9T2B7KDEXAMPLE"}
	if err := d.CreateUser(context.Background(), u, false); err != nil {
		t.Fatal(err)
	}
	return u
}

func newSession(t *testing.T, s *Sessions, userID string) string {
	t.Helper()
	c, err := s.Create(context.Background(), userID, "web", "", "")
	if err != nil {
		t.Fatal(err)
	}
	return c.Session.ID
}

// The feed is how a revoke reaches what a session opened (a socket
// outlives the row); a listener hears every revoke, a no-op included,
// because the row may already be gone through the account's cascade.
func TestRevokeNotifiesListeners(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, d := openSessions(t)
	addUser(t, d, "us-A", "alice")
	var got []RevokeEvent
	s.OnRevoke(func(e RevokeEvent) { got = append(got, e) })
	a, b := newSession(t, s, "us-A"), newSession(t, s, "us-A")

	if err := s.Revoke(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeAllForUser(ctx, "us-A", b); err != nil {
		t.Fatal(err)
	}
	if err := s.RevokeAllForUser(ctx, "us-A", ""); err != nil {
		t.Fatal(err)
	}
	if err := s.Revoke(ctx, a); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("revoking a gone session = %v, want not found", err)
	}
	want := []RevokeEvent{
		{SessionID: a},
		{UserID: "us-A", KeepID: b},
		{UserID: "us-A"},
		{SessionID: a},
	}
	if !slices.Equal(got, want) {
		t.Errorf("events = %+v, want %+v", got, want)
	}
}

// Alive is the backstop a socket re-checks on its ping: a session that
// can no longer authenticate, for whatever reason, is not alive.
func TestAliveRefusesAnExpiredDisabledOrDeletedSession(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, d := openSessions(t)
	u := addUser(t, d, "us-A", "alice")

	alive := func(id string) bool {
		t.Helper()
		ok, err := s.Alive(ctx, id)
		if err != nil {
			t.Fatalf("Alive(%q): %v", id, err)
		}
		return ok
	}
	live := newSession(t, s, u.ID)
	if !alive(live) {
		t.Fatal("a fresh session is not alive")
	}
	if alive("") || alive("se-nope") {
		t.Error("an empty or unknown session id is alive")
	}

	expired := newSession(t, s, u.ID)
	if err := d.TouchSession(ctx, expired, time.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	if alive(expired) {
		t.Error("an expired session is alive")
	}

	deleted := newSession(t, s, u.ID)
	if err := d.DeleteSession(ctx, deleted); err != nil {
		t.Fatal(err)
	}
	if alive(deleted) {
		t.Error("a deleted session is alive")
	}

	// A read that fails answers nothing about the session: the caller
	// must not end it on that.
	stalled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := s.Alive(stalled, live); err == nil {
		t.Error("a failed read reported an answer")
	}

	u.Disabled = true
	if err := d.UpdateUser(ctx, u, false); err != nil {
		t.Fatal(err)
	}
	if alive(live) {
		t.Error("a disabled account's session is alive")
	}
}

// Past the cap a sign-in ends the account's least recently used session
// through Revoke, so whatever that session opened closes with it.
func TestCreateEndsTheStalestSessionPastTheCap(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, d := openSessions(t)
	addUser(t, d, "us-A", "alice")
	s.LimitPerAccount(2)
	var revoked []string
	s.OnRevoke(func(e RevokeEvent) { revoked = append(revoked, e.SessionID) })

	stale := newSession(t, s, "us-A")
	fresh := newSession(t, s, "us-A")
	// The older-created session is the one in use; the cap goes by use.
	if err := d.TouchSession(ctx, stale, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	newest := newSession(t, s, "us-A")

	live, err := s.ListForUser(ctx, "us-A")
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, sess := range live {
		ids = append(ids, sess.ID)
	}
	slices.Sort(ids)
	want := []string{stale, newest}
	slices.Sort(want)
	if !slices.Equal(ids, want) {
		t.Errorf("live sessions = %v, want %v", ids, want)
	}
	if !slices.Equal(revoked, []string{fresh}) {
		t.Errorf("revoked = %v, want the least recently used %s", revoked, fresh)
	}
}
