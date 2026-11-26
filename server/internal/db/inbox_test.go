package db

import (
	"context"
	"fmt"
	"slices"
	"testing"
)

func inboxFixture(t *testing.T) (*DB, context.Context) {
	t.Helper()
	return openTwoUsersTest(t), context.Background()
}

func listAll(t *testing.T, d *DB, ctx context.Context, userID string) []Notification {
	t.Helper()
	rows, err := d.ListNotifications(ctx, userID, 0, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	return rows
}

func upsert(t *testing.T, d *DB, ctx context.Context, n Notification, f NotificationFold) (string, bool) {
	t.Helper()
	id, changed, err := d.UpsertNotification(ctx, n, f)
	if err != nil {
		t.Fatal(err)
	}
	return id, changed
}

// A fold keeps the row's id and createdAt, counts, takes the new wording,
// marks it unread and lifts it to the top of the listing.
func TestAnUpsertedRowKeepsItsIDAndRises(t *testing.T) {
	d, ctx := inboxFixture(t)
	for i, id := range []string{"nf-1", "nf-3"} {
		if err := d.InsertNotification(ctx, Notification{ID: id, UserID: "us-1", Event: "job-finished", CreatedNS: int64(100 * (2*i + 1))}); err != nil {
			t.Fatal(err)
		}
	}
	key := Notification{ID: "nf-2", UserID: "us-1", Event: "backup-completed", DedupeKey: "backup-completed", Title: "first", CreatedNS: 200}
	if id, changed := upsert(t, d, ctx, key, NotificationFold{}); id != "nf-2" || !changed {
		t.Fatalf("insert = %q %v, want nf-2 written", id, changed)
	}
	if err := d.MarkNotificationsRead(ctx, "us-1", nil, 250); err != nil {
		t.Fatal(err)
	}
	again := key
	again.ID, again.Title, again.CreatedNS = "nf-9", "second", 400
	if id, _ := upsert(t, d, ctx, again, NotificationFold{}); id != "nf-2" {
		t.Fatalf("fold answered %q, want the standing row nf-2", id)
	}
	rows := listAll(t, d, ctx, "us-1")
	if len(rows) != 3 {
		t.Fatalf("rows = %+v, want three", rows)
	}
	top := rows[0]
	if top.ID != "nf-2" || top.Count != 2 || top.Title != "second" || top.CreatedNS != 200 ||
		top.BumpedNS != 400 || top.ReadNS != 0 {
		t.Fatalf("top = %+v, want nf-2 folded twice, unread, risen", top)
	}
	if rows[1].ID != "nf-3" || rows[2].ID != "nf-1" {
		t.Fatalf("order = %s %s, want nf-3 then nf-1 below", rows[1].ID, rows[2].ID)
	}
}

// Paging across a fold: a row the fold did not move is seen exactly once,
// the folded one at most once.
func TestPagingAcrossABumpNeitherRepeatsNorSkips(t *testing.T) {
	d, ctx := inboxFixture(t)
	for i := range 6 {
		n := Notification{ID: fmt.Sprintf("nf-%d", i), UserID: "us-1", Event: "playlist-synced",
			DedupeKey: fmt.Sprintf("playlist-synced:pl-%d", i), CreatedNS: int64(100 * (i + 1))}
		upsert(t, d, ctx, n, NotificationFold{})
	}
	first, err := d.ListNotifications(ctx, "us-1", 0, "", 2)
	if err != nil {
		t.Fatal(err)
	}
	// The oldest row, not yet read, folds and rises.
	upsert(t, d, ctx, Notification{ID: "nf-x", UserID: "us-1", Event: "playlist-synced",
		DedupeKey: "playlist-synced:pl-0", CreatedNS: 1000}, NotificationFold{})
	seen := map[string]int{}
	for _, r := range first {
		seen[r.ID]++
	}
	last := first[len(first)-1]
	for {
		page, err := d.ListNotifications(ctx, "us-1", last.BumpedNS, last.ID, 2)
		if err != nil {
			t.Fatal(err)
		}
		if len(page) == 0 {
			break
		}
		for _, r := range page {
			seen[r.ID]++
		}
		last = page[len(page)-1]
	}
	for i := 1; i < 6; i++ {
		if id := fmt.Sprintf("nf-%d", i); seen[id] != 1 {
			t.Errorf("%s seen %d times, want once", id, seen[id])
		}
	}
	if seen["nf-0"] > 1 {
		t.Errorf("the folded row was seen %d times, want at most once", seen["nf-0"])
	}
}

// A recount moves the row and marks it unread on a rise only; a fall
// keeps the read state and the place, and an unchanged count writes
// nothing.
func TestARecountRisesUnreadAndFallsInPlace(t *testing.T) {
	d, ctx := inboxFixture(t)
	n := Notification{ID: "nf-1", UserID: "us-1", Event: "review-ready", DedupeKey: "review-ready", Title: "3", Count: 3, CreatedNS: 100}
	upsert(t, d, ctx, n, NotificationFold{Recount: true})
	if err := d.MarkNotificationsRead(ctx, "us-1", nil, 150); err != nil {
		t.Fatal(err)
	}
	fall := n
	fall.ID, fall.Title, fall.Count, fall.CreatedNS = "nf-2", "2", 2, 200
	if _, changed := upsert(t, d, ctx, fall, NotificationFold{Recount: true}); !changed {
		t.Fatal("a fall changed nothing")
	}
	row := listAll(t, d, ctx, "us-1")[0]
	if row.ID != "nf-1" || row.Count != 2 || row.ReadNS != 150 || row.BumpedNS != 100 || row.Title != "2" {
		t.Fatalf("after a fall = %+v, want count 2, still read, not moved", row)
	}
	same := fall
	same.CreatedNS = 250
	if _, changed := upsert(t, d, ctx, same, NotificationFold{Recount: true}); changed {
		t.Fatal("an unchanged recount wrote the row")
	}
	rise := n
	rise.ID, rise.Title, rise.Count, rise.CreatedNS = "nf-3", "4", 4, 300
	upsert(t, d, ctx, rise, NotificationFold{Recount: true})
	row = listAll(t, d, ctx, "us-1")[0]
	if row.ID != "nf-1" || row.Count != 4 || row.ReadNS != 0 || row.BumpedNS != 300 {
		t.Fatalf("after a rise = %+v, want count 4, unread, moved", row)
	}
}

// A read fold files a new row read and leaves a standing row's read state
// alone, unread included.
func TestAReadFoldKeepsTheReadState(t *testing.T) {
	d, ctx := inboxFixture(t)
	n := Notification{ID: "nf-1", UserID: "us-1", Event: "import-completed", DedupeKey: "import-completed", CreatedNS: 100}
	upsert(t, d, ctx, n, NotificationFold{Read: true})
	if row := listAll(t, d, ctx, "us-1")[0]; row.ReadNS == 0 {
		t.Fatalf("row = %+v, want it filed read", row)
	}
	// Someone else's import marks it unread; the account's own does not
	// read it.
	n.CreatedNS = 200
	upsert(t, d, ctx, n, NotificationFold{})
	n.CreatedNS = 300
	upsert(t, d, ctx, n, NotificationFold{Read: true})
	row := listAll(t, d, ctx, "us-1")[0]
	if row.Count != 3 || row.ReadNS != 0 || row.BumpedNS != 300 {
		t.Fatalf("row = %+v, want count 3, still unread, risen", row)
	}
}

// A resolve settles the rows it names, keeps their count, and lets the
// next occurrence start a new row; clearing resolved rows leaves the rest.
func TestResolvedRowsStandAsHistory(t *testing.T) {
	d, ctx := inboxFixture(t)
	for _, uid := range []string{"us-1", "us-2"} {
		upsert(t, d, ctx, Notification{ID: "nf-a" + uid, UserID: uid, Event: "signup-requested",
			DedupeKey: "signup-requested:us-9", TargetPID: "us-9", CreatedNS: 100}, NotificationFold{})
	}
	if err := d.InsertNotification(ctx, Notification{ID: "nf-pl", UserID: "us-1", Event: "playlist-synced", TargetPID: "pl-1", CreatedNS: 150}); err != nil {
		t.Fatal(err)
	}
	got, err := d.ResolveNotifications(ctx, NotificationResolve{Key: "signup-requested:us-9"}, 500)
	if err != nil || len(got) != 2 {
		t.Fatalf("resolved %+v (%v), want both accounts' rows", got, err)
	}
	if again, err := d.ResolveNotifications(ctx, NotificationResolve{Key: "signup-requested:us-9"}, 600); err != nil || len(again) != 0 {
		t.Fatalf("a second resolve settled %+v (%v), want nothing", again, err)
	}
	if got, err := d.ResolveNotifications(ctx, NotificationResolve{TargetPID: "pl-1", UserIDs: []string{"us-2"}}, 500); err != nil || len(got) != 0 {
		t.Fatalf("resolve of another account = %+v (%v), want nothing", got, err)
	}
	if got, err := d.ResolveNotifications(ctx, NotificationResolve{TargetPID: "pl-1"}, 500); err != nil || len(got) != 1 || got[0].ID != "nf-pl" {
		t.Fatalf("resolve by target = %+v (%v), want the playlist row", got, err)
	}
	if _, err := d.ResolveNotifications(ctx, NotificationResolve{}, 500); err == nil {
		t.Fatal("a resolve naming nothing was taken")
	}
	// The partial index covers unresolved rows only.
	upsert(t, d, ctx, Notification{ID: "nf-b", UserID: "us-1", Event: "signup-requested",
		DedupeKey: "signup-requested:us-9", CreatedNS: 700}, NotificationFold{})
	rows := listAll(t, d, ctx, "us-1")
	if len(rows) != 3 || rows[0].ID != "nf-b" || rows[0].ResolvedNS != 0 || rows[0].Count != 1 {
		t.Fatalf("rows = %+v, want a fresh row over the resolved one", rows)
	}
	if err := d.ClearResolvedNotifications(ctx, "us-1"); err != nil {
		t.Fatal(err)
	}
	if rows := listAll(t, d, ctx, "us-1"); len(rows) != 1 || rows[0].ID != "nf-b" {
		t.Fatalf("after clearing resolved = %+v, want only the open row", rows)
	}
	if rows := listAll(t, d, ctx, "us-2"); len(rows) != 1 || rows[0].ResolvedNS != 500 {
		t.Fatalf("the other account's rows = %+v, want its resolved row kept", rows)
	}
}

// A resolve marks an unread row read at the resolve and leaves a read
// row's time as it was.
func TestAResolveMarksTheRowRead(t *testing.T) {
	d, ctx := inboxFixture(t)
	for _, n := range []Notification{
		{ID: "nf-unread", UserID: "us-1", Event: "playlist-synced", TargetPID: "pl-1", CreatedNS: 100},
		{ID: "nf-read", UserID: "us-1", Event: "feed-disabled", TargetPID: "pl-1", CreatedNS: 110, ReadNS: 200},
	} {
		if err := d.InsertNotification(ctx, n); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.ResolveNotifications(ctx, NotificationResolve{TargetPID: "pl-1"}, 500); err != nil {
		t.Fatal(err)
	}
	want := map[string]int64{"nf-unread": 500, "nf-read": 200}
	for _, r := range listAll(t, d, ctx, "us-1") {
		if r.ResolvedNS != 500 || r.ReadNS != want[r.ID] {
			t.Errorf("row %s read at %d, resolved at %d; want read at %d, resolved at 500", r.ID, r.ReadNS, r.ResolvedNS, want[r.ID])
		}
	}
	if n, err := d.UnreadNotificationCount(ctx, "us-1"); err != nil || n != 0 {
		t.Errorf("unread = %d (%v), want none", n, err)
	}
}

// Marking by event settles every unread row of the events, narrowed by
// target when one is named.
func TestMarkReadByEvent(t *testing.T) {
	d, ctx := inboxFixture(t)
	for _, n := range []Notification{
		{ID: "nf-1", UserID: "us-1", Event: "playlist-synced", TargetPID: "pl-1", CreatedNS: 1},
		{ID: "nf-2", UserID: "us-1", Event: "playlist-synced", TargetPID: "pl-2", CreatedNS: 2},
		{ID: "nf-3", UserID: "us-1", Event: "job-finished", CreatedNS: 3},
		{ID: "nf-4", UserID: "us-2", Event: "playlist-synced", TargetPID: "pl-1", CreatedNS: 4},
	} {
		if err := d.InsertNotification(ctx, n); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.MarkNotificationEventsRead(ctx, "us-1", []string{"playlist-synced"}, "pl-1", 10); err != nil {
		t.Fatal(err)
	}
	read := func(uid string) map[string]bool {
		out := map[string]bool{}
		for _, r := range listAll(t, d, ctx, uid) {
			out[r.ID] = r.ReadNS != 0
		}
		return out
	}
	if got := read("us-1"); !got["nf-1"] || got["nf-2"] || got["nf-3"] {
		t.Fatalf("read = %v, want only nf-1", got)
	}
	if err := d.MarkNotificationEventsRead(ctx, "us-1", []string{"playlist-synced", "job-finished"}, "", 20); err != nil {
		t.Fatal(err)
	}
	if got := read("us-1"); !got["nf-2"] || !got["nf-3"] {
		t.Fatalf("read = %v, want every row of both events", got)
	}
	if got := read("us-2"); got["nf-4"] {
		t.Fatal("another account's row was marked")
	}
}

// Pruning reads the latest occurrence: a row created long ago that keeps
// folding stays, and the cap drops what the listing shows last.
func TestPruneRidesTheLatestOccurrence(t *testing.T) {
	d, ctx := inboxFixture(t)
	upsert(t, d, ctx, Notification{ID: "nf-old", UserID: "us-1", Event: "backup-completed", DedupeKey: "backup-completed", CreatedNS: 10}, NotificationFold{})
	for i, ns := range []int64{200, 300, 400} {
		if err := d.InsertNotification(ctx, Notification{ID: fmt.Sprintf("nf-%d", i), UserID: "us-1", Event: "job-finished", CreatedNS: ns}); err != nil {
			t.Fatal(err)
		}
	}
	upsert(t, d, ctx, Notification{ID: "nf-x", UserID: "us-1", Event: "backup-completed", DedupeKey: "backup-completed", CreatedNS: 500}, NotificationFold{})
	if n, err := d.PruneNotifications(ctx, 100, 0, nil); err != nil || n != 0 {
		t.Fatalf("pruned %d (%v) by age, want the folded row kept", n, err)
	}
	if n, err := d.PruneNotifications(ctx, 0, 2, nil); err != nil || n != 2 {
		t.Fatalf("pruned %d (%v) by cap, want two", n, err)
	}
	rows := listAll(t, d, ctx, "us-1")
	if len(rows) != 2 || rows[0].ID != "nf-old" || rows[1].ID != "nf-2" {
		t.Fatalf("rows = %+v, want the folded row and the newest other", rows)
	}
}

// The rows of the events spared stay while unresolved, past the horizon
// and past the cap; resolved, and every other row, they go as before.
func TestPruneSparesUnresolvedRowsOfTheEventsNamed(t *testing.T) {
	d, ctx := inboxFixture(t)
	for _, n := range []Notification{
		{ID: "nf-review", UserID: "us-1", Event: "review-ready", DedupeKey: "review-ready", CreatedNS: 10},
		{ID: "nf-signup", UserID: "us-1", Event: "signup-requested", DedupeKey: "signup-requested:us-9", CreatedNS: 20},
		{ID: "nf-cleared", UserID: "us-1", Event: "review-ready", CreatedNS: 30, ResolvedNS: 35},
		{ID: "nf-synced", UserID: "us-1", Event: "playlist-synced", DedupeKey: "playlist-synced:pl-1", CreatedNS: 40},
		{ID: "nf-200", UserID: "us-1", Event: "job-finished", CreatedNS: 200},
		{ID: "nf-300", UserID: "us-1", Event: "job-finished", CreatedNS: 300},
		{ID: "nf-400", UserID: "us-1", Event: "job-finished", CreatedNS: 400},
	} {
		if err := d.InsertNotification(ctx, n); err != nil {
			t.Fatal(err)
		}
	}
	spare := []string{"review-ready", "signup-requested"}
	ids := func() []string {
		var out []string
		for _, r := range listAll(t, d, ctx, "us-1") {
			out = append(out, r.ID)
		}
		return out
	}
	if n, err := d.PruneNotifications(ctx, 100, 0, spare); err != nil || n != 2 {
		t.Fatalf("pruned %d (%v) by age, want the resolved review row and the synced row", n, err)
	}
	if got := ids(); !slices.Equal(got, []string{"nf-400", "nf-300", "nf-200", "nf-signup", "nf-review"}) {
		t.Fatalf("after the horizon rows = %v", got)
	}
	if n, err := d.PruneNotifications(ctx, 0, 2, spare); err != nil || n != 1 {
		t.Fatalf("pruned %d (%v) by cap, want the oldest other row", n, err)
	}
	if got := ids(); !slices.Equal(got, []string{"nf-400", "nf-300", "nf-signup", "nf-review"}) {
		t.Fatalf("after the cap rows = %v", got)
	}
}
