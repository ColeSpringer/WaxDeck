package similarity

import (
	"fmt"
	"math"
	"math/rand"
	"testing"
)

func vecAngle(theta float64) []float32 {
	return []float32{float32(math.Cos(theta)), float32(math.Sin(theta))}
}

func TestEncodeDecodeRoundTrip(t *testing.T) {
	v := []float32{0.5, -1.25, 3e-9, 42}
	got := Decode(Encode(v))
	if len(got) != len(v) {
		t.Fatalf("length %d, want %d", len(got), len(v))
	}
	for i := range v {
		if got[i] != v[i] {
			t.Fatalf("index %d: %v, want %v", i, got[i], v[i])
		}
	}
	if Decode([]byte{1, 2, 3}) != nil {
		t.Fatal("odd-length blob should decode nil")
	}
}

func TestNormalizeRejectsZero(t *testing.T) {
	if Normalize([]float32{0, 0, 0}) {
		t.Fatal("zero vector normalized")
	}
	v := []float32{3, 4}
	if !Normalize(v) {
		t.Fatal("nonzero vector rejected")
	}
	if math.Abs(float64(v[0])-0.6) > 1e-6 || math.Abs(float64(v[1])-0.8) > 1e-6 {
		t.Fatalf("normalize wrong: %v", v)
	}
}

func TestIngestMaintainsMutualEdges(t *testing.T) {
	e := New()
	// Points around a circle: neighbors in angle are neighbors in
	// cosine distance.
	angles := []float64{0, 0.1, 0.2, 0.9, 1.0, 2.5}
	for i, th := range angles {
		_, _, ok := e.Ingest(fmt.Sprintf("e%d", i), vecAngle(th))
		if !ok {
			t.Fatalf("ingest %d refused", i)
		}
	}
	// e0 (angle 0) must list e1 (0.1) as its nearest neighbor, even
	// though e1 arrived after it: the reverse-update path did that.
	sim := e.Similar("e0", 1, nil)
	if len(sim) != 1 || sim[0].Neighbor != "e1" {
		t.Fatalf("nearest to e0 = %+v, want e1", sim)
	}
	// The last arrival must appear in earlier nodes' edge lists.
	e.mu.RLock()
	found := false
	for _, ed := range e.graph["e4"] {
		if ed.Neighbor == "e5" {
			found = true
		}
	}
	e.mu.RUnlock()
	if !found {
		t.Fatal("late arrival e5 missing from e4's edges")
	}
}

func TestIngestRejectsDimensionMismatch(t *testing.T) {
	e := New()
	if _, _, ok := e.Ingest("a", []float32{1, 0}); !ok {
		t.Fatal("first ingest refused")
	}
	if _, _, ok := e.Ingest("b", []float32{1, 0, 0}); ok {
		t.Fatal("dimension mismatch accepted")
	}
}

func TestRemoveReportsAffectedAndRecompute(t *testing.T) {
	e := New()
	for i, th := range []float64{0, 0.1, 0.2} {
		e.Ingest(fmt.Sprintf("e%d", i), vecAngle(th))
	}
	affected := e.Remove("e1")
	if len(affected) != 2 {
		t.Fatalf("affected = %v, want both remaining nodes", affected)
	}
	for _, a := range affected {
		edges, ok := e.Recompute(a)
		if !ok {
			t.Fatalf("recompute %s refused", a)
		}
		for _, ed := range edges {
			if ed.Neighbor == "e1" {
				t.Fatal("recomputed edges still reference removed node")
			}
		}
	}
}

func TestPathConnectsAndFitsLength(t *testing.T) {
	e := New()
	// A chain around the circle: consecutive angles are close, the
	// endpoints are far, so the path must walk the chain.
	n := 30
	for i := 0; i < n; i++ {
		e.Ingest(fmt.Sprintf("e%d", i), vecAngle(float64(i)*0.1))
	}
	path, complete := e.Path("e0", fmt.Sprintf("e%d", n-1), 8)
	if !complete {
		t.Fatal("path incomplete on a connected chain")
	}
	if path[0] != "e0" || path[len(path)-1] != fmt.Sprintf("e%d", n-1) {
		t.Fatalf("path endpoints wrong: %v", path)
	}
	if len(path) > 8+2 {
		t.Fatalf("path length %d far exceeds request", len(path))
	}
	seen := map[string]bool{}
	for _, s := range path {
		if seen[s] {
			t.Fatalf("path repeats %s", s)
		}
		seen[s] = true
	}
}

func TestPathDisconnectedIsPartial(t *testing.T) {
	e := New()
	e.Ingest("a", vecAngle(0))
	e.Ingest("b", vecAngle(0.05))
	// Manually disconnect: wipe edges so no traversal exists.
	e.mu.Lock()
	e.graph["a"] = nil
	e.graph["b"] = nil
	e.mu.Unlock()
	path, complete := e.Path("a", "b", 5)
	if complete {
		t.Fatal("disconnected graph reported complete")
	}
	if len(path) == 0 || path[0] != "a" {
		t.Fatalf("partial path should start at the seed: %v", path)
	}
}

func TestSimilarExcludesAndRanks(t *testing.T) {
	e := New()
	for i, th := range []float64{0, 0.1, 0.5, 1.5} {
		e.Ingest(fmt.Sprintf("e%d", i), vecAngle(th))
	}
	got := e.Similar("e0", 10, map[string]bool{"e1": true})
	if len(got) != 2 {
		t.Fatalf("got %d results, want 2", len(got))
	}
	if got[0].Neighbor != "e2" || got[1].Neighbor != "e3" {
		t.Fatalf("ranking wrong: %+v", got)
	}
}

func TestCentroid(t *testing.T) {
	e := New()
	e.Ingest("a", vecAngle(0))
	e.Ingest("b", vecAngle(math.Pi/2))
	c, ok := e.Centroid([]string{"a", "b", "missing"})
	if !ok {
		t.Fatal("centroid refused")
	}
	want := math.Sqrt2 / 2
	if math.Abs(float64(c[0])-want) > 1e-5 || math.Abs(float64(c[1])-want) > 1e-5 {
		t.Fatalf("centroid = %v", c)
	}
}

func TestBruteForceMatchesGraphAtScale(t *testing.T) {
	// The incremental graph must agree with a from-scratch recompute.
	rng := rand.New(rand.NewSource(1))
	e := New()
	const n, dims = 300, 8
	for i := 0; i < n; i++ {
		v := make([]float32, dims)
		for j := range v {
			v[j] = float32(rng.NormFloat64())
		}
		e.Ingest(fmt.Sprintf("e%d", i), v)
	}
	for i := 0; i < n; i += 37 {
		es := fmt.Sprintf("e%d", i)
		e.mu.RLock()
		incremental := append([]Edge(nil), e.graph[es]...)
		e.mu.RUnlock()
		fresh, _ := e.Recompute(es)
		if len(incremental) != len(fresh) {
			t.Fatalf("%s: %d incremental edges, %d fresh", es, len(incremental), len(fresh))
		}
		for j := range fresh {
			if math.Abs(incremental[j].Distance-fresh[j].Distance) > 1e-9 {
				t.Fatalf("%s edge %d: incremental %v fresh %v", es, j, incremental[j], fresh[j])
			}
		}
	}
}
