package providers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// artistArtStub serves both rungs' endpoints and the picture, counting
// per-path hits so a chain test can assert which rungs were asked.
func artistArtStub(t *testing.T, deezerHits string) (*httptest.Server, *atomic.Int64, *atomic.Int64) {
	t.Helper()
	data := testPNG(t)
	fanartAsks, deezerAsks := &atomic.Int64{}, &atomic.Int64{}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v3/music/mbid-known":
			fanartAsks.Add(1)
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"name":"Daft Punk","artistthumb":[{"url":"https://%s/face.png"}]}`, r.Host)
		case "/search/artist":
			deezerAsks.Add(1)
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprint(w, deezerHits)
		case "/face.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			// Unknown MBIDs answer 404, which is fanart.tv's clean miss.
			if len(r.URL.Path) > len("/v3/music/") && r.URL.Path[:10] == "/v3/music/" {
				fanartAsks.Add(1)
			}
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, fanartAsks, deezerAsks
}

func artistChain(srv *httptest.Server, fanartKey string) ArtistArtChain {
	chain := ArtistArtChain{
		Deezer: NewDeezer(DeezerConfig{
			BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		}),
	}
	if fanartKey != "" {
		chain.Fanart = NewFanartTV(FanartTVConfig{
			BaseURL: srv.URL, APIKey: fanartKey, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		})
	}
	return chain
}

func TestArtistArtChainPrefersTheMBIDKeyedRung(t *testing.T) {
	t.Parallel()
	srv, _, deezerAsks := artistArtStub(t, `{"data":[]}`)
	chain := artistChain(srv, "fkey")

	res, err := chain.ArtistImage(context.Background(), "Daft Punk", "mbid-known")
	if err != nil {
		t.Fatal(err)
	}
	if res.Provider != "fanarttv" {
		t.Errorf("provider = %q, want fanarttv first", res.Provider)
	}
	if len(res.Data) == 0 || res.SourceURL == "" {
		t.Errorf("result carries no image or source URL: %+v", res)
	}
	if deezerAsks.Load() != 0 {
		t.Errorf("deezer was asked %d times behind a fanart.tv hit", deezerAsks.Load())
	}
}

// TestDeezerArtistImageGatesOnTheName is the by-name risk pinned: a
// near-miss name is no answer, while case, spacing, and punctuation
// differences still count as the same artist.
func TestDeezerArtistImageGatesOnTheName(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/artist":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[
				{"name":"Daft Punkette","picture_xl":"https://%s/wrong.png"},
				{"name":"daft  punk","picture_xl":"https://%s/face.png"}]}`, r.Host, r.Host)
		case "/face.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		case "/wrong.png":
			t.Error("the near-miss hit's picture was fetched")
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDeezer(DeezerConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})

	res, err := d.ArtistImage(context.Background(), "Daft Punk")
	if err != nil {
		t.Fatal(err)
	}
	if res.Provider != "deezer" || len(res.Data) == 0 {
		t.Fatalf("result = %+v, want the exact-ish match's picture", res)
	}

	// Only near misses: a clean, durable no.
	srv2 := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"data":[{"name":"Daft Punkette","picture_xl":"https://x/p.png"}]}`)
	}))
	defer srv2.Close()
	d2 := NewDeezer(DeezerConfig{BaseURL: srv2.URL, HTTPClient: srv2.Client(), MinInterval: time.Nanosecond})
	if _, err := d2.ArtistImage(context.Background(), "Daft Punk"); !errors.Is(err, ErrNoArtistImage) {
		t.Errorf("near-miss-only search = %v, want ErrNoArtistImage", err)
	}

	// The comparator is the punctuation fold both sides of a cover
	// match use: "AC - DC" in the tags and "AC/DC" on Deezer are one
	// artist. An all-punctuation name folds empty and matches nothing.
	if !artistNameMatch("AC/DC", "AC - DC") {
		t.Error(`artistNameMatch("AC/DC", "AC - DC") = false, want the punctuation folded`)
	}
	if artistNameMatch("!!!", "...") {
		t.Error("two all-punctuation names matched through the empty fold")
	}
}

// TestDeezerArtistImageWalksPastAnUnusablePicture mirrors FrontCover's
// rule: an artist is routinely listed more than once, so one dead
// picture_xl must not end the walk - and when every match's picture is
// dead, the failure surfaces as retriable rather than as a durable
// miss.
func TestDeezerArtistImageWalksPastAnUnusablePicture(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/artist":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[
				{"name":"Daft Punk","picture_xl":"https://%s/gone.png"},
				{"name":"Daft Punk","picture_xl":"https://%s/face.png"}]}`, r.Host, r.Host)
		case "/face.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDeezer(DeezerConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})

	res, err := d.ArtistImage(context.Background(), "Daft Punk")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Data) == 0 {
		t.Fatal("the walk ended on the first dead picture")
	}

	// Every match dead: a reachability error, never ErrNoArtistImage,
	// so the sweep retries next pass instead of recording a 30-day miss.
	srv2 := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/search/artist" {
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[{"name":"Daft Punk","picture_xl":"https://%s/gone.png"}]}`, r.Host)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv2.Close()
	d2 := NewDeezer(DeezerConfig{BaseURL: srv2.URL, HTTPClient: srv2.Client(), MinInterval: time.Nanosecond})
	if _, err := d2.ArtistImage(context.Background(), "Daft Punk"); err == nil || errors.Is(err, ErrNoArtistImage) {
		t.Errorf("all-dead pictures = %v, want a retriable reachability error", err)
	}
}

func TestArtistArtChainMissesFallThroughAndFailuresDoNot(t *testing.T) {
	t.Parallel()
	data := testPNG(t)

	// Fanart.tv answers 404 (a miss); Deezer holds the face: the chain
	// falls through and answers.
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/artist":
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
	chain := artistChain(srv, "fkey")
	res, err := chain.ArtistImage(context.Background(), "Daft Punk", "mbid-unknown")
	if err != nil {
		t.Fatal(err)
	}
	if res.Provider != "deezer" {
		t.Errorf("provider = %q, want the fallback rung", res.Provider)
	}

	// A keyless chain with no configured rungs at all is a clean miss.
	empty := ArtistArtChain{}
	if _, err := empty.ArtistImage(context.Background(), "Anyone", "any"); !errors.Is(err, ErrNoArtistImage) {
		t.Errorf("empty chain = %v, want ErrNoArtistImage", err)
	}

	// Fanart.tv failing to answer ends the walk: Deezer's "no" must not
	// be recorded as a durable miss the failed rung might contradict.
	deezerAsked := &atomic.Int64{}
	srv3 := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/search/artist" {
			deezerAsked.Add(1)
		}
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv3.Close()
	chain3 := artistChain(srv3, "fkey")
	if _, err := chain3.ArtistImage(context.Background(), "Daft Punk", "mbid-known"); err == nil || errors.Is(err, ErrNoArtistImage) {
		t.Errorf("failed rung = %v, want a reachability error", err)
	}
	if deezerAsked.Load() != 0 {
		t.Errorf("deezer was asked %d times behind a fanart.tv failure", deezerAsked.Load())
	}
}

// TestFanartArtistThumbWithoutAKeyIsAMissWithoutANetworkCall mirrors
// the Enrich rule: unkeyed means unconfigured, never an error.
func TestFanartArtistThumbWithoutAKeyIsAMissWithoutANetworkCall(t *testing.T) {
	t.Parallel()
	f := NewFanartTV(FanartTVConfig{BaseURL: "https://never-dialed.invalid"})
	if _, err := f.ArtistThumb(context.Background(), "mbid"); !errors.Is(err, ErrNoArtistImage) {
		t.Errorf("keyless ArtistThumb = %v, want ErrNoArtistImage", err)
	}
	fkeyed := NewFanartTV(FanartTVConfig{BaseURL: "https://never-dialed.invalid", APIKey: "k"})
	if _, err := fkeyed.ArtistThumb(context.Background(), ""); !errors.Is(err, ErrNoArtistImage) {
		t.Errorf("no-MBID ArtistThumb = %v, want ErrNoArtistImage", err)
	}
}
