package api

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A relay holds a goroutine and an upstream socket for as long as the
// transfer runs, so the interesting case is the one that never ends on
// its own: a station that keeps its connection open forever. Enough of
// those and one account has pinned the server.
func TestRadioRelayCapsConcurrentStreamsPerUser(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})

	// The station answers headers and one byte, then holds the
	// connection until the test tears down: a live stream, from the
	// relay's point of view.
	hold := make(chan struct{})
	var closeOnce sync.Once
	release := func() { closeOnce.Do(func() { close(hold) }) }
	t.Cleanup(release)
	station := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("x"))
		http.NewResponseController(w).Flush()
		select {
		case <-hold:
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(station.Close)

	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Held Open FM", "streamUrl": station.URL + "/stream",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	st := decode[RadioStation](t, resp)

	resp = get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	pi := decode[RadioPlayInfo](t, resp)

	// Each open relay is one held slot. Reading a byte first is what
	// makes the slot certainly taken: the relay writes its headers only
	// after acquiring, so a response in hand means the count moved.
	open := func() (*http.Response, error) {
		r, err := http.Get(h.ts.URL + pi.Url)
		if err != nil {
			return nil, err
		}
		if r.StatusCode == http.StatusOK {
			b := make([]byte, 1)
			if _, err := io.ReadFull(r.Body, b); err != nil {
				r.Body.Close()
				return nil, err
			}
		}
		return r, nil
	}

	for i := 0; i < maxUserRelays; i++ {
		r, err := open()
		if err != nil {
			t.Fatalf("relay %d: %v", i, err)
		}
		t.Cleanup(func() { r.Body.Close() })
		if r.StatusCode != 200 {
			t.Fatalf("relay %d status = %d, want 200", i, r.StatusCode)
		}
	}

	over, err := open()
	if err != nil {
		t.Fatal(err)
	}
	defer over.Body.Close()
	if over.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("over-cap relay status = %d, want 429", over.StatusCode)
	}
	if e := decode[Error](t, over); e.Code != "rate-limited" {
		t.Fatalf("over-cap relay code = %q, want rate-limited", e.Code)
	}

	// A slot comes back when its stream ends, so the cap bounds
	// concurrency rather than permanently spending an account's budget.
	release()
	deadline := time.Now().Add(5 * time.Second)
	for {
		again, err := open()
		if err != nil {
			t.Fatal(err)
		}
		code := again.StatusCode
		again.Body.Close()
		if code == http.StatusOK {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("relay slots never came back; last status = %d", code)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestRelayGuardBounds(t *testing.T) {
	t.Parallel()
	// A transfer inside every bound is left alone.
	t.Run("within bounds", func(t *testing.T) {
		g := newRelayGuard(relayLimits{
			idle: time.Minute, maxBytes: 1024, minRate: 1, rateGrace: time.Minute,
		}, func() { t.Error("cancelled a healthy transfer") })
		defer g.stop()
		for i := 0; i < 8; i++ {
			if !g.note(64) {
				t.Fatalf("note %d cut a transfer inside its bounds: %s", i, g.reason())
			}
		}
	})

	// An endless body is the case a finite file cannot have: past the
	// cap, the transfer ends.
	t.Run("size cap", func(t *testing.T) {
		var cancelled bool
		g := newRelayGuard(relayLimits{maxBytes: 100}, func() { cancelled = true })
		defer g.stop()
		if !g.note(100) {
			t.Fatal("cut at exactly the cap; the cap is the last allowed byte")
		}
		if g.note(1) {
			t.Fatal("relayed past the size cap")
		}
		if !cancelled {
			t.Fatal("tripping the size cap did not cancel the upstream")
		}
		if g.reason() == "" {
			t.Fatal("no reason recorded for the size cap")
		}
	})

	// A host dribbling bytes forever is never idle, which is the whole
	// reason the rate floor exists beside the idle deadline. The start
	// is backdated so the grace window is already spent.
	t.Run("rate floor", func(t *testing.T) {
		var cancelled bool
		g := newRelayGuard(relayLimits{
			minRate:    1024,
			rateGrace:  time.Second,
			relayStart: time.Now().Add(-time.Minute),
		}, func() { cancelled = true })
		defer g.stop()
		if g.note(16) {
			t.Fatal("a transfer far under the rate floor was allowed to continue")
		}
		if !cancelled {
			t.Fatal("tripping the rate floor did not cancel the upstream")
		}
	})

	// Inside the grace window the same dribble is left alone, so a slow
	// start is never mistaken for a stall.
	t.Run("rate floor waits out the grace window", func(t *testing.T) {
		g := newRelayGuard(relayLimits{
			minRate: 1024, rateGrace: time.Minute,
		}, func() { t.Error("cut a transfer still inside its grace window") })
		defer g.stop()
		if !g.note(16) {
			t.Fatal("the rate floor applied before its grace window elapsed")
		}
	})

	// A stalled upstream blocks inside Read, so only the timer can end
	// it, and what it ends is the upstream context.
	t.Run("idle deadline", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		g := newRelayGuard(relayLimits{idle: 20 * time.Millisecond}, cancel)
		defer g.stop()
		select {
		case <-ctx.Done():
		case <-time.After(2 * time.Second):
			t.Fatal("the idle deadline never fired")
		}
		if g.note(1) {
			t.Fatal("a transfer continued after its idle deadline fired")
		}
	})

	// The order the relay loops depend on: a cut is observed by note, not
	// inferred from the read error, so a trip is never silent.
	//
	// Both loops call note(n) before they examine readErr. When the idle
	// timer fires it marks the guard stopped *and then* cancels, so the
	// read that returns because of that cancel finds a stopped guard and
	// note answers false - which is the branch that logs the reason. Were
	// the order reversed, or note called only when readErr was nil, a
	// timed-out relay would end with no line explaining it.
	t.Run("a trip is observable after the read it cancelled", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		g := newRelayGuard(relayLimits{idle: 20 * time.Millisecond}, cancel)
		defer g.stop()
		select {
		case <-ctx.Done():
		case <-time.After(2 * time.Second):
			t.Fatal("the idle deadline never fired")
		}
		// The blocked read now returns with a context error and zero
		// bytes, exactly as it does in the relay loops.
		if g.note(0) {
			t.Fatal("note answered true after the guard had tripped")
		}
		if g.reason() == "" {
			t.Fatal("a tripped guard reported no reason, so the cut would log nothing")
		}
		if _, elapsed := g.stats(); elapsed <= 0 {
			t.Fatal("stats reported no elapsed time for the operator's log line")
		}
	})

	// A listener who stops reading blocks the relay's write. That is the
	// listener's pace, not the host's, and charging it to the host cuts a
	// healthy transfer - a paused media element does exactly this once
	// its buffer fills.
	t.Run("a blocked write is not the upstream going idle", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		g := newRelayGuard(relayLimits{idle: 40 * time.Millisecond}, cancel)
		defer g.stop()
		if !g.note(1024) {
			t.Fatal("the first read was refused")
		}
		// Far longer than the idle window, spent writing.
		done := g.writing()
		time.Sleep(200 * time.Millisecond)
		done()
		if ctx.Err() != nil {
			t.Fatal("a slow listener got the upstream cut and the host blamed")
		}
		if !g.note(1024) {
			t.Fatalf("the transfer was cut during a write: %s", g.reason())
		}
	})

	// Same argument for the rate floor: a transfer that delivered its
	// bytes promptly must not fall under the floor because the listener
	// took a long time to accept them.
	t.Run("a blocked write is not a slow upstream", func(t *testing.T) {
		g := newRelayGuard(relayLimits{
			minRate:    1024,
			rateGrace:  10 * time.Millisecond,
			relayStart: time.Now(),
		}, func() { t.Error("cut a transfer for the listener's slowness") })
		defer g.stop()
		if !g.note(4096) {
			t.Fatal("the first read was refused")
		}
		done := g.writing()
		time.Sleep(150 * time.Millisecond)
		done()
		// Without the bracket the elapsed time would now dwarf the bytes
		// and the floor would trip.
		if !g.note(4096) {
			t.Fatalf("the rate floor charged the listener's pace to the host: %s", g.reason())
		}
	})

	// Bytes arriving push the deadline out, or a healthy stream would be
	// cut every idle interval regardless of what it was sending.
	t.Run("idle deadline resets on progress", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		g := newRelayGuard(relayLimits{idle: 80 * time.Millisecond}, cancel)
		defer g.stop()
		for i := 0; i < 5; i++ {
			time.Sleep(30 * time.Millisecond)
			if !g.note(1) {
				t.Fatalf("progress at %d did not hold off the idle deadline", i)
			}
		}
		if ctx.Err() != nil {
			t.Fatal("the idle deadline fired against a stream that kept sending")
		}
	})
}
