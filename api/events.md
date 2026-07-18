# WaxDeck WebSocket events

> Status: the event hub and the invalidation channel described here are
> implemented. The Connect command bus (client-to-server commands beyond the
> subscribe frame, acks, correlation IDs) is not implemented yet; its envelope
> will be specified here with the same rigor before it lands. Frame payload
> schemas are OpenAPI components in `openapi.yaml` (`WsSubscribeFrame`,
> `WsEventFrame`); this file specifies the transport.

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

## Model: invalidate, then pull

The socket carries no entity payloads. It tells a client *that* a stream its
mirror follows has moved; the client pulls the sync endpoints to catch up.
This keeps the socket cheap, makes delivery loss harmless (the next
invalidation or a poll covers it), and means the sync endpoints are the
single hydration path whether or not a socket is connected.

## Subscribe

The client sends exactly one frame, immediately after the upgrade
(`WsSubscribeFrame`):

```json
{ "catalogSince": "…", "serverSince": "…", "topics": ["catalog", "user"] }
```

Cursors are the opaque values the client's mirror is at (from the sync
endpoints' `nextSince`). The server compares them to the current stream
positions and immediately sends an `invalidate` per topic the client is
behind on, then goes live. A client with no mirror yet omits the cursors,
receives only live invalidations, and snapshots through the sync endpoints;
subscribing before or after the snapshot are both sound, because frames
carry no data. To change topics, reconnect.

Topic names the server does not recognize are ignored. Omitting `topics`,
sending an empty list, or sending a list with no recognized names all
subscribe to every topic: an extra invalidation costs one cheap pull, while
a connection that looks live but delivers nothing is silent staleness.

## Server-to-client frames

Every frame is a JSON object (`WsEventFrame`). Two types today; frames with
an unrecognized `type` must be ignored.

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

Two ordered streams, replayable independently through the sync endpoints:

- `catalog` (`catalogSeq`): WaxBin catalog changes, item-granular. WaxBin's
  own change feed also carries file, album, artist, and other entity rows;
  the hub relays only what a summary mirror can act on.
- `user` (`serverSeq`): the calling user's own WaxDeck-side state (playback
  state, preferences), from the `event_log` table.

Cursors are opaque strings. Internally they bind a stream generation, so a
rebuilt catalog or restored database invalidates stale cursors instead of
silently serving diverged history.

## User-state scoping

WaxBin's change log has no user dimension for `play_state`, `bookmark`, and
`play_queue` rows. The hub filters those entity types out of catalog fan-out
entirely. Play state is re-emitted user-scoped on the server cursor (WaxDeck
is the sole writer, so it knows the acting user at write time); bookmarks
and queues will ride the same path when their API surfaces land. No client
ever sees another user's listening activity.
