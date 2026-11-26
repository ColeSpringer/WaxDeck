package service

import (
	"context"
	"encoding/json"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The inbox is the record of what happened to an account, so it is
// written on every emit rather than only where a delivery target was
// configured: a target is how news leaves the server, not where it is
// kept.
func TestInboxIsWrittenWithoutTargets(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	svc.Integrations.EmitNotificationFor(ctx, "episode-downloaded", "New episode: Show",
		"Episode one", "ep-01JZX5N8QW3F4V9T2B7KD3M9R6", []string{uc.ID})

	page, err := svc.Integrations.Notifications(ctx, uc, "", 50)
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

	svc.Integrations.EmitServerNotification(ctx, "backup-completed", "Backup finished", "12 MB")

	page, err := svc.Integrations.Notifications(ctx, uc, "", 50)
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
		svc.Integrations.EmitNotificationFor(ctx, "review-ready", "Ready for review",
			"entry", "", []string{uc.ID})
		// ULIDs mint monotonically within a millisecond, but the keyset
		// only needs them distinct and ordered; a beat apart is the
		// cheapest way to be sure of both.
		if i < 4 {
			time.Sleep(time.Millisecond)
		}
	}

	first, err := svc.Integrations.Notifications(ctx, uc, "", 2)
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
	second, err := svc.Integrations.Notifications(ctx, uc, first.Next, 2)
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
	if err := svc.Integrations.MarkInboxRead(ctx, uc, InboxRead{IDs: []string{target}}); err != nil {
		t.Fatalf("marking one read: %v", err)
	}
	after, err := svc.Integrations.Notifications(ctx, uc, "", 50)
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
	if err := svc.Integrations.MarkInboxRead(ctx, uc, InboxRead{}); err != nil {
		t.Fatalf("marking all read: %v", err)
	}
	all, err := svc.Integrations.Notifications(ctx, uc, "", 50)
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

	other, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "someone-else", Password: "correct-horse",
	})
	if err != nil {
		t.Fatalf("creating the other account: %v", err)
	}
	otherUC, err := svc.Grants.UserCtxFor(ctx, other.User)
	if err != nil {
		t.Fatalf("building a user context: %v", err)
	}

	svc.Integrations.EmitNotificationFor(ctx, "review-ready", "Ready for review", "entry", "",
		[]string{uc.ID, otherUC.ID})
	mine, err := svc.Integrations.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("reading the inbox: %v", err)
	}
	if len(mine.Notifications) != 1 {
		t.Fatalf("inbox = %+v, want one row", mine.Notifications)
	}

	wantKind(t, svc.Integrations.DeleteNotification(ctx, otherUC, mine.Notifications[0].ID),
		KindNotFound)
	if err := svc.Integrations.DeleteNotification(ctx, uc, mine.Notifications[0].ID); err != nil {
		t.Fatalf("deleting my own row: %v", err)
	}
	if again, err := svc.Integrations.Notifications(ctx, uc, "", 50); err != nil ||
		len(again.Notifications) != 0 {
		t.Fatalf("inbox = %+v (%v), want empty", again.Notifications, err)
	}
	// Clearing mine leaves theirs standing.
	if err := svc.Integrations.ClearNotifications(ctx, uc); err != nil {
		t.Fatalf("clearing: %v", err)
	}
	theirs, err := svc.Integrations.Notifications(ctx, otherUC, "", 50)
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
	svc.Integrations.EmitNotificationFor(ctx, "import-completed", "Imported", "now", "", []string{uc.ID})
	now := time.Now()
	if n, err := svc.db.PruneNotifications(ctx, now.Add(time.Hour).UnixNano(), 0, nil); err != nil {
		t.Fatalf("pruning by age: %v", err)
	} else if n != 1 {
		t.Fatalf("pruned %d rows by age, want the one row", n)
	}
	if after, err := svc.Integrations.Notifications(ctx, uc, "", 50); err != nil ||
		len(after.Notifications) != 0 {
		t.Fatalf("inbox = %+v (%v), want empty after the horizon passed",
			after.Notifications, err)
	}
	// And the cap, with nothing old enough to age out.
	for range 4 {
		svc.Integrations.EmitNotificationFor(ctx, "import-completed", "Imported", "again", "", []string{uc.ID})
		time.Sleep(time.Millisecond)
	}
	if n, err := svc.db.PruneNotifications(ctx, now.Add(-time.Hour).UnixNano(), 2, nil); err != nil {
		t.Fatalf("pruning by cap: %v", err)
	} else if n != 2 {
		t.Fatalf("pruned %d rows by cap, want the two oldest", n)
	}
	left, err := svc.Integrations.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatalf("re-reading: %v", err)
	}
	if len(left.Notifications) != 2 {
		t.Fatalf("inbox = %+v, want the newest two", left.Notifications)
	}
}

// An open review or sign-up row is live state, not history: the prune
// spares it past the horizon and past the cap, and takes it once resolved.
func TestThePruneSparesOpenQueueRows(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.Integrations.recountNotification(ctx, uc.ID, "review-ready", reviewInboxKey, "1 waiting for review", "", 1, false)
	if err := svc.db.InsertNotification(ctx, wdb.Notification{
		ID: "nf-signup", UserID: uc.ID, Event: "signup-requested", Title: "Sign-up",
		DedupeKey: signupNotifyKey("us-someone"), CreatedNS: time.Now().UnixNano(),
	}); err != nil {
		t.Fatal(err)
	}
	svc.Integrations.EmitNotificationFor(ctx, "import-completed", "Imported", "old", "", []string{uc.ID})
	// Every row past the horizon.
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE notifications SET created_at_ns = 1, bumped_at_ns = 1`); err != nil {
		t.Fatal(err)
	}
	events := func() []string {
		t.Helper()
		page, err := svc.Integrations.Notifications(ctx, uc, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, n := range page.Notifications {
			out = append(out, n.Event)
		}
		slices.Sort(out)
		return out
	}
	svc.Integrations.PruneNotifications(ctx)
	if got := events(); !slices.Equal(got, []string{"review-ready", "signup-requested"}) {
		t.Fatalf("past the horizon the inbox holds %v, want the two open queue rows", got)
	}
	// Past the cap: a full inbox of newer rows.
	now := time.Now().UnixNano()
	if _, err := svc.db.Writer().ExecContext(ctx, `
		WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?)
		INSERT INTO notifications (id, user_id, event, title, created_at_ns, bumped_at_ns)
		SELECT 'nf-filler-' || i, ?, 'import-completed', 'Imported', ? + i, ? + i FROM n`,
		notificationPerUserCap, uc.ID, now, now); err != nil {
		t.Fatal(err)
	}
	svc.Integrations.PruneNotifications(ctx)
	var open int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM notifications WHERE event IN ('review-ready', 'signup-requested')`).Scan(&open); err != nil || open != 2 {
		t.Fatalf("past the cap %d open queue rows are left (%v), want both", open, err)
	}
	svc.Integrations.resolveNotifications(ctx, wdb.NotificationResolve{UserIDs: []string{uc.ID}, Key: reviewInboxKey})
	svc.Integrations.PruneNotifications(ctx)
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM notifications WHERE event = 'review-ready'`).Scan(&open); err != nil || open != 0 {
		t.Errorf("a resolved review row is kept (%d, %v), want it pruned", open, err)
	}
}

// openAcquired opens one acquired entry as an acquisition does: pending,
// identifying, queued for the identify worker.
func openAcquired(t *testing.T, ctx context.Context, svc *Library, uploader, title string) string {
	t.Helper()
	id, err := svc.Ingest.openReviewEntry(ctx, wdb.ReviewEntry{
		Kind: reviewKindImport, MediaType: "music", Origin: reviewOriginAcquire,
		UploadedBy: uploader, Title: title, Artist: "Test Artist",
	}, reviewPayload{}, true)
	if err != nil {
		t.Fatal(err)
	}
	return id
}

// drainIdentify runs the identify worker until its queue is empty.
func drainIdentify(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	for n := 0; svc.Ingest.DrainMatchQueue(ctx); n++ {
		if n > 50 {
			t.Fatal("the identify queue never drained")
		}
	}
}

// eventRows is the caller's inbox rows of one event.
func eventRows(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, event string) []InboxNotification {
	t.Helper()
	page, err := svc.Integrations.Notifications(ctx, uc, "", 200)
	if err != nil {
		t.Fatal(err)
	}
	var out []InboxNotification
	for _, n := range page.Notifications {
		if n.Event == event {
			out = append(out, n)
		}
	}
	return out
}

// otherAccount is a plain account beside the fixture's administrator.
func otherAccount(t *testing.T, ctx context.Context, svc *Library, name string) *UserCtx {
	t.Helper()
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{Username: name, Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// reviewRow is the caller's one review-ready row, failing on any other
// number of them.
func reviewRow(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) InboxNotification {
	t.Helper()
	rows := eventRows(t, ctx, svc, uc, "review-ready")
	if len(rows) != 1 {
		t.Fatalf("review rows = %+v, want one", rows)
	}
	return rows[0]
}

// markerFor reports whether the caller's stream carries a notification
// marker for row after the event id.
func markerFor(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, after int64, row string) bool {
	t.Helper()
	for _, e := range eventsAfter(t, ctx, svc, uc, after) {
		if e.Kind == eventNotification && e.ItemPID == row {
			return true
		}
	}
	return false
}

// Three acquired items waiting for review are one row in each
// recipient's inbox, the uploader's and every administrator's, counting
// three and naming the newest. Anyone but an administrator counts only
// their own.
func TestAcquiredEntriesFoldIntoOneReviewRow(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	user := otherAccount(t, ctx, svc, "uploader")
	for _, title := range []string{"One", "Two", "Three"} {
		openAcquired(t, ctx, svc, user.ID, title)
	}
	drainIdentify(t, ctx, svc)
	for _, uc := range []*UserCtx{admin, user} {
		row := reviewRow(t, ctx, svc, uc)
		if row.Count != 3 || row.Title != "3 waiting for review" || row.TargetPID != "" ||
			row.Body != "Test Artist: Three finished identification and waits for a decision." {
			t.Fatalf("row for %s = %+v, want three waiting, naming the newest", uc.ID, row)
		}
	}
	other := otherAccount(t, ctx, svc, "another-uploader")
	openAcquired(t, ctx, svc, other.ID, "Theirs")
	drainIdentify(t, ctx, svc)
	for uc, want := range map[*UserCtx]int{admin: 4, user: 3, other: 1} {
		if row := reviewRow(t, ctx, svc, uc); row.Count != want {
			t.Fatalf("row for %s = %+v, want %d", uc.ID, row, want)
		}
	}
	if row := reviewRow(t, ctx, svc, user); row.Body != "Test Artist: Three finished identification and waits for a decision." {
		t.Fatalf("the first uploader's row names %q, want its own newest", row.Body)
	}

	// An administrator's own acquisitions are still one row.
	ctx, svc, admin, _ = openServiceAt(t, t.TempDir(), nil)
	for _, title := range []string{"One", "Two", "Three"} {
		openAcquired(t, ctx, svc, admin.ID, title)
	}
	drainIdentify(t, ctx, svc)
	if row := reviewRow(t, ctx, svc, admin); row.Count != 3 || row.Title != "3 waiting for review" {
		t.Fatalf("row = %+v, want three waiting", row)
	}
}

// The count follows the queue: a fall keeps the read state and the row's
// place, a rise marks it unread and lifts it, a new search adds nothing,
// and the last decision resolves it. Each change marks the stream.
func TestTheReviewRowFollowsTheQueue(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	user := otherAccount(t, ctx, svc, "uploader")
	ids := []string{}
	for _, title := range []string{"One", "Two", "Three"} {
		ids = append(ids, openAcquired(t, ctx, svc, user.ID, title))
	}
	drainIdentify(t, ctx, svc)
	first := reviewRow(t, ctx, svc, user)
	if err := svc.Integrations.MarkInboxRead(ctx, user, InboxRead{}); err != nil {
		t.Fatal(err)
	}

	tail := eventTail(t, ctx, svc, user)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, admin, ids[0], "skip", "", "", false); err != nil {
		t.Fatal(err)
	}
	row := reviewRow(t, ctx, svc, user)
	if row.ID != first.ID || row.Count != 2 || row.ReadAt.IsZero() || !row.UpdatedAt.Equal(first.UpdatedAt) {
		t.Fatalf("after a decision = %+v, want the same row counting 2, still read, not moved", row)
	}
	if row.Title != "2 waiting for review" {
		t.Fatalf("title = %q", row.Title)
	}
	if !markerFor(t, ctx, svc, user, tail, row.ID) {
		t.Fatal("a falling count did not mark the stream")
	}

	tail = eventTail(t, ctx, svc, user)
	ids = append(ids, openAcquired(t, ctx, svc, user.ID, "Four"))
	if row := reviewRow(t, ctx, svc, user); row.Count != 2 {
		t.Fatalf("an entry still identifying counted: %+v", row)
	}
	drainIdentify(t, ctx, svc)
	row = reviewRow(t, ctx, svc, user)
	if row.ID != first.ID || row.Count != 3 || !row.ReadAt.IsZero() || !row.UpdatedAt.After(first.UpdatedAt) {
		t.Fatalf("after an arrival = %+v, want the same row counting 3, unread, moved", row)
	}
	if !markerFor(t, ctx, svc, user, tail, row.ID) {
		t.Fatal("a rising count did not mark the stream")
	}

	// A new search takes the entry out while it runs, a fall that keeps
	// the read state; landing pending again is a rise.
	if err := svc.Integrations.MarkInboxRead(ctx, user, InboxRead{}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Ingest.ReidentifyEntry(ctx, admin, ids[1], ReviewOverrideDTO{}); err != nil {
		t.Fatal(err)
	}
	if mid := reviewRow(t, ctx, svc, user); mid.ID != row.ID || mid.Count != 2 || mid.ReadAt.IsZero() {
		t.Fatalf("while the search runs = %+v, want the same row counting 2, still read", mid)
	}
	drainIdentify(t, ctx, svc)
	again := reviewRow(t, ctx, svc, user)
	if again.ID != row.ID || again.Count != 3 || !again.ReadAt.IsZero() || !again.UpdatedAt.After(row.UpdatedAt) {
		t.Fatalf("after a new search = %+v, want the same row counting 3, unread, risen", again)
	}

	for _, id := range ids[1:] {
		tail = eventTail(t, ctx, svc, user)
		if _, _, err := svc.Ingest.DecideReviewEntry(ctx, admin, id, "skip", "", "", false); err != nil {
			t.Fatal(err)
		}
	}
	row = reviewRow(t, ctx, svc, user)
	if row.ID != first.ID || row.ResolvedAt.IsZero() || row.Count != 1 {
		t.Fatalf("after the last decision = %+v, want the row resolved, keeping its last count", row)
	}
	if !markerFor(t, ctx, svc, user, tail, row.ID) {
		t.Fatal("a resolve did not mark the stream")
	}
	// The administrator never read theirs; resolved, it no longer badges.
	if adminRow := reviewRow(t, ctx, svc, admin); adminRow.ResolvedAt.IsZero() || adminRow.ReadAt.IsZero() {
		t.Fatalf("the administrator's row = %+v, want it resolved too, and read", adminRow)
	}

	// A later arrival starts a new row beside the resolved one.
	openAcquired(t, ctx, svc, user.ID, "Five")
	drainIdentify(t, ctx, svc)
	rows := eventRows(t, ctx, svc, user, "review-ready")
	if len(rows) != 2 || rows[0].ID == first.ID || rows[0].Count != 1 || !rows[0].ResolvedAt.IsZero() {
		t.Fatalf("rows = %+v, want a fresh row over the resolved one", rows)
	}
}

// Only what somebody sent in and what is done identifying reaches the
// inbox: a scan's entry and an entry still identifying add nothing.
func TestScanEntriesAndEntriesStillIdentifyingAddNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	scan := wdb.ReviewEntry{
		ID: newReviewID(), Kind: reviewKindMatch, Status: reviewPending, MediaType: "music",
		Origin: reviewOriginScan, Title: "Scanned", Payload: "{}", CreatedAtNS: time.Now().UnixNano(),
	}
	if err := svc.db.InsertReviewEntry(ctx, scan); err != nil {
		t.Fatal(err)
	}
	svc.Ingest.notifyReview(ctx, scan.ID, "", reviewOriginScan, reviewMayJoin)
	openAcquired(t, ctx, svc, admin.ID, "Still identifying")
	if rows := eventRows(t, ctx, svc, admin, "review-ready"); len(rows) != 0 {
		t.Fatalf("review rows = %+v, want none", rows)
	}
}

// A scan entry's identification never recounts the inbox, whose counts
// it cannot change, though its review marker still goes; an upload's
// recounts.
func TestAScanEntrysIdentificationRunsNoTally(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	var tallies atomic.Int32
	svc.Ingest.reviewTallyHook = func() { tallies.Add(1) }
	open := func(origin string) string {
		e := wdb.ReviewEntry{
			ID: newReviewID(), Kind: reviewKindMatch, Status: reviewPending, MediaType: "music",
			Origin: origin, Title: "Entry", Payload: "{}", Identifying: true, CreatedAtNS: time.Now().UnixNano(),
		}
		if err := svc.db.InsertReviewEntry(ctx, e); err != nil {
			t.Fatal(err)
		}
		return e.ID
	}
	scan := open(reviewOriginScan)
	after := eventTail(t, ctx, svc, admin)
	svc.Ingest.finishIdentifyEmpty(ctx, scan, "")
	if n := tallies.Load(); n != 0 {
		t.Errorf("a scan entry's identification ran %d tallies, want none", n)
	}
	marked := false
	for _, e := range eventsAfter(t, ctx, svc, admin, after) {
		marked = marked || (e.Kind == eventReview && e.ItemPID == scan)
	}
	if !marked {
		t.Error("the scan entry's review marker never went")
	}
	svc.Ingest.finishIdentifyEmpty(ctx, open(reviewOriginUpload), "")
	if tallies.Load() == 0 {
		t.Error("an upload's identification ran no tally, want its inbox recounted")
	}
}

// The row is the queue's, so a restart keeps its count and its id, and
// the next arrival counts on from there.
func TestTheReviewCountSurvivesARestart(t *testing.T) {
	dataDir := t.TempDir()
	ctx, svc, admin, stop := openServiceAt(t, dataDir, nil)
	for _, title := range []string{"One", "Two"} {
		openAcquired(t, ctx, svc, admin.ID, title)
	}
	drainIdentify(t, ctx, svc)
	before := reviewRow(t, ctx, svc, admin)
	stop()

	ctx, svc, admin, _ = openServiceAt(t, dataDir, nil)
	if row := reviewRow(t, ctx, svc, admin); row.ID != before.ID || row.Count != 2 {
		t.Fatalf("after a restart = %+v, want %s counting 2", row, before.ID)
	}
	openAcquired(t, ctx, svc, admin.ID, "Three")
	drainIdentify(t, ctx, svc)
	if row := reviewRow(t, ctx, svc, admin); row.ID != before.ID || row.Count != 3 {
		t.Fatalf("after an arrival = %+v, want %s counting 3", row, before.ID)
	}
}

// An import-completed for the account that sent the files in arrives
// read; folding into a row leaves its read state, so a row unread from
// someone else's import stays unread.
func TestAnOwnImportArrivesReadAndKeepsTheRowsState(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	user := otherAccount(t, ctx, svc, "uploader")
	both := []string{admin.ID, user.ID}
	emit := func(by string) {
		svc.Integrations.EmitNotificationFor(ctx, "import-completed", "Import finished", "by "+by,
			"rv-01JZX5N8QW3F4V9T2B7KD3M9R6", both, NotifyKey("import-completed"), NotifyReadFor(by))
	}
	emit(user.ID)
	mine := eventRows(t, ctx, svc, user, "import-completed")
	theirs := eventRows(t, ctx, svc, admin, "import-completed")
	if len(mine) != 1 || mine[0].ReadAt.IsZero() {
		t.Fatalf("the submitter's rows = %+v, want one, read", mine)
	}
	if len(theirs) != 1 || !theirs[0].ReadAt.IsZero() {
		t.Fatalf("the administrator's rows = %+v, want one, unread", theirs)
	}
	// The administrator's own import folds into a row unread from the
	// user's, which stays unread; the user's row, read, goes unread.
	emit(admin.ID)
	theirs = eventRows(t, ctx, svc, admin, "import-completed")
	if len(theirs) != 1 || theirs[0].Count != 2 || !theirs[0].ReadAt.IsZero() || theirs[0].Body != "by "+admin.ID {
		t.Fatalf("the administrator's rows = %+v, want one counting 2, still unread", theirs)
	}
	mine = eventRows(t, ctx, svc, user, "import-completed")
	if len(mine) != 1 || mine[0].Count != 2 || !mine[0].ReadAt.IsZero() {
		t.Fatalf("the submitter's rows = %+v, want one counting 2, unread from another's import", mine)
	}
	// And the user's own next one leaves it as it is, read once marked.
	if err := svc.Integrations.MarkInboxRead(ctx, user, InboxRead{}); err != nil {
		t.Fatal(err)
	}
	tail := eventTail(t, ctx, svc, user)
	emit(user.ID)
	mine = eventRows(t, ctx, svc, user, "import-completed")
	if len(mine) != 1 || mine[0].Count != 3 || mine[0].ReadAt.IsZero() {
		t.Fatalf("the submitter's rows = %+v, want one counting 3, still read", mine)
	}
	if !markerFor(t, ctx, svc, user, tail, mine[0].ID) {
		t.Fatal("a fold did not mark the stream")
	}
}

// A signup request is one row per administrator naming the account, and
// deciding it resolves every one of them.
func TestDecidingASignupResolvesEveryAdministratorsRow(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "second-admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
		t.Fatal(err)
	}
	decide := map[string]func(id string) error{
		"approve": func(id string) error {
			_, err := svc.Identity.ApproveSignup(ctx, admin, id, SignupApproval{})
			return err
		},
		"reject": func(id string) error { return svc.Identity.RejectSignup(ctx, admin, id) },
		"delete": func(id string) error {
			_, err := svc.Identity.DeleteAccount(ctx, admin, id, AccountDeletion{})
			return err
		},
	}
	for _, how := range []string{"approve", "reject", "delete"} {
		pending, state, err := svc.Identity.Signup(ctx, "pat-"+how, "password123", "", "")
		if err != nil || state != SignupPending {
			t.Fatalf("signup: %v %v", state, err)
		}
		for _, uc := range []*UserCtx{admin, second} {
			var row *InboxNotification
			for _, r := range eventRows(t, ctx, svc, uc, "signup-requested") {
				if r.TargetPID == pending.User.ID {
					row = &r
				}
			}
			if row == nil || !row.ResolvedAt.IsZero() {
				t.Fatalf("%s: %s's row = %+v, want one open row naming the account", how, uc.ID, row)
			}
		}
		if err := decide[how](pending.User.ID); err != nil {
			t.Fatalf("%s: %v", how, err)
		}
		for _, uc := range []*UserCtx{admin, second} {
			for _, r := range eventRows(t, ctx, svc, uc, "signup-requested") {
				if r.TargetPID == pending.User.ID && r.ResolvedAt.IsZero() {
					t.Fatalf("%s: %s's row = %+v, want it resolved", how, uc.ID, r)
				}
			}
		}
	}
}

// Deleting a playlist resolves every row about it, keyed or not; another
// playlist's row stays open.
func TestDeletingAPlaylistResolvesItsRows(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	gone, err := svc.Playlists.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Gone", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}
	kept, err := svc.Playlists.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Kept", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}
	for _, pl := range []Playlist{gone, kept} {
		_, bare, _ := parseAPIPID(pl.PID)
		got, err := svc.lib.Playlists().Get(ctx, bare)
		if err != nil {
			t.Fatal(err)
		}
		svc.Playlists.notifyPlaylistSynced(ctx, uc.ID, got, wdb.PlaylistSyncCounts{Added: 1})
		svc.Playlists.notifyPlaylistSyncDisabled(ctx, uc.ID, got)
	}
	tail := eventTail(t, ctx, svc, uc)
	if err := svc.Playlists.DeletePlaylist(ctx, uc, gone.PID); err != nil {
		t.Fatal(err)
	}
	rows := eventRows(t, ctx, svc, uc, "playlist-synced")
	if len(rows) != 4 {
		t.Fatalf("rows = %+v, want two per playlist", rows)
	}
	for _, r := range rows {
		if (r.TargetPID == gone.PID) == r.ResolvedAt.IsZero() {
			t.Fatalf("row %+v: want resolved exactly when it names the deleted playlist", r)
		}
		if r.TargetPID == gone.PID && !markerFor(t, ctx, svc, uc, tail, r.ID) {
			t.Fatalf("row %s resolved without a marker", r.ID)
		}
	}
}

// Leaving a show resolves the account's rows about it and nobody else's.
func TestUnsubscribingResolvesTheAccountsRowsAboutTheShow(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"})
	sub := f.subscribe(t, "https://feeds.example.com/show.xml", "")
	other := otherAccount(t, f.ctx, f.svc, "listener")
	both := []string{f.uc.ID, other.ID}
	f.svc.Integrations.EmitNotificationFor(f.ctx, "episode-arrived", "New episode", "Episode 000",
		sub.Show.PID, both, NotifyKey("episode-arrived:"+sub.Show.PID))
	f.svc.Integrations.EmitNotificationFor(f.ctx, "feed-disabled", "Podcast feed disabled", "x",
		sub.Show.PID, both)
	if err := f.svc.Podcasts.Unsubscribe(f.ctx, f.uc, sub.Show.PID, false); err != nil {
		t.Fatal(err)
	}
	page, err := f.svc.Integrations.Notifications(f.ctx, f.uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range page.Notifications {
		if r.TargetPID == sub.Show.PID && r.ResolvedAt.IsZero() {
			t.Fatalf("row %+v: want resolved once the account left the show", r)
		}
	}
	page, err = f.svc.Integrations.Notifications(f.ctx, other, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Notifications) != 2 {
		t.Fatalf("the other account's rows = %+v, want both", page.Notifications)
	}
	for _, r := range page.Notifications {
		if !r.ResolvedAt.IsZero() {
			t.Fatalf("the other account's row %+v was resolved", r)
		}
	}
}

// A device's list that stops naming a show the account follows only
// there ends the subscription, and resolves the account's rows about the
// show as an unsubscribe does.
func TestAGpodderListLettingGoOfAShowResolvesItsRows(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, feed := openPodcastFixture(t)
	if res, err := svc.Podcasts.GpodderReplaceDeviceList(ctx, uc, "desk", []string{feed}); err != nil || res.Outcomes[feed] != GpodderLanded {
		t.Fatalf("the desk's first list = %+v (%v)", res, err)
	}
	show := apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc)))
	svc.Integrations.EmitNotificationFor(ctx, "episode-arrived", "New episode", "One",
		show, []string{uc.ID}, NotifyKey("episode-arrived:"+show))
	svc.Integrations.EmitNotificationFor(ctx, "feed-disabled", "Podcast feed disabled", "x", show, []string{uc.ID})
	if res, err := svc.Podcasts.GpodderReplaceDeviceList(ctx, uc, "desk", nil); err != nil || res.Released != 1 {
		t.Fatalf("the desk's empty list = %+v (%v), want the show let go", res, err)
	}
	page, err := svc.Integrations.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var naming []InboxNotification
	for _, r := range page.Notifications {
		if r.TargetPID == show {
			naming = append(naming, r)
		}
	}
	if len(naming) != 2 {
		t.Fatalf("rows naming the show = %+v, want the arrival's and the disabled feed's", naming)
	}
	for _, r := range naming {
		if r.ResolvedAt.IsZero() {
			t.Errorf("row %+v: want resolved once the list let go of the show", r)
		}
	}
}

// A keyed server event folds; the mark-read forms and their refusals.
func TestKeyedServerEventsFoldAndMarkReadForms(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdminFixture(t)
	for range 2 {
		svc.Integrations.EmitServerNotification(ctx, "backup-completed", "Backup completed", "b",
			NotifyKey("backup-completed"))
	}
	if rows := eventRows(t, ctx, svc, uc, "backup-completed"); len(rows) != 1 || rows[0].Count != 2 {
		t.Fatalf("backup rows = %+v, want one counting 2", rows)
	}
	svc.Integrations.EmitNotificationFor(ctx, "playlist-synced", "Synced", "a", "pl-01JZX5N8QW3F4V9T2B7KD3M9R6", []string{uc.ID})
	svc.Integrations.EmitNotificationFor(ctx, "playlist-synced", "Synced", "b", "pl-01JZX5N8QW3F4V9T2B7KD3M9R7", []string{uc.ID})
	for _, bad := range []InboxRead{
		{IDs: []string{"nf-01JZX5N8QW3F4V9T2B7KD3M9R6"}, Events: []string{"playlist-synced"}},
		{TargetPID: "pl-01JZX5N8QW3F4V9T2B7KD3M9R6"},
	} {
		wantKind(t, svc.Integrations.MarkInboxRead(ctx, uc, bad), KindInvalid)
	}
	if err := svc.Integrations.MarkInboxRead(ctx, uc, InboxRead{
		Events: []string{"playlist-synced"}, TargetPID: "pl-01JZX5N8QW3F4V9T2B7KD3M9R6",
	}); err != nil {
		t.Fatal(err)
	}
	for _, r := range eventRows(t, ctx, svc, uc, "playlist-synced") {
		if (r.TargetPID == "pl-01JZX5N8QW3F4V9T2B7KD3M9R6") == r.ReadAt.IsZero() {
			t.Fatalf("row %+v: want read exactly when it names the target", r)
		}
	}
	if err := svc.Integrations.MarkInboxRead(ctx, uc, InboxRead{Events: []string{"backup-completed"}}); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Integrations.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	if page.Unread != 1 {
		t.Fatalf("unread = %d, want the one untouched playlist row", page.Unread)
	}
}

// A submission that declined identification is on its way to importing
// itself, so it waits for nobody until that import stalls.
func TestADeclinedImportCountsOnlyOnceItStalls(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	declined, err := svc.Ingest.openReviewEntry(ctx, wdb.ReviewEntry{
		Kind: reviewKindImport, MediaType: "music", Origin: reviewOriginUpload,
		UploadedBy: admin.ID, Title: "Declined", Artist: "Test Artist",
	}, reviewPayload{}, false)
	if err != nil {
		t.Fatal(err)
	}
	openAcquired(t, ctx, svc, admin.ID, "Other")
	drainIdentify(t, ctx, svc)
	row := reviewRow(t, ctx, svc, admin)
	if row.Count != 1 || row.Title != "1 waiting for review" {
		t.Fatalf("with the declined import in flight = %+v, want only the other entry", row)
	}
	if err := svc.Integrations.MarkInboxRead(ctx, admin, InboxRead{}); err != nil {
		t.Fatal(err)
	}

	yes := true
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, AdminSettingsChange{ReadOnly: &yes}); err != nil {
		t.Fatal(err)
	}
	svc.Ingest.importDeclinedEntry(ctx, declined)
	if e, err := svc.db.ReviewEntryByID(ctx, declined); err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v (%v), want its import stalled", e, err)
	}
	row = reviewRow(t, ctx, svc, admin)
	if row.Count != 2 || !row.ReadAt.IsZero() || row.Title != "2 waiting for review" {
		t.Fatalf("after the import stalled = %+v, want it counted, unread", row)
	}
}

// A stalled declined entry waits for a person: an import that reaches it
// later, as a held-off one released does, leaves it pending.
func TestAStalledDeclinedEntryIsNotImportedLater(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	id, err := svc.Ingest.openReviewEntry(ctx, wdb.ReviewEntry{
		Kind: reviewKindImport, MediaType: "music", Origin: reviewOriginUpload,
		UploadedBy: admin.ID, Title: "Stalled", Artist: "Test Artist",
	}, reviewPayload{}, false)
	if err != nil {
		t.Fatal(err)
	}
	entry, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	svc.Ingest.importStalled(ctx, &entry)
	svc.Ingest.importDeclinedEntry(ctx, id)
	if e, err := svc.db.ReviewEntryByID(ctx, id); err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v (%v), want it still pending for a person", e, err)
	}
}

// A declined entry a stop left before its import ran waits for a person
// after the next start, and counts.
func TestADeclinedEntryStrandedByARestartCountsAfterStartup(t *testing.T) {
	dataDir := t.TempDir()
	ctx, svc, admin, stop := openServiceAt(t, dataDir, nil)
	stranded, err := svc.Ingest.openReviewEntry(ctx, wdb.ReviewEntry{
		Kind: reviewKindImport, MediaType: "music", Origin: reviewOriginUpload,
		UploadedBy: admin.ID, Title: "Stranded", Artist: "Test Artist",
	}, reviewPayload{}, false)
	if err != nil {
		t.Fatal(err)
	}
	openAcquired(t, ctx, svc, admin.ID, "Other")
	drainIdentify(t, ctx, svc)
	if row := reviewRow(t, ctx, svc, admin); row.Count != 1 {
		t.Fatalf("before the restart = %+v, want only the other entry", row)
	}
	stop()

	ctx, svc, admin, _ = openServiceAt(t, dataDir, nil)
	deadline := time.Now().Add(10 * time.Second)
	for {
		row := reviewRow(t, ctx, svc, admin)
		if row.Count == 2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("after the restart = %+v, want the stranded entry counted", row)
		}
		time.Sleep(20 * time.Millisecond)
	}
	e, err := svc.db.ReviewEntryByID(ctx, stranded)
	if err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v (%v), want it pending for a person", e, err)
	}
}

// A declined URL download a stop left between opening its entry and
// importing it is imported after the restart, as the person chose: by its
// task's next run while one is owed, else by the startup pass. Nobody is
// asked to review it.
func TestADeclinedDownloadStrandedByARestartIsImported(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		left string // how the stop leaves the task; ? is the entry
		runs bool   // the task runs again and takes it up
	}{
		{"its task runs again", "", true},
		{"its task failed", `UPDATE tool_tasks SET state = 'failed', finished_at_ns = 1 WHERE ? != ''`, false},
		{"its attempts ran out", `UPDATE tool_tasks SET attempts = 99 WHERE ? != ''`, false},
		{"its task recorded it", `UPDATE tool_tasks SET params = json_set(params, '$.entries', json_array(?))`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dataDir := t.TempDir()
			open := func() (context.Context, *Library, *UserCtx, func()) {
				return openServiceAt(t, dataDir, func(cfg *Config) {
					cfg.Roots[0].Managed = true
					cfg.SourceProviders = []source.Provider{&stagingSource{}}
					cfg.AllowPrivateFeedHosts = true
				})
			}
			ctx, svc, admin, stop := open()
			identify := false
			task, err := svc.Ingest.StartAcquisition(ctx, admin, "https://tube.example/watch?v=one", false, "music", "", "", &identify, nil)
			if err != nil {
				t.Fatal(err)
			}
			// The process stops after the entry opened, before its import.
			svc.Ingest.planHook = func(context.Context, waxbin.AcquiredFile, model.Kind, waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
				panic("the process stopped")
			}
			func() {
				defer func() {
					if recover() == nil {
						t.Fatal("the run did not stop")
					}
				}()
				drainOnce(t, ctx, svc)
			}()
			var entryID string
			if err := svc.db.Reader().QueryRowContext(ctx, `SELECT review_entry_id FROM uploads`).Scan(&entryID); err != nil || entryID == "" {
				t.Fatalf("the download's entry = %q (%v), want one opened", entryID, err)
			}
			if tc.left != "" {
				if _, err := svc.db.Writer().ExecContext(ctx, tc.left, entryID); err != nil {
					t.Fatal(err)
				}
			}
			stop()

			ctx, svc, admin, _ = open()
			// The startup pass runs in the background too; whichever claims
			// the entry, it has taken it up or left it once this returns.
			svc.Ingest.settleStranded(ctx)
			if tc.runs {
				// Left to the task: the pass lists it for no import, and it
				// waits untouched.
				listed, err := svc.db.ReviewEntriesDeclinedInFlight(ctx, time.Now().UnixNano(), toolTaskMaxAttempts)
				if err != nil {
					t.Fatal(err)
				}
				var state string
				if err := svc.db.Reader().QueryRowContext(ctx, `SELECT state FROM uploads`).Scan(&state); err != nil {
					t.Fatal(err)
				}
				if e, err := svc.db.ReviewEntryByID(ctx, entryID); err != nil || slices.Contains(listed, entryID) ||
					e.Status != reviewPending || state == uploadImported {
					t.Fatalf("before the task runs: entry %+v (%v), listed for import %v, download %q; want it left pending for the task",
						e, err, slices.Contains(listed, entryID), state)
				}
				drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
				if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone {
					t.Errorf("task = %s (error %q), want it done", row.State, row.Error)
				}
			}
			// The import marks the download imported before it decides the
			// entry: the wait is for both.
			deadline := time.Now().Add(10 * time.Second)
			var e wdb.ReviewEntry
			for {
				var state string
				if err := svc.db.Reader().QueryRowContext(ctx, `SELECT state FROM uploads`).Scan(&state); err != nil {
					t.Fatal(err)
				}
				if e, err = svc.db.ReviewEntryByID(ctx, entryID); err != nil {
					t.Fatal(err)
				}
				if state == uploadImported && e.Status != reviewPending {
					break
				}
				if time.Now().After(deadline) {
					t.Fatalf("the download is %q and its entry %s, want both imported", state, e.Status)
				}
				time.Sleep(20 * time.Millisecond)
			}
			var payload reviewPayload
			if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
				t.Fatal(err)
			}
			if rows := eventRows(t, ctx, svc, admin, "review-ready"); e.Status != reviewAsIs || payload.ImportStalled || len(rows) != 0 {
				t.Errorf("entry %s (stalled %v), review rows %+v; want it imported as-is and nobody asked", e.Status, payload.ImportStalled, rows)
			}
		})
	}
}

// Every account holding an open review row is recounted, in the scope it
// has now: a demoted administrator counts only its own uploads, and one
// with none sees its row resolve.
func TestADemotedAdministratorsRowIsRecountedToItsOwnScope(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	demote := map[string]*UserCtx{}
	for _, name := range []string{"keeps-one", "keeps-none"} {
		acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
			Username: name, Password: "correct-horse", Roles: []string{"admin"},
		})
		if err != nil {
			t.Fatal(err)
		}
		uc, err := svc.Grants.UserCtxFor(ctx, acct.User)
		if err != nil {
			t.Fatal(err)
		}
		demote[name] = uc
	}
	user := otherAccount(t, ctx, svc, "uploader")
	openAcquired(t, ctx, svc, demote["keeps-one"].ID, "Own")
	openAcquired(t, ctx, svc, user.ID, "Theirs")
	drainIdentify(t, ctx, svc)
	for _, uc := range demote {
		if row := reviewRow(t, ctx, svc, uc); row.Count != 2 {
			t.Fatalf("%s's row = %+v, want the whole queue", uc.ID, row)
		}
	}
	for _, uc := range demote {
		if _, err := svc.Identity.UpdateAccount(ctx, uc.ID, AccountUpdate{Roles: []string{"user"}}); err != nil {
			t.Fatal(err)
		}
	}
	// The next change to the queue, which reaches neither of them.
	openAcquired(t, ctx, svc, user.ID, "More")
	drainIdentify(t, ctx, svc)
	if row := reviewRow(t, ctx, svc, demote["keeps-one"]); row.Count != 1 || !row.ResolvedAt.IsZero() {
		t.Fatalf("the demoted uploader's row = %+v, want its own one entry", row)
	}
	if row := reviewRow(t, ctx, svc, demote["keeps-none"]); row.ResolvedAt.IsZero() {
		t.Fatalf("the demoted reader's row = %+v, want it resolved", row)
	}
	if row := reviewRow(t, ctx, svc, admin); row.Count != 3 {
		t.Fatalf("the administrator's row = %+v, want the whole queue", row)
	}
}

// An auto-apply the busy catalog holds back is in flight: it waits for
// nobody, and applies itself once the catalog frees.
func TestAnAutoApplyWaitingForTheCatalogCountsNothing(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	for _, r := range eventRows(t, ctx, svc, uc, "review-ready") {
		if r.ResolvedAt.IsZero() {
			t.Fatalf("while the apply waits = %+v, want no open review row", r)
		}
	}
	busy.Store(false)
	waitFor(t, func() bool {
		e, err := svc.db.ReviewEntryByID(ctx, id)
		return err == nil && e.Status == reviewAutoApplied
	}, "the apply should go once the catalog frees")
	for _, r := range eventRows(t, ctx, svc, uc, "review-ready") {
		if r.ResolvedAt.IsZero() {
			t.Fatalf("after the apply = %+v, want no open review row", r)
		}
	}
}

// A decision that fails after taking the entry from an auto-apply waiting
// for the catalog leaves it waiting for a person, and counted.
func TestAFailedDecisionOnAWaitingAutoApplyCountsTheEntry(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name      string
		readOnly  bool
		suggested bool
	}{
		{"a read-only library", true, false},
		{"a refused suggestion", false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
			var busy atomic.Bool
			id := waitingBest(t, ctx, svc, uc, &busy)
			if tc.readOnly {
				yes := true
				if _, err := svc.Settings.AdminSettingsPut(ctx, uc, AdminSettingsChange{ReadOnly: &yes}); err != nil {
					t.Fatal(err)
				}
			}
			if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", tc.suggested); err == nil {
				t.Fatal("the decision went, want it refused")
			}
			if row := reviewRow(t, ctx, svc, uc); row.Count != 1 || !row.ResolvedAt.IsZero() {
				t.Fatalf("after the failed decision = %+v, want the entry counted", row)
			}
		})
	}
}

// A review row the account deleted stays gone through a decision; only
// an entry joining its count starts one again.
func TestADeletedReviewRowComesBackOnlyOnAnArrival(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), nil)
	ids := []string{}
	for _, title := range []string{"One", "Two", "Three"} {
		ids = append(ids, openAcquired(t, ctx, svc, admin.ID, title))
	}
	drainIdentify(t, ctx, svc)
	if err := svc.Integrations.DeleteNotification(ctx, admin, reviewRow(t, ctx, svc, admin).ID); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, admin, ids[0], "skip", "", "", false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Ingest.ReidentifyEntry(ctx, admin, ids[1], ReviewOverrideDTO{}); err != nil {
		t.Fatal(err)
	}
	if rows := eventRows(t, ctx, svc, admin, "review-ready"); len(rows) != 0 {
		t.Fatalf("after a decision and a new search = %+v, want the deleted row to stay gone", rows)
	}
	openAcquired(t, ctx, svc, admin.ID, "Four")
	drainIdentify(t, ctx, svc)
	if row := reviewRow(t, ctx, svc, admin); row.Count != 3 || !row.ReadAt.IsZero() {
		t.Fatalf("after arrivals = %+v, want a new row counting 3", row)
	}
}

// The keyed events fold at the places that emit them.
func TestKeyedEventsFoldWhereTheyAreEmitted(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	user := otherAccount(t, ctx, svc, "uploader")
	entry := func(title string) *wdb.ReviewEntry {
		e := wdb.ReviewEntry{
			ID: newReviewID(), Kind: reviewKindImport, Status: reviewAutoApplied, MediaType: "music",
			Origin: reviewOriginUpload, UploadedBy: user.ID, Title: title, Payload: "{}",
			CreatedAtNS: time.Now().UnixNano(),
		}
		if err := svc.db.InsertReviewEntry(ctx, e); err != nil {
			t.Fatal(err)
		}
		return &e
	}
	svc.Ingest.notifyIdentified(ctx, entry("Identified").ID)
	svc.Ingest.notifyImported(ctx, entry("Declined"))
	if mine := eventRows(t, ctx, svc, user, "import-completed"); len(mine) != 1 || mine[0].Count != 2 || mine[0].ReadAt.IsZero() {
		t.Errorf("the submitter's import rows = %+v, want one counting 2, read", mine)
	}
	if theirs := eventRows(t, ctx, svc, admin, "import-completed"); len(theirs) != 1 || theirs[0].Count != 2 || !theirs[0].ReadAt.IsZero() {
		t.Errorf("the administrator's import rows = %+v, want one counting 2, unread", theirs)
	}

	pod := &model.Podcast{PID: "01JZX5N8QW3F4V9T2B7KD3M9R6", Title: "Show"}
	for _, title := range []string{"Episode 1", "Episode 2"} {
		svc.Podcasts.notifyArrivals(ctx, pod, []wdb.Subscription{{UserID: user.ID}},
			[]*model.Episode{{Title: title, CreatedAt: 10}}, 0)
	}
	if rows := eventRows(t, ctx, svc, user, "episode-arrived"); len(rows) != 1 || rows[0].Count != 2 {
		t.Errorf("episode rows = %+v, want one counting 2", rows)
	}

	pl := &model.Playlist{PID: "01JZX5N8QW3F4V9T2B7KD3M9R6", Name: "Synced"}
	for range 2 {
		svc.Playlists.notifyPlaylistSynced(ctx, user.ID, pl, wdb.PlaylistSyncCounts{Added: 1})
	}
	if rows := eventRows(t, ctx, svc, user, "playlist-synced"); len(rows) != 1 || rows[0].Count != 2 {
		t.Errorf("playlist rows = %+v, want one counting 2", rows)
	}

	b := newBackups(svc.db, testCatalog{}, svc.Audit, svc.Integrations, svc.log, t.TempDir(), nil)
	b.catalogStamp = func(context.Context) (uint32, error) { return testCatalogStamp, nil }
	for range 2 {
		createAndRun(t, b)
	}
	if rows := eventRows(t, ctx, svc, admin, "backup-completed"); len(rows) != 1 || rows[0].Count != 2 {
		t.Errorf("backup rows = %+v, want one counting 2", rows)
	}
}

// Leaving a show resolves its rows even when settling the account's
// parked asks fails after the subscription is gone.
func TestUnsubscribingResolvesEvenWhenTheParksFail(t *testing.T) {
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"})
	sub := f.subscribe(t, "https://feeds.example.com/parks.xml", "")
	f.svc.Integrations.EmitNotificationFor(f.ctx, "feed-disabled", "Podcast feed disabled", "x",
		sub.Show.PID, []string{f.uc.ID})
	var once sync.Once
	testHookMembership = func(step string) {
		if step == "removed" {
			once.Do(func() {
				if _, err := f.svc.db.Writer().Exec(`DROP TABLE gpodder_pending`); err != nil {
					t.Error(err)
				}
			})
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	if err := f.svc.Podcasts.Unsubscribe(f.ctx, f.uc, sub.Show.PID, false); err == nil {
		t.Fatal("the unsubscribe stood, want the parks' failure")
	}
	for _, r := range eventRows(t, f.ctx, f.svc, f.uc, "feed-disabled") {
		if r.ResolvedAt.IsZero() {
			t.Fatalf("row %+v: want it resolved once the subscription was removed", r)
		}
	}
}
