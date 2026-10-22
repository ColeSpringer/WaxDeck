package gpodder

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// episodePID finds an episode of a show the account follows by its title.
func (e *env) episodePID(feed, title string) (show, episode string) {
	e.t.Helper()
	subs, _, err := e.svc.Subscriptions(e.ctx, e.uc, "", 50, false)
	if err != nil {
		e.t.Fatal(err)
	}
	for _, s := range subs {
		if s.Show.FeedURL != feed {
			continue
		}
		eps, _, err := e.svc.Episodes(e.ctx, e.uc, s.Show.PID, "", 50)
		if err != nil {
			e.t.Fatal(err)
		}
		for _, ep := range eps {
			if ep.Title == title {
				return s.Show.PID, ep.PID
			}
		}
	}
	e.t.Fatalf("no episode %q of %s", title, feed)
	return "", ""
}

// actions reads the account's episode actions with the given query.
func (e *env) actions(query string) actionsPageJSON {
	e.t.Helper()
	resp, raw := e.call("GET", "/api/2/episodes/alice.json?"+query, "", true)
	mustStatus(e.t, resp, raw, 200)
	var page actionsPageJSON
	if err := json.Unmarshal(raw, &page); err != nil {
		e.t.Fatalf("actions %s: %v", raw, err)
	}
	return page
}

func actionsFor(page actionsPageJSON, episode string) []episodeActionJSON {
	var out []episodeActionJSON
	for _, a := range page.Actions {
		if a.Episode == episode {
			out = append(out, a)
		}
	}
	return out
}

// nextSecond waits out the current second, which a download's cursor
// never covers.
func nextSecond() {
	time.Sleep(time.Until(time.Now().Truncate(time.Second).Add(time.Second + 10*time.Millisecond)))
}

// since is the second just ended, after which nothing the test wrote
// before nextSecond can have been stamped.
func since() string { return strconv.FormatInt(time.Now().Unix()-1, 10) }

// What the WaxDeck apps do to a position reaches gpodder clients as a play
// action from device waxdeck, and what a gpodder client uploaded is not
// said back to it a second time.
func TestFirstPartyPositionsReachGpodder(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := e.feedURLOf(2), e.feed.URL+"/show2.mp3"
	e.change("phone", []string{feed}, nil)
	show, ep := e.episodePID(feed, "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 333_000, nil); err != nil {
		t.Fatal(err)
	}

	page := e.actions("since=0")
	plays := actionsFor(page, enclosure)
	if len(plays) != 1 {
		t.Fatalf("actions for the episode = %+v, want one", plays)
	}
	got := plays[0]
	if got.Device != "waxdeck" || got.Action != "play" || got.Podcast != feed ||
		got.Position == nil || *got.Position != 333 || got.Total == nil || *got.Total != 600 ||
		got.Started == nil || *got.Started != 0 {
		t.Fatalf("the first-party play = %+v", got)
	}
	if _, err := time.Parse("2006-01-02T15:04:05", got.Timestamp); err != nil {
		t.Errorf("timestamp %q is not the protocol's: %v", got.Timestamp, err)
	}

	// The cursor trails the clock, so a write that waited for the writer
	// is never behind it.
	if lag := time.Now().Unix() - page.Timestamp; lag < 5 {
		t.Errorf("the cursor trails the clock by %ds, want at least 5", lag)
	}
	// Nothing new after the write until something moves.
	nextSecond()
	cursor := since()
	if again := e.actions("since=" + cursor); len(again.Actions) != 0 {
		t.Fatalf("actions after the write with nothing moved = %+v", again.Actions)
	}

	// A position a gpodder client uploaded is that client's action, once.
	resp, raw := e.call("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
		`[{"podcast":%q,"episode":%q,"action":"play","device":"phone","timestamp":%q,"started":0,"position":120,"total":600}]`,
		feed, enclosure, time.Now().UTC().Format("2006-01-02T15:04:05")), true)
	mustStatus(t, resp, raw, 200)
	plays = actionsFor(e.actions("since="+cursor), enclosure)
	if len(plays) != 1 || plays[0].Device != "phone" || *plays[0].Position != 120 {
		t.Fatalf("actions after the phone's upload = %+v, want the phone's alone", plays)
	}
	if agg := actionsFor(e.actions("since=0&aggregated=true"), enclosure); len(agg) != 1 || *agg[0].Position != 120 {
		t.Fatalf("aggregated = %+v, want the newest, the phone's", agg)
	}

	// Finishing, even by a mark with no position, says the end.
	nextSecond()
	cursor = since()
	if _, err := e.svc.SetPlayed(e.ctx, e.uc, ep, true, true, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	plays = actionsFor(e.actions("since="+cursor), enclosure)
	if len(plays) != 1 || plays[0].Device != "waxdeck" || *plays[0].Position != 600 {
		t.Fatalf("actions after the finished mark = %+v, want waxdeck's at the end", plays)
	}

	// Another device's filter leaves the first-party actions out, and
	// waxdeck's own leaves only them.
	for _, a := range e.actions("since=0&device=phone").Actions {
		if a.Device != "phone" {
			t.Errorf("device=phone answered %+v", a)
		}
	}
	for _, a := range e.actions("since=0&device=waxdeck").Actions {
		if a.Device != "waxdeck" {
			t.Errorf("device=waxdeck answered %+v", a)
		}
	}
	if plays := actionsFor(e.actions("since=0&podcast="+e.feedURL()), enclosure); len(plays) != 0 {
		t.Errorf("another show's filter answered %+v", plays)
	}

	// A show the account no longer follows says nothing of its own.
	if err := e.svc.Unsubscribe(e.ctx, e.uc, show, false); err != nil {
		t.Fatal(err)
	}
	for _, a := range e.actions("since=0").Actions {
		if a.Device == "waxdeck" {
			t.Errorf("an unfollowed show's position is still said: %+v", a)
		}
	}
}

// An episode a listen report finishes, with no checkpoint at its end,
// reaches gpodder clients finished; one whose length nobody knows says
// nothing, since a play action without its total is none to a client.
func TestAListenThatFinishesAnEpisodeReachesGpodder(t *testing.T) {
	e := newEnv(t)
	feed2 := e.feedURLOf(2)
	e.change("phone", []string{feed2, e.feedURL()}, nil)
	_, pilot := e.episodePID(feed2, "Show 2 Pilot")
	_, one := e.episodePID(e.feedURL(), "Episode One")
	at := time.Now().UTC().Add(-time.Hour)
	res, err := e.svc.IngestListens(e.ctx, e.uc, []service.ListenSession{
		{SessionID: "finish-pilot", PID: pilot, StartedAt: at, MsPlayed: 600_000, Finished: true},
		{SessionID: "finish-one", PID: one, StartedAt: at, MsPlayed: 60_000, Finished: true},
	})
	if err != nil || res.Accepted != 2 {
		t.Fatalf("ingest = %+v (%v), want both accepted", res, err)
	}
	page := e.actions("since=0")
	plays := actionsFor(page, e.feed.URL+"/show2.mp3")
	if len(plays) != 1 || plays[0].Device != "waxdeck" || plays[0].Position == nil || *plays[0].Position != 600 ||
		plays[0].Total == nil || *plays[0].Total != 600 {
		t.Fatalf("actions for the finished pilot = %+v, want waxdeck's at the end", plays)
	}
	if plays = actionsFor(page, e.feed.URL+"/ep1.mp3"); len(plays) != 0 {
		t.Fatalf("actions for the finished episode of no known length = %+v, want none", plays)
	}
}

// A position replayed from an offline outbox, recorded before a client's
// last download but arriving after it, is in that client's next one, at
// the time it was recorded.
func TestAReplayedPositionReachesTheNextDownload(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := e.feedURLOf(2), e.feed.URL+"/show2.mp3"
	e.change("phone", []string{feed}, nil)
	_, ep := e.episodePID(feed, "Show 2 Pilot")
	cursor := e.actions("since=0").Timestamp
	recorded := time.Now().Add(-2 * time.Hour).Truncate(time.Second)
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 120_000, &recorded); err != nil {
		t.Fatal(err)
	}
	plays := actionsFor(e.actions("since="+strconv.FormatInt(cursor, 10)), enclosure)
	if len(plays) != 1 || plays[0].Device != "waxdeck" || plays[0].Position == nil || *plays[0].Position != 120 ||
		plays[0].Timestamp != recorded.UTC().Format("2006-01-02T15:04:05") {
		t.Fatalf("actions after the replay = %+v, want waxdeck's at 120 s, stamped %s", plays, recorded.UTC())
	}
}

// shortFeed serves one show whose one episode the feed says is seven
// seconds long, shorter than the copy a podcast app may hold (dynamic ad
// insertion makes the two differ).
func shortFeed(t *testing.T) (feed, enclosure string) {
	t.Helper()
	var ts *httptest.Server
	ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/short.xml" {
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write([]byte("fake-mp3-bytes"))
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Short Show</title>
<item><title>Short One</title><guid>short-1</guid><enclosure url="%s/short.mp3" type="audio/mpeg" length="14"/>
<itunes:duration>7</itunes:duration><pubDate>Wed, 07 Jan 2026 09:00:00 GMT</pubDate></item>
</channel></rss>`, ts.URL)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/short.xml", ts.URL + "/short.mp3"
}

// A position a gpodder client uploads is never said back as the server's
// own, however the server read it: 90 seconds into an episode the catalog
// holds as seven finishes it here, and the aggregated download still
// answers the device's own 90. A first-party change after an upload is
// the server's own news again.
func TestAnUploadedPositionIsNeverSaidBack(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := shortFeed(t)
	e.change("phone", []string{feed}, nil)
	upload := func(feed, episode string, position int) {
		t.Helper()
		resp, raw := e.call("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
			`[{"podcast":%q,"episode":%q,"action":"play","device":"phone","timestamp":"2026-07-18T10:00:00","started":0,"position":%d,"total":300}]`,
			feed, episode, position), true)
		mustStatus(t, resp, raw, 200)
	}
	upload(feed, enclosure, 90)
	agg := actionsFor(e.actions("since=0&aggregated=true"), enclosure)
	if len(agg) != 1 || agg[0].Device != "phone" || agg[0].Position == nil || *agg[0].Position != 90 {
		t.Fatalf("aggregated = %+v, want the phone's own 90", agg)
	}
	for _, a := range e.actions("since=0").Actions {
		if a.Device == "waxdeck" {
			t.Fatalf("the phone's upload came back as the server's own: %+v", a)
		}
	}
	_, short := e.episodePID(feed, "Short One")
	if st, err := e.svc.PlayState(e.ctx, e.uc, short); err != nil || st.PositionMS != 90_000 {
		t.Fatalf("play state = %+v (%v), want the upload's 90 s", st, err)
	}

	feed2, enclosure2 := e.feedURLOf(2), e.feed.URL+"/show2.mp3"
	e.change("phone", []string{feed2}, nil)
	upload(feed2, enclosure2, 120)
	_, pilot := e.episodePID(feed2, "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, pilot, 333_000, nil); err != nil {
		t.Fatal(err)
	}
	plays := actionsFor(e.actions("since=0"), enclosure2)
	if len(plays) != 2 || plays[1].Device != "waxdeck" || plays[1].Position == nil || *plays[1].Position != 333 {
		t.Fatalf("actions after a first-party checkpoint = %+v, want the phone's and then the server's 333", plays)
	}
}
