package api

import (
	"testing"
)

// TestUnfetchKeepsTheEpisodeInTheShow is the hub disagreeing with the
// show.
//
// Removing a download used to trash the item, and every delete mode
// archives an item on losing its last file - so `countShow`, which
// counts through visibleItems(), stopped seeing an episode that
// `/podcasts/{pid}/episodes` still listed. A three-episode feed read
// "2 unplayed" on the hub beside three unplayed episodes on the show,
// and because the file is one shared catalog row, one subscriber's
// unfetch moved every subscriber's count.
//
// The listing is the surface that was right: an unfetched episode is
// still an episode of the feed and still streams by enclosure
// passthrough, which podcasts.spec.ts pins.
func TestUnfetchKeepsTheEpisodeInTheShow(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 3)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)

	eps := decode[EpisodePage](t, get(t, h.ts,
		"/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 3 {
		t.Fatalf("episodes = %d, want 3", len(eps))
	}
	if got := showEpisodeCount(t, h, sub.Show.Pid); got != 3 {
		t.Fatalf("hub count before any fetch = %d, want 3", got)
	}

	// Fetch one, then unfetch it. Both counts have to hold at three the
	// whole way: an episode's presence in the show is about the feed,
	// not about whether this server holds its bytes.
	target := eps[1]
	resp = h.postJSON(t, "/api/v1/episodes/"+target.Pid+"/fetch", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("fetch status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainFetches(t, h)

	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+target.Pid+"/fetch", h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("unfetch status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	after := decode[EpisodePage](t, get(t, h.ts,
		"/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(after) != 3 {
		t.Errorf("episodes after unfetch = %d, want 3", len(after))
	}
	for _, ep := range after {
		if ep.Pid == target.Pid && ep.Downloaded {
			t.Errorf("the unfetched episode still reads downloaded")
		}
	}
	if got := showEpisodeCount(t, h, sub.Show.Pid); got != len(after) {
		t.Errorf("hub count = %d while the show lists %d", got, len(after))
	}

	// A second subscriber reads the same numbers, which is where the
	// sharing bit showed: one catalog row, every account's tile.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	other := loginAs(t, h.ts, "sam", testPassword)
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", other.Token,
		map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 && resp.StatusCode != 200 {
		t.Fatalf("second subscribe status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	theirs := decode[EpisodePage](t, reqAs(t, h, "GET",
		"/api/v1/podcasts/"+sub.Show.Pid+"/episodes", other.Token, nil)).Items
	if len(theirs) != 3 {
		t.Errorf("second subscriber's episodes = %d, want 3", len(theirs))
	}
	if got := showEpisodeCountAs(t, h, other.Token, sub.Show.Pid); got != len(theirs) {
		t.Errorf("second subscriber's hub count = %d while their show lists %d", got, len(theirs))
	}
}

func showEpisodeCount(t *testing.T, h *harness, showPID string) int {
	t.Helper()
	return showEpisodeCountAs(t, h, h.token, showPID)
}

// showEpisodeCountAs reads one show's tile count off the subscriptions
// hub, which is the surface that disagreed with the show screen.
func showEpisodeCountAs(t *testing.T, h *harness, token, showPID string) int {
	t.Helper()
	page := decode[SubscriptionPage](t, reqAs(t, h, "GET", "/api/v1/podcasts", token, nil))
	for _, row := range page.Items {
		if row.Show.Pid == showPID {
			if row.Show.EpisodeCount == nil {
				t.Fatalf("show %s reports no episodeCount", showPID)
			}
			return *row.Show.EpisodeCount
		}
	}
	t.Fatalf("show %s is missing from the subscriptions hub", showPID)
	return 0
}
