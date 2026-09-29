package providers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// reply is one canned API answer; HOST in its body is the stub's own URL.
type reply struct {
	status int
	ctype  string
	body   string
}

// classStub answers the API with api, and images by path (see the switch):
// a picture, typed or sent as bytes, and the ways one can fail to come.
func classStub(t *testing.T, api reply) *httptest.Server {
	t.Helper()
	png := testPNG(t)
	var srv *httptest.Server
	srv = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/img/ok":
			w.Header().Set("Content-Type", "image/png")
			w.Write(png)
		case "/img/gone":
			w.WriteHeader(http.StatusNotFound)
		case "/img/refused":
			w.WriteHeader(http.StatusForbidden)
		case "/img/bad":
			w.WriteHeader(http.StatusBadRequest)
		case "/img/octet":
			w.Header().Set("Content-Type", "application/octet-stream")
			w.Write(png)
		case "/img/junk":
			w.Header().Set("Content-Type", "application/octet-stream")
			fmt.Fprint(w, "not a picture at all")
		case "/img/busy":
			w.WriteHeader(http.StatusServiceUnavailable)
		case "/img/page":
			w.Header().Set("Content-Type", "text/html")
			fmt.Fprint(w, "<html>try later</html>")
		default:
			if api.ctype != "" {
				w.Header().Set("Content-Type", api.ctype)
			}
			w.WriteHeader(api.status)
			fmt.Fprint(w, strings.ReplaceAll(api.body, "HOST", srv.URL))
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

const classMBID = "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"

// classCase builds one provider over a stub and the request that reaches
// its API.
type classCase struct {
	name  string
	build func(srv *httptest.Server) enrich.Provider
	req   enrich.Request
	// keyed says the endpoint answers an unknown identifier with a 404.
	keyed bool
}

var classCases = []classCase{
	{name: "deezer", req: enrich.Request{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover, Title: "Signal Garden", Artist: "Test Ensemble"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewDeezer(DeezerConfig{BaseURL: s.URL, HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "itunes", req: enrich.Request{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover, Title: "Signal Garden", Artist: "Test Ensemble"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewITunes(ITunesConfig{BaseURL: s.URL, HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "discogs", req: enrich.Request{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover, Title: "Signal Garden", Artist: "Test Ensemble"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewDiscogs(DiscogsConfig{BaseURL: s.URL, Token: "k", HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "audnexus", keyed: true, req: enrich.Request{Type: enrich.TargetBook, Want: enrich.CapBookMeta | enrich.CapCover, ASIN: "B00TEST000"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewAudnexus(AudnexusConfig{BaseURL: s.URL, HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "hardcover", req: enrich.Request{Type: enrich.TargetBook, Want: enrich.CapBookMeta, ASIN: "B00TEST000"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewHardcover(HardcoverConfig{BaseURL: s.URL, Token: "k", HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "googlebooks", req: enrich.Request{Type: enrich.TargetBook, Want: enrich.CapBookMeta, ISBN: "9780000000002"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewGoogleBooks(GoogleBooksConfig{BaseURL: s.URL, HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "openlibrary", keyed: true, req: enrich.Request{Type: enrich.TargetBook, Want: enrich.CapBookMeta, ISBN: "9780000000002"},
		build: func(s *httptest.Server) enrich.Provider {
			return NewOpenLibrary(OpenLibraryConfig{BaseURL: s.URL, HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
	{name: "fanarttv", keyed: true, req: enrich.Request{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover | enrich.CapAuxArt, MBID: classMBID},
		build: func(s *httptest.Server) enrich.Provider {
			return NewFanartTV(FanartTVConfig{BaseURL: s.URL, APIKey: "k", HTTPClient: s.Client(), MinInterval: time.Nanosecond})
		}},
}

// A lookup the service could not answer is a failure the catalog asks
// again; only an identifier's 404 says the thing is not there. A search
// answers "nothing" with an empty list, so its 404 is a failure too.
func TestAnUnansweredLookupIsAFailure(t *testing.T) {
	t.Parallel()
	for _, tc := range classCases {
		for class, api := range map[string]reply{
			"503":       {status: http.StatusServiceUnavailable},
			"500":       {status: http.StatusInternalServerError},
			"HTML body": {status: http.StatusOK, ctype: "text/html", body: "<html>down for maintenance</html>"},
			"404":       {status: http.StatusNotFound},
		} {
			cand, err := tc.build(classStub(t, api)).Enrich(context.Background(), tc.req)
			if class == "404" && tc.keyed {
				if cand != nil || err != nil {
					t.Errorf("%s, an identifier's 404: %+v, %v; want a miss", tc.name, cand, err)
				}
				continue
			}
			if err == nil {
				t.Errorf("%s, a %s: %+v and no error; want a failure", tc.name, class, cand)
			}
		}
	}
}

// imageAnswers are API bodies whose one picture is at /img/IMG.
var imageAnswers = map[string]string{
	"deezer":   `{"data":[{"title":"Signal Garden","cover_xl":"HOST/img/IMG","artist":{"name":"Test Ensemble"}}]}`,
	"itunes":   `{"results":[{"collectionName":"Signal Garden","artistName":"Test Ensemble","artworkUrl100":"HOST/img/IMG"}]}`,
	"discogs":  `{"results":[{"title":"Test Ensemble - Signal Garden","cover_image":"HOST/img/IMG"}]}`,
	"audnexus": `{"publisherName":"Penguin","image":"HOST/img/IMG"}`,
	"fanarttv": `{"albums":{"` + classMBID + `":{"albumcover":[{"url":"HOST/img/IMG"}]}}}`,
}

// A picture that is gone is a miss for its slot; one the host could not
// serve now, or served as a page, is a failure when it is all the answer
// had. A book's details do not hang on its cover.
func TestAnImageFailureIsClassed(t *testing.T) {
	t.Parallel()
	for _, tc := range classCases {
		body, ok := imageAnswers[tc.name]
		if !ok {
			continue
		}
		for img, failed := range map[string]bool{
			"ok": false, "octet": false, "gone": false, "refused": false, "bad": false, "junk": false,
			"busy": true, "page": true,
		} {
			wantErr := failed && tc.name != "audnexus"
			api := reply{status: http.StatusOK, ctype: "application/json", body: strings.ReplaceAll(body, "IMG", img)}
			cand, err := tc.build(classStub(t, api)).Enrich(context.Background(), tc.req)
			if wantErr {
				if err == nil {
					t.Errorf("%s, image %s: %+v and no error; want a failure", tc.name, img, cand)
				}
				continue
			}
			if err != nil {
				t.Errorf("%s, image %s: %v; want no failure", tc.name, img, err)
				continue
			}
			var pictured bool
			if cand != nil {
				pictured = cand.Cover != nil || cand.Art[model.ArtRoleFront] != nil
			}
			if pictured != (img == "ok" || img == "octet") {
				t.Errorf("%s, image %s: pictured = %v", tc.name, img, pictured)
			}
			if tc.name == "audnexus" && (cand == nil || cand.Publisher != "Penguin") {
				t.Errorf("audnexus, image %s: %+v, want the publisher kept", img, cand)
			}
		}
	}
}

// A role that fails after another landed costs that role alone: the
// catalog drops a candidate that comes with an error, so failing the
// answer would lose the front on every pass while the disc stays broken.
func TestFanartTVALaterRoleFailure(t *testing.T) {
	t.Parallel()
	req := enrich.Request{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover | enrich.CapAuxArt, MBID: classMBID}
	build := func(disc string) enrich.Provider {
		srv := classStub(t, reply{status: http.StatusOK, ctype: "application/json",
			body: `{"albums":{"` + classMBID + `":{"albumcover":[{"url":"HOST/img/ok"}],"cdart":[{"url":"HOST/img/` + disc + `"}]}}}`})
		return NewFanartTV(FanartTVConfig{BaseURL: srv.URL, APIKey: "k", HTTPClient: srv.Client(), MinInterval: time.Nanosecond})
	}
	for _, disc := range []string{"gone", "busy"} {
		cand, err := build(disc).Enrich(context.Background(), req)
		if err != nil || cand == nil || cand.Art[model.ArtRoleFront] == nil || cand.Art[model.ArtRoleDisc] != nil {
			t.Errorf("disc %s: %+v, %v; want the front alone", disc, cand, err)
		}
	}
}

// The contract's statuses: 204 and 404 are misses; a 5xx, any other status
// or a page where JSON was promised is a failure, asked again next pass.
func TestHTTPBridgeClassesTheAnswer(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		api  reply
		miss bool
	}{
		{reply{status: http.StatusNoContent}, true},
		{reply{status: http.StatusNotFound}, true},
		{reply{status: http.StatusInternalServerError}, false},
		{reply{status: http.StatusServiceUnavailable}, false},
		{reply{status: http.StatusUnauthorized}, false},
		{reply{status: http.StatusOK, ctype: "text/html", body: "<html>down</html>"}, false},
	} {
		srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/capabilities" {
				fmt.Fprint(w, `{"name":"regionaldb","capabilities":["lyrics"]}`)
				return
			}
			if tc.api.ctype != "" {
				w.Header().Set("Content-Type", tc.api.ctype)
			}
			w.WriteHeader(tc.api.status)
			fmt.Fprint(w, tc.api.body)
		}))
		bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
			Label: "regional", BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
		})
		if err != nil {
			t.Fatal(err)
		}
		cand, err := bridge.Enrich(context.Background(), enrich.Request{Type: enrich.TargetRecording, Title: "One More Time"})
		srv.Close()
		if tc.miss && (cand != nil || err != nil) {
			t.Errorf("%d: %+v, %v; want a miss", tc.api.status, cand, err)
		}
		if !tc.miss && err == nil {
			t.Errorf("%d %q: %+v and no error; want a failure", tc.api.status, tc.api.body, cand)
		}
	}
}
