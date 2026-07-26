# 21. Connect and the head unit drive the local queue through one gateway

Date: 2026-07-25

## Status

Accepted.

## Context

The client had two queues. `QueueController` (ADR-0019) is the one the
listener edits, and `NowPlayingController` (ADR-0020) plays it. The other
lived inside `ConnectEndpointController` as `_ConnectQueue`, built when a
remote load arrived, playing its entries through headless sessions of its
own, and thrown away when it ended.

That made a queue handed over from another device invisible: no screen
could show it, the deck bar now being built could not render it, and the
gapless preload never applied to it. It ran the other way too. Android Auto's
skip callbacks stepped that queue, so a skip on a head unit moved
something the screen did not have while the queue on screen stood still,
and a browse leaf tapped in the car built yet a third session outside
both. Two queues in one client is one too many, and neither of the
outside surfaces had a way to reach the real one.

## Decision

**One seam: `QueueGateway`.** The endpoint controller takes it in its
constructor, the media session reads it from a provider, and
`LocalQueueGateway` implements it over the two controllers that actually
hold the queue and the playback following it. `_ConnectQueue` is gone,
and with it the endpoint controller's repository, session registry,
client id, sync engine, and download manager: it no longer builds
sessions, so it no longer needs what building one takes. It holds a bus,
an engine, and the gateway.

Providers are read per call rather than held, because playback is built
on top of Connect (the endpoint controller is one of `NowPlayingController`'s
dependencies) and reading it back at construction would close the loop.

**A remote load becomes the local queue, in the order it arrived.** The
pids in the frame are the order the controlling device is showing, and
shuffle is its own verb, so the load turns the standing local preference
off rather than reordering what was handed over: the alternative has the
two ends disagreeing about what plays next while the toggle claims
something the queue does not show. What arrives has no provenance to
claim (pids and nothing else; the entity they came from stayed on the
device that sent it), so the queue's source is `none`.

**Reports are pulled, not pushed.** The controller asks the gateway for a
snapshot rather than being handed a session to hold: pids, index,
position, repeat, and shuffle. A null snapshot means nothing local is
playing, which is what stops the reports, and it is the same answer for
an empty queue and for an engine live radio has taken. `repeat` and
`shuffle` now ride every report, which the spec has always had room for
and the client never had an answer for. The position is the playing
item's or zero, never the engine's raw one: a session is installed
before its start resolves, and until media reaches the engine its
position still belongs to the item before it, which a controller would
render as a scrubber past the end of what the report names.

**A session frame is only this endpoint's if it says so.** Frames arrive
for anything the connection watches, and a controller screen following
another device receives that session here too. Adopting it would make
another endpoint's session this one's, so a later "play on the kitchen
speaker" would transfer someone else's playback and that session's end
would stop the reports for playback still running here.

**The queue rides only the reports where it changed**, per the mirror
contract, measured against the last snapshot reported rather than against
a dirty flag: every source of a queue change is covered, including the
ones playback never hears about. The end of a session clears that
record, because the next report then creates one and the server drops a
creating report that carries no queue: a registration (a fresh
connection means a fresh mirror session server-side), a session the
server says has ended, and playback stopping with nothing queued.
Without it, playing the same album twice in a row is a second session
that never comes into existence. What is emphatically not the end of a
session is the gap at a gapless crossing, where the outgoing session
lets go before the incoming one takes over: treating that as one would
re-send the whole queue at every track, and the server answers a queue
by re-resolving every entry, rewriting the session, and fanning a
player-topic invalidation out to every client.

**An edit is reported once it settles.** A drag emits a queue per frame
and no frame of one is worth a socket write, so a queue change schedules
a report 400 ms out rather than sending one, restarting that timer on
each further edit: held from the first edit instead, a long drag would
put an order nobody stopped on over the wire and leave the one they did
to the heartbeat. The index is not part of what counts as a change: what
moves the index is playback changing hands, which reports for itself
immediately.

**The verbs the client never answered are answered.** The server routes
`next`, `previous`, `set-queue`, `set-repeat`, and `set-shuffle` to
client endpoints, and this client replied "unknown verb" to all five, so
the app's own remote-control screen had two dead buttons against any
WaxDeck client. They are one call each on the gateway now. A refusal
carries its own message rather than a stringified exception, because
whoever sent the command is what renders it, and it says which refusal
it is: the end of a queue and no local playback at all are different
answers. The result frame carries a code beside the message per the
frame contract, but the server currently collapses every routed refusal
to `invalid-request` on its way back to the controller (recorded in
deferred work); the message is what actually travels today.

**A skip beats repeat one.** `QueueController.advance()` is the verb for
an item that ended and holds the queue in place under repeat one;
`skipNext()` is the verb for someone asking, and does not. Repeat one
holds an item against its own end, not against a skip. Previous steps
back, or starts the current entry over at the front, which is what a
second press means everywhere else. Neither does anything while live
radio has the engine: radio never queues, so there is nothing to step,
and stepping would take the engine back from the station the listener
chose, which no skip button means. That is the same rule the completion
and boundary handlers already follow.

**A controller's `stop` ends the queue.** The local queue is what the
mirror session is, so ending the session ends the queue: the deck bar
going quiet is the honest reflection of stopping playback from another
device. Pausing is a separate verb and leaves everything standing. The
engine is silenced by the handler rather than left to the session's
teardown, which flushes a checkpoint and a listen report first: on a
slow link that is two round trips of audio after the sender was told it
stopped. The queue verb still runs first, because the checkpoint it
takes reads the engine's position and a stopped engine has none.

**The endpoint answers for the start.** `playPids` resolves when the
entry it lands on has started or failed, and the gateway reads the
failure back off the state, so a load naming an item this client cannot
fetch answers `ok: false` the way it did when the endpoint owned the
session. Without it a routed load would be acknowledged before anything
played, and a failure would show only as an error pane on a device
nobody is looking at. Whether a start happened at all is a generation
counter, not a comparison of the errors: not every verb starts something
(a skip at the front replays what is loaded), and a repeated failure is
often the very same object, since an API exception is const-constructible
and a client that caches one hands back the same instance every time.

**Connect mirrors the session that owns the engine.** `liveSession` is
that session from the moment it is installed;
`NowPlaying.session` is the one to render, and appears once the item has
loaded. Between them is the window where an item is still loading, and a
command routed in during it belongs to the item loading, not to the one
it replaced. Playback tells Connect through one setter, so the endpoint
learns about a change of hands exactly once.

**An episode reached by pid alone finds its show.** `GET /items/{pid}`
answers a plain item detail with no show pid, and the per-show speed,
trim, and skip settings all hang off that. Resolving an entry now follows
a podcast to `GET /episodes/{pid}`, which carries one. It is a second
round trip on the paths that have no summary in hand (a handed-over
queue, a browse leaf, a restored queue the mirror could not name) and
none at all on the common one, where the screen passed the summary it
was already showing. A failure there leaves the episode playing with
default settings rather than not playing.

## Consequences

- The Android Auto browse leaf plays through the queue like everything
  else, so the car gets resume, checkpoints, listen accounting, skip
  maps, and the offline fallback from the same code the screen uses, and
  what it started is on the deck bar when the driver gets out.
- A queue loaded from another device is preloaded gaplessly, persisted,
  restorable, and editable, because it is not a special kind of queue.
- A remote controller watching a WaxDeck client now sees the real queue
  and the real index, where before it saw a single pid at index zero for
  anything played on screen.
- The endpoint controller has no session lifecycle left to get wrong. It
  cannot leak a session, cannot double-register one, and cannot
  checkpoint an item under another item's position, because it never
  holds one.
- `set-queue` and `load` are the same operation on this side. The server
  distinguishes them (a set-queue also rewrites its own entries first),
  but what reaches the client is identical apart from a set-queue always
  playing.
- The endpoint controller's tests run through the real container now: the
  real gateway over the real queue and the real playback, with only the
  repository, the engine, and the socket faked. A load that does not
  reach the queue fails them.
- Two things the device picker was getting wrong turned up while
  chasing an intermittent failure in the Connect journey and are fixed
  here: it read this client's endpoint id once at build, so a picker
  opened before registration landed offered to play here, on the device
  already playing; and it dropped its device list on any error rather
  than keeping the last one, which is the wrong trade for a list that
  refetches on every session anywhere. Neither was the cause of the
  intermittent failure, which predates this work and is now addressed
  where it lives: the journey runs under its own account, because
  sessions are visible per owner and several specs play the same
  fixture track under the shared admin account at once, so a session
  picked out of that list by the track it carries could be another
  spec's, ending when its browser closed.
- Repeat and shuffle reported from here are the local listener's, which
  is the right answer while this client drives the session and a
  question that does not arise while another endpoint does (the local
  queue is not the authority for a session running elsewhere, per
  ADR-0008).
- What a controller cannot do is reorder this client's queue: there is no
  verb for it in the protocol, and `set-queue` replacing the whole thing
  is the closest thing to one. Nothing needs it yet.
