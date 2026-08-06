package api

import (
	"sync"
	"time"
)

// Bounds for the two relays that stream a third party's bytes through
// this origin: /media/enclosure and /media/radio/{pid}. Both hold a
// goroutine and an upstream connection for as long as the transfer
// runs, and neither target is under this server's control, so both need
// a ceiling on how many a single account can hold and a way out of a
// transfer that never ends on its own.
//
// The concurrency cap is shared, because the resource is: a goroutine
// and a socket cost the same whichever relay holds them. The second
// bound is not shared, and the difference is the point. An episode is a
// finite file, so a transfer that has run past any real episode's size
// or has fallen below any usable rate is not going to finish, and both
// are safe to cut. A station is not finite -- a stream runs as long as
// somebody listens -- so neither a size cap nor a rate floor can be
// applied to it without eventually cutting a healthy listen. What is
// left for radio is the idle deadline, which says only that a station
// sending nothing at all has stopped being a station.

const (
	// maxUserRelays bounds concurrent relays per account across both
	// endpoints. Sized for device fan-out with headroom for reconnect
	// churn: a media element that seeks aborts and re-opens, and the
	// abandoned transfer can still be releasing when its replacement
	// arrives.
	maxUserRelays = 8

	// enclosureMaxBytes cuts an episode relay that has run past any
	// plausible episode. Long-form shows reach a few hundred MB, so
	// this clears real audio by a wide margin and still bounds a host
	// answering an endless body.
	enclosureMaxBytes = 1 << 30

	// enclosureMinRate is the floor an episode transfer has to hold on
	// average, in bytes per second. Below this the episode would not
	// finish in any time the listener would wait; the transfer is
	// consuming a slot rather than delivering audio. Well under a
	// 32 kbps spoken-word stream, so it cuts stalls rather than slow
	// but working connections.
	enclosureMinRate = 1 << 10

	// enclosureRateGrace is how long a transfer runs before the rate
	// floor applies, so a slow start (TLS, a cold CDN object, a host
	// thinking about a range request) is never mistaken for a stall.
	enclosureRateGrace = 30 * time.Second

	// enclosureIdle and radioIdle cut a transfer whose upstream has
	// gone quiet. Radio's is the looser of the two because a station's
	// own buffering can legitimately pause a stream for several
	// seconds, where a file server that stops mid-file has failed.
	enclosureIdle = 30 * time.Second
	radioIdle     = 60 * time.Second
)

// relayGate counts live relays per account.
//
// The same shape as shareStreamGate, kept separate rather than
// generalized with it: that one is keyed by share and exists to stop a
// public link becoming a bandwidth faucet, this one is keyed by account
// and exists to stop an authenticated caller pinning goroutines. They
// answer to different limits and will drift.
type relayGate struct {
	mu   sync.Mutex
	live map[string]int
}

func (g *relayGate) acquire(userID string) (release func(), ok bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.live == nil {
		g.live = map[string]int{}
	}
	if g.live[userID] >= maxUserRelays {
		return nil, false
	}
	g.live[userID]++
	var once sync.Once
	return func() {
		once.Do(func() {
			g.mu.Lock()
			// Zeroed entries are dropped, or the map grows by one per
			// account that ever relayed for the life of the process.
			if g.live[userID]--; g.live[userID] <= 0 {
				delete(g.live, userID)
			}
			g.mu.Unlock()
		})
	}, true
}

// relayLimits configures one guarded transfer. A zero field disables
// that bound, which is how radio takes the idle deadline and nothing
// else.
type relayLimits struct {
	idle       time.Duration
	maxBytes   int64
	minRate    int64 // bytes per second
	rateGrace  time.Duration
	relayStart time.Time
}

// relayGuard bounds one relayed body. Cancelling is the only lever it
// has: the response headers went out before the first byte, so there is
// no status left to change and a bound that trips can do nothing but
// end the transfer. Cancelling the upstream context rather than just
// breaking the loop is what also releases the socket.
//
// Every bound here judges the *upstream* and nothing else, which takes
// deliberate work because the relay loop does two things and only one of
// them is the upstream's fault. Writing to the listener blocks whenever
// their link is slow or their player has stopped reading -- a paused
// media element does exactly this once its buffer fills -- and a bound
// measured over that time would cut a healthy transfer and blame the
// podcast host for a slow phone. So the loop brackets its write with
// [relayGuard.writing], and the two reference points this reads are
// pushed forward by however long the write blocked.
//
// The idle deadline is a self-rearming watchdog rather than a timer the
// reader resets, and that is a correctness requirement rather than a
// style. A fired AfterFunc cannot be called off: Reset does not un-fire
// it, so a reader that reset a timer whose callback was already blocked
// on this mutex would be cut immediately after delivering bytes. Here
// the callback only ever *reads* the last-progress mark under the mutex
// and re-arms itself for the remainder, so a read landing at any moment
// is seen rather than lost.
type relayGuard struct {
	limits relayLimits
	cancel func()

	mu      sync.Mutex
	timer   *time.Timer
	stopped bool

	bytes int64
	// start is when upstream time began, and lastProgress when the
	// upstream last delivered. Both are pushed forward by time spent
	// blocked writing to the listener, which is what keeps a slow
	// listener from reading as a slow host.
	start        time.Time
	lastProgress time.Time
	// writeStart is non-zero while the relay is blocked writing to the
	// listener. Upstream idleness does not accrue then.
	writeStart time.Time
	// tripped records which bound ended the transfer, for the caller's
	// log line. Read after the loop, so the mutex covers it.
	tripped string
}

// newRelayGuard arms the guard. cancel is the upstream request's
// context cancel.
func newRelayGuard(limits relayLimits, cancel func()) *relayGuard {
	g := &relayGuard{limits: limits, cancel: cancel, start: limits.relayStart}
	if g.start.IsZero() {
		g.start = time.Now()
	}
	g.lastProgress = g.start
	if limits.idle > 0 {
		g.timer = time.AfterFunc(limits.idle, g.checkIdle)
	}
	return g
}

// checkIdle is the watchdog. It runs on the timer, re-arms itself while
// the upstream is behaving, and trips only when the upstream has
// genuinely been quiet for the whole window.
func (g *relayGuard) checkIdle() {
	g.mu.Lock()
	if g.stopped {
		g.mu.Unlock()
		return
	}
	// Blocked writing to the listener: the upstream is not being
	// judged right now, so there is nothing to decide. Come back later.
	if !g.writeStart.IsZero() {
		g.timer.Reset(g.limits.idle)
		g.mu.Unlock()
		return
	}
	// Bytes arrived since this was armed, so the window restarts from
	// them rather than from when the timer happened to be set.
	if quiet := time.Since(g.lastProgress); quiet < g.limits.idle {
		g.timer.Reset(g.limits.idle - quiet)
		g.mu.Unlock()
		return
	}
	g.stopped = true
	g.tripped = "the upstream stopped sending"
	g.mu.Unlock()
	g.cancel()
}

// writing brackets a write to the listener, returning the function that
// ends it. Time inside the bracket is excluded from every bound, so a
// listener who has stopped reading cannot get the upstream cut.
func (g *relayGuard) writing() (done func()) {
	g.mu.Lock()
	if !g.stopped {
		g.writeStart = time.Now()
	}
	g.mu.Unlock()
	return func() {
		g.mu.Lock()
		if !g.writeStart.IsZero() {
			blocked := time.Since(g.writeStart)
			g.writeStart = time.Time{}
			// Pushing the reference points forward is the same as
			// subtracting the blocked time from both bounds, without
			// carrying a separate budget to keep in step with them.
			g.lastProgress = g.lastProgress.Add(blocked)
			g.start = g.start.Add(blocked)
		}
		g.mu.Unlock()
	}
}

// note records a read of n bytes and reports whether the transfer may
// continue. A false return means a bound tripped and the caller stops;
// the upstream context is already cancelled.
func (g *relayGuard) note(n int) bool {
	g.mu.Lock()
	if g.stopped {
		g.mu.Unlock()
		return false
	}
	g.bytes += int64(n)
	total := g.bytes
	elapsed := time.Since(g.start)
	// The watchdog reads this rather than being reset from here, so a
	// timer already firing cannot be lost.
	if n > 0 {
		g.lastProgress = time.Now()
	}
	g.mu.Unlock()

	if g.limits.maxBytes > 0 && total > g.limits.maxBytes {
		g.trip("the upstream body ran past the size limit")
		return false
	}
	// An average over the transfer's *upstream* time - time blocked
	// writing to the listener is already out of `start` - rather than an
	// instantaneous rate: a transfer that has delivered its bytes and is
	// briefly paused should not be cut, and one that has never reached
	// the floor has been failing since it started.
	//
	// An average cannot see a transfer that ran fast and then stopped
	// dead, and it does not have to: that is a stall, and the idle
	// watchdog ends it within its own window no matter how much the
	// transfer delivered beforehand. The two bounds divide the space
	// between them - idle catches "stopped", the floor catches "never
	// going fast enough to finish" - which is why the floor is free to
	// be the cheap average.
	if g.limits.minRate > 0 && elapsed > g.limits.rateGrace {
		if total < int64(elapsed.Seconds()*float64(g.limits.minRate)) {
			g.trip("the upstream fell below the minimum transfer rate")
			return false
		}
	}
	return true
}

func (g *relayGuard) trip(reason string) {
	g.mu.Lock()
	if g.stopped {
		g.mu.Unlock()
		return
	}
	g.stopped = true
	g.tripped = reason
	if g.timer != nil {
		g.timer.Stop()
	}
	g.mu.Unlock()
	g.cancel()
}

// stop disarms the guard at the end of a transfer that ended on its
// own. It does not cancel: the caller's own defer owns that, and
// cancelling here would race a body still being drained.
func (g *relayGuard) stop() {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.stopped = true
	if g.timer != nil {
		g.timer.Stop()
	}
}

// reason reports the bound that ended the transfer, empty when none
// did.
func (g *relayGuard) reason() string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.tripped
}

// stats reports what the transfer actually managed, for the log line
// that reports a cut. The reason names which bound tripped; these say
// whether it tripped on a broken host or on a cap set too tight, which
// is the question the operator is actually asking and the one a bare
// reason string leaves them to guess at.
func (g *relayGuard) stats() (bytes int64, elapsed time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.bytes, time.Since(g.start)
}
