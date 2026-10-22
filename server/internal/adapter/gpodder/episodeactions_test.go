package gpodder

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// protocolTime spells a time the way gpodder clients do.
const protocolTime = "2006-01-02T15:04:05"

// upload posts one batch of episode actions and answers its ack.
func (e *env) upload(actions ...string) uploadAckJSON {
	e.t.Helper()
	resp, raw := e.call("POST", "/api/2/episodes/alice.json", "["+strings.Join(actions, ",")+"]", true)
	mustStatus(e.t, resp, raw, 200)
	var ack uploadAckJSON
	if err := json.Unmarshal(raw, &ack); err != nil {
		e.t.Fatalf("ack %s: %v", raw, err)
	}
	return ack
}

// playOf is one device's play action, its numbers as JSON.
func playOf(device, feed, episode, at, started, position, total string) string {
	return fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"play","device":%q,"timestamp":%q,"started":%s,"position":%s,"total":%s}`,
		feed, episode, device, at, started, position, total)
}

// positionOf reads where the account is in an episode, in milliseconds.
func (e *env) positionOf(episode string) int64 {
	e.t.Helper()
	st, err := e.svc.PlayState(e.ctx, e.uc, episode)
	if err != nil {
		e.t.Fatal(err)
	}
	return st.PositionMS
}

// A play's numbers are seconds within an episode. An action whose start,
// position or length is negative or past thirty days, or whose position is
// past the length it gives, is skipped and the rest of its batch kept:
// nothing negative is stored, said to another device or written through,
// and no position wraps on its way to milliseconds.
func TestImplausiblePlayNumbersAreSkipped(t *testing.T) {
	e := newEnv(t)
	e.subscribe("phone")
	feed, one, two := e.feedURL(), e.feed.URL+"/ep1.mp3", e.feed.URL+"/ep2.mp3"
	const at = "2026-01-10T08:00:00"
	e.upload(
		playOf("phone", feed, one, at, "0", "18446744073709552", "18446744073709553"),
		playOf("phone", feed, one, at, "-5", "120", "600"),
		playOf("phone", feed, one, at, "0", "-120", "600"),
		playOf("phone", feed, one, at, "0", "120", "-600"),
		playOf("phone", feed, one, at, "2592001", "120", "600"),
		playOf("phone", feed, one, at, "0", "2592001", "2592002"),
		playOf("phone", feed, one, at, "0", "700", "600"),
		playOf("phone", feed, two, at, "0", "120", "600"),
	)
	stored := e.actions("since=0").Actions
	if len(stored) != 1 || stored[0].Episode != two || *stored[0].Position != 120 {
		t.Fatalf("stored = %+v, want only the plausible play", stored)
	}
	_, epOne := e.episodePID(feed, "Episode One")
	_, epTwo := e.episodePID(feed, "Episode Two")
	if got := e.positionOf(epOne); got != 0 {
		t.Errorf("Episode One is at %d ms, want untouched by the skipped plays", got)
	}
	if got := e.positionOf(epTwo); got != 120_000 {
		t.Errorf("Episode Two is at %d ms, want the plausible play's 120 s", got)
	}
}

// The aggregated download keeps, for each episode, the action with the
// latest time, whoever uploaded last: an offline play from an hour ago,
// uploaded after the apps moved the episode, is not where the episode is.
// Of two actions at one time, the later upload's stands.
func TestTheAggregatedDownloadKeepsTheLatestAction(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := e.feedURLOf(2), e.feed.URL+"/show2.mp3"
	e.change("phone", []string{feed}, nil)
	_, ep := e.episodePID(feed, "Show 2 Pilot")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 500_000, nil); err != nil {
		t.Fatal(err)
	}
	nextSecond()
	e.upload(playOf("phone", feed, enclosure, time.Now().UTC().Add(-time.Hour).Format(protocolTime), "0", "100", "600"))
	agg := actionsFor(e.actions("since=0&aggregated=true"), enclosure)
	if len(agg) != 1 || agg[0].Device != "waxdeck" || agg[0].Position == nil || *agg[0].Position != 500 {
		t.Fatalf("aggregated = %+v, want the apps' 500 s, the latest", agg)
	}

	later := time.Now().UTC().Add(time.Minute).Format(protocolTime)
	e.upload(playOf("phone", feed, enclosure, later, "0", "200", "600"))
	e.upload(playOf("tablet", feed, enclosure, later, "0", "250", "600"))
	agg = actionsFor(e.actions("since=0&aggregated=true"), enclosure)
	if len(agg) != 1 || agg[0].Device != "tablet" || *agg[0].Position != 250 {
		t.Fatalf("aggregated = %+v, want the tablet's, the later of two at one time", agg)
	}
}

// sharedEnclosureFeed serves one show whose two episodes name one
// enclosure, the way a reissued episode or a placeholder file does.
func sharedEnclosureFeed(t *testing.T) (feed, enclosure string) {
	t.Helper()
	var ts *httptest.Server
	ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Shared</title>
<item><title>Placeholder</title><guid>shared-1</guid><enclosure url="%[1]s/shared.mp3" type="audio/mpeg" length="1"/>
<itunes:duration>600</itunes:duration><pubDate>Mon, 05 Jan 2026 09:00:00 GMT</pubDate></item>
<item><title>Reissue</title><guid>shared-2</guid><enclosure url="%[1]s/shared.mp3" type="audio/mpeg" length="1"/>
<itunes:duration>600</itunes:duration><pubDate>Tue, 06 Jan 2026 09:00:00 GMT</pubDate></item>
</channel></rss>`, ts.URL)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", ts.URL + "/shared.mp3"
}

// A play of an enclosure two episodes share lands on the newest of them.
func TestAPlayOfASharedEnclosureLandsOnTheNewest(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := sharedEnclosureFeed(t)
	e.change("phone", []string{feed}, nil)
	_, older := e.episodePID(feed, "Placeholder")
	_, newer := e.episodePID(feed, "Reissue")
	e.upload(playOf("phone", feed, enclosure, time.Now().UTC().Format(protocolTime), "0", "120", "600"))
	if got := e.positionOf(newer); got != 120_000 {
		t.Errorf("the reissue is at %d ms, want the play's 120 s", got)
	}
	if got := e.positionOf(older); got != 0 {
		t.Errorf("the placeholder is at %d ms, want untouched", got)
	}
}

// An action sent again is stored once, so a client that resends a batch
// whose answer it lost adds nothing to the log; another position, time or
// device is another action.
func TestAnActionSentAgainIsStoredOnce(t *testing.T) {
	e := newEnv(t)
	e.subscribe("phone")
	feed, one := e.feedURL(), e.feed.URL+"/ep1.mp3"
	const at = "2026-01-10T08:00:00"
	batch := []string{
		playOf("phone", feed, one, at, "0", "120", "600"),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"phone","timestamp":"2026-01-10T07:00:00"}`, feed, one),
	}
	e.upload(batch...)
	e.upload(batch...)
	e.upload(batch[0], batch[0])
	if got := e.actions("since=0").Actions; len(got) != 2 {
		t.Fatalf("stored = %+v, want the batch once", got)
	}
	e.upload(
		playOf("phone", feed, one, at, "0", "130", "600"),
		playOf("phone", feed, one, "2026-01-10T08:00:01", "0", "120", "600"),
		playOf("tablet", feed, one, at, "0", "120", "600"),
	)
	if got := e.actions("since=0").Actions; len(got) != 5 {
		t.Fatalf("stored = %d actions, want three more", len(got))
	}
}

// Every upload's answer carries update_urls, an empty list when nothing
// was rewritten: AntennaPod fails a sync whose answer lacks the key.
func TestEveryUploadAnswerCarriesUpdateURLs(t *testing.T) {
	e := newEnv(t)
	download := fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download"}`, e.feedURL(), e.feed.URL+"/ep1.mp3")
	for _, c := range []struct{ path, body string }{
		{"/api/2/subscriptions/alice/phone.json", fmt.Sprintf(`{"add":[%q],"remove":[]}`, e.feedURL())},
		{"/api/2/subscriptions/alice/phone.json", `{"add":[],"remove":[]}`},
		{"/api/2/subscriptions/alice/phone.json", `{}`},
		{"/api/2/episodes/alice.json", `[]`},
		{"/api/2/episodes/alice.json", "[" + download + "]"},
		{"/api/2/episodes/alice.json", `[{"podcast":"","episode":"","action":"play"}]`},
	} {
		resp, raw := e.call("POST", c.path, c.body, true)
		mustStatus(t, resp, raw, 200)
		var ack map[string]json.RawMessage
		if err := json.Unmarshal(raw, &ack); err != nil {
			t.Fatalf("%s %s: %v", c.path, raw, err)
		}
		if got := string(ack["update_urls"]); got != "[]" {
			t.Errorf("POST %s %s answered update_urls %q, want []", c.path, c.body, got)
		}
	}
}

// A position the apps move on an episode whose length nobody knows says
// nothing to gpodder clients: a play action without a total is one a
// client reads as no position at all, and acts on as the episode's start.
func TestAPositionOfUnknownLengthSaysNothing(t *testing.T) {
	e := newEnv(t)
	e.change("phone", []string{e.feedURL()}, nil)
	_, one := e.episodePID(e.feedURL(), "Episode One")
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, one, 1_200_000, nil); err != nil {
		t.Fatal(err)
	}
	for _, a := range e.actions("since=0").Actions {
		if a.Device == "waxdeck" {
			t.Errorf("an episode of unknown length said %+v", a)
		}
	}
}

// holdWriter keeps the server's one write connection for d, the way a
// backup's VACUUM INTO does, so whatever writes meanwhile waits for it.
func (e *env) holdWriter(d time.Duration) {
	e.t.Helper()
	tx, err := e.store.Writer().BeginTx(e.ctx, nil)
	if err != nil {
		e.t.Fatal(err)
	}
	timer := time.AfterFunc(d, func() { tx.Rollback() })
	e.t.Cleanup(func() {
		timer.Stop()
		tx.Rollback()
	})
}

// An upload answers the time it arrived, not the time its work ended: a
// client keeps the answer as the since of its next download, so a change
// made before the upload's own work finished is still ahead of it.
func TestAnUploadAnswersTheTimeItArrived(t *testing.T) {
	e := newEnv(t)
	feed, enclosure := e.feedURLOf(2), e.feed.URL+"/show2.mp3"
	e.change("phone", []string{feed}, nil)
	_, ep := e.episodePID(feed, "Show 2 Pilot")
	stall := service.GpodderCursorLag + 1500*time.Millisecond

	// The apps move the episode; the phone's next upload then waits on the
	// writer longer than the cursor trails the clock.
	if _, err := e.svc.Checkpoint(e.ctx, e.uc, ep, 300_000, nil); err != nil {
		t.Fatal(err)
	}
	e.holdWriter(stall)
	ack := e.upload(fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"phone"}`, feed, enclosure))
	plays := actionsFor(e.actions("since="+strconv.FormatInt(ack.Timestamp, 10)), enclosure)
	found := false
	for _, a := range plays {
		found = found || (a.Device == "waxdeck" && a.Position != nil && *a.Position == 300)
	}
	if !found {
		t.Errorf("the download from the episodes upload's answer = %+v, want the apps' 300 s made before it", plays)
	}

	// The same for a subscription upload and another device's add.
	e.change("tablet", []string{e.feedURLOf(3)}, nil)
	e.holdWriter(stall)
	sub := e.change("phone", nil, nil)
	if d := e.changesSince("phone", sub.Timestamp); !strings.Contains(strings.Join(d.Add, " "), e.feedURLOf(3)) {
		t.Errorf("the delta from the subscription upload's answer = %+v, want the tablet's add made before it", d)
	}
}

// An action is kept in a shape every client can read back: one sent
// without a time is stored at its upload's, and one mygpoclient refuses
// to build (a start, position or length on an action other than play, a
// play with its start or length but no position) is skipped like any
// other the log cannot keep.
func TestEveryStoredActionReadsBackInEveryClient(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	ep := func(n int) string { return fmt.Sprintf("%s/shape-%d.mp3", e.feed.URL, n) }
	at := time.Now().UTC().Add(-time.Minute).Format(protocolTime)
	before := time.Now().UTC().Truncate(time.Second)
	e.upload(
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"kasts"}`, feed, ep(1)),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"kasts","timestamp":%q,"position":0}`, feed, ep(2), at),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"delete","device":"kasts","timestamp":%q,"total":600}`, feed, ep(3), at),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"play","device":"kasts","timestamp":%q,"started":0,"total":600}`, feed, ep(4), at),
	)
	stored := e.actions("since=0").Actions
	if len(stored) != 1 || stored[0].Episode != ep(1) {
		t.Fatalf("stored = %+v, want only the untimed download", stored)
	}
	when, err := time.Parse(protocolTime, stored[0].Timestamp)
	if err != nil || when.Before(before) || when.After(time.Now().UTC()) {
		t.Errorf("the untimed action was stored at %q (%v), want its upload's time", stored[0].Timestamp, err)
	}
}

// A field of the wrong type skips its action, never its batch: a position
// in fractional seconds or as text, or a time sent as a number, leaves the
// rest of the upload stored.
func TestAMistypedActionIsSkippedAlone(t *testing.T) {
	e := newEnv(t)
	feed := e.feedURL()
	ep := func(n int) string { return fmt.Sprintf("%s/typed-%d.mp3", e.feed.URL, n) }
	const at = "2026-01-10T08:00:00"
	e.upload(
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"play","device":"web","timestamp":%q,"started":0,"position":120.5,"total":600}`, feed, ep(1), at),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"play","device":"web","timestamp":%q,"started":0,"position":"120","total":600}`, feed, ep(2), at),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"web","timestamp":1768032000}`, feed, ep(3)),
		fmt.Sprintf(`{"podcast":%q,"episode":%q,"action":"download","device":"web","timestamp":%q}`, feed, ep(4), at),
	)
	if stored := e.actions("since=0").Actions; len(stored) != 1 || stored[0].Episode != ep(4) {
		t.Fatalf("stored = %+v, want the well-typed action alone", stored)
	}
}
