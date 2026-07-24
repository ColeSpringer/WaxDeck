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

- **In-place playlist rule update.** The playlists facade has no way
  to change a smart playlist's rule under a stable pid, so WaxDeck
  reissues the pid and links the generations with `previousPid`
  (docs/adr/0006). An engine-side rule setter dissolves that whole
  seam: the reissue contract, the two-event sync story, and the
  client-side follow logic.
- **Relative date operators in the query engine.** Conditions compare
  absolute timestamps only, so a rule meaning "played in the last 30
  days" must be re-saved to move its cutoff. WaxDeck's contract
  documents the gap (docs/adr/0006).
- **Smart-list limit modes beyond item count.** Random-sample, total
  minutes, and total megabytes limits have no engine primitive; the
  API exposes a count limit only.
- **Entity-level library attribution.** Artists and albums cannot be
  attributed to library roots, so users restricted to a subset of
  roots lose entity search entirely (docs/adr/0004). WaxDeck filters
  at the item level and hides entity surfaces from restricted users.
- **Entity facets in the item query grammar.** Items cannot be
  filtered by artist or album entity pid, only by display string,
  which is why the Subsonic surface mints its artist and album ids
  from strings. A real entity facet would retire the minted ids. The
  discovery and sharing surfaces added two more consumers: instant
  mixes cannot take an album pid as a seed (clients seed with a
  member track instead), and share links cannot target an album
  (users share a playlist of its tracks instead). Artist seeds work
  today only through a full artist facet scan that maps pid to
  display name; an entity lookup or entity-pid filter retires that
  scan too.
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
