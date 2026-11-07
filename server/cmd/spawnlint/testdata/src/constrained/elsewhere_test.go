//go:build ignore

package constrained

func spawnsInATest(f func()) {
	go f()
}
