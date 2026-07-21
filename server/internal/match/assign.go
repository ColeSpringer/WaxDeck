package match

import "math"

// assign solves the minimum cost bipartite assignment for a cost matrix
// (rows are unit tracks, columns are release tracks) and returns, for
// each row, the assigned column index. Every row is assigned when there
// are at least as many columns as rows; with fewer columns the cheapest
// rows win and the rest return -1. The solver is the Hungarian method
// with potentials, cubic in the larger dimension, which is instant at
// album sizes.
func assign(cost [][]float64) []int {
	n := len(cost)
	if n == 0 {
		return nil
	}
	m := len(cost[0])
	if m == 0 {
		out := make([]int, n)
		for i := range out {
			out[i] = -1
		}
		return out
	}
	if n <= m {
		return hungarian(cost, n, m)
	}
	// More rows than columns: solve the transpose, then invert the
	// mapping; unassigned rows get -1.
	t := make([][]float64, m)
	for j := 0; j < m; j++ {
		t[j] = make([]float64, n)
		for i := 0; i < n; i++ {
			t[j][i] = cost[i][j]
		}
	}
	colToRow := hungarian(t, m, n)
	out := make([]int, n)
	for i := range out {
		out[i] = -1
	}
	for j, i := range colToRow {
		if i >= 0 {
			out[i] = j
		}
	}
	return out
}

// hungarian implements the potentials formulation for n rows and m
// columns with n <= m, returning the assigned column per row.
func hungarian(cost [][]float64, n, m int) []int {
	u := make([]float64, n+1)
	v := make([]float64, m+1)
	p := make([]int, m+1)   // p[j] is the 1 based row matched to column j
	way := make([]int, m+1) // alternating path parents
	for i := 1; i <= n; i++ {
		p[0] = i
		j0 := 0
		minv := make([]float64, m+1)
		used := make([]bool, m+1)
		for j := range minv {
			minv[j] = math.Inf(1)
		}
		for {
			used[j0] = true
			i0 := p[j0]
			delta := math.Inf(1)
			j1 := 0
			for j := 1; j <= m; j++ {
				if used[j] {
					continue
				}
				cur := cost[i0-1][j-1] - u[i0] - v[j]
				if cur < minv[j] {
					minv[j] = cur
					way[j] = j0
				}
				if minv[j] < delta {
					delta = minv[j]
					j1 = j
				}
			}
			for j := 0; j <= m; j++ {
				if used[j] {
					u[p[j]] += delta
					v[j] -= delta
				} else {
					minv[j] -= delta
				}
			}
			j0 = j1
			if p[j0] == 0 {
				break
			}
		}
		for j0 != 0 {
			j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
		}
	}
	out := make([]int, n)
	for i := range out {
		out[i] = -1
	}
	for j := 1; j <= m; j++ {
		if p[j] > 0 {
			out[p[j]-1] = j - 1
		}
	}
	return out
}
