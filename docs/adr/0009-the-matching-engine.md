# 9. The matching engine

Date: 2026-07-21

## Status

Accepted

## Context

WaxDeck's metadata completer promises beets-quality release matching
with a Picard-style review queue: files are identified against
MusicBrainz, confident matches apply themselves, uncertain ones wait
for a human with ranked candidates and a field diff. WaxBin does not
provide this. Its enrichment spine resolves identity only: the
MusicBrainz text search accepts or rejects a single best hit above a
fixed score, AcoustID picks one hit above a fixed confidence, and
neither returns ranked candidates, per field distances, or any notion
of an album as a unit. Its clients are unexported, so they cannot be
called for candidate lists even where the shapes are close.

Matching quality is the product's flagship claim, and the hard part
is not the queue UI. It is the pipeline that turns a directory of
loose files into "this is release X with 94 percent confidence, track
7 is missing": clustering, candidate retrieval, track assignment, and
calibrated scoring. beets spent years tuning the equivalent distance
weights.

## Decision

WaxDeck owns the matching engine as a pure Go library in
`server/internal/match`, structured as five stages:

1. **Cluster.** Pending files group into album units by normalized
   album artist and album tags, falling back to parent directory when
   tags are missing. A unit is the atomic decision: it auto applies
   or queues as one, never both.
2. **Candidates.** A `CandidateSource` port supplies releases three
   ways: direct lookup when a file already carries a release MBID,
   AcoustID fingerprint lookup, and MusicBrainz text search. Once a
   clear majority of a unit's fingerprints agree on a release group,
   the remaining tracks bind to that candidate through assignment
   instead of issuing their own lookups: fewer provider calls, and no
   split verdicts inside one unit.
3. **Assign.** For each candidate release, tracks map to release
   tracks by minimum cost bipartite assignment (Hungarian method)
   over title, duration, and position distances, so wrong or missing
   track numbers cannot corrupt the pairing.
4. **Score.** A weighted distance model over album level fields
   (artist, album, year, media) and the assigned per track fields
   (title, duration, position), plus penalties for unmatched tracks
   on either side. The complement is the match percentage the UI
   shows, and the per field components ride along so the review queue
   can explain a score instead of asserting it.
5. **Decide.** Distance at or below the auto apply threshold applies
   the winning candidate; anything else queues for review with its
   ranked candidates. Per library modes can force review of
   everything or skip matching entirely.

The engine is deterministic and network free: all provider access
sits behind the `CandidateSource` port. The live implementation is
WaxDeck's own rate limited MusicBrainz and AcoustID clients (WaxBin's
are unexported, and its request pacing machinery is internal), with
response caching and the etiquette the providers require. AcoustID
runs only when an API key is configured and fpcalc is present;
without them matching degrades to tag and search evidence.

Thresholds and weights are calibrated against a labeled evaluation
corpus checked into the test tree: synthesized messy libraries with
known correct releases served by a canned candidate source. CI scores
auto apply precision and recall and fails on regression. Precision
gates the auto apply threshold (a wrong auto apply is the one
unforgivable outcome); recall is the tuning target. Applied matches
are additionally logged so the UI can surface the observed revert
rate, a trust signal, never the calibration input.

On approval or auto apply the engine's chosen candidate writes
through the WaxBin curation surface as one batch edit (fields,
identifiers, credits where present), with locks left at their
defaults so a later rescan cannot undo an accepted match.

Content with no canonical release is a first class terminal state,
not a failure: the review queue always offers keep as is and mark
unofficial. Marking unofficial sets the `RELEASESTATUS` custom tag to
`unofficial` (locked), which excludes the item from match retries and
health penalties; files that arrive already tagged with a bootleg
status are treated the same way.

## Alternatives considered

- Extending WaxBin's enrichment spine with ranked candidates.
  Rejected for now: the engine needs fast iteration against the
  corpus while thresholds settle, and its decision model (album
  units, review states) is WaxDeck product logic. Upstreaming is
  worth revisiting once the weights stabilize.
- Matching files independently, Picard lookup style. Rejected: the
  album is the natural decision unit; per file verdicts half apply
  albums and multiply provider calls.
- Greedy track pairing instead of bipartite assignment. Rejected:
  greedy pairing degrades exactly on the messy inputs the product
  targets (missing track numbers, reordered files, duplicate
  titles).

## Consequences

- WaxDeck carries its own MusicBrainz and AcoustID clients with per
  host pacing, a user agent contract, and response caching. These
  also serve the review queue's candidate refresh.
- The evaluation corpus is a maintained artifact: new failure
  classes (box sets, non Latin scripts, compilations) get corpus
  cases before they get engine fixes, and multi movement classical
  albums must cluster as single units from day one.
- The engine stays importable in isolation (no waxbin dependency),
  which keeps the eval harness trivial and the door open to
  upstreaming.
