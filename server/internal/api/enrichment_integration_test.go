package api

import (
	"context"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// fakeBookProvider is a book-metadata enrich provider that returns a fixed
// candidate, for driving the enrichBook provider loop from a test.
type fakeBookProvider struct {
	name string
	cand *enrich.Candidate
}

func (f fakeBookProvider) Name() string                    { return f.name }
func (f fakeBookProvider) Capabilities() enrich.Capability { return enrich.CapBookMeta }
func (f fakeBookProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return f.cand, nil
}

// A provider whose only novel value is one WaxBin would reject (a bad-checksum
// ISBN) must not end the enrich pass: enrichBook has to fall through to the next
// provider, which here supplies a valid publisher. Regression guard for the
// skip-refactor that briefly returned early on an all-malformed candidate.
func TestEnrichBookFallsThroughMalformedProvider(t *testing.T) {
	t.Parallel()
	bad := fakeBookProvider{name: "bad", cand: &enrich.Candidate{ISBN: "9780306406158"}}     // valid shape, bad checksum
	good := fakeBookProvider{name: "good", cand: &enrich.Candidate{Publisher: "Beta House"}} // valid, fills the gap
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{bad, good}
	})
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) == 0 {
		t.Fatal("no audiobook scanned")
	}
	book := books.Items[0].Pid

	// Book providers key on ASIN, so the item needs one before enrichBook runs.
	resp := h.patchJSON(t, "/api/v1/items/"+book+"/metadata", map[string]any{
		"fields": map[string]string{"asin": "B000002L5R"},
	})
	wantStatus(t, resp, 200, "set asin")

	resp = h.postJSON(t, "/api/v1/items/"+book+"/enrich", map[string]any{"want": []string{"book"}})
	wantStatus(t, resp, 200, "enrich book")

	// The bad provider ran first and offered only the malformed ISBN; the good
	// provider's publisher lands only if the pass fell through instead of ending.
	if got := h.itemMeta(t, book).Fields["publisher"]; got != "Beta House" {
		t.Fatalf("publisher = %q, want Beta House - enrich did not fall through the malformed provider", got)
	}
}

// fakeCoverProvider is a cover-art enrich provider returning a fixed image,
// for driving the enrichCover provider loop from a test.
type fakeCoverProvider struct {
	name  string
	cover *model.ArtImage
}

func (f fakeCoverProvider) Name() string                    { return f.name }
func (f fakeCoverProvider) Capabilities() enrich.Capability { return enrich.CapCover }
func (f fakeCoverProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return &enrich.Candidate{Cover: f.cover}, nil
}

// A cover the server fetched must not report itself as one a person chose.
// The enrich-now path holds the provider's name one line from the write, and
// this is what keeps it from being thrown away: the stored cover names the
// provider and the URL it came from, which is the difference between "someone
// picked this" and "a service offered it".
func TestEnrichCoverRecordsTheProviderThatSuppliedIt(t *testing.T) {
	t.Parallel()
	const sourceURL = "https://example.invalid/covers/fixture.png"
	p := fakeCoverProvider{name: "fixturecovers", cover: &model.ArtImage{
		Data:        tinyPNG(t),
		Attribution: model.Attribution{SourceURL: sourceURL},
	}}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid

	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{"want": []string{"cover"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("enrich cover status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if len(res.Applied) == 0 {
		t.Fatalf("nothing applied: applied=%v skipped=%v", res.Applied, res.Skipped)
	}

	art := getArt(t, h, "/api/v1/items/"+pid+"/art", "")
	art.Body.Close()
	if got := art.Header.Get("X-Art-Source"); got != "enrichment" {
		t.Errorf("X-Art-Source = %q, want enrichment - a fetched cover reads as hand-set", got)
	}
	if got := art.Header.Get("X-Art-Provider"); got != p.name {
		t.Errorf("X-Art-Provider = %q, want %q", got, p.name)
	}
	if got := art.Header.Get("X-Art-Source-Url"); got != sourceURL {
		t.Errorf("X-Art-Source-Url = %q, want %q", got, sourceURL)
	}

	// Enrichment forms no pin intent, so the slot it filled stays unpinned
	// and a later hand-set cover replaces it without a force.
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	front, ok := roleNamed(roles, "front")
	if !ok {
		t.Fatalf("art-roles missing front: %+v", roles.Roles)
	}
	if front.Locked != nil && *front.Locked {
		t.Error("the enriched cover pinned the slot; enrichment states no lock intent")
	}
}

// The catalog holds item-level art for tracks and books only, so an
// episode cover write is refused whatever the bytes are. The want has to
// say that up front rather than calling every cover provider first: the
// old order fetched a picture over somebody's network, had the store
// refuse it, and reported "no provider hit" - which reads as a lookup
// that missed, and re-fetches on the next request.
func TestEnrichCoverSkipsEpisodesWithoutFetching(t *testing.T) {
	t.Parallel()
	var called int
	p := countingCoverProvider{name: "shouldnotrun", calls: &called}
	h := newPodcastHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	feed := newFeedServer(t, 1)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show.Pid

	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	eps := decode[EpisodePage](t, resp).Items
	if len(eps) == 0 {
		t.Fatal("the feed fixture produced no episodes")
	}

	resp = h.postJSON(t, "/api/v1/items/"+eps[0].Pid+"/enrich", map[string]any{"want": []string{"cover"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("enrich status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if len(res.Applied) != 0 {
		t.Errorf("applied = %v, want nothing: an episode cannot hold its own cover", res.Applied)
	}
	if len(res.Skipped) != 1 || !strings.Contains(res.Skipped[0], "feed") {
		t.Errorf("skipped = %v, want one reason naming the feed", res.Skipped)
	}
	if called != 0 {
		t.Errorf("cover provider called %d times for an episode; the guard runs before the fetch", called)
	}
}

// countingCoverProvider records whether the cover loop reached it.
type countingCoverProvider struct {
	name  string
	calls *int
}

func (f countingCoverProvider) Name() string                    { return f.name }
func (f countingCoverProvider) Capabilities() enrich.Capability { return enrich.CapCover }
func (f countingCoverProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	*f.calls++
	return nil, nil
}
