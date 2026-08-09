# ADR-0056: What a book scrubber draws

Status: accepted

## Context

The waveform endpoint has always answered per audio file. That is the
right unit for a track, and the wrong one for an audiobook: a book's
seek bar spans a chapter or the whole book, and neither is a file. A
multi-file book's parts are wherever the ripper cut them, so drawing
part three's envelope under a chapter that starts inside part two is a
picture of the wrong audio.

So the client asked for a waveform only when `mediaType` was music
(`player_screen.dart`), and a book got a plain bar. The deferred entry
recorded the shape of the answer rather than the answer: the catalog
exposes `PeaksForItem(itemPID) []model.ItemPeaks`, every part's
envelope in one read, which is what a book-timeline waveform is built
from.

## Decision

**A book scrubber draws the whole book, and the chapter view is a slice
of it.** `GET /items/{pid}/waveform` gains `span=[part, item]`, default
`part`, so nothing that exists changes. Under `span=item` the answer is
one envelope over the item's whole timeline in the unchanged `Waveform`
shape.

**The stitch is server-side.** Buckets are spread evenly across the
total duration, and each part is given bucket-space in proportion to
how long it is - not to how many buckets it stored, which is a constant
per file and would make a two-minute prologue as wide as an hour-long
chapter. Chosen over client-stitched per-part arrays because that
would mean N requests, N cache entries, N validators, and the same
duration weighting written again in Dart; `PeaksForItem` answers the
whole thing in one read.

**Loudest-wins across the overlap, and it is truthful.** Verified
before it was relied on: waxbin's peaks are absolute full-scale
amplitude with no per-file normalisation anywhere (`peaks/peaks.go`
keeps a max in [0,1]; `maxPool` and `Pack` never rescale; `analyze.go`
stores the accumulator's output directly). So parts share a scale, and
a quiet part stays honestly quiet beside a loud one. A mean would lose
the transients a listener aims a scrub at, which is the same reason
`downsamplePeaks` takes a maximum.

**Readiness is all parts or nothing.** `ready` only when every part has
an envelope; a part that can never be measured makes the whole book
`unavailable`, and any other gap makes it `pending`. A partial stitch
would draw silence across minutes of real audio and a listener would
seek into it - the same reasoning that refuses a cue-carved track its
backing file's envelope.

**Resolution scales with duration**, clamped to 1000-4000 buckets
(about one per ten seconds). A fixed thousand would give a three-minute
chapter of a twenty-hour book three bars. This is not a contract
change: `resolution` is read rather than assumed on both sides of the
wire, which is what makes the number a rendering choice.

**The validator is a digest of everything the stitched bytes are built
from.** Re-analysing any part, or re-ordering the book, changes the
answer, so it has to change the ETag; part zero's essence alone would
let a client hold a superseded envelope for a day of freshness plus a
week of stale-while-revalidate.

Two corrections to that as first written, both found in review. The
essences are not the whole dependency: each part's *duration* decides
its span on the timeline and the total decides the bucket count, so a
rescan that corrects a lying VBR header rewrites every bucket while
leaving essence and analysis version untouched - byte-identical
validator, different picture. The durations are digested with the
essences for that reason. And the parts are digested rather than
joined, because a join does not survive its own success: a shipping
audiobook runs to a hundred parts and an essence digest is some seventy
characters, so the validator would be kilobytes, past the header
buffers reverse proxies ship with in both directions - and the
conditional request that exists to save the transfer would answer 400
instead of 304.

Client side, `BookSeek` becomes the consumer. The book view draws the
full envelope with chapter starts ticked along it; the chapter view
slices the same list, keeping the book's normalisation - rescaling a
quiet chapter to fill the bar would make the same audio look different
depending on which button was pressed last. The ticks are decoration
and carry no semantics: the slider already announces one position and
one span, and a screen reader hearing forty tick marks would be told
the shape of a picture it cannot see. The music gate in
`player_screen.dart` is untouched.

## Consequences

A single-file item under `span=item` answers exactly what `span=part`
answers, proven by the integration test rather than assumed, so the
client can ask for the whole item without branching on part count.
`partIndex` is ignored under `span=item` - a part index names nothing
across a book's timeline - and the answer does not echo one.

An unanalyzed part now costs the whole book its waveform where the
per-part path would have drawn one part's. That is the intended
trade: the book bar is one timeline, and the honest states for it are
"all of it" and "none of it yet".

The stitcher is pure and unit-tested on its own: duration weighting,
the scale, the maximum inside a bucket, a part shorter than one bucket
(kept - dropping it would silence real audio), and no gap at any
boundary. The endpoint's states and caching ride the integration suite
against real analyzed fixtures.

No e2e case. The shared stack's analyze state is not any one test's to
own, and a spec that ran the pass would be changing what every other
spec reads - the same reason the existing waveform coverage stops at
the Go suite.

Episode clip scrubbers are unaffected: episodes are never analyzed by
design, and they answer `unavailable` under either span.
