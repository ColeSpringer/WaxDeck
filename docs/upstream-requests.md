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

- **Entity enumeration for the compatibility surface.** The entity-pid
  item facets (`artist_pid`, `album_pid`, `album_artist_pid`,
  `genre_pid`) and the `EntityByPID` lookup landed, and WaxDeck adopted
  them: album-seeded instant mixes, album share links, and the
  retirement of the artist facet scan all ride the new filters, and
  restricted-user entity search rides `EntityInfo.LibraryPIDs`
  (docs/adr/0004) — one `EntityByPID` per entity hit, bounded by the
  search page and paid only by restricted callers; a batch entity
  lookup over a set of pids would retire that per-hit cost. One consumer
  stays on the string-minted workaround.
  The Subsonic compatibility surface groups its in-memory artist and
  album index by display string and mints `A!`/`L!` base64 ids;
  retiring them for real entity pids needs a way to *enumerate* album
  entities (there is no `album` facet group — only artist, albumArtist,
  genre, year, kind, and library) or to read an item's artist and album
  entity pids off its view (an item view carries display strings only;
  the facet fields filter but do not project). Either an album facet
  group or entity pids on the item view would let the compatibility
  index carry real entity pids. Until then WaxDeck keeps the minted
  ids, which are stable, decodable without state, and never persisted
  (stars, playlist rows, and shares all key on real item pids), so a
  client that cached one loses nothing.
- **As-of timestamp on play-state mutations.** The per-field
  `StarredChangedAt`/`RatingChangedAt` stamps landed (retiring the
  earlier `UpdatedAt`/`StarredAt` request), but `SetStar`/`SetRating`
  stamp them at server-apply time, while an offline-replay guard must
  order a replayed toggle by the client-recorded time it happened. So
  the stamps, added for exactly this, cannot order a WaxDeck replay
  against an out-of-band change (a Subsonic star, a migration import) to
  the same item. An as-of/recorded-time parameter on the mutation would
  land the stamp in recorded time, make cross-surface ordering correct
  for every consumer, and let WaxDeck retire the star/rating half of its
  `play_state_stamps` mirror (the resume shelf keeps the position half).
  Today WaxDeck mirrors its own recorded-time stamps and firms the guard
  with the catalog stamp only where the mirror is silent: conservative-
  safe (it never resurrects an undone state) but it skips a legitimately
  newer replay when an out-of-band change intervened.
- **Entity-scoped star writes.** `SetStar` operates on item pids, and
  WaxDeck's star surface is item-scoped to match. The entity-pid facets
  that landed (`album_pid`, `artist_pid`, `album_artist_pid`) gave the
  catalog stable album and artist identities, but nothing writes a star
  against one, so a migration import that reads getStarred2 (Subsonic,
  Navidrome) keeps its song stars and drops the album and artist stars
  it carries alongside them: there is no release-group or artist star to
  persist. A `SetStar` overload taking an entity ref, stored and
  queryable the way item stars are (and stamped in recorded time, so it
  pairs with the as-of-timestamp ask above), would let WaxDeck keep an
  imported album or artist star as what it is; `SetRating` would want
  the same overload the day WaxDeck imports entity ratings. Today
  WaxDeck imports the song stars only; the available in-repo stopgap is
  to expand an entity star into stars on its member items, which carries
  the intent but round-trips as N item stars rather than one entity star
  (and would re-star a member the user later unstarred), so it is
  deferred in favor of the faithful surface.
- **Playlist as a first-class art entity.** The catalog art store keys
  `art_map` by `entity_type` over
  `track|album|release_group|artist|genre|episode|podcast`, and
  `ResolveArt`/`ArtRoles`/the art write facade take an `EntityRef` that
  cannot name a playlist. WaxDeck wants a synced or imported playlist to
  carry a cover (a custom upload, the source's own thumbnail, or an auto
  four-cover mosaic WaxDeck generates) stored and served through the
  same content-addressed blob store, thumbnail cache, and ETag path as
  every other cover, so it shows up uniformly in the REST playlist
  reads, the Subsonic `coverArt`, and M3U8 exports. This needs
  `art_map.entity_type` to accept `playlist`, the resolve and write
  surfaces to take a playlist ref, and the `front` role to resolve at
  the playlist's own level with no parent fallback walk (a playlist has
  no art ancestry). The synced-playlist feature ships without a cover
  meanwhile; the available workaround is a WaxDeck-side cover in
  `waxdeck.db` keyed by playlist pid, injected into the playlist DTO and
  the Subsonic mapping, deferred by choice so the plumbing is not laid
  down and later retired. Extends the art-role model (docs/adr/0014).

## WaxFlow

- **Runtime root configuration in the streaming sidecar.** WaxDeck now
  adds a library root at runtime through WaxBin `AddRoot`, and the
  catalog scans it so browsing and downloading its files work at once.
  But the streaming sidecar (`waxflow-catalog`) mounts its roots from
  startup configuration and re-reads them only on restart, so a stream
  request for a file under a runtime-added root fails until the sidecar
  restarts. A reload endpoint or a config watch on the sidecar would let
  a runtime-added root stream without downtime. Until then WaxDeck serves
  the new root's files by direct download and documents the restart the
  streaming path needs.

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
