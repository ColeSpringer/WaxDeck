// Package similarity is the in-memory sonic-similarity engine: unit
// vectors keyed by audio essence, cosine distance, and a top-K
// nearest-neighbor graph maintained incrementally at ingest.
//
// Single-seed queries are deliberate brute-force scans: at library
// scale (100k tracks, ~200 dims) an exhaustive dot-product pass is
// milliseconds, which beats carrying an approximate-nearest-neighbor
// index. Path queries never sweep: the ingest pass precomputes each
// track's top-K neighbor edges, and pathfinding is plain graph
// traversal over them. Graph maintenance is incremental by
// construction: the ingest sweep's distances also update any existing
// node whose current worst neighbor the new track beats (O(K) per
// affected node, no additional vector math), and deletions prune edges
// and queue only the affected nodes for lazy recompute. There is no
// full-rebuild job on purpose; a periodic top-K recompute would be
// O(N^2) across the library.
package similarity

import (
	"container/heap"
	"encoding/binary"
	"math"
	"sort"
	"sync"
)

// K is the per-node neighbor-edge count. Enough for paths to branch,
// small enough that the whole graph stays cheap.
const K = 10

// Edge is one neighbor edge: cosine distance in [0, 2], nearer first.
type Edge struct {
	Neighbor string
	Distance float64
}

// Engine holds every vector and the neighbor graph. All methods are
// safe for concurrent use.
type Engine struct {
	mu      sync.RWMutex
	dims    int
	vectors map[string][]float32
	graph   map[string][]Edge
}

// New returns an empty engine.
func New() *Engine {
	return &Engine{
		vectors: make(map[string][]float32),
		graph:   make(map[string][]Edge),
	}
}

// Normalize scales v to unit length in place. False for a zero vector,
// which carries no direction and cannot be compared.
func Normalize(v []float32) bool {
	var sum float64
	for _, x := range v {
		sum += float64(x) * float64(x)
	}
	if sum == 0 || math.IsNaN(sum) || math.IsInf(sum, 0) {
		return false
	}
	inv := 1 / math.Sqrt(sum)
	for i := range v {
		v[i] = float32(float64(v[i]) * inv)
	}
	return true
}

// Encode packs a vector as little-endian float32 for storage.
func Encode(v []float32) []byte {
	out := make([]byte, 4*len(v))
	for i, x := range v {
		binary.LittleEndian.PutUint32(out[4*i:], math.Float32bits(x))
	}
	return out
}

// Decode unpacks a stored vector. Nil when the blob length is not a
// multiple of four.
func Decode(b []byte) []float32 {
	if len(b)%4 != 0 {
		return nil
	}
	out := make([]float32, len(b)/4)
	for i := range out {
		out[i] = math.Float32frombits(binary.LittleEndian.Uint32(b[4*i:]))
	}
	return out
}

// distance is cosine distance between unit vectors: 1 - dot.
func distance(a, b []float32) float64 {
	var dot float64
	for i := range a {
		dot += float64(a[i]) * float64(b[i])
	}
	return 1 - dot
}

// Load inserts a vector without graph math, for warming from storage.
// The vector must already be unit length (Ingest stores them that way).
func (e *Engine) Load(essence string, vec []float32) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.dims = len(vec)
	e.vectors[essence] = vec
}

// LoadEdges installs a node's stored edge list, for warming.
func (e *Engine) LoadEdges(essence string, edges []Edge) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.graph[essence] = edges
}

// Len reports how many vectors are held.
func (e *Engine) Len() int {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return len(e.vectors)
}

// Has reports whether an essence has a vector.
func (e *Engine) Has(essence string) bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	_, ok := e.vectors[essence]
	return ok
}

// Dims reports the vector dimensionality, 0 when empty.
func (e *Engine) Dims() int {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.dims
}

// Reset drops everything (a model switch restarts coverage).
func (e *Engine) Reset() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.dims = 0
	e.vectors = make(map[string][]float32)
	e.graph = make(map[string][]Edge)
}

// Ingest inserts vec (normalizing it), computes the new node's top-K
// edges in one sweep, and updates every existing node whose current
// worst edge the new arrival beats. It returns the new node's edges
// and each updated node's new edge list, for persistence. False when
// the vector is zero or its length disagrees with the stored
// dimensionality.
func (e *Engine) Ingest(essence string, vec []float32) (edges []Edge, updated map[string][]Edge, ok bool) {
	if !Normalize(vec) {
		return nil, nil, false
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.dims != 0 && len(e.vectors) > 0 && len(vec) != e.dims {
		return nil, nil, false
	}
	updated = make(map[string][]Edge)
	best := newTopK(K)
	for other, ov := range e.vectors {
		if other == essence {
			continue
		}
		d := distance(vec, ov)
		best.offer(Edge{Neighbor: other, Distance: d})
		// The same distance read updates the other node when the new
		// arrival beats its current worst edge (or it has room).
		g := e.graph[other]
		if len(g) < K || d < g[len(g)-1].Distance {
			g = insertEdge(g, Edge{Neighbor: essence, Distance: d}, K)
			e.graph[other] = g
			updated[other] = g
		}
	}
	e.dims = len(vec)
	e.vectors[essence] = vec
	edges = best.sorted()
	e.graph[essence] = edges
	return edges, updated, true
}

// Remove drops an essence's vector and edges, prunes edges pointing at
// it, and returns the nodes that lost one (they need a lazy recompute).
func (e *Engine) Remove(essence string) (affected []string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if _, ok := e.vectors[essence]; !ok {
		return nil
	}
	delete(e.vectors, essence)
	delete(e.graph, essence)
	for node, edges := range e.graph {
		for i, ed := range edges {
			if ed.Neighbor == essence {
				e.graph[node] = append(edges[:i:i], edges[i+1:]...)
				affected = append(affected, node)
				break
			}
		}
	}
	return affected
}

// Recompute rebuilds one node's top-K edges by brute force (the lazy
// backfill after deletions). False when the essence holds no vector.
func (e *Engine) Recompute(essence string) ([]Edge, bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	vec, ok := e.vectors[essence]
	if !ok {
		return nil, false
	}
	best := newTopK(K)
	for other, ov := range e.vectors {
		if other == essence {
			continue
		}
		best.offer(Edge{Neighbor: other, Distance: distance(vec, ov)})
	}
	edges := best.sorted()
	e.graph[essence] = edges
	return edges, true
}

// Similar brute-force scans for the k nearest to an essence's vector.
// Nil when the essence holds no vector.
func (e *Engine) Similar(essence string, k int, exclude map[string]bool) []Edge {
	e.mu.RLock()
	vec, ok := e.vectors[essence]
	e.mu.RUnlock()
	if !ok {
		return nil
	}
	if exclude == nil {
		exclude = map[string]bool{}
	}
	exclude[essence] = true
	return e.SimilarToVector(vec, k, exclude)
}

// SimilarToVector brute-force scans for the k nearest to an arbitrary
// unit vector (a centroid seed).
func (e *Engine) SimilarToVector(vec []float32, k int, exclude map[string]bool) []Edge {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if len(vec) != e.dims {
		return nil
	}
	best := newTopK(k)
	for other, ov := range e.vectors {
		if exclude[other] {
			continue
		}
		best.offer(Edge{Neighbor: other, Distance: distance(vec, ov)})
	}
	return best.sorted()
}

// Vector returns a copy of an essence's stored vector.
func (e *Engine) Vector(essence string) ([]float32, bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	v, ok := e.vectors[essence]
	if !ok {
		return nil, false
	}
	out := make([]float32, len(v))
	copy(out, v)
	return out, true
}

// Centroid returns the normalized mean of the named essences' vectors.
// False when none of them holds a vector.
func (e *Engine) Centroid(essences []string) ([]float32, bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.dims == 0 {
		return nil, false
	}
	sum := make([]float32, e.dims)
	n := 0
	for _, es := range essences {
		v, ok := e.vectors[es]
		if !ok {
			continue
		}
		for i := range sum {
			sum[i] += v[i]
		}
		n++
	}
	if n == 0 || !Normalize(sum) {
		return nil, false
	}
	return sum, true
}

// maxPathExpansions bounds Dijkstra so a pathological graph cannot peg
// a request; at K edges per node this covers libraries far beyond the
// design target.
const maxPathExpansions = 200000

// Path finds a listening path between two essences over the neighbor
// graph: Dijkstra on edge distances, then even downsampling when the
// hop count exceeds length, or edge-local enrichment (each hop's
// candidates are the K stored neighbors, never a sweep) when it falls
// short. complete is false when the graph does not connect the
// endpoints; the returned prefix is a greedy walk that still drifts
// toward the target.
func (e *Engine) Path(from, to string, length int) (path []string, complete bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if _, ok := e.vectors[from]; !ok {
		return nil, false
	}
	if _, ok := e.vectors[to]; !ok {
		return nil, false
	}
	if from == to {
		return []string{from}, true
	}
	if p := e.dijkstra(from, to); p != nil {
		p = e.fitLength(p, length)
		return p, true
	}
	return e.greedyToward(from, to, length), false
}

// dijkstra runs bounded shortest-path over the neighbor graph. Nil when
// to is unreachable within the expansion budget.
func (e *Engine) dijkstra(from, to string) []string {
	dist := map[string]float64{from: 0}
	prev := map[string]string{}
	done := map[string]bool{}
	pq := &edgeHeap{{Neighbor: from, Distance: 0}}
	expansions := 0
	for pq.Len() > 0 && expansions < maxPathExpansions {
		cur := heap.Pop(pq).(Edge)
		if done[cur.Neighbor] {
			continue
		}
		done[cur.Neighbor] = true
		expansions++
		if cur.Neighbor == to {
			var path []string
			for at := to; ; at = prev[at] {
				path = append([]string{at}, path...)
				if at == from {
					return path
				}
			}
		}
		for _, ed := range e.graph[cur.Neighbor] {
			if done[ed.Neighbor] {
				continue
			}
			nd := cur.Distance + ed.Distance
			if old, ok := dist[ed.Neighbor]; !ok || nd < old {
				dist[ed.Neighbor] = nd
				prev[ed.Neighbor] = cur.Neighbor
				heap.Push(pq, Edge{Neighbor: ed.Neighbor, Distance: nd})
			}
		}
	}
	return nil
}

// fitLength adjusts a path to approximately the requested length: even
// downsampling (keeping both endpoints) when too long, hop enrichment
// via stored neighbor edges when too short.
func (e *Engine) fitLength(p []string, length int) []string {
	if length < 2 {
		length = 2
	}
	if len(p) > length {
		out := make([]string, 0, length)
		for i := 0; i < length; i++ {
			out = append(out, p[i*(len(p)-1)/(length-1)])
		}
		return dedupePath(out)
	}
	used := make(map[string]bool, len(p))
	for _, s := range p {
		used[s] = true
	}
	// Each pass splits the widest hop by the neighbor that best bridges
	// it: candidates are the hop endpoints' K stored edges, so a pass
	// costs O(len * K) distance reads against held vectors, no sweep.
	for len(p) < length {
		bestHop, bestGain := -1, 0.0
		var bestVia string
		for i := 0; i+1 < len(p); i++ {
			a, b := e.vectors[p[i]], e.vectors[p[i+1]]
			hop := distance(a, b)
			for _, ed := range e.graph[p[i]] {
				if used[ed.Neighbor] {
					continue
				}
				v, ok := e.vectors[ed.Neighbor]
				if !ok {
					continue
				}
				// A good via sits between its endpoints: both legs
				// shorter than the hop it splits.
				la, lb := distance(a, v), distance(v, b)
				if la >= hop || lb >= hop {
					continue
				}
				gain := hop - math.Max(la, lb)
				if gain > bestGain {
					bestHop, bestGain, bestVia = i, gain, ed.Neighbor
				}
			}
		}
		if bestHop < 0 {
			break
		}
		p = append(p[:bestHop+1], append([]string{bestVia}, p[bestHop+1:]...)...)
		used[bestVia] = true
	}
	return p
}

// greedyToward walks neighbor edges always reducing vector distance to
// the target, for the partial answer when the graph is disconnected.
func (e *Engine) greedyToward(from, to string, length int) []string {
	target := e.vectors[to]
	path := []string{from}
	used := map[string]bool{from: true}
	cur := from
	for len(path) < length {
		curDist := distance(e.vectors[cur], target)
		next, nextDist := "", curDist
		for _, ed := range e.graph[cur] {
			if used[ed.Neighbor] {
				continue
			}
			v, ok := e.vectors[ed.Neighbor]
			if !ok {
				continue
			}
			if d := distance(v, target); d < nextDist {
				next, nextDist = ed.Neighbor, d
			}
		}
		if next == "" {
			break
		}
		path = append(path, next)
		used[next] = true
		cur = next
	}
	return path
}

func dedupePath(p []string) []string {
	out := p[:0]
	seen := map[string]bool{}
	for _, s := range p {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

// insertEdge inserts ed into a distance-sorted list, dropping any prior
// edge to the same neighbor and capping at k.
func insertEdge(edges []Edge, ed Edge, k int) []Edge {
	for i, ex := range edges {
		if ex.Neighbor == ed.Neighbor {
			edges = append(edges[:i:i], edges[i+1:]...)
			break
		}
	}
	i := sort.Search(len(edges), func(i int) bool { return edges[i].Distance >= ed.Distance })
	edges = append(edges, Edge{})
	copy(edges[i+1:], edges[i:])
	edges[i] = ed
	if len(edges) > k {
		edges = edges[:k]
	}
	return edges
}

// topK keeps the k nearest edges seen, worst on top of a max-heap.
type topK struct {
	k int
	h maxHeap
}

func newTopK(k int) *topK { return &topK{k: k} }

func (t *topK) offer(e Edge) {
	if t.k <= 0 {
		return
	}
	if len(t.h) < t.k {
		heap.Push(&t.h, e)
		return
	}
	if e.Distance < t.h[0].Distance {
		t.h[0] = e
		heap.Fix(&t.h, 0)
	}
}

func (t *topK) sorted() []Edge {
	out := make([]Edge, len(t.h))
	copy(out, t.h)
	sort.Slice(out, func(i, j int) bool { return out[i].Distance < out[j].Distance })
	return out
}

type maxHeap []Edge

func (h maxHeap) Len() int           { return len(h) }
func (h maxHeap) Less(i, j int) bool { return h[i].Distance > h[j].Distance }
func (h maxHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *maxHeap) Push(x any)        { *h = append(*h, x.(Edge)) }
func (h *maxHeap) Pop() any          { old := *h; n := len(old); x := old[n-1]; *h = old[:n-1]; return x }

type edgeHeap []Edge

func (h edgeHeap) Len() int           { return len(h) }
func (h edgeHeap) Less(i, j int) bool { return h[i].Distance < h[j].Distance }
func (h edgeHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *edgeHeap) Push(x any)        { *h = append(*h, x.(Edge)) }
func (h *edgeHeap) Pop() any          { old := *h; n := len(old); x := old[n-1]; *h = old[:n-1]; return x }
