package providers

import (
	"context"
	"net/http"
	"testing"

	"github.com/colespringer/waxbin/enrich"
)

var allTargets = []enrich.TargetType{
	enrich.TargetArtist, enrich.TargetReleaseGroup, enrich.TargetRelease,
	enrich.TargetBook, enrich.TargetRecording,
}

// noDial fails the test on any request.
type noDial struct{ t *testing.T }

func (n noDial) RoundTrip(r *http.Request) (*http.Response, error) {
	n.t.Errorf("dialed %s at a rung the provider does not serve", r.URL.Host)
	return nil, http.ErrHandlerTimeout
}

// stockProviders are the in-tree providers with keys set, over a transport
// that fails the test if anything dials.
func stockProviders(t *testing.T) []enrich.Provider {
	c := &http.Client{Transport: noDial{t}}
	deezer := NewDeezer(DeezerConfig{HTTPClient: c})
	fanart := NewFanartTV(FanartTVConfig{APIKey: "k", HTTPClient: c})
	return []enrich.Provider{
		deezer, fanart,
		WithoutArtistArt(deezer), WithoutArtistArt(fanart),
		NewITunes(ITunesConfig{HTTPClient: c}),
		NewDiscogs(DiscogsConfig{Token: "k", HTTPClient: c}),
		NewAudnexus(AudnexusConfig{HTTPClient: c}),
		NewHardcover(HardcoverConfig{Token: "k", HTTPClient: c}),
		NewGoogleBooks(GoogleBooksConfig{APIKey: "k", HTTPClient: c}),
		NewOpenLibrary(OpenLibraryConfig{HTTPClient: c}),
	}
}

// fullRequest carries every hint, so only the rung gate can keep a
// provider off the network.
func fullRequest(t enrich.TargetType) enrich.Request {
	return enrich.Request{
		Type: t, Title: "Signal Garden", Artist: "Test Ensemble", Album: "Signal Garden",
		MBID: "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0", ASIN: "B00TEST000", ISBN: "9780000000002",
		ISRC: "USTEST000001", Barcode: "0123456789012", CatalogNumber: "TEST-1",
		ReleaseGroupMBID: "1f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0", DurationSec: 200,
	}
}

// Every stock provider declares its rungs: nothing advertised is out of
// reach, no rung claims more than it advertises, and a rung it declares
// empty is never dialed.
func TestProvidersDeclareTheirRungs(t *testing.T) {
	t.Parallel()
	for _, p := range stockProviders(t) {
		tc, ok := p.(enrich.TargetCapabilities)
		if !ok {
			t.Errorf("%s declares no rungs", p.Name())
			continue
		}
		var union enrich.Capability
		for _, target := range allTargets {
			at := tc.CapabilitiesAt(target)
			if at&^p.Capabilities() != 0 {
				t.Errorf("%s at %s claims %v beyond its capabilities %v", p.Name(), target, at, p.Capabilities())
			}
			union |= at
			if at != 0 {
				continue
			}
			if cand, err := p.Enrich(context.Background(), fullRequest(target)); cand != nil || err != nil {
				t.Errorf("%s at %s, a rung it declares empty, answered %+v, %v", p.Name(), target, cand, err)
			}
		}
		if union != p.Capabilities() {
			t.Errorf("%s serves %v across its rungs, advertises %v", p.Name(), union, p.Capabilities())
		}
	}
}

// The rungs the catalog reads for fanart.tv: nothing for one pressing, art
// for a group, both halves for an artist.
func TestFanartTVRungs(t *testing.T) {
	t.Parallel()
	f := NewFanartTV(FanartTVConfig{APIKey: "k", HTTPClient: &http.Client{Transport: noDial{t}}})
	for target, want := range map[enrich.TargetType]enrich.Capability{
		enrich.TargetRelease:      0,
		enrich.TargetReleaseGroup: enrich.CapCover | enrich.CapAuxArt,
		enrich.TargetArtist:       enrich.CapArtistArt,
	} {
		if got := CapabilitiesAt(f, target); got != want {
			t.Errorf("fanarttv at %s = %v, want %v", target, got, want)
		}
	}
	if got := CapabilitiesAt(WithoutArtistArt(f), enrich.TargetArtist); got != 0 {
		t.Errorf("fanarttv without artist art at the artist rung = %v, want nothing", got)
	}
}
