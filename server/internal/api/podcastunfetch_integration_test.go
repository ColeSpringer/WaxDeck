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

// TestDeleteItemsRefusesEpisodes pins the other half of the podcast
// tree's ownership: its files are not the catalog delete's to take, so
// naming one refuses instead of trashing it. The refusal is WaxDeck's
// own words - the catalog's names a CLI verb this server does not have -
// and it is the whole call, so a caller never learns that some of a
// batch went through.
func TestDeleteItemsRefusesEpisodes(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	eps := decode[EpisodePage](t, get(t, h.ts,
		"/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	episode := eps[0].Pid

	// A downloaded one, so the refusal is not standing in for "no file
	// to delete".
	resp = h.postJSON(t, "/api/v1/episodes/"+episode+"/fetch", nil)
	resp.Body.Close()
	drainFetches(t, h)

	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{episode},
	})
	wantStatus(t, resp, 400, "deleting an episode")

	// Mixed batch: the track is deletable on its own, and the episode
	// beside it stops the whole call rather than taking the track with
	// it.
	page := h.items(t, "?mediaType=music")
	if len(page.Items) == 0 {
		t.Fatal("no music items to pair with the episode")
	}
	track := page.Items[0].Pid
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{track, episode},
	})
	wantStatus(t, resp, 400, "deleting a mixed batch")

	after := h.items(t, "?mediaType=music")
	for _, it := range after.Items {
		if it.Pid == track {
			return
		}
	}
	t.Fatalf("track %s left the listing; the refused batch deleted part of itself", track)
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

// TestPlaylistCountScopesEpisodesToSubscribers is the third clause of
// the count's narrow, and the one only a podcast harness can reach.
//
// An episode may be a playlist member like anything else, and
// subscriptions are per-user views: a shared list holding an episode
// counts it for a subscriber and not for anybody else. The count is a
// query now, so this scoping had to move into the query with it - a
// listing row that still counted every member would tell a
// non-subscriber a list is longer than the members it hands them.
func TestPlaylistCountScopesEpisodesToSubscribers(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	episode := decode[EpisodePage](t, get(t, h.ts,
		"/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0].Pid

	// One music track beside it, so a wrong answer is a wrong number
	// rather than an empty list.
	track := h.items(t, "?mediaType=music").Items[0].Pid
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Mixed", "kind": "static", "visibility": "shared",
		"itemPids": []string{track, episode},
	})
	pl := decode[Playlist](t, resp)
	if pl.ItemCount == nil || *pl.ItemCount != 2 {
		t.Fatalf("subscriber's count = %v, want 2", pl.ItemCount)
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	// Sam follows nothing, so the episode is not theirs to see. The
	// listing row and the opened list have to say so together.
	theirs := decode[Playlist](t, reqAs(t, h, "GET", "/api/v1/playlists/"+pl.Pid, sam.Token, nil))
	if theirs.ItemCount == nil || *theirs.ItemCount != 1 {
		t.Errorf("non-subscriber's count = %v, want 1", theirs.ItemCount)
	}
	items := decode[PlaylistItemsPage](t, reqAs(t, h, "GET",
		"/api/v1/playlists/"+pl.Pid+"/items", sam.Token, nil)).Entries
	if len(items) != 1 {
		t.Errorf("non-subscriber's member listing holds %d, want 1", len(items))
	}
	for _, row := range decode[PlaylistPage](t, reqAs(t, h, "GET",
		"/api/v1/playlists", sam.Token, nil)).Playlists {
		if row.Pid != pl.Pid {
			continue
		}
		if row.ItemCount == nil || *row.ItemCount != 1 {
			t.Errorf("non-subscriber's listing row = %v, want 1", row.ItemCount)
		}
	}

	// And once Sam subscribes, the same list counts two for them too.
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", sam.Token, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()
	theirs = decode[Playlist](t, reqAs(t, h, "GET", "/api/v1/playlists/"+pl.Pid, sam.Token, nil))
	if theirs.ItemCount == nil || *theirs.ItemCount != 2 {
		t.Errorf("count after subscribing = %v, want 2", theirs.ItemCount)
	}
}
