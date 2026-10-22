package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// timedFeed serves one show whose one episode the feed says is ten
// minutes long, answering its feed and enclosure URLs.
func timedFeed(t *testing.T) (feed, enclosure string) {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Timed Show</title>
<item><title>Timed</title><guid>timed-1</guid><enclosure url="http://%s/timed.mp3" type="audio/mpeg" length="1"/>
<itunes:duration>600</itunes:duration></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", ts.URL + "/timed.mp3"
}

// No download answers a cursor at or past a write still waiting for the
// writer, however long it waits. Each kind of change a gpodder download
// reports, alone in flight for its account, stamped before the download
// and committed after it, holds that download's cursor back and is in the
// next download from it; a subscription upload after such a delta answers
// no later than the delta did.
func TestNoCursorPassesAWriteInFlight(t *testing.T) {
	type stalled struct {
		ctx  context.Context
		svc  *Library
		uc   *UserCtx
		feed string
		ep   string
	}
	for _, c := range []struct {
		name  string
		subs  bool
		write func(s stalled) error
		said  func(rows []wdb.GpodderAction, evs []wdb.GpodderSubEvent) bool
	}{
		{name: "an uploaded action", write: func(s stalled) error {
			return s.svc.GpodderRecordActions(s.ctx, s.uc, []wdb.GpodderAction{{
				PodcastURL: s.feed, EpisodeURL: s.feed + "/stalled.mp3", DeviceID: "phone", Action: "download",
			}})
		}, said: func(rows []wdb.GpodderAction, _ []wdb.GpodderSubEvent) bool {
			return slices.ContainsFunc(rows, func(a wdb.GpodderAction) bool { return a.DeviceID == "phone" })
		}},
		{name: "a position the apps moved", write: func(s stalled) error {
			_, err := s.svc.Checkpoint(s.ctx, s.uc, s.ep, 90_000, nil)
			return err
		}, said: func(rows []wdb.GpodderAction, _ []wdb.GpodderSubEvent) bool {
			return slices.ContainsFunc(rows, func(a wdb.GpodderAction) bool { return a.DeviceID == GpodderOwnDevice && *a.PositionSec == 90 })
		}},
		{name: "an episode marked played", write: func(s stalled) error {
			_, err := s.svc.SetPlayed(s.ctx, s.uc, s.ep, true, true, nil, nil, nil)
			return err
		}, said: func(rows []wdb.GpodderAction, _ []wdb.GpodderSubEvent) bool {
			return slices.ContainsFunc(rows, func(a wdb.GpodderAction) bool { return a.DeviceID == GpodderOwnDevice && *a.PositionSec == 600 })
		}},
		{name: "a subscription change", subs: true, write: func(s stalled) error {
			return s.svc.db.AppendGpodderSubEvent(s.ctx, wdb.GpodderSubEvent{
				UserID: s.uc.ID, ShowPID: "stalled-show", FeedURL: "https://feeds.example/stalled.xml",
				Action: "add", TsSec: time.Now().Unix(),
			}, gpodderRemovalsPerUser)
		}, said: func(_ []wdb.GpodderAction, evs []wdb.GpodderSubEvent) bool {
			return slices.ContainsFunc(evs, func(ev wdb.GpodderSubEvent) bool { return ev.ShowPID == "stalled-show" })
		}},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, _ := openPodcastFixture(t)
			feed, _ := timedFeed(t)
			sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
			if err != nil {
				t.Fatal(err)
			}
			eps, _, err := svc.Episodes(ctx, uc, sub.Show.PID, "", 1)
			if err != nil || len(eps) != 1 {
				t.Fatalf("episodes = %+v (%v)", eps, err)
			}
			registered(t, ctx, svc, uc, "phone")
			read := func(since int64) ([]wdb.GpodderAction, []wdb.GpodderSubEvent, int64) {
				t.Helper()
				if c.subs {
					evs, cursor, err := svc.GpodderSubChangesSince(ctx, uc, "phone", since)
					if err != nil {
						t.Fatal(err)
					}
					return nil, evs, cursor
				}
				rows, cursor, err := svc.GpodderActionsSince(ctx, uc, "", since, "", "")
				if err != nil {
					t.Fatal(err)
				}
				return rows, nil, cursor
			}

			// The device has read once, so a read keeps nothing new for it
			// while the writer is held.
			read(0)
			// A backup's VACUUM INTO holds the one write connection.
			tx, err := svc.db.Writer().BeginTx(ctx, nil)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { tx.Rollback() })
			stamp := time.Now().Unix()
			wrote := make(chan error, 1)
			go func() { wrote <- c.write(stalled{ctx: ctx, svc: svc, uc: uc, feed: feed, ep: eps[0].PID}) }()
			time.Sleep(GpodderCursorLag + 1500*time.Millisecond)
			_, _, cursor := read(0)
			tx.Rollback()
			if err := <-wrote; err != nil {
				t.Fatal(err)
			}
			if cursor >= stamp {
				t.Errorf("the download answered %d with a write stamped %d in flight, want before it", cursor, stamp)
			}
			if rows, evs, _ := read(cursor); !c.said(rows, evs) {
				t.Errorf("the next download from %d = %+v %+v, want the stalled change", cursor, rows, evs)
			}
			if c.subs {
				if err := svc.GpodderRememberRead(ctx, uc, "phone", cursor); err != nil {
					t.Fatal(err)
				}
				if got, err := svc.GpodderUploadCursor(ctx, uc, "phone", time.Now()); err != nil || got > cursor {
					t.Errorf("the upload after the held delta answered %d (%v), want no later than %d", got, err, cursor)
				}
			}
		})
	}
}

// A download that stops short of the clock, at its stamp or play budget,
// holds the episodes upload after it back to its answer: the client keeps
// the upload's answer and has still to read what the download left.
func TestAShortDownloadHoldsTheUploadBack(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := timedFeed(t)
	followedEpisode(t, ctx, svc, uc, feed)
	seedStamps(t, ctx, svc, uc, 30, time.Now().Add(-time.Hour).UnixNano(), int64(time.Second))
	saved := gpodderDownloadPaging
	gpodderDownloadPaging = gpodderPaging{page: 10, budget: 20, plays: 1}
	t.Cleanup(func() { gpodderDownloadPaging = saved })
	_, cursor, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if clock := time.Now().Add(-GpodderCursorLag).Unix(); cursor >= clock-1 {
		t.Fatalf("the download answered %d, want it stopped short of the clock %d", cursor, clock)
	}
	if got := svc.GpodderEpisodesUploadCursor(uc, "", time.Now()); got > cursor {
		t.Errorf("the upload answered %d, past the short download's %d", got, cursor)
	}
}

// An episodes upload answers no later than the lowest answer a download
// gave in the last ten minutes, however many higher ones came after it,
// each answer's ten minutes running from when it was given, and an account
// answers for itself.
func TestTheDownloadAnswersOfTheLastTenMinutes(t *testing.T) {
	t.Parallel()
	var d gpodderDownloads
	t0 := time.Now()
	lowest := func(at time.Duration) int64 {
		t.Helper()
		got, ok := d.lowest("us-A", t0.Add(at))
		if !ok {
			return -1
		}
		return got
	}
	d.note("us-A", 100, t0)
	d.note("us-A", 200, t0.Add(time.Minute))
	for _, c := range []struct {
		at   time.Duration
		want int64
	}{{5 * time.Minute, 100}, {10 * time.Minute, 200}, {11 * time.Minute, -1}} {
		if got := lowest(c.at); got != c.want {
			t.Errorf("lowest at %v = %d, want %d", c.at, got, c.want)
		}
	}
	for i := range gpodderAnswersKept + 20 {
		d.note("us-A", int64(1000+i), t0.Add(time.Duration(i)*time.Second))
	}
	if got := lowest(2 * time.Minute); got != 1000 {
		t.Errorf("lowest past the kept bound = %d, want the first, 1000", got)
	}
	d.note("us-A", 5, t0.Add(3*time.Minute))
	if got := lowest(4 * time.Minute); got != 5 {
		t.Errorf("lowest after a lower answer = %d, want 5", got)
	}
	if _, ok := d.lowest("us-B", t0); ok {
		t.Error("another account has an answer it never got")
	}
}

// A position a gpodder upload moved is that upload's action to tell only
// while the log keeps the action: once the cap or the year's prune lets it
// go, the position is the server's to say, so a device reading from the
// start still learns where the episode is.
func TestAPositionOutlivesTheActionThatMovedIt(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, enclosure := timedFeed(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	started, position, total := int64(0), int64(300), int64(600)
	if err := svc.GpodderRecordActions(ctx, uc, []wdb.GpodderAction{{
		PodcastURL: feed, EpisodeURL: enclosure, DeviceID: "phone", Action: "play",
		ActionTS: time.Now().UTC().Format(gpodderTimeLayout), StartedSec: &started, PositionSec: &position, TotalSec: &total,
	}}); err != nil {
		t.Fatal(err)
	}
	said := func() []string {
		t.Helper()
		rows, _, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "")
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, a := range rows {
			out = append(out, fmt.Sprintf("%s %d", a.DeviceID, *a.PositionSec))
		}
		return out
	}
	if got := said(); !slices.Equal(got, []string{"phone 300"}) {
		t.Fatalf("actions while the upload is kept = %v, want the phone's alone", got)
	}
	if _, err := svc.db.PruneGpodderActions(ctx, time.Now().Unix()+1); err != nil {
		t.Fatal(err)
	}
	if got := said(); !slices.Equal(got, []string{GpodderOwnDevice + " 300"}) {
		t.Fatalf("actions once the upload was let go = %v, want the server's 300", got)
	}
}

// A batch once stored is answered stored, whatever the write-through after
// it meets: a client told otherwise sends the batch again.
func TestAStoredBatchIsAnsweredStored(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	reqCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	testHookMembership = func(step string) {
		if step == "recorded" {
			cancel()
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	position := int64(120)
	err := svc.GpodderRecordActions(reqCtx, uc, []wdb.GpodderAction{{
		PodcastURL: feed, EpisodeURL: feed + "/one.mp3", DeviceID: "phone", Action: "play",
		PositionSec: &position,
	}})
	testHookMembership = nil
	if err != nil {
		t.Fatalf("a stored batch whose write-through failed answered %v", err)
	}
	if rows, _, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "phone"); err != nil || len(rows) != 1 {
		t.Fatalf("stored = %+v (%v), want the batch", rows, err)
	}
}
