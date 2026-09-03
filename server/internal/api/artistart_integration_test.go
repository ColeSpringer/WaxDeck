package api

import (
	"context"
	"net/url"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/providers"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// fakeArtistArt is a scriptable ArtistArtProvider recording who was
// asked, so the sweep tests can assert what was fetched and, as
// importantly, what was not.
type fakeArtistArt struct {
	mu   sync.Mutex
	asks []string
	miss bool
	img  []byte
}

func (f *fakeArtistArt) ArtistImage(ctx context.Context, name, mbid string) (providers.TitleCoverResult, error) {
	f.mu.Lock()
	f.asks = append(f.asks, name)
	f.mu.Unlock()
	if f.miss {
		return providers.TitleCoverResult{}, providers.ErrNoArtistImage
	}
	return providers.TitleCoverResult{
		Data: f.img, MIME: "image/png",
		Provider:  "fakeface",
		SourceURL: "https://faces.example/fixture.png",
	}, nil
}

func (f *fakeArtistArt) askCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.asks)
}

// demoArtistPID resolves the fixture library's one artist entity.
func demoArtistPID(t *testing.T, h *harness) string {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/search?q="+url.QueryEscape("Fixture Artist"), h.token)
	res := decode[SearchResults](t, resp)
	if len(res.Artists) == 0 {
		t.Fatal("the fixture artist is not a search hit")
	}
	return res.Artists[0].Pid
}

func TestArtistArtSweepFillsAndThenLeavesAlone(t *testing.T) {
	t.Parallel()
	fake := &fakeArtistArt{img: tinyPNG(t)}
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.ArtistArtProvider = fake })
	pid := demoArtistPID(t, h)

	res, err := h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Filled != 1 {
		t.Fatalf("first sweep filled %d, want the one fixture artist", res.Filled)
	}

	// The portrait serves from the artist's own slot, marked as the
	// enrichment write it is, with the provider and origin cited.
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	if roles.ArtSource == nil {
		t.Fatal("the swept artist reports no art source")
	}
	if roles.ArtSource.Source != "enrichment" {
		t.Errorf("art source = %q, want enrichment", roles.ArtSource.Source)
	}
	if roles.ArtSource.Provider == nil || *roles.ArtSource.Provider != "fakeface" {
		t.Errorf("art provider = %v, want the supplying rung", roles.ArtSource.Provider)
	}

	// A second pass finds the slot resolving and asks nobody.
	asked := fake.askCount()
	res, err = h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Filled != 0 || fake.askCount() != asked {
		t.Errorf("second sweep filled %d and asked %d more times, want a no-op",
			res.Filled, fake.askCount()-asked)
	}

	// Clearing the portrait (the sweep pins nothing) hands the slot back
	// to the next pass: fill-when-empty means empty-again refills, the
	// same contract every enrichment write keeps.
	resp := reqAs(t, h, "DELETE", "/api/v1/entities/artist/"+pid+"/artwork", h.token, nil)
	wantStatus(t, resp, 204, "clear the swept portrait")
	res, err = h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Filled != 1 {
		t.Errorf("post-clear sweep filled %d, want the refill", res.Filled)
	}
}

func TestArtistArtSweepRemembersMisses(t *testing.T) {
	t.Parallel()
	fake := &fakeArtistArt{miss: true}
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.ArtistArtProvider = fake })

	res, err := h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Misses != 1 || fake.askCount() != 1 {
		t.Fatalf("first sweep = %+v with %d asks, want one recorded miss", res, fake.askCount())
	}

	// The miss holds: the next pass does not re-ask.
	res, err = h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Misses != 0 || fake.askCount() != 1 {
		t.Errorf("second sweep = %+v with %d asks, want the miss remembered", res, fake.askCount())
	}
}

func TestArtistArtSweepRespectsAStandingPin(t *testing.T) {
	t.Parallel()
	fake := &fakeArtistArt{img: tinyPNG(t)}
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.ArtistArtProvider = fake })
	pid := demoArtistPID(t, h)

	// A pin on an empty slot is a person's "do not refill this".
	resp := h.putJSON(t, "/api/v1/entities/artist/"+pid+"/artwork/lock", map[string]any{"locked": true})
	wantStatus(t, resp, 200, "pin the empty slot")

	res, err := h.svc.ArtistArtSweep(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if res.Filled != 0 || fake.askCount() != 0 {
		t.Errorf("sweep over a pinned slot = %+v with %d asks, want neither", res, fake.askCount())
	}
}

// TestArtistArtSweepCoversWhatTheCatalogPassDoesNot is the boundary
// between the two passes that fill artist art, and the boundary moves.
//
// An artist carrying a MusicBrainz id belongs to the catalog's own
// enrichment pass, which asks fanart.tv and Deezer by that id through
// the port - so the sweep leaves it alone rather than racing a
// name-matched face against an identity-matched one. But that pass
// needs an enrichment contact and does not run without one, while a
// library tagged by Picard or beets carries artist mbids straight off
// the files. Skipping them unconditionally is how a stock install ends
// up fetching no portraits at all with the flag still reporting on.
func TestArtistArtSweepCoversWhatTheCatalogPassDoesNot(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name             string
		contact          string
		sweptWhenMatched bool
	}{
		{name: "no contact", contact: "", sweptWhenMatched: true},
		{name: "enrichment configured", contact: "waxdeck@example.test", sweptWhenMatched: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			fake := &fakeArtistArt{img: tinyPNG(t)}
			h := newHarnessWith(t, func(cfg *service.Config) {
				cfg.ArtistArtProvider = fake
				cfg.EnrichmentContact = tc.contact
			})
			pid := demoArtistPID(t, h)

			// Unmatched, which is how the fixture library scans: the
			// sweep's business either way.
			res, err := h.svc.ArtistArtSweep(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if res.Scanned == 0 || fake.askCount() == 0 {
				t.Fatalf("an mbid-less artist was not swept: %+v, asks=%d", res, fake.askCount())
			}

			// Give the artist an identity and clear the portrait the
			// first pass stored, so the only thing that can keep the
			// next one away is the id.
			resp := h.patchJSON(t, "/api/v1/entities/artist/"+pid, map[string]any{
				"edits": map[string]string{"mbid": "11111111-2222-3333-4444-555555555555"},
			})
			if resp.StatusCode != 200 {
				t.Fatalf("setting the artist mbid: status %d", resp.StatusCode)
			}
			resp.Body.Close()
			wantStatus(t, h.deleteReq(t, "/api/v1/entities/artist/"+pid+"/artwork?force=true"), 204,
				"clearing the swept portrait")
			// The clear leaves the pin as it stood, and this artist was
			// never pinned; unpinning explicitly would test the pin,
			// not the filter.

			before := fake.askCount()
			res, err = h.svc.ArtistArtSweep(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			asked := fake.askCount() != before
			if asked != tc.sweptWhenMatched {
				t.Errorf("matched artist asked = %v, want %v", asked, tc.sweptWhenMatched)
			}
			if scanned := res.Scanned > 0; scanned != tc.sweptWhenMatched {
				t.Errorf("matched artist counted as scanned = %v, want %v", scanned, tc.sweptWhenMatched)
			}
		})
	}
}
