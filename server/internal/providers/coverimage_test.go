package providers

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/enrich"
)

// testPNG synthesizes a real 8x8 image, because the point of these
// tests is the header probe: a string standing in for image bytes
// probes as a failure and would prove nothing about the dimensions.
func testPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	for y := range 8 {
		for x := range 8 {
			img.Set(x, y, color.RGBA{R: 0x30, G: 0x60, B: 0x90, A: 0xFF})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// TestCoverImageHashesAndMeasures pins the contract every provider's
// cover depends on.
//
// The hash is the load-bearing part. The catalog's art store is
// content-addressed and its ingest treats an image with no hash as
// nothing to store - silently, returning success - so a cover that
// reaches it unhashed is a picture fetched over somebody else's network
// and then dropped, with no error and a run that reports itself clean.
// Every provider here shipped exactly that until this helper existed.
func TestCoverImageHashesAndMeasures(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	img := coverImage(data, "image/png", "https://example.com/cover.png")
	if img == nil {
		t.Fatal("coverImage returned nil for a real image")
	}
	if img.Hash == "" {
		t.Fatal("no hash: the catalog's ingest discards this image and reports success")
	}
	if img.Hash != art.Hash(data) {
		t.Errorf("Hash = %q, want the content address of the bytes", img.Hash)
	}
	if img.Format != "png" || img.Width != 8 || img.Height != 8 {
		t.Errorf("probe wrong: format=%q %dx%d, want png 8x8", img.Format, img.Width, img.Height)
	}
	if img.SourceURL != "https://example.com/cover.png" {
		t.Errorf("SourceURL = %q, want the URL it was fetched from", img.SourceURL)
	}
}

// TestCoverImageUndecodableKeepsTheTransportFormat covers the picture
// no pure-Go decoder can measure. An AVIF or HEIC cover is a perfectly
// good image the catalog stores happily, so failing the probe must not
// throw it away - it keeps the media type's format and unknown
// dimensions, which is what the catalog's own archive provider does.
func TestCoverImageUndecodableKeepsTheTransportFormat(t *testing.T) {
	t.Parallel()
	img := coverImage([]byte("not really an image"), "image/jpeg", "https://example.com/x.jpg")
	if img == nil {
		t.Fatal("an unprobeable image is still an image")
	}
	if img.Hash == "" {
		t.Error("an unprobeable image still needs its content address")
	}
	if img.Format != "jpeg" {
		t.Errorf("Format = %q, want the transport's jpeg", img.Format)
	}
	if img.Width != 0 || img.Height != 0 {
		t.Errorf("dimensions = %dx%d, want unknown", img.Width, img.Height)
	}
}

// TestCoverImageEmptyIsNoCover: no bytes is a miss, not an image the
// store would refuse. Returning a non-nil husk here would make the
// enrichment pass count a cover it never fetched.
func TestCoverImageEmptyIsNoCover(t *testing.T) {
	t.Parallel()
	if img := coverImage(nil, "image/png", "https://example.com/x.png"); img != nil {
		t.Errorf("coverImage(nil) = %+v, want nil", img)
	}
	if img := coverImage([]byte{}, "image/png", ""); img != nil {
		t.Errorf("coverImage(empty) = %+v, want nil", img)
	}
}

// TestEveryCoverProviderHashesItsCover drives all four cover providers
// against a stub and asserts what the store needs from each: a content
// address, and the URL the picture came from so the source mark can
// cite it. One test rather than four assertions spread across the
// per-provider tests, because the failure is identical in each and a
// provider added later should fail here on the day it is written.
func TestEveryCoverProviderHashesItsCover(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/album": // deezer
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data":[{"title":"Discovery","artist":{"name":"Daft Punk"},
				"cover_xl":"https://%s/cover.png"}]}`, r.Host)
		case "/search": // itunes
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"results":[{"collectionName":"Discovery","artistName":"Daft Punk",
				"artworkUrl100":"https://%s/cover.png"}]}`, r.Host)
		case "/v3/music/albums/rg-1": // fanart.tv
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"albums":{"rg-1":{"albumcover":[{"url":"https://%s/cover.png"}]}}}`, r.Host)
		case "/books/B00PROJHM": // audnexus
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"asin":"B00PROJHM","title":"Project Hail Mary",
				"image":"https://%s/cover.png"}`, r.Host)
		case "/cover.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	cases := []struct {
		name     string
		provider enrich.Provider
		req      enrich.Request
	}{
		{"deezer", NewDeezer(DeezerConfig{
			BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		}), enrich.Request{Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk"}},
		{"itunes", NewITunes(ITunesConfig{
			BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		}), enrich.Request{Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk"}},
		{"fanarttv", NewFanartTV(FanartTVConfig{
			BaseURL: srv.URL, APIKey: "fkey", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		}), enrich.Request{Type: enrich.TargetReleaseGroup, MBID: "rg-1"}},
		{"audnexus", NewAudnexus(AudnexusConfig{
			BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		}), enrich.Request{Type: enrich.TargetBook, ASIN: "B00PROJHM"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			cand, err := c.provider.Enrich(context.Background(), c.req)
			if err != nil {
				t.Fatal(err)
			}
			if cand == nil || cand.Cover == nil {
				t.Fatalf("%s returned no cover", c.name)
			}
			if cand.Cover.Hash != art.Hash(data) {
				t.Errorf("%s cover hash = %q, want the content address; without it the "+
					"catalog stores nothing and says the run succeeded", c.name, cand.Cover.Hash)
			}
			if cand.Cover.Width != 8 || cand.Cover.Height != 8 {
				t.Errorf("%s cover = %dx%d, want the probed 8x8",
					c.name, cand.Cover.Width, cand.Cover.Height)
			}
			if cand.Cover.SourceURL == "" {
				t.Errorf("%s cover carries no source URL, so the mark cannot cite it", c.name)
			}
		})
	}
}
