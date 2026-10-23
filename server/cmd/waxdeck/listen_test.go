package main

import (
	"bytes"
	"context"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// lockedLog collects what the server says from its own goroutines.
type lockedLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *lockedLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *lockedLog) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// A port another process holds fails the start, naming the address,
// before the server has said it listens.
func TestListenFailsBeforeAnythingLogs(t *testing.T) {
	held, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer held.Close()
	addr := held.Addr().String()
	if _, err := listen(addr); err == nil || !strings.HasPrefix(err.Error(), "listening on "+addr+": ") {
		t.Fatalf("listen(%s) = %v, want the bind refusal naming the address", addr, err)
	}
}

// Once bound, the server says so; a serve that fails stops the process
// and is what run returns, not a clean exit.
func TestAServeFailureStopsTheProcessAndIsReturned(t *testing.T) {
	logs := &lockedLog{}
	log := slog.New(slog.NewTextHandler(logs, nil))
	group := supervise.NewGroup(log)
	ln, err := listen("127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	stopped := make(chan struct{})
	served := serve(context.Background(), group, log, &http.Server{Handler: http.NotFoundHandler()}, ln,
		func() { close(stopped) })

	deadline := time.Now().Add(10 * time.Second)
	for !strings.Contains(logs.String(), "waxdeck listening") {
		if time.Now().After(deadline) {
			t.Fatal("the server never said it listens")
		}
		time.Sleep(5 * time.Millisecond)
	}
	ln.Close()
	select {
	case <-stopped:
	case <-time.After(10 * time.Second):
		t.Fatal("a failed serve did not stop the process")
	}
	group.Wait()
	if err := served(); err == nil || !strings.HasPrefix(err.Error(), "serving on ") {
		t.Fatalf("served = %v, want the serve failure", err)
	}
}

// A server shut down on purpose ends clean.
func TestAShutdownServeIsNoFailure(t *testing.T) {
	log := slog.New(slog.DiscardHandler)
	group := supervise.NewGroup(log)
	ln, err := listen("127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: http.NotFoundHandler()}
	served := serve(context.Background(), group, log, srv, ln, func() { t.Error("a shutdown stopped the process as a failure") })
	resp, err := http.Get("http://" + ln.Addr().String() + "/")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if err := srv.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	group.Wait()
	if err := served(); err != nil {
		t.Fatalf("served = %v after a shutdown, want nil", err)
	}
}
