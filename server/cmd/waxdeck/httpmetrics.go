package main

import (
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/colespringer/waxdeck/server/internal/metrics"
)

// Request-level metrics: one counter and one latency histogram over the
// top-level handlers, partitioned by a route class named at each
// registration.
//
// The class is always a literal. Deriving it from the request path, or
// from the registered pattern set, would either put pids in a label (an
// unbounded series count, which in a process that runs for months is a
// memory leak) or add machinery that drifts as routes are added. Naming
// it at the registration is bounded by construction and reads where the
// route is declared.

// httpMetrics is the pair of families. A nil *httpMetrics instruments
// nothing, which is what a server with no /metrics endpoint gets: with
// no scraper, the series would only accumulate unread.
type httpMetrics struct {
	requests *metrics.CounterVec
	latency  *metrics.HistogramVec
}

func newHTTPMetrics(reg *metrics.Registry) *httpMetrics {
	labels := []string{"class", "method", "status"}
	return &httpMetrics{
		requests: reg.CounterVec("waxdeck_http_requests_total",
			"HTTP requests served, by route class, method, and response status.",
			labels),
		latency: reg.HistogramVec("waxdeck_http_request_duration_seconds",
			"HTTP request seconds, by route class, method, and response status. "+
				"The media-stream and download classes observe time to first byte rather than "+
				"total duration: those responses stay open for as long as someone is listening or "+
				"downloading, so timing them whole would put multi-hour observations in the same "+
				"buckets as JSON reads and make every percentile meaningless.",
			labels, metrics.DefBuckets()),
	}
}

// instrument wraps a handler whose response completes when the work
// does, so its duration is service time.
func (m *httpMetrics) instrument(class string, h http.HandlerFunc) http.Handler {
	return m.wrap(class, h, false)
}

// instrumentStream wraps a handler whose response body is a media
// transfer. It records time to first byte; the count and the status
// distribution stay exactly as useful either way.
func (m *httpMetrics) instrumentStream(class string, h http.HandlerFunc) http.Handler {
	return m.wrap(class, h, true)
}

func (m *httpMetrics) wrap(class string, h http.HandlerFunc, firstByteOnly bool) http.Handler {
	if m == nil {
		return h
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		cw := &countingWriter{ResponseWriter: w}
		// Deferred, so a panicking handler is still counted. Without it
		// the one class of failure an operator most wants on a dashboard
		// is the one class that never appears.
		returned := false
		defer func() {
			code := statusLabel(cw.status, returned)
			method := methodLabel(r.Method)
			m.requests.With(class, method, code).Inc()

			observed := time.Since(start)
			if firstByteOnly && !cw.firstByte.IsZero() {
				observed = cw.firstByte.Sub(start)
			}
			m.latency.With(class, method, code).Observe(observed.Seconds())
		}()
		h.ServeHTTP(cw, r)
		returned = true
	})
}

// knownMethods bounds the method label. net/http accepts any token as a
// request method, and the prefix-registered handlers take every one of
// them, so an unclamped r.Method is a label value the client chooses.
var knownMethods = map[string]bool{
	http.MethodGet: true, http.MethodHead: true, http.MethodPost: true,
	http.MethodPut: true, http.MethodPatch: true, http.MethodDelete: true,
	http.MethodOptions: true, http.MethodConnect: true, http.MethodTrace: true,
}

func methodLabel(method string) string {
	if knownMethods[method] {
		return method
	}
	return "other"
}

// statusLabel names what the client actually got. A handler that wrote
// nothing and returned normally answered 200, since that is what
// net/http sends for it; one that wrote nothing and did not return
// panicked, and net/http closes the connection with no response at all,
// so calling that 200 would hide the failure inside the healthy series.
func statusLabel(status int, returned bool) string {
	switch {
	case status != 0:
		return strconv.Itoa(status)
	case returned:
		return strconv.Itoa(http.StatusOK)
	default:
		return "panic"
	}
}

// countingWriter records the response status and the instant the first
// byte went out, and is otherwise transparent.
//
// Unwrap covers the callers that resolve capabilities properly:
// http.ResponseController (how httputil.ReverseProxy flushes audio as it
// arrives) and the WebSocket upgrade both follow it to the real writer.
// Flush is implemented anyway, and unconditionally, because not every
// caller does: the generated SSE writer type-asserts `w.(http.Flusher)`
// directly and silently degrades to a non-flushing io.Copy when the
// assertion fails, which buffers tool-task progress frames instead of
// delivering them per event. Claiming the capability costs nothing when
// the writer underneath lacks it, since the fallback those callers take
// does not flush either.
type countingWriter struct {
	http.ResponseWriter
	status    int
	firstByte time.Time
}

// Flush delegates through a ResponseController so it reaches the real
// writer whatever else wraps it, and does nothing when that writer
// cannot flush.
func (w *countingWriter) Flush() {
	_ = http.NewResponseController(w.ResponseWriter).Flush()
}

func (w *countingWriter) WriteHeader(status int) {
	w.mark(status)
	w.ResponseWriter.WriteHeader(status)
}

func (w *countingWriter) Write(b []byte) (int, error) {
	w.mark(http.StatusOK)
	return w.ResponseWriter.Write(b)
}

// ReadFrom keeps the fast path http.ServeContent and io.Copy reach for:
// net/http's own writer copies a file to the socket with sendfile, and
// a wrapper without ReadFrom silently drops every media byte back to a
// userspace buffer loop.
func (w *countingWriter) ReadFrom(r io.Reader) (int64, error) {
	w.mark(http.StatusOK)
	if rf, ok := w.ResponseWriter.(io.ReaderFrom); ok {
		return rf.ReadFrom(r)
	}
	return io.Copy(w.ResponseWriter, r)
}

func (w *countingWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func (w *countingWriter) mark(status int) {
	if w.status == 0 {
		w.status = status
		w.firstByte = time.Now()
	}
}
