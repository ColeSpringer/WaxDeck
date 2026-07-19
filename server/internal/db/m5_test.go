package db

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

func enqueueTestScrobble(t *testing.T, d *DB, user, title string, ns int64) {
	t.Helper()
	err := d.EnqueueScrobble(context.Background(), ScrobbleRow{
		UserID:       user,
		Service:      "listenbrainz",
		ItemPID:      "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		Artist:       "Fixture Artist",
		Title:        title,
		ListenedAtNS: ns,
	}, ns)
	if err != nil {
		t.Fatal(err)
	}
}

func TestScrobbleOutboxLease(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	enqueueTestScrobble(t, d, "us-1", "First", 1)
	enqueueTestScrobble(t, d, "us-1", "Second", 2)

	// Oldest first, and a leased row is excluded until the lease ends.
	first, err := d.LeaseScrobble(ctx, 10, 100, 10)
	if err != nil || first.Title != "First" {
		t.Fatalf("first lease = (%+v, %v), want the oldest row", first, err)
	}
	second, err := d.LeaseScrobble(ctx, 10, 100, 10)
	if err != nil || second.Title != "Second" || second.ID == first.ID {
		t.Fatalf("second lease = (%+v, %v), want the remaining row", second, err)
	}
	if _, err := d.LeaseScrobble(ctx, 10, 100, 10); !errors.Is(err, ErrNotFound) {
		t.Fatalf("lease with both rows leased = %v, want ErrNotFound", err)
	}

	// Past expiry both rows are claimable again; completing one leaves
	// only the other.
	if err := d.CompleteScrobble(ctx, first.ID); err != nil {
		t.Fatal(err)
	}
	got, err := d.LeaseScrobble(ctx, 200, 100, 10)
	if err != nil || got.ID != second.ID {
		t.Fatalf("post-expiry lease = (%+v, %v), want the surviving row", got, err)
	}

	// Fail keeps the row unclaimable before its retry time and counts
	// the attempt.
	if err := d.FailScrobble(ctx, got.ID, "boom", 1000); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseScrobble(ctx, 999, 100, 10); !errors.Is(err, ErrNotFound) {
		t.Fatalf("lease before retry time = %v, want ErrNotFound", err)
	}
	got, err = d.LeaseScrobble(ctx, 1001, 100, 10)
	if err != nil || got.ID != second.ID || got.Attempts != 1 {
		t.Fatalf("lease after retry time = (%+v, %v), want attempts 1", got, err)
	}
}

func TestScrobbleOutboxExhaustAndPrune(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	enqueueTestScrobble(t, d, "us-1", "Doomed", 1)

	const maxAttempts = 3
	now := int64(10)
	for i := 0; i < maxAttempts; i++ {
		row, err := d.LeaseScrobble(ctx, now, 100, maxAttempts)
		if err != nil {
			t.Fatalf("lease attempt %d: %v", i, err)
		}
		if err := d.FailScrobble(ctx, row.ID, "still down", now+1); err != nil {
			t.Fatal(err)
		}
		now += 10
	}
	if _, err := d.LeaseScrobble(ctx, now, 100, maxAttempts); !errors.Is(err, ErrNotFound) {
		t.Fatalf("lease of an exhausted row = %v, want ErrNotFound", err)
	}

	// Prune removes exhausted rows even when they are not yet old.
	n, err := d.PruneScrobbleOutbox(ctx, 0, maxAttempts)
	if err != nil || n != 1 {
		t.Fatalf("prune exhausted = (%d, %v), want 1 row", n, err)
	}

	// And rows past the horizon regardless of attempts.
	enqueueTestScrobble(t, d, "us-1", "Stale", 100)
	n, err = d.PruneScrobbleOutbox(ctx, 200, maxAttempts)
	if err != nil || n != 1 {
		t.Fatalf("prune stale = (%d, %v), want 1 row", n, err)
	}
	n, err = d.PruneScrobbleOutbox(ctx, 200, maxAttempts)
	if err != nil || n != 0 {
		t.Fatalf("second prune = (%d, %v), want 0 rows", n, err)
	}
}

func TestPushRegistrationCap(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	mustCreateTestUser(t, d, "us-2")

	endpoint := func(i int) string { return fmt.Sprintf("https://push.example.net/ep/%d", i) }
	for i := 0; i < 20; i++ {
		_, created, err := d.UpsertPushRegistration(ctx, PushRegistration{
			ID: fmt.Sprintf("reg-%02d", i), UserID: "us-1", Endpoint: endpoint(i), Label: "device", CreatedAtNS: int64(i),
		})
		if err != nil || !created {
			t.Fatalf("registration %d = (created %v, %v)", i, created, err)
		}
	}
	_, _, err := d.UpsertPushRegistration(ctx, PushRegistration{
		ID: "reg-over", UserID: "us-1", Endpoint: endpoint(20), CreatedAtNS: 20,
	})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("21st registration = %v, want ErrConflict", err)
	}

	// Re-registering a held endpoint at the cap updates the label in
	// place instead of tripping the cap.
	stored, created, err := d.UpsertPushRegistration(ctx, PushRegistration{
		ID: "reg-ignored", UserID: "us-1", Endpoint: endpoint(0), Label: "renamed", CreatedAtNS: 99,
	})
	if err != nil || created {
		t.Fatalf("re-register = (created %v, %v), want an update", created, err)
	}
	if stored.ID != "reg-00" || stored.Label != "renamed" {
		t.Fatalf("re-register stored = %+v, want the original row with the new label", stored)
	}

	// The cap is per user.
	if _, created, err := d.UpsertPushRegistration(ctx, PushRegistration{
		ID: "reg-other", UserID: "us-2", Endpoint: endpoint(0), CreatedAtNS: 1,
	}); err != nil || !created {
		t.Fatalf("other-user registration = (created %v, %v)", created, err)
	}

	// Deleting one row frees a slot.
	if err := d.DeletePushRegistration(ctx, "us-1", "reg-01"); err != nil {
		t.Fatal(err)
	}
	if _, created, err := d.UpsertPushRegistration(ctx, PushRegistration{
		ID: "reg-fresh", UserID: "us-1", Endpoint: endpoint(21), CreatedAtNS: 21,
	}); err != nil || !created {
		t.Fatalf("post-delete registration = (created %v, %v)", created, err)
	}
}

func TestRadioStationGuards(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	a := RadioStation{ID: "01JZX5N8QW3F4V9T2B7KD3M9R1", Name: "One", StreamURL: "http://one.example/s", CreatedAtNS: 1}
	if err := d.CreateRadioStation(ctx, a); err != nil {
		t.Fatal(err)
	}

	// The duplicate guard lives in the insert statement.
	dup := RadioStation{ID: "01JZX5N8QW3F4V9T2B7KD3M9R2", Name: "Two", StreamURL: a.StreamURL, CreatedAtNS: 2}
	if err := d.CreateRadioStation(ctx, dup); !errors.Is(err, ErrConflict) {
		t.Fatalf("duplicate create = %v, want ErrConflict", err)
	}

	b := RadioStation{ID: "01JZX5N8QW3F4V9T2B7KD3M9R3", Name: "Two", StreamURL: "http://two.example/s", CreatedAtNS: 3}
	if err := d.CreateRadioStation(ctx, b); err != nil {
		t.Fatal(err)
	}

	// An update may keep its own URL but never steal another row's.
	b.Name = "Two Renamed"
	if err := d.UpdateRadioStation(ctx, b); err != nil {
		t.Fatalf("same-url update = %v", err)
	}
	b.StreamURL = a.StreamURL
	if err := d.UpdateRadioStation(ctx, b); !errors.Is(err, ErrConflict) {
		t.Fatalf("colliding update = %v, want ErrConflict", err)
	}
	missing := RadioStation{ID: "01JZX5N8QW3F4V9T2B7KD3M9R4", Name: "Ghost", StreamURL: "http://ghost.example/s"}
	if err := d.UpdateRadioStation(ctx, missing); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing update = %v, want ErrNotFound", err)
	}

	if err := d.DeleteRadioStation(ctx, a.ID); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteRadioStation(ctx, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("second delete = %v, want ErrNotFound", err)
	}
}
