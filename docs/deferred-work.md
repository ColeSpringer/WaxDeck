# Deferred work

The tracked list of WaxDeck work that was cut from an otherwise
shipped slice. Roadmap items that have simply not started yet do not
belong here, and deliberate v1 scope exclusions live in the roadmap
and the ADRs; this list is for the residuals that would otherwise
survive only as a sentence in a progress note. Agents: when you cut
something from a slice, add it here in the same change (as with
upstream-requests.md, which holds the sibling-repo asks); when the
work lands, remove the entry.

## Playback and apps

- **Offline multi-part audiobooks play only their first file.** The
  download path stores every part, but offline playback loads
  `paths.first`, never sequences the rest, and applies the
  book-timeline resume position to file one. Fixing it needs per-part
  durations in download-info (small spec addition), offline part
  resolution mirroring the server's, and advance-on-complete.
  Surfaced by the direct-playback audit; the offline span-clipping
  half of that audit's findings is fixed.
- **Verify clip windows on the desktop engine backend.** Direct and
  offline playback of carved tracks clip through just_audio's
  ClippingAudioSource; the mpv bridge desktop builds use should be
  verified to honor the window on a real desktop build (docs/adr/0007).
- **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- **Sleep-timer fade.** Fading out instead of stopping needs a volume
  control on the audio engine port, which exposes none yet.
- **Offline artwork caching.** The offline grid shows placeholders;
  artwork is only fetched live.
- **Web loading and scrolling performance.** Parked for the larger UI
  and UX overhaul rather than spot-fixed. The recorded perf gate
  measured the virtualized grid without artwork; the suspected
  aggravator is per-card artwork fetches at grid scale, so the
  overhaul's measurement pass should use real content.

## Podcasts

- **Enclosure-passthrough streaming for unfetched episodes.** A
  remote episode answers a typed conflict today, and the Subsonic
  podcast mapping gives streamIds only to downloaded episodes for the
  same reason. One passthrough proxy would fix both.
- **Per-feed episode keyword filters** (auto-download only matching
  episodes). These were waiting on the smart-list engine, which now
  exists.
- **PodPing update notifications.** Polling is the only feed refresh
  trigger.
- **Skip-map refresh on detector upgrades.** Maps refresh only when a
  file's essence changes; the caps-level detector version this needs
  is in upstream-requests.md.

## Compatibility

- **Playlist durations on Subsonic list rows.** Exact on detail
  responses; list rows report zero for smart playlists because
  membership is computed on read.
- **NSP import and export.**
- **Driving a real client binary in CI.** No Docker in the dev
  distro, and the web-based Subsonic clients need CORS headers
  WaxDeck does not expose; the client trace suites (Subsonic and
  gpodder) are the automated stand-in and fail on missing endpoints.

## Infrastructure

- **Nothing empties the trash.** Deletes go to the catalog's
  reversible trash (a same-volume .waxbin-trash the scanner skips),
  and no WaxDeck surface or job ever purges it, so reclaimed space
  only accumulates. Until the admin slice ships the trash UI, the
  proxied CLI is the answer: waxbin trash list / restore / empty, and
  waxbin rm with the permanent mode for trash-bypassing deletes; a
  REST delete surface (dry-run plan, mode choice, trash list,
  restore, empty) and an optional age-based purge job ride the
  roadmap's admin-and-ops slice with the delete permission toggle.
- **Scheduled event-log and stamp pruning**, slated for the roadmap's
  scheduled-jobs slice; the manual prune call and the session janitor
  cover it meanwhile.
- **Compose e2e harness with the real dex IdP.** The browser SSO
  journey runs against the bare-binary test IdP; dex returns when the
  compose harness exists.
- **The docker compose acceptance has never run.** Docker Desktop WSL
  integration is off in the dev environment; the first verification
  needs to happen wherever Docker exists.

## Decided, not deferred

Recorded so they are not re-read as gaps: gpodder episode delete
actions stay echo-only (a per-device client delete must not reclaim a
shared server file). Scope-level non-goals and accepted risks live in
the roadmap's post-v1 section and the ADRs.
