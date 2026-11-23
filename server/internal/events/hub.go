// Package events is the WebSocket event hub: it turns the service's
// lossy change-wakeup hints into coalesced, per-connection invalidation
// frames. Frames carry no entity data (clients pull the sync endpoints),
// so a connection's pending state is a handful of flags, one position
// and one bounded set of pids instead of a queue: a set that would
// outgrow its bound becomes a flag, which the frame carries in place of
// the names, so overflow is impossible by construction, and a slow
// client costs that fixed state, not memory.
package events

import (
	"context"
	"slices"
	"sync"
	"time"
)

// Topics the hub fans out. The player and radio topics have no cursor:
// they invalidate ephemeral state, which always answers current truth.
const (
	TopicCatalog = "catalog"
	TopicUser    = "user"
	TopicPlayer  = "player"
	// TopicRadio says a station's face has something new: a song, a
	// cover. A client not tuned to a station ignores it.
	TopicRadio = "radio"
)

// Frame is one server-to-client event frame, JSON-shaped per the
// contract (WsEventFrame in the spec).
type Frame struct {
	Type  string `json:"type"`
	Topic string `json:"topic,omitempty"`
	// Pids names the entities a catalog invalidation covers, sorted; nil
	// when it names none and on every other frame.
	Pids []string `json:"pids,omitempty"`
	// Unnamed says entities a catalog invalidation covers changed and are
	// not in Pids; never set beside Pids.
	Unnamed bool `json:"unnamed,omitempty"`
	// Unchanged says a catalog invalidation is only the answer to a
	// subscribing cursor that nothing in the catalog moved after; never
	// set beside Pids or Unnamed.
	Unchanged bool `json:"unchanged,omitempty"`
	// Since is the catalog position a catalog invalidation covers up to,
	// as a cursor the account may present when it subscribes again; empty
	// when it could not be had, and on every other frame.
	Since string `json:"since,omitempty"`
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
	// DrainCatalogChanges takes the pids of the entities behind the
	// catalog wakes since it was last asked; unnamed says entities
	// changed that it cannot name, and unknown that a wake had no row
	// behind it. None of the three is a wake with nothing to name.
	DrainCatalogChanges() (pids []string, unnamed, unknown bool)
	// CatalogPosition is where the catalog stream stands: every change up
	// to it is in the drain that follows or an earlier one. order sorts
	// positions, a newer one larger; cover is the newest show cover move
	// it covers; pos is handed back to CatalogFrameFor.
	CatalogPosition() (order, cover int64, pos string)
	// CatalogFrameFor reads the account as a catalog invalidation is
	// built: the cursor at pos for it, "" for none or when it could not be
	// read, and, for a frame with names, those of them it may be told, in
	// order; unnamed says it could not decide them all.
	CatalogFrameFor(userID, pos string, pids []string) (since string, named []string, unnamed bool)
	// CatalogChangesSince is what changed after a cursor the account
	// presented, named as a drain names it, with the position the answer
	// covers up to; unnamed for a cursor the stream cannot serve, and
	// unchanged when nothing in the catalog moved after one it can.
	CatalogChangesSince(userID, cursor string) (pids []string, unnamed, unchanged bool, order, cover int64, pos string)
}

// catalogMove is what one catalog invalidation stands for.
type catalogMove struct {
	// pids names the entities that changed, at most MaxCatalogPIDs.
	pids []string
	// unnamed says entities changed that pids does not name.
	unnamed bool
	// unknown says the catalog may be another one: names that share its
	// frame are dropped.
	unknown bool
	// unchanged says it is an answer to a subscribing cursor that nothing
	// in the catalog moved after.
	unchanged bool
	// order, cover and pos are the position the move covers up to, as
	// the source gave them; pos is empty for a move that has none.
	order int64
	cover int64
	pos   string
}

// MaxCatalogPIDs is the most entities one catalog invalidation names,
// the contract's bound, and so the most a connection holds pending.
const MaxCatalogPIDs = 64

// coalesceWindow batches invalidations so a bulk edit becomes a few
// frames, not thousands.
const coalesceWindow = 250 * time.Millisecond

// Hub owns the connection registry and the coalescer.
type Hub struct {
	src wakeSource

	// radioDirty holds the stations woken since the last tick: a set,
	// because many wakes on one station inside a window are one frame.
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
	hub       *Hub
	userID    string
	sessionID string          // the session that opened it; "" for none
	topics    map[string]bool // nil means every topic

	mu sync.Mutex
	// station is the radio station this client says it is listening to,
	// empty when it is listening to none, and tuned whether it has ever
	// said. Together they decide which connections a radio wake
	// reaches; see Tune.
	station string
	tuned   bool
	pending struct {
		catalog bool
		// catalogPids is what the owed catalog invalidation names, at most
		// MaxCatalogPIDs; catalogPlain says it names nothing, because the
		// names outgrew the set, could not all be had, or may be another
		// catalog's; catalogUnnamed says an entity changed that it does
		// not name.
		catalogPids    map[string]struct{}
		catalogPlain   bool
		catalogUnnamed bool
		// catalogPos is the newest position the owed catalog invalidation
		// covers up to, catalogOrder and catalogCover its order and cover
		// stamp; empty for none.
		catalogPos   string
		catalogOrder int64
		catalogCover int64
		// catalogStirred says something other than an unchanged answer
		// joined the owed catalog invalidation: a move, a plain mark or a
		// resync.
		catalogStirred bool
		user           bool
		player         bool
		radio          bool
		resync         bool
		// resyncCatalog is a resync of the catalog stream alone.
		resyncCatalog bool
	}
	wake chan struct{}

	endOnce sync.Once
	ended   chan struct{}
}

// Register adds a connection for the given user. topics of zero length
// subscribes to everything; unknown names are dropped (ignored per the
// contract). A list with no recognized names also subscribes to
// everything: spurious invalidations are harmless by the model, while a
// connection that looks live but hears nothing is silent staleness.
func (h *Hub) Register(userID, sessionID string, topics []string) *Conn {
	c := &Conn{hub: h, userID: userID, sessionID: sessionID, wake: make(chan struct{}, 1), ended: make(chan struct{})}
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

// Ended closes when the session that opened the connection has ended;
// the transport then closes the socket.
func (c *Conn) Ended() <-chan struct{} { return c.ended }

func (c *Conn) end() { c.endOnce.Do(func() { close(c.ended) }) }

// EndSessions ends the connections the named sessions opened.
func (h *Hub) EndSessions(ids ...string) {
	gone := make(map[string]bool, len(ids))
	for _, id := range ids {
		if id != "" {
			gone[id] = true
		}
	}
	h.endWhere(func(c *Conn) bool { return gone[c.sessionID] })
}

// EndUser ends every connection of the account except those keepSessionID
// opened ("" keeps none).
func (h *Hub) EndUser(userID, keepSessionID string) {
	h.endWhere(func(c *Conn) bool {
		return c.userID == userID && (keepSessionID == "" || c.sessionID != keepSessionID)
	})
}

// endWhere ends the matching connections outside the registry lock, as
// markAllAs marks them.
func (h *Hub) endWhere(match func(*Conn) bool) {
	h.mu.Lock()
	var hit []*Conn
	for c := range h.conns {
		if match(c) {
			hit = append(hit, c)
		}
	}
	h.mu.Unlock()
	for _, c := range hit {
		c.end()
	}
}

// wants reports whether the connection subscribed to the topic.
func (c *Conn) wants(topic string) bool {
	return c.topics == nil || c.topics[topic]
}

// Tune names the station this connection is listening to, replacing
// whatever it named before; an empty pid says it is listening to none.
// A connection that has tuned hears only its own station's wakes; one
// that never has keeps the topic's older contract and hears every
// station's, so a client that never sends the frame loses nothing.
func (c *Conn) Tune(stationPID string) {
	c.mu.Lock()
	c.station = stationPID
	c.tuned = true
	c.mu.Unlock()
}

// tunedTo reports whether a wake on one of the stations concerns
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

// Mark queues an invalidation, or for TypeResync a resync of the catalog
// stream or of every stream (an empty topic), and wakes the writer.
// Invalidations for unsubscribed topics are dropped. A catalog
// invalidation queued here has no names of its own and leaves alone
// those the frame holds; like a resync, it keeps the frame from saying
// it is unchanged. A resync drops them, and any that join the
// frame after it: the catalog they were read from may be gone. Names
// dropped that way are owed as unnamed.
func (c *Conn) Mark(frameType, topic string) {
	if frameType == TypeInvalidate && !c.wants(topic) {
		return
	}
	c.mu.Lock()
	switch {
	case frameType == TypeResync && topic == TopicCatalog:
		c.pending.resyncCatalog = true
		c.unnameCatalog()
	case frameType == TypeResync:
		c.pending.resync = true
		c.unnameCatalog()
	case topic == TopicCatalog:
		c.pending.catalog = true
		c.pending.catalogStirred = true
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

// unnameCatalog makes the catalog invalidation owed, or the next one
// queued before a take, name nothing and never say it is unchanged; names
// it held become unnamed. c.mu is held.
func (c *Conn) unnameCatalog() {
	c.pending.catalogStirred = true
	if len(c.pending.catalogPids) > 0 {
		c.pending.catalogUnnamed = true
	}
	c.pending.catalogPlain = true
	c.pending.catalogPids = nil
}

// markCatalog queues a catalog invalidation for the move and wakes the
// writer. Names add up until the frame is taken, and a move with nothing
// to name leaves them be. Past MaxCatalogPIDs, or sharing the frame with
// an unnamed or unknown move, they are dropped and the frame owed is
// unnamed. The frame covers up to the newest position of its moves: of
// two at one order, the one covering the newer show cover move (an
// answer queued after a live move may have read the older), else the
// later queued. It is unchanged only while every move it holds is.
func (c *Conn) markCatalog(m catalogMove) {
	if !c.wants(TopicCatalog) {
		return
	}
	c.mu.Lock()
	c.pending.catalog = true
	c.pending.catalogStirred = c.pending.catalogStirred || !m.unchanged
	if m.pos != "" && (c.pending.catalogPos == "" || m.order > c.pending.catalogOrder ||
		m.order == c.pending.catalogOrder && m.cover >= c.pending.catalogCover) {
		c.pending.catalogPos, c.pending.catalogOrder, c.pending.catalogCover = m.pos, m.order, m.cover
	}
	switch {
	case m.unnamed:
		c.unnameCatalog()
		c.pending.catalogUnnamed = true
	case m.unknown:
		c.unnameCatalog()
	case len(m.pids) == 0:
	case c.pending.catalogPlain:
		c.pending.catalogUnnamed = true
	default:
		if c.pending.catalogPids == nil {
			c.pending.catalogPids = make(map[string]struct{}, len(m.pids))
		}
		for _, pid := range m.pids {
			c.pending.catalogPids[pid] = struct{}{}
			if len(c.pending.catalogPids) > MaxCatalogPIDs {
				c.unnameCatalog()
				break
			}
		}
	}
	c.mu.Unlock()
	select {
	case c.wake <- struct{}{}:
	default:
	}
}

// MarkCatalogSince answers a subscribe that presented a catalog cursor:
// it asks the source what changed after it, here on the caller's
// goroutine, never the hub's loop, and queues that as a catalog move, so
// it follows the rules every move does and joins what is owed.
func (c *Conn) MarkCatalogSince(cursor string) {
	if !c.wants(TopicCatalog) {
		return
	}
	if c.hub.src == nil {
		c.Mark(TypeInvalidate, TopicCatalog)
		return
	}
	pids, unnamed, unchanged, order, cover, pos := c.hub.src.CatalogChangesSince(c.userID, cursor)
	if unnamed || len(pids) > MaxCatalogPIDs {
		pids, unnamed = nil, true
	}
	unchanged = unchanged && !unnamed && len(pids) == 0
	c.markCatalog(catalogMove{pids: pids, unnamed: unnamed, unchanged: unchanged, order: order, cover: cover, pos: pos})
}

// Wake signals that pending frames exist.
func (c *Conn) Wake() <-chan struct{} { return c.wake }

// TakePending returns and clears the queued frames, in send order. The
// catalog invalidation names, of what it covers, what the account may be
// told, asked as the frame is built: grants move under a live
// connection, and a pid outside them is never named. Names it could not
// decide are sent as unnamed; none it may be told, as the bare frame.
// The same read mints the account's cursor at the frame's position.
func (c *Conn) TakePending() []Frame {
	out, catalog, named, unnamed, unchanged, pos := c.takePending()
	if catalog < 0 {
		return out
	}
	f := &out[catalog]
	switch {
	case c.hub.src == nil:
		unnamed, named = unnamed || len(named) > 0, nil
	case pos != "" || len(named) > 0:
		var undecided bool
		f.Since, named, undecided = c.hub.src.CatalogFrameFor(c.userID, pos, named)
		unnamed = unnamed || undecided
	}
	switch {
	case unnamed:
		f.Unnamed = true
	case len(named) > 0:
		f.Pids = named
	default:
		f.Unchanged = unchanged
	}
	return out
}

// takePending is TakePending before the account is asked about: the
// frames, where the catalog invalidation sits among them (-1 for none),
// either the pids it may name, sorted, or that it left entities unnamed,
// whether it holds nothing but unchanged answers, and the position it
// covers up to.
func (c *Conn) takePending() (out []Frame, catalog int, named []string, unnamed, unchanged bool, pos string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	catalog = -1
	if c.pending.resync {
		out = append(out, Frame{Type: TypeResync})
	} else if c.pending.resyncCatalog {
		out = append(out, Frame{Type: TypeResync, Topic: TopicCatalog})
	}
	if c.pending.catalog {
		catalog = len(out)
		out = append(out, Frame{Type: TypeInvalidate, Topic: TopicCatalog})
		unnamed, unchanged, pos = c.pending.catalogUnnamed, !c.pending.catalogStirred, c.pending.catalogPos
		if !c.pending.catalogPlain {
			named = make([]string, 0, len(c.pending.catalogPids))
			for pid := range c.pending.catalogPids {
				named = append(named, pid)
			}
			slices.Sort(named)
		}
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
	c.pending.radio, c.pending.resync, c.pending.resyncCatalog = false, false, false
	c.pending.catalogPids, c.pending.catalogPlain, c.pending.catalogUnnamed = nil, false, false
	c.pending.catalogPos, c.pending.catalogOrder, c.pending.catalogCover, c.pending.catalogStirred = "", 0, 0, false
	return out, catalog, named, unnamed, unchanged, pos
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
			var moved catalogMove
			if catalogDirty {
				moved = h.catalogMoved()
			}
			h.flush(catalogDirty, moved, dirtyUsers, stations)
			catalogDirty = false
			clear(dirtyUsers)
		}
	}
}

// catalogMoved takes what the catalog invalidation about to be flushed
// stands for. A source that could not name everything, or named more
// than a frame holds, is unnamed with no pids; a wake with nothing to
// name (a genre's, which has no pid, or a spare one) has no names. It
// asks after the wake, so everything the wake stood for is in the
// answer, and first takes a wake still waiting: the source records a
// row before it wakes, so that wake's row is in this answer too, and
// left waiting it would cost a second frame for nothing. The position
// is read before the drain, so the drain holds every change up to it.
func (h *Hub) catalogMoved() catalogMove {
	select {
	case <-h.src.CatalogWakeups():
	default:
	}
	order, cover, pos := h.src.CatalogPosition()
	pids, unnamed, unknown := h.src.DrainCatalogChanges()
	if unnamed || len(pids) > MaxCatalogPIDs {
		return catalogMove{unnamed: true, unknown: unknown, order: order, cover: cover, pos: pos}
	}
	return catalogMove{pids: pids, unknown: unknown, order: order, cover: cover, pos: pos}
}

// MarkPlayerAll queues a player-topic invalidation on every
// connection. Lifecycle changes are rare and the pull applies
// visibility, so fanning to everyone is cheap and leaks nothing.
func (h *Hub) MarkPlayerAll() { h.markAll(TopicPlayer) }

// MarkRadio queues a radio-topic invalidation for the connections a wake
// on stationPID concerns, at the next tick: a song and its covers arrive
// moments apart. A wake with no station to name marks nothing.
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

// takeRadio drains the stations woken since the last tick.
func (h *Hub) takeRadio() map[string]struct{} {
	h.radioMu.Lock()
	defer h.radioMu.Unlock()
	stations := h.radioDirty
	h.radioDirty = nil
	return stations
}

// MarkCatalogReplaced asks every connection to re-mirror both streams:
// a replaced catalog breaks the catalog stream and moves what the user
// stream hydrates (play states, stars, playlists).
func (h *Hub) MarkCatalogReplaced() { h.markAllAs(TypeResync, "") }

func (h *Hub) markAll(topic string) { h.markAllAs(TypeInvalidate, topic) }

func (h *Hub) markAllAs(frameType, topic string) {
	h.mu.Lock()
	conns := make([]*Conn, 0, len(h.conns))
	for c := range h.conns {
		conns = append(conns, c)
	}
	h.mu.Unlock()
	for _, c := range conns {
		c.Mark(frameType, topic)
	}
}

// flush marks what the tick gathered on every connection; moved is
// catalogMoved's answer for the catalog invalidation.
func (h *Hub) flush(catalog bool, moved catalogMove, users map[string]struct{}, stations map[string]struct{}) {
	h.mu.Lock()
	conns := make([]*Conn, 0, len(h.conns))
	for c := range h.conns {
		conns = append(conns, c)
	}
	h.mu.Unlock()
	for _, c := range conns {
		if catalog {
			c.markCatalog(moved)
		}
		if _, ok := users[c.userID]; ok {
			c.Mark(TypeInvalidate, TopicUser)
		}
		// Checked only when a station woke: the connection's lock is not
		// worth taking four times a second for nothing.
		if len(stations) > 0 && c.tunedTo(stations) {
			c.Mark(TypeInvalidate, TopicRadio)
		}
	}
}
