// Package events is the WebSocket event hub: it turns the service's
// lossy change-wakeup hints into coalesced, per-connection invalidation
// frames. Frames carry no data (clients pull the sync endpoints), so a
// connection's pending state is a handful of booleans instead of a
// queue: overflow is impossible by construction, and a slow client
// costs those flags, not memory.
package events

import (
	"context"
	"sync"
	"sync/atomic"
	"time"
)

// Topics the hub fans out. The player and radio topics have no cursor:
// they invalidate ephemeral state, which always answers current truth.
const (
	TopicCatalog = "catalog"
	TopicUser    = "user"
	TopicPlayer  = "player"
	// TopicRadio says artwork for an announced title has landed. A
	// client not tuned to a station ignores it.
	TopicRadio = "radio"
)

// Frame is one server-to-client event frame, JSON-shaped per the
// contract (WsEventFrame in the spec).
type Frame struct {
	Type  string `json:"type"`
	Topic string `json:"topic,omitempty"`
}

// Frame types.
const (
	TypeInvalidate = "invalidate"
	TypeResync     = "resync"
)

// wakeSource is the service-side seam the hub consumes: coalesced
// wakeup hints for catalog changes and per-user server events.
type wakeSource interface {
	CatalogWakeups() <-chan struct{}
	UserEventWakeups() <-chan string
}

// coalesceWindow batches invalidations so a bulk edit becomes a few
// frames, not thousands.
const coalesceWindow = 250 * time.Millisecond

// Hub owns the connection registry and the coalescer.
type Hub struct {
	src wakeSource

	// radioDirty is a cover landing waiting for the next tick. A flag
	// rather than a channel because the frame carries no data: many
	// landings inside one window are one invalidation.
	radioDirty atomic.Bool

	mu    sync.Mutex
	conns map[*Conn]struct{}
}

// New builds a hub over the service's wakeup channels.
func New(src wakeSource) *Hub {
	return &Hub{src: src, conns: make(map[*Conn]struct{})}
}

// Conn is one subscribed connection. The transport layer owns the
// socket; the hub only marks pending topics and wakes it.
type Conn struct {
	userID string
	topics map[string]bool // nil means every topic

	mu      sync.Mutex
	pending struct {
		catalog bool
		user    bool
		player  bool
		radio   bool
		resync  bool
	}
	wake chan struct{}
}

// Register adds a connection for the given user. topics of zero length
// subscribes to everything; unknown names are dropped (ignored per the
// contract). A list with no recognized names also subscribes to
// everything: spurious invalidations are harmless by the model, while a
// connection that looks live but hears nothing is silent staleness.
func (h *Hub) Register(userID string, topics []string) *Conn {
	c := &Conn{userID: userID, wake: make(chan struct{}, 1)}
	if len(topics) > 0 {
		c.topics = make(map[string]bool, len(topics))
		for _, t := range topics {
			if t == TopicCatalog || t == TopicUser || t == TopicPlayer || t == TopicRadio {
				c.topics[t] = true
			}
		}
		if len(c.topics) == 0 {
			c.topics = nil
		}
	}
	h.mu.Lock()
	h.conns[c] = struct{}{}
	h.mu.Unlock()
	return c
}

// Unregister removes the connection; safe to call more than once.
func (h *Hub) Unregister(c *Conn) {
	h.mu.Lock()
	delete(h.conns, c)
	h.mu.Unlock()
}

// wants reports whether the connection subscribed to the topic.
func (c *Conn) wants(topic string) bool {
	return c.topics == nil || c.topics[topic]
}

// Mark queues an invalidation (or, for TypeResync, a resync) and wakes
// the writer. Invalidations for unsubscribed topics are dropped.
func (c *Conn) Mark(frameType, topic string) {
	if frameType == TypeInvalidate && !c.wants(topic) {
		return
	}
	c.mu.Lock()
	switch {
	case frameType == TypeResync:
		c.pending.resync = true
	case topic == TopicCatalog:
		c.pending.catalog = true
	case topic == TopicUser:
		c.pending.user = true
	case topic == TopicPlayer:
		c.pending.player = true
	case topic == TopicRadio:
		c.pending.radio = true
	}
	c.mu.Unlock()
	select {
	case c.wake <- struct{}{}:
	default:
	}
}

// Wake signals that pending frames exist.
func (c *Conn) Wake() <-chan struct{} { return c.wake }

// TakePending returns and clears the queued frames, in send order.
func (c *Conn) TakePending() []Frame {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []Frame
	if c.pending.resync {
		out = append(out, Frame{Type: TypeResync})
	}
	if c.pending.catalog {
		out = append(out, Frame{Type: TypeInvalidate, Topic: TopicCatalog})
	}
	if c.pending.user {
		out = append(out, Frame{Type: TypeInvalidate, Topic: TopicUser})
	}
	if c.pending.player {
		out = append(out, Frame{Type: TypeInvalidate, Topic: TopicPlayer})
	}
	if c.pending.radio {
		out = append(out, Frame{Type: TypeInvalidate, Topic: TopicRadio})
	}
	c.pending.catalog, c.pending.user, c.pending.player = false, false, false
	c.pending.radio, c.pending.resync = false, false
	return out
}

// Run consumes wakeup hints and flushes coalesced invalidations to the
// registered connections. It runs supervised for the process lifetime
// and returns nil on context cancel.
func (h *Hub) Run(ctx context.Context) error {
	catalogDirty := false
	dirtyUsers := make(map[string]struct{})
	ticker := time.NewTicker(coalesceWindow)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-h.src.CatalogWakeups():
			catalogDirty = true
		case uid := <-h.src.UserEventWakeups():
			dirtyUsers[uid] = struct{}{}
		case <-ticker.C:
			radioDirty := h.radioDirty.Swap(false)
			if !catalogDirty && len(dirtyUsers) == 0 && !radioDirty {
				continue
			}
			h.flush(catalogDirty, dirtyUsers, radioDirty)
			catalogDirty = false
			clear(dirtyUsers)
		}
	}
}

// MarkPlayerAll queues a player-topic invalidation on every
// connection. Lifecycle changes are rare and the pull applies
// visibility, so fanning to everyone is cheap and leaks nothing.
func (h *Hub) MarkPlayerAll() { h.markAll(TopicPlayer) }

// MarkRadioAll queues a radio-topic invalidation on every connection at
// the next tick. Coalesced rather than sent on the spot: covers land one
// detached worker at a time, and every landing reaches every connection.
func (h *Hub) MarkRadioAll() { h.radioDirty.Store(true) }

func (h *Hub) markAll(topic string) {
	h.mu.Lock()
	conns := make([]*Conn, 0, len(h.conns))
	for c := range h.conns {
		conns = append(conns, c)
	}
	h.mu.Unlock()
	for _, c := range conns {
		c.Mark(TypeInvalidate, topic)
	}
}

func (h *Hub) flush(catalog bool, users map[string]struct{}, radio bool) {
	h.mu.Lock()
	conns := make([]*Conn, 0, len(h.conns))
	for c := range h.conns {
		conns = append(conns, c)
	}
	h.mu.Unlock()
	for _, c := range conns {
		if catalog {
			c.Mark(TypeInvalidate, TopicCatalog)
		}
		if _, ok := users[c.userID]; ok {
			c.Mark(TypeInvalidate, TopicUser)
		}
		if radio {
			c.Mark(TypeInvalidate, TopicRadio)
		}
	}
}
