package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
)

// countingHandler stands in for the mux, so a test can say not just what
// came back but whether the request ever reached the router.
type countingHandler struct {
	calls int
}

func (h *countingHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	h.calls++
	w.WriteHeader(http.StatusOK)
}

func TestWithCORSDisabledIsTransparent(t *testing.T) {
	next := &countingHandler{}
	// The identity check is the assertion: an unconfigured server must
	// serve exactly what it served before this wrapper existed, and a
	// wrapper that merely adds no headers is still a wrapper.
	if got := withCORS(nil, next); got != http.Handler(next) {
		t.Fatalf("withCORS(nil) wrapped the handler; want it returned untouched")
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/rest/ping", nil)
	req.Header.Set("Origin", "http://localhost:9180")
	withCORS(nil, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Vary"); got != "" {
		t.Errorf("Vary = %q; want empty when CORS is off", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q; want empty when CORS is off", got)
	}
}

func TestWithCORSAllowsNamedOrigin(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/rest/ping", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9180" {
		t.Errorf("Access-Control-Allow-Origin = %q; want the request's origin", got)
	}
	if got := rec.Header().Get("Vary"); got != "Origin" {
		t.Errorf("Vary = %q; want Origin", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Credentials"); got != "" {
		t.Errorf("Access-Control-Allow-Credentials = %q; want it never set", got)
	}
	if next.calls != 1 {
		t.Errorf("handler calls = %d; want the request routed", next.calls)
	}
}

func TestWithCORSDeniesUnnamedOrigin(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/rest/ping", nil)
	req.Header.Set("Origin", "http://evil.example")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q; want empty for an origin not named", got)
	}
	// Still varies: the answer would have differed for another origin,
	// and a cache must not reuse this one for it.
	if got := rec.Header().Get("Vary"); got != "Origin" {
		t.Errorf("Vary = %q; want Origin even when the origin is refused", got)
	}
	// Routed anyway. The browser is what refuses the response; the server
	// answering 403 here would break every non-browser client that sends
	// an Origin header.
	if next.calls != 1 {
		t.Errorf("handler calls = %d; want the request still routed", next.calls)
	}
}

func TestWithCORSAnswersPreflightBeforeTheMux(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/rest/stream", nil)
	req.Header.Set("Origin", "http://localhost:9180")
	req.Header.Set("Access-Control-Request-Method", "GET")
	req.Header.Set("Access-Control-Request-Headers", "authorization, x-feishin-quirk")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("status = %d; want %d", rec.Code, http.StatusNoContent)
	}
	if next.calls != 0 {
		t.Errorf("handler calls = %d; want the preflight answered before the mux", next.calls)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9180" {
		t.Errorf("Access-Control-Allow-Origin = %q; want the request's origin", got)
	}
	// Echoed verbatim, the unknown header included: a fixed allow-list
	// would refuse whatever a client sends that nobody enumerated, and
	// this is the assertion that pins the echo rather than a list.
	if got := rec.Header().Get("Access-Control-Allow-Headers"); got != "authorization, x-feishin-quirk" {
		t.Errorf("Access-Control-Allow-Headers = %q; want the request's list echoed", got)
	}
	if got := rec.Header().Get("Access-Control-Max-Age"); got != corsMaxAge {
		t.Errorf("Access-Control-Max-Age = %q; want %q", got, corsMaxAge)
	}
	if got := rec.Header().Values("Vary"); len(got) != 2 {
		t.Errorf("Vary = %v; want both Origin and Access-Control-Request-Headers", got)
	}
}

func TestWithCORSPreflightFromUnnamedOriginCarriesNoGrant(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/rest/stream", nil)
	req.Header.Set("Origin", "http://evil.example")
	req.Header.Set("Access-Control-Request-Method", "GET")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin = %q; want empty", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); got != "" {
		t.Errorf("Access-Control-Allow-Methods = %q; want empty", got)
	}
	if next.calls != 0 {
		t.Errorf("handler calls = %d; want the preflight answered here", next.calls)
	}
}

// A plain OPTIONS is not a preflight, and the mux is what knows whether
// the route takes it.
func TestWithCORSRoutesOptionsThatIsNotAPreflight(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/rest/ping", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if next.calls != 1 {
		t.Errorf("handler calls = %d; want a bare OPTIONS routed", next.calls)
	}
}

// Artwork and the stream endpoints set a Vary of their own, and Set
// replaces. Without the write-time fixup a shared cache could hand one
// origin's response - Access-Control-Allow-Origin included - to another.
func TestWithCORSKeepsVaryAHandlerOverwrote(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Vary", "Accept")
		w.WriteHeader(http.StatusOK)
	})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/media/art", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	var sawOrigin, sawAccept bool
	for _, v := range rec.Header().Values("Vary") {
		switch v {
		case "Origin":
			sawOrigin = true
		case "Accept":
			sawAccept = true
		}
	}
	if !sawOrigin {
		t.Errorf("Vary = %v; want Origin to survive the handler's Set", rec.Header().Values("Vary"))
	}
	if !sawAccept {
		t.Errorf("Vary = %v; want the handler's own value kept too", rec.Header().Values("Vary"))
	}
}

// Flush commits headers like a write does: a handler that replaced Vary
// and then flushed - never having called Write or WriteHeader - must not
// publish a grant a shared cache can key without Origin.
func TestWithCORSKeepsVaryAcrossFlush(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Vary", "Accept")
		w.(http.Flusher).Flush()
	})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/media/art", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	var sawOrigin bool
	for _, v := range rec.Header().Values("Vary") {
		if v == "Origin" {
			sawOrigin = true
		}
	}
	if !sawOrigin {
		t.Errorf("Vary = %v; want Origin to survive a flush-first handler", rec.Header().Values("Vary"))
	}
}

// An answer its handler never started still goes out, as the 200 net/http
// sends once the handler returns, and with the grant on it, so it keeps
// Vary: Origin too. A copy that brought nothing is one way there.
func TestWithCORSKeepsVaryOnAnAnswerNothingStarted(t *testing.T) {
	for name, write := range map[string]func(http.ResponseWriter){
		"nothing written": func(http.ResponseWriter) {},
		"an empty copy":   func(w http.ResponseWriter) { io.Copy(w, struct{ io.Reader }{strings.NewReader("")}) },
	} {
		next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Vary", "Accept-Encoding")
			write(w)
		})
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/media/art", nil)
		req.Header.Set("Origin", "http://localhost:9180")

		withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

		if got := rec.Header().Values("Vary"); !slices.Contains(got, "Origin") {
			t.Errorf("%s: Vary = %v; want Origin kept beside the handler's", name, got)
		}
	}
}

// Not duplicated when the handler already varies on Origin itself.
func TestWithCORSDoesNotDuplicateVaryOrigin(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Vary", "origin")
		w.WriteHeader(http.StatusOK)
	})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/media/art", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if got := rec.Header().Values("Vary"); len(got) != 1 {
		t.Errorf("Vary = %v; want the handler's single value, case-insensitively matched", got)
	}
}

// The writer a handler is given under CORS is still a streaming one. The
// metrics writer sits inside it and resolves io.ReaderFrom against it, so
// one that lacked ReadFrom would cost http.ServeContent its sendfile path
// for every media byte; Unwrap is how a ResponseController and the
// WebSocket upgrade reach the real writer.
func TestCORSKeepsAStreamingWriter(t *testing.T) {
	var readsFrom, flushes, unwraps bool
	h := withCORS([]string{"https://app.example.com"}, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, readsFrom = w.(io.ReaderFrom)
		_, flushes = w.(http.Flusher)
		_, unwraps = w.(interface{ Unwrap() http.ResponseWriter })
	}))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))
	if !readsFrom || !flushes || !unwraps {
		t.Errorf("the writer under CORS: ReadFrom %v, Flusher %v, Unwrap %v; want all three", readsFrom, flushes, unwraps)
	}
}

func TestNormalizeOrigins(t *testing.T) {
	got, err := normalizeOrigins([]string{
		"  http://localhost:9180/ ",
		"https://app.example.com",
		"",
		"   ",
	})
	if err != nil {
		t.Fatalf("normalizeOrigins() error = %v; want none", err)
	}
	want := []string{"http://localhost:9180", "https://app.example.com"}

	if len(got) != len(want) {
		t.Fatalf("normalizeOrigins() = %v; want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("normalizeOrigins()[%d] = %q; want %q", i, got[i], want[i])
		}
	}
}

// The point of validating at all: each of these is accepted-looking and
// matches nothing a browser sends, so taking them silently would be the
// invisible failure the function exists to prevent. The server refuses
// to start instead, the way an unparseable trusted-proxy list does.
func TestNormalizeOriginsRefusesWhatNoBrowserSends(t *testing.T) {
	for _, bad := range []string{
		"music.example.com",              // no scheme
		"https://app.example.com/rest",   // carries a path
		"HTTPS://App.Example.com",        // not lowercase
		"ftp://app.example.com",          // not an http scheme
		"https://",                       // no host
		"https://app.example.com?a=b",    // query
		"https://user@app.example.com",   // userinfo
		"https://app.example.com#anchor", // fragment
	} {
		if _, err := normalizeOrigins([]string{bad}); err == nil {
			t.Errorf("normalizeOrigins(%q) accepted it; want an error", bad)
		}
	}
}

// A media client fetching audio has to be able to read what it got.
func TestWithCORSExposesTheRangeHeaders(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/media/stream", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	got := rec.Header().Get("Access-Control-Expose-Headers")
	for _, want := range []string{"Accept-Ranges", "Content-Range"} {
		if !strings.Contains(got, want) {
			t.Errorf("Access-Control-Expose-Headers = %q; want it to include %q", got, want)
		}
	}
}

func TestWithCORSPreflightAllowsHead(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/media/stream", nil)
	req.Header.Set("Origin", "http://localhost:9180")
	req.Header.Set("Access-Control-Request-Method", "HEAD")

	withCORS([]string{"http://localhost:9180"}, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "HEAD") {
		t.Errorf("Access-Control-Allow-Methods = %q; want HEAD listed", got)
	}
}

// The reason normalizing is worth doing at all: a trailing slash in an
// env file is the near-miss that would otherwise match nothing.
func TestWithCORSMatchesOriginConfiguredWithTrailingSlash(t *testing.T) {
	next := &countingHandler{}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/rest/ping", nil)
	req.Header.Set("Origin", "http://localhost:9180")

	origins, err := normalizeOrigins([]string{"http://localhost:9180/"})
	if err != nil {
		t.Fatalf("normalizeOrigins() error = %v; want the slash tolerated", err)
	}
	withCORS(origins, next).ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9180" {
		t.Errorf("Access-Control-Allow-Origin = %q; want the slash tolerated", got)
	}
}
