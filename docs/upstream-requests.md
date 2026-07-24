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

## WaxFlow

- **A `ReloadRoots` method on the Go client.** `client.Caps` exposes
  `Delivery.RootsReload`, so a consumer can learn the daemon serves
  `POST /roots/reload`, but `client.Client` has no method to call it:
  every other control endpoint (caps, sign, timelines, jobs, cache) has
  one. WaxDeck adds a library root at runtime and reconciles the sidecar
  against a rewritten config file, so it hand-rolls the POST with its
  own `http.Client`, its own `X-API-Key` header, and its own decode of
  the `{added, removed, changed, roots}` delta and the error envelope --
  duplicating what `postJSON` and `decodeEnvelope` already do correctly,
  including the envelope-to-code mapping this copy does not attempt.
  The workaround is shipped and working
  (`server/internal/bridge/flow/bridge.go`); it retires the day the
  method exists.

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
