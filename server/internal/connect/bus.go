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
		if args.Rate == nil || *args.Rate < 0.25 || *args.Rate > 5 {
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
		return InvalidError{Msg: msg}
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
		target := *args.PositionMS
		abs := target
		if tm != nil {
			s.mu.Lock()
			idx := sess.q.Index
			s.mu.Unlock()
			abs = timelineAbsoluteMS(tm, idx, target)
		}
		if err := driver.SeekTo(ctx, abs); err != nil {
			return commandFailed(err)
		}
		s.updateSession(sess, func() {
			sess.q.PositionMS = target
			sess.q.PositionAt = now
		})
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
			return InvalidError{Msg: "already at the end of the queue"}
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
		var tm *TimelineMedia
		var err error
		if ep.Kind == KindCast && len(entries) > 1 {
			tm, err = s.cfg.Resolver.Timeline(ctx, ownerID, entries, 0, base)
			if err != nil {
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
		return nil
	}
	return commandFailed(lastErr)
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
	var sess *session
	if id, ok := s.byEndpoint[endpointID]; ok {
		sess = s.sessions[id]
	}
	created := false
	if sess == nil {
		if _, pending := s.pendingLoads[endpointID]; pending {
			// A routed load is installing this endpoint's session; the
			// racing first report is dropped rather than allowed to
			// mint a ghost id the client would then hold stale.
			s.mu.Unlock()
			return nil, false
		}
		// A recently server-ended session on this endpoint answers
		// terminally instead of spawning a ghost from a stale report.
		if mark, ok := s.recentEnds[endpointID]; ok && s.cfg.Now().Sub(mark.at) < reportGrace {
			s.mu.Unlock()
			ended := Session{ID: mark.sessionID, EndpointID: endpointID, OwnerUserID: link.UserID, Authority: AuthorityMirror, Ended: true, UpdatedAt: s.cfg.Now(), PositionAt: s.cfg.Now(), Rate: 1}
			return &ended, true
		}
		if len(rep.ItemPids) == 0 {
			// A creating report must carry the queue; a session
			// without one is unrenderable, so the report is ignored.
			s.mu.Unlock()
			return nil, false
		}
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
	if sess.ownerID != link.UserID {
		// An endpoint id collision across users cannot happen (ids
		// derive from the device session), but stay fail-closed.
		s.mu.Unlock()
		return nil, false
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
	}
	sess.updatedAt = now
	pidsForHydrate := rep.ItemPids
	snap := s.snapshotLocked(sess)
	s.mu.Unlock()

	if queueChanged {
		// Hydrate titles off-lock; a failed hydration keeps bare pids
		// out of the entries rather than blocking the report.
		if entries, err := s.cfg.Resolver.Entries(ctx, link.UserID, pidsForHydrate); err == nil {
			s.mu.Lock()
			sess.q.Entries = entries
			snap = s.snapshotLocked(sess)
			s.mu.Unlock()
		}
		s.cfg.Sink.SetQueue(ctx, link.UserID, pidsForHydrate)
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

// HandleWatch follows one session's live state for the connection.
// Results: (snapshot, true) on success, (nil, true) for a stop watch,
// (nil, false) for an unknown or invisible session (the transport
// answers an error frame). The success snapshot always carries
// entries; the watch state remembers the delivered queue version so
// later pushes omit an unchanged queue.
func (s *Service) HandleWatch(link *ClientLink, sessionID string) (*Session, bool) {
	s.mu.Lock()
	if sessionID == "" {
		delete(s.watchers, link)
		s.mu.Unlock()
		return nil, true
	}
	sess, ok := s.sessions[sessionID]
	if !ok || !s.visibleSessionLocked(link.UserID, sess) {
		delete(s.watchers, link)
		s.mu.Unlock()
		return nil, false
	}
	s.watchers[link] = &watchState{sessionID: sessionID, sentQV: sess.q.QueueVersion, sentAny: true}
	snap := s.snapshotLocked(sess)
	s.mu.Unlock()
	return &snap, true
}

// OnDisconnect tears down a connection's registrations: its endpoint,
// its watch, and any mirror session it was driving.
func (s *Service) OnDisconnect(ctx context.Context, link *ClientLink) {
	endpointID := clientEndpointID(link.SessionID)
	s.mu.Lock()
	delete(s.watchers, link)
	if id, ok := s.byEndpoint[endpointID]; ok {
		if sess, ok := s.sessions[id]; ok && sess.authority == AuthorityMirror {
			s.endSessionLocked(ctx, sess, false)
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
	type push struct {
		link        *ClientLink
		withEntries bool
	}
	var pushes []push
	for link, ws := range s.watchers {
		if ws.sessionID != sessionID {
			continue
		}
		withEntries := !ws.sentAny || ws.sentQV != snap.QueueVersion
		ws.sentAny = true
		ws.sentQV = snap.QueueVersion
		pushes = append(pushes, push{link: link, withEntries: withEntries})
	}
	s.mu.Unlock()
	for _, p := range pushes {
		p.link.Send(WireSessionFrame(snap, p.link.UserID, p.withEntries))
	}
}

// notifyEnded pushes a terminal frame to the ended session's watchers
// and unwatches them.
func (s *Service) notifyEnded(snap Session) {
	s.mu.Lock()
	var links []*ClientLink
	for link, ws := range s.watchers {
		if ws.sessionID == snap.ID {
			links = append(links, link)
			delete(s.watchers, link)
		}
	}
	s.mu.Unlock()
	for _, link := range links {
		link.Send(WireSessionFrame(snap, link.UserID, false))
	}
}

// pushPlayingToWatchers refreshes every watched, playing session about
// once per second (entries omitted; the queue did not change).
func (s *Service) pushPlayingToWatchers() {
	s.mu.Lock()
	type push struct {
		snap        Session
		link        *ClientLink
		withEntries bool
	}
	var pushes []push
	for link, ws := range s.watchers {
		if sess, ok := s.sessions[ws.sessionID]; ok && sess.q.Playing {
			snap := s.snapshotLocked(sess)
			withEntries := !ws.sentAny || ws.sentQV != snap.QueueVersion
			ws.sentAny = true
			ws.sentQV = snap.QueueVersion
			pushes = append(pushes, push{snap: snap, link: link, withEntries: withEntries})
		}
	}
	s.mu.Unlock()
	for _, p := range pushes {
		p.link.Send(WireSessionFrame(p.snap, p.link.UserID, p.withEntries))
	}
}

// checkpointPlaying persists remote playing sessions and writes their
// positions through to per-user playback state.
func (s *Service) checkpointPlaying(ctx context.Context) {
	s.mu.Lock()
	type cp struct {
		sess *session
		pid  string
		pos  int64
	}
	var cps []cp
	for _, sess := range s.sessions {
		if sess.authority != AuthorityRemote || !sess.q.Playing {
			continue
		}
		snap := s.snapshotLocked(sess)
		cps = append(cps, cp{sess: sess, pid: currentPID(snap), pos: snap.PositionMS})
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
		s.endSessionLocked(ctx, sess, false)
		s.mu.Unlock()
		s.cfg.InvalidatePlayer()
		return
	}

	now := ev.At
	if now.IsZero() {
		now = s.cfg.Now()
	}
	index := sess.q.Index
	posMS := ev.PositionMS
	if sess.timeline != nil {
		index, posMS = timelineLocate(sess.timeline, ev.PositionMS)
	} else if ev.Index >= 0 && ev.Index < len(sess.q.Entries) {
		index = ev.Index
	}

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
			s.endSessionLocked(ctx, sess, false)
		}
	}
	s.mu.Unlock()
	s.cfg.InvalidatePlayer()
}

// RouteDeadline exposes the routing deadline for transports and tests.
func RouteDeadline() time.Duration { return routeDeadline }
