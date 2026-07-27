# 18. Gapless lives at the engine port, as a two-item window

Date: 2026-07-25

## Status

Accepted.

## Context

`AudioEnginePort` played one item at a time: `load()` took a single URL,
`completed` fired when it ran out, and callers loaded the next thing.
That is a reload between every track, which is audible on anything cut to
run continuously: a live album, a mixed record, a DJ set, and every
carved rip where two tracks share one file.

The client rewrite promotes the queue to a user-visible concept, so the
question could no longer be deferred: either the port learns about the
item after the current one, or gapless gets retrofitted later through a
layer that has already been built on the single-item assumption. The
retrofit reopens the conformance suite, the Connect endpoint, and the
Android Auto queue at the same time.

The other end of the range is an engine that owns the queue outright:
hand it the list, let it advance. just_audio would take that happily.
It puts ordering, shuffle, repeat, and provenance behind a plugin
boundary the app does not control, splits queue authority with the
Connect session that already owns it during a remote handoff, and makes
the queue's persistence a function of a plugin's internal state.

## Decision

**The port learns about exactly one item ahead.** `preloadNext(url,
{mimeType, clipStart, clipEnd})` prepares the item that follows;
`clearPreload()` drops it; `itemBoundary` fires when playback crosses
into it. The queue stays entirely in WaxDeck's own controller, which
decides what the next item is and hands the engine that one item.

**Item-ended and queue-ended are different signals.** `completed` (and
`EngineProcessingState.completed`) now means one thing: the engine has
run out. Crossing into a preloaded item stays `ready`, keeps playing,
and fires `itemBoundary`. A caller that advances on `completed` is
therefore correct whether or not the engine preloads, which is what
makes the degradation below invisible to it.

**Preloading is best effort, and the port says so.** An engine that
cannot preload leaves `preloadNext` a no-op and runs off the end; the
caller advances on `completed` as it always did and gets a small gap.
The conformance suite asserts that degraded shape for a harness that
declares it, so "we cannot do this here" is a tested contract rather
than an undefined one. The deferred hls.js web engine will land against
that clause.

**`JustAudioEngine` implements it as a sliding two-item source list.**
just_audio 0.10's `setAudioSources` holds the playing item plus the
preloaded one; the platform makes crossing between them gapless
(ExoPlayer's playlist, mpv's `prefetch-playlist`, which desktop now
switches on). The window never grows past two: the consumed item is
dropped at the crossing, not later. That timing is deliberate: on the
mpv bridge, renumbering the list republishes position zero, which is the
truth at the crossing and a rewind at any other moment. Nothing is
addressed by the platform's own index, which arrives by event and so
lags a crossing; the engine holds the two sources it put in the window
and finds them by identity, so an edit can never remove the item that is
playing.

**Stopping releases the window, not just the media.** A preload that
survived a stop would start playing on the next `play()`, an item the
caller stopped before reaching. Both engines drop it, and the port says
so.

**The engine answers for a clip window's length itself.** Two tracks
carved from one album rip are one file to the platform, and the mpv
bridge re-reports a length only when the file's own length changes, so
it leaves the new window with none; it also blanks the length on every
source-list edit and never restores it. Both are the engine's to
normalize, exactly as it already normalizes just_audio's `playing` flag
after completion: it computes a closed window's length and holds the
last length reported for the item playing. Windows with an open end and
live streams have no length to compute and keep reporting whatever the
platform says.

## Consequences

- The queue controller owns ordering and provenance, and the engine
  never has an opinion about what plays next. Connect remains the
  authority during a remote session without contending with a plugin's
  internal playlist.
- Accounting rolls at `itemBoundary`: the session layer finalizes the
  outgoing item's checkpoint and listen report and starts the next
  item's against a stream that never stopped. Nothing about
  checkpointing, trim maps, or offline fallback changes.
- **A load that interrupts an in-flight preload owns the window.**
  just_audio funnels every source-list change through one playlist lock,
  so a preload that has to drop a stale source before adding its own can
  have that add land after a load replaced the list, and the interrupted
  preload then plays after the loaded item, gaplessly, as a track nobody
  queued. Reproduced against the real desktop engine. Loading therefore
  queues a trim behind whatever is in flight, and an edit records a
  preload only if the window it belongs to still exists; the conformance
  suite pins the case, and fails without either half.
- Only direct-play streams are worth preloading. A preloaded transcode
  would open a second server-side session, so the admission policy that
  rides on this (playback owns it, not the engine) preloads passthrough
  items and loads everything else on advance.
- The conformance suite grew a gapless group, and it runs against the
  real desktop engine as well as the fake: crossing fires the boundary
  and not completion, playback neither pauses nor re-prepares, clip
  windows survive the crossing, a replaced preload is the one that
  plays, and the item after a boundary ends the queue. The same run
  verified clip windows on the mpv backend end to end, which is what
  `docs/deferred-work.md` had open.
- Sample adjacency is asserted where a manual clock makes it exact (the
  fake carries the overshoot into the next item's head). Against a real
  backend the honest statement is that playback never stopped and the
  media was never re-prepared; an audible-gap check on real hardware
  stays a human step.
- `prefetch-playlist` is documented as experimental upstream. Without
  it the window still plays correctly, with the load gap the port
  allows, so the downside of it misbehaving is the behavior we would
  have had anyway.
- **The engine's own window length is preferred over the platform's, and
  that is not a staleness risk.** It reads like one, so it is recorded
  here rather than re-derived: just_audio keys its duration to the
  current index and caches one per source, so at a crossing it can never
  answer with the finished item's length, and an idle player after
  `stop()` reports the stopped item's cached duration. The engine's held
  value is only ever the answer where a closed clip window is the sole
  source of one, which is exactly the case that reported nothing at all
  before.
