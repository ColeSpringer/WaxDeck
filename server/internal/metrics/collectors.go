package metrics

import (
	"fmt"
	"math"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Counter is a monotonically increasing value. The zero value is ready to
// use; obtain counters from a Registry so they are exposed.
type Counter struct {
	bits atomic.Uint64 // IEEE 754 bits of the current value
}

// Inc adds 1 to the counter.
func (c *Counter) Inc() { c.Add(1) }

// Add adds v to the counter. It panics if v is negative: counters are
// monotonic by definition, so a negative delta is a programmer error.
func (c *Counter) Add(v float64) {
	if v < 0 {
		panic(fmt.Sprintf("metrics: counter Add with negative value %v", v))
	}
	addFloat(&c.bits, v)
}

func (c *Counter) value() float64 { return math.Float64frombits(c.bits.Load()) }

// Gauge is a value that can go up and down. The zero value is ready to use;
// obtain gauges from a Registry so they are exposed.
type Gauge struct {
	bits atomic.Uint64 // IEEE 754 bits of the current value
}

// Set replaces the gauge's value.
func (g *Gauge) Set(v float64) { g.bits.Store(math.Float64bits(v)) }

// Inc adds 1 to the gauge.
func (g *Gauge) Inc() { g.Add(1) }

// Dec subtracts 1 from the gauge.
func (g *Gauge) Dec() { g.Add(-1) }

// Add adds v (which may be negative) to the gauge.
func (g *Gauge) Add(v float64) { addFloat(&g.bits, v) }

func (g *Gauge) value() float64 { return math.Float64frombits(g.bits.Load()) }

// addFloat atomically adds v to a float64 stored as bits, via a CAS loop.
func addFloat(bits *atomic.Uint64, v float64) {
	for {
		old := bits.Load()
		want := math.Float64bits(math.Float64frombits(old) + v)
		if bits.CompareAndSwap(old, want) {
			return
		}
	}
}

// vec is the shared implementation of CounterVec and GaugeVec: a lazily
// populated map from label values to child collectors.
type vec[C any] struct {
	labels []string
	newC   func() C

	mu   sync.Mutex
	kids map[string]*vecChild[C]
}

type vecChild[C any] struct {
	vals []string
	c    C
}

func newVec[C any](labels []string, newC func() C) vec[C] {
	return vec[C]{
		labels: slices.Clone(labels),
		newC:   newC,
		kids:   make(map[string]*vecChild[C]),
	}
}

func (v *vec[C]) with(vals []string) C {
	if len(vals) != len(v.labels) {
		panic(fmt.Sprintf("metrics: got %d label values for %d labels %q", len(vals), len(v.labels), v.labels))
	}
	key := vecKey(vals)
	v.mu.Lock()
	defer v.mu.Unlock()
	if ch, ok := v.kids[key]; ok {
		return ch.c
	}
	ch := &vecChild[C]{vals: slices.Clone(vals), c: v.newC()}
	v.kids[key] = ch
	return ch.c
}

// children returns a snapshot of the vec's children sorted by label values,
// for deterministic exposition.
func (v *vec[C]) children() []*vecChild[C] {
	v.mu.Lock()
	out := make([]*vecChild[C], 0, len(v.kids))
	for _, ch := range v.kids {
		out = append(out, ch)
	}
	v.mu.Unlock()
	slices.SortFunc(out, func(a, b *vecChild[C]) int { return slices.Compare(a.vals, b.vals) })
	return out
}

// vecKey encodes label values into an unambiguous map key
// (length-prefixed, so no separator can collide with value contents).
func vecKey(vals []string) string {
	var b strings.Builder
	for _, v := range vals {
		b.WriteString(strconv.Itoa(len(v)))
		b.WriteByte(':')
		b.WriteString(v)
	}
	return b.String()
}

// CounterVec is a family of counters partitioned by label values.
type CounterVec struct {
	v vec[*Counter]
}

// With returns the child counter for the given label values, creating it on
// first use. The number of values must match the vec's label names; the same
// values always return the same *Counter.
func (cv *CounterVec) With(labelValues ...string) *Counter { return cv.v.with(labelValues) }

// GaugeVec is a family of gauges partitioned by label values.
type GaugeVec struct {
	v vec[*Gauge]
}

// With returns the child gauge for the given label values, creating it on
// first use. The number of values must match the vec's label names; the same
// values always return the same *Gauge.
func (gv *GaugeVec) With(labelValues ...string) *Gauge { return gv.v.with(labelValues) }

// Histogram counts observations into cumulative buckets and tracks their sum.
type Histogram struct {
	upper []float64 // finite bucket upper bounds, strictly increasing; immutable

	mu     sync.Mutex
	counts []uint64 // per-bucket (non-cumulative) observation counts
	count  uint64
	sum    float64
}

func newHistogram(name string, buckets []float64) *Histogram {
	if len(buckets) == 0 {
		buckets = DefBuckets()
	}
	b := slices.Clone(buckets)
	if math.IsInf(b[len(b)-1], +1) {
		b = b[:len(b)-1] // the +Inf bucket is implicit
	}
	for i, ub := range b {
		if math.IsNaN(ub) {
			panic(fmt.Sprintf("metrics: histogram %q has NaN bucket bound", name))
		}
		if i > 0 && ub <= b[i-1] {
			panic(fmt.Sprintf("metrics: histogram %q buckets not strictly increasing: %v", name, buckets))
		}
	}
	return &Histogram{upper: b, counts: make([]uint64, len(b))}
}

// Observe records v in the histogram.
func (h *Histogram) Observe(v float64) {
	// The first bucket whose upper bound is >= v (le semantics). NaN
	// compares false against everything and lands in +Inf only.
	i := sort.SearchFloat64s(h.upper, v)
	h.mu.Lock()
	if i < len(h.counts) {
		h.counts[i]++
	}
	h.count++
	h.sum += v
	h.mu.Unlock()
}

// snapshot returns the finite bucket bounds, cumulative per-bucket counts,
// total count, and sum, consistent with each other.
func (h *Histogram) snapshot() (upper []float64, cum []uint64, count uint64, sum float64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	cum = make([]uint64, len(h.counts))
	var run uint64
	for i, c := range h.counts {
		run += c
		cum[i] = run
	}
	return h.upper, cum, h.count, h.sum
}

// DefBuckets returns the classic default histogram buckets, suited to
// request latencies in seconds. The caller owns the returned slice.
func DefBuckets() []float64 {
	return []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10}
}

// DurationSince observes the elapsed time since start, in seconds.
func DurationSince(h *Histogram, start time.Time) {
	h.Observe(time.Since(start).Seconds())
}
