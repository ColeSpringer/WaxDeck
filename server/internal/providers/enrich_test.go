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
)

func TestNameMatch(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"Discovery", "discovery", true},
		{"  Daft   Punk ", "daft punk", true},
		{"Discovery", "Homework", false},
		{"", "", true},
	}
	for _, c := range cases {
		if got := nameMatch(c.a, c.b); got != c.want {
			t.Errorf("nameMatch(%q, %q) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

func TestDeezerEnrich(t *testing.T) {
	var gotQ atomic.Value
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search/album":
			gotQ.Store(r.URL.Query().Get("q"))
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data": [
				{"title": "Discovery (Live)", "artist": {"name": "Daft Punk"}, "cover_xl": "https://%s/cover.jpg"},
				{"title": "Discovery", "artist": {"name": "Daft Punk"}, "cover_xl": "https://%s/cover.jpg"}
			]}`, r.Host, r.Host)
		case "/cover.jpg":
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write([]byte("JPEGDATA"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	d := NewDeezer(DeezerConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	if d.Name() != "deezer" || !d.Capabilities().Has(enrich.CapCover) {
		t.Fatalf("identity wrong: name=%q caps=%v", d.Name(), d.Capabilities())
	}

	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if q, _ := gotQ.Load().(string); q != `artist:"Daft Punk" album:"Discovery"` {
		t.Fatalf("q = %q", q)
	}
	if cand == nil || cand.Cover == nil {
		t.Fatalf("want cover candidate, got %+v", cand)
	}
	if cand.Confidence != 0.7 {
		t.Fatalf("Confidence = %v, want 0.7", cand.Confidence)
	}
	if string(cand.Cover.Data) != "JPEGDATA" || cand.Cover.Format != "jpeg" {
		t.Fatalf("cover wrong: format=%q data=%q", cand.Cover.Format, cand.Cover.Data)
	}
}

func TestDeezerEnrichNoMatch(t *testing.T) {
	var requests atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"data": [{"title": "Something Else", "artist": {"name": "Nobody"}, "cover_xl": "https://example.com/x.jpg"}]}`))
	}))
	defer srv.Close()

	d := NewDeezer(DeezerConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss, got cand=%+v err=%v", cand, err)
	}

	// A non-release-group request never reaches the network.
	cand, err = d.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, Title: "Discovery"})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss for wrong type, got cand=%+v err=%v", cand, err)
	}
	if requests.Load() != 1 {
		t.Fatalf("server requests = %d, want 1", requests.Load())
	}
}

func TestITunesEnrich(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search":
			if got := r.URL.Query().Get("entity"); got != "album" {
				t.Errorf("entity = %q, want album", got)
			}
			if got := r.URL.Query().Get("term"); got != "Daft Punk Discovery" {
				t.Errorf("term = %q, want Daft Punk Discovery", got)
			}
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"resultCount": 1, "results": [
				{"collectionName": "Discovery", "artistName": "Daft Punk", "artworkUrl100": "https://%s/art/100x100bb.jpg"}
			]}`, r.Host)
		case "/art/1200x1200bb.jpg":
			w.Header().Set("Content-Type", "image/png")
			w.Write([]byte("PNGDATA"))
		default:
			// The 100x100 thumbnail path must not be fetched; the URL is
			// upgraded before download.
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	it := NewITunes(ITunesConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	if it.Name() != "itunes" || !it.Capabilities().Has(enrich.CapCover) {
		t.Fatalf("identity wrong: name=%q caps=%v", it.Name(), it.Capabilities())
	}

	cand, err := it.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil {
		t.Fatalf("want cover candidate, got %+v", cand)
	}
	if cand.Confidence != 0.6 {
		t.Fatalf("Confidence = %v, want 0.6", cand.Confidence)
	}
	if string(cand.Cover.Data) != "PNGDATA" || cand.Cover.Format != "png" {
		t.Fatalf("cover wrong: format=%q data=%q", cand.Cover.Format, cand.Cover.Data)
	}
}

func TestITunesEnrichNoMatch(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"resultCount": 0, "results": []}`))
	}))
	defer srv.Close()

	it := NewITunes(ITunesConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	cand, err := it.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss, got cand=%+v err=%v", cand, err)
	}
}

func TestFanartTVEnrich(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v3/music/albums/rg-1":
			if got := r.URL.Query().Get("api_key"); got != "fkey" {
				t.Errorf("api_key = %q, want fkey", got)
			}
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"name": "Daft Punk", "albums": {"rg-1": {"albumcover": [
				{"url": "https://%s/cover.png", "likes": "4"}
			]}}}`, r.Host)
		case "/cover.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write([]byte("FANARTPNG"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	f := NewFanartTV(FanartTVConfig{BaseURL: srv.URL, APIKey: "fkey", HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	if f.Name() != "fanarttv" || !f.Capabilities().Has(enrich.CapCover) {
		t.Fatalf("identity wrong: name=%q caps=%v", f.Name(), f.Capabilities())
	}

	cand, err := f.Enrich(context.Background(), enrich.Request{Type: enrich.TargetReleaseGroup, MBID: "rg-1"})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil || string(cand.Cover.Data) != "FANARTPNG" {
		t.Fatalf("want cover candidate, got %+v", cand)
	}
	if cand.Confidence != 0.8 {
		t.Fatalf("Confidence = %v, want 0.8", cand.Confidence)
	}

	// Unknown release group is a clean miss.
	cand, err = f.Enrich(context.Background(), enrich.Request{Type: enrich.TargetReleaseGroup, MBID: "rg-unknown"})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss, got cand=%+v err=%v", cand, err)
	}
}

func TestFanartTVEmptyKeyShortCircuits(t *testing.T) {
	var requests atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
	}))
	defer srv.Close()

	f := NewFanartTV(FanartTVConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	cand, err := f.Enrich(context.Background(), enrich.Request{Type: enrich.TargetReleaseGroup, MBID: "rg-1"})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss without a key, got cand=%+v err=%v", cand, err)
	}
	if requests.Load() != 0 {
		t.Fatalf("server requests = %d, want 0", requests.Load())
	}
}

func TestAudnexusEnrich(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/books/B00PROJHM":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{
				"asin": "B00PROJHM",
				"title": "Project Hail Mary",
				"narrators": [{"name": "Ray Porter"}, {"name": "Kate Reading"}],
				"publisherName": "Audible Studios",
				"releaseDate": "2021-05-04T00:00:00.000Z",
				"summary": "<p>A lone astronaut.<br/>A desperate mission.</p>",
				"genres": [
					{"name": "Science Fiction", "type": "genre"},
					{"name": "Space Opera", "type": "tag"}
				],
				"image": "https://%s/book.jpg"
			}`, r.Host)
		case "/book.jpg":
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write([]byte("BOOKJPEG"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	a := NewAudnexus(AudnexusConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	if a.Name() != "audnexus" {
		t.Fatalf("Name = %q, want audnexus", a.Name())
	}
	if caps := a.Capabilities(); !caps.Has(enrich.CapBookMeta) || !caps.Has(enrich.CapCover) {
		t.Fatalf("Capabilities = %v, want book meta and cover", caps)
	}

	cand, err := a.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ASIN: "B00PROJHM"})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil {
		t.Fatal("want candidate, got nil")
	}
	if cand.Confidence != 0.9 {
		t.Fatalf("Confidence = %v, want 0.9", cand.Confidence)
	}
	wantFields := map[string]string{
		"narrator":    "Ray Porter, Kate Reading",
		"publisher":   "Audible Studios",
		"year":        "2021",
		"description": "A lone astronaut. A desperate mission.",
	}
	for k, want := range wantFields {
		if got := cand.Fields[k]; got != want {
			t.Errorf("Fields[%q] = %q, want %q", k, got, want)
		}
	}
	if cand.Publisher != "Audible Studios" {
		t.Errorf("Publisher = %q, want Audible Studios", cand.Publisher)
	}
	if len(cand.Genres) != 1 || cand.Genres[0] != "Science Fiction" {
		t.Errorf("Genres = %v, want [Science Fiction] (type genre only)", cand.Genres)
	}
	if cand.Cover == nil || string(cand.Cover.Data) != "BOOKJPEG" || cand.Cover.Format != "jpeg" {
		t.Errorf("Cover wrong: %+v", cand.Cover)
	}
}

func TestAudnexusEnrichNoASIN(t *testing.T) {
	var requests atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	a := NewAudnexus(AudnexusConfig{BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	cand, err := a.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, Title: "Untitled"})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss without an ASIN, got cand=%+v err=%v", cand, err)
	}
	if requests.Load() != 0 {
		t.Fatalf("server requests = %d, want 0", requests.Load())
	}

	// An unknown ASIN 404s: also a clean miss, with one request.
	cand, err = a.Enrich(context.Background(), enrich.Request{Type: enrich.TargetBook, ASIN: "B00GONE"})
	if err != nil || cand != nil {
		t.Fatalf("want clean miss on 404, got cand=%+v err=%v", cand, err)
	}
	if requests.Load() != 1 {
		t.Fatalf("server requests = %d, want 1", requests.Load())
	}
}
