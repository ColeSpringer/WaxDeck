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
		case "/album/upc:724384960650":
			// The identifier endpoints answer the resource itself, not
			// a reference to it: the fields are already here and a
			// second fetch would be a wasted half-second.
			fmt.Fprintf(w, `{"id": 302127, "label": "Virgin", "release_date": "2001-03-12",
				"cover_xl": "https://%s/images/discovery-xl.jpg"}`, r.Host)
		case "/images/discovery-xl.jpg":
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write([]byte("JPEGDATA"))
		case "/album/upc:4006381333931":
			// Deezer answers an unknown identifier with 200 and an
			// error object rather than a status code.
			fmt.Fprint(w, `{"error": {"type": "DataException", "message": "no data"}}`)
		case "/search/album":
			fmt.Fprint(w, `{"data": [
				{"id": 111, "title": "Discovery (Live)", "artist": {"name": "Daft Punk"}},
				{"id": 302127, "title": "Discovery", "artist": {"name": "Daft Punk"}}
			]}`)
		case "/album/302127":
			fmt.Fprintf(w, `{"id": 302127, "label": "Virgin", "release_date": "2001-03-12",
				"cover_xl": "https://%s/images/discovery-xl.jpg"}`, r.Host)
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
		case "/album/upc:5012345678900":
			// A quota window: HTTP 200 with a failure in the body.
			fmt.Fprint(w, `{"error": {"type": "Exception", "message": "Quota limit exceeded", "code": 4}}`)
		case "/album/upc:5901234123457":
			fmt.Fprintf(w, `{"id": 5, "label": "Virgin", "release_date": "2001-03-12",
				"cover_xl": "https://%s/images/gone-xl.jpg"}`, r.Host)
		case "/album/upc:4012345678901":
			// No picture: Deezer names its stand-in, a path with no hash.
			fmt.Fprintf(w, `{"id": 6, "label": "Virgin", "release_date": "2001-03-12",
				"cover_xl": "https://%s/images/cover//1000x1000-000000-80-0-0.jpg"}`, r.Host)
		case "/images/cover//1000x1000-000000-80-0-0.jpg":
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write([]byte("STANDIN"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func newFieldsDeezer(t *testing.T, srv *httptest.Server) *Deezer {
	t.Helper()
	d := NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	d.quotaWait = time.Millisecond
	return d
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
	if cand.Cover != nil || slices.Contains(seen, "/images/discovery-xl.jpg") {
		t.Errorf("a fields request fetched the cover: %v", seen)
	}
}

// Without a barcode - and with one nothing holds - the title search
// stands in, matched on both names.
func TestDeezerReleaseFieldsFallsBackToTheSearch(t *testing.T) {
	t.Parallel()
	for _, barcode := range []string{"", "4006381333931"} {
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
		if cand.Cover != nil {
			t.Errorf("barcode %q: a fields request answered a cover", barcode)
		}
	}
}

// The album rung's cover is one pressing's, so it comes from the barcode
// alone: a title search names a record, and its picture could be any edition's.
func TestDeezerReleaseArtNeedsABarcode(t *testing.T) {
	t.Parallel()
	for _, barcode := range []string{"", "4006381333931"} {
		var seen []string
		d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
		cand, err := d.Enrich(context.Background(), enrich.Request{
			Type: enrich.TargetRelease, Want: enrich.CapCover,
			Title: "Discovery", Artist: "Daft Punk", Barcode: barcode,
		})
		if err != nil || cand != nil {
			t.Fatalf("barcode %q: release art = %+v (%v), want none", barcode, cand, err)
		}
		if slices.Contains(seen, "/search/album") {
			t.Errorf("barcode %q: release art fell back to the title search: %v", barcode, seen)
		}
	}
}

// A barcode tagged with separators still names the pressing.
func TestDeezerReleaseArtStripsBarcodeSeparators(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover, Barcode: "0 7243-8496065 0",
	})
	if err != nil || cand == nil || cand.Cover == nil {
		t.Fatalf("candidate = %+v, %v; want the pressing's cover", cand, err)
	}
	if !slices.Contains(seen, "/album/upc:724384960650") {
		t.Errorf("requests = %v, want the digits alone", seen)
	}
}

func TestDeezerReleaseArtByBarcode(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover,
		Title: "Discovery", Artist: "Daft Punk", Barcode: "0724384960650",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil || string(cand.Cover.Data) != "JPEGDATA" {
		t.Fatalf("candidate = %+v, want the pressing's cover", cand)
	}
	if len(cand.Fields) != 0 {
		t.Errorf("an art request answered fields: %v", cand.Fields)
	}
	if want := []string{"/album/upc:724384960650", "/images/discovery-xl.jpg"}; !slices.Equal(seen, want) {
		t.Errorf("requests = %v, want %v", seen, want)
	}
}

// Deezer files a 13-digit EAN that starts with a zero as its 12-digit UPC,
// and a barcode that fails its checksum can only miss, so it is not sent.
func TestDeezerAsksForTheBarcodeDeezerFiles(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Title: "Discovery", Artist: "Daft Punk", Barcode: "0724384960651",
	})
	if err != nil || cand == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("candidate = %+v, %v; want the searched album's fields", cand, err)
	}
	for _, path := range seen {
		if strings.HasPrefix(path, "/album/upc:") {
			t.Errorf("an invalid barcode was looked up: %v", seen)
		}
	}
}

// A release id and a group picture do not mean the archive holds this
// pressing's front, and without a contact it is not asked at all, so Deezer
// still answers the barcode it holds.
func TestDeezerAnswersAPressingWhoseGroupHasAPicture(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover, Barcode: "0724384960650",
		MBID:             "c26a1f9b-2e1e-4a42-a39b-4f7a0b8f3e11",
		ReleaseGroupMBID: "48117b0e-1a4b-4ac5-8c2b-5a0b5a6c8f9e", GroupFrontHash: "c0ffee",
	})
	if err != nil || cand == nil || cand.Cover == nil || string(cand.Cover.Data) != "JPEGDATA" {
		t.Fatalf("release art = %+v (%v), want the pressing's cover", cand, err)
	}
}

// A picture that will not load is no reason to drop the label and year the
// same lookup answered.
func TestDeezerKeepsTheFieldsWhenTheCoverWillNotLoad(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Title: "Discovery", Artist: "Daft Punk", Barcode: "5901234123457",
	})
	if err != nil || cand == nil || cand.Fields["label"] != "Virgin" || cand.Fields["year"] != "2001" {
		t.Fatalf("candidate = %+v, %v; want the fields without the cover", cand, err)
	}
	if cand.Cover != nil {
		t.Errorf("cover = %+v, want none", cand.Cover)
	}
	// Asked for the cover alone, the failure is still the answer.
	if _, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover, Barcode: "5901234123457",
	}); err == nil {
		t.Error("a cover that would not load read as a clean no-match")
	}
}

// Where Deezer holds no picture it names a stand-in, which is not the album's.
func TestDeezerSkipsItsStandInCover(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover, Barcode: "4012345678901",
	})
	if err != nil || cand != nil {
		t.Fatalf("candidate = %+v, %v; want no cover", cand, err)
	}
	for _, path := range seen {
		if strings.HasPrefix(path, "/images/") {
			t.Errorf("the stand-in was fetched: %v", seen)
		}
	}
}

// A request that wants everything looks the barcode up once for both answers.
func TestDeezerReleaseAnswersBothFromOneLookup(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Title: "Discovery", Artist: "Daft Punk", Barcode: "0724384960650",
	})
	if err != nil || cand == nil || cand.Cover == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("candidate = %+v, %v; want the cover and the fields", cand, err)
	}
	lookups := 0
	for _, path := range seen {
		if strings.HasPrefix(path, "/album/upc:") {
			lookups++
		}
	}
	if lookups != 1 {
		t.Errorf("requests = %v, want one barcode lookup", seen)
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

// Deezer reports a quota window as HTTP 200 with a failure in the body,
// which must surface as a failure rather than a clean no-match.
func TestDeezerInBandErrorIsAFailure(t *testing.T) {
	t.Parallel()
	var seen []string
	d := newFieldsDeezer(t, deezerFieldsServer(t, &seen))
	_, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields,
		Barcode: "5012345678900",
	})
	if err == nil {
		t.Fatal("a quota answer read as a clean no-match")
	}
	if !strings.Contains(err.Error(), "Quota limit exceeded") {
		t.Errorf("error = %v, want it to carry what Deezer said", err)
	}
}

// quotaServer answers the barcode lookup with a quota window for the first
// quotas requests, then with the album; asked counts the lookups.
func quotaServer(t *testing.T, quotas int64, asked *atomic.Int64) *httptest.Server {
	t.Helper()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path != "/album/upc:724384960650" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		if asked.Add(1) <= quotas {
			fmt.Fprint(w, `{"error": {"type": "Exception", "message": "Quota limit exceeded", "code": 4}}`)
			return
		}
		fmt.Fprint(w, `{"id": 302127, "label": "Virgin", "release_date": "2001-03-12"}`)
	}))
	t.Cleanup(srv.Close)
	return srv
}

// A quota window is waited out once: the catalog records a provider's failure
// on a target as a miss, so answering it later beats failing it now.
func TestDeezerWaitsOutAQuotaWindow(t *testing.T) {
	t.Parallel()
	var asked atomic.Int64
	d := newFieldsDeezer(t, quotaServer(t, 1, &asked))
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapFields, Barcode: "0724384960650",
	})
	if err != nil || cand == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("candidate = %+v, %v; want the answer after the window", cand, err)
	}
	if n := asked.Load(); n != 2 {
		t.Errorf("lookups = %d, want 2", n)
	}
}

// A failure that arrives as a 200 is not kept in the cache, where it would be
// replayed for a day in place of asking again.
func TestDeezerAsksAgainAfterAFailedAnswer(t *testing.T) {
	t.Parallel()
	var asked atomic.Int64
	d := newFieldsDeezer(t, quotaServer(t, 2, &asked))
	req := enrich.Request{Type: enrich.TargetRelease, Want: enrich.CapFields, Barcode: "0724384960650"}
	if _, err := d.Enrich(context.Background(), req); err == nil {
		t.Fatal("a window that outlasted the wait read as a clean no-match")
	}
	cand, err := d.Enrich(context.Background(), req)
	if err != nil || cand == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("second ask = %+v, %v; want Deezer asked again", cand, err)
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
		Title: "Discovery", Artist: "Daft Punk", Barcode: "4006381333931",
	})
	if err != nil {
		t.Fatalf("an unknown barcode failed the lookup: %v", err)
	}
	if cand == nil || cand.Fields["label"] != "Virgin" {
		t.Fatalf("candidate = %+v, want the search fallback's answer", cand)
	}
}
