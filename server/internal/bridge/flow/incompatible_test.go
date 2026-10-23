package flow

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// upgradableEngine is a fake sidecar that answers /caps without
// progressive delivery, as an incompatible build does, until upgraded.
type upgradableEngine struct {
	srv      *httptest.Server
	upgraded atomic.Bool
	asks     atomic.Int32
}

func newUpgradableEngine(t *testing.T) *upgradableEngine {
	t.Helper()
	e := &upgradableEngine{}
	e.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/caps" {
			http.NotFound(w, r)
			return
		}
		e.asks.Add(1)
		caps := capsJSON()
		if !e.upgraded.Load() {
			caps = strings.Replace(caps, `"progressive":true`, `"progressive":false`, 1)
		}
		fmt.Fprint(w, caps)
	}))
	t.Cleanup(e.srv.Close)
	return e
}

// eventually waits until cond holds, failing with what it waited for.
func eventually(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for " + what)
		}
		time.Sleep(time.Millisecond)
	}
}

// cannotServe is what the log says of an engine that answers without
// what this server needs.
const cannotServe = `level=ERROR msg="the streaming engine answers but cannot serve this server`

// An engine that answers but cannot serve this server is told apart from
// one that does not answer: one ERROR naming what it lacks, at the
// crossing into that state, and the bridge stays not connected.
func TestAnEngineThatCannotServeIsSaidAsOne(t *testing.T) {
	e := newUpgradableEngine(t)
	logs := &lockedBuffer{}
	b := newEngineBridge(t, e.srv.URL, flacSource(t), slog.New(slog.NewTextHandler(logs, nil)))
	ups, downs := countCrossings(b)
	ctx := context.Background()
	for range 3 {
		if b.Connect(ctx) == nil {
			t.Fatal("an engine without progressive streams answered nil")
		}
	}
	if b.Up() || b.Status().Connected {
		t.Fatalf("up %v, status %+v; want an engine that cannot serve not connected", b.Up(), b.Status())
	}
	if downs.Load() != 1 || ups.Load() != 0 {
		t.Fatalf("OnDown ran %d times, OnUp %d; want the one crossing down", downs.Load(), ups.Load())
	}
	if n := logs.count(cannotServe); n != 1 {
		t.Fatalf("the engine that cannot serve was said %d times, want once:\n%s", n, logs.buf.String())
	}
	for _, line := range strings.Split(logs.buf.String(), "\n") {
		if strings.Contains(line, cannotServe) && (!strings.Contains(line, "progressive") || !strings.Contains(line, e.srv.URL)) {
			t.Errorf("the line %q does not name what the engine lacks and where it is", line)
		}
	}
	for _, said := range []string{"not answering yet", "streaming engine unreachable"} {
		if logs.count(said) != 0 {
			t.Errorf("an engine that answers was said as %q:\n%s", said, logs.buf.String())
		}
	}

	e.upgraded.Store(true)
	connect(t, b)
	if !b.Up() || ups.Load() != 1 {
		t.Fatalf("after the upgrade: up %v, OnUp ran %d times; want it up", b.Up(), ups.Load())
	}
	e.upgraded.Store(false)
	if b.Connect(ctx) == nil {
		t.Fatal("an engine without progressive streams answered nil")
	}
	if n := logs.count(cannotServe); n != 2 || b.Up() {
		t.Fatalf("after a downgrade: said %d times, up %v; want it said again at the crossing, down", n, b.Up())
	}
}

// The bridge asks an engine that cannot serve again at the normal
// interval, not the backoff for one that does not answer, so an upgraded
// sidecar is taken on without a restart.
func TestAnUpgradedEngineIsTakenOnWithoutARestart(t *testing.T) {
	e := newUpgradableEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	b.retryMin, b.retryMax, b.probeEvery = time.Hour, time.Hour, 5*time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- b.Run(ctx) }()
	defer func() {
		cancel()
		<-done
	}()
	eventually(t, func() bool { return e.asks.Load() >= 3 }, "the bridge to keep asking the engine that cannot serve")
	e.upgraded.Store(true)
	eventually(t, b.Up, "the upgraded engine to be taken on")
}
