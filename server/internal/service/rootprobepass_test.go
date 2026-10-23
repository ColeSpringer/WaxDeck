package service

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// awaitClosed waits for ch to close, failing with what it waited for.
func awaitClosed(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(10 * time.Second):
		t.Fatal("timed out waiting for " + what)
	}
}

// A pass lets go of the probe in more(), and a pass can start in the
// moment after, before the first one's worker has ended: that worker
// leaves the new pass's flags alone, so a refresh during the new pass
// asks it for another rather than running one beside it, and is kept.
func TestAProbePassStartedAsTheLastEndsKeepsItsFlags(t *testing.T) {
	t.Parallel()
	_, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	p := &svc.rootProbe
	waitFor(t, p.idle, "the boot probe pass to end")

	held, firstGone, third := make(chan struct{}), make(chan struct{}), make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	letHeldGo := func() { once.Do(func() { close(release) }) }
	t.Cleanup(letHeldGo)
	var passes, letGos, exits atomic.Int32
	p.mu.Lock()
	p.step = func(step string) {
		switch step {
		case "pass":
			switch passes.Add(1) {
			case 2:
				close(held)
				<-release
			case 3:
				close(third)
			}
		case "let-go":
			if letGos.Add(1) == 1 {
				svc.probeRoots()
			}
		case "exit":
			if exits.Add(1) == 1 {
				close(firstGone)
			}
		}
	}
	p.mu.Unlock()

	svc.probeRoots()
	awaitClosed(t, held, "the second pass to start")
	awaitClosed(t, firstGone, "the first pass's worker to end")
	if p.idle() {
		t.Fatal("the first pass's worker let go of the probe the second pass holds")
	}
	svc.probeRoots()
	p.mu.Lock()
	again := p.all
	p.mu.Unlock()
	if !again {
		t.Error("a refresh during the second pass was not kept for it")
	}
	if n := passes.Load(); n != 2 {
		t.Errorf("%d passes started while the second ran, want it alone", n)
	}
	letHeldGo()
	awaitClosed(t, third, "the pass the refresh asked for")
	waitFor(t, p.idle, "the passes to end")
}

// A pass that panics still lets go of the probe, so the next refresh
// probes again.
func TestAProbePassThatPanicsLetsGo(t *testing.T) {
	t.Parallel()
	_, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	p := &svc.rootProbe
	waitFor(t, p.idle, "the boot probe pass to end")
	var passes atomic.Int32
	p.mu.Lock()
	p.step = func(step string) {
		if step == "pass" && passes.Add(1) == 1 {
			panic("the pass broke")
		}
	}
	p.mu.Unlock()
	svc.probeRoots()
	waitFor(t, func() bool { return passes.Load() == 1 && p.idle() }, "the broken pass to let go")
	svc.probeRoots()
	waitFor(t, func() bool { return passes.Load() == 2 }, "the next pass")
}
