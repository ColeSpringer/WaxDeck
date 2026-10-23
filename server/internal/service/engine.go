package service

import (
	"context"
	"maps"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// EngineState is the streaming engine as the bridge last said: whether
// one is set up, whether it is answering, and what it offers while it
// is.
type EngineState struct {
	Configured bool
	Connected  bool
	Timelines  bool
	VoiceBoost bool
	FileTools  bool
}

// SetEngineState records what the bridge says of the engine. A change
// from what it said before puts the pid-less server marker on every
// account's stream, so open clients read /health again; the first word,
// at startup, is no change.
func (l *Library) SetEngineState(ctx context.Context, st EngineState) {
	if prev := l.streaming.Swap(&st); prev == nil || *prev == st {
		return
	}
	l.emitEveryoneEvent(ctx, eventServer)
}

// EngineState is the engine's state as last recorded, the zero state
// before anything was.
func (l *Library) EngineState() EngineState {
	if st := l.streaming.Load(); st != nil {
		return *st
	}
	return EngineState{}
}

// EngineBridge is the streaming bridge as the service follows it: its
// crossings, the roots it holds for an answer, and its runtime-root
// surface.
type EngineBridge interface {
	FlowRootSync
	OnUp(fn func(ctx context.Context, st flow.Status))
	OnDown(fn func())
	OnHeld(fn func(held []string))
}

// FollowEngine has the service track the streaming engine through the
// bridge's crossings: the state /health reports and its marker, and at
// every answer that ends an outage the roots the engine should map, the
// ones it refused before the outage included. The bridge is wired for
// roots at once, so every root operation works before the engine first
// answers, as during any outage: the bridge holds the change for the
// engine and it is offered again when the engine answers, and so is one
// held for an answer that crossed nothing (a reload that ran out of time
// while the engine stayed up). Called once, before the bridge runs.
func (l *Library) FollowEngine(ctx context.Context, b EngineBridge) {
	l.SetEngineState(ctx, EngineState{Configured: true})
	l.SetFlowRoots(b)
	b.OnUp(func(ctx context.Context, st flow.Status) {
		l.SetEngineState(ctx, EngineState{
			Configured: true, Connected: st.Connected,
			Timelines: st.Timelines, VoiceBoost: st.VoiceBoost, FileTools: st.FileTools,
		})
		l.ResyncFlowRoots()
	})
	b.OnDown(func() {
		l.flowOutages.Add(1)
		l.SetEngineState(ctx, EngineState{Configured: true})
	})
	b.OnHeld(l.OfferHeldRoots)
}

// OfferHeldRoots offers the engine again the roots it held for an answer,
// which were told they wait as a refused root is: their refusal is let go
// and the root sync offers them, off the caller.
func (l *Library) OfferHeldRoots(held []string) {
	l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
		l.flowSyncMu.Lock()
		for _, name := range held {
			delete(l.flowRefused, name)
		}
		l.flowSyncMu.Unlock()
		l.syncFlowRoots(ctx)
		return nil
	})
}

// engineAway reports a configured engine that is not answering.
func (l *Library) engineAway() bool {
	st := l.EngineState()
	return st.Configured && !st.Connected
}

// ResyncFlowRoots offers the engine every root it does not map, the ones
// it refused before it last went away included: an engine answering again
// may be one restarted where it can see them. A refusal given since, by
// the engine answering now, stands, so a root offered between its answer
// and this re-sync is not offered twice. Run off the caller, since each
// offer is a request to the engine.
func (l *Library) ResyncFlowRoots() {
	outages := l.flowOutages.Load()
	l.workers.GoOnce(l.procCtx, "flow-roots", func(ctx context.Context) error {
		l.flowSyncMu.Lock()
		maps.DeleteFunc(l.flowRefused, func(_ string, r flowRefusal) bool { return r.outages < outages })
		l.flowSyncMu.Unlock()
		l.syncFlowRoots(ctx)
		return nil
	})
}

// needsEngine refuses a request only the streaming engine serves, saying
// so for an engine that is away rather than missing.
func (l *Library) needsEngine(what string) error {
	msg := what + " needs the streaming engine"
	if l.engineAway() {
		msg += ", which is not reachable right now"
	}
	return &Error{Kind: KindFeature, Msg: msg}
}

// PodcastsOn reports whether this server keeps podcasts: false when its
// podcast directory is turned off, which refuses every subscribe.
func (l *Library) PodcastsOn() bool { return l.podcastDir != "" }
