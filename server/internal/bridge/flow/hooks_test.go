package flow

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// slowDownHook registers an OnDown hook whose first run holds until the
// test lets it go, answering the channel it closes when it starts, the
// release, and its run count.
func slowDownHook(t *testing.T, b *Bridge) (entered <-chan struct{}, letGo func(), downs *atomic.Int32) {
	t.Helper()
	in, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	letGo = func() { once.Do(func() { close(release) }) }
	t.Cleanup(letGo)
	downs = new(atomic.Int32)
	b.OnDown(func() {
		if downs.Add(1) == 1 {
			close(in)
			<-release
		}
	})
	return in, letGo, downs
}

// returnsSoon fails unless fn returns while the test still holds a hook.
func returnsSoon(t *testing.T, fn func(), what string) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		defer close(done)
		fn()
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal(what)
	}
}

// A request that finds the engine gone while a probe's crossing is being
// told to a slow hook does not wait on the hook.
func TestARequestWaitsOnNoHookAProbeIsTelling(t *testing.T) {
	e := newSwitchedEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	entered, letGo, downs := slowDownHook(t, b)
	connect(t, b)
	e.away.Store(true)
	probed := make(chan error, 1)
	go func() { probed <- b.Connect(context.Background()) }()
	awaitSignal(t, entered, "the probe to tell the hook of the outage")
	returnsSoon(t, func() { b.lost(errors.New("connection reset by peer")) },
		"a request finding the engine gone waited on the hook a probe was running")
	letGo()
	if err := <-probed; err == nil {
		t.Fatal("the probe of an engine that is away answered nil")
	}
	if n := downs.Load(); n != 1 {
		t.Fatalf("OnDown ran %d times, want once for the one outage", n)
	}
}

// A request that finds the engine gone does not wait on the hooks of the
// crossing it makes: they are told off the request, at the probe it asks
// for.
func TestARequestFindingTheEngineGoneWaitsOnNoHook(t *testing.T) {
	e := newSwitchedEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	entered, letGo, downs := slowDownHook(t, b)
	connect(t, b)
	streamURL := tokenURL(t, b, "tr-X")
	e.away.Store(true)
	rec := httptest.NewRecorder()
	returnsSoon(t, func() { b.ServeStream(rec, httptest.NewRequest("GET", streamURL, nil)) },
		"the request that found the engine gone waited on the hooks of its crossing")
	if rec.Code != http.StatusBadGateway || b.Up() {
		t.Fatalf("status = %d, up %v; want 502 and the engine down", rec.Code, b.Up())
	}
	wantProbeAsked(t, b, "the request that found the engine gone")
	probed := make(chan error, 1)
	go func() { probed <- b.Connect(context.Background()) }()
	awaitSignal(t, entered, "the probe to tell the hook of the outage")
	letGo()
	if err := <-probed; err == nil {
		t.Fatal("the probe of an engine that is away answered nil")
	}
	if n := downs.Load(); n != 1 {
		t.Fatalf("OnDown ran %d times, want once for the one outage", n)
	}
}

// The hooks are told one crossing at a time, in the order the crossings
// were made, whichever goroutine made them.
func TestTheHooksRunInCrossingOrder(t *testing.T) {
	e := newSwitchedEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	var mu sync.Mutex
	var told []string
	var running, overlaps atomic.Int32
	tell := func(what string) {
		if running.Add(1) > 1 {
			overlaps.Add(1)
		}
		mu.Lock()
		told = append(told, what)
		mu.Unlock()
		running.Add(-1)
	}
	b.OnUp(func(context.Context, Status) { tell("up") })
	b.OnDown(func() { tell("down") })

	connect(t, b)
	b.lost(errors.New("connection reset by peer"))
	connect(t, b)
	b.lost(errors.New("connection reset by peer"))
	e.away.Store(true)
	if b.Connect(context.Background()) == nil {
		t.Fatal("the probe of an engine that is away answered nil")
	}
	mu.Lock()
	defer mu.Unlock()
	if want := []string{"up", "down", "up", "down"}; !slices.Equal(told, want) || overlaps.Load() != 0 {
		t.Fatalf("hooks told %v with %d overlaps, want %v one at a time", told, overlaps.Load(), want)
	}
}

// A hook that panics loses only its own crossing: the crossings queued
// behind it are told by the next probe.
func TestAPanickingHookLosesNoLaterCrossing(t *testing.T) {
	e := newSwitchedEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	var ups, downs atomic.Int32
	b.OnUp(func(context.Context, Status) { ups.Add(1) })
	b.OnDown(func() {
		if downs.Add(1) == 1 {
			panic("the hook broke")
		}
	})
	connect(t, b)
	caps := b.Caps()
	b.lost(errors.New("connection reset by peer"))
	b.settle(context.Background(), caps, nil)
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("the hook's panic did not reach its teller")
			}
		}()
		b.runHooks()
	}()
	b.runHooks()
	if n := ups.Load(); n != 2 {
		t.Fatalf("OnUp ran %d times, want the first answer and the return queued behind the panic (2)", n)
	}
}
