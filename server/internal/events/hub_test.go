package events

import (
	"context"
	"testing"
	"time"
)

// The subscribe-frame topic list is client input: unknown names are
// ignored, and a list left with no recognized names falls back to every
// topic rather than silently subscribing to nothing.
func TestRegisterTopicFiltering(t *testing.T) {
	h := New(nil)
	cases := []struct {
		name          string
		topics        []string
		catalog, user bool
	}{
		{"empty list means everything", nil, true, true},
		{"catalog only", []string{TopicCatalog}, true, false},
		{"unknown names are dropped", []string{TopicUser, "bogus"}, false, true},
		{"only unknown names fall back to everything", []string{"bogus", "custom"}, true, true},
	}
	for _, tc := range cases {
		c := h.Register("u1", tc.topics)
		if got := c.wants(TopicCatalog); got != tc.catalog {
			t.Errorf("%s: wants(catalog) = %v, want %v", tc.name, got, tc.catalog)
		}
		if got := c.wants(TopicUser); got != tc.user {
			t.Errorf("%s: wants(user) = %v, want %v", tc.name, got, tc.user)
		}
		h.Unregister(c)
	}
}

// Invalidations for unsubscribed topics are dropped at Mark time; a
// resync always queues.
func TestMarkRespectsSubscription(t *testing.T) {
	h := New(nil)
	c := h.Register("u1", []string{TopicCatalog})
	c.Mark(TypeInvalidate, TopicUser)
	if frames := c.TakePending(); len(frames) != 0 {
		t.Fatalf("unsubscribed invalidate queued: %+v", frames)
	}
	c.Mark(TypeInvalidate, TopicCatalog)
	c.Mark(TypeResync, "")
	frames := c.TakePending()
	if len(frames) != 2 || frames[0].Type != TypeResync || frames[1].Topic != TopicCatalog {
		t.Fatalf("frames = %+v, want resync then catalog invalidate", frames)
	}
}

// idleSource is a wakeSource that never wakes, so a test can run the
// coalescer without catalog or user traffic crossing it.
type idleSource struct{}

func (idleSource) CatalogWakeups() <-chan struct{} { return nil }
func (idleSource) UserEventWakeups() <-chan string { return nil }

// waitForFrames drains the connection until it has something, so a test
// asserts on the coalescer's tick rather than racing it.
func waitForFrames(t *testing.T, c *Conn) []Frame {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if frames := c.TakePending(); len(frames) > 0 {
			return frames
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("no frames arrived before the deadline")
	return nil
}

// The radio topic rides the same registry as the rest - subscribable by
// name, filtered when a connection asked for other topics only - and the
// same coalescer, so a burst of covers landing is one frame per socket.
func TestHubFansRadioOutAndRespectsTheSubscription(t *testing.T) {
	t.Parallel()
	h := New(idleSource{})
	all := h.Register("u1", nil)
	radioOnly := h.Register("u1", []string{TopicRadio})
	catalogOnly := h.Register("u2", []string{TopicCatalog})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	// Three covers landing inside one window, which is what a household
	// on three stations does after a restart.
	h.MarkRadioAll()
	h.MarkRadioAll()
	h.MarkRadioAll()

	want := []Frame{{Type: TypeInvalidate, Topic: TopicRadio}}
	for _, tc := range []struct {
		name string
		conn *Conn
	}{
		{"subscribed to everything", all},
		{"subscribed to radio", radioOnly},
	} {
		got := waitForFrames(t, tc.conn)
		if len(got) != 1 || got[0] != want[0] {
			t.Fatalf("%s: frames = %v, want %v", tc.name, got, want)
		}
	}
	if got := catalogOnly.TakePending(); got != nil {
		t.Fatalf("subscribed elsewhere: frames = %v, want none", got)
	}
	// Taken once: the flag clears with the frame, so a listener does not
	// re-poll on every later wake.
	if got := all.TakePending(); got != nil {
		t.Fatalf("frames after taking = %v, want none", got)
	}
}
