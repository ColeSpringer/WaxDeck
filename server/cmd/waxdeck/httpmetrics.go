package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/colespringer/waxdeck/server/internal/metrics"
	"github.com/colespringer/waxdeck/server/internal/respwriter"
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
		cw := newCountingWriter(w)
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

// countingWriter records the status the answer started with and the
// instant it did, and is otherwise the shared writer, transparent: Flush,
// ReadFrom and Unwrap are respwriter's, which says why each matters.
type countingWriter struct {
	respwriter.Writer
	status    int
	firstByte time.Time
}

func newCountingWriter(w http.ResponseWriter) *countingWriter {
	cw := &countingWriter{}
	cw.Writer = respwriter.Writer{ResponseWriter: w, Before: cw.mark}
	return cw
}

func (w *countingWriter) mark(status int) {
	w.status = status
	w.firstByte = time.Now()
}
