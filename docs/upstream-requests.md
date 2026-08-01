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

## WaxBin

- **An `explicit` item query field.** `podcast_pid` landed and the
  subscription tile's three numbers are two counting queries and a
  one-row read now, but only for a caller who may see explicit content.
  The walk it replaced dropped episodes the caller cannot see
  (`ep.Explicit && !uc.Explicit`), and no item query field expresses
  that flag, so `countShow` still walks for a restricted account
  (`server/internal/service/podcasts.go`). The flag is on the episode
  row already; a presence-style `explicit` field (`is 0` / `is 1`, like
  `has_art`) would retire the second path. This is the rare branch -
  `permissionsOf` grants Explicit by default and every admin holds it -
  so the workaround is shipped, correct, and cheap meanwhile.

- **A publication-ordered cross-show listing primitive.**
  `GET /podcasts/episodes`, episodes across everything the caller
  follows, assembles every subscribed show's episodes in Go, sorts them,
  and pages the slice, per request (`SubscribedEpisodes`,
  `server/internal/service/podcasts.go`). An earlier version of this
  entry claimed `podcast_pid` would make it "one keyset query over an
  indexed join". It does not, and the correction is the ask: `QueryPage`
  owns `sort_key` ordering and ignores a query's own sort, and no
  discovery list orders by publication date, so a cross-show listing in
  newest-published order has no keyset primitive behind it at all.
  Either a publication-ordered discovery list or sort-aware keyset
  paging would give it one. The `in-progress` filter needs a second
  thing besides: it selects on `PositionMS > 0` and there is no position
  field. A listener follows tens of shows, so the slice is correct and
  affordable today, and it is the wrong layer for a power user's OPML
  import.

- **A file handle on `DiagnosticFilter`.** `FileDiagnostics` landed and
  is the query surface the earlier "per-file diagnostics" ask wanted;
  `model.FileDiagnostic` maps onto WaxDeck's `WriteBackIssueDTO` field
  for field. What it cannot answer is "this item's issues": the filter
  is origin, code, severity, and library pid, so a per-item read means
  pulling a whole library's diagnostics and scanning them on every
  editor open. A `FilePID` dimension (WaxDeck resolves an item's files
  through `ItemFiles`) would close it. Until then
  `GET /items/{pid}/metadata` answers an empty `writeBackIssues`, which
  the contract already allows.

- **A release-group handle on the item view.** `model.ItemView` projects
  `ArtistPID`, `AlbumArtistPID`, and `AlbumPID`, and WaxDeck reads all
  three - the item listing and the metadata editor both carry the artist
  and album pids now. There is no release-group equivalent, and no
  facade read that resolves one from an item, so `ItemMetadata`'s
  declared `releaseGroupPid` is permanently absent. The enrichment spine
  already keys release groups, so this is a projection rather than new
  identity work. The field is optional in the contract, so the gap is a
  missing link rather than a broken read.

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
