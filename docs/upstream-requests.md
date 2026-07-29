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

- **Changed flag on play-state mutations.** `SetStar`/`SetRating` take
  a recorded-time `asOf` now and enforce recorded-time
  last-writer-wins, which is exactly what WaxDeck asked for and it has
  adopted it (the star and rating half of the `play_state_stamps`
  mirror is gone; the resume shelf keeps the position half). The store's
  `playStateWrite` already computes whether the write changed anything
  and suppresses its change-feed delta when it did not, but the facade
  returns only `error`, so a consumer cannot learn the same thing
  without a follow-up state read comparing `StarredChangedAt` against
  the `asOf` it sent. A `changed bool` return would carry it for free.
  Today WaxDeck emits its own `play-state` sync event unconditionally:
  a replay the catalog skipped still announces itself, which is a
  redundant event, not a wrong one (the client reconciles from the
  state it fetches), and one read per write is the more expensive
  alternative.

- **Keyset pagination on `Library.Facet`.** Every other read surface
  pages: `QueryPage` takes a cursor and a limit and answers a `read.Page`
  with `HasMore`/`Next`, and `Browse` does the same. `Facet` does not --
  it takes a query and a group-by and returns one `FacetResult` holding
  every bucket, with no cursor and no bound. WaxDeck's first-party
  browse-dimension endpoint is keyset-paged like the rest of its
  contract, so it computes the whole enumeration, sorts it, and runs its
  own keyset over that slice -- the cursor carries the last bucket's
  (count, label, key) and the next page resumes strictly after it, since
  counts are the leading sort term and an offset would skip or repeat
  buckets whenever one moved (`server/internal/service/facets.go`). It
  also caches the unfiltered full-visibility answer per dimension and
  order against `CatalogTailSeq()` to keep a browse index from
  recomputing every artist in the library per page. An
  artist or album dimension over a large catalog is exactly the case that
  wants a cursor. A `FacetPage(ctx, q, groupBy, order, cursor, limit, userPID)`
  beside the existing one would retire both the in-memory window and the
  cache; the workaround is shipped and correct meanwhile.

  The `order` in that signature is part of the ask, not a nicety. The
  endpoint serves two orders now: biggest-first (the `sortExpr` the
  aggregation already sorts on) and A-to-Z by display label, which is
  what the artist and album index screens' alphabet rail scrolls. The
  label order is case-folded and puts the unknown bucket last, neither
  of which falls out of the count order's collation, and its cursor
  carries the order it was issued under so the two cannot be crossed. A
  paged `Facet` that could only walk the count order would leave the
  A-to-Z half on the in-memory window, so the window and its cache would
  survive the very change meant to retire them.

- **A filter on `Browse`.** `read.BrowseOptions` carries a user, a seed,
  a cursor, and a limit, and the two list-shaped fields `ListByYear` and
  `ListByGenre` need. It takes no query, so the random list is over the
  whole catalog and nothing else. WaxDeck's queue windows any scope
  larger than 500 entries and draws more as it drains (ADR-0028); for a
  shuffled window that draw wants a random order over the *scope*, which
  is usually one facet bucket — a giant artist, a giant genre. A
  `Query query.Query` field on `BrowseOptions`, applied the way
  `QueryPage` applies one, would give every discovery list a scope and
  make this exact. The shipped workaround: a shuffled window over the
  whole music library uses `ListRandom` and is a real shuffle, and a
  shuffled window over a bucket pages that bucket's own listing and
  shuffles each arriving page among itself — so a shuffled 5,000-track
  genre hears a shuffle of its first 500 before a shuffle of its second
  500. Complete coverage, no repeats, an order that is more local than
  it should be.

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
