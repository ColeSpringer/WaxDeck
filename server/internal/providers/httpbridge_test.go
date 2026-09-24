package providers

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// conformanceStub is a minimal service implementing the published
// custom-provider contract: GET /capabilities and POST /enrich. The
// bridge tests double as the contract's conformance proof - a remote
// this stub models correctly is a remote the bridge serves.
func conformanceStub(t *testing.T, enrichCalls *atomic.Int64) *httptest.Server {
	t.Helper()
	png := testPNG(t)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /capabilities", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"name":"regionaldb","capabilities":["cover","genres","book","futuristics"]}`)
	})
	mux.HandleFunc("POST /enrich", func(w http.ResponseWriter, r *http.Request) {
		enrichCalls.Add(1)
		var req struct {
			Type   string `json:"type"`
			Title  string `json:"title"`
			Artist string `json:"artist"`
			ISBN   string `json:"isbn"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Errorf("decoding enrich body: %v", err)
		}
		switch {
		case req.Type == "release_group" && req.Title == "Discovery":
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]any{
				"confidence": 0.9,
				"genres":     []string{"French House"},
				"cover": map[string]string{
					"data":      base64.StdEncoding.EncodeToString(png),
					"mediaType": "image/png",
					"sourceUrl": "https://regionaldb.example/discovery.png",
				},
			})
		case req.Type == "book" && req.ISBN == "9780306406157":
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]any{
				"publisher": "Bridge House",
				"fields":    map[string]string{"narrator": "A Reader"},
			})
		default:
			// The contract's clean no-match.
			w.WriteHeader(http.StatusNoContent)
		}
	})
	srv := httptest.NewTLSServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestHTTPBridgeConformance(t *testing.T) {
	t.Parallel()
	var calls atomic.Int64
	srv := conformanceStub(t, &calls)
	bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "regional", BaseURL: srv.URL,
		HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if err != nil {
		t.Fatal(err)
	}

	// The provenance name is the remote's own; the capability set is the
	// advertised one, with the token this build does not know ignored.
	if bridge.Name() != "regionaldb" {
		t.Errorf("Name() = %q, want the advertised name", bridge.Name())
	}
	want := enrich.CapCover | enrich.CapGenres | enrich.CapBookMeta
	if bridge.Capabilities() != want {
		t.Errorf("Capabilities() = %b, want %b", bridge.Capabilities(), want)
	}

	// A cover answer maps onto the port's candidate: content-addressed
	// bytes, format, and the citable source URL.
	cand, err := bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil {
		t.Fatalf("candidate = %+v, want a cover", cand)
	}
	if cand.Cover.Hash != art.Hash(testPNG(t)) {
		t.Error("the bridged cover is not content-addressed; the store would drop it")
	}
	if cand.Cover.SourceURL != "https://regionaldb.example/discovery.png" {
		t.Errorf("cover source = %q", cand.Cover.SourceURL)
	}
	if len(cand.Genres) != 1 || cand.Genres[0] != "French House" {
		t.Errorf("genres = %v", cand.Genres)
	}

	// A book answer carries the scalar and the generic fields.
	cand, err = bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetBook, ISBN: "9780306406157",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Publisher != "Bridge House" || cand.Fields["narrator"] != "A Reader" {
		t.Fatalf("book candidate = %+v", cand)
	}

	// 204 is the clean no-match, not an error - and so is an all-empty
	// 200 object, which every-field-optional makes contract-legal: a
	// non-nil empty candidate would end an enrichment want ("nothing
	// new to fill") that a later provider could still answer.
	cand, err = bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRecording, Title: "Unknown",
	})
	if cand != nil || err != nil {
		t.Errorf("no-match = %+v, %v; want nil, nil", cand, err)
	}

	// Enrich answers are never cached bridge-side (a candidate can carry
	// a whole cover), so a repeat ask reaches the remote each time - the
	// remote's own cache, which Force asks past, is the only one.
	calls.Store(0)
	req := enrich.Request{Type: enrich.TargetReleaseGroup, Title: "Discovery"}
	for range 2 {
		if _, err := bridge.Enrich(context.Background(), req); err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 2 {
		t.Errorf("repeat ask reached the remote %d times, want every ask through", calls.Load())
	}
}

// The release rung asks once for fields and once for a cover, so the
// request says which, with the pressing's identifiers; a group-front
// answer maps back.
func TestHTTPBridgeCarriesTheReleaseRung(t *testing.T) {
	t.Parallel()
	var got atomic.Value
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/capabilities" {
			fmt.Fprint(w, `{"name":"pressings","capabilities":["cover","fields"]}`)
			return
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Errorf("decoding enrich body: %v", err)
		}
		got.Store(body)
		fmt.Fprint(w, `{"frontIsGroupFront": true}`)
	}))
	defer srv.Close()
	bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "pressings", BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	cand, err := bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Want: enrich.CapCover,
		Title: "Discovery", Barcode: "0724384960650", CatalogNumber: "7243 8 49606 5 0",
		ReleaseGroupMBID: "48117b0e-1a4b-4ac5-8c2b-5a0b5a6c8f9e", GroupFrontHash: "c0ffee",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || !cand.FrontIsGroupFront {
		t.Fatalf("candidate = %+v, want the group's front taken as this pressing's", cand)
	}
	body := got.Load().(map[string]any)
	for key, want := range map[string]string{
		"type": "release", "barcode": "0724384960650", "catalogNumber": "7243 8 49606 5 0",
		"releaseGroupMbid": "48117b0e-1a4b-4ac5-8c2b-5a0b5a6c8f9e", "groupFrontHash": "c0ffee",
	} {
		if body[key] != want {
			t.Errorf("%s = %v, want %q", key, body[key], want)
		}
	}
	if wants, _ := body["wants"].([]any); len(wants) != 1 || wants[0] != "cover" {
		t.Errorf("wants = %v, want [cover]", body["wants"])
	}

	// No want is the pre-want contract, everything, so nothing is named.
	if _, err := bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetRelease, Title: "Discovery",
	}); err != nil {
		t.Fatal(err)
	}
	if wants, ok := got.Load().(map[string]any)["wants"]; ok {
		t.Errorf("wants = %v on an unstamped request, want it omitted", wants)
	}
}

// scriptedBridge serves the capabilities document and answers every
// enrich call with body, for the tests about how an answer maps back.
func scriptedBridge(t *testing.T, caps string, body any) *HTTPBridge {
	t.Helper()
	return scriptedBridgeLogging(t, caps, body, nil)
}

func scriptedBridgeLogging(t *testing.T, caps string, body any, log *slog.Logger) *HTTPBridge {
	t.Helper()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/capabilities" {
			fmt.Fprint(w, caps)
			return
		}
		json.NewEncoder(w).Encode(body)
	}))
	t.Cleanup(srv.Close)
	bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "scripted", BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond, Log: log,
	})
	if err != nil {
		t.Fatal(err)
	}
	return bridge
}

// One refused image costs only itself: the rest of the answer lands, and
// the refusal is logged for whoever runs the service.
func TestHTTPBridgeKeepsTheRestOfAnAnswerPastABadImage(t *testing.T) {
	t.Parallel()
	good := map[string]string{"data": base64.StdEncoding.EncodeToString(testPNG(t)), "mediaType": "image/png"}
	var logged bytes.Buffer
	bridge := scriptedBridgeLogging(t, `{"name":"sleeves","capabilities":["cover","aux-art","lyrics","fields"]}`,
		map[string]any{
			"cover": good,
			"art": map[string]any{
				"back":    map[string]string{"data": "%not base64%"},
				"disc":    map[string]string{"data": base64.StdEncoding.EncodeToString([]byte("junk")), "mediaType": "image/jpeg"},
				"booklet": good,
			},
			"lyrics": map[string]any{"unsynced": "la la la"},
			"fields": map[string]string{"label": "Virgin"},
		}, slog.New(slog.NewTextHandler(&logged, nil)))

	cand, err := bridge.Enrich(context.Background(), enrich.Request{Type: enrich.TargetRelease, Title: "Discovery"})
	if err != nil || cand == nil {
		t.Fatalf("answer = %+v, %v; want what was usable", cand, err)
	}
	if cand.Cover == nil || cand.Lyrics == nil || cand.Fields["label"] != "Virgin" {
		t.Errorf("cover %v, lyrics %v, fields %v; want all three kept", cand.Cover != nil, cand.Lyrics != nil, cand.Fields)
	}
	if len(cand.Art) != 1 || cand.Art[model.ArtRoleBooklet] == nil {
		t.Errorf("art = %v, want the booklet alone", cand.Art)
	}
	for _, role := range []string{"back", "disc"} {
		if !strings.Contains(logged.String(), role) {
			t.Errorf("log = %q, want the refused %s named", logged.String(), role)
		}
	}
}

// The aux-art and artist-art walks read the role map alone, so a remote
// delivers those roles through `art`, and an artist's cover rides there too.
func TestHTTPBridgeCarriesArtRoles(t *testing.T) {
	t.Parallel()
	png := testPNG(t)
	img := map[string]string{"data": base64.StdEncoding.EncodeToString(png), "mediaType": "image/png"}
	bridge := scriptedBridge(t, `{"name":"sleeves","capabilities":["cover","aux-art","artist-art"]}`,
		map[string]any{"cover": img, "art": map[string]any{"back": img, "disc": img, "spine": img}})

	cand, err := bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Want: enrich.CapAuxArt, Title: "Discovery",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || len(cand.Art) != 2 || cand.Art[model.ArtRoleBack] == nil || cand.Art[model.ArtRoleDisc] == nil {
		t.Fatalf("art = %+v, want back and disc and no unknown role", cand)
	}
	if cand.Art[model.ArtRoleBack].Hash != art.Hash(png) {
		t.Error("a bridged role image is not content-addressed")
	}

	cand, err = bridge.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetArtist, Want: enrich.CapArtistArt, Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Art[model.ArtRoleFront] == nil {
		t.Fatalf("artist answer = %+v, want its cover in the front role", cand)
	}
}

// A group-front claim counts only on the release request that named the
// group's front; anywhere else it would end the walk with no picture.
func TestHTTPBridgeIgnoresAnUnaskedGroupFront(t *testing.T) {
	t.Parallel()
	bridge := scriptedBridge(t, `{"name":"claims","capabilities":["cover"]}`,
		map[string]any{"frontIsGroupFront": true})
	for _, req := range []enrich.Request{
		{Type: enrich.TargetReleaseGroup, Want: enrich.CapCover, Title: "Discovery", GroupFrontHash: "c0ffee"},
		{Type: enrich.TargetRelease, Want: enrich.CapCover, Title: "Discovery"},
	} {
		cand, err := bridge.Enrich(context.Background(), req)
		if err != nil || cand != nil {
			t.Errorf("%s answer = %+v (%v), want a clean miss", req.Type, cand, err)
		}
	}
}

// TestHTTPBridgeRefusesMarkupCovers pins the same door fetchImage
// guards on remote-chosen URLs: SVG must not ride inline base64 past it
// under any spelling of its type, and nor may bytes nothing recognizes.
func TestHTTPBridgeRefusesMarkupCovers(t *testing.T) {
	t.Parallel()
	svg := base64.StdEncoding.EncodeToString([]byte("<svg xmlns='http://www.w3.org/2000/svg'/>"))
	for _, cover := range []map[string]string{
		{"data": svg, "mediaType": "image/svg+xml"},
		{"data": svg, "mediaType": "image/svg+xml; charset=utf-8"},
		{"data": svg, "mediaType": "Image/SVG+XML"},
		{"data": svg},
		{"data": base64.StdEncoding.EncodeToString([]byte("not a picture")), "mediaType": "image/png"},
	} {
		bridge := scriptedBridge(t, `{"name":"marky","capabilities":["cover"]}`, map[string]any{"cover": cover})
		cand, err := bridge.Enrich(context.Background(), enrich.Request{Type: enrich.TargetReleaseGroup, Title: "Anything"})
		if err != nil || cand != nil {
			t.Errorf("cover typed %q = %+v, %v; want it refused and nothing else answered", cover["mediaType"], cand, err)
		}
	}
}

func TestHTTPBridgeCarriesTheBearerToken(t *testing.T) {
	t.Parallel()
	var gotAuth atomic.Value
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth.Store(r.Header.Get("Authorization"))
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"name":"authy","capabilities":["lyrics"]}`)
	}))
	defer srv.Close()
	if _, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "authy", BaseURL: srv.URL, Token: "s3cret",
		HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	}); err != nil {
		t.Fatal(err)
	}
	if got := gotAuth.Load(); got != "Bearer s3cret" {
		t.Errorf("Authorization = %v, want the bearer token", got)
	}
}

func TestHTTPBridgeValidatesAtStartup(t *testing.T) {
	t.Parallel()
	// Unreachable: the operator wired it, so silence is not an option.
	// The short deadline cuts the boot-race retry ladder off - the
	// ladder itself is exercised below.
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if _, err := NewHTTPBridge(ctx, HTTPBridgeConfig{
		Label: "down", BaseURL: "https://127.0.0.1:1",
		HTTPClient: &http.Client{Timeout: time.Second}, MinInterval: time.Nanosecond,
	}); err == nil {
		t.Error("an unreachable remote was accepted")
	}

	// A nameless remote cannot stamp provenance and is refused with the
	// reason, rather than being dropped later by namedEnrichProviders
	// with only a log line.
	nameless := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"name":"","capabilities":["cover"]}`)
	}))
	defer nameless.Close()
	if _, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "nameless", BaseURL: nameless.URL,
		HTTPClient: nameless.Client(), MinInterval: time.Nanosecond,
	}); err == nil {
		t.Error("a nameless remote was accepted")
	}

	// A remote advertising nothing this build understands constructs
	// with an empty capability set: that is version skew, and the
	// wiring skips it with a log line rather than refusing to start.
	futurist := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"name":"tomorrow","capabilities":["telepathy"]}`)
	}))
	defer futurist.Close()
	bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "tomorrow", BaseURL: futurist.URL,
		HTTPClient: futurist.Client(), MinInterval: time.Nanosecond,
	})
	if err != nil {
		t.Fatalf("a newer-contract remote failed to construct: %v", err)
	}
	if bridge.Capabilities() != 0 {
		t.Errorf("Capabilities() = %b, want none understood", bridge.Capabilities())
	}
}

// TestHTTPBridgeRetriesTheBootRace: the capabilities probe retries, so
// a provider container that answers on the second ask (compose started
// both at once) still connects instead of crash-looping the server.
func TestHTTPBridgeRetriesTheBootRace(t *testing.T) {
	t.Parallel()
	var asks atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if asks.Add(1) == 1 {
			// The first ask lands before the app inside is listening.
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"name":"latecomer","capabilities":["lyrics"]}`)
	}))
	defer srv.Close()
	bridge, err := NewHTTPBridge(context.Background(), HTTPBridgeConfig{
		Label: "late", BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	if bridge.Name() != "latecomer" || asks.Load() < 2 {
		t.Errorf("bridge = %q after %d asks, want the retried connect", bridge.Name(), asks.Load())
	}
}
