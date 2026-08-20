package api

import (
	"strings"
	"testing"
)

// TestPrivateFeedArtURLIsWithheld covers the one place a cover's
// provenance is somebody's credential.
//
// A feed cover's source URL is minted from the feed document and lives
// on the feed's host, so a credentialed show's channel image sits on
// the same tokenized path its feed does - the value `showDTO` already
// withholds, OPML export skips, shares refuse, and feed errors scrub.
// The art source is the newest way to ask for it, and it reaches four
// read paths at once (the show detail, an episode's item read, the
// art-roles read, and the `X-Art-Source-Url` header on the bytes), so
// the withholding lives under all four rather than at each.
//
// The rest of the attribution stays: what the caller loses is the
// address, not the fact that the picture came from the feed.
func TestPrivateFeedArtURLIsWithheld(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url":      fs.feedURL(),
		"username": "member",
		"password": "s3cret",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show

	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	// The feed URL itself is the rule this follows; if it ever stopped
	// being withheld the art URL would be the least of it.
	if got := deref(detail.FeedUrl); got != "" {
		t.Fatalf("a credentialed feed URL was reported at all: %q", got)
	}
	if detail.ArtSource == nil {
		t.Fatal("a private show reported no art source; the attribution is not the secret, the address is")
	}
	if detail.ArtSource.Source != "feed" {
		t.Errorf("show art source = %q, want feed", detail.ArtSource.Source)
	}
	if got := deref(detail.ArtSource.SourceUrl); got != "" {
		t.Errorf("a private show's cover reported its address: %q", got)
	}

	// The byte endpoint's header form of the same four values.
	res := get(t, h.ts, "/api/v1/items/"+show.Pid+"/art", h.token)
	defer res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("art status = %d", res.StatusCode)
	}
	if got := res.Header.Get("X-Art-Source"); got != "feed" {
		t.Errorf("X-Art-Source = %q, want feed", got)
	}
	if got := res.Header.Get("X-Art-Source-Url"); got != "" {
		t.Errorf("X-Art-Source-Url leaked a private feed's address: %q", got)
	}
}

// TestPublicFeedArtURLIsReported is the other half: withholding has to
// cost something, so a show nobody credentialed still cites where its
// picture came from. Without this the fix above could be "never report
// a feed URL" and pass.
func TestPublicFeedArtURLIsReported(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show

	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil {
		t.Fatal("a public show reported no art source")
	}
	if got := deref(detail.ArtSource.SourceUrl); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("show art sourceUrl = %q, want the feed's image", got)
	}
	res := get(t, h.ts, "/api/v1/items/"+show.Pid+"/art", h.token)
	defer res.Body.Close()
	if got := res.Header.Get("X-Art-Source-Url"); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("X-Art-Source-Url = %q, want the feed's image", got)
	}
}
