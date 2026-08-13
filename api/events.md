# WaxDeck WebSocket events

> Status: the event hub, the invalidation channel, and the player command
> bus described here are implemented. Frame payload schemas are OpenAPI
> components in `openapi.yaml` (`WsSubscribeFrame`, `WsEventFrame`, and the
> `WsCommandFrame` family); this file specifies the transport.

## Endpoint and handshake

`GET /api/v1/ws` is a standard WebSocket upgrade, authenticated like any API
call (session cookie or bearer token). An unauthenticated upgrade is refused
with HTTP 401 before the handshake completes. Because WebSocket requests are
not bound by `SameSite` cookie rules or CORS, the server validates the
`Origin` header on cookie-authenticated upgrades: a browser-sent Origin that
is not the server's own origin is refused with 403. Bearer-authenticated
upgrades (native clients, which may send no Origin) are exempt.

One socket per client; all topics multiplex over it. Frames are JSON text
messages. A connection that has not sent its subscribe frame within a few
seconds is closed.

## Model: invalidate, then pull; commands are a separate plane

For mirrored data the socket carries no entity payloads. It tells a client
*that* a stream its mirror follows has moved; the client pulls the sync
endpoints to catch up. This keeps the socket cheap, makes delivery loss
harmless (the next invalidation or a poll covers it), and means the sync
endpoints are the single hydration path whether or not a socket is
connected.

The player command bus (below) is deliberately different: it is a live
control plane, not a mirror. Command, ack, and session-state frames carry
data because they describe ephemeral remote-playback state that has no
cursor and needs no replay; a lost state frame is corrected by the next
report, and a lost command is the sender's to retry (commands are
idempotent absolute-state verbs, never deltas). The invalidate-then-pull
model still governs the *lists* around the command bus: session and
endpoint lifecycle changes arrive as `invalidate` frames on the `player`
topic, and the client pulls `/player/endpoints` and `/player/sessions`.

## Subscribe

The client sends exactly one subscribe frame, immediately after the upgrade
(`WsSubscribeFrame`):

```json
{ "catalogSince": "abc", "serverSince": "def", "topics": ["catalog", "user"] }
```

Cursors are the opaque values the client's mirror is at (from the sync
endpoints' `nextSince`). The server compares them to the current stream
positions and immediately sends an `invalidate` per topic the client is
behind on, then goes live. A client with no mirror yet omits the cursors,
receives only live invalidations, and snapshots through the sync endpoints;
subscribing before or after the snapshot are both sound, because
invalidations carry no data. To change topics, reconnect.

Topic names the server does not recognize are ignored. Omitting `topics`,
sending an empty list, or sending a list with no recognized names all
subscribe to every topic: an extra invalidation costs one cheap pull, while
a connection that looks live but delivers nothing is silent staleness.

The subscribe frame must be the first client frame. After it, the client
may send command-bus frames (below) at any time; a client that only wants
invalidations never sends anything else.

## Server-to-client frames (event channel)

Every frame is a JSON object. The event channel uses two types
(`WsEventFrame`); the command bus below adds its own. Frames with an
unrecognized `type` must be ignored.

Invalidation, coalesced over roughly 250 ms windows:

```json
{ "type": "invalidate", "topic": "catalog" }
```

The named stream moved: pull the matching sync endpoint (`catalog` topic:
`/sync/catalog`; `user` topic: `/sync/server`) from the client's own cursor.
One frame can cover many changes, and a redundant pull is harmless.

Resync:

```json
{ "type": "resync", "topic": "catalog" }
```

Continuity was lost for the named stream, or for every stream when `topic`
is absent (this connection's bounded send queue overflowed, or retained
change history no longer reaches the client's cursor). The client drops the
affected mirror halves, re-mirrors through the sync endpoints (snapshot for
`catalog`, re-mint and re-hydrate for `user`), then closes the socket,
reconnects, and resubscribes with the fresh cursors. Change-log pruning and
visibility-grant changes surface the same way through a 410 `sync-reset` on
the sync endpoints, so a full resync is a first-class client path, exercised
continuously in tests.

## Topics and cursors

Two ordered streams, replayable independently through the sync endpoints,
plus one cursorless topic:

- `catalog` (`catalogSeq`): WaxBin catalog changes, item-granular, plus
  podcast show rows (a show is list-level metadata every subscriber's UI
  renders, and it is not per-user state; shows travel through
  `/sync/catalog` as their own `upsert-show` entries, which clients from
  before that operation existed drop harmlessly). WaxBin's own change
  feed also carries file, album, artist, and other entity rows; the hub
  relays only what a summary mirror can act on.
- `user` (`serverSeq`): the calling user's own WaxDeck-side state (playback
  state, preferences, podcast subscriptions and their settings, per-book
  playback settings), from the `event_log` table. Curation surfaces ride
  this stream as marker kinds (`review`, `upload`, `task`) carrying only
  the pid to refetch by: the review queue, upload sessions, and tool
  tasks are live reads, not mirrored state, so the markers hydrate
  nothing. Review markers fan out to every administrator plus the
  entry's uploader; upload and task markers go to their owner and the
  administrators.
- `player` (no cursor): the caller's visible player-endpoint and
  playback-session *lists* changed (an endpoint appeared or went offline,
  a session started, ended, or moved to another endpoint, or a session's
  queue was replaced). Pull `/player/endpoints` and `/player/sessions`;
  both always return current truth, so there is nothing to replay and no
  cursor to carry. Position movement and play/pause flips do not
  invalidate this topic; watchers get those as `session` frames.

Cursors are opaque strings. Internally they bind a stream generation, so a
rebuilt catalog or restored database invalidates stale cursors instead of
silently serving diverged history.

## User-state scoping

WaxBin's change log has no user dimension for `play_state`, `bookmark`,
`play_queue`, and `playlist` rows. The hub filters those entity types out of
catalog fan-out entirely. Play state is re-emitted user-scoped on the server
cursor (WaxDeck is the sole writer, so it knows the acting user at write
time); bookmarks and queues will ride the same path when their API surfaces
land. No client ever sees another user's listening activity.

Playlists ride the `user` stream too (the `playlist` event kind on
`/sync/server`): a mutation reaches the owner always, and a shared
playlist's mutation additionally reaches every other user, since shared
playlists are visible to all. A playlist leaving a viewer's visibility
(deletion, a shared list flipped private, or a rule-replace retiring the
old pid) reaches those viewers as a playlist-absent event, so mirrors never
strand a row they can no longer read. Private playlists never appear on
anyone else's stream, which is why playlist rows cannot ride the catalog
stream. A smart playlist's *membership* drift (an underlying star, rating,
or catalog change) emits no playlist event; clients re-evaluate on the
play-state and catalog invalidations they already receive.

Podcast subscriptions are WaxDeck-side per-user state and ride the `user`
stream (the `subscription` event kind on `/sync/server`), so one user's
subscribe never invalidates another user's *user* mirror; the show and
episode rows a first subscription creates are catalog entities like any
other and reach every client through the `catalog` stream. Per-book
playback settings are per-user state the same way (the `book-settings`
event kind).

## The player command bus

Everything below rides the same socket, after the subscribe frame. Frame
payload shapes are OpenAPI components (`WsCommandFrame`, `WsAckFrame`,
`WsErrorFrame`, `WsRegisterEndpointFrame`, `WsEndpointCommandFrame`,
`WsCommandResultFrame`, `WsSessionReportFrame`, `WsSessionFrame`,
`WsWatchFrame`, `WsPingFrame`, `WsPongFrame`). The REST surface
(`/player/*`) owns endpoint listing, session creation, transfer, and
teardown; the bus owns the live verbs, endpoint registration, state
reporting, and clock sync. Server-to-client frames with an unrecognized
`type` must be ignored, exactly as on the event channel; client-to-server
frames with an unrecognized `type` are answered with an `error` frame
carrying `invalid-request` (and the frame's `id` when it sent one), never
with a closed socket.

### Correlation and errors

Every client-initiated request frame (`cmd`, `register-endpoint`) carries a
client-chosen `id`, opaque to the server and unique per connection while
the request is outstanding. The server answers each exactly once: an `ack`
frame echoing the `id` on success, or an `error` frame echoing it on
failure. `error` frames carry the API error vocabulary in `code` (
`invalid-request`, `not-found`, `forbidden`, `endpoint-offline`, plus
`timeout` when a routed command's target connection did not answer within
the server's routing deadline, ten seconds). An `error` frame without an
`id` is connection-level (a malformed frame that could not be parsed far
enough to find one). A refusal whose code covers several causes may also
carry `params`, the same flat string map on the same best-effort terms
the REST `Error` schema documents, so a refusal reachable over either
transport says the same thing on both. A `cmd-result` from a player
client never carries params: the codes a client endpoint may answer are
whitelisted before they reach the wire, and passing its own detail
through to other listeners would need the same treatment.

### Commands (controller to server)

```json
{ "type": "cmd", "id": "c7", "sessionId": "ps-01...", "verb": "seek",
  "positionMs": 83000 }
```

Verbs: `play`, `pause`, `stop`, `seek` (`positionMs`), `next`, `previous`,
`set-volume` (`volume`, 0 to 1), `set-rate` (`rate`), `set-queue`
(`itemPids`, `index`, optional `positionMs`), `set-repeat` (`repeat`:
`off`, `all`, `one`), `set-shuffle` (`shuffle`). Arguments are absolute
state, never deltas, so a retried command is harmless. Unknown verbs
answer `invalid-request`, and so do `set-volume` and `set-rate` against
an endpoint whose capability flag is false. The `ack` for a session
command carries the updated session snapshot when the server has one;
for commands routed to a playing client the snapshot may lag or be
absent (the client's own report is what updates the mirror), and
controllers render those results from the following `session` frame.
`stop` ends playback but keeps the session; deleting the session is
REST (`DELETE /player/sessions/{id}`).

Shuffle is applied to the queue itself: a session's entries always list
the true play order, `set-shuffle` on reorders the unplayed remainder
(bumping the queue version), and `set-shuffle` off keeps the current
order.

Commands are authorized like the REST session surface: your own sessions
always; another user's session only when it plays on a shared endpoint.

### Endpoint registration (player client to server)

A first-party client that is willing to be controlled registers once per
connection:

```json
{ "type": "register-endpoint", "id": "r1", "name": "Kitchen laptop",
  "volumeControl": true, "rateControl": true }
```

The `ack` carries the endpoint's `endpointId`. The endpoint id is derived
from the client's device session, so the same signed-in device keeps its
id across reconnects; a second connection registering under the same
device session replaces the first as the routing target. The endpoint
exists while its connection lives: closing the socket removes it from
`/player/endpoints` and ends any active session on it (the session's
final state is checkpointed server-side). After a reconnect the client's
first report creates a fresh session id; session ids never survive their
session. Client endpoints are visible only to their owning user; device
endpoints the server itself drives (cast, DLNA renderers, the jukebox)
are shared and visible to every user.

### Routed commands (server to player client)

When a controller's command targets a session playing on a registered
client endpoint, the server routes it to that client:

```json
{ "type": "endpoint-cmd", "id": "e42", "sessionId": "ps-01...",
  "verb": "load", "itemPids": ["tr-01..."], "index": 0,
  "positionMs": 83000, "play": true }
```

Verbs are the command verbs plus `load` (start this queue at this index
and position; the client resolves play-info for the pids itself, so token
shaping stays where it lives). The client executes against its local
engine and answers exactly once:

```json
{ "type": "cmd-result", "id": "e42", "ok": true }
```

A `cmd-result` with `ok` false carries `code` and `message`. The server
converts a missing result within the routing deadline into a `timeout`
error for the controller, and ignores a result that arrives after the
deadline. After executing, the client reports state (next section); the
report, not the result, is what updates watchers. A `load` also
establishes the session's queue on the server, so the published queue
version bumps there, not on the client's report.

### Session reports (player client to server)

A client playing local audio is the authority for its own playback; the
server mirrors it. The client sends a report on every state change (play,
pause, seek, track change, queue change) and at least every five seconds
while playing:

```json
{ "type": "session-report", "playing": true, "positionMs": 84100,
  "index": 0, "rate": 1.0 }
```

The steady fields (`playing`, `positionMs`, `index`, `rate`, `volume`,
`repeat`, `shuffle`) carry current truth on every report; a track
advance is just a report with the new `index`. `itemPids` rides only
the reports where the queue itself changed, with a bumped
`queueVersion`, plus the first report of a connection that is already
playing, since that report creates (or, after a reconnect, re-creates
under a fresh id) the client's mirror session, and a session without a
queue is unrenderable; a creating report without `itemPids` is ignored.
The server answers a creating report with a `session` frame carrying
the assigned session id; subsequent reports are unacknowledged. The
queue version the server publishes on the session is its own monotone
counter (stable across transfers); the reported `queueVersion` is only
the change signal. A report for a session the server has ended (for
example, a transfer moved playback elsewhere and this client kept
reporting) is answered with a `session` frame for the ended id and
`ended` true, telling the client to stop treating its local playback as
that session.

After a `load` routed to a client endpoint, the client's own session
reports continue under the same session id the load named: the session
becomes client-authoritative again (its `authority` reads `mirror`), while
staying remotely controllable through routed commands. Authority states
who advances the queue and whose position wins, not who may control.

### Session state to watchers (server to controller)

A controller that is rendering one session live (remote-control screen,
device picker detail) watches it:

```json
{ "type": "watch", "sessionId": "ps-01..." }
```

Watching follows session visibility: your own sessions, others' only on
shared endpoints. One watched session per connection; a new `watch`
replaces the old one, and `watch` without `sessionId` stops watching. A
successful watch is not acked; the server immediately sends the current
state as a `session` frame, then pushes another on every state change
and about once per second while the session plays. A watch of an
unknown or invisible session answers an `error` frame with `not-found`,
echoing the frame's optional `id` when it sent one:

```json
{ "type": "session", "session": { "id": "ps-01...", "playing": true,
  "positionMs": 84100, "positionAt": "2026-07-19T18:30:00.123Z", ... } }
```

The `session` payload is the REST `PlaybackSession` schema, with one
economy: `entries` rides the first frame of a watch and every frame
where `queueVersion` bumped, and is omitted otherwise (state frames at
1 Hz must not carry a 500-row queue). Controllers render position by
extrapolating from `positionMs` at `positionAt` using `rate` while
`playing`, against the clock offset below, so scrubbers track smoothly
instead of jittering with delivery latency. A `session` frame with
`ended` true is terminal for that delivery context: the session ended
or left your visibility (a transfer to a private endpoint); re-list
`/player/sessions` to learn which. State frames are best-effort: they
are dropped rather than queued for a slow connection, because the next
report supersedes them anyway.

Play and pause flips on an unwatched session deliberately do not
invalidate the `player` topic (position movement never does): a device
picker rendering many sessions refetches when opened and watches the
one it focuses. What does invalidate `player` is lifecycle: sessions
starting, ending, changing endpoint, or replacing their queue, and
endpoints appearing or going offline.

### Clock sync

```json
{ "type": "ping", "t": 1786213800123 }
{ "type": "pong", "t": 1786213800123, "at": 1786213800161 }
```

`t` is an opaque client timestamp echoed back; `at` is the server's clock
in Unix milliseconds when it handled the frame. NTP-style: offset is
`at - (send + receive) / 2` on the client's clock. Clients measure at
connect and refresh occasionally; the offset makes `positionAt`
extrapolation immune to clock skew. `ping` frames are unrelated to
WebSocket protocol pings, which the server also sends as keepalive.
