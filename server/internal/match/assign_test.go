package match

import (
	"math"
	"math/rand"
	"testing"
)

// bruteForce finds the optimal assignment cost by permutation search,
// assigning min(n,m) pairs. With more rows than columns it recurses on
// the transpose so every choice of winning rows is considered.
func bruteForce(cost [][]float64) float64 {
	n := len(cost)
	m := len(cost[0])
	if n > m {
		t := make([][]float64, m)
		for j := range t {
			t[j] = make([]float64, n)
			for i := range t[j] {
				t[j][i] = cost[i][j]
			}
		}
		return bruteForce(t)
	}
	cols := make([]int, m)
	for j := range cols {
		cols[j] = j
	}
	best := math.Inf(1)
	var permute func(k int)
	permute = func(k int) {
		if k == len(cols) || k == n {
			total := 0.0
			for i := 0; i < n && i < len(cols); i++ {
				total += cost[i][cols[i]]
			}
			if total < best {
				best = total
			}
			return
		}
		for j := k; j < len(cols); j++ {
			cols[k], cols[j] = cols[j], cols[k]
			permute(k + 1)
			cols[k], cols[j] = cols[j], cols[k]
		}
	}
	permute(0)
	return best
}

func assignedCost(cost [][]float64, assigned []int) float64 {
	total := 0.0
	for i, j := range assigned {
		if j >= 0 {
			total += cost[i][j]
		}
	}
	return total
}

func TestAssignMatchesBruteForce(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	for trial := 0; trial < 200; trial++ {
		n := 1 + rng.Intn(5)
		m := 1 + rng.Intn(5)
		cost := make([][]float64, n)
		for i := range cost {
			cost[i] = make([]float64, m)
			for j := range cost[i] {
				cost[i][j] = float64(rng.Intn(1000)) / 1000
			}
		}
		assigned := assign(cost)
		if len(assigned) != n {
			t.Fatalf("trial %d: got %d assignments for %d rows", trial, len(assigned), n)
		}
		usedCols := make(map[int]bool)
		assignedRows := 0
		for _, j := range assigned {
			if j < 0 {
				continue
			}
			if usedCols[j] {
				t.Fatalf("trial %d: column %d assigned twice", trial, j)
			}
			usedCols[j] = true
			assignedRows++
		}
		want := n
		if m < n {
			want = m
		}
		if assignedRows != want {
			t.Fatalf("trial %d: %d rows assigned, want %d (n=%d m=%d)", trial, assignedRows, want, n, m)
		}
		got := assignedCost(cost, assigned)
		best := bruteForce(cost)
		if math.Abs(got-best) > 1e-9 {
			t.Fatalf("trial %d: cost %v, brute force %v (n=%d m=%d cost=%v)", trial, got, best, n, m, cost)
		}
	}
}

func TestAssignDegenerate(t *testing.T) {
	if got := assign(nil); got != nil {
		t.Fatalf("nil matrix: got %v", got)
	}
	got := assign([][]float64{{}, {}})
	if len(got) != 2 || got[0] != -1 || got[1] != -1 {
		t.Fatalf("zero columns: got %v", got)
	}
}

func TestAssignPrefersDiagonal(t *testing.T) {
	cost := [][]float64{
		{0.0, 0.9, 0.9},
		{0.9, 0.0, 0.9},
		{0.9, 0.9, 0.0},
	}
	got := assign(cost)
	for i, j := range got {
		if i != j {
			t.Fatalf("expected identity assignment, got %v", got)
		}
	}
}
