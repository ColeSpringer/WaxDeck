// Package supervise is the only sanctioned way to start a goroutine in
// the WaxDeck server. One process hosts hostile-input parsing next to
// everyone's live audio, and net/http only recovers handler panics, so
// every worker goroutine runs behind a recover boundary that degrades
// its own subsystem and restarts with backoff instead of taking the
// process down. A lint forbids bare go statements outside this package.
package supervise

import (
	"context"
	"log/slog"
	"runtime/debug"
	"sync"
	"time"
)

// backoff bounds for restarting a failed worker.
const (
	initialBackoff = time.Second
	maxBackoff     = time.Minute
)

// Group tracks the workers it spawned so a caller can wait for them on
// shutdown. The count is a counter under a condition variable rather
// than a sync.WaitGroup, because workers keep arriving while Wait runs:
// teardown is itself supervised, and request-time spawns (a radio
// artwork lookup, a logo warm) can land mid-shutdown - the WaitGroup
// shape panics on exactly that ("Add called concurrently with Wait").
// Construct with [NewGroup].
type Group struct {
	log  *slog.Logger
	mu   sync.Mutex
	idle *sync.Cond
	n    int
}

// NewGroup returns a Group logging through log (nil discards).
func NewGroup(log *slog.Logger) *Group {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	g := &Group{log: log}
	g.idle = sync.NewCond(&g.mu)
	return g
}

// spawn runs body on a counted goroutine: the one goroutine statement
// in the server, per the package lint.
func (g *Group) spawn(body func()) {
	g.mu.Lock()
	g.n++
	g.mu.Unlock()
	go func() {
		defer func() {
			g.mu.Lock()
			g.n--
			if g.n == 0 {
				g.idle.Broadcast()
			}
			g.mu.Unlock()
		}()
		body()
	}()
}

// Go runs fn in a supervised goroutine named name. A panic or error is
// logged and fn restarts with exponential backoff; a nil return or a
// canceled ctx ends the worker for good. Wait returns once every worker
// has ended.
//
// It reports whether the worker started: a context already canceled is
// refused, which keeps a request racing shutdown from spawning work
// after the group has been waited out - work nothing would wait for. A
// cancellation landing between this check and the spawn still leaves an
// instant where a worker can slip past a concurrent Wait; every body
// must therefore still honor its context promptly.
func (g *Group) Go(ctx context.Context, name string, fn func(context.Context) error) bool {
	if ctx.Err() != nil {
		return false
	}
	g.spawn(func() {
		backoff := initialBackoff
		for {
			err := g.run(ctx, name, fn)
			if ctx.Err() != nil {
				return
			}
			if err == nil {
				g.log.Info("worker ended", "worker", name)
				return
			}
			g.log.Error("worker failed; restarting", "worker", name, "err", err, "backoff", backoff)
			select {
			case <-ctx.Done():
				return
			case <-time.After(backoff):
			}
			backoff = min(backoff*2, maxBackoff)
		}
	})
	return true
}

// GoOnce runs fn in a supervised goroutine without restarting: a panic
// is contained and logged, and the worker ends. For one-shot work whose
// failure should degrade, not loop. Like [Group.Go] it refuses an
// already-canceled context and reports whether the worker started, so a
// caller holding state the worker was meant to release can release it
// itself.
func (g *Group) GoOnce(ctx context.Context, name string, fn func(context.Context) error) bool {
	if ctx.Err() != nil {
		return false
	}
	g.spawn(func() {
		if err := g.run(ctx, name, fn); err != nil && ctx.Err() == nil {
			g.log.Error("worker failed", "worker", name, "err", err)
		}
	})
	return true
}

// run invokes fn converting a panic into an error.
func (g *Group) run(ctx context.Context, name string, fn func(context.Context) error) (err error) {
	defer func() {
		if r := recover(); r != nil {
			g.log.Error("worker panicked", "worker", name, "panic", r, "stack", string(debug.Stack()))
			err = &PanicError{Worker: name, Value: r}
		}
	}()
	return fn(ctx)
}

// Wait blocks until the group has no running workers, counting any that
// were spawned after Wait began. It returns at the first moment the
// count is zero.
func (g *Group) Wait() {
	g.mu.Lock()
	for g.n > 0 {
		g.idle.Wait()
	}
	g.mu.Unlock()
}

// PanicError reports a recovered worker panic.
type PanicError struct {
	Worker string
	Value  any
}

func (e *PanicError) Error() string { return "panic in worker " + e.Worker }
