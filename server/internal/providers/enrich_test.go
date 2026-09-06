package providers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
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

// deezerFieldsServer answers the five reads the fields walks make: the
// UPC and ISRC lookups that name an entity outright, the two searches
// that stand in when the catalog holds no identifier, and the album and
// track fetches that carry the values themselves. It records which
// paths were asked for, so a test can prove the identifier route
// skipped the search.
func deezerFieldsServer(t *testing.T, seen *[]string) *httptest.Server {
	t.Helper()
	var mu sync.Mutex
	record := func(p string) {
		mu.Lock()
		*seen = append(*seen, p)
		mu.Unlock()
	}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		record(r.URL.Path)
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/album/upc:0724384960650":
			// The identifier endpoints answer the resource itself, not
			// a reference to it: the fields are already here and a
			// second fetch would be a wasted half-second.
			fmt.Fprint(w, `{"id": 302127, "label": "Virgin", "release_date": "2001-03-12"}`)
		case "/album/upc:0000000000000":
			// Deezer answers an unknown identifier with 200 and an
			// error object rather than a status code.
			fmt.Fprint(w, `{"error": {"type": "DataException", "message": "no data"}}`)
		case "/search/album":
			fmt.Fprint(w, `{"data": [
				{"id": 111, "title": "Discovery (Live)", "artist": {"name": "Daft Punk"}},
				{"id": 302127, "title": "Discovery", "artist": {"name": "Daft Punk"}}
			]}`)
		case "/album/302127":
			fmt.Fprint(w, `{"id": 302127, "label": "Virgin", "release_date": "2001-03-12"}`)
		case "/track/isrc:GBDUW0000059":
			fmt.Fprint(w, `{"id": 3135556, "bpm": 123.4, "isrc": "GBDUW0000059"}`)
		case "/search/track":
			fmt.Fprint(w, `{"data": [
				{"id": 999, "title": "One More Time", "duration": 400, "artist": {"name": "Daft Punk"}},
				{"id": 3135556, "title": "One More Time", "duration": 320, "artist": {"name": "Daft Punk"}}
			]}`)
		case "/track/3135556":
			fmt.Fprint(w, `{"id": 3135556, "bpm": 123.4, "isrc": "GBDUW0000059"}`)
		case "/track/999":
			fmt.Fprint(w, `{"id": 999, "bpm": 0, "isrc": ""}`)
		case "/album/upc:9999999999999":
			// A quota window: HTTP 200 with a failure in the body.
			fmt.Fprint(w, `{"error": {"type": "Exception", "message": "Quota limit exceeded"}}`)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func newFieldsDeezer(t *testing.T, srv *httptest.Server) *Deezer {
	t.Helper()
	return NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
}

// The album rung: a barcode names the pressing outright, so the search
// is never run, and the album fetch carries label and year.
func TestDeezerReleaseFieldsByBarcode(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Title: "Discovery", Artist: "Daft Punk", Barcode: "0724384960650",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil {
		t.Fatal("no candidate for a known barcode")
	}
	if cand.Fields["label"] != "Virgin" || cand.Fields["year"] != "2001" {
		t.Fatalf("fields = %v, want the label and the year", cand.Fields)
	}
	if cand.Confidence != 0.7 {
		t.Errorf("confidence = %v, want 0.7", cand.Confidence)
	}
	if slices.Contains(seen, "/search/album") {
		t.Errorf("the search ran beside a barcode lookup: %v", seen)
	}
	// One request, not two: the UPC endpoint answered the album itself.
	if slices.Contains(seen, "/album/302127") {
		t.Errorf("the album was re-fetched by id after a barcode lookup: %v", seen)
	}
}

// Without a barcode - and with one nothing holds - the title search
// stands in, matched on both names.
func TestDeezerReleaseFieldsFallsBackToTheSearch(t *testing.T) {
	t.Parallel()
	for _, barcode := range []string{"", "0000000000000"} {
		var seen []string
		d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
		cand, err := d.Enrich(context.Background(), enrich.Request{
			Type: enrich.TargetRelease, Want: enrich.CapFields,
			Title: "Discovery", Artist: "Daft Punk", Barcode: barcode,
		})
		if err != nil {
			t.Fatal(err)
		}
		if cand == nil || cand.Fields["label"] != "Virgin" {
			t.Fatalf("barcode %q: candidate = %+v, want the searched album's fields", barcode, cand)
		}
		if !slices.Contains(seen, "/search/album") {
			t.Errorf("barcode %q: the search did not run: %v", barcode, seen)
		}
	}
}

// The album rung declines art. Deezer cannot tell which pressing the
// request names, so a picture here would be the wrong edition's as
// often as not - the decision the barcode-on-art upstream ask would
// reopen.
func TestDeezerReleaseRungDeclinesArt(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover,
		Title: "Discovery", Artist: "Daft Punk", Barcode: "0724384960650",
	})
	if err != nil || cand != nil {
		t.Fatalf("release art = %+v (%v), want a declined rung", cand, err)
	}
	if len(seen) != 0 {
		t.Errorf("a declined rung still dialled out: %v", seen)
	}
}

// The track rung: an ISRC names the recording, and a zero tempo is not
// written - Deezer reports 0 for a track it never analyzed.
func TestDeezerRecordingFieldsByISRC(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRecording, Want: enrich.CapFields,
		Title: "One More Time", Artist: "Daft Punk", ISRC: "GBDUW0000059",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Fields["bpm"] != "123" || cand.Fields["isrc"] != "GBDUW0000059" {
		t.Fatalf("candidate = %+v, want the tempo and the identifier", cand)
	}
	if slices.Contains(seen, "/search/track") {
		t.Errorf("the search ran beside an ISRC lookup: %v", seen)
	}
	if slices.Contains(seen, "/track/3135556") {
		t.Errorf("the track was re-fetched by id after an ISRC lookup: %v", seen)
	}
}

// Without an ISRC the search stands in, and the duration is what picks
// the take: the first hit matches both names and is four hundred
// seconds long, which is a different recording of the same song.
func TestDeezerRecordingFieldsMatchesOnDuration(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRecording, Want: enrich.CapFields,
		Title: "One More Time", Artist: "Daft Punk", DurationSec: 321,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Fields["bpm"] != "123" {
		t.Fatalf("candidate = %+v, want the take whose length matches", cand)
	}
	if !slices.Contains(seen, "/track/3135556") {
		t.Errorf("the matched take was not fetched: %v", seen)
	}
}

// A bare title names too many recordings to be worth a write, so a
// request with no artist and no identifier asks nothing at all.
func TestDeezerRecordingFieldsRefusesABareTitle(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRecording, Want: enrich.CapFields, Title: "One More Time",
	})
	if err != nil || cand != nil {
		t.Fatalf("bare-title fields = %+v (%v), want nothing", cand, err)
	}
	if len(seen) != 0 {
		t.Errorf("a bare title still dialled out: %v", seen)
	}
}

// iTunes answers the album rung's year off the same search its cover
// lookup runs, and nothing else: a picture on this rung would be the
// wrong pressing's.
func TestITunesReleaseFieldsAnswerTheYear(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"results": [
			{"collectionName": "Discovery", "artistName": "Daft Punk",
			 "artworkUrl100": "https://example.invalid/a100x100.jpg",
			 "releaseDate": "2001-03-12T08:00:00Z"}
		]}`)
	}))
	defer srv.Close()
	it := NewITunes(ITunesConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if !it.Capabilities().Has(enrich.CapFields) {
		t.Fatalf("caps = %v, want the fields bit", it.Capabilities())
	}
	cand, err := it.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Fields["year"] != "2001" {
		t.Fatalf("candidate = %+v, want the release year", cand)
	}
	if cand.Cover != nil {
		t.Errorf("the release rung answered art: %+v", cand.Cover)
	}
}

func TestReleaseYear(t *testing.T) {
	t.Parallel()
	cases := []struct{ in, want string }{
		{"2001", "2001"},
		{"2001-03-12", "2001"},
		{"2001-03-12T08:00:00Z", "2001"},
		{" 1969-07-20 ", "1969"},
		{"", ""},
		{"soon", ""},
		{"20", ""},
		{"0000-01-01", ""},
		{"9999-01-01", ""},
	}
	for _, c := range cases {
		if got := releaseYear(c.in); got != c.want {
			t.Errorf("releaseYear(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// Deezer reports a quota window as HTTP 200 with a failure in the body.
// Reading that as a clean no-match is not a small mistake: the
// enrichment engine marks a target nothing answered for, the marker has
// no expiry, and a throttled night would retire every target it touched
// until somebody forces a whole-catalog pass.
func TestDeezerInBandErrorIsAFailure(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	_, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Barcode: "9999999999999",
	})
	if err == nil {
		t.Fatal("a quota answer read as a clean no-match")
	}
	if !strings.Contains(err.Error(), "Quota limit exceeded") {
		t.Errorf("error = %v, want it to carry what Deezer said", err)
	}
}

// The one in-band answer that is a miss: an identifier the service does
// not hold. It falls through to the search rather than failing the run.
func TestDeezerUnknownIdentifierIsAMiss(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Title: "Discovery", Artist: "Daft Punk", Barcode: "0000000000000",
	})
	if err != nil {
		t.Fatalf("an unknown barcode failed the lookup: %v", err)
	}
	if cand == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("candidate = %+v, want the search fallback's answer", cand)
	}
}
