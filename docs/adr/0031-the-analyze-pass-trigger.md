# 31. Giving the analyze pass a trigger

Date: 2026-07-28

## Status

Accepted.

## Context

The catalog has one pass that decodes audio. It measures loudness,
computes an acoustic fingerprint, and folds a waveform out of the same
decode, then stamps the file with the algorithm version so the work is
not repeated until the audio or an algorithm changes. It is resumable,
job-scoped, cancelable, and it has never run anywhere.

Nothing in WaxDeck called it. Library startup and the tools surface
start scans, and a scan hashes files and reads tags without decoding
them. So on every deployment that has ever existed, stored loudness,
fingerprints, and waveform peaks are empty, and three features rest on
data nothing writes: ReplayGain (which needs stored album gain to pass
as an explicit dB), duplicate grouping by fingerprint, and the waveform
seek bar, whose endpoint is otherwise a pure read.

What was missing was never an algorithm. It was a trigger and a policy.

## Decision

**Two triggers, both explicit.** `POST /library/analyze` runs it now and
answers the same `Job` shape a rescan does. An `analyze` schedule kind
sits beside scan, backup, and prune, off by default, defaulting to a
weekly small-hours cron when an administrator switches it on.

**Never automatic after a scan.** A scan is what happens when files
arrive, and it is cheap enough to run nightly on a large library.
Chaining a full decode to it would make the cheap thing expensive, and
the trigger an administrator was reasoning about ("scan my new files")
would not be the one they got. The two passes take different job scopes
upstream, so they can run at the same time; that is a capability, not a
schedule.

**Call `StartAnalyze`, not `Analyze`.** This is the thing that would
otherwise be built wrong, and it is invisible in a unit test. The plain
`Analyze` facade runs the work inline: it blocks for the whole decode
and only names its job once the run has finished, so an endpoint built
on it could not answer a `Job` at all and a cron tick would stall for
the length of the pass. `StartAnalyze` returns a PID as soon as the job
row exists, which is exactly what `Rescan` already uses `StartScan` for.
Measured on the corpus below, the endpoint returns in about a
millisecond with the job reading `running`.

**Both triggers handle the conflict, differently.** Analysis takes an
`analyze` scope lease, so a second start while one is in flight answers
`CodeConflict`. Run-now maps that to 409. The cron path must *not* mark
the schedule as run: marking it would defer the pass to the next firing,
a week away on the default. It logs and leaves the schedule unmarked, so
the next 30-second tick retries. That is the shape the scheduled-backup
collision already uses, copied rather than reinvented.

**`AnalyzeOptions.WriteReplayGainTags` stays false.** Upstream ORs the
per-run flag with the library's own configured toggle, so leaving it
unset means "do whatever this deployment is configured to do". Setting
it here would override that choice from a trigger, which is not what a
trigger is for. It is not a gap.

**There is nothing to throttle, and no throttle to ask for.** Starving
live streaming on a busy box is the obvious worry and it does not apply:
the pass is a plain serial loop over files upstream, with no goroutines
and no worker-count option. It decodes one file at a time and uses one
core. It is slow, not greedy. Recorded here so the question is not
reopened as a WaxDeck-side interlock or an upstream request.

## What it costs

Measured on this repo's own corpus generator: 200 FLAC files, about 620
seconds of audio, on an AMD Ryzen 5 5500 with no `fpcalc` installed.

    scan     15.6s
    analyze   5.2s   (38 files/s, about 120x realtime)

Two things keep that number from being a promise. The corpus files are
three seconds long, so per-file overhead is a large share of each one; a
library of real four-minute tracks amortizes that over far more audio
and does better per second of audio, not worse. And the fingerprint half
decodes at most the first two minutes of a file while the loudness and
waveform measurement decodes all of it, so the two halves diverge as
tracks get longer.

The per-file work is two decodes either way, which is worth stating
plainly because "a full PCM decode of every file" undersells it. Without
`fpcalc` the fingerprint decodes in-process and the measurement decodes
again. With `fpcalc` the fingerprint is a subprocess that decodes
externally and the measurement decodes in-process. Loudness and peaks
share one decode through a tap, so the waveform itself is free once the
loudness is being measured.

## Consequences

The schedule's helper text in the admin UI says what it costs, because
"Analyze audio" beside "Library scan" reads like another scan and is
not.

`GET /items/{pid}/waveform` ships alongside this and is a pure read of
what the pass stores. Its `pending` state points here: an item reads
pending precisely because this pass has not covered it yet, which is the
answer for every item on every deployment until an administrator turns
one of these triggers on.

Podcast episodes are never analyzed, upstream and by design, because
fingerprinting hours of speech would pollute the duplicate-detection
min-hash. That is why the waveform endpoint answers `unavailable` rather
than `pending` for them: a client told to poll would poll forever.

Quality upgrade groups start working, with no code change. The surface
is built and shipped (`ListUpgradeGroups` over the catalog's fingerprint
index, admin-only) and has been answering an empty list on every
deployment for want of fingerprints to group by. An instance that runs
the pass gets its real answer.

ReplayGain wiring is unblocked but not built: the values now exist,
and passing stored album gain into timelines lands with the crossfade
settings that make it visible.
