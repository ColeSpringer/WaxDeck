package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// A feed that still declares the Podcasting 2.0 namespace at the address
// it lived at before podcastindex.org reads the same as one that declares
// it at the current one: the show's credits, the episode's chapters and
// its transcript all arrive. The parser that aliases the old spelling is
// the catalog's; this pins it from here, so a bump that loses it fails in
// this repository rather than in somebody's feed.
func TestLegacyPodcastNamespaceFeed(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	dir := t.TempDir()
	host := httptest.NewServer(http.FileServer(http.Dir(dir)))
	t.Cleanup(host.Close)
	feed := fixtures.FeedSpec{
		Title:           "Legacy Namespace Cast",
		Author:          "Legacy Host",
		Description:     "A show whose feed declares the old namespace address.",
		LegacyNamespace: true,
		Persons: []fixtures.PersonSpec{
			{Name: "Old Host", Role: "Host", Href: "https://example.com/old-host"},
		},
		Episodes: []fixtures.EpisodeSpec{{
			Title:   "Legacy Pilot",
			GUID:    "wd-legacy-ns-ep-001",
			PubDate: time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC),
			Spec: fixtures.Spec{
				Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
				Tags: map[string]string{"TITLE": "Legacy Pilot", "ARTIST": "Legacy Host", "ALBUM": "Legacy Namespace Cast"},
			},
			TranscriptVTT: "WEBVTT\n\n00:00.000 --> 00:01.500\nHello from the old address\n",
			ChaptersJSON:  `{"version":"1.2.0","chapters":[{"startTime":0,"title":"Before"},{"startTime":2,"title":"After"}]}`,
		}},
	}
	if _, err := fixtures.GeneratePodcastFeed(dir, feed, host.URL); err != nil {
		t.Fatal(err)
	}

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": host.URL + "/feed.xml"})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)

	show := decodeStatus[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid, h.token),
		http.StatusOK, "show detail").Show
	if show.Persons == nil || len(*show.Persons) != 1 {
		t.Fatalf("show persons = %+v, want the one credit", show.Persons)
	}
	if host := (*show.Persons)[0]; host.Name != "Old Host" ||
		host.Role == nil || *host.Role != "host" ||
		host.Href == nil || *host.Href != "https://example.com/old-host" {
		t.Fatalf("host credit = %+v", host)
	}

	eps := decodeStatus[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token),
		http.StatusOK, "episodes").Items
	if len(eps) != 1 {
		t.Fatalf("episodes = %d, want 1", len(eps))
	}
	if eps[0].HasTranscript == nil || !*eps[0].HasTranscript {
		t.Error("the episode does not announce its transcript")
	}
	// Nothing fetched the episode, so these chapters come from the pointer
	// the legacy spelling carried.
	detail := decodeStatus[Episode](t, get(t, h.ts, "/api/v1/episodes/"+eps[0].Pid, h.token),
		http.StatusOK, "episode detail")
	if detail.Chapters == nil || len(*detail.Chapters) != 2 {
		t.Fatalf("episode chapters = %+v, want two", detail.Chapters)
	}
	for i, want := range []struct {
		title string
		start int64
	}{{"Before", 0}, {"After", 2000}} {
		got := (*detail.Chapters)[i]
		if got.Title == nil || *got.Title != want.title || got.StartMs != want.start {
			t.Errorf("chapter %d = %+v, want %q at %d ms", i, got, want.title, want.start)
		}
	}
}
