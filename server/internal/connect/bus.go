package connect

import (
	"context"
	"time"
)

// Client-to-server frame payloads, decoded by the transport layer and
// handed here. Shapes mirror the spec components (WsCommandFrame,
// WsRegisterEndpointFrame, WsCommandResultFrame, WsSessionReportFrame,
// WsWatchFrame).

// CommandArgs carries a controller command's arguments.
type CommandArgs struct {
	PositionMS *int64
	Volume     *float64
	Rate       *float64
	ItemPids   []string
	Index      *int
	Repeat     string
	Shuffle    *bool
}

// SessionReport is one state report from a playing client. The steady
// fields carry current truth on every report; ItemPids rides only
// queue changes (and the creating report). The reported queue version
// is an edge signal only; the server publishes its own counter.
type SessionReport struct {
	Playing    bool
	PositionMS int64
	Index      int
	Rate       *float64
	Volume     *float64
	ItemPids   []string
	Repeat     string
	Shuffle    *bool
}

// HandleRegister registers the connection as a controllable client
// endpoint and returns its endpoint id.
func (s *Service) HandleRegister(link *ClientLink, name string, volumeControl, rateControl bool) string {
	ep := s.reg.RegisterClient(link, name, volumeControl, rateControl)
	link.setRegistered(true)
	s.cfg.InvalidatePlayer()
	return ep.ID
}

// HandleCommand executes a controller command against a session. The
// returned snapshot (when non-nil) rides the ack.
func (s *Service) HandleCommand(ctx context.Context, link *ClientLink, sessionID, verb string, args CommandArgs) (*Session, error) {
	s.mu.Lock()
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(link.UserID, sess) {
		s.mu.Unlock()
		return nil, ErrNotFound
	}
	authority := sess.authority
	endpointID := sess.endpointID
	driver := sess.driver
	tm := sess.timeline
	owner := sess.ownerID
	s.mu.Unlock()

	if err := validateCommand(verb, args); err != nil {
		return nil, err
	}
	if ep, ok := s.reg.Lookup(owner, endpointID); ok {
		if ep.Shared && !s.sharedAllowed(link.UserID) {
			return nil, ErrForbidden
		}
		if verb == "set-volume" && !ep.VolumeControl {
			return nil, InvalidError{Msg: "this endpoint has no volume control"}
		}
		if verb == "set-rate" && !ep.RateControl {
			return nil, InvalidError{Msg: "this endpoint has no rate control"}
		}
	}
	if verb == "set-queue" && link.UserID != owner {
		// The sender's own reach first: the queue resolves for the owner,
		// which would put on the device, and name in the ack, a track the
		// sender cannot see.
		if _, err := s.cfg.Resolver.Entries(ctx, link.UserID, args.ItemPids); err != nil {
			return nil, err
		}
	}

	if authority == AuthorityMirror || driver == nil {
		if target, ok := s.reg.link(endpointID); ok && target == link {
			// The caller drives this session locally; routing the
			// command back to it over its own read loop would wait on
			// a result that loop cannot produce until the wait ends.
			return nil, InvalidError{Msg: "this client drives the session locally; apply it to the local player"}
		}
		if err := s.routeCommandToClient(ctx, sess.id, endpointID, verb, args); err != nil {
			return nil, err
		}
		if verb == "stop" {
			// A stop is the end of a mirror session, because that is
			// what it is on the client: it clears the queue as well as
			// silencing the engine, and forgets the session it was
			// reporting under. Left standing here, the row would keep
			// the endpoint looking busy in every picker while its
			// client reported into a session it could no longer be
			// told about - and every later routed verb would come back
			// `no-session`. Not another routed stop: the client has
			// already done it.
			snap, err := s.Session(link.UserID, sessionID)
			if err != nil {
				return nil, err
			}
			s.mu.Lock()
			if live, ok := s.sessions[sessionID]; ok {
				s.endSessionLocked(live, false)
			}
			s.mu.Unlock()
			s.cfg.InvalidatePlayer()
			snap.Playing = false
			return &snap, nil
		}
		// The client's own report updates the mirror; ack with the
		// current snapshot (slightly stale is honest here).
		snap, err := s.Session(link.UserID, sessionID)
		if err != nil {
			return nil, err
		}
		return &snap, nil
	}
	if err := s.applyRemoteCommand(ctx, sess, driver, tm, verb, args); err != nil {
		return nil, err
	}
	snap, err := s.Session(link.UserID, sessionID)
	if err != nil {
		return nil, err
	}
	s.notifyWatchers(sessionID)
	return &snap, nil
}

func validateCommand(verb string, args CommandArgs) error {
	switch verb {
	case "play", "pause", "stop", "next", "previous":
		return nil
	case "seek":
		if args.PositionMS == nil || *args.PositionMS < 0 {
			return InvalidError{Msg: "seek needs a non-negative positionMs"}
		}
	case "set-volume":
		if args.Volume == nil || *args.Volume < 0 || *args.Volume > 1 {
			return InvalidError{Msg: "set-volume needs volume between 0 and 1"}
		}
	case "set-rate":
		if args.Rate == nil || *args.Rate < minRate || *args.Rate > maxRate {
			return InvalidError{Msg: "set-rate needs a rate between 0.25 and 5"}
		}
	case "set-queue":
		if len(args.ItemPids) == 0 || len(args.ItemPids) > maxQueueItems {
			return InvalidError{Msg: "set-queue needs 1 to 500 itemPids"}
		}
		if args.Index != nil && (*args.Index < 0 || *args.Index >= len(args.ItemPids)) {
			return InvalidError{Msg: "set-queue index is outside the queue"}
		}
	case "set-repeat":
		switch args.Repeat {
		case "off", "all", "one":
		default:
			return InvalidError{Msg: "set-repeat needs repeat off, all, or one"}
		}
	case "set-shuffle":
		if args.Shuffle == nil {
			return InvalidError{Msg: "set-shuffle needs shuffle"}
		}
	default:
		return InvalidError{Msg: "unknown verb " + verb}
	}
	return nil
}

// routeCommandToClient forwards a verb to the client driving the
// session.
func (s *Service) routeCommandToClient(ctx context.Context, sessionID, endpointID, verb string, args CommandArgs) error {
	link, ok := s.reg.link(endpointID)
	if !ok {
		return ErrEndpointOffline
	}
	cmd := wireEndpointCommand{
		Type:       "endpoint-cmd",
		SessionID:  sessionID,
		Verb:       verb,
		ItemPids:   args.ItemPids,
		Index:      args.Index,
		PositionMS: args.PositionMS,
		Volume:     args.Volume,
		Rate:       args.Rate,
		Repeat:     args.Repeat,
		Shuffle:    args.Shuffle,
	}
	res, err := s.routeToLink(ctx, link, cmd)
	if err != nil {
		return err
	}
	if !res.ok {
		msg := res.message
		if msg == "" {
			msg = "the client rejected the command"
		}
		// The client's own code travels with its message; the
		// transport whitelists it before it reaches the wire.
		return InvalidError{Msg: msg, Code: res.code}
	}
	return nil
}

// applyRemoteCommand drives the endpoint for a server-authoritative
// session and updates the session's observed state optimistically
// (driver events refine it).
func (s *Service) applyRemoteCommand(ctx context.Context, sess *session, driver Driver, tm *TimelineMedia, verb string, args CommandArgs) error {
	now := s.cfg.Now()
	switch verb {
	case "play":
		if err := driver.Play(ctx); err != nil {
			return commandFailed(err)
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = sess.q.extrapolate(now)
			sess.q.PositionAt = now
			sess.q.Playing = true
		})
	case "pause":
		if err := driver.Pause(ctx); err != nil {
			return commandFailed(err)
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = sess.q.extrapolate(now)
			sess.q.PositionAt = now
			sess.q.Playing = false
		})
		s.checkpointRemote(ctx, sess)
	case "stop":
		if err := driver.Stop(ctx); err != nil {
			return commandFailed(err)
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = sess.q.extrapolate(now)
			sess.q.PositionAt = now
			sess.q.Playing = false
		})
		s.checkpointRemote(ctx, sess)
	case "seek":
		return s.remoteSeek(ctx, sess, driver, tm, *args.PositionMS)
	case "next", "previous":
		return s.remoteSkip(ctx, sess, driver, tm, verb == "next")
	case "set-volume":
		if err := driver.SetVolume(ctx, *args.Volume); err != nil {
			return commandFailed(err)
		}
		v := *args.Volume
		s.updateSession(sess, func() { sess.q.Volume = &v })
	case "set-rate":
		if err := driver.SetRate(ctx, *args.Rate); err != nil {
			return commandFailed(err)
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = sess.q.extrapolate(now)
			sess.q.PositionAt = now
			sess.q.Rate = *args.Rate
		})
	case "set-queue":
		return s.remoteSetQueue(ctx, sess, args)
	case "set-repeat":
		s.updateSession(sess, func() { sess.q.Repeat = args.Repeat })
		s.persist(ctx, sess, true)
	case "set-shuffle":
		return s.remoteSetShuffle(ctx, sess, *args.Shuffle)
	}
	return nil
}

// remoteSeek moves within the entry the session is on. A queue loaded
// as one timeline seeks that stream; a queue loaded per item seeks
// inside the loaded item, unless the target lies in another part of a
// multi-file audiobook - a different file, so the device is reloaded at
// it and the chapter jump costs a brief gap.
func (s *Service) remoteSeek(ctx context.Context, sess *session, driver Driver, tm *TimelineMedia, target int64) error {
	s.mu.Lock()
	index := sess.q.Index
	mediaIdx, inMediaMS := place(sess.slots, index, target)
	loaded := sess.mediaIndex
	playing := sess.q.Playing
	s.mu.Unlock()

	switch {
	case tm != nil:
		if err := driver.SeekTo(ctx, timelineAbsoluteMS(tm, index, target)); err != nil {
			return commandFailed(err)
		}
	case mediaIdx != loaded:
		if err := s.reloadRemote(ctx, sess, index, target, playing); err != nil {
			return err
		}
	default:
		if err := driver.SeekTo(ctx, inMediaMS); err != nil {
			return commandFailed(err)
		}
	}
	now := s.cfg.Now()
	s.updateSession(sess, func() {
		sess.q.PositionMS = target
		sess.q.PositionAt = now
	})
	return nil
}

func commandFailed(err error) error {
	return InvalidError{Msg: "the endpoint rejected the command: " + err.Error()}
}

func (s *Service) updateSession(sess *session, mutate func()) {
	s.mu.Lock()
	mutate()
	sess.updatedAt = s.cfg.Now()
	s.mu.Unlock()
}

// remoteSkip moves to the adjacent queue entry.
func (s *Service) remoteSkip(ctx context.Context, sess *session, driver Driver, tm *TimelineMedia, forward bool) error {
	s.mu.Lock()
	index := sess.q.Index
	if forward {
		index++
	} else {
		index--
	}
	if index < 0 {
		index = 0
	}
	if index >= len(sess.q.Entries) {
		if sess.q.Repeat == "all" {
			index = 0
		} else {
			s.mu.Unlock()
			// The code a client endpoint answers the same refusal with, so
			// a controller words it in its own language either way.
			return InvalidError{Msg: "already at the end of the queue", Code: "queue-end"}
		}
	}
	s.mu.Unlock()

	if tm != nil {
		abs := timelineAbsoluteMS(tm, index, 0)
		if err := driver.SeekTo(ctx, abs); err != nil {
			return commandFailed(err)
		}
	} else {
		if err := s.reloadRemote(ctx, sess, index, 0, true); err != nil {
			return err
		}
	}
	s.flushEntryListen(ctx, sess)
	s.updateSession(sess, func() {
		sess.q.Index = index
		sess.q.PositionMS = 0
		sess.q.PositionAt = s.cfg.Now()
	})
	s.checkpointRemote(ctx, sess)
	return nil
}

// remoteSetQueue replaces a remote session's queue and reloads.
func (s *Service) remoteSetQueue(ctx context.Context, sess *session, args CommandArgs) error {
	entries, err := s.cfg.Resolver.Entries(ctx, sess.ownerID, args.ItemPids)
	if err != nil {
		return err
	}
	index := 0
	if args.Index != nil {
		index = *args.Index
	}
	var positionMS int64
	if args.PositionMS != nil {
		positionMS = *args.PositionMS
	}
	s.mu.Lock()
	sess.q.Entries = entries
	sess.q.QueueVersion++
	s.mu.Unlock()
	if err := s.reloadRemote(ctx, sess, index, positionMS, true); err != nil {
		return err
	}
	s.updateSession(sess, func() {
		sess.q.Index = index
		sess.q.PositionMS = positionMS
		sess.q.PositionAt = s.cfg.Now()
		sess.q.Playing = true
	})
	s.persist(ctx, sess, true)
	s.cfg.Sink.SetQueue(ctx, sess.ownerID, args.ItemPids)
	s.cfg.InvalidatePlayer()
	return nil
}

// remoteSetShuffle reorders the remaining queue and reloads.
func (s *Service) remoteSetShuffle(ctx context.Context, sess *session, on bool) error {
	s.mu.Lock()
	sess.q.Shuffle = on
	if on {
		sess.q.Entries = shuffledEntries(sess.q.Entries, sess.q.Index)
		sess.q.Index = 0
		sess.q.QueueVersion++
	}
	index := sess.q.Index
	positionMS := sess.q.extrapolate(s.cfg.Now())
	playing := sess.q.Playing
	s.mu.Unlock()
	if !on {
		// Turning shuffle off keeps the current order by contract (the
		// spec states it; there is no original order to restore once
		// the remainder was reshuffled). Only the flag changes.
		s.updateSession(sess, func() {})
		s.persist(ctx, sess, true)
		return nil
	}
	if err := s.reloadRemote(ctx, sess, index, positionMS, playing); err != nil {
		return err
	}
	s.persist(ctx, sess, true)
	s.cfg.InvalidatePlayer()
	return nil
}

// reloadRemote re-renders the current queue onto the session's
// endpoint (queue edits, shuffle, repeat-driven reloads).
func (s *Service) reloadRemote(ctx context.Context, sess *session, index int, positionMS int64, play bool) error {
	s.mu.Lock()
	ep, ok := s.reg.Lookup(sess.ownerID, sess.endpointID)
	driver := sess.driver
	entries := sess.q.Entries
	ownerID := sess.ownerID
	s.mu.Unlock()
	if !ok || driver == nil {
		return ErrEndpointOffline
	}
	bases := s.cfg.Bases.forKind(ep.Kind)
	ttl := mediaTTL(entries)
	var lastErr error
	for _, base := range bases {
		rendered, err := s.renderQueue(ctx, ownerID, ep, driver, entries, base, ttl)
		if err != nil {
			s.forgetLoad(sess)
			return err
		}
		if err := s.driveLoad(ctx, sess, driver, rendered, index, positionMS, play); err != nil {
			lastErr = err
			continue
		}
		return nil
	}
	// Nothing loaded, so nothing on the device answers to the mapping
	// the session was holding - and after a queue edit the entries it
	// spoke for are gone too. Reports stop being read as positions
	// until a load lands, and the queue carries on from where it was
	// rather than adopting a number in units it no longer knows.
	s.forgetLoad(sess)
	return commandFailed(lastErr)
}

// forgetLoad drops the mapping a failed load leaves behind.
func (s *Service) forgetLoad(sess *session) {
	s.mu.Lock()
	sess.timeline = nil
	sess.slots = nil
	sess.mediaIndex = 0
	s.mu.Unlock()
}

// HandleCommandResult resolves a routed command's waiter.
func (s *Service) HandleCommandResult(id string, ok bool, code, message string) {
	s.mu.Lock()
	r, found := s.routes[id]
	s.mu.Unlock()
	if !found {
		return
	}
	select {
	case r.done <- routeResult{ok: ok, code: code, message: message}:
	default:
	}
}

// HandleSessionReport mirrors a playing client's state. The bool
// result says whether a session frame should be sent back (identity
// assigned or the reported session ended).
func (s *Service) HandleSessionReport(ctx context.Context, link *ClientLink, rep SessionReport) (*Session, bool) {
	endpointID := clientEndpointID(link.SessionID)
	if !link.isRegistered() {
		// An unregistered connection reporting playback implicitly
		// registers with defaults: reports are what make Connect see
		// local playback at all.
		s.HandleRegister(link, "", true, true)
	}

	s.mu.Lock()
	sess, answer, keep := s.reportTargetLocked(endpointID, link.UserID, rep)
	var entries []QueueEntry
	if keep && len(rep.ItemPids) > 0 {
		// The queue's titles are a catalog read, taken off the lock for a
		// report the checks keep, which then run again. The entries go
		// live in the same hold as the queue's version: a push between
		// the two would pair the new version with the old entries, and
		// every later one would leave the queue out as unchanged.
		s.mu.Unlock()
		entries = s.reportedEntries(ctx, link.UserID, rep.ItemPids)
		s.mu.Lock()
		sess, answer, keep = s.reportTargetLocked(endpointID, link.UserID, rep)
	}
	if !keep {
		s.mu.Unlock()
		return answer, answer != nil
	}
	created := false
	if sess == nil {
		sess = &session{
			id:         newSessionID(),
			ownerID:    link.UserID,
			ownerName:  link.UserName,
			endpointID: endpointID,
			authority:  AuthorityMirror,
			q:          queueState{Rate: 1, Repeat: "off"},
			createdAt:  s.cfg.Now(),
		}
		s.sessions[sess.id] = sess
		s.byEndpoint[endpointID] = sess.id
		created = true
	}

	now := s.cfg.Now()
	queueChanged := len(rep.ItemPids) > 0
	sess.authority = AuthorityMirror
	sess.q.Playing = rep.Playing
	sess.q.PositionMS = rep.PositionMS
	sess.q.PositionAt = now
	sess.q.Index = rep.Index
	if rep.Rate != nil {
		sess.q.Rate = *rep.Rate
	}
	if rep.Volume != nil {
		sess.q.Volume = rep.Volume
	}
	if rep.Repeat != "" {
		sess.q.Repeat = rep.Repeat
	}
	if rep.Shuffle != nil {
		sess.q.Shuffle = *rep.Shuffle
	}
	if queueChanged {
		// The published queue version is the server's own monotone
		// counter; the client's number is only the change signal.
		sess.q.QueueVersion++
		sess.q.Entries = entries
	}
	sess.updatedAt = now
	snap := s.snapshotLocked(sess)
	s.mu.Unlock()

	if queueChanged {
		s.cfg.Sink.SetQueue(ctx, link.UserID, rep.ItemPids)
		s.persist(ctx, sess, true)
		s.cfg.InvalidatePlayer()
	}
	if created {
		s.persist(ctx, sess, true)
		s.cfg.InvalidatePlayer()
	}
	s.notifyWatchers(sess.id)
	if created {
		return &snap, true
	}
	return nil, false
}

// reportTargetLocked finds the session a report applies to, nil for one
// it would create. keep is false for a report that is not applied, and
// answer is then the terminal frame owed for a session the server just
// ended. The caller holds s.mu.
func (s *Service) reportTargetLocked(endpointID, userID string, rep SessionReport) (sess *session, answer *Session, keep bool) {
	if id, ok := s.byEndpoint[endpointID]; ok {
		sess = s.sessions[id]
	}
	if sess != nil {
		// An endpoint id collision across users cannot happen (ids
		// derive from the device session), but stay fail-closed.
		return sess, nil, sess.ownerID == userID
	}
	if _, pending := s.pendingLoads[endpointID]; pending {
		// A routed load is installing this endpoint's session; the
		// racing first report is dropped rather than allowed to
		// mint a ghost id the client would then hold stale.
		return nil, nil, false
	}
	// A recently server-ended session on this endpoint answers
	// terminally instead of spawning a ghost from a stale report.
	if mark, ok := s.recentEnds[endpointID]; ok && s.cfg.Now().Sub(mark.at) < reportGrace {
		now := s.cfg.Now()
		return nil, &Session{ID: mark.sessionID, EndpointID: endpointID, OwnerUserID: userID, Authority: AuthorityMirror, Ended: true, UpdatedAt: now, PositionAt: now, Rate: 1}, false
	}
	// A creating report must carry the queue; a session without one
	// is unrenderable, so the report is ignored.
	return nil, nil, len(rep.ItemPids) > 0
}

// reportedEntries is a reported queue hydrated for display. A read that
// fails leaves the titles out, not the queue: its pids are what the
// client plays, and a transfer loads them, resolving each for the owner
// again.
func (s *Service) reportedEntries(ctx context.Context, userID string, pids []string) []QueueEntry {
	entries, err := s.cfg.Resolver.Entries(ctx, userID, pids)
	if err == nil {
		return entries
	}
	s.cfg.Logger.Warn("reading a mirrored queue's titles", "err", err)
	bare := make([]QueueEntry, len(pids))
	for i, pid := range pids {
		bare[i] = QueueEntry{PID: pid}
	}
	return bare
}

// HandleWatch follows one session's live state for the connection and
// sends the watch's first frame: the session as the connection's user
// may read it, entries included. The watch state remembers the queue
// version that frame delivered, so later pushes omit an unchanged
// queue. An empty sessionID stops watching.
//
// found is false for an unknown or invisible session (the transport
// answers an error frame). sent is false when the first frame could not
// be queued, which leaves the connection unwatched (the transport closes
// it, as for any answer it cannot deliver).
func (s *Service) HandleWatch(link *ClientLink, sessionID string) (found, sent bool) {
	s.mu.Lock()
	// The previous watch ends here, and the new one gets no push before
	// its first frame.
	delete(s.watchers, link)
	if sessionID == "" {
		s.mu.Unlock()
		return true, true
	}
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(link.UserID, sess) {
		s.mu.Unlock()
		return false, true
	}
	read := s.snapshotLocked(sess)
	s.mu.Unlock()
	// What the receiver may see is a catalog read, so it is taken off the
	// lock. The watch registers afterwards, in the hold that sends the
	// first frame: pushes collect their watchers under the lock too, so
	// none can reach the link ahead of that frame.
	visible := s.entriesVisible(read, link.UserID)

	s.mu.Lock()
	sess, ok = s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(link.UserID, sess) {
		s.mu.Unlock()
		return false, true
	}
	snap := s.snapshotLocked(sess)
	first := snap
	// A queue replaced during the read is one the read does not cover:
	// the first frame carries the queue it does, and a push owed in this
	// hold follows with the current one, to this watcher alone.
	behind := visible != nil && snap.QueueVersion != read.QueueVersion
	if behind {
		first = read
	}
	if !link.Send(WireSessionFrame(onlyVisible(first, visible), link.UserID, true)) {
		s.mu.Unlock()
		return true, false
	}
	ws := &watchState{sessionID: sessionID, queueVersion: first.QueueVersion}
	s.watchers[link] = ws
	var catchUp []watchPush
	if behind {
		catchUp = []watchPush{ws.owe(link, snap)}
	}
	s.mu.Unlock()
	s.deliver(catchUp)
	return true, true
}

// OnDisconnect tears down a connection's registrations: its endpoint,
// its watch, and any mirror session it was driving.
func (s *Service) OnDisconnect(ctx context.Context, link *ClientLink) {
	endpointID := clientEndpointID(link.SessionID)
	s.mu.Lock()
	delete(s.watchers, link)
	if id, ok := s.byEndpoint[endpointID]; ok {
		if sess, ok := s.sessions[id]; ok && sess.authority == AuthorityMirror {
			s.endSessionLocked(sess, false)
		}
	}
	s.mu.Unlock()
	if link.isRegistered() {
		s.reg.UnregisterClient(link)
		s.cfg.InvalidatePlayer()
	}
}

// notifyWatchers pushes the session's current state to its watchers,
// including entries only when the queue changed since that watcher
// last saw it.
func (s *Service) notifyWatchers(sessionID string) {
	s.mu.Lock()
	sess, ok := s.sessions[sessionID]
	if !ok {
		s.mu.Unlock()
		return
	}
	snap := s.snapshotLocked(sess)
	var pushes []watchPush
	for link, ws := range s.watchers {
		if ws.sessionID == sessionID {
			pushes = append(pushes, ws.owe(link, snap))
		}
	}
	s.mu.Unlock()
	s.deliver(pushes)
}

// watchPush is one frame a watcher is owed: its place in the order they
// were owed, the state it carries, and whether the queue rides along.
type watchPush struct {
	link        *ClientLink
	ws          *watchState
	seq         uint64
	snap        Session
	withEntries bool
}

// owe numbers the next push the watcher is owed, which carries the queue
// until a frame with its version has been sent. The caller holds s.mu.
func (ws *watchState) owe(link *ClientLink, snap Session) watchPush {
	ws.owed++
	return watchPush{link: link, ws: ws, seq: ws.owed, snap: snap, withEntries: snap.QueueVersion != ws.queueVersion}
}

// deliver sends the pushes. One that needs no catalog read goes out at
// once; each of the others right after its own read, which is taken off
// the lock, so a slow read holds back only the reads behind it.
func (s *Service) deliver(pushes []watchPush) {
	if len(pushes) == 0 {
		return
	}
	var reads []watchPush
	s.mu.Lock()
	for _, p := range pushes {
		if p.withEntries && len(p.snap.Entries) > 0 && s.filtersEntries(p.snap, p.link.UserID) {
			reads = append(reads, p)
			continue
		}
		s.sendLocked(p, p.snap)
	}
	s.mu.Unlock()
	for _, p := range reads {
		view := s.receiverView(p.snap, p.link.UserID)
		s.mu.Lock()
		s.sendLocked(p, view)
		s.mu.Unlock()
	}
}

// sendLocked sends a push unless it is stale: its watch has ended or
// been replaced, or a push owed after it has gone out already. A frame
// the connection does not take is owed again by the next push, queue and
// all. The caller holds s.mu.
func (s *Service) sendLocked(p watchPush, view Session) {
	ws := p.ws
	if s.watchers[p.link] != ws || p.seq <= ws.sent {
		return
	}
	if !p.link.Send(WireSessionFrame(view, p.link.UserID, p.withEntries)) {
		return
	}
	ws.sent = p.seq
	if p.withEntries {
		ws.queueVersion = p.snap.QueueVersion
	}
}

// notifyEnded pushes a terminal frame to the ended session's watchers
// and unwatches them. It goes out under the lock, as every watch frame
// does.
func (s *Service) notifyEnded(snap Session) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for link, ws := range s.watchers {
		if ws.sessionID == snap.ID {
			delete(s.watchers, link)
			link.Send(WireSessionFrame(snap, link.UserID, false))
		}
	}
}

// pushPlayingToWatchers refreshes every watched, playing session about
// once per second, leaving the queue out for a watcher already sent it.
func (s *Service) pushPlayingToWatchers() {
	s.mu.Lock()
	var pushes []watchPush
	for link, ws := range s.watchers {
		if sess, ok := s.sessions[ws.sessionID]; ok && sess.q.Playing {
			pushes = append(pushes, ws.owe(link, s.snapshotLocked(sess)))
		}
	}
	s.mu.Unlock()
	s.deliver(pushes)
}

// checkpointPlaying persists every playing session, and writes the
// positions of the ones the server drives through to per-user playback
// state.
//
// The two halves have different scopes on purpose. Progress accounting
// stays remote-only, as it always has: a mirror session's position
// arrives in reports the playing client sends, and the server counting
// it as well would count it twice. The checkpoint covers both, because
// a session only ever ends gracefully through endSessionLocked, and
// nothing writes a mirror session's row between queue changes - so a
// crash or restart mid-album used to leave its history entry at
// whatever the last queue change said, which is usually the first
// track at zero.
func (s *Service) checkpointPlaying(ctx context.Context) {
	s.mu.Lock()
	type cp struct {
		sess *session
		pid  string
		pos  int64
	}
	var cps []cp
	for _, sess := range s.sessions {
		if !sess.q.Playing {
			continue
		}
		c := cp{sess: sess}
		if sess.authority == AuthorityRemote {
			snap := s.snapshotLocked(sess)
			c.pid = currentPID(snap)
			c.pos = snap.PositionMS
		}
		cps = append(cps, c)
	}
	s.mu.Unlock()
	for _, c := range cps {
		if c.pid != "" {
			s.cfg.Sink.Progress(c.sess.ownerID, c.pid, c.pos)
		}
		s.persist(ctx, c.sess, true)
	}
}

// checkpointRemote writes one remote session's position through
// immediately (pause, stop, track change).
func (s *Service) checkpointRemote(ctx context.Context, sess *session) {
	s.mu.Lock()
	snap := s.snapshotLocked(sess)
	authority := sess.authority
	s.mu.Unlock()
	if authority != AuthorityRemote {
		return
	}
	if pid := currentPID(snap); pid != "" {
		s.cfg.Sink.Checkpoint(ctx, sess.ownerID, pid, snap.PositionMS)
	}
	s.persist(ctx, sess, true)
}

// flushEntryListen closes the listen accumulator for the session's
// current entry (call before changing entries). Caller holds no lock
// requirements; uses its own.
func (s *Service) flushEntryListen(ctx context.Context, sess *session) {
	s.mu.Lock()
	lt := s.listen[sess.id]
	delete(s.listen, sess.id)
	owner := sess.ownerID
	s.mu.Unlock()
	s.flushListen(ctx, owner, lt)
}

// onDriverEvent folds a driver observation into the session.
func (s *Service) onDriverEvent(sessionID string, gen int, ev DriverEvent) {
	ctx := context.Background()
	s.mu.Lock()
	sess, ok := s.sessions[sessionID]
	if !ok || s.driverGen[sessionID] != gen {
		s.mu.Unlock()
		return
	}
	if ev.Fatal {
		s.cfg.Logger.Warn("endpoint died mid-session", "session", sessionID, "err", ev.Err)
		s.endSessionLocked(sess, false)
		s.mu.Unlock()
		s.cfg.InvalidatePlayer()
		return
	}
	if lc, ok := sess.driver.(LoadCounter); ok && ev.Load != 0 && ev.Load < lc.CurrentLoad() {
		s.mu.Unlock()
		return
	}

	now := ev.At
	if now.IsZero() {
		now = s.cfg.Now()
	}
	// The driver reports where it is in what it was handed, which is
	// one stream for a timeline and one item per slot otherwise; both
	// map back to a queue entry and a position on that entry's own
	// timeline, so a book's parts read as one book.
	//
	// The default carries on from where the session was rather than
	// adopting the report: an observation the load's mapping cannot
	// explain is in units this session does not know - a part-relative
	// position where the table is gone, an index into a render the
	// queue has since replaced - and publishing it moves a listener's
	// place in a book by hours.
	index, posMS := sess.q.Index, sess.q.extrapolate(now)
	switch {
	case sess.timeline != nil:
		index, posMS = timelineLocate(sess.timeline, ev.PositionMS)
	case ev.Index >= 0 && ev.Index < len(sess.slots):
		sess.mediaIndex = ev.Index
		index, posMS = locate(sess.slots, ev.Index, ev.PositionMS)
	case len(sess.slots) == 0 && ev.Index >= 0 && ev.Index < len(sess.q.Entries):
		// No table, which means a reload failed and the device is
		// playing something this session can no longer describe. One
		// item per entry is what it was before books could split, and
		// reading it that way keeps a queue of whole tracks tracking
		// until a load lands.
		index, posMS = ev.Index, ev.PositionMS
	}
	// Bounded against the queue as it is now, not as the render saw it:
	// a queue edit swaps the entries before the reload that follows it,
	// and a report landing in that gap resolves through the old table.
	if index < 0 || index >= len(sess.q.Entries) {
		index, posMS = sess.q.Index, sess.q.extrapolate(now)
	}

	// Entry indices, so stepping from one part of a book to the next is
	// not a track change: no listen flushed, no checkpoint, and the
	// listen accumulator's delta across the seam is the ordinary
	// forward motion it looks like.
	indexChanged := index != sess.q.Index
	pauseEdge := sess.q.Playing && !ev.Playing

	// Listen accounting: accumulate forward motion while playing.
	lt := s.listen[sessionID]
	pid := ""
	if sess.q.Index >= 0 && sess.q.Index < len(sess.q.Entries) {
		pid = sess.q.Entries[sess.q.Index].PID
	}
	if lt == nil && pid != "" && ev.Playing {
		lt = &listenTrack{pid: pid, startedAt: now, lastPos: posMS}
		s.listen[sessionID] = lt
	}
	if lt != nil && !indexChanged && sess.q.Playing {
		delta := posMS - lt.lastPos
		if delta > 0 && delta < 30000 {
			lt.playedMS += delta
		}
		lt.lastPos = posMS
	}

	var finishedListen *listenTrack
	owner := sess.ownerID
	if indexChanged {
		finishedListen = lt
		delete(s.listen, sessionID)
	}

	sess.q.Index = index
	sess.q.PositionMS = posMS
	sess.q.PositionAt = now
	sess.q.Playing = ev.Playing
	if ev.Volume != nil {
		sess.q.Volume = ev.Volume
	}
	sess.updatedAt = s.cfg.Now()

	repeat := sess.q.Repeat
	finished := ev.Finished
	snap := s.snapshotLocked(sess)
	s.mu.Unlock()

	if finishedListen != nil {
		s.flushListen(ctx, owner, finishedListen)
	}
	if pid := currentPID(snap); pid != "" && (indexChanged || pauseEdge) {
		s.cfg.Sink.Checkpoint(ctx, owner, pid, snap.PositionMS)
	} else if pid != "" && snap.Playing {
		s.cfg.Sink.Progress(owner, pid, snap.PositionMS)
	}
	s.notifyWatchers(sessionID)

	if finished {
		s.onLoadFinished(ctx, sess, repeat)
	}
}

// onLoadFinished applies repeat policy when the whole load ran out.
// A failed reload falls through to the stopped shape: the physical
// output is silent, and the session must say so.
func (s *Service) onLoadFinished(ctx context.Context, sess *session, repeat string) {
	switch repeat {
	case "all":
		if err := s.reloadRemote(ctx, sess, 0, 0, true); err != nil {
			s.cfg.Logger.Warn("repeat-all reload", "err", err)
			s.settleFinished(ctx, sess)
			return
		}
		s.updateSession(sess, func() {
			sess.q.Index = 0
			sess.q.PositionMS = 0
			sess.q.PositionAt = s.cfg.Now()
			sess.q.Playing = true
		})
		s.notifyWatchers(sess.id)
	case "one":
		s.mu.Lock()
		index := sess.q.Index
		s.mu.Unlock()
		if err := s.reloadRemote(ctx, sess, index, 0, true); err != nil {
			s.cfg.Logger.Warn("repeat-one reload", "err", err)
			s.settleFinished(ctx, sess)
			return
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = 0
			sess.q.PositionAt = s.cfg.Now()
			sess.q.Playing = true
		})
		s.notifyWatchers(sess.id)
	default:
		s.settleFinished(ctx, sess)
	}
}

// settleFinished parks a session whose load ran out (or whose repeat
// reload failed): stopped, listen flushed, checkpointed, watchers told.
func (s *Service) settleFinished(ctx context.Context, sess *session) {
	s.updateSession(sess, func() {
		sess.q.Playing = false
	})
	s.flushEntryListen(ctx, sess)
	s.checkpointRemote(ctx, sess)
	s.notifyWatchers(sess.id)
}

// EndpointOnline is called by discovery when a device (re)appears.
func (s *Service) EndpointOnline(ctx context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial DialFunc) (Endpoint, error) {
	ep, err := s.reg.UpsertDevice(ctx, kind, deviceKey, name, address, volumeControl, rateControl, dial)
	if err != nil {
		return Endpoint{}, err
	}
	s.cfg.InvalidatePlayer()
	return ep, nil
}

// EndpointOffline is called by discovery when a device stops
// answering. Any active session on it ends.
func (s *Service) EndpointOffline(ctx context.Context, endpointID string) {
	s.reg.MarkDeviceOffline(endpointID)
	s.mu.Lock()
	if id, ok := s.byEndpoint[endpointID]; ok {
		if sess, ok := s.sessions[id]; ok {
			s.endSessionLocked(sess, false)
		}
	}
	s.mu.Unlock()
	s.cfg.InvalidatePlayer()
}

// RouteDeadline exposes the routing deadline for transports and tests.
func RouteDeadline() time.Duration { return routeDeadline }
