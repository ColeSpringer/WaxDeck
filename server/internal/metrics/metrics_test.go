package metrics

import (
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func scrape(t *testing.T, r *Registry) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	r.Handler().ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	return rec
}

func mustPanic(t *testing.T, fn func()) {
	t.Helper()
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic, got none")
		}
	}()
	fn()
}

// buildGolden populates a registry with one collector of each type, using
// only exactly representable values so the exposition is byte-stable.
func buildGolden(reverse bool) *Registry {
	r := NewRegistry()
	fill := []func(){
		func() { r.Counter("wax_tracks_scanned_total", "Tracks scanned.").Add(3) },
		func() {
			cv := r.CounterVec("wax_http_requests_total", "HTTP requests handled.", []string{"method", "code"})
			cv.With("POST", "200").Inc()
			cv.With("GET", "404").Inc()
			cv.With("GET", "200").Add(2)
		},
		func() { r.Gauge("wax_queue_depth", "Items waiting in the work queue.").Set(7.5) },
		func() {
			gv := r.GaugeVec("wax_worker_busy", "Busy workers per pool.", []string{"pool"})
			gv.With("scan").Set(2)
		},
		func() {
			r.GaugeFunc("wax_uptime_ratio", "Fraction of time the server was up.",
				func() float64 { return 0.25 })
		},
		func() {
			h := r.Histogram("wax_req_seconds", "Request latency in seconds.", []float64{0.1, 0.5, 1})
			h.Observe(0.0625)
			h.Observe(0.25)
			h.Observe(0.75)
			h.Observe(3)
		},
		func() {
			hv := r.HistogramVec("wax_route_seconds", "Request latency per route.",
				[]string{"route"}, []float64{0.1, 0.5})
			hv.With("api").Observe(0.0625)
			hv.With("api").Observe(0.75)
			hv.With("web").Observe(0.25)
		},
	}
	if reverse {
		for i := len(fill) - 1; i >= 0; i-- {
			fill[i]()
		}
	} else {
		for _, f := range fill {
			f()
		}
	}
	return r
}

const golden = `# HELP wax_http_requests_total HTTP requests handled.
# TYPE wax_http_requests_total counter
wax_http_requests_total{method="GET",code="200"} 2
wax_http_requests_total{method="GET",code="404"} 1
wax_http_requests_total{method="POST",code="200"} 1
# HELP wax_queue_depth Items waiting in the work queue.
# TYPE wax_queue_depth gauge
wax_queue_depth 7.5
# HELP wax_req_seconds Request latency in seconds.
# TYPE wax_req_seconds histogram
wax_req_seconds_bucket{le="0.1"} 1
wax_req_seconds_bucket{le="0.5"} 2
wax_req_seconds_bucket{le="1"} 3
wax_req_seconds_bucket{le="+Inf"} 4
wax_req_seconds_sum 4.0625
wax_req_seconds_count 4
# HELP wax_route_seconds Request latency per route.
# TYPE wax_route_seconds histogram
wax_route_seconds_bucket{route="api",le="0.1"} 1
wax_route_seconds_bucket{route="api",le="0.5"} 1
wax_route_seconds_bucket{route="api",le="+Inf"} 2
wax_route_seconds_sum{route="api"} 0.8125
wax_route_seconds_count{route="api"} 2
wax_route_seconds_bucket{route="web",le="0.1"} 0
wax_route_seconds_bucket{route="web",le="0.5"} 1
wax_route_seconds_bucket{route="web",le="+Inf"} 1
wax_route_seconds_sum{route="web"} 0.25
wax_route_seconds_count{route="web"} 1
# HELP wax_tracks_scanned_total Tracks scanned.
# TYPE wax_tracks_scanned_total counter
wax_tracks_scanned_total 3
# HELP wax_uptime_ratio Fraction of time the server was up.
# TYPE wax_uptime_ratio gauge
wax_uptime_ratio 0.25
# HELP wax_worker_busy Busy workers per pool.
# TYPE wax_worker_busy gauge
wax_worker_busy{pool="scan"} 2
`

func TestGoldenExposition(t *testing.T) {
	got := scrape(t, buildGolden(false)).Body.String()
	if got != golden {
		t.Errorf("exposition mismatch\ngot:\n%s\nwant:\n%s", got, golden)
	}
}

func TestDeterministicOutput(t *testing.T) {
	a := buildGolden(false)
	b := buildGolden(true) // same collectors, reversed registration order
	first := scrape(t, a).Body.String()
	if second := scrape(t, a).Body.String(); second != first {
		t.Errorf("same registry scraped twice differs\nfirst:\n%s\nsecond:\n%s", first, second)
	}
	if other := scrape(t, b).Body.String(); other != first {
		t.Errorf("registration order changed the output\nforward:\n%s\nreverse:\n%s", first, other)
	}
}

func TestHistogramInvariants(t *testing.T) {
	r := NewRegistry()
	h := r.Histogram("lat_seconds", "", DefBuckets())
	obs := []float64{0.001, 0.003, 0.02, 0.02, 0.3, 4, 9.5, 100}
	var wantSum float64
	for _, v := range obs {
		h.Observe(v)
		wantSum += v
	}

	upper, cum, count, sum := h.snapshot()
	if count != uint64(len(obs)) {
		t.Errorf("count = %d, want %d", count, len(obs))
	}
	if sum != wantSum {
		t.Errorf("sum = %v, want %v", sum, wantSum)
	}
	if len(upper) != len(DefBuckets()) {
		t.Fatalf("got %d finite buckets, want %d", len(upper), len(DefBuckets()))
	}
	var prev uint64
	for i, c := range cum {
		if c < prev {
			t.Errorf("bucket le=%v count %d < previous %d: not cumulative", upper[i], c, prev)
		}
		// Recount from scratch to pin the le (<=) semantics.
		var want uint64
		for _, v := range obs {
			if v <= upper[i] {
				want++
			}
		}
		if c != want {
			t.Errorf("bucket le=%v = %d, want %d", upper[i], c, want)
		}
		prev = c
	}
	if last := cum[len(cum)-1]; last > count {
		t.Errorf("largest finite bucket %d exceeds count %d", last, count)
	}

	// The +Inf bucket line must equal the _count line in the exposition.
	body := scrape(t, r).Body.String()
	infLine := `lat_seconds_bucket{le="+Inf"} ` + strconv.Itoa(len(obs))
	countLine := "lat_seconds_count " + strconv.Itoa(len(obs))
	for _, want := range []string{infLine, countLine} {
		if !strings.Contains(body, want+"\n") {
			t.Errorf("exposition missing %q:\n%s", want, body)
		}
	}
}

func TestLabelEscaping(t *testing.T) {
	r := NewRegistry()
	r.GaugeVec("esc", "Line one.\nLine \\two.", []string{"v"}).With("a\\b\"c\nd").Set(1)
	body := scrape(t, r).Body.String()
	want := `# HELP esc Line one.\nLine \\two.
# TYPE esc gauge
esc{v="a\\b\"c\nd"} 1
`
	if body != want {
		t.Errorf("escaping mismatch\ngot:\n%s\nwant:\n%s", body, want)
	}
}

func TestConcurrentCounter(t *testing.T) {
	const workers, perWorker = 64, 1000
	r := NewRegistry()
	c := r.Counter("c_total", "")
	cv := r.CounterVec("cv_total", "", []string{"w"})
	var wg sync.WaitGroup
	for range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range perWorker {
				c.Inc()
				cv.With("x").Inc() // resolve the child concurrently too
			}
		}()
	}
	wg.Wait()
	const want = workers * perWorker
	if got := c.value(); got != want {
		t.Errorf("counter = %v, want %d", got, want)
	}
	if got := cv.With("x").value(); got != want {
		t.Errorf("vec child = %v, want %d", got, want)
	}
}

func TestConcurrentGauge(t *testing.T) {
	const workers, perWorker = 32, 500
	r := NewRegistry()
	g := r.Gauge("g", "")
	var wg sync.WaitGroup
	for i := range workers {
		wg.Add(1)
		go func(up bool) {
			defer wg.Done()
			for range perWorker {
				if up {
					g.Inc()
				} else {
					g.Dec()
				}
			}
		}(i%2 == 0)
	}
	wg.Wait()
	if got := g.value(); got != 0 {
		t.Errorf("gauge = %v, want 0 after balanced Inc/Dec", got)
	}
}

func TestCollectorIdentity(t *testing.T) {
	r := NewRegistry()
	if r.Counter("c_total", "help") != r.Counter("c_total", "other help") {
		t.Error("Counter with same name returned a different collector")
	}
	if r.Gauge("g", "") != r.Gauge("g", "") {
		t.Error("Gauge with same name returned a different collector")
	}
	if r.Histogram("h", "", nil) != r.Histogram("h", "", []float64{1, 2}) {
		t.Error("Histogram with same name returned a different collector")
	}
	cv := r.CounterVec("cv_total", "", []string{"a", "b"})
	if cv != r.CounterVec("cv_total", "", []string{"a", "b"}) {
		t.Error("CounterVec with same name and labels returned a different vec")
	}
	if cv.With("1", "2") != cv.With("1", "2") {
		t.Error("CounterVec.With with same values returned a different child")
	}
	if cv.With("1", "2") == cv.With("1", "3") {
		t.Error("CounterVec.With with different values returned the same child")
	}
	hv := r.HistogramVec("hv_seconds", "", []string{"a"}, []float64{1, 2})
	if hv != r.HistogramVec("hv_seconds", "", []string{"a"}, nil) {
		t.Error("HistogramVec with same name and labels returned a different vec")
	}
	if hv.With("x") != hv.With("x") {
		t.Error("HistogramVec.With with same values returned a different child")
	}
	// Every child shares the family's bounds, which is what makes the
	// family aggregatable across label values.
	if a, b := hv.With("x"), hv.With("y"); a == b || len(a.upper) != len(b.upper) {
		t.Error("HistogramVec children do not share one bucket set")
	}
}

func TestRegistrationPanics(t *testing.T) {
	cases := []struct {
		name string
		fn   func(r *Registry)
	}{
		{"counter then gauge", func(r *Registry) {
			r.Counter("m", "")
			r.Gauge("m", "")
		}},
		{"counter then counter vec", func(r *Registry) {
			r.Counter("m", "")
			r.CounterVec("m", "", []string{"a"})
		}},
		{"histogram then counter", func(r *Registry) {
			r.Histogram("m", "", nil)
			r.Counter("m", "")
		}},
		{"gauge vec then gauge", func(r *Registry) {
			r.GaugeVec("m", "", []string{"a"})
			r.Gauge("m", "")
		}},
		{"vec label mismatch", func(r *Registry) {
			r.CounterVec("m", "", []string{"a"})
			r.CounterVec("m", "", []string{"b"})
		}},
		{"histogram vec then histogram", func(r *Registry) {
			r.HistogramVec("m", "", []string{"a"}, nil)
			r.Histogram("m", "", nil)
		}},
		{"histogram vec label mismatch", func(r *Registry) {
			r.HistogramVec("m", "", []string{"a"}, nil)
			r.HistogramVec("m", "", []string{"b"}, nil)
		}},
		{"unsorted histogram vec buckets", func(r *Registry) {
			r.HistogramVec("m", "", []string{"a"}, []float64{2, 1})
		}},
		// The exposition appends le to the family's labels, so a family
		// carrying one of its own emits two le keys per bucket line.
		{"histogram vec claims the le label", func(r *Registry) {
			r.HistogramVec("m", "", []string{"le"}, nil)
		}},
		{"duplicate gauge func", func(r *Registry) {
			r.GaugeFunc("m", "", func() float64 { return 0 })
			r.GaugeFunc("m", "", func() float64 { return 0 })
		}},
		{"gauge then gauge func", func(r *Registry) {
			r.Gauge("m", "")
			r.GaugeFunc("m", "", func() float64 { return 0 })
		}},
		{"invalid metric name", func(r *Registry) { r.Counter("0bad", "") }},
		{"metric name with space", func(r *Registry) { r.Gauge("bad name", "") }},
		{"invalid label name", func(r *Registry) { r.CounterVec("m", "", []string{"0bad"}) }},
		{"colon in label name", func(r *Registry) { r.GaugeVec("m", "", []string{"a:b"}) }},
		{"duplicate label name", func(r *Registry) { r.CounterVec("m", "", []string{"a", "a"}) }},
		{"with arity mismatch", func(r *Registry) {
			r.CounterVec("m", "", []string{"a", "b"}).With("only")
		}},
		{"negative counter add", func(r *Registry) { r.Counter("m", "").Add(-1) }},
		{"unsorted histogram buckets", func(r *Registry) { r.Histogram("m", "", []float64{2, 1}) }},
		{"nil gauge func", func(r *Registry) { r.GaugeFunc("m", "", nil) }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := NewRegistry()
			mustPanic(t, func() { tc.fn(r) })
		})
	}
}

func TestHandlerContentType(t *testing.T) {
	rec := scrape(t, buildGolden(false))
	if rec.Code != 200 {
		t.Errorf("status = %d, want 200", rec.Code)
	}
	const want = "text/plain; version=0.0.4; charset=utf-8"
	if got := rec.Header().Get("Content-Type"); got != want {
		t.Errorf("Content-Type = %q, want %q", got, want)
	}
	if cl := rec.Header().Get("Content-Length"); cl != strconv.Itoa(rec.Body.Len()) {
		t.Errorf("Content-Length = %q, want %d", cl, rec.Body.Len())
	}
}

func TestGoRuntime(t *testing.T) {
	r := NewRegistry()
	r.GoRuntime()
	body := scrape(t, r).Body.String()
	for _, want := range []string{
		"# TYPE go_goroutines gauge\n",
		"# TYPE go_memstats_alloc_bytes gauge\n",
		"# TYPE go_memstats_heap_inuse_bytes gauge\n",
		"# TYPE go_memstats_sys_bytes gauge\n",
		"# TYPE go_gc_cycles_total counter\n",
		"# TYPE process_start_time_seconds gauge\n",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("exposition missing %q:\n%s", want, body)
		}
	}
	var start float64
	for line := range strings.Lines(body) {
		if v, ok := strings.CutPrefix(line, "process_start_time_seconds "); ok {
			f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
			if err != nil {
				t.Fatalf("bad process_start_time_seconds value %q: %v", v, err)
			}
			start = f
		}
	}
	now := float64(time.Now().UnixNano()) / 1e9
	if start <= 0 || start > now {
		t.Errorf("process_start_time_seconds = %v, want in (0, %v]", start, now)
	}
}

func TestDurationSince(t *testing.T) {
	r := NewRegistry()
	h := r.Histogram("d_seconds", "", DefBuckets())
	DurationSince(h, time.Now().Add(-50*time.Millisecond))
	_, _, count, sum := h.snapshot()
	if count != 1 {
		t.Fatalf("count = %d, want 1", count)
	}
	if sum < 0.05 || sum > 10 {
		t.Errorf("sum = %v, want roughly 0.05s", sum)
	}
}

func TestDefBuckets(t *testing.T) {
	b := DefBuckets()
	for i := 1; i < len(b); i++ {
		if b[i] <= b[i-1] {
			t.Fatalf("DefBuckets not strictly increasing at %d: %v", i, b)
		}
	}
	b[0] = 99 // callers own the slice; mutation must not leak
	if DefBuckets()[0] == 99 {
		t.Error("DefBuckets returned a shared slice")
	}
}
