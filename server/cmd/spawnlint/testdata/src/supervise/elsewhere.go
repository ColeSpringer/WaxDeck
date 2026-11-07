//go:build ignore

package supervise

func goElsewhere(f func()) {
	go f()
}
