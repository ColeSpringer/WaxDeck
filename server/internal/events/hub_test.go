package events

import "testing"

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
