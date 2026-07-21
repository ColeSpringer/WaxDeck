# Deferred work

The tracked list of WaxDeck work that was cut from an otherwise
shipped slice. Roadmap items that have simply not started yet do not
belong here, and deliberate v1 scope exclusions live in the roadmap
and the ADRs; this list is for the residuals that would otherwise
survive only as a sentence in a progress note. Agents: when you cut
something from a slice, add it here in the same change (as with
upstream-requests.md, which holds the sibling-repo asks); when the
work lands, remove the entry.

Every entry carries a gate tag saying what actually blocks it:

- `[in-repo]` nothing blocks it; it was cut for scope and is ours to
  build whenever it is picked up.
- `[upstream]` needs sibling-repo work first; the ask itself lives in
  upstream-requests.md and the entry names it.
- `[hardware]` needs a device or environment the dev box lacks
  (a phone, a head unit, Docker, real cast hardware).
- `[roadmap]` deliberately rides a named later slice; listed here
  only because the cut happened mid-slice and would otherwise read
  as forgotten.

Most of this list is `[in-repo]` by design: the working rule is that
a slice ships when its acceptance holds, and polish residuals get
written down instead of silently dropped or half-shipped. Very little
here waits on upstream.

## Playback and apps

- `[in-repo]` **Offline multi-part audiobooks play only their first file.** The
  download path stores every part, but offline playback loads
  `paths.first`, never sequences the rest, and applies the
  book-timeline resume position to file one. Fixing it needs per-part
  durations in download-info (small spec addition), offline part
  resolution mirroring the server's, and advance-on-complete.
  Surfaced by the direct-playback audit; the offline span-clipping
  half of that audit's findings is fixed.
- `[in-repo]` **Verify clip windows on the desktop engine backend.** Direct and
  offline playback of carved tracks clip through just_audio's
  ClippingAudioSource; the mpv bridge desktop builds use should be
  verified to honor the window on a real desktop build (docs/adr/0007).
- `[hardware]` **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- `[in-repo]` **Sleep-timer fade.** Now unblocked: the engine port
  grew setVolume for remote volume control, so the fade is a timer
  loop away.
- `[in-repo]` **Offline artwork caching.** The offline grid shows placeholders;
  artwork is only fetched live.
- `[roadmap]` **Web loading and scrolling performance.** Parked for the larger UI
  and UX overhaul rather than spot-fixed. The recorded perf gate
  measured the virtualized grid without artwork; the suspected
  aggravator is per-card artwork fetches at grid scale, so the
  overhaul's measurement pass should use real content.

## Connect and casting

- `[in-repo]` **Web gapless over hls.js stayed a gated attempt and did not ship.**
  The engine port grew everything it needs (a fourth implementation
  slot behind the same conformance suite), and the server side is
  complete: queue timelines mint over `POST /player/timeline` and the
  proxied HLS tree serves them today (cast rides them already). What
  is missing is the client half: a vendored hls.js MSE engine behind
  `AudioEnginePort` via `dart:js_interop`, feature-flagged with the
  standard audio path as default and fallback. Deferred rather than
  rushed; the standard web path keeps working, and the recorded gate
  posture is that this attempt may miss without slipping anything.
- `[in-repo]` **AirPlay sender.** The experimental RAOP/AirPlay-1 push endpoint
  is not built. Go's AirPlay-sender ecosystem is weak, OS-level
  routing on Apple hardware is the blessed path, and the roadmap
  explicitly allows this to miss without slipping. The endpoint
  registry takes a new kind without schema changes when it lands.
- `[in-repo]` **Multi-part audiobooks refuse device endpoints.** Casting a
  multi-part book to a cast, DLNA, or jukebox endpoint answers a
  clear error instead of playing file one and losing the reader's
  place mid-book. Client endpoints handle books fully. Needs
  part-aware loading and part-advance in the session manager.
- `[in-repo]` **DLNA format negotiation stops at the floor.** Every DLNA item is
  delivered as mp3 (or passthrough for mp3/wav sources) regardless of
  the renderer's ProtocolInfo. The SOAP client already parses the
  Sink list; the resolver just does not consume it yet.
- `[in-repo]` **Cast device displays show no artwork.** The art endpoint
  authenticates by session, which a cast device cannot present; media
  items are sent without an art URL. Needs a media-token art variant.
- `[in-repo]` **Session restore surface.** Ended sessions keep their final state
  in `playback_sessions` (pruned to the newest five per user), but no
  API or UI reads it back yet; the queue-restore history the sync
  design names is data-complete and surface-absent.
- `[roadmap]` **Shared-outputs permission gate.** Device endpoints are visible
  and controllable by every user; the "use shared outputs" toggle
  rides the granular permission set when that lands.
- `[in-repo]` **Timeline URLs do not survive a server restart.** The HLS proxy
  reconstructs signed upstream URLs from an in-memory stash; after a
  restart a live timeline fetch answers not-found and the client
  re-mints. Cheap to persist if it ever matters beyond the seam.
- `[in-repo]` **Cast preflight verifies server-side only.** The
  reachability verdict is the server fetching itself through each
  candidate base; true device-side verification (loading a probe URL
  on the device and watching status) would catch DNS and cert
  failures the server cannot see.
- `[in-repo]` **Cast preflight has no UI surface.** The endpoint
  answers plain-language diagnostics, but no settings or picker
  screen renders them yet; users would have to curl it.
- `[in-repo]` **Crossfade and ReplayGain settings do not feed
  timelines yet.** The whole mechanism is built and tested end to
  end: the mint takes crossfadeSeconds, the identical value rides
  the signed playlist, and the gain parameter is explicit (off
  today) exactly as timelines require. What is missing is user
  configuration wiring: a crossfade setting reaching cast session
  loads, and stored album gain values passed as the explicit dB.
- `[in-repo]` **The head unit gets skip controls but no queue
  display.** Next and previous step the active queue from Auto and
  the notification; publishing the queue itself as media items (so
  the head unit renders an up-next list) is the remaining half.
- `[upstream]` **Virtual tracks cannot join gapless timelines.**
  Timeline members are whole files upstream; a CUE-carved track in a
  cast queue falls back to per-item URLs, and the timeline endpoint
  answers conflict for it. The ask (sample windows on timeline
  members) is filed in upstream-requests.md; until it lands this is
  not buildable here.
- `[hardware]` **The real-device cast checklist has not run.** The
  protocol suites drive wire-honest fakes (a TLS CASTV2 receiver, a
  SOAP renderer), but a real Chromecast, a speaker group, and a real
  renderer on a real LAN, including the zero-TLS path end to end,
  need hardware this environment lacks. Speaker groups are handled
  by construction (they announce like devices); that claim is
  exactly what the checklist verifies.

## Podcasts

- `[in-repo]` **Enclosure-passthrough streaming for unfetched episodes.** A
  remote episode answers a typed conflict today, and the Subsonic
  podcast mapping gives streamIds only to downloaded episodes for the
  same reason. One passthrough proxy would fix both.
- `[in-repo]` **Per-feed episode keyword filters** (auto-download only matching
  episodes). These were waiting on the smart-list engine, which now
  exists.
- `[in-repo]` **PodPing update notifications.** Polling is the only feed refresh
  trigger.
- `[upstream]` **Skip-map refresh on detector upgrades.** Maps
  refresh only when a file's essence changes; the caps-level detector
  version this needs is in upstream-requests.md.

## Compatibility

- `[in-repo]` **Playlist durations on Subsonic list rows.** Exact on detail
  responses; list rows report zero for smart playlists because
  membership is computed on read.
- `[in-repo]` **NSP import and export.**
- `[hardware]` **Driving a real client binary in CI.** No Docker in the dev
  distro, and the web-based Subsonic clients need CORS headers
  WaxDeck does not expose; the client trace suites (Subsonic and
  gpodder) are the automated stand-in and fail on missing endpoints.

## Infrastructure

- `[roadmap]` **Nothing empties the trash.** Deletes go to the catalog's
  reversible trash (a same-volume .waxbin-trash the scanner skips),
  and no WaxDeck surface or job ever purges it, so reclaimed space
  only accumulates. Until the admin slice ships the trash UI, the
  proxied CLI is the answer: waxbin trash list / restore / empty, and
  waxbin rm with the permanent mode for trash-bypassing deletes; a
  REST delete surface (dry-run plan, mode choice, trash list,
  restore, empty) and an optional age-based purge job ride the
  roadmap's admin-and-ops slice with the delete permission toggle.
- `[roadmap]` **Scheduled event-log and stamp pruning**, slated for the roadmap's
  scheduled-jobs slice; the manual prune call and the session janitor
  cover it meanwhile.
- `[hardware]` **Compose e2e harness with the real dex IdP.** The browser SSO
  journey runs against the bare-binary test IdP; dex returns when the
  compose harness exists.
- `[hardware]` **The docker compose acceptance has never run.** Docker Desktop WSL
  integration is off in the dev environment; the first verification
  needs to happen wherever Docker exists.

## Decided, not deferred

Recorded so they are not re-read as gaps: gpodder episode delete
actions stay echo-only (a per-device client delete must not reclaim a
shared server file). Scope-level non-goals and accepted risks live in
the roadmap's post-v1 section and the ADRs.
