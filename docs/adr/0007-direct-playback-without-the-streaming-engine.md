# 7. Direct playback without the streaming engine

Date: 2026-07-19

## Status

Accepted

## Context

The WaxFlow sidecar was designed as the streaming engine: a four-rung
ladder (direct, transmux, cut, transcode) behind one proxied stream
URL. The implementation drifted into treating it as a prerequisite:
with no `WAXDECK_FLOW_URL`, play-info answered an error, `/media/stream`
was a 501 stub, and the Subsonic stream endpoint refused. A server
without the sidecar could browse everything and play nothing, even a
plain MP3 the client decodes natively.

Intent was the opposite: the sidecar is an opt-in for
people who want transcoding and streaming over constrained links;
local playback of the files themselves must work without it.

## Decision

When no streaming engine is configured, playback serves the original
file bytes directly:

- Play-info resolves the item's backing file (or the selected part of
  a multi-file book) and mints a URL onto the same media-token
  download endpoint offline downloads use: ranged, resumable, byte
  identity pinned, visibility enforced at mint.
- A track carved out of a larger file (CUE rips) serves the whole
  backing file and the response carries `spanStartMs`/`spanEndMs`;
  the first-party player clips to the window through the audio engine
  port's clip parameters, so positions, duration, and completion stay
  track-relative. The same clip path now also applies to offline
  playback of downloaded originals, which had stored the window
  without applying it.
- The Subsonic surface streams by redirect to the same endpoint.
  Span-carved tracks are the one refusal (third-party clients cannot
  clip); the error says why.
- What direct mode honestly cannot do: transcoding and format policy,
  gapless timelines, voice boost, sample-exact server-side span
  cutting. Playable formats are whatever the client decodes; on the
  web that is the browser's codec support.

## Alternatives considered

- Bundling the sidecar into `make run` and the default deployment.
  Rejected as the primary answer: it fixes the dev experience while
  keeping the engine a hard prerequisite, which contradicts the
  design intent. It remains a fine thing to do for people who want
  the full ladder.
- Teaching WaxDeck itself to cut spans (decode and re-encode
  windows). Rejected: that rebuilds the engine's job inside the
  server the engine was extracted from.

## Consequences

- The engine becomes a genuine upgrade, not a dependency: adding
  `WAXDECK_FLOW_URL` restores the full ladder with no client change
  (play-info simply stops emitting span fields).
- Clients must treat span fields as load-bearing: a player that
  ignores them would play a whole rip in place of one track. The
  engine port's clip contract is the enforcement point.
- The desktop engine backend (mpv via the just_audio bridge) needs
  its clip-window behavior verified on a real desktop build; recorded
  in deferred-work.
