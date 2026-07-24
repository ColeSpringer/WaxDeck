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
- `[in-repo]` **Queued listen sessions drop skippedMs.** Live listen
  reports carry the trimmed-time counter, but the offline outbox
  table (waxdeck_data OutboxListens) has no column for it, so a
  session that fails to report and replays from the queue loses its
  time-saved contribution. Fixing it needs a drift schema bump with a
  migration and a regenerated database.g.dart.
- `[roadmap]` **Web loading and scrolling performance.** Parked for the larger UI
  and UX overhaul rather than spot-fixed. The recorded perf gate
  measured the virtualized grid without artwork; the suspected
  aggravator is per-card artwork fetches at grid scale, so the
  overhaul's measurement pass should use real content.
- `[in-repo]` **Discord rich presence from the desktop builds.** The
  Spotify-style "Listening to" status (track, artist, album art, a
  progress bar) while WaxDeck plays. Distinct from the Discord
  notification provider, which is a server-side webhook: presence is
  set through the Discord desktop client's local IPC endpoint (a Unix
  socket on Linux and macOS, a named pipe on Windows) with a
  registered application id, no bot and no OAuth, and activity type 2
  renders as "Listening to WaxDeck" with timestamps driving the
  progress bar. That endpoint only exists where the Discord desktop
  client runs, so this is a desktop-build feature, but the connect
  surface already mirrors sessions on other devices, so the desktop
  app can publish presence for playback happening anywhere (a phone
  included) while it is open. Shape: a presence port behind the
  plugin-wrapping rule, fed by player and connect state, implemented
  either as a pinned community plugin or a small pure-Dart IPC client
  (a handshake and SET_ACTIVITY as JSON frames; the Windows named
  pipe is the fiddly half). Update on track and pause changes, not
  position ticks; Discord displays at most roughly one activity
  update per 15 seconds. Album art must be publicly fetchable by
  Discord's media proxy, so a LAN-only instance's art URLs will not
  render: Cover Art Archive URLs from matched MusicBrainz release ids
  are the workable default (a small read-surface addition if the
  playing track does not expose its id yet), a public instance needs
  the same media-token art variant the cast-artwork entry wants, and
  a static WaxDeck asset is the fallback. Navidrome ships this
  server-side instead, over a gateway connection authenticated with
  stored per-user Discord user tokens, which works from any client
  but is self-botting against Discord's terms of service; recorded
  so it is not re-derived as an option. Needs no sibling-repo work.

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

- `[hardware]` **Compose e2e harness with the real dex IdP.** The browser SSO
  journey runs against the bare-binary test IdP; dex returns when the
  compose harness exists.
- `[in-repo]` **Wire the docker compose stack into CI.** Docker is now
  available in the dev environment and `make up` brings the full stack
  (waxdeck + the flavored waxflow sidecar) up locally, so the old
  "never verified" blocker is cleared for manual runs. What remains is
  running it in CI as an acceptance gate (build both images, up, smoke
  the origin, down) rather than only by hand.

## Curation and metadata

- `[in-repo]` **Scan discoveries do not enqueue matching on their own.** The
  identify pipeline runs for uploads and for explicit rematch
  requests; a library scan that discovers new loose files does not
  yet open review entries for them. The wiring point is the catalog
  change feed consumer (debounce a scan's item additions into album
  units once the scan settles); until it lands, "identify my new
  files" is a rematch away.
- `[in-repo]` **Genre normalization.** The canonical genre tree and
  whitelist mapping (provider tags normalized through an editable
  tree, with a shipped default) is specified but unbuilt; the health
  dashboard consequently has no genre-whitelist rule yet.
- `[in-repo]` **Book and remaining metadata providers.** Hardcover
  (the ASIN to ISBN bridge), Google Books and Open Library fallbacks,
  and Discogs are not yet implemented as enrichment providers; Deezer,
  iTunes, Audnexus, and fanart.tv shipped. Each is one self-contained
  provider in the providers package.
- `[in-repo]` **The custom-metadata-provider spec is unpublished.** The
  documented OpenAPI contract that would let community regional
  providers plug in (the Audiobookshelf pattern) still needs writing;
  the in-process provider port it would bridge to is live.
- `[in-repo]` **Small artwork is not yet a health rule.** The art
  resolution path does not expose dimensions cheaply; the rule needs
  either a size probe during the sweep or an upstream dimensions
  report on resolved art.
- `[in-repo]` **Android folder picking is excluded from the upload
  surface.** File picking works on every platform (the endorsed
  `file_selector_android` implementation covers in-app file picks),
  but Android folder access means SAF tree URIs, which the
  `FilePickerPort` deliberately does not speak; the "Upload a folder"
  tile hides there (`canPickFolders`). Multi-select plus auto
  grouping covers the album case on Android meanwhile.
- `[in-repo]` **Upload quota does not reclaim on library deletion.** The
  quota charges every non-discarded session's declared size, imported
  ones included, so it reads as a total-storage-contribution cap. But a
  deleted library item never releases its upload row's bytes: there is no
  library-item delete endpoint (deletion runs through the waxbin CLI or
  the dedup/merge/health flows), so nothing links "this item is gone"
  back to the upload session, and `DeleteUpload` refuses imported rows.
  A user who fills a small quota and then has those items deleted stays
  locked out. The clean fix depends on a product decision left open here:
  either the quota means in-flight footprint (then stop counting
  imported), or it means total contribution (then a delete path, or a
  WaxBin deletion hook, must discard the linked upload row). Not changed
  unilaterally because the two readings imply opposite behavior.
- `[in-repo]` **Acquired-track metadata is cleaned for matching, not for
  display.** For a loose track the matching engine reads an "Artist -
  Track" title and a channel-style artist tag into a clean recording
  query (dash split, trailing alias/producer and production-note
  stripping) and surfaces the real release for review. The staged file's
  own tags are left as the source delivered them (channel as artist, full
  video title), so the review queue shows the raw title until the release
  is approved or the user hand-edits; the same parse could pre-fill the
  review entry's title/artist as an editable suggestion. Deferred as a
  display nicety, not a correctness gap: manual editing and the surfaced
  candidate both cover it, and rewriting embedded tags from a guess is the
  riskier half.
- `[in-repo]` **OpenSubsonic explicitStatus is not emitted.** The
  Subsonic surface's song and album shapes accept an
  `explicitStatus` field ("explicit" or "clean") that clients
  render; mapping it from the episode flag and the ITUNESADVISORY
  custom tag is a small adapter change next time that surface is
  touched.

## Discovery and stats

- `[in-repo]` **Virtual tracks are not sonically analyzed.** A track
  carved out of a shared single-file rip by a cue sheet shares its
  backing file's audio essence, and embeddings are keyed by essence,
  so per-window analysis would collide with itself. The analysis
  sweep skips virtual tracks; they still appear in metadata-based
  mixes and inherit nothing sonic. Fixing it means keying embeddings
  by essence plus sample window and teaching the worker audio pull to
  serve the window (the stream surface already can).
- `[upstream]` **Album seeds and album shares.** Instant mixes cannot
  seed from an album pid and share links cannot target one, because
  the item query addresses entities by display string only; clients
  seed mixes with a member track and share a playlist instead. Rides
  the entity-lookup ask in upstream-requests.md.
- `[in-repo]` **Time and mood mixes.** Daylist-style rotating mixes
  with scheduled auto-names are a scheduler and a naming table over
  the instant-mix engine that shipped; nothing else blocks them.
- `[in-repo]` **Share-card image export.** The year-in-review surface
  answers data; rendering shareable image cards from it (and clip
  cards for episode shares) is client work on top of the existing
  responses.
- `[in-repo]` **Speed-up time saved is not reported by the first-party
  client.** The wire field (`ListenSession.skippedMs`) covers both
  silence trimming and playback speed above 1x, but the player only
  accounts trim jumps; counting speed savings needs seek-aware
  wall-clock-versus-content tracking in the playback session (a trim
  jump and a user seek look identical as position moves, so naive
  content-minus-wall math double counts). The stats labels say
  "silence trimming" until this lands.

## Admin and ops

- `[in-repo]` **Subsonic album and artist stars are pulled but not
  written.** The migration importer reads getStarred2's albums and
  artists alongside songs, but WaxDeck's star surface is item-scoped,
  so only song stars import. Album/artist stars would need either an
  entity star surface or expansion to member items.
- `[in-repo]` **Importers beyond Navidrome/Subsonic and
  Audiobookshelf.** The migration framework (portable-ref matching,
  backdated idempotent listen ingest, dry runs, task reports) is
  built; Jellyfin, Last.fm and ListenBrainz history, and the Spotify
  GDPR export ride it as fast-follows, as the roadmap allows.
- `[in-repo]` **Backup archive downloads are not ranged.** The
  download endpoint streams the whole zip; resuming an interrupted
  multi-gigabyte download re-fetches it. Needs serving outside the
  generated strict-handler shape (http.ServeContent), like the media
  download endpoint.
- `[in-repo]` **The transcode session limiter gates progressive
  streams only.** HLS timeline segment fetches are too granular to
  count as sessions; they ride the streaming engine's own liveSlots
  admission control (the documented backstop). A per-timeline
  session notion would close the gap.
- `[in-repo]` **Forcing the source's own format still spends an
  admission slot.** A client that pins `fmt=X` on a whole file already
  in format X (some Subsonic clients always pin a format) is routed
  through the engine and charged a concurrent-session slot, though the
  auto ladder would direct-play the same bytes as a seekable passthrough.
  `ServeStream` clears `Seekable` for any forced format unconditionally,
  and passthrough is signaled by `format=auto`, not by the source's own
  format name, so the guard is not a one-liner: it must match the forced
  format against the source container and still exclude voice boost and
  virtual tracks (and reconcile container-versus-format naming for
  mp4/adts/aac) so a real encode never escapes admission. Conservative
  today (it over-counts sessions, never under-counts); worth doing only
  if concurrent-session limits get tight.
- `[in-repo]` **No radio-scrobbling off switch.** Radio plays scrobble
  by default for users with scrobble connections, behind the
  transition-and-parse guards; a per-user preference (and possibly a
  per-station flag for talk stations) is the obvious follow-up for
  anyone whose station's metadata is honest but unwanted.
- `[in-repo]` **No request-level metrics.** /metrics serves runtime,
  account, queue-depth, and transcode-session gauges; an HTTP
  request counter/latency histogram by route class needs a mux
  middleware pass that has not been written.
- `[in-repo]` **Notification provider niceties.** The provider
  surface ships deliberately plain: no webhook custom headers or
  HMAC request signing (receivers that must authenticate WaxDeck can
  use a secret-bearing path), no Retry-After honoring (backoff is
  the generic exponential ramp), no per-target mute flag (emptying
  the event selection is the workaround), no Discord rich embeds
  beyond title and description, no ntfy attachments or action
  buttons, and no per-target rate limiting (a noisy event source
  rides the outbox's global pacing). Each is an isolated extension
  of one provider file when wanted.
- `[in-repo]` **No import-completed notification event.** The
  review-ready event deliberately skips entries that auto-apply, so
  a fully automatic import is silent end to end. Probably right (the
  uploader is usually watching the uploads screen, which updates
  live), but it is a decision: an import-completed user event would
  close the gap for fire-and-forget uploads.

## Decided, not deferred

Recorded so they are not re-read as gaps: gpodder episode delete
actions stay echo-only (a per-device client delete must not reclaim a
shared server file). Music has no first-class explicit boolean by
decision: no canonical source exists (MusicBrainz carries no explicit
flag), so files' own ITUNESADVISORY tags ride the custom-tag surface
(queryable, facetable, hand-settable, lockable) and enforcement is
the deny-list mechanism, not a per-track flag. Audiobooks have no
explicit convention anywhere; custom tags cover anyone who wants one.
Scope-level non-goals and accepted risks live in the roadmap's
post-v1 section and the ADRs.
