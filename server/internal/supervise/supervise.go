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
// shutdown.
type Group struct {
	log *slog.Logger
	wg  sync.WaitGroup
}

// NewGroup returns a Group logging through log (nil discards).
func NewGroup(log *slog.Logger) *Group {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Group{log: log}
}

// Go runs fn in a supervised goroutine named name. A panic or error is
// logged and fn restarts with exponential backoff; a nil return or a
// canceled ctx ends the worker for good. Wait returns once every worker
// has ended.
func (g *Group) Go(ctx context.Context, name string, fn func(context.Context) error) {
	g.wg.Go(func() {
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
}

// GoOnce runs fn in a supervised goroutine without restarting: a panic
// is contained and logged, and the worker ends. For one-shot work whose
// failure should degrade, not loop.
func (g *Group) GoOnce(ctx context.Context, name string, fn func(context.Context) error) {
	g.wg.Go(func() {
		if err := g.run(ctx, name, fn); err != nil && ctx.Err() == nil {
			g.log.Error("worker failed", "worker", name, "err", err)
		}
	})
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

// Wait blocks until every spawned worker has returned.
func (g *Group) Wait() { g.wg.Wait() }

// PanicError reports a recovered worker panic.
type PanicError struct {
	Worker string
	Value  any
}

func (e *PanicError) Error() string { return "panic in worker " + e.Worker }
