package api

import (
	"testing"
	"time"
)

// Podcast listening has to reach both stats surfaces: the per-media
// split on the listening totals, and the `shows` top list. The show is
// the grouping that has no column of its own - an episode's item view
// carries the show title through Artist - so this is the test that
// proves the two ends agree about what a podcast listen was.
func TestPodcastListensReachStats(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)

	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) != 2 {
		t.Fatalf("episodes = %d, want 2", len(page.Items))
	}

	// One listen per episode, so the show total is a sum rather than a
	// single row wearing the show's name.
	started := time.Now().UTC().Truncate(time.Second).Add(-time.Minute)
	const epMs = int64(60_000)
	var sessions []map[string]any
	for i, ep := range page.Items {
		sessions = append(sessions, map[string]any{
			"sessionId": "pod-sess-" + ep.Pid,
			"pid":       ep.Pid,
			"startedAt": started.Add(time.Duration(i) * time.Second).Format(time.RFC3339),
			"msPlayed":  epMs,
			"finished":  true,
		})
	}
	res := decode[ListenIngestResult](t, h.postJSON(t, "/api/v1/listens", map[string]any{
		"sessions": sessions,
	}))
	if res.Accepted != 2 {
		t.Fatalf("ingest = %+v, want two accepted", res)
	}

	// The split names the listening as podcast, not as music.
	resp = get(t, h.ts, "/api/v1/stats/listening?range=30d", h.token)
	stats := decode[ListeningStats](t, resp)
	var podcast *MediaTypeListening
	for i, m := range stats.ByMediaType {
		if m.MediaType == StatsMediaTypePodcast {
			podcast = &stats.ByMediaType[i]
		}
	}
	if podcast == nil {
		t.Fatalf("no podcast slice: %+v", stats.ByMediaType)
	}
	if podcast.Ms != 2*epMs || podcast.Sessions != 2 {
		t.Fatalf("podcast slice = %+v, want %dms over 2 sessions", *podcast, 2*epMs)
	}

	// And the show top list groups both episodes under the show.
	resp = get(t, h.ts, "/api/v1/stats/top?kind=shows&range=30d", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("top shows status = %d", resp.StatusCode)
	}
	top := decode[TopList](t, resp)
	if len(top.Entries) != 1 {
		t.Fatalf("top shows = %+v, want the one subscribed show", top.Entries)
	}
	e := top.Entries[0]
	if e.Name != "Fixture Cast" {
		t.Fatalf("top show name = %q, want the show title", e.Name)
	}
	if e.Ms != 2*epMs || e.Plays != 2 {
		t.Fatalf("top show entry = %+v, want both episodes summed", e)
	}
}
