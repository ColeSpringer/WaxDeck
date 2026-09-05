package service

import (
	"testing"
	"time"
)

// The inbox is the record of what happened to an account, so it is
// written on every emit rather than only where a delivery target was
// configured: a target is how news leaves the server, not where it is
// kept.
func TestInboxIsWrittenWithoutTargets(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	svc.EmitNotificationFor(ctx, "episode-downloaded", "New episode: Show",
		"Episode one", "ep-01JZX5N8QW3F4V9T2B7KD3M9R6", []string{uc.ID})

	page, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("reading the inbox: %v", err)
	}
	if len(page.Notifications) != 1 {
		t.Fatalf("inbox = %+v, want one row", page.Notifications)
	}
	row := page.Notifications[0]
	if row.Event != "episode-downloaded" {
		t.Fatalf("event = %q", row.Event)
	}
	if row.TargetPID != "ep-01JZX5N8QW3F4V9T2B7KD3M9R6" {
		t.Fatalf("targetPid = %q, want the episode", row.TargetPID)
	}
	if !row.ReadAt.IsZero() {
		t.Fatalf("a new row reads as read: %+v", row)
	}
	if page.Unread != 1 {
		t.Fatalf("unread = %d, want 1", page.Unread)
	}
	// And the row's arrival is on the caller's sync stream, so a client
	// that is running refetches instead of waiting for a relaunch.
	if evs := eventsAfter(t, ctx, svc, uc, 0); len(evs) == 0 ||
		evs[len(evs)-1].Kind != eventNotification {
		t.Fatalf("events = %+v, want a trailing notification marker", evs)
	}
}

// A server-scope event is every enabled administrator's own record.
func TestServerNotificationsReachAdminInboxes(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	svc.EmitServerNotification(ctx, "backup-completed", "Backup finished", "12 MB")

	page, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("reading the inbox: %v", err)
	}
	if len(page.Notifications) != 1 ||
		page.Notifications[0].Event != "backup-completed" {
		t.Fatalf("inbox = %+v, want the backup row", page.Notifications)
	}
}

func TestInboxPagingAndReadMarks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	for i := range 5 {
		svc.EmitNotificationFor(ctx, "review-ready", "Ready for review",
			"entry", "", []string{uc.ID})
		// ULIDs mint monotonically within a millisecond, but the keyset
		// only needs them distinct and ordered; a beat apart is the
		// cheapest way to be sure of both.
		if i < 4 {
			time.Sleep(time.Millisecond)
		}
	}

	first, err := svc.Notifications(ctx, uc, "", 2)
	if err != nil {
		t.Fatalf("first page: %v", err)
	}
	if len(first.Notifications) != 2 || first.Next == "" {
		t.Fatalf("first page = %+v (next %q), want two rows and a cursor",
			first.Notifications, first.Next)
	}
	if first.Unread != 5 {
		t.Fatalf("unread = %d, want the whole inbox rather than the page", first.Unread)
	}
	second, err := svc.Notifications(ctx, uc, first.Next, 2)
	if err != nil {
		t.Fatalf("second page: %v", err)
	}
	if len(second.Notifications) != 2 {
		t.Fatalf("second page = %+v, want two rows", second.Notifications)
	}
	if second.Notifications[0].ID == first.Notifications[0].ID {
		t.Fatal("the cursor served the first page again")
	}

	// Marked by id: one row, and only that one.
	target := first.Notifications[0].ID
	if err := svc.MarkNotificationsRead(ctx, uc, []string{target}); err != nil {
		t.Fatalf("marking one read: %v", err)
	}
	after, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("re-reading: %v", err)
	}
	if after.Unread != 4 {
		t.Fatalf("unread = %d, want 4", after.Unread)
	}
	for _, row := range after.Notifications {
		if (row.ID == target) != !row.ReadAt.IsZero() {
			t.Fatalf("row %+v disagrees with what was marked", row)
		}
	}

	// And with no ids: everything.
	if err := svc.MarkNotificationsRead(ctx, uc, nil); err != nil {
		t.Fatalf("marking all read: %v", err)
	}
	all, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("re-reading: %v", err)
	}
	if all.Unread != 0 {
		t.Fatalf("unread = %d, want none", all.Unread)
	}
}

// The inbox is per account, so another account's row is not a thing this
// caller can be told exists.
func TestDeleteAndClearAreScopedToTheCaller(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	other, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "someone-else", Password: "correct-horse",
	})
	if err != nil {
		t.Fatalf("creating the other account: %v", err)
	}
	otherUC, err := svc.UserCtx(ctx, other.User)
	if err != nil {
		t.Fatalf("building a user context: %v", err)
	}

	svc.EmitNotificationFor(ctx, "review-ready", "Ready for review", "entry", "",
		[]string{uc.ID, otherUC.ID})
	mine, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("reading the inbox: %v", err)
	}
	if len(mine.Notifications) != 1 {
		t.Fatalf("inbox = %+v, want one row", mine.Notifications)
	}

	wantKind(t, svc.DeleteNotification(ctx, otherUC, mine.Notifications[0].ID),
		KindNotFound)
	if err := svc.DeleteNotification(ctx, uc, mine.Notifications[0].ID); err != nil {
		t.Fatalf("deleting my own row: %v", err)
	}
	if again, err := svc.Notifications(ctx, uc, "", 50); err != nil ||
		len(again.Notifications) != 0 {
		t.Fatalf("inbox = %+v (%v), want empty", again.Notifications, err)
	}
	// Clearing mine leaves theirs standing.
	if err := svc.ClearNotifications(ctx, uc); err != nil {
		t.Fatalf("clearing: %v", err)
	}
	theirs, err := svc.Notifications(ctx, otherUC, "", 50)
	if err != nil {
		t.Fatalf("reading their inbox: %v", err)
	}
	if len(theirs.Notifications) != 1 {
		t.Fatalf("their inbox = %+v, want their own row", theirs.Notifications)
	}
}

func TestPruneNotificationsByAgeAndCap(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	// Two rows, one of them older than any horizon.
	svc.EmitNotificationFor(ctx, "review-ready", "Ready", "now", "", []string{uc.ID})
	now := time.Now()
	if n, err := svc.db.PruneNotifications(ctx, now.Add(time.Hour).UnixNano(), 0); err != nil {
		t.Fatalf("pruning by age: %v", err)
	} else if n != 1 {
		t.Fatalf("pruned %d rows by age, want the one row", n)
	}
	if after, err := svc.Notifications(ctx, uc, "", 50); err != nil ||
		len(after.Notifications) != 0 {
		t.Fatalf("inbox = %+v (%v), want empty after the horizon passed",
			after.Notifications, err)
	}
	// And the cap, with nothing old enough to age out.
	for range 4 {
		svc.EmitNotificationFor(ctx, "review-ready", "Ready", "again", "", []string{uc.ID})
		time.Sleep(time.Millisecond)
	}
	if n, err := svc.db.PruneNotifications(ctx, now.Add(-time.Hour).UnixNano(), 2); err != nil {
		t.Fatalf("pruning by cap: %v", err)
	} else if n != 2 {
		t.Fatalf("pruned %d rows by cap, want the two oldest", n)
	}
	left, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("re-reading: %v", err)
	}
	if len(left.Notifications) != 2 {
		t.Fatalf("inbox = %+v, want the newest two", left.Notifications)
	}
}
