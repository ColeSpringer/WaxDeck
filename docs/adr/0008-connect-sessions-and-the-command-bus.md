# 8. Connect sessions and the command bus

Date: 2026-07-21

## Status

Accepted

## Context

Multi-device control needs one design that covers three shapes at
once: a phone telling a Chromecast what to play, a laptop remotely
controlling the phone, and the common case of a client just playing
its own audio while other devices can see and steer it. Prior art
splits two ways: client-proxied casting (the controlling app owns the
device session, so control dies when that app sleeps) and fully
server-authoritative players (every local tap pays a round trip).

## Decision

**Playback authority is split by where the audio renders.** Sessions
on device endpoints the server drives itself (cast, DLNA renderers,
the jukebox output) are server-authoritative: the server dials the
device, pushes media URLs, consumes its status stream, advances the
queue, and writes positions through to per-user playback state. A
client playing its own audio is client-authoritative: it applies every
interaction locally and mirrors state to the server as coalesced
session reports (on change plus a five second heartbeat). Both are
controlled identically; authority states who advances playback and
whose position wins, never who may control. A transfer converts
between the two: the server loads the target with the extrapolated
snapshot, rebinds the session to it, then quiets the source, and the
session id survives the move so controllers keep following it.

**Live verbs ride the existing WebSocket as a command bus; lists stay
invalidate-then-pull.** Commands carry client correlation ids and are
answered exactly once (ack or typed error). Commands for a session on
a registered client endpoint route to that client as endpoint
commands, answered with command results and followed by the state
report that actually updates watchers. Session state streams only to
the one session a connection watches, position extrapolation runs
client-side against an NTP style clock offset measured over the same
socket, and lifecycle changes fan out as cursorless `player` topic
invalidations. The invalidate-then-pull economy of the event channel
survives intact: the only payload-bearing frames describe ephemeral
state with no cursor and no replay.

**Endpoints are visible by ownership.** Client endpoints exist while
their socket lives, derive their id from the device session so
reconnects keep identity, and are visible only to their owner. Device
endpoints are shared, persist their identity in `player_endpoints`
under the device's own durable key, and are dialed on demand so idle
devices hold no connections.

**Cast queues ride HLS timelines when the engine offers them.** A
multi-item cast load mints one gapless timeline and plays it as a
single stream, with per-member boundaries mapping positions both
ways. The proxied HLS tree authorizes every fetch by media token while the
actual byte authorization is the upstream signature already embedded
in the playlists, so the proxy never attaches its API key to an HLS
request and a token holder can fetch nothing beyond what the signed
playlists name. Timeline tokens are sized to the queue duration, so a
long album never expires mid-listen.

## Consequences

- Local taps never pay a network round trip, and a sleeping phone
  never strands a speaker.
- The server owns re-mint orchestration for immutable timelines;
  queue edits on cast sessions reload rather than mutate.
- A mirror session's truth lives in the client; the server's copy is
  a checkpointed shadow, which is why crash recovery marks sessions
  inactive instead of resuming them.
- The one-session-per-endpoint invariant plus a short report grace
  after server-side ends keeps a stale reporter from spawning ghost
  sessions during transfers.
