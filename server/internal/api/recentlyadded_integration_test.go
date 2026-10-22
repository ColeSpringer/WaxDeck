package api

import (
	"net/http"
	"testing"
	"time"
)

// listedTitles is a page's titles in order, for a failure that reads.
func listedTitles(page ItemPage) []string {
	out := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		out = append(out, it.Title)
	}
	return out
}

// Subscribing to a show inserts its episodes at the head of every
// created-at ordering, so a "recently added" list that mixed them in
// handed the first page to the show and pushed the music off it. Episodes
// have their own lists; the unfiltered one is music and books, and asking
// for podcasts by name still lists them.
func TestRecentlyAddedLeavesEpisodesToTheirOwnList(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 3)

	library := browsePage(t, h, "?list=recently-added&limit=50")
	if len(library.Items) == 0 {
		t.Fatal("the demo library lists nothing as recently added")
	}
	head := library.Items[0]

	sub := decode[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}))

	for _, query := range []string{
		"?list=recently-added&limit=1",
		"?list=recently-added&limit=50",
	} {
		page := browsePage(t, h, query)
		if len(page.Items) == 0 || page.Items[0].Pid != head.Pid {
			t.Errorf("%s lists %q after subscribing, want it to open on %q", query, listedTitles(page), head.Title)
		}
		for _, it := range page.Items {
			if it.MediaType == MediaTypePodcast {
				t.Errorf("%s lists the episode %q", query, it.Title)
			}
		}
	}

	// Asked for by name, the episodes are still there.
	named := browsePage(t, h, "?list=recently-added&mediaType=podcast&limit=50")
	if len(named.Items) != 3 {
		t.Errorf("recently-added podcasts = %d items, want the show's 3 episodes", len(named.Items))
	}
	drilled := browsePage(t, h, "?list=recently-added&facet=kind&facetKey=episode&limit=50")
	if len(drilled.Items) != 3 {
		t.Errorf("recently-added drilled to the episode kind = %q, want the show's 3 episodes", listedTitles(drilled))
	}
	if eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)); len(eps.Items) != 3 {
		t.Errorf("the show lists %d episodes, want 3", len(eps.Items))
	}
}

// A follower and a stranger to the show read the same unfiltered list,
// and both pages are full: the scope is in the query, and the episodes
// are not in the list at all.
func TestRecentlyAddedPagesAreFullForFollowersAndStrangers(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 3)
	wantStatus(t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}),
		http.StatusCreated, "the admin follows the show")
	_, stranger := listenerAccount(t, h, "stranger", true)

	for name, token := range map[string]string{"the follower": h.token, "a stranger": stranger} {
		page := decodeStatus[ItemPage](t, get(t, h.ts, "/api/v1/library/browse?list=recently-added&limit=1", token),
			http.StatusOK, name)
		if len(page.Items) != 1 {
			t.Fatalf("%s: first page holds %d items (next %v), want one", name, len(page.Items), page.NextCursor)
		}
		if page.Items[0].MediaType == MediaTypePodcast {
			t.Errorf("%s: first page opens on the episode %q", name, page.Items[0].Title)
		}
	}
}

// An episode's detail dates it by the clock the lists sort by: when the
// feed first listed it here. An episode nobody has fetched has no file to
// date, and fetching one later must not move the date.
func TestEpisodeDetailCarriesAddedAtBeforeAnyFetch(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	start := time.Now().Add(-time.Second)
	sub := decode[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}))
	end := time.Now().Add(time.Second)
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 2 || eps[0].Downloaded {
		t.Fatalf("episodes = %+v, want two unfetched", eps)
	}

	added := func() *time.Time {
		t.Helper()
		return decodeStatus[Item](t, get(t, h.ts, "/api/v1/items/"+eps[0].Pid, h.token), http.StatusOK, "episode detail").AddedAt
	}
	before := added()
	if before == nil {
		t.Fatal("an unfetched episode's detail carries no addedAt")
	}
	if before.Before(start) || before.After(end) {
		t.Fatalf("addedAt = %s, want when the feed was subscribed (%s to %s)", before, start, end)
	}

	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+eps[0].Pid+"/fetch", nil), http.StatusAccepted, "fetch")
	drainFetches(t, h)
	if got := added(); got == nil || !got.Equal(*before) {
		t.Errorf("addedAt after the fetch = %v, want it unmoved at %s", got, before)
	}
}
