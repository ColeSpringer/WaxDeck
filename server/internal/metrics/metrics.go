// Package metrics is a small, dependency-free metrics registry that speaks
// the Prometheus text exposition format (version 0.0.4).
//
// The WaxDeck server is stdlib-only by posture, and the text format is tiny,
// so this is hand-rolled rather than pulling in prometheus/client_golang and
// its dependency tree. Scope is deliberately narrow: in-process collectors
// (counters, gauges, histograms, and scrape-time gauge functions) plus an
// http.Handler that renders them. There is no push support, no protobuf
// exposition, and no metric expiry; callers hold a *Registry and mount
// Handler wherever they route HTTP.
//
// The package spawns no goroutines. All collectors are safe for concurrent
// use via atomics and mutexes.
package metrics

import (
	"fmt"
	"regexp"
	"slices"
	"sync"
	"sync/atomic"
)

// metricType is the exposition TYPE of a metric family.
type metricType uint8

const (
	typeCounter metricType = iota
	typeGauge
	typeHistogram
)

func (t metricType) String() string {
	switch t {
	case typeCounter:
		return "counter"
	case typeGauge:
		return "gauge"
	case typeHistogram:
		return "histogram"
	}
	return "untyped"
}

// family is one registered metric family: a name, help text, a type, and
// exactly one of the collector fields.
type family struct {
	name string
	help string
	typ  metricType

	counter *Counter
	gauge   *Gauge
	hist    *Histogram
	fn      func() float64
	cvec    *CounterVec
	gvec    *GaugeVec
	hvec    *HistogramVec
}

// Registry holds metric families and renders them in the Prometheus text
// format. The zero value is not usable; call NewRegistry.
type Registry struct {
	mu       sync.Mutex
	families map[string]*family

	// scrapeSeq increments once per exposition pass. Scrape-time samplers
	// (see memSampler) compare against it to cache expensive reads for the
	// duration of a single scrape.
	scrapeSeq atomic.Uint64
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{families: make(map[string]*family)}
}

// Counter returns the monotonic counter registered under name, creating it on
// first use. Repeated calls with the same name return the same *Counter.
// It panics if name is invalid or already registered as a different
// collector type (a programmer error).
func (r *Registry) Counter(name, help string) *Counter {
	mustMetricName(name)
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.counter == nil {
			panicConflict(name)
		}
		return f.counter
	}
	c := new(Counter)
	r.families[name] = &family{name: name, help: help, typ: typeCounter, counter: c}
	return c
}

// CounterVec returns the labeled counter family registered under name,
// creating it on first use. Repeated calls with the same name and the same
// label names return the same *CounterVec; anything else panics.
func (r *Registry) CounterVec(name, help string, labels []string) *CounterVec {
	mustMetricName(name)
	mustLabelNames(labels)
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.cvec == nil || !slices.Equal(f.cvec.v.labels, labels) {
			panicConflict(name)
		}
		return f.cvec
	}
	cv := &CounterVec{v: newVec(labels, func() *Counter { return new(Counter) })}
	r.families[name] = &family{name: name, help: help, typ: typeCounter, cvec: cv}
	return cv
}

// Gauge returns the gauge registered under name, creating it on first use.
// Repeated calls with the same name return the same *Gauge; a name collision
// with a different collector type panics.
func (r *Registry) Gauge(name, help string) *Gauge {
	mustMetricName(name)
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.gauge == nil {
			panicConflict(name)
		}
		return f.gauge
	}
	g := new(Gauge)
	r.families[name] = &family{name: name, help: help, typ: typeGauge, gauge: g}
	return g
}

// GaugeVec returns the labeled gauge family registered under name, creating
// it on first use. Repeated calls with the same name and the same label names
// return the same *GaugeVec; anything else panics.
func (r *Registry) GaugeVec(name, help string, labels []string) *GaugeVec {
	mustMetricName(name)
	mustLabelNames(labels)
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.gvec == nil || !slices.Equal(f.gvec.v.labels, labels) {
			panicConflict(name)
		}
		return f.gvec
	}
	gv := &GaugeVec{v: newVec(labels, func() *Gauge { return new(Gauge) })}
	r.families[name] = &family{name: name, help: help, typ: typeGauge, gvec: gv}
	return gv
}

// GaugeFunc registers a gauge whose value is sampled by calling fn at scrape
// time. fn must be safe for concurrent use and must not block. Unlike the
// other constructors there is nothing to hand back, so re-registering the
// same name panics.
func (r *Registry) GaugeFunc(name, help string, fn func() float64) {
	r.registerFunc(name, help, typeGauge, fn)
}

// registerFunc is the shared implementation behind GaugeFunc and the
// counter-typed runtime metrics registered by GoRuntime.
func (r *Registry) registerFunc(name, help string, typ metricType, fn func() float64) {
	mustMetricName(name)
	if fn == nil {
		panic(fmt.Sprintf("metrics: nil sample func for %q", name))
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.families[name]; ok {
		panicConflict(name)
	}
	r.families[name] = &family{name: name, help: help, typ: typ, fn: fn}
}

// Histogram returns the histogram registered under name, creating it on
// first use with the given bucket upper bounds. A nil or empty buckets slice
// means DefBuckets. Bounds must be strictly increasing; a trailing +Inf is
// stripped (the +Inf bucket is always implicit). Repeated calls with the same
// name return the same *Histogram and ignore buckets; a name collision with a
// different collector type panics.
func (r *Registry) Histogram(name, help string, buckets []float64) *Histogram {
	mustMetricName(name)
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.hist == nil {
			panicConflict(name)
		}
		return f.hist
	}
	h := newHistogram(name, buckets)
	r.families[name] = &family{name: name, help: help, typ: typeHistogram, hist: h}
	return h
}

// HistogramVec returns the labeled histogram family registered under
// name, creating it on first use. Every child shares one bucket set,
// which is what makes the family aggregatable across label values; a
// nil or empty buckets slice means DefBuckets. Repeated calls with the
// same name and the same label names return the same *HistogramVec and
// ignore buckets; anything else panics.
func (r *Registry) HistogramVec(name, help string, labels []string, buckets []float64) *HistogramVec {
	mustMetricName(name)
	mustLabelNames(labels)
	// le is the bucket bound's own label, and the exposition appends it
	// to these. A family carrying one would emit two le keys on every
	// bucket line, which no scraper can parse. The check is here rather
	// than in mustLabelNames because le is reserved for histograms
	// alone: on a counter or gauge family it is merely an odd name.
	for _, l := range labels {
		if l == "le" {
			panic(fmt.Sprintf("metrics: %q reserves the le label for bucket bounds", name))
		}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if f, ok := r.families[name]; ok {
		if f.hvec == nil || !slices.Equal(f.hvec.v.labels, labels) {
			panicConflict(name)
		}
		return f.hvec
	}
	// Validating the bounds here rather than inside the child
	// constructor means a bad bucket list panics at registration, where
	// the mistake is, instead of on whichever request first observes.
	// The bounds are immutable, so every child shares the one slice; the
	// histogram they are validated through is discarded rather than
	// captured, so its counts and mutex do not outlive this call.
	bounds := newHistogram(name, buckets).upper
	hv := &HistogramVec{v: newVec(labels, func() *Histogram {
		return &Histogram{upper: bounds, counts: make([]uint64, len(bounds))}
	})}
	r.families[name] = &family{name: name, help: help, typ: typeHistogram, hvec: hv}
	return hv
}

func panicConflict(name string) {
	panic(fmt.Sprintf("metrics: %q is already registered as a different collector", name))
}

var (
	metricNameRE = regexp.MustCompile(`^[a-zA-Z_:][a-zA-Z0-9_:]*$`)
	labelNameRE  = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_]*$`)
)

func mustMetricName(name string) {
	if !metricNameRE.MatchString(name) {
		panic(fmt.Sprintf("metrics: invalid metric name %q", name))
	}
}

func mustLabelNames(labels []string) {
	seen := make(map[string]struct{}, len(labels))
	for _, l := range labels {
		if !labelNameRE.MatchString(l) {
			panic(fmt.Sprintf("metrics: invalid label name %q", l))
		}
		if _, dup := seen[l]; dup {
			panic(fmt.Sprintf("metrics: duplicate label name %q", l))
		}
		seen[l] = struct{}{}
	}
}
