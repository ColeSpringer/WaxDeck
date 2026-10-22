package db

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"
)

func attach(t *testing.T, d *DB, show, holder string) bool {
	t.Helper()
	created, err := d.AttachSubscription(context.Background(),
		Subscription{UserID: "us-A", ShowPID: show, Folder: "kept", CreatedAtNS: 1, UpdatedAtNS: 1}, holder,
		"https://feeds.example/"+show+".xml")
	if err != nil {
		t.Fatal(err)
	}
	return created
}

// A show stays followed while anyone holds it: attaching holds it and
// creates the row once, one holder's release leaves the others, and the
// last release or a remove takes the row and its holds together.
func TestGpodderHolds(t *testing.T) {
	d, ctx := gpodderFixture(t)
	if !attach(t, d, "pc-1", "") || attach(t, d, "pc-1", "phone") || attach(t, d, "pc-1", "phone") {
		t.Fatal("attaching a followed show created its row again")
	}
	attach(t, d, "pc-2", "phone")
	attach(t, d, "pc-3", "desk")
	held, err := d.GpodderHeldBy(ctx, "us-A", "phone")
	if err != nil || !slices.Equal(held, []string{"pc-1", "pc-2"}) {
		t.Fatalf("held by the phone = %v (%v), want pc-1 and pc-2", held, err)
	}
	if gone, _, err := d.ReleaseGpodderHold(ctx, "us-A", "pc-1", "phone"); err != nil || gone {
		t.Fatalf("releasing the phone's pc-1 took the row = %v (%v), want the apps' hold to keep it", gone, err)
	}
	if gone, _, err := d.ReleaseGpodderHold(ctx, "us-A", "pc-2", "phone"); err != nil || !gone {
		t.Fatalf("releasing the phone's pc-2, its last hold, took the row = %v (%v), want it gone", gone, err)
	}
	if sub, err := d.SubscriptionFor(ctx, "us-A", "pc-1"); err != nil || sub.Folder != "kept" {
		t.Fatalf("pc-1 = %+v (%v), want it kept with its settings", sub, err)
	}
	if existed, _, err := d.RemoveSubscription(ctx, "us-A", "pc-1"); err != nil || !existed {
		t.Fatalf("removing pc-1 = %v (%v)", existed, err)
	}
	if held, _ := d.GpodderHeldBy(ctx, "us-A", ""); len(held) != 0 {
		t.Errorf("the apps' holds after the remove = %v", held)
	}
	if existed, _, err := d.RemoveSubscription(ctx, "us-A", "pc-1"); err != nil || existed {
		t.Errorf("removing it again = %v (%v), want nothing there", existed, err)
	}
	if held, _ := d.GpodderHeldBy(ctx, "us-A", "desk"); !slices.Equal(held, []string{"pc-3"}) {
		t.Errorf("the desk's holds = %v, want its own show kept", held)
	}
}

// A parked feed keeps its first ask and gains every device that names it,
// the account parks a bounded number of feeds, and the due ones come out
// soonest first with all their askers.
func TestGpodderPending(t *testing.T) {
	d, ctx := gpodderFixture(t)
	park := func(url, device string, at int64) bool {
		t.Helper()
		ok, err := d.ParkGpodderPending(ctx, GpodderPending{
			UserID: "us-A", FeedURL: url, DeviceID: device, CreatedAtNS: at, NextTryNS: at + 10,
		}, 3)
		if err != nil {
			t.Fatal(err)
		}
		return ok
	}
	if !park("https://a.example/feed", "phone", 100) || !park("https://b.example/feed", "desk", 200) {
		t.Fatal("parking under the cap refused")
	}
	if !park("https://a.example/feed", "desk", 300) || !park("https://a.example/feed", "desk", 350) {
		t.Fatal("another device's ask for a parked feed refused")
	}
	if !park("https://c.example/feed", "phone", 400) {
		t.Fatal("the third feed refused")
	}
	if park("https://d.example/feed", "phone", 500) {
		t.Fatal("a fourth feed past a cap of three landed")
	}
	parks, err := d.GpodderParks(ctx, "us-A")
	if err != nil || len(parks) != 3 {
		t.Fatalf("parks = %+v (%v), want three feeds", parks, err)
	}
	if a := parks[0]; a.FeedURL != "https://a.example/feed" || !slices.Equal(a.Devices, []string{"phone", "desk"}) ||
		a.CreatedAtNS != 100 || a.NextTryNS != 110 {
		t.Errorf("a feed asked for twice = %+v, want both devices on the first ask's schedule", a)
	}

	asks, err := d.GpodderParkAsks(ctx, "us-A", "https://a.example/feed")
	if err != nil {
		t.Fatal(err)
	}
	if err := d.RescheduleGpodderParkAsks(ctx, "us-A", "https://a.example/feed", asks, 1, 1000, "host-error"); err != nil {
		t.Fatal(err)
	}
	due, err := d.DueGpodderParks(ctx, 500, 10)
	if err != nil {
		t.Fatal(err)
	}
	var urls []string
	for _, p := range due {
		urls = append(urls, p.FeedURL)
	}
	if !slices.Equal(urls, []string{"https://b.example/feed", "https://c.example/feed"}) {
		t.Errorf("due at 500 = %v, want b then c, a rescheduled past it", urls)
	}
	if due, _ := d.DueGpodderParks(ctx, 1000, 10); len(due) != 3 || !slices.Equal(due[2].Devices, []string{"phone", "desk"}) || due[2].Attempts != 1 {
		t.Errorf("due at 1000 = %+v, want a last, with both askers and its one attempt", due)
	}

	// The phone letting go of a drops only its own ask.
	if err := d.DropGpodderPendingFor(ctx, "us-A", "phone", []string{"https://c.example/feed"}); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteGpodderPending(ctx, "us-A", "https://b.example/feed"); err != nil {
		t.Fatal(err)
	}
	parks, _ = d.GpodderParks(ctx, "us-A")
	if len(parks) != 2 || parks[0].FeedURL != "https://a.example/feed" || !slices.Equal(parks[0].Devices, []string{"desk"}) ||
		parks[1].FeedURL != "https://c.example/feed" {
		t.Errorf("parks = %+v, want a held by the desk alone and c", parks)
	}
}

// A stamp says when the server saw the position move, which a replayed
// one recorded long before still says is now.
func TestPositionStampsAfterTheyWereSeen(t *testing.T) {
	d, ctx := gpodderFixture(t)
	before := time.Now().UnixNano()
	recorded := time.Now().Add(-48 * time.Hour).UnixNano()
	ids, err := d.AppendGpodderActions(ctx, []GpodderAction{{UserID: "us-A", PodcastURL: "https://a.example/feed",
		EpisodeURL: "https://a.example/old.mp3", Action: "play", UploadedSec: 100}}, 10)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.StampPlayState(ctx, "us-A", "ep-old", recorded, ids[0]); err != nil {
		t.Fatal(err)
	}
	if err := d.TouchPlayStamp(ctx, "us-A", "ep-marked", 0); err != nil {
		t.Fatal(err)
	}
	stamps, err := d.PositionStampsAfter(ctx, "us-A", before, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(stamps) != 2 || stamps[0].ItemPID != "ep-old" || stamps[0].PositionNS != recorded ||
		stamps[0].SeenNS < before || !stamps[0].FromGpodder || stamps[1].ItemPID != "ep-marked" ||
		stamps[1].PositionNS != 0 || stamps[1].FromGpodder {
		t.Fatalf("stamps = %+v, want the replay (an upload's) and the mark, both seen now", stamps)
	}
	// The next change says who made it: a first-party touch is no
	// longer the upload's, and keeps the position stamp.
	if err := d.TouchPlayStamp(ctx, "us-A", "ep-old", 0); err != nil {
		t.Fatal(err)
	}
	if again, _ := d.PositionStampsAfter(ctx, "us-A", stamps[1].SeenNS, stamps[1].ItemPID, 10); len(again) != 1 ||
		again[0].FromGpodder || again[0].PositionNS != recorded {
		t.Fatalf("stamps after a first-party touch = %+v, want the replay's position, no longer the upload's", again)
	}
	stamps, _ = d.PositionStampsAfter(ctx, "us-A", before, "", 10)
	if later, _ := d.PositionStampsAfter(ctx, "us-A", stamps[1].SeenNS, stamps[1].ItemPID, 10); len(later) != 0 {
		t.Errorf("stamps after the last = %+v", later)
	}
	// Stamps seen in the same nanosecond page by pid, none skipped.
	tie := stamps[1].SeenNS + 1
	for _, pid := range []string{"ep-b", "ep-a", "ep-c"} {
		if _, err := d.Writer().ExecContext(ctx, `INSERT INTO play_state_stamps (user_id, item_pid, seen_ns)
			VALUES ('us-A', ?, ?)`, pid, tie); err != nil {
			t.Fatal(err)
		}
	}
	var paged []string
	afterNS, afterPID := tie, ""
	for range 4 {
		page, err := d.PositionStampsAfter(ctx, "us-A", afterNS, afterPID, 1)
		if err != nil {
			t.Fatal(err)
		}
		if len(page) == 0 {
			break
		}
		paged = append(paged, page[0].ItemPID)
		afterNS, afterPID = page[0].SeenNS, page[0].ItemPID
	}
	if strings.Join(paged, ",") != "ep-a,ep-b,ep-c" {
		t.Errorf("paged one at a time = %v, want all three by pid", paged)
	}
	if st, _ := d.PlayStamp(ctx, "us-A", "ep-marked"); st.PositionNS != 0 {
		t.Errorf("a mark moved the position stamp to %d", st.PositionNS)
	}
	// The prune keeps what was seen inside the window, however old the
	// position it carries.
	if n, err := d.PruneStamps(ctx, before); err != nil || n != 0 {
		t.Errorf("prune of rows seen just now removed %d (%v)", n, err)
	}
}

// The action log keeps the newest per account under its cap, and a year.
func TestGpodderActionCaps(t *testing.T) {
	d, ctx := gpodderFixture(t)
	batch := make([]GpodderAction, 0, 7)
	for i := range 7 {
		batch = append(batch, GpodderAction{UserID: "us-A", PodcastURL: "https://a.example/feed",
			EpisodeURL: fmt.Sprintf("https://a.example/%d.mp3", i), Action: "play", UploadedSec: int64(100 + i)})
	}
	if _, err := d.AppendGpodderActions(ctx, batch, 5); err != nil {
		t.Fatal(err)
	}
	rows, err := d.GpodderActionsSince(ctx, "us-A", 0, "", "")
	if err != nil || len(rows) != 5 || rows[0].EpisodeURL != "https://a.example/2.mp3" {
		t.Fatalf("after a batch past the cap: %d rows (%v), first %+v, want the newest five", len(rows), err, rows)
	}
	if n, err := d.PruneGpodderActions(ctx, 104); err != nil || n != 2 {
		t.Fatalf("pruning before 104 removed %d (%v), want 2", n, err)
	}
}

// Past the cap a new device takes the slot of the least recently seen one
// holding nothing; when all hold something, of the least recently seen of
// all, whose holds pass to the apps where nobody else has them.
func TestRegisterGpodderDeviceMakesRoom(t *testing.T) {
	d, ctx := gpodderFixture(t)
	register := func(id string, at int64) *GpodderEviction {
		t.Helper()
		ev, err := d.RegisterGpodderDevice(ctx, GpodderDevice{UserID: "us-A", DeviceID: id, CreatedAtNS: at, UpdatedAtNS: at}, 3)
		if err != nil {
			t.Fatal(err)
		}
		return ev
	}
	register("a", 1)
	register("b", 2)
	register("c", 3)
	attach(t, d, "pc-1", "a") // a: the stalest, pc-1's only holder
	attach(t, d, "pc-2", "c")
	attach(t, d, "pc-2", "b")
	if ev := register("a", 4); ev != nil {
		t.Fatalf("re-registering a known device evicted %+v", ev)
	}
	// Everybody holds something: b, now the stalest, goes, and pc-2 has
	// c still.
	if ev := register("d", 5); ev == nil || ev.DeviceID != "b" || !ev.Held || ev.Kept != 0 {
		t.Fatalf("evicted %+v, want b with nothing to pass on", ev)
	}
	if ev := register("e", 6); ev == nil || ev.DeviceID != "d" || ev.Held {
		t.Fatalf("evicted %+v, want d, which holds nothing, quietly", ev)
	}
	attach(t, d, "pc-3", "e")
	if err := d.SeeGpodderDevice(ctx, "us-A", "c", 10); err != nil {
		t.Fatal(err)
	}
	ev := register("f", 7)
	if ev == nil || ev.DeviceID != "a" || !ev.Held || ev.Kept != 1 {
		t.Fatalf("evicted %+v, want a, the stalest, with pc-1 kept for the apps", ev)
	}
	if held, _ := d.GpodderHeldBy(ctx, "us-A", ""); !slices.Equal(held, []string{"pc-1"}) {
		t.Errorf("the apps hold %v, want pc-1, which only a held", held)
	}
	devs, err := d.GpodderDevicesByUser(ctx, "us-A")
	if err != nil || len(devs) != 3 {
		t.Fatalf("devices = %+v (%v), want three", devs, err)
	}
}

// Counting an account's inbox rows of an event, whatever they say, filed
// after a time.
func TestCountNotificationsSince(t *testing.T) {
	d, ctx := gpodderFixture(t)
	if err := d.CreateUser(ctx, mkUser("us-B", "bob", []string{"user"}), false); err != nil {
		t.Fatal(err)
	}
	for _, n := range []Notification{
		{ID: "nt-1", UserID: "us-A", Event: "subscription-failed", Body: "the body", CreatedNS: 100},
		{ID: "nt-2", UserID: "us-B", Event: "subscription-failed", Body: "bob's body", CreatedNS: 300},
		{ID: "nt-3", UserID: "us-A", Event: "subscription-failed", Body: "another", CreatedNS: 200},
		{ID: "nt-4", UserID: "us-A", Event: "feed-disabled", Body: "the body", CreatedNS: 250},
	} {
		if err := d.InsertNotification(ctx, n); err != nil {
			t.Fatal(err)
		}
	}
	for _, c := range []struct {
		since int64
		want  int
	}{{99, 2}, {100, 1}, {200, 0}} {
		if n, err := d.CountNotificationsSince(ctx, "us-A", "subscription-failed", c.since); err != nil || n != c.want {
			t.Errorf("rows after %d = %d (%v), want %d", c.since, n, err, c.want)
		}
	}
}

// A remembered transcript failure keeps its reason, and a fetched
// transcript replacing it carries none.
func TestTranscriptCacheKeepsTheFailureReason(t *testing.T) {
	d, ctx := gpodderFixture(t)
	if err := d.PutTranscriptCache(ctx, TranscriptRow{EpisodePID: "ep-1", Negative: true, FailReason: "host-refused", FetchedAtNS: 5}); err != nil {
		t.Fatal(err)
	}
	row, err := d.TranscriptCacheFor(ctx, "ep-1")
	if err != nil || !row.Negative || row.FailReason != "host-refused" || row.FetchedAtNS != 5 {
		t.Fatalf("row = %+v (%v), want the failure and its reason", row, err)
	}
	if err := d.PutTranscriptCache(ctx, TranscriptRow{EpisodePID: "ep-1", Format: "vtt", Cues: "[]", FetchedAtNS: 6}); err != nil {
		t.Fatal(err)
	}
	if row, err = d.TranscriptCacheFor(ctx, "ep-1"); err != nil || row.Negative || row.FailReason != "" || row.Format != "vtt" {
		t.Fatalf("row = %+v (%v), want the transcript and no reason", row, err)
	}
}

// The change log keeps a show's latest change only, whatever URL each
// was made under, the newest removals up to the cap, and removals for the
// retention.
func TestGpodderSubEventsStayBounded(t *testing.T) {
	d, ctx := gpodderFixture(t)
	add := func(show, action string, ts int64) {
		t.Helper()
		if err := d.AppendGpodderSubEvent(ctx, GpodderSubEvent{UserID: "us-A", ShowPID: show,
			FeedURL: fmt.Sprintf("https://feeds.example/%s/%d", show, ts), Action: action, TsSec: ts}, 2); err != nil {
			t.Fatal(err)
		}
	}
	log := func() string {
		t.Helper()
		evs, err := d.GpodderSubEventsSince(ctx, "us-A", 0)
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, ev := range evs {
			out = append(out, fmt.Sprintf("%s %s %d", ev.Action, ev.ShowPID, ev.TsSec))
		}
		return strings.Join(out, ", ")
	}
	for i, action := range []string{"add", "remove", "add", "remove"} {
		add("a", action, int64(100+i))
	}
	if got := log(); got != "remove a 103" {
		t.Fatalf("log after a show flapped under four URLs = %q, want its last change", got)
	}
	add("b", "add", 104)
	add("c", "remove", 105)
	add("d", "remove", 106)
	add("e", "remove", 107)
	if got := log(); got != "add b 104, remove d 106, remove e 107" {
		t.Fatalf("log past the removal cap = %q, want the adds and the newest two removals", got)
	}
	if n, err := d.PruneGpodderSubEvents(ctx, 107); err != nil || n != 1 {
		t.Fatalf("prune = %d (%v), want the one removal before 107", n, err)
	}
	if got := log(); got != "add b 104, remove e 107" {
		t.Fatalf("log after the prune = %q, want an add however old", got)
	}
}
