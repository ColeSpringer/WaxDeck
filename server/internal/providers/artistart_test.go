package providers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

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

// Where Deezer holds no portrait it names a stand-in, a path with no image
// hash, which would otherwise land as the artist's own picture.
func TestDeezerArtistImageSkipsTheStandInPortrait(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/artist":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[{"name":"The Zzyzx Road Band",
				"picture_xl":"https://%s/images/artist//1000x1000-000000-80-0-0.jpg"}]}`, r.Host)
		case "/images/artist//1000x1000-000000-80-0-0.jpg":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDeezer(DeezerConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	if res, err := d.ArtistImage(context.Background(), "The Zzyzx Road Band"); !errors.Is(err, ErrNoArtistImage) {
		t.Errorf("stand-in = %d bytes, %v; want ErrNoArtistImage", len(res.Data), err)
	}
}

// An artist is routinely listed more than once, so one dead picture_xl
// must not end the walk, FrontCover's rule; when every match's picture is
// dead, the failure surfaces as an error rather than a clean no.
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
	// so the catalog logs a failure rather than reading a clean no.
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
