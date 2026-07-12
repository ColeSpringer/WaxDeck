# WaxDeck WebSocket events

> Status: contract sketch. The event hub and the Connect command bus are not
> implemented yet. This document pins the envelope and cursor model now so
> nothing else has to move later. Event payload schemas are defined as OpenAPI
> components in `openapi.yaml` (one spec generates every DTO); this file
> specifies the transport.

## Endpoint

`GET /api/v1/ws` is a standard WebSocket upgrade, authenticated like any API
call (session cookie or bearer token). One socket per client; all topics
multiplex over it.

## Envelope

Every server-to-client frame is a JSON object:

```json
{
  "topic": "catalog",        // subscription topic this frame belongs to
  "seq": 12345,              // cursor position on that topic's ordered stream
  "type": "item-changed",    // payload discriminator (an OpenAPI component name)
  "payload": { }             // schema per `type`
}
```

## Dual cursors

Two ordered streams, replayable independently:

- `catalogSeq`: WaxBin catalog changes (items, albums, artwork, and so on).
- `serverSeq`: WaxDeck-side state (connect sessions, job progress, user data,
  shares), from the `event_log` table.

Client subscribe frame:

```json
{ "catalogSince": 12000, "serverSince": 340, "topics": ["catalog", "user", "jobs"] }
```

The server replays both streams from the given cursors, then goes live with
about 250 ms of coalescing into batched invalidation frames.

## Backpressure and resync

Per-connection send queues are bounded. On overflow the server drops the buffer
and sends `{"type": "resync"}`, and the client must re-mirror via the sync
endpoints and resubscribe with fresh cursors. Change-log pruning can also force
this, so a full resync is a first-class client path, exercised continuously in
tests.

## User-state scoping

WaxBin's change log has no user dimension for `play_state`, `bookmark`, and
`play_queue` rows. The hub filters those entity types out of catalog fan-out
and re-emits them user-scoped on the server cursor (WaxDeck is the sole writer,
so it knows the acting user at write time). No client ever sees another user's
listening activity.
