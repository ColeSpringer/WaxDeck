# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.

Earlier request batches (twenty items across three sprints, covering
the facade surface, metadata vocabulary, podcast preservation, and the
sidecar injection seam) all landed and are not repeated here.

Nothing is open against WaxBin: the eight standing asks all landed in
`v0.0.0-20260807053401-227d33fad6f1` and are adopted (ADR-0051). File
the next one here rather than in a progress note.

## Recorded upstream non-goals

Deliberate upstream decisions WaxDeck designs around; listed so they
are not re-filed as asks:

- Episode tag write-back is refused (episodes are not tagged files;
  edits stay DB-only).
- WaxTap rips refuse tag write-back and export no fingerprint
  (descriptive-rung matching only); WaxDeck stamps provenance via
  WaxLabel at ingest instead.
- Secret operations are not proxied to the standalone CLI; WaxDeck
  owns the entire secret lifecycle.
- Decoding the vendored exotics (WMA, APE, WavPack) stays out of
  WaxFlow; the few samples exist to prove graceful failure.
- fpcalc stays: it is the one runtime subprocess (WaxBin acoustic
  fingerprinting), kept by decision. The ffmpeg era is already over
  in every runtime path; ffmpeg appears only in WaxFlow's test
  utilities for cross-validation and a doctor diagnostic. Do not
  file native fingerprinting as an ask.
- Playlist covers are not exported to M3U8. The format has no standard
  cover directive, so the playlist art entity stores and serves a cover
  everywhere else (the REST art endpoint, the Subsonic `coverArt`) and
  the export stays text. Do not re-file it as a gap.
- Facet paging is refused. `Library.Facet` takes an order and a top-N
  limit and will never take a cursor: paging one would re-run the whole
  `GROUP BY` and `COUNT(DISTINCT)` per page. The answer offered for a
  large-dimension index is `EntityPage(kind, cursor, limit)`, a keyset
  walk of an entity table's `sort_key` index - and WaxDeck does not
  adopt it, because it enumerates the entities that exist rather than
  the entities matching a query. ADR-0040 records the four mismatches
  (library scoping, orphan entities, the unknown bucket, rollup counts)
  and the `startsAt` seek that scales the index instead. So
  `/library/facets` computing and caching a whole enumeration is
  permanent, not a workaround.
- `read.GroupPodcast`, a facet dimension bucketing episodes by feed, is
  shipped upstream and deliberately unused here: `/podcasts/subscriptions`
  answers the per-user view, and a catalog-wide dimension would
  enumerate shows nobody follows while the subscription scoping that
  hides them is a per-item decision no aggregation can express.
