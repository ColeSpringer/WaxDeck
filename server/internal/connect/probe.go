package connect

import (
	"context"
	"fmt"
	"time"
)

// probeWait is how long a device gets to fetch the probe before the
// verdict is "timeout". Generous: a cast device resolving a name,
// opening TLS, and pulling a second of audio over a slow wireless link
// is the case being measured, and calling that a failure would be the
// diagnosis lying about the thing it exists to diagnose.
const probeWait = 10 * time.Second

// probePoll is how often the fetch is checked. Nothing pushes it - the
// evidence is a request this server served - so it is looked at beside
// the driver's events rather than waited on.
const probePoll = 200 * time.Millisecond

// probeStopWait bounds the silencing that follows each trial.
const probeStopWait = 5 * time.Second

// Probe verdicts.
const (
	ProbePlayed  = "played"
	ProbeFailed  = "failed"
	ProbeTimeout = "timeout"
)

// ProbeMedia is what a device probe plays and how the server can tell
// the device came and got it.
type ProbeMedia struct {
	// Item builds the stream to load from one base, for an endpoint
	// that declared these formats.
	Item func(target EndpointTarget, base string) MediaItem
	// Fetched reports whether this server has served the probe through
	// that base yet.
	//
	// This, and not what the device says about itself, is what a
	// verdict is built on: a cast receiver reports BUFFERING while it
	// is still resolving a name it will never resolve, and a renderer
	// can start and finish a one-second clip between two polls. A
	// request that arrived is the one unambiguous fact - the device
	// opened this address, on this server, and took the bytes.
	//
	// Nil where the server cannot tell, which falls the verdict back
	// on what the device reports.
	Fetched func(base string) bool
}

// BaseVerdict is what one device made of one advertise base.
type BaseVerdict struct {
	Base      string
	Verdict   string
	Detail    string
	LatencyMS int64
}

// EndpointProbe is a whole device probe: the endpoint it ran against
// and one verdict per candidate base, in the order sessions try them.
// Short of the full list where the device stopped answering partway.
type EndpointProbe struct {
	EndpointID string
	Name       string
	Kind       string
	Bases      []BaseVerdict
}

// Probe plays a short stream on a device endpoint from each advertise
// base in turn and reports what the device did with it. It is the half
// of the connection check the server cannot do for itself: whether the
// device resolves the name, trusts the certificate, and has a route.
//
// Nothing is probed over somebody's listening. A live session on the
// endpoint, a foreign application on a cast device, a renderer holding
// something paused, or another probe already running all refuse with
// ErrEndpointBusy naming what is there: loading media replaces what a
// device is doing, and a connection check is not worth interrupting a
// film for.
func (s *Service) Probe(ctx context.Context, userID, endpointID string, media ProbeMedia) (EndpointProbe, error) {
	ep, ok := s.reg.Lookup(userID, endpointID)
	if !ok {
		return EndpointProbe{}, ErrNotFound
	}
	// Only the endpoints that fetch media for themselves have anything
	// to prove here. A client endpoint holds a session with the server
	// it is signed in to, and the jukebox is this process; neither can
	// fail the way this exists to catch, so neither is a probe target
	// rather than a probe that always passes.
	if ep.Kind != KindCast && ep.Kind != KindDLNA {
		return EndpointProbe{}, ErrNotFound
	}
	if ep.Shared && !s.sharedAllowed(userID) {
		return EndpointProbe{}, ErrForbidden
	}
	// Claimed in the same breath as the check, so two probes and a
	// session start cannot all pass it.
	s.mu.Lock()
	_, playing := s.byEndpoint[ep.ID]
	running := s.probing[ep.ID]
	if !playing && !running {
		s.probing[ep.ID] = true
	}
	s.mu.Unlock()
	switch {
	case playing:
		return EndpointProbe{}, fmt.Errorf("%w: %s is playing a WaxDeck queue", ErrEndpointBusy, ep.Name)
	case running:
		return EndpointProbe{}, fmt.Errorf("%w: a connection check is already running on %s", ErrEndpointBusy, ep.Name)
	}
	defer func() {
		s.mu.Lock()
		delete(s.probing, ep.ID)
		s.mu.Unlock()
	}()

	dial, ok := s.reg.dialer(ep.ID)
	if !ok {
		return EndpointProbe{}, ErrEndpointOffline
	}
	driver, err := dial(ctx)
	if err != nil {
		s.reg.MarkDeviceOffline(ep.ID)
		return EndpointProbe{}, fmt.Errorf("%w: %v", ErrEndpointOffline, err)
	}
	defer driver.Close()

	if idler, ok := driver.(Idler); ok {
		if idle, detail := idler.Idle(ctx); !idle {
			return EndpointProbe{}, fmt.Errorf("%w: %s", ErrEndpointBusy, detail)
		}
	}

	target := TargetFor(ep.Kind, driver)
	out := EndpointProbe{EndpointID: ep.ID, Name: ep.Name, Kind: ep.Kind}
	for _, base := range s.cfg.Bases.forKind(ep.Kind) {
		v, alive := s.probeBase(ctx, driver, base, target, media)
		out.Bases = append(out.Bases, v)
		// A dead socket has nothing to say about the next address, and
		// a row claiming otherwise would read as a verdict.
		if !alive || ctx.Err() != nil {
			break
		}
	}
	return out, nil
}

// probeBase runs one base's trial: load, wait for the device to come
// and fetch it, then silence it again whatever happened. The second
// result is whether the driver is still worth asking about the next
// base.
func (s *Service) probeBase(ctx context.Context, driver Driver, base string, target EndpointTarget, media ProbeMedia) (v BaseVerdict, alive bool) {
	// Whatever the driver observed before the load describes the state
	// the probe is about to replace, and a stale `playing` in it would
	// pass this base without the device having fetched anything.
	for drained := true; drained; {
		select {
		case _, ok := <-driver.Events():
			drained = ok
		default:
			drained = false
		}
	}

	started := s.cfg.Now()
	v = BaseVerdict{Base: base, Verdict: ProbeTimeout, Detail: "the device never fetched this address"}
	alive = true
	defer func() {
		// Timed to the device's answer rather than to the end of the
		// trial: the number is how long a listener waits for sound.
		v.LatencyMS = int64(s.cfg.Now().Sub(started) / time.Millisecond)
		// Silenced whatever the verdict, a load that reported an error
		// included: a renderer can take the URI and fail the play, and
		// a speaker left looping a second of silence is worse than a
		// wrong verdict. On its own deadline, detached from the
		// caller's, so a listener who closed the sheet still gets the
		// room back and a device that has stopped answering cannot
		// hold the handler open while it is asked to.
		stopCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), probeStopWait)
		defer cancel()
		if err := driver.Stop(stopCtx); err != nil {
			s.cfg.Logger.Warn("stopping a probe", "base", base, "err", err)
		}
	}()

	if err := driver.Load(ctx, []MediaItem{media.Item(target, base)}, 0, 0, true); err != nil {
		v.Verdict, v.Detail = ProbeFailed, err.Error()
		return v, alive
	}
	fetched := media.Fetched
	if fetched == nil {
		// Nothing to observe, so the device's own word is all there
		// is. Weaker, and the reason the fetch exists.
		fetched = func(string) bool { return false }
	}
	tick := time.NewTicker(probePoll)
	defer tick.Stop()
	deadline := time.NewTimer(probeWait)
	defer deadline.Stop()
	said := false
	for {
		if fetched(base) {
			v.Verdict, v.Detail = ProbePlayed, ""
			return v, alive
		}
		select {
		case ev, ok := <-driver.Events():
			if !ok {
				v.Verdict, v.Detail = ProbeFailed, "the device closed the connection"
				return v, false
			}
			switch {
			case ev.Err != nil:
				v.Verdict, v.Detail = ProbeFailed, ev.Err.Error()
				return v, !ev.Fatal
			case ev.Fatal:
				v.Verdict, v.Detail = ProbeFailed, "the device stopped answering"
				return v, false
			case ev.Playing && media.Fetched == nil:
				v.Verdict, v.Detail = ProbePlayed, ""
				return v, alive
			case ev.Playing:
				// Provisional: a receiver says this while it is still
				// opening the stream, and the fetch is what settles it.
				said = true
			}
		case <-tick.C:
		case <-deadline.C:
			if said {
				v.Detail = "the device reported playing but never fetched this address"
			}
			return v, alive
		case <-ctx.Done():
			v.Detail = "the check was cancelled"
			return v, alive
		}
	}
}
