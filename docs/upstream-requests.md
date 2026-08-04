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

- **A last-touched primitive for started-and-unfinished items.** The
  publication-ordered ask this entry used to carry landed as the
  `recent-episodes` list, and `latest`/`unplayed` on
  `GET /podcasts/episodes` are keyset browses of the catalog now. The
  `in-progress` filter did not follow, and the reason is a design
  decision rather than a missing field: `last_played_at` is stamped by
  `MarkPlayed` and never by `Checkpoint`, so `recently-played` excludes
  exactly the checkpoint-only rows that are the in-progress population.
  `position_ms` landed and gives the membership
  (`position_ms gt 0 AND finished is 0`), so what is left is ordering:
  a discovery list over items a user last touched, or a per-user
  last-touched sort field, would let the strip page as a keyset browse
  instead of collecting its population and ranking it in Go
  (`inProgressEpisodes`, `server/internal/service/podcasts.go`). The
  population is human-bounded - a row exists only for an episode
  somebody started - so the shipped ranking is correct and affordable.

- **A podcast handle on the item view.** `model.ItemView` projects
  `Explicit` now, which is the episode's own advisory flag, and WaxDeck
  reads it: `allowedByContent` refuses a flagged episode without a read.
  A *clean* episode still costs two, because deciding it needs the
  show's flag and the view carries no `PodcastPID` to reach the show
  with - so the check reads the episode to learn its show, then reads
  the show. `subscriptionFilter.allowsEpisode` pays the first of those
  two for the same reason: it reads a whole episode to learn one pid it
  then looks up in the subscribed set
  (`server/internal/service/perms.go`, `podcasts.go`).
  `ArtistPID`, `AlbumPID`, and `ReleaseGroupPID` are all
  projected already, so a `PodcastPID` beside them is the same kind of
  handle and would halve the chain. The workaround is shipped and
  correct, and restricted callers are the rare branch, so this is a cost
  rather than a gap.

- **A release MBID on the item view.** `model.ItemView` carries no
  MusicBrainz identifier of any kind, which is the same wall the
  `missing-mbid` health check ran into and recorded rather than crossed
  (`server/internal/service/health.go`): "the recording MBID is not
  reachable from here at sweep cost". Two WaxDeck surfaces want one and
  neither can have it. The health sweep would report the gap it is
  named for. And Discord rich presence (ADR-0045) would draw the real
  album cover: Discord fetches art through its own media proxy, so the
  URL has to be publicly resolvable, and a Cover Art Archive URL built
  from a matched release id is the one source that is public without the
  instance being. The identifiers exist - matching writes them, the
  review surfaces speak them (`appliedMbid`, `releaseGroupMbid`), and
  the metadata editor edits them - so this is a projection rather than
  new storage. A release MBID on the item view, or on the album view the
  item resolves through, closes both. The workaround is shipped for
  both: the health check omits the rule, and presence shows the
  application's own static asset.

- **A set-membership operator on item queries.** There is no `OpIn`: the
  operator vocabulary is is/isNot, the string and ordered comparisons,
  `OpInRange` (a two-ended range, not a set), the presence pair, and the
  relative-time pair. So "episodes of any show this caller follows"
  compiles as a `query.Or` of one `podcast_pid is X` arm per
  subscription (`subscribedEpisodeScope`,
  `server/internal/service/podcasts.go`). That is the shipped workaround
  and it is fine at the design center of tens of shows; the practical
  ceiling is somewhere in the low hundreds of subscriptions, past which
  the OR width is a real cost. An `OpIn` taking `Cond.Values` would
  collapse the whole disjunction into one indexed predicate, and it
  would serve every other "any of these entities" scope besides this
  one.

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
