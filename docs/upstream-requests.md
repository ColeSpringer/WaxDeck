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

- **A `playlist_pid` query field.** Playlist membership is the one item
  relation the query engine cannot express, so "how many members of this
  playlist is this caller offered" cannot be asked as a query and has to
  be answered by hydrating every member and filtering in Go.

  Everything else the count needs is already expressible:
  `visibleItems()` carries the state predicate, `library` scopes to the
  caller's grants, and `podcast_pid` with `OpIn` is how the subscription
  scope is already built. Only membership is missing, so one field turns
  the whole thing into a single indexed `Count`.

  The shape exists and has two precedents in the same file:
  `SetColumn` over a join table keyed on `pi.id`, which is what
  `genre_pid` is and what `credit_artist_pid` - landed in this very
  batch - is. `playlist_item(playlist_id, position, item_id)` already
  carries `playlist_item_item ON playlist_item(item_id)`, so the
  subquery is served:

      "playlist_pid": {Set: &query.SetColumn{
          Sub: "SELECT 1 FROM playlist_item plq JOIN playlist plq2" +
              " ON plq2.id = plq.playlist_id WHERE plq.item_id = pi.id",
          ValueExpr: "plq2.pid",
      }},

  **Scoped to the count, not the listing.** A playlist's order is its
  stored `position`, and a query orders by `sort_key`, so the member
  *listing* cannot move onto this field without a position sort - which
  is not being asked for. Counting does not care about order.

  Worth more than the count, probably: it would also make playlist
  membership addressable from a smart rule ("tracks not in my Archive
  list"), which is a real capability rather than an optimization, and
  the reason a set field rather than a scalar is the right shape.

  **The workaround WaxDeck runs on today:** the listing row's count is
  memoized per (user, playlist) on the playlist's `UpdatedAt` with a
  one-minute TTL, which is what keeps the user-stream fan-out from
  re-hydrating every playlist's members on every star and checkpoint
  (ADR-0052). The opened playlist counts live. When this field lands,
  `cachedMemberCount` and its TTL go away and both paths become one
  exact `Count`.

- **`podcast.Service.Unfetch` takes no file-mutation lease.** Every other
  verb that removes bytes runs inside a job in the `fs-mutate` scope -
  `ApplyDelete`, `RestoreTrash`, `EmptyTrash`, `PurgeTrash` - and that
  scope is what serializes them against the scan and organize jobs.
  `Unfetch` calls `os.Remove` and `DropEpisodeFile` directly, so a client
  unfetching an episode during a scan can delete a file the scanner is
  about to stat.

  WaxDeck cannot take the lease on its behalf: `fsMutateScope` is an
  unexported const, `l.jobs` is unexported, and there is no exported
  "run this under the fs lease" entry point. So it is upstream's call,
  either running Unfetch under the same scope its siblings use or saying
  deliberately that one episode file is small enough not to need it.

  **The workaround WaxDeck runs on today:** none - the exposure is
  accepted rather than mitigated. The window is one `os.Remove` of one
  file, the scanner already tolerates a file that vanishes underneath it,
  and the alternative (going back to `PlanDeletePIDs`) reopens the
  hub-versus-listing count bug ADR-0052 closed. One visible consequence:
  `DELETE /episodes/{pid}/fetch` no longer answers `catalog-busy`,
  because nothing on that path can produce it.

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
- `HasArt` landed on `model.EnrichTarget` and deliberately not on
  `read.FacetBucket`. That is the field a facet index would want, so the
  absence is worth recording rather than re-filing: a bucket's art is
  derived on read from current track maps, which is exactly why the
  entity's own `art_map` rows cannot answer the question. The
  `hasArt`-on-buckets deferred entry is untouched by it and stays
  sequenced behind artist art existing at all.
