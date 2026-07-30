# 15. Virtual tracks in gapless timelines, gated on sidecar support

Date: 2026-07-23

## Status

Accepted.

## Context

A virtual track is a window within a shared single-file album rip,
carved out by a cue sheet: it plays a sample range of the backing file
rather than the whole file. Gapless playback mints a server-side
timeline (`POST /player/timeline`) that names each queue member as a
source the streaming sidecar stitches without gaps.

The sidecar's timeline sources originally addressed a whole file. A
virtual member has no whole-file identity to hand over - only a window
into another file - so the timeline builder refused any queue holding a
virtual track and both callers (the queue-timeline mint and the
connect-session timeline) bailed on the whole timeline rather than
serving a wrong one. A carved track could play on the direct path,
which clips the window correctly, but never as part of a gapless run.

The sidecar then grew member windows: a timeline source may carry a
`From`/`To` sample range, advertised through
`caps.Delivery.TimelineMemberWindows`. An older sidecar without the
capability would mishandle a windowed source (serve the whole file or
error), so WaxDeck cannot emit windows unconditionally.

## Decision

The flow bridge exposes a `TimelineMemberWindowsSupported()` capability
helper (reading `caps.Delivery.TimelineMemberWindows`), mirroring the
existing `TimelinesSupported()`, and nothing outside the bridge pokes
the raw caps struct. When windows are supported the timeline builder
emits a virtual member as a windowed source (`From: FromSample`,
`To: ToSample`); when they are not, it keeps the refusal.

The two callers gate on the same helper. When windows are supported and
a queue holds a virtual member, they build the timeline instead of
bailing; when they are not, the queue-timeline mint returns nil (the
client falls back to per-item playback) and the connect-session path
answers a conflict, exactly as before.

## Consequences

- A cue-carved track joins a gapless timeline on a sidecar that
  advertises member windows, and playback is gapless across it. On an
  older sidecar the queue degrades to per-item playback, which still
  clips the window correctly through the direct path - no track is
  ever skipped or served whole by mistake.
- The refusal is all-or-nothing per timeline, not per member: a
  timeline with one unsupported virtual member is refused whole rather
  than served with that member silently dropped, because a dropped
  member is a skipped track, while a refused timeline falls back to a
  path that plays every member.
- Capability access stays behind the bridge. A future delivery
  capability follows the same helper shape rather than spreading raw
  `caps` reads across the API layer.
