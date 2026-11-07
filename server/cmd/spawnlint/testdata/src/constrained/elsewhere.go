//go:build ignore

package constrained

func spawns(f func()) {
	go f()
}
