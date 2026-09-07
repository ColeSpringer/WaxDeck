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

	// radioDirty holds the stations whose artwork landed since the last
	// tick. A set rather than a channel because the frame carries no
	// data: many landings on one station inside one window are one
	// invalidation.
	radioMu    sync.Mutex
	radioDirty map[string]struct{}

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

	mu sync.Mutex
	// station is the radio station this client says it is listening to,
	// empty when it is listening to none, and tuned whether it has ever
	// said. Together they decide which connections a cover landing
	// reaches; see Tune.
	station string
	tuned   bool
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

// Tune names the station this connection is listening to, replacing
// whatever it named before; an empty pid says it is listening to none.
// A connection that has tuned hears only its own station's landings. One
// that never has keeps the topic's older contract - every landing, which
// its subscription asked for before there was a frame to narrow it - so
// a client from before the frame, or one that never sends it, loses
// nothing it subscribed to.
func (c *Conn) Tune(stationPID string) {
	c.mu.Lock()
	c.station = stationPID
	c.tuned = true
	c.mu.Unlock()
}

// tunedTo reports whether a landing on one of the stations concerns
// this connection: yes for one that never tuned, and for one tuned to a
// station in the set.
func (c *Conn) tunedTo(stations map[string]struct{}) bool {
	c.mu.Lock()
	station, tuned := c.station, c.tuned
	c.mu.Unlock()
	if !tuned {
		return true
	}
	if station == "" {
		return false
	}
	_, ok := stations[station]
	return ok
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
			stations := h.takeRadio()
			if !catalogDirty && len(dirtyUsers) == 0 && len(stations) == 0 {
				continue
			}
			h.flush(catalogDirty, dirtyUsers, stations)
			catalogDirty = false
			clear(dirtyUsers)
		}
	}
}

// MarkPlayerAll queues a player-topic invalidation on every
// connection. Lifecycle changes are rare and the pull applies
// visibility, so fanning to everyone is cheap and leaks nothing.
func (h *Hub) MarkPlayerAll() { h.markAll(TopicPlayer) }

// MarkRadio queues a radio-topic invalidation for the connections a
// landing on stationPID concerns, at the next tick. Coalesced rather than
// sent on the spot: covers land one detached worker at a time, and a
// station whose stream announces a new title every three minutes can
// land two rungs of artwork for it. A landing with no station to name
// concerns nobody in particular and marks nothing.
func (h *Hub) MarkRadio(stationPID string) {
	if stationPID == "" {
		return
	}
	h.radioMu.Lock()
	defer h.radioMu.Unlock()
	if h.radioDirty == nil {
		h.radioDirty = map[string]struct{}{}
	}
	h.radioDirty[stationPID] = struct{}{}
}

// takeRadio drains the stations that landed since the last tick.
func (h *Hub) takeRadio() map[string]struct{} {
	h.radioMu.Lock()
	defer h.radioMu.Unlock()
	stations := h.radioDirty
	h.radioDirty = nil
	return stations
}

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

func (h *Hub) flush(catalog bool, users map[string]struct{}, stations map[string]struct{}) {
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
		// Checked only when something landed: the connection's lock is
		// not worth taking four times a second for nothing.
		if len(stations) > 0 && c.tunedTo(stations) {
			c.Mark(TypeInvalidate, TopicRadio)
		}
	}
}
