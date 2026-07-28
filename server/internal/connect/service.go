package connect

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// MediaResolver turns queue pids into playable media for endpoints.
// Implementations enforce the user's library visibility on every call.
type MediaResolver interface {
	// Entries hydrates queue entries for the pids, in order. An
	// invisible or unknown pid fails the whole call with ErrNotFound
	// (a queue is one decision, never a partial load).
	Entries(ctx context.Context, userID string, pids []string) ([]QueueEntry, error)
	// StreamItems builds device-fetchable media items against the
	// given base URL, minting tokens that live at least ttl. kind is
	// the endpoint kind, which picks format floors (DLNA renderers
	// get mp3 or passthrough, the jukebox gets wav).
	StreamItems(ctx context.Context, userID string, entries []QueueEntry, kind, base string, ttl time.Duration) ([]MediaItem, error)
	// Timeline renders the whole queue as one gapless stream when the
	// streaming engine supports it and every entry is eligible. A nil
	// result without error means "not available; use StreamItems".
	Timeline(ctx context.Context, userID string, entries []QueueEntry, crossfade float64, base string) (*TimelineMedia, error)
}

// ProgressSink is the write-through to per-user playback state. Only
// remote sessions write through it: a mirror session's owning client
// checkpoints itself over REST, and double-writing would fight it.
type ProgressSink interface {
	Progress(userID, pid string, positionMS int64)
	Checkpoint(ctx context.Context, userID, pid string, positionMS int64)
	SetQueue(ctx context.Context, userID string, pids []string)
	Listen(ctx context.Context, userID, pid string, msPlayed int64, startedAt time.Time)
}

// Bases are the URL prefixes endpoints fetch media from, in the order
// sessions try them per endpoint kind.
type Bases struct {
	// Public is the configured externally reachable base (may be
	// HTTPS; cast devices need a publicly trusted certificate for it).
	Public string
	// LAN is the auto-detected plain-HTTP LAN base; the zero-TLS cast
	// path and the DLNA default.
	LAN string
	// Loopback serves the jukebox on the server's own interface.
	Loopback string
}

// forKind returns the candidate bases for an endpoint kind, first
// preference first.
func (b Bases) forKind(kind string) []string {
	var out []string
	add := func(s string) {
		if s == "" {
			return
		}
		for _, have := range out {
			if have == s {
				return
			}
		}
		out = append(out, s)
	}
	switch kind {
	case KindDLNA:
		// Most renderers speak no TLS at all: plain HTTP always.
		add(b.LAN)
		add(b.Loopback)
	case KindJukebox:
		add(b.Loopback)
		add(b.LAN)
	default:
		add(b.Public)
		add(b.LAN)
	}
	return out
}

// Config wires the service.
type Config struct {
	Store    *db.DB
	Group    *supervise.Group
	Resolver MediaResolver
	Sink     ProgressSink
	Bases    Bases
	// InvalidatePlayer fans a player-topic invalidation out to every
	// connected client (lifecycle changes only).
	InvalidatePlayer func()
	// SharedOutputsAllowed gates control of shared device endpoints
	// (cast targets, DLNA renderers, the jukebox) per user; nil allows
	// everyone. A caller's own client endpoints are never gated.
	SharedOutputsAllowed func(userID string) bool
	Logger               logger
	Now                  func() time.Time
}

type logger interface {
	Info(msg string, args ...any)
	Warn(msg string, args ...any)
}

type nopLogger struct{}

func (nopLogger) Info(string, ...any) {}
func (nopLogger) Warn(string, ...any) {}

// Timings. The routing deadline bounds a routed command waiting on a
// client; the report grace keeps a just-ended session's stale reports
// from spawning a ghost; checkpoints bound how stale a crash-recovered
// row can be.
const (
	routeDeadline      = 10 * time.Second
	reportGrace        = 3 * time.Second
	checkpointInterval = 5 * time.Second
	watcherTick        = time.Second
	sessionKeepPerUser = 5
	maxQueueItems      = 500
)

// Service is the connect core: registry + sessions + command routing.
type Service struct {
	cfg Config
	reg *Registry

	mu         sync.Mutex
	sessions   map[string]*session
	byEndpoint map[string]string // endpoint id -> active session id
	watchers   map[*ClientLink]*watchState
	routes     map[string]*route  // routed endpoint-cmd id -> waiter
	recentEnds map[string]endMark // endpoint id -> last server-ended session
	// pendingLoads marks endpoints with a routed load in flight whose
	// session is not installed yet; reports for them are dropped (the
	// client re-reports within seconds) instead of creating ghosts.
	pendingLoads map[string]string // endpoint id -> session id
	driverGen    map[string]int    // session id -> driver generation
	listen       map[string]*listenTrack
	routeSeq     uint64
}

// watchState tracks one connection's watch and the queue version it
// last received entries for (state frames omit the queue unless it
// changed).
type watchState struct {
	sessionID string
	sentQV    int64
	sentAny   bool
}

type route struct {
	done chan routeResult
}

type routeResult struct {
	ok      bool
	code    string
	message string
}

type endMark struct {
	sessionID string
	at        time.Time
}

// listenTrack accumulates played milliseconds for one remote session's
// current entry.
type listenTrack struct {
	pid       string
	startedAt time.Time
	playedMS  int64
	lastPos   int64
}

// New builds the service and boots crash recovery (active rows from a
// previous process flip inactive; their state stays as history).
func New(ctx context.Context, cfg Config) (*Service, error) {
	if cfg.Logger == nil {
		cfg.Logger = nopLogger{}
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.InvalidatePlayer == nil {
		cfg.InvalidatePlayer = func() {}
	}
	if err := cfg.Store.DeactivatePlaybackSessions(ctx); err != nil {
		return nil, err
	}
	reg := NewRegistry(cfg.Store, cfg.Now)
	if err := reg.RestorePersisted(ctx); err != nil {
		return nil, err
	}
	s := &Service{
		cfg:          cfg,
		reg:          reg,
		sessions:     make(map[string]*session),
		byEndpoint:   make(map[string]string),
		watchers:     make(map[*ClientLink]*watchState),
		routes:       make(map[string]*route),
		recentEnds:   make(map[string]endMark),
		pendingLoads: make(map[string]string),
		driverGen:    make(map[string]int),
		listen:       make(map[string]*listenTrack),
	}
	return s, nil
}

// Registry exposes the endpoint registry for discovery packages.
func (s *Service) Registry() *Registry { return s.reg }

// Run is the service's supervised housekeeping loop: watcher pushes
// and periodic checkpoints for playing sessions, and session-history
// pruning. Returns nil on context cancel.
func (s *Service) Run(ctx context.Context) error {
	tick := time.NewTicker(watcherTick)
	defer tick.Stop()
	lastCheckpoint := s.cfg.Now()
	lastPrune := s.cfg.Now()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-tick.C:
			now := s.cfg.Now()
			s.pushPlayingToWatchers()
			if now.Sub(lastCheckpoint) >= checkpointInterval {
				lastCheckpoint = now
				s.checkpointPlaying(ctx)
			}
			if now.Sub(lastPrune) >= time.Hour {
				lastPrune = now
				if err := s.cfg.Store.PrunePlaybackSessions(ctx, sessionKeepPerUser); err != nil {
					s.cfg.Logger.Warn("pruning playback sessions", "err", err)
				}
			}
		}
	}
}

// sharedAllowed consults the shared-outputs permission gate.
func (s *Service) sharedAllowed(userID string) bool {
	if s.cfg.SharedOutputsAllowed == nil {
		return true
	}
	return s.cfg.SharedOutputsAllowed(userID)
}

func newSessionID() string {
	return "ps-" + ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
}

// visibleSession reports whether the user may see (and so control) the
// session: their own always, others' exactly on shared endpoints.
func (s *Service) visibleSessionLocked(userID string, sess *session) bool {
	if sess.ownerID == userID {
		return true
	}
	ep, ok := s.reg.Lookup(userID, sess.endpointID)
	return ok && ep.Shared
}

// snapshotLocked builds a public snapshot with the position
// extrapolated to now.
func (s *Service) snapshotLocked(sess *session) Session {
	now := s.cfg.Now()
	endpointName := ""
	if ep, ok := s.reg.Lookup(sess.ownerID, sess.endpointID); ok {
		endpointName = ep.Name
	}
	return Session{
		ID:           sess.id,
		EndpointID:   sess.endpointID,
		EndpointName: endpointName,
		OwnerUserID:  sess.ownerID,
		OwnerName:    sess.ownerName,
		Authority:    sess.authority,
		Playing:      sess.q.Playing,
		Index:        sess.q.Index,
		PositionMS:   sess.q.extrapolate(now),
		PositionAt:   now,
		Rate:         sess.q.Rate,
		Volume:       sess.q.Volume,
		Repeat:       sess.q.Repeat,
		Shuffle:      sess.q.Shuffle,
		QueueVersion: sess.q.QueueVersion,
		Entries:      sess.q.Entries,
		Ended:        sess.ended,
		UpdatedAt:    sess.updatedAt,
	}
}

// Endpoints lists the endpoints visible to the user, with active
// session ids attached.
func (s *Service) Endpoints(userID string) []Endpoint {
	return s.reg.Visible(userID)
}

// ActiveSessionID returns the visible active session on an endpoint.
func (s *Service) ActiveSessionID(userID, endpointID string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, ok := s.byEndpoint[endpointID]
	if !ok {
		return ""
	}
	sess, ok := s.sessions[id]
	if !ok || !s.visibleSessionLocked(userID, sess) {
		return ""
	}
	return id
}

// Sessions lists the sessions visible to the user, most recent
// activity first.
func (s *Service) Sessions(userID string) []Session {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []Session
	for _, sess := range s.sessions {
		if s.visibleSessionLocked(userID, sess) {
			out = append(out, s.snapshotLocked(sess))
		}
	}
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j].UpdatedAt.After(out[j-1].UpdatedAt); j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// SessionHistory reads back the caller's ended sessions, newest
// first, as the state each stopped in.
//
// Scoped by user id alone: the shared-endpoint visibility that lets
// housemates see each other's live sessions has no counterpart here,
// and reusing it would hand someone else's finished queue to whoever
// happens to be near the speaker.
func (s *Service) SessionHistory(ctx context.Context, userID string) ([]EndedSession, error) {
	rows, err := s.cfg.Store.EndedPlaybackSessions(ctx, userID, sessionKeepPerUser)
	if err != nil {
		return nil, err
	}
	out := make([]EndedSession, 0, len(rows))
	for _, row := range rows {
		var ps persistedState
		if err := json.Unmarshal([]byte(row.State), &ps); err != nil {
			// One undecodable checkpoint is one lost resume, not a
			// reason to answer nothing for the other four.
			s.cfg.Logger.Warn("decoding ended playback session", "session", row.ID, "err", err)
			continue
		}
		e := EndedSession{
			ID:         row.ID,
			EndpointID: row.EndpointID,
			Authority:  row.Authority,
			Index:      ps.Index,
			PositionMS: ps.PositionMS,
			// endSessionLocked sets q.PositionAt and updatedAt from
			// one instant, and the row's timestamp is that write, so
			// updated_at_ns is faithfully when the final position was
			// true. persistedState carries no timestamp of its own.
			PositionAt: time.Unix(0, row.UpdatedAtNS),
			Rate:       ps.Rate,
			Repeat:     ps.Repeat,
			Shuffle:    ps.Shuffle,
		}
		if e.Rate <= 0 {
			e.Rate = 1
		}
		// The endpoint may be long gone — a client endpoint goes with
		// its connection — so the name is absent rather than an error.
		if ep, ok := s.reg.Lookup(userID, row.EndpointID); ok {
			e.EndpointName = ep.Name
		}
		for _, pe := range ps.Entries {
			e.Entries = append(e.Entries, QueueEntry(pe))
		}
		out = append(out, e)
	}
	return out, nil
}

// Session returns one visible session.
func (s *Service) Session(userID, sessionID string) (Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(userID, sess) {
		return Session{}, ErrNotFound
	}
	return s.snapshotLocked(sess), nil
}

// CreateSession loads a queue onto an endpoint and starts a session
// there ("play on the kitchen speaker").
func (s *Service) CreateSession(ctx context.Context, userID, userName, endpointID string, pids []string, index int, positionMS int64, play bool) (Session, error) {
	if len(pids) == 0 || len(pids) > maxQueueItems {
		return Session{}, InvalidError{Msg: fmt.Sprintf("queue must hold 1 to %d items", maxQueueItems)}
	}
	if index < 0 || index >= len(pids) {
		return Session{}, InvalidError{Msg: "index is outside the queue"}
	}
	if positionMS < 0 {
		return Session{}, InvalidError{Msg: "positionMs must not be negative"}
	}
	ep, ok := s.reg.Lookup(userID, endpointID)
	if !ok {
		return Session{}, ErrNotFound
	}
	if ep.Shared && !s.sharedAllowed(userID) {
		return Session{}, ErrForbidden
	}
	entries, err := s.cfg.Resolver.Entries(ctx, userID, pids)
	if err != nil {
		return Session{}, err
	}

	sess := &session{
		id:         newSessionID(),
		ownerID:    userID,
		ownerName:  userName,
		endpointID: endpointID,
		authority:  AuthorityRemote,
		q: queueState{
			Entries:      entries,
			Index:        index,
			PositionMS:   positionMS,
			PositionAt:   s.cfg.Now(),
			Playing:      play,
			Rate:         1,
			Repeat:       "off",
			QueueVersion: 1,
		},
		createdAt: s.cfg.Now(),
		updatedAt: s.cfg.Now(),
	}

	if ep.Kind == KindClient {
		sess.authority = AuthorityMirror
		s.markLoadPending(endpointID, sess.id)
		err := s.loadOnClient(ctx, sess.id, pids, endpointID, index, positionMS, play)
		if err != nil {
			s.clearLoadPending(endpointID)
			return Session{}, err
		}
		snap := s.adoptSession(ctx, sess)
		s.clearLoadPending(endpointID)
		return snap, nil
	}
	if err := s.loadOnDevice(ctx, sess, ep, entries, index, positionMS, play); err != nil {
		return Session{}, err
	}
	return s.adoptSession(ctx, sess), nil
}

// adoptSession installs a successfully loaded session as its
// endpoint's active one, ending any predecessor.
func (s *Service) adoptSession(ctx context.Context, sess *session) Session {
	s.mu.Lock()
	if oldID, ok := s.byEndpoint[sess.endpointID]; ok && oldID != sess.id {
		if old, ok := s.sessions[oldID]; ok {
			s.endSessionLocked(ctx, old, false)
		}
	}
	s.sessions[sess.id] = sess
	s.byEndpoint[sess.endpointID] = sess.id
	snap := s.snapshotLocked(sess)
	s.mu.Unlock()

	s.persist(ctx, sess, true)
	s.cfg.Sink.SetQueue(ctx, sess.ownerID, entryPIDs(snap.Entries))
	s.cfg.InvalidatePlayer()
	return snap
}

func entryPIDs(entries []QueueEntry) []string {
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.PID
	}
	return out
}

// loadOnDevice dials the endpoint's driver and loads media, trying
// the advertise bases in order (the first base the device actually
// accepts wins; a cast device that cannot fetch HTTPS falls to the
// LAN base).
func (s *Service) loadOnDevice(ctx context.Context, sess *session, ep Endpoint, entries []QueueEntry, index int, positionMS int64, play bool) error {
	dial, ok := s.reg.dialer(ep.ID)
	if !ok {
		return ErrEndpointOffline
	}
	driver, err := dial(ctx)
	if err != nil {
		s.reg.MarkDeviceOffline(ep.ID)
		return fmt.Errorf("%w: %v", ErrEndpointOffline, err)
	}

	bases := s.cfg.Bases.forKind(ep.Kind)
	if len(bases) == 0 {
		driver.Close()
		return InvalidError{Msg: "no advertise base is configured for casting"}
	}
	ttl := mediaTTL(entries)
	ownerID := sess.ownerID
	var lastErr error
	for _, base := range bases {
		var tm *TimelineMedia
		if ep.Kind == KindCast && len(entries) > 1 {
			tm, err = s.cfg.Resolver.Timeline(ctx, ownerID, entries, 0, base)
			if err != nil {
				s.cfg.Logger.Warn("timeline mint failed; loading per item", "err", err)
				tm = nil
			}
		}
		if tm != nil {
			abs := timelineAbsoluteMS(tm, index, positionMS)
			if err := driver.Load(ctx, []MediaItem{tm.Item}, 0, abs, play); err != nil {
				lastErr = err
				continue
			}
			s.mu.Lock()
			sess.timeline = tm
			s.mu.Unlock()
		} else {
			items, err := s.cfg.Resolver.StreamItems(ctx, ownerID, entries, ep.Kind, base, ttl)
			if err != nil {
				driver.Close()
				return err
			}
			if err := driver.Load(ctx, items, index, positionMS, play); err != nil {
				lastErr = err
				continue
			}
			s.mu.Lock()
			sess.timeline = nil
			s.mu.Unlock()
		}
		lastErr = nil
		break
	}
	if lastErr != nil {
		driver.Close()
		return fmt.Errorf("%w: %v", ErrEndpointOffline, lastErr)
	}
	s.attachDriver(sess, driver)
	return nil
}

// markLoadPending and clearLoadPending bracket a routed load: while
// set, session reports from that endpoint are dropped rather than
// allowed to create a session the load is about to install anyway.
func (s *Service) markLoadPending(endpointID, sessionID string) {
	s.mu.Lock()
	s.pendingLoads[endpointID] = sessionID
	s.mu.Unlock()
}

func (s *Service) clearLoadPending(endpointID string) {
	s.mu.Lock()
	delete(s.pendingLoads, endpointID)
	s.mu.Unlock()
}

// mediaTTL sizes token lifetimes so a queue can play through without
// its URLs expiring mid-listen.
func mediaTTL(entries []QueueEntry) time.Duration {
	var totalMS int64
	for _, e := range entries {
		totalMS += e.DurationMS
	}
	ttl := time.Duration(totalMS)*time.Millisecond + 15*time.Minute
	if ttl < 30*time.Minute {
		ttl = 30 * time.Minute
	}
	return ttl
}

// timelineAbsoluteMS maps (index, in-entry position) to the absolute
// timeline position.
func timelineAbsoluteMS(tm *TimelineMedia, index int, positionMS int64) int64 {
	if index < 0 || index >= len(tm.Boundaries) || tm.EnvelopeRate <= 0 {
		return positionMS
	}
	offsetMS := tm.Boundaries[index].OffsetSamples * 1000 / int64(tm.EnvelopeRate)
	return offsetMS + positionMS
}

// timelineLocate maps an absolute timeline position back to (index,
// in-entry position).
func timelineLocate(tm *TimelineMedia, absMS int64) (int, int64) {
	if tm.EnvelopeRate <= 0 || len(tm.Boundaries) == 0 {
		return 0, absMS
	}
	idx := 0
	for i, b := range tm.Boundaries {
		offsetMS := b.OffsetSamples * 1000 / int64(tm.EnvelopeRate)
		if absMS >= offsetMS {
			idx = i
		} else {
			break
		}
	}
	offsetMS := tm.Boundaries[idx].OffsetSamples * 1000 / int64(tm.EnvelopeRate)
	return idx, absMS - offsetMS
}

// attachDriver binds a live driver to the session and starts its
// event pump under supervision.
func (s *Service) attachDriver(sess *session, driver Driver) {
	pumpCtx, cancel := context.WithCancel(context.Background())
	// The session can already be reachable here (a transfer loads onto
	// a live session), so the field writes take the lock like every
	// reader does.
	s.mu.Lock()
	sess.driver = driver
	sess.driverCancel = cancel
	s.driverGen[sess.id]++
	gen := s.driverGen[sess.id]
	s.mu.Unlock()
	name := fmt.Sprintf("session-pump-%s-%d", sess.id, gen)
	s.cfg.Group.GoOnce(pumpCtx, name, func(ctx context.Context) error {
		for {
			select {
			case <-ctx.Done():
				return nil
			case ev, ok := <-driver.Events():
				if !ok {
					return nil
				}
				s.onDriverEvent(sess.id, gen, ev)
			}
		}
	})
}

// loadOnClient routes a load command to the owning client endpoint.
func (s *Service) loadOnClient(ctx context.Context, sessionID string, pids []string, endpointID string, index int, positionMS int64, play bool) error {
	link, ok := s.reg.link(endpointID)
	if !ok {
		return ErrEndpointOffline
	}
	cmd := wireEndpointCommand{
		Type:       "endpoint-cmd",
		SessionID:  sessionID,
		Verb:       "load",
		ItemPids:   pids,
		Index:      &index,
		PositionMS: &positionMS,
		Play:       &play,
	}
	res, err := s.routeToLink(ctx, link, cmd)
	if err != nil {
		return err
	}
	if !res.ok {
		return InvalidError{
			Msg:  fmt.Sprintf("client endpoint refused the load: %s", res.message),
			Code: res.code,
		}
	}
	return nil
}

// routeToLink sends an endpoint command and waits for its cmd-result
// within the routing deadline.
func (s *Service) routeToLink(ctx context.Context, link *ClientLink, cmd wireEndpointCommand) (routeResult, error) {
	s.mu.Lock()
	s.routeSeq++
	cmd.ID = fmt.Sprintf("e%d", s.routeSeq)
	r := &route{done: make(chan routeResult, 1)}
	s.routes[cmd.ID] = r
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.routes, cmd.ID)
		s.mu.Unlock()
	}()

	if !link.Send(cmd) {
		return routeResult{}, ErrEndpointOffline
	}
	timer := time.NewTimer(routeDeadline)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return routeResult{}, ctx.Err()
	case <-timer.C:
		return routeResult{}, ErrTimeout
	case res := <-r.done:
		return res, nil
	}
}

// jitterlessShuffle returns a shuffled copy of the queue keeping the
// current entry first (crypto/rand keeps the lint honest; quality is
// irrelevant here).
func shuffledEntries(entries []QueueEntry, currentIndex int) []QueueEntry {
	out := make([]QueueEntry, 0, len(entries))
	if currentIndex >= 0 && currentIndex < len(entries) {
		out = append(out, entries[currentIndex])
	}
	rest := make([]QueueEntry, 0, len(entries))
	for i, e := range entries {
		if i != currentIndex {
			rest = append(rest, e)
		}
	}
	for len(rest) > 0 {
		nBig, err := rand.Int(rand.Reader, big.NewInt(int64(len(rest))))
		n := 0
		if err == nil {
			n = int(nBig.Int64())
		}
		out = append(out, rest[n])
		rest = append(rest[:n], rest[n+1:]...)
	}
	return out
}

// Transfer moves a session's live playback to another endpoint.
func (s *Service) Transfer(ctx context.Context, userID, sessionID, targetEndpointID string) (Session, error) {
	s.mu.Lock()
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(userID, sess) {
		s.mu.Unlock()
		return Session{}, ErrNotFound
	}
	target, ok := s.reg.Lookup(sess.ownerID, targetEndpointID)
	if !ok {
		// The controller may also see the target under their own
		// visibility (a shared device); resolve against the caller too.
		target, ok = s.reg.Lookup(userID, targetEndpointID)
	}
	if !ok {
		s.mu.Unlock()
		return Session{}, ErrNotFound
	}
	if userID != sess.ownerID && !target.Shared {
		// Moving someone else's queue onto a private endpoint would
		// take it out of their sight.
		s.mu.Unlock()
		return Session{}, ErrForbidden
	}
	if target.Shared && !s.sharedAllowed(userID) {
		s.mu.Unlock()
		return Session{}, ErrForbidden
	}
	if target.ID == sess.endpointID {
		snap := s.snapshotLocked(sess)
		s.mu.Unlock()
		return snap, nil
	}
	now := s.cfg.Now()
	index := sess.q.Index
	positionMS := sess.q.extrapolate(now)
	play := sess.q.Playing
	entries := sess.q.Entries
	oldEndpoint := sess.endpointID
	oldDriver := sess.driver
	oldCancel := sess.driverCancel
	oldAuthority := sess.authority
	s.mu.Unlock()

	if target.Kind == KindClient {
		s.markLoadPending(target.ID, sessionID)
		if err := s.loadOnClient(ctx, sessionID, entryPIDs(entries), target.ID, index, positionMS, play); err != nil {
			s.clearLoadPending(target.ID)
			return Session{}, err
		}
	} else {
		if err := s.loadOnDevice(ctx, sess, target, entries, index, positionMS, play); err != nil {
			return Session{}, err
		}
	}

	// Rebind the session to the target BEFORE quieting the source: a
	// mirror source answers its stop with one last report, and that
	// report must fall into the ended-endpoint grace, never back onto
	// the session it would clobber.
	s.mu.Lock()
	if s.byEndpoint[oldEndpoint] == sess.id {
		delete(s.byEndpoint, oldEndpoint)
	}
	s.recentEnds[oldEndpoint] = endMark{sessionID: sess.id, at: s.cfg.Now()}
	if oldID, ok := s.byEndpoint[target.ID]; ok && oldID != sess.id {
		if old, ok := s.sessions[oldID]; ok {
			s.endSessionLocked(ctx, old, false)
		}
	}
	sess.endpointID = target.ID
	s.byEndpoint[target.ID] = sess.id
	if target.Kind == KindClient {
		sess.authority = AuthorityMirror
		sess.driver = nil
		sess.driverCancel = nil
		sess.timeline = nil
		// Fence the old device driver: a buffered trailing status from
		// its pump must not clobber the position the transfer carried.
		s.driverGen[sess.id]++
	} else {
		sess.authority = AuthorityRemote
	}
	sess.q.Index = index
	sess.q.PositionMS = positionMS
	sess.q.PositionAt = s.cfg.Now()
	sess.q.Playing = play
	sess.updatedAt = s.cfg.Now()
	snap := s.snapshotLocked(sess)
	delete(s.pendingLoads, target.ID)
	s.mu.Unlock()

	// The target is playing and owns the session; quiesce the source.
	if oldDriver != nil {
		stopCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := oldDriver.Stop(stopCtx); err != nil {
			s.cfg.Logger.Warn("stopping transfer source", "err", err)
		}
		cancel()
		if oldCancel != nil {
			oldCancel()
		}
		oldDriver.Close()
	} else if oldAuthority == AuthorityMirror {
		if link, ok := s.reg.link(oldEndpoint); ok {
			stop := wireEndpointCommand{Type: "endpoint-cmd", SessionID: sessionID, Verb: "stop"}
			if _, err := s.routeToLink(ctx, link, stop); err != nil {
				s.cfg.Logger.Warn("stopping transfer source client", "err", err)
			}
		}
	}

	if oldAuthority == AuthorityRemote && oldDriver != nil {
		s.cfg.Sink.Checkpoint(ctx, sess.ownerID, currentPID(snap), positionMS)
	}
	s.persist(ctx, sess, true)
	s.notifyWatchers(sess.id)
	s.cfg.InvalidatePlayer()
	return snap, nil
}

func currentPID(snap Session) string {
	if snap.Index >= 0 && snap.Index < len(snap.Entries) {
		return snap.Entries[snap.Index].PID
	}
	return ""
}

// End stops and removes a session (REST DELETE).
func (s *Service) End(ctx context.Context, userID, sessionID string) error {
	s.mu.Lock()
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(userID, sess) {
		s.mu.Unlock()
		return ErrNotFound
	}
	s.endSessionLocked(ctx, sess, true)
	s.mu.Unlock()
	// The teardown persists too, but from a supervised goroutine, and
	// the session leaves the live map synchronously — so between the
	// two it is in neither list. A caller that ends a session and reads
	// history back would race that window, and a process stopping
	// inside it would leave the row active with a stale position.
	// Writing here is what makes this call's own answer true; the
	// teardown's write lands on top with the same state.
	s.persist(ctx, sess, false)
	s.cfg.InvalidatePlayer()
	return nil
}

// endSessionLocked tears a session down: stops remote playback (async
// where it can block), notifies watchers terminally, and keeps the
// final row as history. Callers hold s.mu.
func (s *Service) endSessionLocked(ctx context.Context, sess *session, stopPlayback bool) {
	if sess.ended {
		return
	}
	sess.ended = true
	sess.q.PositionMS = sess.q.extrapolate(s.cfg.Now())
	sess.q.PositionAt = s.cfg.Now()
	sess.q.Playing = false
	sess.updatedAt = s.cfg.Now()
	delete(s.sessions, sess.id)
	if s.byEndpoint[sess.endpointID] == sess.id {
		delete(s.byEndpoint, sess.endpointID)
	}
	s.recentEnds[sess.endpointID] = endMark{sessionID: sess.id, at: s.cfg.Now()}
	driver := sess.driver
	cancel := sess.driverCancel
	sess.driver = nil
	sess.driverCancel = nil
	snap := s.snapshotLocked(sess)
	authority := sess.authority
	ownerID := sess.ownerID
	sessionID := sess.id
	lt := s.listen[sess.id]
	delete(s.listen, sess.id)
	delete(s.driverGen, sess.id)

	// Watcher notification and driver teardown must not hold the lock;
	// hand them to the supervised group.
	s.cfg.Group.GoOnce(context.Background(), "session-teardown-"+sessionID, func(bg context.Context) error {
		if driver != nil {
			if stopPlayback {
				stopCtx, c := context.WithTimeout(bg, 5*time.Second)
				if err := driver.Stop(stopCtx); err != nil {
					s.cfg.Logger.Warn("stopping ended session", "err", err)
				}
				c()
			}
			if cancel != nil {
				cancel()
			}
			driver.Close()
		} else if stopPlayback && authority == AuthorityMirror {
			if link, ok := s.reg.link(snap.EndpointID); ok {
				stop := wireEndpointCommand{Type: "endpoint-cmd", SessionID: sessionID, Verb: "stop"}
				if _, err := s.routeToLink(bg, link, stop); err != nil {
					s.cfg.Logger.Warn("stopping mirror session client", "err", err)
				}
			}
		}
		if authority == AuthorityRemote {
			if pid := currentPID(snap); pid != "" {
				s.cfg.Sink.Checkpoint(bg, ownerID, pid, snap.PositionMS)
			}
			s.flushListen(bg, ownerID, lt)
		}
		s.persist(bg, sess, false)
		s.notifyEnded(snap)
		return nil
	})
}

// flushListen reports an accumulated listen when it is worth counting.
func (s *Service) flushListen(ctx context.Context, userID string, lt *listenTrack) {
	if lt == nil || lt.playedMS < 2000 || lt.pid == "" {
		return
	}
	s.cfg.Sink.Listen(ctx, userID, lt.pid, lt.playedMS, lt.startedAt)
}

// persist checkpoints the session row.
func (s *Service) persist(ctx context.Context, sess *session, active bool) {
	s.mu.Lock()
	row := db.PlaybackSessionRow{
		ID:          sess.id,
		UserID:      sess.ownerID,
		EndpointID:  sess.endpointID,
		Authority:   sess.authority,
		State:       sess.persisted(),
		Active:      active && !sess.ended,
		CreatedAtNS: sess.createdAt.UnixNano(),
		UpdatedAtNS: sess.updatedAt.UnixNano(),
	}
	s.mu.Unlock()
	if err := s.cfg.Store.SavePlaybackSession(ctx, row); err != nil {
		s.cfg.Logger.Warn("checkpointing playback session", "err", err)
	}
}
