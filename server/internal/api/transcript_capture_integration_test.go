package api

import (
	"testing"
)

// TestCaptureEpisodeTranscript covers the streamed-episode transcript
// capture: an episode a listener never downloads is not a transcript-search
// hit until captured; capture indexes it (a word that appears only in the
// transcript then finds it) without downloading the audio; an episode that
// announces no transcript is a clean 404; and re-capturing an indexed
// episode is a no-op success.
func TestCaptureEpisodeTranscript(t *testing.T) {
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
	// Newest first: [Episode 2, Episode 1]. Only Episode 1 announces a
	// transcript; neither is downloaded.
	epWithTx := page.Items[1]
	epNoTx := page.Items[0]
	if epWithTx.Downloaded {
		t.Fatal("episode 1 should be streamed, not downloaded")
	}
	if epWithTx.HasTranscript == nil || !*epWithTx.HasTranscript {
		t.Fatal("episode 1 should announce a transcript")
	}

	// "Hello" appears only in the transcript, so before capture the streamed
	// episode is not a transcript-search hit.
	searchHello := func() int {
		r := get(t, h.ts, "/api/v1/library/search?q=Hello", h.token)
		return len(decode[SearchResults](t, r).Episodes)
	}
	if n := searchHello(); n != 0 {
		t.Fatalf("pre-capture transcript search found %d episodes, want 0", n)
	}

	// Capture indexes the transcript without downloading the audio.
	resp = reqAs(t, h, "POST", "/api/v1/episodes/"+epWithTx.Pid+"/transcript", h.token, nil)
	wantStatus(t, resp, 204, "capture transcript")

	if n := searchHello(); n != 1 {
		t.Fatalf("post-capture transcript search found %d episodes, want 1", n)
	}

	// Re-capturing an already-indexed episode is a no-op success.
	resp = reqAs(t, h, "POST", "/api/v1/episodes/"+epWithTx.Pid+"/transcript", h.token, nil)
	wantStatus(t, resp, 204, "re-capture transcript")

	// An episode that announces no transcript is a clean 404.
	resp = reqAs(t, h, "POST", "/api/v1/episodes/"+epNoTx.Pid+"/transcript", h.token, nil)
	wantStatus(t, resp, 404, "capture without transcript")
}
