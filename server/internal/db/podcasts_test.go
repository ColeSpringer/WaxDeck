package db

import (
	"context"
	"testing"
)

func mustCreateTestUser(t *testing.T, d *DB, id string) {
	t.Helper()
	u := &User{
		ID:            id,
		Username:      id,
		Roles:         []string{"user"},
		LibraryAccess: "all",
		WaxbinUserPID: "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
	}
	if err := d.CreateUser(context.Background(), u, false); err != nil {
		t.Fatal(err)
	}
}

func TestSubscriptionRoundTrip(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")
	mustCreateTestUser(t, d, "us-b")

	keep := int64(5)
	speed := 1.5
	trim := true
	sub := Subscription{
		UserID:        "us-a",
		ShowPID:       "01JZX5N8QW3F4V9T2B7KDSHOW01",
		Folder:        "news/tech",
		Private:       true,
		RetentionKeep: &keep,
		AutoDownload:  true,
		Speed:         &speed,
		TrimSilence:   &trim,
		CreatedAtNS:   100,
		UpdatedAtNS:   100,
	}
	if err := d.UpsertSubscription(ctx, sub); err != nil {
		t.Fatal(err)
	}

	got, err := d.SubscriptionFor(ctx, "us-a", sub.ShowPID)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Private || !got.AutoDownload || got.Folder != "news/tech" {
		t.Fatalf("round trip lost scalar fields: %+v", got)
	}
	if got.RetentionKeep == nil || *got.RetentionKeep != 5 {
		t.Fatalf("retention keep = %v, want 5", got.RetentionKeep)
	}
	if got.Speed == nil || *got.Speed != 1.5 {
		t.Fatalf("speed = %v, want 1.5", got.Speed)
	}
	if got.TrimSilence == nil || !*got.TrimSilence {
		t.Fatalf("trim = %v, want true", got.TrimSilence)
	}
	if got.VoiceBoost != nil {
		t.Fatalf("voice boost should stay unset (server default), got %v", *got.VoiceBoost)
	}

	// Replace clears fields back to NULL when absent and keeps created_at.
	if err := d.UpsertSubscription(ctx, Subscription{
		UserID: "us-a", ShowPID: sub.ShowPID, CreatedAtNS: 999, UpdatedAtNS: 200,
	}); err != nil {
		t.Fatal(err)
	}
	got, err = d.SubscriptionFor(ctx, "us-a", sub.ShowPID)
	if err != nil {
		t.Fatal(err)
	}
	if got.RetentionKeep != nil || got.Speed != nil || got.TrimSilence != nil {
		t.Fatalf("replace kept stale settings: %+v", got)
	}
	if got.CreatedAtNS != 100 {
		t.Fatalf("created_at_ns = %d, want preserved 100", got.CreatedAtNS)
	}
	if got.UpdatedAtNS != 200 {
		t.Fatalf("updated_at_ns = %d, want 200", got.UpdatedAtNS)
	}

	// A second user's subscription to the same show is independent, and
	// both appear in the by-show listing the retention union reads.
	if err := d.UpsertSubscription(ctx, Subscription{
		UserID: "us-b", ShowPID: sub.ShowPID, CreatedAtNS: 300, UpdatedAtNS: 300,
	}); err != nil {
		t.Fatal(err)
	}
	subs, err := d.SubscribersByShow(ctx, sub.ShowPID)
	if err != nil {
		t.Fatal(err)
	}
	if len(subs) != 2 {
		t.Fatalf("subscribers = %d, want 2", len(subs))
	}

	shows, err := d.SubscribedShowPIDs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(shows) != 1 || shows[0] != sub.ShowPID {
		t.Fatalf("subscribed shows = %v", shows)
	}

	existed, err := d.DeleteSubscription(ctx, "us-a", sub.ShowPID)
	if err != nil || !existed {
		t.Fatalf("delete = (%v, %v), want (true, nil)", existed, err)
	}
	existed, err = d.DeleteSubscription(ctx, "us-a", sub.ShowPID)
	if err != nil || existed {
		t.Fatalf("second delete = (%v, %v), want (false, nil)", existed, err)
	}
	if _, err := d.SubscriptionFor(ctx, "us-a", sub.ShowPID); err != ErrNotFound {
		t.Fatalf("read after delete = %v, want ErrNotFound", err)
	}
}

func TestQueueLeaseCycle(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	if err := d.EnqueueAnalysis(ctx, "essence-1", "ep-x", 10); err != nil {
		t.Fatal(err)
	}
	// A duplicate enqueue is a no-op, not an error.
	if err := d.EnqueueAnalysis(ctx, "essence-1", "ep-y", 20); err != nil {
		t.Fatal(err)
	}

	row, err := d.LeaseAnalysis(ctx, 100, 50, 5)
	if err != nil {
		t.Fatal(err)
	}
	if row.Key != "essence-1" || row.ItemPID != "ep-x" {
		t.Fatalf("leased %+v", row)
	}

	// Leased rows are invisible until the lease expires.
	if _, err := d.LeaseAnalysis(ctx, 120, 50, 5); err != ErrNotFound {
		t.Fatalf("second lease = %v, want ErrNotFound", err)
	}
	// After expiry the row is claimable again.
	if _, err := d.LeaseAnalysis(ctx, 200, 50, 5); err != nil {
		t.Fatalf("lease after expiry = %v", err)
	}

	// A failure holds the row until its retry time: the backoff is the
	// lease, so a just-failed row can never bounce straight back.
	if err := d.FailAnalysis(ctx, "essence-1", "boom", 280); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseAnalysis(ctx, 260, 50, 5); err != ErrNotFound {
		t.Fatalf("lease before retry time = %v, want ErrNotFound", err)
	}
	row, err = d.LeaseAnalysis(ctx, 300, 50, 5)
	if err != nil {
		t.Fatal(err)
	}
	if row.Attempts != 1 {
		t.Fatalf("attempts = %d, want 1", row.Attempts)
	}

	// Rows at the attempt cap stop being served.
	for range 4 {
		if err := d.FailAnalysis(ctx, "essence-1", "boom", 350); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.LeaseAnalysis(ctx, 400, 50, 5); err != ErrNotFound {
		t.Fatalf("capped lease = %v, want ErrNotFound", err)
	}

	if err := d.CompleteAnalysis(ctx, "essence-1"); err != nil {
		t.Fatal(err)
	}

	// The retention queue drains wholesale.
	if err := d.EnqueueRetention(ctx, "show-1", 1); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueRetention(ctx, "show-1", 2); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueRetention(ctx, "show-2", 3); err != nil {
		t.Fatal(err)
	}
	shows, err := d.TakeRetentionQueue(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(shows) != 2 {
		t.Fatalf("retention queue = %v, want 2 shows", shows)
	}
	shows, err = d.TakeRetentionQueue(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(shows) != 0 {
		t.Fatalf("second drain = %v, want empty", shows)
	}
}

func TestFeedStateFailureAccounting(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	st, err := d.RecordFeedFailure(ctx, "show-1", "timeout", 10, 3)
	if err != nil {
		t.Fatal(err)
	}
	if st.ConsecutiveFailures != 1 || st.Disabled {
		t.Fatalf("after one failure: %+v", st)
	}
	if _, err := d.RecordFeedFailure(ctx, "show-1", "timeout", 20, 3); err != nil {
		t.Fatal(err)
	}
	st, err = d.RecordFeedFailure(ctx, "show-1", "timeout", 30, 3)
	if err != nil {
		t.Fatal(err)
	}
	if st.ConsecutiveFailures != 3 || !st.Disabled {
		t.Fatalf("after three failures: %+v", st)
	}

	if err := d.RecordFeedSuccess(ctx, "show-1", 40); err != nil {
		t.Fatal(err)
	}
	st, err = d.FeedStateFor(ctx, "show-1")
	if err != nil {
		t.Fatal(err)
	}
	if st.ConsecutiveFailures != 0 || st.Disabled || st.LastSyncedNS != 40 {
		t.Fatalf("after recovery: %+v", st)
	}
}

func TestGpodderLogs(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-g")

	if err := d.UpsertGpodderDevice(ctx, GpodderDevice{
		UserID: "us-g", DeviceID: "phone", Caption: "Phone", Type: "mobile",
		CreatedAtNS: 1, UpdatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	// A partial update keeps the fields it does not supply.
	if err := d.UpsertGpodderDevice(ctx, GpodderDevice{
		UserID: "us-g", DeviceID: "phone", CreatedAtNS: 2, UpdatedAtNS: 2,
	}); err != nil {
		t.Fatal(err)
	}
	devs, err := d.GpodderDevicesByUser(ctx, "us-g")
	if err != nil {
		t.Fatal(err)
	}
	if len(devs) != 1 || devs[0].Caption != "Phone" || devs[0].Type != "mobile" {
		t.Fatalf("device after partial update: %+v", devs)
	}

	for i, action := range []string{"add", "remove", "add"} {
		if err := d.AppendGpodderSubEvent(ctx, GpodderSubEvent{
			UserID: "us-g", FeedURL: "https://example.com/feed.xml",
			Action: action, TsSec: int64(100 + i),
		}); err != nil {
			t.Fatal(err)
		}
	}
	evs, err := d.GpodderSubEventsSince(ctx, "us-g", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(evs) != 2 {
		t.Fatalf("events since 100 = %d, want 2 (since is exclusive)", len(evs))
	}

	pos := int64(90)
	total := int64(300)
	if err := d.AppendGpodderAction(ctx, GpodderAction{
		UserID: "us-g", PodcastURL: "https://example.com/feed.xml",
		EpisodeURL: "https://example.com/ep1.mp3", Action: "play",
		PositionSec: &pos, TotalSec: &total, UploadedSec: 500,
	}); err != nil {
		t.Fatal(err)
	}
	acts, err := d.GpodderActionsSince(ctx, "us-g", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(acts) != 1 || acts[0].PositionSec == nil || *acts[0].PositionSec != 90 {
		t.Fatalf("actions = %+v", acts)
	}
	acts, err = d.GpodderActionsSince(ctx, "us-g", 500, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(acts) != 0 {
		t.Fatalf("actions since 500 = %d, want 0 (since is exclusive)", len(acts))
	}
}
