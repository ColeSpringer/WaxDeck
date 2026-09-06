package api

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The claim the retired artist-portrait sweep rested on, kept as the
// one test that proves the catalog's own walk now covers what the
// sweep used to: an artist MusicBrainz never matched still gets a
// portrait, from a provider answering the artist target by name.
//
// It is a whole-catalog pass rather than a per-item fetch, because the
// artist rung has no per-item surface: the walk is the only thing that
// reaches an artist entity, and the sweep is gone.

// fakeArtistArtProvider answers the artist target by name, recording
// who it was asked about, the way Deezer's artist search does.
type fakeArtistArtProvider struct {
	mu   sync.Mutex
	asks []string
	img  []byte
}

func (f *fakeArtistArtProvider) Name() string                    { return "fakeface" }
func (f *fakeArtistArtProvider) Capabilities() enrich.Capability { return enrich.CapArtistArt }

func (f *fakeArtistArtProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetArtist {
		return nil, nil
	}
	name := req.Artist
	if name == "" {
		name = req.Title
	}
	f.mu.Lock()
	f.asks = append(f.asks, name)
	f.mu.Unlock()
	if name == "" {
		return nil, nil
	}
	return &enrich.Candidate{
		Confidence: 0.7,
		Art: map[model.ArtRole]*model.ArtImage{model.ArtRoleFront: {
			Data:        f.img,
			Format:      "png",
			Attribution: model.Attribution{SourceURL: "https://faces.example/fixture.png"},
		}},
	}, nil
}

func (f *fakeArtistArtProvider) askedAbout(name string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, a := range f.asks {
		if a == name {
			return true
		}
	}
	return false
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

// runEnrichmentAndWait starts the catalog pass and polls it to done.
func runEnrichmentAndWait(t *testing.T, h *harness) {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/library/enrichment/run", map[string]any{})
	if resp.StatusCode != 202 {
		defer resp.Body.Close()
		var body map[string]any
		json.NewDecoder(resp.Body).Decode(&body)
		t.Fatalf("enrichment run status = %d (%v), want 202", resp.StatusCode, body)
	}
	job := decode[EnrichmentRunResult](t, resp)
	deadline := time.Now().Add(30 * time.Second)
	for {
		resp := get(t, h.ts, "/api/v1/jobs/"+job.JobPid, h.token)
		j := decode[Job](t, resp)
		switch j.State {
		case "done":
			return
		case "failed", "crashed", "canceled":
			t.Fatalf("enrichment job ended %s: %v", j.State, deref(j.Error))
		}
		if time.Now().After(deadline) {
			t.Fatal("enrichment job did not finish in time")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// TestCatalogPassFillsAnUnmatchedArtistsPortrait is the retirement's
// load-bearing claim. The fixture library scans unmatched - no artist
// carries a MusicBrainz id - and no contact is configured, so the
// identity phases do not run at all. The artist-art phase still does,
// because a registered provider advertises the capability that gates
// it, and it asks by name.
func TestCatalogPassFillsAnUnmatchedArtistsPortrait(t *testing.T) {
	t.Parallel()
	fake := &fakeArtistArtProvider{img: tinyPNG(t)}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{fake}
		c.EnrichmentContact = ""
	})
	pid := demoArtistPID(t, h)

	// The status surface says as much before the run: a pass would do
	// something, but not identity.
	st := decode[EnrichmentStatus](t, get(t, h.ts, "/api/v1/library/enrichment", h.token))
	if !st.Configured {
		t.Fatal("configured = false with an artist-art provider registered")
	}
	if st.MusicbrainzConfigured {
		t.Fatal("musicbrainzConfigured = true with no contact")
	}
	if !hasPhase(st.Phases, EnrichmentStatusPhasesArtistArt) {
		t.Fatalf("phases = %v, want the artist-art phase", st.Phases)
	}
	if hasPhase(st.Phases, EnrichmentStatusPhasesIdentity) {
		t.Fatalf("phases = %v, want no identity phase without a contact", st.Phases)
	}

	runEnrichmentAndWait(t, h)

	if !fake.askedAbout("Fixture Artist") {
		t.Fatalf("the unmatched artist was never asked about; asks = %v", fake.asks)
	}
	// The portrait serves from the artist's own slot, marked as the
	// enrichment write it is, with the provider cited.
	roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
	if roles.ArtSource == nil {
		t.Fatal("the enriched artist reports no art source")
	}
	if roles.ArtSource.Source != "enrichment" {
		t.Errorf("art source = %q, want enrichment", roles.ArtSource.Source)
	}
	if roles.ArtSource.Provider == nil || *roles.ArtSource.Provider != "fakeface" {
		t.Errorf("art provider = %v, want the supplying rung", roles.ArtSource.Provider)
	}
}

// A server with neither a contact nor a phase-gating provider has
// nothing to run, and says so rather than offering a button that
// errors. The refusal names both routes back.
func TestEnrichmentStatusReportsNothingToRun(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = nil
		c.EnrichmentContact = ""
	})
	st := decode[EnrichmentStatus](t, get(t, h.ts, "/api/v1/library/enrichment", h.token))
	if st.Configured || st.MusicbrainzConfigured {
		t.Fatalf("status = %+v, want nothing configured", st)
	}
	if len(st.Phases) != 0 {
		t.Fatalf("phases = %v, want none", st.Phases)
	}
	resp := h.postJSON(t, "/api/v1/library/enrichment/run", map[string]any{})
	defer resp.Body.Close()
	if resp.StatusCode != 501 {
		t.Fatalf("run status = %d, want 501", resp.StatusCode)
	}
	var body struct{ Message string }
	json.NewDecoder(resp.Body).Decode(&body)
	for _, want := range []string{"enrichment-contact", "provider"} {
		if !strings.Contains(body.Message, want) {
			t.Errorf("refusal %q does not name %q", body.Message, want)
		}
	}
}

func hasPhase(phases []EnrichmentStatusPhases, want EnrichmentStatusPhases) bool {
	for _, p := range phases {
		if p == want {
			return true
		}
	}
	return false
}
