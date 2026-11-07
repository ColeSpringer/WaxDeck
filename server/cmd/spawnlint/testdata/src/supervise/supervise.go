// Package supervise stands in for the one package that may spawn.
package supervise

func Go(f func()) {
	go f()
}
