# 20. Playback belongs to a controller that follows the queue, and the crossing rolls the session over

Date: 2026-07-25

## Status

Accepted.

## Context

`PlayerScreen` created a `PlaybackSession` in `initState` and disposed it
in `dispose`. Opening the screen was what started playback; leaving it was
what stopped it. That is a coherent design for a single-item player and an
impossible one for everything the client rewrite is built on: a deck bar
that persists across navigation, a queue that plays through, an advance
that outlives whatever screen happened to start it.

The queue landed first (ADR-0019) as a pure state machine with no
consumer, and the engine port learned to hold one item ahead (ADR-0018)
with no caller. This is the layer between them.

## Decision

**One controller owns playback, and it follows the queue's current
entry.** `NowPlayingController` (`src/player/now_playing_controller.dart`)
holds at most one `PlaybackSession`, in the order the widget kept:
interrupt radio, build the session, register it, attach Connect, start it,
feed the sleep timer. Whatever puts an entry at the queue's current index
is what starts playing — a tap, a skip, a drag onto the current slot, a
restored queue, an advance at the end of an item. Nothing else starts
playback, and no screen stops it.

**Screens are viewers.** `PlayerScreen` reads `nowPlayingProvider` and
renders it; it takes no item, owns no session, and its route carries no
payload, so `/now-playing` resolves on a reload and says "nothing is
playing" when that is the truth. Every play entry point calls one verb,
`NowPlayingController.play(items, source:)`, which builds the queue that
gesture defines and then pushes the player. The verb is where the layers
meet: the queue does not know where the displaced queue stood (playback
does, and passes it for the Undo), and playback does not know what list a
tap came from (the screen does).

**Entries are followed by queue id, not by pid or index.** The controller
restarts only when the current entry's id changes, so a reorder around the
playing item, a repeat toggle, or a queue-wide edit never re-loads it, and
the same track queued twice is two entries that each play.

**The rollover happens in the session layer, at the boundary, and touches
no engine state.** On `itemBoundary` the outgoing session is finalized
where its item ended (`finishAtBoundary`: checkpoint at the item's own
duration, listen report `finished: true`) rather than at the engine's
position, which by then belongs to the item now playing. The queue is
moved to the entry that was prepared — found by identity, since the queue
may have been edited since — and a session for it *adopts* the running
stream: no fetch, no load, no seek, no play. Engine ownership moves as the
new session starts, so the outgoing one flushes without stopping media it
no longer owns.

`PlaybackSession` grew exactly what that needs: `sessionCompleted` (fired
only on true completion, so a book rolling from part one to part two is
never mistaken for the end of an item), `adopt`, `finishAtBoundary`,
`replay` for repeat-one, and an `autoplay` flag on `start` for a queue put
back at launch. Checkpointing, listen accounting, trim maps, offline
fallback, and multi-part books are untouched.

**The preload admission policy, and when it fires.** The engine is handed
the next item only when all of these hold:

- Both the playing item and the next one are music. Spoken word carries
  per-item playback config a crossing cannot apply in time — a show or
  book plays at its own remembered speed, and an episode with a
  skip-intro setting does not start at its own head — and a book's parts
  roll inside one session, which is not a queue boundary at all.
- The next item's play-info is a passthrough stream: seekable and not
  voice-boosted. A preloaded transcode opens a second server-side session,
  which double counts against the transcode limiter or is refused outright
  mid-queue. The server clears `seekable` for anything it cuts, voice
  boost included, so those two answers are the whole test; this client
  never forces a format.
- The next item would start at the head of its window (its checkpointed
  position is zero), because that is the only thing `preloadNext` can
  prepare.
- The playing item is within `kPreloadLead` (30 seconds) of its end.

That last one is a real constraint, not a heuristic: a stream URL is a
fifteen-minute media token, so arming at the start of a long track hands
the engine a URL that expires before the crossing. Thirty seconds is long
enough for the platform to have the source ready and far inside the token's
life.

An armed entry the queue no longer wants next is dropped and re-armed,
and anything that fails is logged and skipped: preloading is best effort
by the port's own contract, and its failure costs the gapless crossing
and nothing else, because the item still loads on advance.

**What is armed is a record of what the engine holds, not of what the
queue wants.** Resolving a preload takes three round trips, so a queue
edited inside that window is common enough to design for. The record is
written even when the queue moved while the last call landed, because it
is the truth about the engine, and it is what lets a crossing during that
window find by identity which entry actually played. Correcting the
engine is the reconcile's job: a sync request that arrives while an arm
is in flight is remembered and run after it rather than dropped, so the
edit is honored immediately instead of waiting for the next position tick
— which never comes if playback is paused.

**A crossing publishes once, whole.** The new session goes on the state
as soon as it exists, not once its adoption settles, and the summary is
normally already in hand because arming resolved it. There is no frame
where the state carries no session for the transport to bind to, and none
where it still names the session that let go at the boundary. The
fallback, for an entry whose summary is somehow not cached, is to publish
the entry alone while it resolves: the outgoing session has already been
finalized, and naming it would hand surfaces something that has let go.

**Radio never advances a queue, and the item lets go of the engine.**
Radio drives the engine directly, bypassing sessions, so completion and
boundary events are ignored while a station is playing — without that, a
stream dropping would step the queue and load a track over the radio. The
item that was playing also hands the engine over the moment a station
starts: checkpointed where it stands, its listen reported unfinished, the
media left alone. A session that stayed subscribed would count the
station's stream as time listened to the item, checkpoint the item's pid
at the station's position, and report it finished when the stream ended.
The queue keeps its entry, so what was playing is still named; nothing
restarts it, because that would load over the radio the listener chose.

**A session that has let go stops mid-flight.** Every await in `start`
re-checks: a tap on something else, or a queue emptying, while play-info
resolves would otherwise have the abandoned session load its media over
whatever took the engine, under subscriptions nothing can cancel and a
state nothing names. The same guard covers the offline branch and part
resolution.

## Consequences

- Leaving the player keeps the music on. The tests say so directly, and
  every player test now ends playback explicitly, because nothing else
  will: unmounting a screen leaves a session running, its checkpoint timer
  ticking, and Connect still reporting it.
- The queue's entry points are the whole play surface now. Grids queue the
  one item they were tapped on (they mix media types and page as they
  scroll, so the list they would make is not one anybody asked for); a
  playlist, a mix, and a similar-tracks answer queue themselves from the
  row that was tapped. Books and episodes queue as themselves per the
  mixed-domain rule.
- A restored queue comes back paused at its checkpoint. Accepting a launch
  offer means "put it back", not "start playing", and the offer's own
  verb hands the queue to playback rather than to the queue controller,
  so the pause rides with it.
- Item summaries the callers had in hand are cached. It saves a round
  trip, and for episodes it is the only way the show survives:
  `GET /items/{pid}` answers a plain item detail with no show pid, and
  the per-show speed, trim, and skip settings hang off that. (The Connect
  endpoint's own queue has always had this bug; it goes with
  `_ConnectQueue` when the gateway lands.) The cache is pruned to the
  queue whenever it grows past the queue's own cap, so a session that
  runs for days holds summaries for what is queued rather than for
  everything that ever was.
- A failed start releases its session as well as reporting the error. It
  is installed before it is known to work, so that the outgoing session
  can let go while this one loads; when it does not work, Connect would
  otherwise keep reporting an endpoint playing an item that never loaded.
- A failed start leaves the queue's entry where it is, so nothing else
  would try again. The player offers that: `retry()` starts the current
  entry over, from the position it was asked to start at rather than
  from the checkpoint, which is the difference between a stall and a
  moment of bad network. Skipping past it is the transport's job and
  lands with the deck bar. A session that never got as far as loading
  now checkpoints nothing on its way out: the engine's position belongs
  to whatever played before it, and writing that as the item's resume
  point was how a failure could cost the listener their place. For the
  same reason an item stopped at its outro cutoff holds the end it
  recorded, so the final checkpoint cannot walk the resume point back
  before the outro and fire it again on the next play.
- An armed end-of-chapter sleep timer belongs to the item that armed it.
  The boundary is a bare position with no item identity, so playback
  drops the mode when the item changes; a countdown is wall clock and
  the listener's, and stays.
- The admission policy remembers a refusal. The last thirty seconds of a
  track are hundreds of position ticks, and re-asking on each of them
  would mint a stream token per tick for an item that will never be
  prepared.
- Every async continuation checks that it still speaks for the controller
  (a newer start, or a disposed container): playback outlives screens, so
  its work now routinely outlives the thing that asked for it.
- `finishAtBoundary` is the only path that reports a listen as finished
  without the engine having said `completed`, which is exactly right: the
  engine walked out of the item, and the port's `completed` now means the
  queue ran out.
