# 19. The local queue is a pure state machine with a play order and a source order

Date: 2026-07-25

## Status

Accepted.

## Context

Playback was single-item. The only queue in the client lived inside the
Connect endpoint controller (`_ConnectQueue`), built when a remote load
arrived and thrown away when it ended, so nothing in the app could
answer "what plays after this" and no screen could show a queue at all.
The client rewrite promotes the queue to something the listener sees and
edits: play next, add to queue, drag to reorder, shuffle the remainder,
resume it after a restart, and hand it to another endpoint.

That raises questions a single-item player never had to answer. What is
an entry's identity when a playlist names the same track twice? What
does un-shuffling restore? What gets evicted when a queue hits its cap?
What happens to a queue when the app is closed, and whose queue is it
when a different account signs in? Answering them inside the widget
layer, one screen at a time, is how a queue ends up meaning something
different on the deck bar than in the queue panel.

## Decision

**One controller, no I/O.** `QueueController` (`src/queue/`) is a
Riverpod notifier over an immutable `QueueState`. It owns ordering,
the current index, shuffle, repeat, provenance, and the cap. It plays
nothing, fetches nothing, and reads no clock: the playback layer above
it reacts to the current entry changing. Every operation is synchronous,
so its tests are about queue semantics and nothing else.

**Entries carry a stable id, not a pid.** A queue is a list of
`QueueEntry{queueId, pid}`. Duplicates are legal, a reorder moves an
entry rather than replacing one, and the current entry is followed by
id across every edit rather than by index arithmetic.

**Two orders, one of them the permutation.** `entries` is play order:
what the queue screen renders, what an advance walks, and what a Connect
load serializes to (`pids` plus `currentIndex` is exactly what
`POST /player/sessions`, `set-queue`, and a timeline mint consume).
`sourceOrder` is the same entries in the order the queue was built in.
Shuffle reorders the entries after the current one and leaves
`sourceOrder` alone; un-shuffling sorts that same remainder back by it.
The played head is never reordered, so the history the queue surface
shows is the order actually played.

This diverges from the server on one point, deliberately. The Connect
service's `set-shuffle` moves the current entry to index zero, shuffles
everything else, and cannot put the order back (its own comment says so:
there is nothing kept to restore). A local queue keeps the order it was
built in, so it restores it. Where the two meet, the local queue always
speaks in ordered pids plus an index, which is authority-neutral.

**Shuffle is a standing preference, and only the listener changes it.**
The toggle survives a queue being replaced, and a new queue is built
under whatever it says: tapping a track with shuffle on plays that track
and shuffles what follows, and the "Shuffle" entry point turns the
preference on and draws from anywhere. Nothing else may flip it, because
a toggle that answers itself is a toggle nobody can trust. The
corollary is that entries are always minted in the order they arrived
in, whatever order they are played in, so `sourceOrder` is the album's
order even for a queue that has never been played in it.

**A hand placement outranks the source.** Dragging an entry moves it in
both orders, landing after the same neighbour in each. A listener who
put a track somewhere finds it there after shuffle goes off. A drag that
lands out of range moves nothing, in either order.

**500 entries, evicting history first.** The cap mirrors the server's
session cap, so a local queue can always be handed to an endpoint whole.
A list longer than the cap is windowed rather than refused: in order the
window starts where play starts, shuffled it is a random draw from the
whole list (which is what a scope too large to hold should mean). What
survives still knows where it came from, so un-shuffling a draw gives
source order. Additions past the cap evict the oldest played entries
first, then the far end, and never the entry playing or (while anything
else can go) the entries just added: "Add to queue" that quietly does
nothing is worse than dropping something hours away. The eviction set is
chosen in one pass and applied in one rebuild, because a 500-item add is
a gesture someone is waiting through. The same rule is what a rolling
shuffle window over a scope larger than the cap will refill against.

**Undo is one step, held in state.** Replacing an active queue stashes
the displaced queue and the position it stood at, which is what the
"Playing from" toast's Undo restores. It is not a history: the next
replacement takes the slot, and nothing persists it, because a relaunch
is not an accident to take back.

**Advance and retreat answer, they do not assume.** `advance()` returns
whether it moved, wants the current item repeated (repeat-one), ran out,
or had nothing queued; `retreat()` distinguishes moving back from being
at the front. Repeat-one deliberately does not touch the queue, so the
caller re-mints its listen session through the existing path rather than
having the queue silently loop under the accounting. A single entry on
repeat-all is the same answer: it wraps onto itself, which is a repeat,
and calling it an advance would have the caller reload what is already
playing and the accounting count a play that never restarted.

**Persistence is a port, and the schema bump is one migration.**
`QueueStore` (in `waxdeck_data`, where drift lives) writes ordered pids,
ranks, and provenance to `QueueEntries` and `QueueMeta`; the web build
gets `NoQueueStore` and offers the server's most recent session instead.
Writes are debounced (a drag emits a state per frame) and flushed when
the session ends. Schema v2 adds those two tables, the `ArtworkPins`
table the artwork pipeline will fill, and the `skippedMs` column the
listen outbox was missing, in one migration rather than three.

**No titles and no position are persisted.** The catalog mirror is the
one catalog truth and the checkpointed play state is the one position
truth; a copy of either inside the queue could only disagree with it.
The restore offer hydrates its title from the mirror when the mirror has
it, and goes without when it does not.

**An offer is only ever about a queue that is not playing.** Anything
that starts one retires it, and a launch that already has a queue is
offered nothing. Otherwise the affordance outlives its own premise and
sits there ready to replace live playback with a snapshot of what came
before it.

**The queue does not outlive the session.** Signing out clears the
queue, its store, the offer, and the standing repeat and shuffle
preferences that belonged to the listener leaving. The rest of the local
mirror survives a sign-out today, but the queue is the piece a next
launch would put back in front of whoever signs in next, by name.
("Clear queue" is a different verb and keeps the preferences; when
settings gain a per-user client store, repeat and shuffle move there and
this stops being the queue's business.)

That teardown is one function the queue owns, called by the auth
controller, not a list of steps auth maintains. It is deliberately not
hung off the persistence provider's disposal: a provider is disposed for
reasons that are not a sign-out, and forgetting a listener's queue on a
rebuild would be data loss with no cause. It cannot fail the sign-out
either. A store that will not clear is a stale offer next launch; a
session left standing because a write threw is a dead credential the UI
keeps using.

## Consequences

- The queue can be tested without an engine, a server, or a widget: the
  state machine's suite is a seeded `Random` and no fakes at all, so
  shuffle is an assertable order rather than a probability.
- Playback ownership, Connect, and Android Auto can all be pointed at
  one queue, which is what makes head-unit skips, UI skips, and remote
  loads agree rather than each keeping their own idea of next.
- The stable `queueId` is an in-memory identity, not a write strategy.
  A save deletes the rows and writes the snapshot whole, in one
  transaction: at 500 rows the bookkeeping to work out which positions
  moved costs more than writing them, and a torn write leaves the
  previous queue rather than half of two. A rank that repeats on the
  way back in breaks its tie on play position, so the documented
  degradation is real rather than whatever an unstable sort left.
- The id counter is persisted with the entries and repaired on load
  (a counter left behind its rows cannot mint an id already in use).
- Value equality is deliberately absent from `QueueState`: comparing
  500-entry lists on every notification would cost more than the
  notification, and the controller only assigns when something changed.
  Widgets select the fields they care about.
- The cap's windowing means "play from track 700 of a 900-track
  playlist" queues 500 entries starting there, not a refusal and not a
  silent truncation to the first 500.
- A failed write is swallowed and printed. Persistence is a cache with
  no other symptom: a queue that stopped being written looks exactly
  like one that was, until the next launch offers nothing, so the
  reason belongs in the console even though it belongs nowhere in the
  UI.
