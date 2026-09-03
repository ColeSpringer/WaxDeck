package providers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// fanartArtStub serves the two fanart.tv endpoints with a per-role
// asset apiece, counting image fetches per role so a test can assert
// what a scoped ask did *not* download - which is the whole point of
// the want gate.
func fanartArtStub(t *testing.T) (*httptest.Server, map[string]*atomic.Int64) {
	t.Helper()
	data := testPNG(t)
	fetched := map[string]*atomic.Int64{
		"albumcover": {}, "cdart": {}, "thumb": {}, "background": {},
	}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v3/music/albums/rg-1":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"albums":{"rg-1":{
				"albumcover":[{"url":"https://%[1]s/albumcover.png"}],
				"cdart":[{"url":"https://%[1]s/cdart.png"}]}}}`, r.Host)
		case "/v3/music/ar-1":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{
				"artistthumb":[{"url":"https://%[1]s/thumb.png"}],
				"artistbackground":[{"url":"https://%[1]s/background.png"}]}`, r.Host)
		case "/albumcover.png", "/cdart.png", "/thumb.png", "/background.png":
			fetched[r.URL.Path[1:len(r.URL.Path)-len(".png")]].Add(1)
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, fetched
}

func newFanartFor(t *testing.T, srv *httptest.Server) *FanartTV {
	t.Helper()
	return NewFanartTV(FanartTVConfig{
		BaseURL: srv.URL, APIKey: "fkey", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
}

// fanart.tv is the only provider that answers art by role, which is why
// it advertises all three art capabilities and rides ahead of the
// others. The want gate is what makes that affordable: a cover pass
// must not pull down disc art nobody asked for.
func TestFanartTVAnswersPerRoleAndSkipsWhatIsNotWanted(t *testing.T) {
	t.Parallel()
	srv, fetched := fanartArtStub(t)
	f := newFanartFor(t, srv)

	for _, cap := range []enrich.Capability{enrich.CapCover, enrich.CapAuxArt, enrich.CapArtistArt} {
		if !f.Capabilities().Has(cap) {
			t.Errorf("capabilities %v do not include %v", f.Capabilities(), cap)
		}
	}

	// A cover ask takes the front and leaves the disc art alone.
	cand, err := f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, MBID: "rg-1", Want: enrich.CapCover,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil || cand.Art[model.ArtRoleFront] == nil {
		t.Fatalf("cover ask = %+v, want the front under both the alias and the role", cand)
	}
	if cand.Art[model.ArtRoleDisc] != nil {
		t.Errorf("a cover ask carried disc art")
	}
	if n := fetched["cdart"].Load(); n != 0 {
		t.Errorf("a cover ask downloaded the disc art %d times", n)
	}

	// An auxiliary ask is the mirror: disc art, no cover fetch.
	before := fetched["albumcover"].Load()
	cand, err = f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, MBID: "rg-1", Want: enrich.CapAuxArt,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleDisc] == nil {
		t.Fatalf("aux ask = %+v, want the disc art", cand)
	}
	if cand.Cover != nil || cand.Art[model.ArtRoleFront] != nil {
		t.Errorf("an auxiliary ask carried the front cover")
	}
	if n := fetched["albumcover"].Load(); n != before {
		t.Errorf("an auxiliary ask downloaded the cover")
	}

	// The artist target: the thumb is the front (upstream's art model
	// gives an artist no separate portrait slot), the scenic image the
	// background.
	cand, err = f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, MBID: "ar-1", Want: enrich.CapArtistArt,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil || cand.Art[model.ArtRoleBackground] == nil {
		t.Fatalf("artist ask = %+v, want a portrait and a background", cand)
	}
	// Cover is the release group's alias and stays nil on an artist:
	// an apply pass reading it would write a portrait into an album.
	if cand.Cover != nil {
		t.Error("an artist candidate filled the release-group cover alias")
	}

	// A zero want is the everything contract, which is the shape the
	// whole-library pass has.
	cand, err = f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, MBID: "rg-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil || cand.Art[model.ArtRoleDisc] == nil {
		t.Fatalf("unscoped ask = %+v, want every role", cand)
	}

	// An id with no assets is a clean miss, and so is a target neither
	// endpoint serves.
	for _, req := range []enrich.Request{
		{Type: enrich.TargetArtist, MBID: "ar-unknown"},
		{Type: enrich.TargetRecording, MBID: "rec-1"},
	} {
		if cand, err := f.Enrich(context.Background(), req); err != nil || cand != nil {
			t.Errorf("%v = %+v, %v; want a clean miss", req.Type, cand, err)
		}
	}
}

// Deezer answers the artist target by name, since it knows nothing of
// MusicBrainz. The placeholder gate is the risk that matters: an exact
// match on "Various Artists" would put a stranger's face on every
// compilation in a library.
func TestDeezerEnrichesAnArtistByName(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	var searches atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/artist":
			searches.Add(1)
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[{"name":"Daft Punk","picture_xl":"https://%s/face.png"}]}`, r.Host)
		case "/face.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	if !d.Capabilities().Has(enrich.CapArtistArt) {
		t.Errorf("capabilities %v do not include artist art", d.Capabilities())
	}
	// Not aux art: Deezer serves one picture per album, so it has
	// nothing to put in a back, disc, or booklet slot.
	if d.Capabilities().Has(enrich.CapAuxArt) {
		t.Errorf("capabilities %v claim auxiliary roles Deezer cannot fill", d.Capabilities())
	}

	// The engine puts the artist's name in Artist for this target.
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, Artist: "Daft Punk", Want: enrich.CapArtistArt,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil {
		t.Fatalf("artist ask = %+v, want the portrait under front", cand)
	}
	if cand.Cover != nil {
		t.Error("an artist candidate filled the release-group cover alias")
	}

	// A placeholder name is refused before the search goes out.
	before := searches.Load()
	cand, err = d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, Artist: "Various Artists", Want: enrich.CapArtistArt,
	})
	if err != nil || cand != nil {
		t.Fatalf("placeholder ask = %+v, %v; want a clean miss", cand, err)
	}
	if n := searches.Load(); n != before {
		t.Errorf("a placeholder name reached the search %d times", n-before)
	}

	// A cover-shaped want still answers: that is how the identity phase
	// asks about an artist, and reading only the backfill's own bit
	// here is what left a stock install with no portraits.
	cand, err = d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, Artist: "Daft Punk", Want: enrich.CapCover,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil {
		t.Fatalf("cover-want artist ask = %+v, want the portrait", cand)
	}

	// A want no role on this target can answer never reaches the wire.
	before = searches.Load()
	if cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, Artist: "Daft Punk", Want: enrich.CapGenres,
	}); err != nil || cand != nil {
		t.Fatalf("genres-want artist ask = %+v, %v; want a clean miss", cand, err)
	}
	if n := searches.Load(); n != before {
		t.Errorf("an unanswerable want reached the artist search %d times", n-before)
	}
}

// WithoutArtistArt is what WAXDECK_ARTIST_ART=false rides on: the
// provider stays registered for the covers it still supplies, and both
// halves have to hold. Clearing the capability keeps it out of the
// artist backfill's queue; refusing the artist target covers the other
// path, where the identity phase asks about an artist under CapCover
// and no capability mask can tell that from a real cover ask.
func TestWithoutArtistArtHidesAndRefusesBothPaths(t *testing.T) {
	t.Parallel()
	srv, fetched := fanartArtStub(t)
	masked := WithoutArtistArt(newFanartFor(t, srv))

	if masked.Capabilities().Has(enrich.CapArtistArt) {
		t.Errorf("capabilities %v still advertise artist art", masked.Capabilities())
	}
	if !masked.Capabilities().Has(enrich.CapCover) {
		t.Errorf("capabilities %v dropped a bit that was not hidden", masked.Capabilities())
	}

	// Both wants an artist can arrive under, including the cover-shaped
	// one the identity phase stamps - the case a capability mask alone
	// let straight through.
	for _, want := range []enrich.Capability{enrich.CapArtistArt, enrich.CapCover, enrich.CapAuxArt, 0} {
		before := fetched["thumb"].Load() + fetched["background"].Load()
		cand, err := masked.Enrich(context.Background(), enrich.Request{
			Type: enrich.TargetArtist, MBID: "ar-1", Want: want,
		})
		if err != nil || cand != nil {
			t.Errorf("artist ask under want %v = %+v, %v; want a clean miss", want, cand, err)
		}
		if n := fetched["thumb"].Load() + fetched["background"].Load(); n != before {
			t.Errorf("an artist ask under want %v reached the network", want)
		}
	}

	// What was not hidden still answers.
	cand, err := masked.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, MBID: "rg-1", Want: enrich.CapCover,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil {
		t.Fatalf("masked cover ask = %+v, want the cover", cand)
	}
}

// The identity phase asks about an artist through the release-group
// passes - CapCover for the front, CapAuxArt for the rest - and never
// through the artist backfill's own bit. A provider reading only
// CapArtistArt there answers nothing while still paying for the keyed
// lookup, which is one wasted request per matched artist per pass.
func TestFanartTVAnswersAnArtistOnTheIdentityPassesWants(t *testing.T) {
	t.Parallel()
	srv, fetched := fanartArtStub(t)
	f := newFanartFor(t, srv)

	cand, err := f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, MBID: "ar-1", Want: enrich.CapCover,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil {
		t.Fatalf("cover-want artist ask = %+v, want the portrait", cand)
	}
	if cand.Art[model.ArtRoleBackground] != nil {
		t.Error("a cover-want ask carried the background")
	}

	cand, err = f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, MBID: "ar-1", Want: enrich.CapAuxArt,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleBackground] == nil {
		t.Fatalf("aux-want artist ask = %+v, want the background", cand)
	}
	if cand.Art[model.ArtRoleFront] != nil {
		t.Error("an aux-want ask carried the portrait")
	}

	// A want no role on this target can answer never reaches the wire:
	// the endpoint read happens before the roles are filtered, so the
	// gate has to be ahead of it.
	before := fetched["thumb"].Load() + fetched["background"].Load()
	if cand, err := f.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, MBID: "ar-1", Want: enrich.CapGenres,
	}); err != nil || cand != nil {
		t.Fatalf("genres-want artist ask = %+v, %v; want a clean miss", cand, err)
	}
	if n := fetched["thumb"].Load() + fetched["background"].Load(); n != before {
		t.Error("an unanswerable want still downloaded an image")
	}
}
