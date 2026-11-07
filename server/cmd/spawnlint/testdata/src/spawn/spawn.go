package spawn

import "sync"

func work() {}

func spawns() {
	go work() // want `bare go statement`
	var wg sync.WaitGroup
	wg.Go(work) // want `sync.WaitGroup.Go spawns an unsupervised goroutine`
}

type group struct{}

func (group) Go(func()) {}

// Another type's Go method is not a WaitGroup's.
func supervised() {
	var g group
	g.Go(work)
}
