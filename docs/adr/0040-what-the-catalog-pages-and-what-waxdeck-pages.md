# 40. What the catalog pages, and what WaxDeck pages

Date: 2026-07-31

## Status

Accepted.

## Context

WaxBin answered every open ask in `docs/upstream-requests.md` in one
batch: a `changed bool` on the four star and rating writes, `podcast_pid`
as an item query field, `read.BrowseOptions.Query`, and per-file peaks.
Adopting them retires four shipped workarounds and closes two tracked
deferrals.

It also answered one ask by declining it, and that is the part worth an
ADR. `Library.Facet` gained an order and a top-N limit but no cursor, and
upstream's own documentation says facet paging is not offered and will
not be: a cursor would re-run the whole `GROUP BY` and `COUNT(DISTINCT)`
per page. The answer it offers instead is `EntityPage(kind, cursor,
limit)`, a keyset walk of an entity table's `sort_key` index.

The next agent looking at a slow artist index will find `EntityPage`,
read "keyset walk of every artist", and think it is the fix for
`/library/facets`. It is not, and the reasoning has to be written down
where that agent will find it.

## Decision

### `/library/facets` computes and caches a whole enumeration, permanently

The endpoint's paging is a window over a sorted slice held in
`server/internal/service/facets.go`, with the cache narrowed to
full-visibility callers and keyed on the catalog feed position and the
genre vocabulary version. The file's header used to promise that the
window and the cache go away when upstream pages `Facet`. That promise is
now false and has been rewritten: this is the permanent shape.

The order is applied in WaxDeck rather than passed to upstream, and the
two disagree deliberately. `facetFolded` case-folds the *display label*
after a left-trim; `read.FacetOrderLabel` collates on `sort_key` with
articles stripped, so "The Beatles" files under B there and under T here.
The alphabet rail's letters follow this file's answer, so this file has
to produce it. The left trim landed with the same change and closed a
live bug: `fastScrollLetter` on the client trims before taking its first
character, so a label " Weeknd" sorted ahead of every A on the server
while the rail filed it under W. One fold now decides the sort, the seek,
and the rail letter.

### `EntityPage` is not adopted, and here is why in four parts

It enumerates the entities that *exist* rather than the entities matching
a query, and every consequence of that is a mismatch with what this
endpoint promises:

- **Library scoping is lost.** `/library/facets` narrows the enumeration
  to the caller's granted libraries, which is the axis that actually
  hides content.
- **Orphans appear.** An entity with no items is a row in the entity
  table and would be a bucket with nothing behind it, so a bucket's count
  and the list it opens would disagree at exactly the rows nobody can
  open.
- **There is no unknown bucket.** "[Non-Album]" and "[Unknown Artist]"
  are real buckets holding the items a dimension is absent from. An
  entity table has no row for an absence.
- **The counts are different numbers.** They come from rollups, which
  are track-based for artists, so a book counts under its author for
  `LibraryPIDs` but not for `ItemCount` - and they would not match the
  bucket counts the same screen has always shown. `album-artist` has no
  entity kind at all.

The scaling answer for a large dimension is the `startsAt` seek added to
`/library/facets` in the same change: an alphabet rail tap becomes one
request rather than up to twenty sequential pages, without giving up any
of the four properties above.

### `read.GroupPodcast` is not adopted either

Upstream also shipped a facet dimension bucketing episodes by feed,
which nothing asked for. WaxDeck already answers the per-user view at
`/podcasts/subscriptions`, and a catalog-wide podcast dimension would
enumerate shows nobody follows. The subscription scoping that hides them
is a per-item decision no aggregation can express, so the dimension would
be a bucket list whose counts no drill could reproduce. Recorded here so
its absence reads as a decision rather than an oversight.

### A browse or item cursor carries the scope it was issued for

`/library/browse` used to pass the catalog's opaque token straight
through, so a client that changed `seed` mid-page already got a silently
wrong window: the cursor names a position in a seeded permutation, and
under another seed it names a position in a different permutation
entirely. Pushing `mediaType` down and adding `facet`/`facetKey` widened
a hazard that was already live.

Both endpoints now wrap the catalog's token in an envelope carrying a
hash of the scope - for browse the (list, seed, mediaType, canonical
facet, facetKey) tuple, for items the filter alone - and answer
`invalid-request` on a mismatch. The dimension is hashed in its
*canonical* spelling, or `tag.mood` and `tag.MOOD` would mint two scopes
for one listing.

This repo had already solved the same problem twice - the facet cursor
carries its sort and refuses a mismatch, the cross-show episode cursor
carries its filter and refuses a mismatch - so these two were the
outliers, not a new case.

**The two sit at different risk levels behind the same wrapper, and that
is worth keeping straight.** Browse's cursor is a position in a
permutation, so reusing one under another scope yields garbage.
`QueryPage`'s is `(sort_key, pid)`, so reusing one under a changed filter
yields a well-defined window: the next page of the *new* filter's set,
resuming after that sort key, skipping and duplicating nothing, merely
missing the head. That is a degradation rather than garbage. Items takes
the wrapper for consistency, not because it had the same bug - two
sibling endpoints behind one page shape should behave alike, and a
refusal is a better answer than a quietly headless page.

### The division of labour, as upstream states it

Browse owns the ordering vocabulary. `QueryPage` owns `sort_key`
ordering. They share one filter engine, and a `BrowseOptions.Query`'s own
sort, limit, and offset are ignored exactly as `QueryPage` ignores them.

That is what makes the scoped shuffle exact and the cross-show episode
listing still a slice in Go: a discovery list can be narrowed to any
whitelisted field, but it cannot be *reordered*, and no discovery list
orders by publication date. The correction is filed upstream as a
publication-ordered listing primitive rather than as the pid field an
earlier entry wrongly claimed would fix it.

## Consequences

`/library/facets` and its cache are load-bearing rather than
transitional, and a future agent proposing to replace them with
`EntityPage` has the four mismatches to answer first.

Any change to what a browse or item cursor encodes now reaches clients
holding tokens minted by the previous build, because queue source cursors
are persisted rather than ephemeral. The client's rolling-queue pager
treats a rejected cursor as no cursor and falls through to placement,
which is why that fallback landed as this change's first commit rather
than alongside it.
