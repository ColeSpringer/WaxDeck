package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/metrics"
)

func scrapeText(t *testing.T, reg *metrics.Registry) string {
	t.Helper()
	rec := httptest.NewRecorder()
	reg.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	return rec.Body.String()
}

func TestInstrumentCountsByClassMethodAndStatus(t *testing.T) {
	reg := metrics.NewRegistry()
	m := newHTTPMetrics(reg)

	ok := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("hi"))
	})
	missing := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})
	silent := m.instrument("web", func(w http.ResponseWriter, r *http.Request) {})

	for range 2 {
		ok.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))
	}
	missing.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/api/v1/y", nil))
	silent.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))

	text := scrapeText(t, reg)
	for _, want := range []string{
		`waxdeck_http_requests_total{class="api",method="GET",status="200"} 2`,
		`waxdeck_http_requests_total{class="api",method="POST",status="404"} 1`,
		// A handler that writes nothing still answered 200.
		`waxdeck_http_requests_total{class="web",method="GET",status="200"} 1`,
		`waxdeck_http_request_duration_seconds_count{class="api",method="GET",status="200"} 2`,
	} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in:\n%s", want, text)
		}
	}
}

// TestInstrumentBoundsTheMethodLabel pins the one label value a client
// can choose. net/http takes any token as a method, and the
// prefix-registered handlers accept every one of them, so an unclamped
// method label is unbounded series growth in a long-running process.
func TestInstrumentBoundsTheMethodLabel(t *testing.T) {
	reg := metrics.NewRegistry()
	m := newHTTPMetrics(reg)
	h := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {})

	for _, method := range []string{"WAXDECK", "SOMETHINGELSE", "AGAIN"} {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/x", nil)
		req.Method = method
		h.ServeHTTP(httptest.NewRecorder(), req)
	}
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodDelete, "/api/v1/x", nil))

	text := scrapeText(t, reg)
	if !strings.Contains(text, `waxdeck_http_requests_total{class="api",method="other",status="200"} 3`) {
		t.Errorf("unknown methods did not collapse to one series:\n%s", text)
	}
	if !strings.Contains(text, `waxdeck_http_requests_total{class="api",method="DELETE",status="200"} 1`) {
		t.Errorf("a known method was collapsed:\n%s", text)
	}
	if strings.Contains(text, "WAXDECK") {
		t.Errorf("a client-chosen method reached a label:\n%s", text)
	}
}

// TestInstrumentStreamRecordsTimeToFirstByte is the whole reason
// streaming routes are classed apart: a listening session's length must
// not land in the same buckets as a JSON read.
func TestInstrumentStreamRecordsTimeToFirstByte(t *testing.T) {
	reg := metrics.NewRegistry()
	m := newHTTPMetrics(reg)

	const hold = 120 * time.Millisecond
	stream := m.instrumentStream("media-stream", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK) // headers out immediately
		time.Sleep(hold)             // then the body stays open
		w.Write([]byte("audio"))
	})
	whole := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(hold)
		w.Write([]byte("json"))
	})
	stream.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/media/stream", nil))
	whole.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))

	text := scrapeText(t, reg)
	// 0.1s is a bucket bound: the stream's first byte is under it, the
	// duration-timed handler's whole response is not.
	if !strings.Contains(text, `waxdeck_http_request_duration_seconds_bucket{class="media-stream",method="GET",status="200",le="0.1"} 1`) {
		t.Errorf("stream observation was not time to first byte:\n%s", text)
	}
	if !strings.Contains(text, `waxdeck_http_request_duration_seconds_bucket{class="api",method="GET",status="200",le="0.1"} 0`) {
		t.Errorf("duration-timed observation landed too low:\n%s", text)
	}
}

// TestCountingWriterStaysTransparent pins the capabilities the wrapper
// must not swallow: the reverse proxy flushes audio through a
// ResponseController, the WebSocket upgrade hijacks through Unwrap, and
// http.ServeContent copies files through ReadFrom.
func TestCountingWriterStaysTransparent(t *testing.T) {
	reg := metrics.NewRegistry()
	m := newHTTPMetrics(reg)

	dir := t.TempDir()
	path := filepath.Join(dir, "body.bin")
	payload := strings.Repeat("wax", 4096)
	if err := os.WriteFile(path, []byte(payload), 0o644); err != nil {
		t.Fatal(err)
	}

	var sawFlusher, sawReadFrom, sawUnwrap, sawRawFlusher bool
	h := m.instrumentStream("media-stream", func(w http.ResponseWriter, r *http.Request) {
		_, sawUnwrap = w.(interface{ Unwrap() http.ResponseWriter })
		_, sawReadFrom = w.(io.ReaderFrom)
		// The generated SSE writer asserts this directly rather than
		// going through a ResponseController, and falls back to a
		// non-flushing io.Copy when it fails, which buffers tool-task
		// progress frames instead of delivering them per event.
		_, sawRawFlusher = w.(http.Flusher)
		f, err := os.Open(path)
		if err != nil {
			t.Error(err)
			return
		}
		defer f.Close()
		http.ServeContent(w, r, "body.bin", time.Unix(0, 0), f)
		// After the body, so the probe does not force an implicit header
		// write that ServeContent would then duplicate.
		if err := http.NewResponseController(w).Flush(); err == nil {
			sawFlusher = true
		}
	})

	// The client can finish reading before the server goroutine is done,
	// so the probes and the counters are read only after it returns.
	served := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer close(served)
		h.ServeHTTP(w, r)
	}))
	defer srv.Close()
	resp, err := http.Get(srv.URL + "/media/stream")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != payload {
		t.Fatalf("body = %d bytes, want %d", len(body), len(payload))
	}
	<-served
	if !sawUnwrap {
		t.Error("the wrapper does not unwrap, so a WebSocket upgrade cannot hijack through it")
	}
	if !sawReadFrom {
		t.Error("the wrapper drops ReadFrom, so file copies lose the sendfile path")
	}
	if !sawFlusher {
		t.Error("the wrapper hides Flush, so the stream proxy cannot push audio as it arrives")
	}
	if !sawRawFlusher {
		t.Error("the wrapper fails a bare http.Flusher assertion, so SSE frames stop flushing per event")
	}
	if !strings.Contains(scrapeText(t, reg),
		`waxdeck_http_requests_total{class="media-stream",method="GET",status="200"} 1`) {
		t.Error("the served range was not counted")
	}
}

// TestInstrumentCountsAPanickingHandler pins that the one class of
// failure most worth a dashboard is not the one class that never
// reaches it. A panic before any write gets its own status label rather
// than being filed as 200, because net/http closes the connection
// without sending a response at all.
func TestInstrumentCountsAPanickingHandler(t *testing.T) {
	reg := metrics.NewRegistry()
	m := newHTTPMetrics(reg)

	early := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {
		panic("nothing written yet")
	})
	late := m.instrument("api", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		panic("mid-body")
	})
	call := func(h http.Handler) {
		defer func() { _ = recover() }()
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))
	}
	call(early)
	call(late)

	text := scrapeText(t, reg)
	if !strings.Contains(text, `waxdeck_http_requests_total{class="api",method="GET",status="panic"} 1`) {
		t.Errorf("a handler that panicked before writing was not counted:\n%s", text)
	}
	// One that panicked after its header went out did answer 200, and
	// the client saw it, so that is what it is counted as.
	if !strings.Contains(text, `waxdeck_http_requests_total{class="api",method="GET",status="200"} 1`) {
		t.Errorf("a handler that panicked after writing lost its real status:\n%s", text)
	}
}

// A nil *httpMetrics is what a server with no metrics token builds, and
// it must hand back the handler untouched rather than panicking.
func TestNilHTTPMetricsInstrumentsNothing(t *testing.T) {
	var m *httpMetrics
	called := false
	h := m.instrument("api", func(w http.ResponseWriter, r *http.Request) { called = true })
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/x", nil))
	if !called {
		t.Fatal("the wrapped handler did not run")
	}
	h = m.instrumentStream("media-stream", func(w http.ResponseWriter, r *http.Request) {})
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/media/stream", nil))
}
