package api

import (
	"context"
	"strings"
	"sync"
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

	// Book providers key on an identifier, so the item needs one before
	// enrichBook runs.
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

// captureBookProvider records the request it was asked and answers a
// fixed candidate, for asserting what the enrich pass hands providers.
type captureBookProvider struct {
	seen chan enrich.Request
	cand *enrich.Candidate
}

func (c captureBookProvider) Name() string                    { return "capture" }
func (c captureBookProvider) Capabilities() enrich.Capability { return enrich.CapBookMeta }
func (c captureBookProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	select {
	case c.seen <- req:
	default:
	}
	return c.cand, nil
}

// An audiobook carrying an ISBN and no ASIN still reaches the book
// providers, and the request hands them the stored ISBN - the seam the
// ISBN-keyed fallbacks (Google Books, Open Library) key their lookups
// on, and the reason the guard reads "ASIN or ISBN" rather than the
// ASIN alone it required before those providers existed.
func TestEnrichBookRunsOnAnISBNAlone(t *testing.T) {
	t.Parallel()
	p := captureBookProvider{
		seen: make(chan enrich.Request, 1),
		cand: &enrich.Candidate{Publisher: "Bridge House"},
	}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
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

	const isbn = "9780306406157"
	resp := h.patchJSON(t, "/api/v1/items/"+book+"/metadata", map[string]any{
		"fields": map[string]string{"isbn": isbn},
	})
	wantStatus(t, resp, 200, "set isbn")

	resp = h.postJSON(t, "/api/v1/items/"+book+"/enrich", map[string]any{"want": []string{"book"}})
	wantStatus(t, resp, 200, "enrich book")

	select {
	case req := <-p.seen:
		if req.ISBN != isbn {
			t.Errorf("provider request ISBN = %q, want the stored one", req.ISBN)
		}
		if req.ASIN != "" {
			t.Errorf("provider request ASIN = %q, want empty", req.ASIN)
		}
	default:
		t.Fatal("the book provider was never asked")
	}
	if got := h.itemMeta(t, book).Fields["publisher"]; got != "Bridge House" {
		t.Errorf("publisher = %q, want the provider's fill", got)
	}
}

// A proposal commit is client-supplied values, so it re-checks the
// identifier precondition the propose half enforces: without this, an
// audiobook no provider could ever have been asked about (no ASIN, no
// ISBN) would still take hand-built fields stamped with a registered
// provider's provenance mark.
func TestEnrichCommitRefusesAnIdentifierlessBook(t *testing.T) {
	t.Parallel()
	p := fakeBookProvider{name: "capture", cand: &enrich.Candidate{Publisher: "Real House"}}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
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

	resp := h.postJSON(t, "/api/v1/items/"+book+"/enrich", map[string]any{
		"want": []string{"book"},
		"proposal": map[string]any{
			"fields": []map[string]any{
				{"name": "publisher", "proposed": "Forged House", "provider": "capture"},
			},
		},
	})
	wantStatus(t, resp, 200, "commit on an identifier-less book")
	if got := h.itemMeta(t, book).Fields["publisher"]; got != "" {
		t.Errorf("publisher = %q, want the identifier-less commit refused", got)
	}
}

// scopedGenreProvider records the want each ask carried, proving the
// propose loops stamp Request.Want rather than leaving it zero - the
// seam that keeps a multi-capability provider (Discogs) from
// downloading a cover on every genre ask. A zero want is the
// everything contract, so an unstamped ask is the failure to catch.
type scopedGenreProvider struct {
	mu    sync.Mutex
	wants []enrich.Capability
}

func (s *scopedGenreProvider) Name() string { return "scopey" }
func (s *scopedGenreProvider) Capabilities() enrich.Capability {
	return enrich.CapGenres | enrich.CapCover
}
func (s *scopedGenreProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	s.mu.Lock()
	s.wants = append(s.wants, req.Want)
	s.mu.Unlock()
	return &enrich.Candidate{Genres: []string{"House"}}, nil
}

func TestEnrichStampsTheWantOnTheRequest(t *testing.T) {
	t.Parallel()
	p := &scopedGenreProvider{}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid

	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{"want": []string{"genres"}})
	wantStatus(t, resp, 200, "enrich genres")

	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.wants) != 1 || p.wants[0] != enrich.CapGenres {
		t.Errorf("stamped wants = %v, want one CapGenres ask", p.wants)
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

// The preview is a read: it reports exactly what the providers would
// store - proposal rows and the cover bytes - and the item afterwards
// is byte-for-byte what it was before. Passing that same answer back
// as the proposal then lands it, which is the whole preview contract
// exercised end to end.
func TestEnrichPreviewWritesNothingAndItsProposalApplies(t *testing.T) {
	t.Parallel()
	book := fakeBookProvider{name: "bookfacts", cand: &enrich.Candidate{Publisher: "Beta House"}}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{book}
	})
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) == 0 {
		t.Fatal("no audiobook scanned")
	}
	pid := books.Items[0].Pid
	resp := h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"asin": "B000002L5R"}, "lock": false,
	})
	wantStatus(t, resp, 200, "set asin")

	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich/preview", map[string]any{"want": []string{"book"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("preview status = %d", resp.StatusCode)
	}
	preview := decode[EnrichPreview](t, resp)
	if len(preview.Fields) != 1 || preview.Fields[0].Name != "publisher" ||
		preview.Fields[0].Proposed != "Beta House" || preview.Fields[0].Provider != "bookfacts" {
		t.Fatalf("preview fields = %+v, want one publisher row from bookfacts", preview.Fields)
	}

	// The preview stored nothing: the publisher gap it reported is still a gap.
	if got := h.itemMeta(t, pid).Fields["publisher"]; got != "" {
		t.Fatalf("publisher = %q after a preview; a preview must not write", got)
	}

	// The preview's own answer is the proposal.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want":     []string{"book"},
		"proposal": map[string]any{"fields": preview.Fields},
	})
	wantStatus(t, resp, 200, "apply")
	if got := h.itemMeta(t, pid).Fields["publisher"]; got != "Beta House" {
		t.Fatalf("publisher = %q after apply, want the previewed proposal committed", got)
	}
}

// An apply that carries a proposal commits it verbatim and consults no
// provider: a fresh fetch could answer differently than the preview the
// user approved. The injected provider counts its calls, and the stored
// cover names the proposal's provider - one no live provider has.
func TestEnrichApplyCommitsTheProposalWithoutRefetching(t *testing.T) {
	t.Parallel()
	var called int
	p := countingCoverProvider{name: "livecovers", calls: &called}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid

	// The proposal names the registered provider - a preview's own answer
	// carries the name of the provider that supplied it - and the counter
	// is what proves the commit stored the bytes without consulting it.
	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"cover"},
		"proposal": map[string]any{"cover": map[string]any{
			"provider": "livecovers",
			"data":     tinyPNG(t),
			"format":   "png",
		}},
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("apply status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if !containsString(res.Applied, "cover: livecovers") {
		t.Fatalf("applied = %v, want the proposal's cover committed", res.Applied)
	}
	if called != 0 {
		t.Fatalf("cover provider called %d times on an apply-with-proposal; the commit must not fetch", called)
	}
	art := getArt(t, h, "/api/v1/items/"+pid+"/art", "")
	art.Body.Close()
	if got := art.Header.Get("X-Art-Provider"); got != "livecovers" {
		t.Errorf("X-Art-Provider = %q, want the proposal's provider", got)
	}
}

// The commit re-runs the local guards: a field filled between the
// preview and the apply is skipped with the reason, never overwritten.
func TestEnrichApplySkipsWhatFilledSinceThePreview(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{
			fakeBookProvider{name: "stalepreview"},
		}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	resp := h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"genre": "Ambient"}, "lock": false,
	})
	wantStatus(t, resp, 200, "hand-set genre")

	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"genres"},
		"proposal": map[string]any{"fields": []map[string]any{{
			"name": "genre", "proposed": "Jazz", "provider": "stalepreview",
		}}},
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("apply status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if !containsString(res.Skipped, "genres: already present") {
		t.Fatalf("skipped = %v, want the already-present guard", res.Skipped)
	}
	if got := h.itemMeta(t, pid).Fields["genre"]; got != "Ambient" {
		t.Fatalf("genre = %q, want the hand-set value kept", got)
	}
}

// A proposal can only carry fields enrichment proposes; anything else
// is a caller error, refused before any write.
func TestEnrichApplyRefusesForeignProposalFields(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	resp := h.postJSON(t, "/api/v1/items/"+page.Items[0].Pid+"/enrich", map[string]any{
		"want": []string{"genres"},
		"proposal": map[string]any{"fields": []map[string]any{{
			"name": "title", "proposed": "Renamed", "provider": "sneaky",
		}}},
	})
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("apply with a title proposal status = %d, want 400", resp.StatusCode)
	}
}

// The whole proposal validates before the first write: a refusal must
// mean nothing landed, not that the valid half landed and the response
// then said 400 as if it had not.
func TestEnrichApplyRefusesTheWholeProposalBeforeAnyWrite(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{
			fakeBookProvider{name: "bookfacts"},
		}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid
	resp := h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"genre": ""}, "lock": false,
	})
	wantStatus(t, resp, 200, "clear genre")

	// A valid genre row rides ahead of the foreign field; committing in
	// row order before validating would land it.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"genres"},
		"proposal": map[string]any{"fields": []map[string]any{
			{"name": "genre", "proposed": "Jazz", "provider": "bookfacts"},
			{"name": "title", "proposed": "Renamed", "provider": "bookfacts"},
		}},
	})
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("mixed proposal status = %d, want 400", resp.StatusCode)
	}
	if got := h.itemMeta(t, pid).Fields["genre"]; got != "" {
		t.Fatalf("genre = %q after a refused proposal; a 400 must mean nothing landed", got)
	}
}

// A proposal only answers the wants beside it, and its providers must
// be registered on the port: the proposal is the preview's own answer
// passed back, so a cover nobody asked for or a name no provider
// carries is refused rather than stored under a false mark.
func TestEnrichApplyRefusesWantMismatchAndForeignProviders(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{
			fakeBookProvider{name: "bookfacts"},
		}
	})
	page := h.items(t, "")
	if len(page.Items) == 0 {
		t.Fatal("no items in the demo library")
	}
	pid := page.Items[0].Pid

	// A cover the request did not want.
	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"genres"},
		"proposal": map[string]any{"cover": map[string]any{
			"provider": "bookfacts", "data": tinyPNG(t),
		}},
	})
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("unwanted cover status = %d, want 400", resp.StatusCode)
	}

	// A provider this server never registered.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"genres"},
		"proposal": map[string]any{"fields": []map[string]any{{
			"name": "genre", "proposed": "Jazz", "provider": "forged",
		}}},
	})
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("foreign provider status = %d, want 400", resp.StatusCode)
	}

	// Bytes that are not an image are refused whole, not stored as a
	// cover the art surface would then attribute to a provider.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"cover"},
		"proposal": map[string]any{"cover": map[string]any{
			"provider": "bookfacts", "data": []byte("not an image"),
		}},
	})
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("garbage cover status = %d, want 400", resp.StatusCode)
	}
}

// fakeFieldsProvider answers the fields capability on both rungs,
// recording the request so a test can prove the identifiers rode along.
type fakeFieldsProvider struct {
	mu     sync.Mutex
	name   string
	seen   []enrich.Request
	fields map[string]string
}

func (f *fakeFieldsProvider) Name() string {
	if f.name != "" {
		return f.name
	}
	return "factdb"
}
func (f *fakeFieldsProvider) Capabilities() enrich.Capability { return enrich.CapFields }
func (f *fakeFieldsProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	f.mu.Lock()
	f.seen = append(f.seen, req)
	f.mu.Unlock()
	if req.Type != enrich.TargetRecording {
		return nil, nil
	}
	return &enrich.Candidate{Confidence: 0.7, Fields: f.fields}, nil
}

func (f *fakeFieldsProvider) lastRecording() (enrich.Request, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for i := len(f.seen) - 1; i >= 0; i-- {
		if f.seen[i].Type == enrich.TargetRecording {
			return f.seen[i], true
		}
	}
	return enrich.Request{}, false
}

// The editor's Fetch offers a track's scalar fields, and the preview
// and commit halves agree: what the sheet showed is what lands.
func TestEnrichItemFillsTrackFields(t *testing.T) {
	t.Parallel()
	p := &fakeFieldsProvider{fields: map[string]string{
		"bpm": "123", "isrc": "GBDUW0000059", "composer": "Bangalter",
		// A key the track fill set does not take: dropped, never
		// written, and never proposed.
		"label": "Virgin",
	}}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	page := h.items(t, "?mediaType=music")
	if len(page.Items) == 0 {
		t.Fatal("no music items in the demo library")
	}
	pid := page.Items[0].Pid

	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich/preview",
		map[string]any{"want": []string{"fields"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("preview track fields status = %d", resp.StatusCode)
	}
	preview := decode[EnrichPreview](t, resp)
	got := map[string]string{}
	for _, f := range preview.Fields {
		got[f.Name] = f.Proposed
		if f.Provider != "factdb" {
			t.Errorf("%s cites provider %q", f.Name, f.Provider)
		}
	}
	if got["bpm"] != "123" || got["isrc"] != "GBDUW0000059" || got["composer"] != "Bangalter" {
		t.Fatalf("preview fields = %v, want the track's own three", got)
	}
	if _, ok := got["label"]; ok {
		t.Errorf("preview offered an album field on the track rung: %v", got)
	}

	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want":     []string{"fields"},
		"proposal": map[string]any{"fields": preview.Fields},
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("apply track fields status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if !containsString(res.Applied, "fields: factdb") {
		t.Fatalf("applied = %v, want the fields edit", res.Applied)
	}
	meta := h.itemMeta(t, pid)
	if meta.Fields["bpm"] != "123" || meta.Fields["isrc"] != "GBDUW0000059" ||
		meta.Fields["composer"] != "Bangalter" {
		t.Fatalf("stored fields = %v", meta.Fields)
	}

	// A second fetch has nothing left to fill, and says so without
	// asking a provider at all - every key in the set is filled, so
	// there is nothing an answer could land.
	asked := len(p.seen)
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"fields"},
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("second fetch status = %d", resp.StatusCode)
	}
	res = decode[EnrichItemResult](t, resp)
	if !containsString(res.Skipped, "fields: nothing new to fill") {
		t.Fatalf("skipped = %v, want the fill-when-empty guard", res.Skipped)
	}
	if len(p.seen) != asked {
		t.Errorf("a full item still asked %d providers", len(p.seen)-asked)
	}

	// The request carries the identifier the walk keys on. A second
	// track with only its ISRC set is the shape that shows it: something
	// still to fill, and an identifier to ask by.
	if len(page.Items) < 2 {
		t.Fatal("the demo library holds one music item")
	}
	other := page.Items[1].Pid
	resp = h.patchJSON(t, "/api/v1/items/"+other+"/metadata", map[string]any{
		"fields": map[string]string{"isrc": "GBAYE0601498"},
	})
	wantStatus(t, resp, 200, "set isrc")
	resp = h.postJSON(t, "/api/v1/items/"+other+"/enrich/preview",
		map[string]any{"want": []string{"fields"}})
	wantStatus(t, resp, 200, "preview the second track")

	req, ok := p.lastRecording()
	if !ok {
		t.Fatal("the provider was never asked about a recording")
	}
	if req.ISRC != "GBAYE0601498" {
		t.Errorf("request ISRC = %q, want the stored one", req.ISRC)
	}
	if req.Title == "" || req.Artist == "" {
		t.Errorf("request = %+v, want the track's names for a text match", req)
	}
}

// The fields want is a track's. Asking for it on an audiobook is
// refused with the reason rather than silently filling nothing.
func TestEnrichItemRefusesFieldsForABook(t *testing.T) {
	t.Parallel()
	p := &fakeFieldsProvider{fields: map[string]string{"bpm": "123"}}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) == 0 {
		t.Fatal("no audiobook scanned")
	}
	resp := h.postJSON(t, "/api/v1/items/"+books.Items[0].Pid+"/enrich",
		map[string]any{"want": []string{"fields"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("fields on a book status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if !containsString(res.Skipped, "fields: not a track") {
		t.Fatalf("skipped = %v, want the kind guard", res.Skipped)
	}
}

// The book want now fills upstream's whole book set, so the editor's
// Fetch offers exactly what the catalog's book walk would.
func TestEnrichBookFillsTheWholeFillSet(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{fakeBookProvider{
			name: "bookfacts",
			cand: &enrich.Candidate{
				Publisher: "Beta House",
				Fields: map[string]string{
					"subtitle": "A Study", "edition": "Unabridged",
					"narrator": "Reader One", "description": "Blurb.",
				},
			},
		}}
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
	resp := h.patchJSON(t, "/api/v1/items/"+book+"/metadata", map[string]any{
		"fields": map[string]string{"asin": "B000002L5R"},
	})
	wantStatus(t, resp, 200, "set asin")

	resp = h.postJSON(t, "/api/v1/items/"+book+"/enrich", map[string]any{"want": []string{"book"}})
	wantStatus(t, resp, 200, "enrich book")
	fields := h.itemMeta(t, book).Fields
	for name, want := range map[string]string{
		"publisher": "Beta House", "subtitle": "A Study",
		"edition": "Unabridged", "narrator": "Reader One", "description": "Blurb.",
	} {
		if fields[name] != want {
			t.Errorf("%s = %q, want %q", name, fields[name], want)
		}
	}
}

// The editor's Fetch offers what a nightly pass would fill, and the
// catalog's walk keeps the first answer per key across every capable
// provider. Two providers commonly split the set, so stopping at the
// first would leave the other's field for a later pass to find - and
// the sheet would promise less than the schedule delivers.
func TestEnrichItemMergesFieldsAcrossProviders(t *testing.T) {
	t.Parallel()
	tempo := &fakeFieldsProvider{fields: map[string]string{"bpm": "123"}}
	credits := &fakeFieldsProvider{fields: map[string]string{"composer": "Bangalter"}}
	credits.name = "creditdb"
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{tempo, credits}
	})
	page := h.items(t, "?mediaType=music")
	if len(page.Items) == 0 {
		t.Fatal("no music items in the demo library")
	}
	pid := page.Items[0].Pid

	resp := h.postJSON(t, "/api/v1/items/"+pid+"/enrich/preview",
		map[string]any{"want": []string{"fields"}})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("preview status = %d", resp.StatusCode)
	}
	preview := decode[EnrichPreview](t, resp)
	got := map[string]string{}
	for _, f := range preview.Fields {
		got[f.Name] = f.Provider
	}
	if got["bpm"] != "factdb" || got["composer"] != "creditdb" {
		t.Fatalf("preview providers = %v, want each field to cite the one that answered it", got)
	}

	// And the commit lands both, one edit per provider, so the
	// provenance the sheet showed is the provenance stored.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want":     []string{"fields"},
		"proposal": map[string]any{"fields": preview.Fields},
	})
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("apply status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if !containsString(res.Applied, "fields: creditdb, factdb") {
		t.Fatalf("applied = %v, want both providers named", res.Applied)
	}
	meta := h.itemMeta(t, pid)
	if meta.Fields["bpm"] != "123" || meta.Fields["composer"] != "Bangalter" {
		t.Fatalf("stored fields = %v, want both providers' values", meta.Fields)
	}
}
