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
