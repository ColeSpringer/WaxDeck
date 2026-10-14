package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// gpodderFixture is one account holding one app password.
func gpodderFixture(t *testing.T) (*DB, context.Context) {
	t.Helper()
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-A", "alice", []string{"user"}), false); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"ap-1", "ap-2"} {
		if _, err := d.InsertAppPassword(ctx, &AppPassword{ID: id, UserID: "us-A", Label: id,
			SecretEnc: []byte(id), SecretHash: []byte(id)}, 10); err != nil {
			t.Fatal(err)
		}
	}
	return d, ctx
}

func gpodderSession(id, appPassword string, created, expires time.Time) GpodderSession {
	return GpodderSession{ID: id, UserID: "us-A", AppPasswordID: appPassword, TokenHash: []byte(id),
		CreatedAtNS: created.UnixNano(), ExpiresAtNS: expires.UnixNano()}
}

func hasGpodderSession(t *testing.T, d *DB, ctx context.Context, id string) bool {
	t.Helper()
	_, err := d.GpodderSessionByHash(ctx, []byte(id))
	if err != nil && !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	return err == nil
}

// A gpodder session goes with the app password that opened it and with
// its account, by the schema's own cascade: nothing has to remember to.
func TestGpodderSessionsCascade(t *testing.T) {
	d, ctx := gpodderFixture(t)
	now := time.Now()
	for _, s := range []GpodderSession{
		gpodderSession("one", "ap-1", now, now.Add(time.Hour)),
		gpodderSession("two", "ap-2", now, now.Add(time.Hour)),
	} {
		if err := d.InsertGpodderSession(ctx, s, 20); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.DeleteAppPassword(ctx, "us-A", "ap-1"); err != nil {
		t.Fatal(err)
	}
	if hasGpodderSession(t, d, ctx, "one") {
		t.Error("a session outlived its app password")
	}
	if !hasGpodderSession(t, d, ctx, "two") {
		t.Fatal("another app password's session went with it")
	}
	if err := d.DeleteUser(ctx, "us-A", false); err != nil {
		t.Fatal(err)
	}
	if hasGpodderSession(t, d, ctx, "two") {
		t.Error("a session outlived its account")
	}
}

// The sweep takes expired sessions and leaves live ones, and one app
// password holds at most the cap, the oldest giving way: a client that
// logs in on every sync cannot grow the table.
func TestGpodderSessionsAreBounded(t *testing.T) {
	d, ctx := gpodderFixture(t)
	now := time.Now()
	if err := d.InsertGpodderSession(ctx, gpodderSession("stale", "ap-1", now.Add(-2*time.Hour), now.Add(-time.Hour)), 20); err != nil {
		t.Fatal(err)
	}
	if err := d.InsertGpodderSession(ctx, gpodderSession("live", "ap-2", now, now.Add(time.Hour)), 20); err != nil {
		t.Fatal(err)
	}
	if err := d.SweepExpired(ctx); err != nil {
		t.Fatal(err)
	}
	if hasGpodderSession(t, d, ctx, "stale") || !hasGpodderSession(t, d, ctx, "live") {
		t.Error("the sweep did not take exactly the expired session")
	}

	for i, id := range []string{"first", "second", "third"} {
		s := gpodderSession(id, "ap-1", now.Add(time.Duration(i)*time.Second), now.Add(time.Hour))
		if err := d.InsertGpodderSession(ctx, s, 2); err != nil {
			t.Fatal(err)
		}
	}
	if hasGpodderSession(t, d, ctx, "first") {
		t.Error("the oldest session survived past the cap")
	}
	if !hasGpodderSession(t, d, ctx, "second") || !hasGpodderSession(t, d, ctx, "third") || !hasGpodderSession(t, d, ctx, "live") {
		t.Error("the cap took a newer session, or another app password's")
	}

	if err := d.DeleteGpodderSessionsForUser(ctx, "us-A"); err != nil {
		t.Fatal(err)
	}
	if hasGpodderSession(t, d, ctx, "live") || hasGpodderSession(t, d, ctx, "third") {
		t.Error("ending the account's sessions left one")
	}
}
