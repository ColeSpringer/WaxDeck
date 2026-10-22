package service

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// seedStamps writes n stamps for items that are not episodes, the way a
// music listener's history fills the stamp log, seen from fromNS on and
// stepNS apart.
func seedStamps(t *testing.T, ctx context.Context, l *Library, uc *UserCtx, n int, fromNS, stepNS int64) {
	t.Helper()
	tx, err := l.db.Writer().BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for i := range n {
		ns := fromNS + int64(i)*stepNS
		if _, err := tx.ExecContext(ctx, `INSERT INTO play_state_stamps (user_id, item_pid, position_ns, seen_ns)
			VALUES (?, ?, ?, ?)`, uc.ID, fmt.Sprintf("tr-%d-%06d", fromNS, i), ns, ns); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
}

// followedEpisode subscribes to the fixture feed and moves its episode,
// answering the episode's pid.
func followedEpisode(t *testing.T, ctx context.Context, l *Library, uc *UserCtx, feed string) string {
	t.Helper()
	sub, _, err := l.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := l.Episodes(ctx, uc, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want the fixture's one", eps, err)
	}
	if _, err := l.Checkpoint(ctx, uc, eps[0].PID, 30_000, nil); err != nil {
		t.Fatal(err)
	}
	return eps[0].PID
}

// A first download after a long music history still carries the
// episodes: the history is read past, not answered a page at a time.
func TestAFirstDownloadReadsPastAMusicHistory(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := timedFeed(t)
	seedStamps(t, ctx, svc, uc, 6000, time.Now().Add(-time.Hour).UnixNano(), int64(time.Millisecond))
	followedEpisode(t, ctx, svc, uc, feed)
	rows, cursor, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	plays := 0
	for _, a := range rows {
		if a.DeviceID == GpodderOwnDevice {
			plays++
		}
	}
	if plays != 1 {
		t.Fatalf("first-party plays = %d, want the episode's", plays)
	}
	if lag := time.Now().Unix() - cursor; lag > int64(GpodderCursorLag/time.Second)+2 {
		t.Fatalf("cursor = %d, %ds behind the clock, want it at the present", cursor, lag)
	}
}

// A download that stops short, at its stamp budget or with enough plays,
// answers a cursor past what it read whole, so a client following it
// reaches the present, even through a second holding more stamps than one
// download reads.
func TestADownloadThatStopsShortStillMakesProgress(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := timedFeed(t)
	base := time.Now().Add(-time.Hour).Truncate(time.Second)
	// 105 stamps inside one second, then one a second for 30 seconds,
	// the episode, and one a second for 15 seconds after it.
	seedStamps(t, ctx, svc, uc, 105, base.UnixNano(), int64(time.Millisecond))
	seedStamps(t, ctx, svc, uc, 30, base.Add(time.Second).UnixNano(), int64(time.Second))
	followedEpisode(t, ctx, svc, uc, feed)
	after := time.Now()
	seedStamps(t, ctx, svc, uc, 15, after.Add(time.Second).UnixNano(), int64(time.Second))

	paging := gpodderPaging{page: 10, budget: 100, plays: 1}
	since, plays := base.Unix()-1, 0
	var cursors []int64
	for range 10 {
		made, through, err := svc.gpodderFirstPartyPlays(ctx, uc, since, "", paging)
		if err != nil {
			t.Fatal(err)
		}
		plays += len(made)
		if through == 0 {
			break
		}
		if through <= since {
			t.Fatalf("a download from %d answered %d, no further", since, through)
		}
		cursors = append(cursors, through)
		since = through
	}
	// The crowded second whole, at the budget; then the second before
	// the one the episode's page ended in, at the plays.
	if want := []int64{base.Unix(), after.Unix() + 8}; !slices.Equal(cursors, want) {
		t.Fatalf("cursors on the way = %v, want %v", cursors, want)
	}
	if plays != 1 {
		t.Fatalf("plays on the way = %d, want the episode's once", plays)
	}
}

// A play position is said in whole seconds of an episode whose length is
// known, at its end once finished; an episode of no known length is said
// no position at all, finished or not.
func TestAPlayPositionSaysTheEnd(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		durationMS, positionMS int64
		finished               bool
		position, total        int64
		said                   bool
	}{
		{600_000, 333_400, false, 333, 600, true},
		{600_000, 333_400, true, 600, 600, true},
		{400, 0, false, 0, 1, true},
		{400, 0, true, 1, 1, true},
		{0, 42_000, false, 0, 0, false},
		{0, 42_000, true, 0, 0, false},
	} {
		position, total, said := gpodderPlayPosition(c.durationMS, &model.PlayState{PositionMS: c.positionMS, Finished: c.finished})
		if said != c.said || (said && (position != c.position || total != c.total)) {
			t.Errorf("gpodderPlayPosition(%d, %d, finished %v) = %d of %d (%v), want %d of %d (%v)",
				c.durationMS, c.positionMS, c.finished, position, total, said, c.position, c.total, c.said)
		}
	}
}

// The nightly prune drops the change log's removals past a year and
// keeps its adds, however old.
func TestThePruneTrimsTheChangeLog(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	old := time.Now().Add(-gpodderActionRetention - 24*time.Hour).Unix()
	for _, ev := range []wdb.GpodderSubEvent{
		{UserID: uc.ID, ShowPID: "kept", FeedURL: "https://feeds.example/kept.xml", Action: "add", TsSec: old},
		{UserID: uc.ID, ShowPID: "gone", FeedURL: "https://feeds.example/gone.xml", Action: "remove", TsSec: old},
		{UserID: uc.ID, ShowPID: "recent", FeedURL: "https://feeds.example/recent.xml", Action: "remove", TsSec: time.Now().Unix()},
	} {
		if err := svc.db.AppendGpodderSubEvent(ctx, ev, gpodderRemovalsPerUser); err != nil {
			t.Fatal(err)
		}
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	evs, err := svc.db.GpodderSubEventsSince(ctx, uc.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	var left []string
	for _, ev := range evs {
		left = append(left, ev.FeedURL)
	}
	if !slices.Equal(left, []string{"https://feeds.example/kept.xml", "https://feeds.example/recent.xml"}) {
		t.Fatalf("change log after the prune = %v, want the old add and the recent removal", left)
	}
}

// An upload whose write-through lands seconds after the request arrived
// (a long batch, a slow disk) is still the uploader's action alone, never
// said back as the server's own beside it.
func TestALongUploadIsNeverSaidBack(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	enclosure := strings.TrimSuffix(feed, "feed.xml") + "one.mp3"
	testHookMembership = func(step string) {
		if step == "record" {
			time.Sleep(2100 * time.Millisecond)
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	uploaded := time.Now().Unix()
	started, position := int64(0), int64(120)
	if err := svc.GpodderRecordActions(ctx, uc, []wdb.GpodderAction{{
		PodcastURL: feed, EpisodeURL: enclosure, DeviceID: "phone", Action: "play",
		ActionTS: time.Now().UTC().Format(gpodderTimeLayout), StartedSec: &started, PositionSec: &position,
		UploadedSec: uploaded,
	}}); err != nil {
		t.Fatal(err)
	}
	testHookMembership = nil

	stamps, err := svc.db.PositionStampsAfter(ctx, uc.ID, 0, "", 10)
	if err != nil || len(stamps) != 1 {
		t.Fatalf("stamps = %+v (%v), want the episode's", stamps, err)
	}
	if seen := stamps[0].SeenNS / int64(time.Second); seen < uploaded+2 {
		t.Fatalf("the write-through landed in second %d, want two or more after the upload's %d", seen, uploaded)
	}
	rows, _, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	var got []wdb.GpodderAction
	for _, a := range rows {
		if a.EpisodeURL == enclosure {
			got = append(got, a)
		}
	}
	if len(got) != 1 || got[0].DeviceID != "phone" || got[0].PositionSec == nil || *got[0].PositionSec != 120 {
		t.Fatalf("actions for the episode = %+v, want the phone's 120 alone", got)
	}
}
