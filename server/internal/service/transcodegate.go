package service

import (
	"context"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// transcodeGate implements the bridge's session gate against the
// runtime limits and per-account permissions. Counts are in-memory:
// sessions do not survive a restart, so neither should their slots.
type transcodeGate struct {
	l  *Library
	mu sync.Mutex
	// active counts engine-backed streams per user id; total is the sum.
	active map[string]int
	total  int
}

// TranscodeGate returns the bridge-facing session gate. One instance
// per service: the metrics surface reads the same counters.
func (l *Library) TranscodeGate() flow.TranscodeGate {
	l.gateOnce.Do(func() {
		l.gate = &transcodeGate{l: l, active: map[string]int{}}
	})
	return l.gate
}

// ActiveTranscodeSessions reports the engine-backed streams in flight.
func (l *Library) ActiveTranscodeSessions() int {
	l.gateOnce.Do(func() {
		l.gate = &transcodeGate{l: l, active: map[string]int{}}
	})
	l.gate.mu.Lock()
	defer l.gate.mu.Unlock()
	return l.gate.total
}

func (g *transcodeGate) Acquire(ctx context.Context, user string) (func(), error) {
	lim := g.l.currentToggles().limits
	admin := g.userIsAdmin(ctx, user)
	g.mu.Lock()
	defer g.mu.Unlock()
	if lim.MaxConcurrent > 0 && g.total >= lim.MaxConcurrent {
		return nil, flow.ErrTranscodeLimited
	}
	if !admin && lim.MaxConcurrentPerUser > 0 && g.active[user] >= lim.MaxConcurrentPerUser {
		return nil, flow.ErrTranscodeLimited
	}
	g.active[user]++
	g.total++
	var once sync.Once
	return func() {
		once.Do(func() {
			g.mu.Lock()
			defer g.mu.Unlock()
			g.active[user]--
			if g.active[user] <= 0 {
				delete(g.active, user)
			}
			g.total--
		})
	}, nil
}

func (g *transcodeGate) MaxBitrateKbps(ctx context.Context, user string) int {
	if g.userIsAdmin(ctx, user) {
		return 0
	}
	ctx, cancel := gateCtx(ctx)
	defer cancel()
	if u, err := g.l.db.UserByID(ctx, user); err == nil && u.MaxTranscodeKbps > 0 {
		return int(u.MaxTranscodeKbps)
	}
	return g.l.currentToggles().limits.DefaultMaxBitrateKbps
}

func (g *transcodeGate) userIsAdmin(ctx context.Context, user string) bool {
	ctx, cancel := gateCtx(ctx)
	defer cancel()
	u, err := g.l.db.UserByID(ctx, user)
	if err != nil {
		return false
	}
	return hasRole(u.Roles, "admin")
}

// gateCtx bounds the gate's per-stream lookups: a stalled database
// must fail the check, never hang the client's connection.
func gateCtx(ctx context.Context) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithTimeout(ctx, 5*time.Second)
}
