# 36. Pacing the live invalidation fan-out, and keeping it off first builds

Date: 2026-07-30

## Status

Accepted.

## Context

The client's half of live sync is one move: a change hint arrives on the
event channel and `syncBinderProvider` invalidates every controller that
topic could have made stale. The catalog topic reaches twelve of them, the
user topic seventeen, and several are families, so one hint invalidates
every open instance of a playlist detail, a show, an episode, a review
entry, a play state.

That fan-out ran on every hint, and the server's own ceiling is one hint
per topic per 250 ms (`events.coalesceWindow`). Both topics reach the
playlist providers, so a busy server had this client refetching whole
screens roughly eight times a second.

Where a provider already holds a value that is merely wasteful: riverpod
treats an `invalidate` as a *refresh* rather than a *reload*, so the state
stays `AsyncData` with `isLoading` set, the screen keeps drawing what it
had, and the new data replaces it when it lands. Nothing blinks.

Where a provider is still doing its **first** build it is not wasteful, it
is destructive. There is no previous value to keep, so the state is a bare
`AsyncLoading` and the screen is on its skeleton; and riverpod cannot
cancel a `Future`, so the rebuild does not stop the fetch in flight, it
abandons it and starts another beside it. Hints arriving faster than a
build completes therefore hold the screen on its skeleton for as long as
they keep coming, piling up one orphaned fetch per hint. It is a livelock,
not a slowdown: the screen does not load late, it does not load at all.

A playlist detail is the worst case in the app - `PlaylistDetailController.build`
is a playlist read followed by a walk of every member page, restarted from
the top each time - and it is where this surfaced. `playlists.spec.ts`
timed out waiting for the add row of a list it had just opened, once, in a
full four-worker run and never under `--repeat-each` against the same
build. That is the signature: the specs share one server and one admin
account, so the three other workers' scans, stars, and scrobbles are what
keep both topics hot, and a spec running alone sees none of it.

Reproduced as a widget test before anything was changed: a playlist detail
mounted against a repository with 200 ms reads, invalidated every 125 ms,
never rendered its add row in five seconds of hints and issued 40 member
reads doing it. The same screen already loaded rode the same storm without
dropping a frame of its body, which is the seamless-refresh half above.

## Decision

Two mechanisms, layered: the fan-out runs at a bounded rate, and a run
never touches a provider whose first build is in flight. The first bounds
cost; the second is what actually removes the livelock, for builds of any
length.

### The fan-out is paced, and the pacing is per topic

`PacedRefresh` sits between the hint and the fan-out: the first hint after
a quiet spell runs it at once, hints arriving inside the window collapse
into exactly one at its end. A leading edge with a trailing flush, window
one second, one instance per topic.

**Leading, because a lone change must land immediately.** The live-update
surfaces are a product promise and an asserted one - another device stars
a track and the open smart playlist re-evaluates itself - and those specs
allow three to five seconds. A pure trailing debounce would delay every
single change by a window; worse, under a sustained stream it would never
fire at all, which is the opposite failure.

**Trailing, because nothing may be dropped.** A hint is a wakeup, not a
payload, so collapsing several into one loses nothing - but skipping the
last one entirely would leave a screen stale until the next unrelated
change, which on a quiet server is never.

**One second, because a hint should land about as fast as it used to.**
The bound has to stay well under the tightest live-update assertion in
the suite (three seconds) with room for the round trips that follow it.
It no longer has to exceed a first build - the deferral below is what
protects builds, whatever they take - so the window is purely a rate
choice, and it is deliberately not tuned around build times.

**Per topic, not one pacer for both.** Catalog and user hints invalidate
overlapping but different sets, and a shared pacer would let a busy
catalog swallow the user hint that a star just produced.

The binder owns both pacers and hands them to whichever transport is live,
so the native sync engine's streams and the web build's event channel get
the same behavior. The player topic stays unpaced: it feeds the Connect
command bus rather than a screen refetch, it is not a fan-out, and it is
the one place latency is the point.

### A run defers around in-flight first builds

`InvalidationFanOut` is the run itself: the topic's providers and
families as data rather than a closure of `ref.invalidate` calls. For
each target - families per live instance, discovered through
`ProviderContainer.allProviders(family:)` - it asks one question before
invalidating: is this provider's first build in flight? If so, the
instance is skipped and owed, the run reports itself incomplete, and the
pacer re-attempts just the owed set at each window's end until the build
has landed and the invalidation can be applied. The build is never
interrupted; the data it fetched from before the change is replaced one
window after it lands. A fresh hint during the cooldown outranks the
retry, since a full run recomputes what is owed from scratch.

The question is answered by `FirstBuildObserver`, a `ProviderObserver` on
the root container that keeps the set of providers whose current state is
a bare loading - `isLoading` with no value and no error, which is exactly
the skeleton condition, since a refresh keeps its data and a reload
carries it forward. `didAddProvider` sees the initial loading at element
birth, `didUpdateProvider` sees the landing, and both disposal hooks
prune: `didUnmountProvider` for an element leaving memory, and
`didDisposeProvider` because it fires on every invalidation, and an
invalidation *cancels* the build in flight - the landing the entry was
waiting for will never notify. Without that prune, a keep-alive instance
invalidated mid-first-build from outside the fan-out (`appendTo`
invalidating an unopened playlist's detail, a delete invalidating the
grid) stayed in the ledger for the life of the session: deferred forever,
excluded from live invalidation, its topic's retry timer re-arming every
window. The prune's own narrow cost is accepted and worth naming: a
*watched* instance invalidated mid-first-build rebuilds into a bare
loading equal to the old one, which the notification gate suppresses, so
that instance rides plain pacing - the pre-deferral behavior - until a
differing state lands and re-adds it.

**An observer, because it is the one way to know without touching.** This
took a false start to learn, and the constraint is worth recording.
Riverpod deliberately leaves an invalidated element lazy while nothing
listens - `invalidateSelf` does not schedule paused providers, so an
unwatched screen's controllers sit marked-dirty and free. Every read path
the public API offers (`container.read`, a subscription's `readSafe`)
flushes that mark as a side effect: probing state by read would have
rebuilt every once-visited screen's providers on every sweep, turning the
fan-out's cheapest case into its most expensive. The observer hooks carry
every state passively, so the ledger never causes work. The element-level
alternative (`getAllProviderElements` and `isActive`) answers the same
question but the whole element API is marked `@internal` ("Do not use"),
which on a pinned riverpod is exactly the surface that rewrites between
minors.

The ledger only works registered from the first element, so `main.dart`
passes it to the root `ProviderContainer`. A container without one (a
widget test's `ProviderScope`) gets the pre-deferral behavior: the binder
finds no observer and the fan-out invalidates unconditionally.

### What was rejected

**Fixing it in the playlist controllers.** The detail screen is the worst
case, not a special one; every provider in either list has the same
exposure, and a library grid or a show screen opened at the wrong moment
fails the same way. A fix per controller would be twenty-five of them and
would still miss the twenty-sixth. Single-flight caches per controller
also fight the notifier lifecycle: controllers are recreated on rebuild,
so the in-flight state would need a companion cache per family.

**Probing element state through the container.** Rejected twice, for
different reasons at each layer: the public read paths flush (the
regression described above), and the internal element API that avoids the
flush is `@internal`. The observer is the supported shape of the same
idea.

**Leaving it and widening the e2e timeout.** The starvation is not a test
artifact. Four workers on one server is a fair model of a household with
four devices, and the screen that never loads is the same screen either
way.

## Consequences

The livelock is gone, not narrowed: a first build of any length completes
under a sustained hint stream, because nothing restarts it. What a slow
build trades for that is freshness at the edge - it lands with the data
its own fetch started before the change, and the owed invalidation
replaces that within a window of the landing. A change hint that arrives
during a cooldown is likewise applied up to one second late. Nothing in
the suite or the UI depends on tighter than that, and the first hint
after any quiet spell - which is what a single user's own device
produces - is unaffected.

The wasteful half goes with it: a busy server used to cost this client up
to eight full fan-outs a second, each one a refetch of every open screen.
It now costs one per second per topic, and deferred work never becomes
invented work - an invalidation applied to an unwatched element stays a
lazy mark, which the fan-out's tests pin down explicitly.

The residuals, small and named, are tracked in `docs/deferred-work.md`.
A build that never lands (a hung request with no timeout) keeps its
topic's pacer re-arming every window; the retry is a set lookup and an
early return, so the cost is a timer, but a session with such a build
ticks until it is disposed. A nested `ProviderScope` that overrides a
target provider sits outside the sweep: the root ledger *does* see its
elements (a child container splices its parent's observers in), but
`allProviders` enumerates this container and its parents, never
children, so the sweep would neither invalidate nor defer the nested
instance - exactly as the old `ref.invalidate` from the root never
reached it - and, because the ledger keys by provider, a nested
instance mid-first-build would mark the same key its root counterpart
answers to. No screen nests an override of a fan-out target today;
whoever introduces one takes the enumeration with it. And the
watched-instance micro-window above rides plain pacing until a
differing state notifies.

`PacedRefresh`, `FirstBuildObserver`, and `InvalidationFanOut` are each
unit-tested, the slower-than-window first build has a widget regression
test through the full wiring, and the same test runs again without the
ledger asserting the starvation comes back - the failure mode is pinned,
so the mechanism cannot quietly rot. The binder wiring itself is not
covered on the VM: `syncEngineProvider` is null under `flutter test` and
the web branch needs a browser, so the e2e suite is what exercises the
seam between a real hint and a real refetch.
