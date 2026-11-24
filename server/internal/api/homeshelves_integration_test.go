package api

import (
	"fmt"
	"net/http"
	"testing"
)

// Home draws its shelves from these lists. A show's backlog is hundreds of
// episodes nobody has played, so an unfiltered list that held them would
// crowd out the music and books the shelf is for. Naming podcasts, by
// medium or by the kind dimension, still lists the episodes.
func TestHomeShelvesLeaveEpisodesOut(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 3)
	sub := decode[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}))
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 3 {
		t.Fatalf("the show lists %d episodes, want 3", len(eps))
	}
	music := h.items(t, "?mediaType=music").Items
	if len(music) < 2 {
		t.Fatalf("the demo library listed %d tracks; this needs several", len(music))
	}

	isEpisode := map[string]bool{}
	for _, ep := range eps {
		isEpisode[ep.Pid] = true
	}

	// The admin plays every episode and one track (most-played). A second
	// listener who follows the show stars the same episodes and another
	// track without playing anything (rediscover, and never-played where
	// every episode qualifies).
	_, other := listenerAccount(t, h, "shelf-listener", true)
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/podcasts", other, map[string]any{"url": feed.feedURL()}),
		http.StatusCreated, "the second listener follows the show")
	for i, ep := range eps {
		reportListen(t, h, fmt.Sprintf("shelf-ep-%d", i), ep.Pid, 1000)
		wantStatus(t, reqAs(t, h, "PUT", "/api/v1/items/"+ep.Pid+"/star", other, map[string]any{"starred": true}),
			200, "star an episode")
	}
	reportListen(t, h, "shelf-track", music[1].Pid, music[1].DurationMs)
	wantStatus(t, reqAs(t, h, "PUT", "/api/v1/items/"+music[0].Pid+"/star", other, map[string]any{"starred": true}),
		200, "star a track")

	for _, tc := range []struct {
		list  string
		token string
		want  string // a track that must stay on the list
	}{
		{"never-played", other, music[0].Pid},
		{"rediscover", other, music[0].Pid},
		{"most-played", h.token, music[1].Pid},
	} {
		t.Run(tc.list, func(t *testing.T) {
			read := func(query string) ItemPage {
				t.Helper()
				return decodeStatus[ItemPage](t, get(t, h.ts, "/api/v1/library/browse?list="+tc.list+query, tc.token),
					200, tc.list+query)
			}

			page := read("&limit=100")
			if !pids(page)[tc.want] {
				t.Fatalf("%s lists %q, want the track %s on it", tc.list, listedTitles(page), tc.want)
			}
			for _, it := range page.Items {
				if isEpisode[it.Pid] {
					t.Errorf("%s lists the episode %q", tc.list, it.Title)
				}
			}

			named := read("&mediaType=podcast&limit=100")
			if len(named.Items) != 3 {
				t.Errorf("%s with mediaType=podcast = %q, want the show's 3 episodes", tc.list, listedTitles(named))
			}
			drilled := read("&facet=kind&facetKey=episode&limit=100")
			if len(drilled.Items) != 3 {
				t.Errorf("%s drilled to the episode kind = %q, want the show's 3 episodes", tc.list, listedTitles(drilled))
			}
		})
	}

	// Continue listening stays across every medium: an episode the second
	// listener started is on it with no mediaType named.
	wantStatus(t, reqAs(t, h, "PUT", "/api/v1/items/"+eps[0].Pid+"/play-state", other, map[string]any{"positionMs": 1000}),
		http.StatusNoContent, "start an episode")
	started := decodeStatus[ItemPage](t, get(t, h.ts, "/api/v1/library/browse?list=in-progress&limit=100", other),
		200, "in-progress")
	if !pids(started)[eps[0].Pid] {
		t.Errorf("in-progress lists %q, want the started episode on it", listedTitles(started))
	}
}
