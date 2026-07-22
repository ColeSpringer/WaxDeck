package db

import (
	"context"
	"errors"
	"fmt"
	"sync"
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

func upTarget(id, user, endpoint, label string, ns int64) NotificationTarget {
	return NotificationTarget{
		ID: id, Kind: "unifiedpush", Scope: "user", UserID: user, Label: label,
		SealedConfig: []byte("sealed:" + endpoint), EnabledEvents: `["episode-downloaded"]`,
		DedupeKey: endpoint, CreatedAtNS: ns,
	}
}

func TestUnifiedPushTargetUpsertAndCap(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	mustCreateTestUser(t, d, "us-2")

	endpoint := func(i int) string { return fmt.Sprintf("https://push.example.net/ep/%d", i) }
	for i := 0; i < 20; i++ {
		_, created, err := d.UpsertUnifiedPushTarget(ctx, upTarget(fmt.Sprintf("reg-%02d", i), "us-1", endpoint(i), "device", int64(i)))
		if err != nil || !created {
			t.Fatalf("registration %d = (created %v, %v)", i, created, err)
		}
	}
	_, _, err := d.UpsertUnifiedPushTarget(ctx, upTarget("reg-over", "us-1", endpoint(20), "", 20))
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("21st registration = %v, want ErrConflict", err)
	}

	// Re-registering a held endpoint at the cap refreshes label and
	// config in place instead of tripping the cap, and preserves the
	// event selection made in the targets surface.
	if err := d.UpdateNotificationTarget(ctx, NotificationTarget{
		ID: "reg-00", Label: "device", SealedConfig: []byte("sealed:" + endpoint(0)),
		EnabledEvents: `["feed-disabled"]`, DedupeKey: endpoint(0),
	}); err != nil {
		t.Fatal(err)
	}
	stored, created, err := d.UpsertUnifiedPushTarget(ctx, upTarget("reg-ignored", "us-1", endpoint(0), "renamed", 99))
	if err != nil || created {
		t.Fatalf("re-register = (created %v, %v), want an update", created, err)
	}
	if stored.ID != "reg-00" || stored.Label != "renamed" {
		t.Fatalf("re-register stored = %+v, want the original row with the new label", stored)
	}
	if stored.EnabledEvents != `["feed-disabled"]` {
		t.Fatalf("re-register enabled events = %s, want the narrowed selection preserved", stored.EnabledEvents)
	}

	// The cap is per user.
	if _, created, err := d.UpsertUnifiedPushTarget(ctx, upTarget("reg-other", "us-2", endpoint(0), "", 1)); err != nil || !created {
		t.Fatalf("other-user registration = (created %v, %v)", created, err)
	}

	// The cap is also per kind: a webhook target does not consume a
	// unifiedpush slot.
	if err := d.InsertNotificationTarget(ctx, NotificationTarget{
		ID: "wh-1", Kind: "webhook", Scope: "user", UserID: "us-2",
		SealedConfig: []byte("sealed"), EnabledEvents: `[]`, CreatedAtNS: 2,
	}); err != nil {
		t.Fatalf("other-kind insert = %v", err)
	}

	// A direct insert of a held endpoint is ErrExists, not a cap
	// conflict.
	if err := d.InsertNotificationTarget(ctx, upTarget("dup", "us-2", endpoint(0), "", 3)); !errors.Is(err, ErrExists) {
		t.Fatalf("duplicate endpoint insert = %v, want ErrExists", err)
	}

	// Deleting one row frees a slot.
	if err := d.DeleteUserNotificationTarget(ctx, "us-1", "reg-01"); err != nil {
		t.Fatal(err)
	}
	if _, created, err := d.UpsertUnifiedPushTarget(ctx, upTarget("reg-fresh", "us-1", endpoint(21), "", 21)); err != nil || !created {
		t.Fatalf("post-delete registration = (created %v, %v)", created, err)
	}
}

func TestNotificationTargetOwnershipAndScopes(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	mustCreateTestUser(t, d, "us-2")

	server := NotificationTarget{
		ID: "srv-1", Kind: "webhook", Scope: "server",
		SealedConfig: []byte("sealed"), EnabledEvents: `["signup-requested"]`, CreatedAtNS: 1,
	}
	personal := NotificationTarget{
		ID: "per-1", Kind: "webhook", Scope: "user", UserID: "us-1",
		SealedConfig: []byte("sealed"), EnabledEvents: `[]`, CreatedAtNS: 2,
	}
	if err := d.InsertNotificationTarget(ctx, server); err != nil {
		t.Fatal(err)
	}
	if err := d.InsertNotificationTarget(ctx, personal); err != nil {
		t.Fatal(err)
	}

	srv, err := d.ServerNotificationTargets(ctx)
	if err != nil || len(srv) != 1 || srv[0].ID != "srv-1" || srv[0].UserID != "" {
		t.Fatalf("server list = (%+v, %v), want just srv-1 with no owner", srv, err)
	}
	mine, err := d.UserNotificationTargets(ctx, "us-1")
	if err != nil || len(mine) != 1 || mine[0].ID != "per-1" {
		t.Fatalf("user list = (%+v, %v), want just per-1", mine, err)
	}

	// Owner scoping on delete: another user's row and the server row
	// are both out of reach.
	if err := d.DeleteUserNotificationTarget(ctx, "us-2", "per-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("cross-user delete = %v, want ErrNotFound", err)
	}
	if err := d.DeleteUserNotificationTarget(ctx, "us-1", "srv-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user delete of server row = %v, want ErrNotFound", err)
	}
	if err := d.DeleteServerNotificationTarget(ctx, "per-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("server delete of user row = %v, want ErrNotFound", err)
	}
	if err := d.DeleteServerNotificationTarget(ctx, "srv-1"); err != nil {
		t.Fatal(err)
	}
}

func TestNotifyOutboxTargetBinding(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")
	target := NotificationTarget{
		ID: "tgt-1", Kind: "webhook", Scope: "user", UserID: "us-1",
		SealedConfig: []byte("sealed"), EnabledEvents: `[]`, CreatedAtNS: 1,
	}
	if err := d.InsertNotificationTarget(ctx, target); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueNotify(ctx, NotifyRow{TargetID: "tgt-1", Event: "test", Title: "T"}, 10); err != nil {
		t.Fatal(err)
	}

	row, err := d.LeaseNotify(ctx, 20, 100, 10)
	if err != nil || row.TargetID != "tgt-1" || row.Event != "test" {
		t.Fatalf("lease = (%+v, %v), want the queued row", row, err)
	}
	// Health marks land on the target row.
	if err := d.MarkNotifyTargetDelivery(ctx, "tgt-1", false, "boom", 30); err != nil {
		t.Fatal(err)
	}
	got, err := d.NotificationTargetByID(ctx, "tgt-1")
	if err != nil || got.LastError != "boom" || got.LastErrorNS != 30 {
		t.Fatalf("failed mark = (%+v, %v)", got, err)
	}
	if err := d.MarkNotifyTargetDelivery(ctx, "tgt-1", true, "", 40); err != nil {
		t.Fatal(err)
	}
	got, err = d.NotificationTargetByID(ctx, "tgt-1")
	if err != nil || got.LastSuccessNS != 40 || got.LastError != "" || got.LastErrorNS != 0 {
		t.Fatalf("success mark = (%+v, %v), want the error cleared", got, err)
	}
	if err := d.CompleteNotify(ctx, row.ID); err != nil {
		t.Fatal(err)
	}

	// Deleting a target cascades its queued deliveries away.
	if err := d.EnqueueNotify(ctx, NotifyRow{TargetID: "tgt-1", Event: "test"}, 50); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteUserNotificationTarget(ctx, "us-1", "tgt-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseNotify(ctx, 60, 100, 10); !errors.Is(err, ErrNotFound) {
		t.Fatalf("lease after cascade = %v, want ErrNotFound", err)
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

func TestUnifiedPushUpsertRaceStaysIdempotent(t *testing.T) {
	// Two statements make the upsert, so concurrent registrations of
	// one endpoint can interleave update-miss, update-miss, insert,
	// insert-hits-dedupe; the losing call must retry its update leg
	// and answer like the idempotent re-register it is, never an
	// error.
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-1")

	const racers = 8
	created := make(chan bool, racers)
	errs := make(chan error, racers)
	var wg sync.WaitGroup
	for i := 0; i < racers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, was, err := d.UpsertUnifiedPushTarget(ctx,
				upTarget(fmt.Sprintf("race-%02d", i), "us-1", "https://push.example.net/race", "device", int64(i)))
			created <- was
			errs <- err
		}(i)
	}
	wg.Wait()
	close(created)
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("racing upsert = %v, want success for every caller", err)
		}
	}
	wins := 0
	for was := range created {
		if was {
			wins++
		}
	}
	if wins != 1 {
		t.Fatalf("created count = %d, want exactly one winner", wins)
	}
	rows, err := d.UserNotificationTargets(ctx, "us-1")
	if err != nil || len(rows) != 1 {
		t.Fatalf("targets after race = (%d, %v), want exactly one row", len(rows), err)
	}
}
