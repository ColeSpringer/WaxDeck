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
- `[hardware]` **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- `[in-repo]` **The queue surface has no multi-select.** Rows reorder by
  drag (or by the move actions a screen reader gets), remove by swipe or
  by their own button, and jump on tap — one at a time. Long-pressing to
  select several and moving or dropping the set together is the half
  that is not built, and neither is dragging a row out of a listing and
  into the panel. Both are additions to `queueSlivers`, which is the one
  body the panel and the `/queue` screen share, so either lands in both
  at once. See ADR-0029.
- `[in-repo]` **A tap that replaces the queue offers no undo except from
  the session-history rows.** The queue layer records what a replacement
  displaced and where it stood (`QueueUndo`), and playback can put it
  back (`NowPlayingController.undoReplace`), but the "Playing from
  [source]" toast the plan asks for on every replacing tap exists only
  on the "EARLIER" rows of the queue surface, which is where a mis-tap
  is most destructive. Every other play verb — a track row, an album's
  Play, a Shuffle — replaces silently. The mechanism is built and
  tested; what is missing is one toast, raised from wherever the play
  verbs converge rather than added per call site.
- `[in-repo]` **An artist screen has no "Appears on" and no biography.**
  The screen shows the artist's own releases and tracks. Albums they are
  credited on without being the album artist would need a credits-shaped
  query the catalog does not expose as a facet, and the biography needs
  an enrichment field nothing writes yet — the same provider gap that
  keeps artist artwork from existing. Both are additive sections on a
  screen that is otherwise complete.
- `[in-repo]` **The client half of the waveform seek bar.** The server
  side landed ahead of P18 (`GET /items/{pid}/waveform`, ADR-0031 for the
  pass that fills it), and the generated Dart model exists, but nothing
  reads it: there is no `waxdeck_api` repository wrapper and no seek bar
  drawing it. P18 is the phase this landed ahead of. Two things it has to
  handle beyond `ready`: `unavailable` is final and means draw the plain
  slider, never a spinner, and it is the answer for every podcast
  episode, every cue-carved track, and every multi-file audiobook; and
  `resolution` is read from the response rather than assumed, since the
  1000 buckets are a catalog constant that an analysis-version bump may
  change.
- `[in-repo]` **Sleep-timer fade.** Now unblocked: the engine port
  grew setVolume for remote volume control, so the fade is a timer
  loop away.
- `[roadmap]` **The account menu is in the tab bar, not the app bar.** The
  layout system puts the avatar in the top app bar at every width; the
  shell owns no app bar, and the screens that do are the ones written
  before the design system existed, so on compact the control takes a
  fixed cell at the trailing end of the tab bar instead. It moves to the
  bar's trailing slot as the screens are rebuilt on `WaxScaffold`, which
  is also when the count question lands: a fifth domain tab plus an
  account cell is six targets on a phone. See ADR-0024.
- `[roadmap]` **No wifi-only switch for gapless preloading.** Playback
  prepares the next queue entry 30 seconds before the crossing whenever
  the admission policy allows it (music to music, passthrough stream,
  starts at its own head), with no way to hold that back on a metered
  connection. The per-device store it would be written to now exists
  (ADR-0027); what is still missing is the control in Settings, Playback
  and — the larger half — a connectivity port to tell metered from not,
  since no connectivity plugin is pinned anywhere and wrapping one is its
  own decision. Until then the cost is one track's worth of buffering
  ahead. See ADR-0020.
- `[roadmap]` **Spoken-word skip intervals are not configurable.** The deck
  bar's minus and plus controls jump 15 seconds back and 30 forward, which
  are the defaults every client ships, and there is no way to change them.
  The per-device store exists now (ADR-0027); the setting still needs its
  control in Settings, Playback, which is all that is left. See ADR-0023.
- `[roadmap]` **The deck bar has no volume control, at any width.** The
  layout system puts a slider in the bar's right cluster under two
  separate conditions: on desktop and web it is always present and drives
  local output, and on mobile it appears only while controlling a remote
  endpoint that reports `volumeControl`, since hardware buttons own local
  volume there. Neither is built, and only the second was written down,
  which is how the first went missing instead of being cut. Nothing local
  reads or writes the engine's volume: `AudioEnginePort.setVolume` and
  `volume` exist, and their only callers are the endpoint controller's
  session report and its `set-volume` case, so another device can turn
  this one down while its own user has no way to. `waxdeck_ui` carries no
  slider primitive either (the seek bar is bespoke, and the remote screen
  that has one predates the design system and uses Material's), so this
  wants that primitive, a volume field on `NowPlayingData` and
  `DeckBarActions`, a desktop and web gate, and a generated semantics id.
  It lands with the cast phase, which builds the second condition anyway;
  the radio player face and the keyboard map's volume and mute keys read
  the same state after that. See ADR-0023.
- `[in-repo]` **The web build's per-device settings binding is not covered
  by an automated test.** `BrowserClientSettingsStore` — the probe, the
  fallback to memory, the write-through shadow, the key semantics — is
  tested on the VM against a fake `BrowserStorage`, including a throwing
  one. What no test touches is `_LocalStorage`, the ten lines that hand
  over the real `window.localStorage`. Nothing in this repo runs under a
  browser: there is no `@TestOn` anywhere, `make test-app` runs
  `flutter test` on the VM per package, and `waxdeck_data`'s tests import
  `drift/native`, so `--platform chrome` cannot simply be switched on for
  the workspace. Adding Chrome to CI is an infrastructure decision that
  was deliberately kept off ADR-0027's change rather than smuggled in
  with it. Verified by hand in the meantime: collapse the sidebar in the
  web build, reload, still collapsed. Whoever adds a browser test target
  should take this with it.
- `[in-repo]` **The web perf gate's measurement run is still owed.** Parked
  for the larger UI and UX overhaul rather than spot-fixed, and the code
  the run needs has now landed: the corpus writes one directory per album
  with its own synthesized cover (`corpusgen`, `-covers=false` for the
  comparison without art), the rAF collector and wheel loop are a
  reusable helper (`e2e/tests/scroll-pacing.ts`), and `perf-web.spec.ts`
  measures the music indexes, a bucket listing, and the grid with a track
  playing alongside the original grid scenario. What is left is running
  it and recording the numbers.

  Two things to know before starting it. The corpus with covers is about
  half a gigabyte on disk (covers are roughly 400 KB each against 86 KB
  of audio per album), against well under a tenth of that without them.
  And the three scenarios are declared `mode: 'default'` so they run in
  one worker in order — running them at once would price the contention
  between them rather than the app, which is the opposite of the point.

  The reason it was split off rather than run inline: by the skwasm
  entry's own words the gate prices whatever raster-thread difference
  remains before the single-threaded force is removed, so while that
  entry stands the number has to be taken twice regardless.

  **The miss policy, named before the run so a red number is a decision
  and not an argument.** A miss on cold TTI, warm TTI, or login-to-grid
  is a hardening item and goes on the performance slice. A miss on scroll
  FPS or long-frame share on the *index* scenarios reopens the artwork
  negative cache's approach then and there, since those are the surfaces
  it just changed. The artwork pipeline (ADR-0025) already took the cheap
  levers — sized requests, bounded decodes, a day of client-side
  freshness — so a miss on the grid is a signal about the virtualized
  list rather than about artwork, and `-covers=false` is the run that
  tells the two apart.
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
  playing track does not expose its id yet), a public instance can use
  the tokenized `/media/art` the cast displays now use, and a static
  WaxDeck asset is the fallback. Navidrome ships this
  server-side instead, over a gateway connection authenticated with
  stored per-user Discord user tokens, which works from any client
  but is self-botting against Discord's terms of service; recorded
  so it is not re-derived as an option. Needs no sibling-repo work.

## Connect and casting

- `[roadmap]` **The deck bar does not say when playback is somewhere else.**
  The bar reads local playback alone, so handing a session to another
  endpoint leaves it showing the item stopped rather than "on
  [endpoint name]": the cast glyph over the artwork, the caption line,
  and the volume slider an endpoint reporting `volumeControl` gets are
  all specified and none is wired (`NowPlayingData.remoteEndpoint` is
  never set). That slider has a second reason to exist which this entry
  does not cover, tracked above under the deck bar having no volume
  control: on desktop and web it belongs there for local output, with no
  endpoint involved. The remote face stayed out of the deck bar's own
  phase because controlling another endpoint is a pushed
  screen holding its own watch-frame state, and making the shell follow
  it is a piece of the Connect UX rather than of the bar: the picker,
  the disconnect triad, and the refusal explanations land together with
  the cast phase. See ADR-0023.
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
  place mid-book. The refusal carries code `feature-unavailable`
  naming the pid, so a picker can offer "play here instead" rather
  than a dead end (P14's refusal explanations); client endpoints
  handle books fully. Needs part-aware loading and part-advance in
  the session manager.
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

- `[in-repo]` **PodPing update notifications.** Polling is the only feed refresh
  trigger.
- `[upstream]` **`unplayedCount` costs a walk per subscription.** The
  count on a subscription row loads the show's episodes and batch-reads
  their play states, so listing subscriptions is two queries per show
  (ADR-0032). It is opt-in per caller, so the Subsonic adapter does not
  pay it, and a listener follows tens of shows rather than thousands.
  but the durable shape is a counting query upstream, which would want a
  `podcast_pid` field on WaxBin's item query surface (there is a
  `podcast` field, and it is the show's title). Filed in
  `docs/upstream-requests.md`; the walk is correct meanwhile.
- `[in-repo]` **No concurrency or byte bound on the media relays.**
  `/s/{token}` caps concurrent anonymous streams; `/media/enclosure` and
  `/media/radio/{pid}` cap nothing, and both deliberately carry no
  overall client timeout because a stream runs as long as someone
  listens. So a user can point either at an endless or enormous remote
  file and hold a goroutine and an upstream connection per request. The
  URL comes from a feed or station the user chose rather than from the
  request, so this is resource use rather than an open proxy. Fix both
  together when it is worth a bound, since they have the same shape: a
  per-user cap plus an idle-read deadline, not an overall one.
- `[in-repo]` **The unfetch conflict is told apart by message, not
  code.** `RemoveEpisodeDownload` answers 409 for two unrelated reasons:
  someone is listening (wait for them) and a busy file-mutation job lease
  (retry shortly). Both carry `conflict`, so only the prose distinguishes
  them, and `podcasts.spec.ts` matches on that prose to decide what to
  retry. The durable form is a second code added to the defined-code list
  in `api/spec/_root.yaml` (`Error.code` is a plain string there, not an
  enum, so the list is the contract). Left out of the batch that
  introduced the split because it is a contract change and the two
  messages are stable in the meantime.
- `[in-repo]` **An analysis entry that exhausts its attempts is
  permanent.** The queue is keyed by essence hash, `EnqueueAnalysis`
  ignores a key it already holds, and only success deletes a row, so five
  failed attempts bar that audio for the life of the database. Work that
  cannot come good is now dropped (`errAnalysisMoot`), but a durable
  outage still burns the budget: a sidecar down for an hour leaves every
  file queued during it unanalyzable, and the on-access path cannot heal
  it because its enqueue is the same no-op. Wants a sweep of exhausted
  rows on a horizon (the prune job) or a reset on a genuinely fresh
  enqueue; not retry-forever, since a client polling a pending skip map
  re-enqueues on every request.
- `[in-repo]` **A skip map stays pending for audio deleted behind the
  server's back.** The item is still `present` in the catalog, so
  `SkipMapFor` enqueues and answers pending, while the worker drops the
  entry as moot: a client polling gets pending forever, re-queuing work
  that is dropped again. Harmless (playback of that item fails anyway)
  and self-correcting once a scan retires the item, but the honest fix is
  for the worker's discovery that the bytes are gone to reach the
  catalog, not just the queue.

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

- `[in-repo]` **Scripts outside the owned font set render tofu on web,
  online and off alike.** The owned chain covers Latin, Greek,
  Cyrillic, Arabic, Hebrew, Thai, and CJK, and the engine's own CDN
  fallback (its Roboto default and per-glyph Noto shards) is
  deliberately pointed at an unrouted same-origin path, so an instance
  behaves identically with and without internet: Devanagari, Tamil,
  emoji, and anything else unbundled renders as boxes instead of
  sometimes-working via Google. That trade is recorded in ADR-0016;
  what remains is growing the set as real libraries need it, which is
  one face per script in `tools/fetch-fonts.sh` plus a `WaxScript`
  entry and detection range in `WaxFonts` (emoji is the awkward one: a
  color-emoji face is its own multi-megabyte decision). Native builds
  keep using system fonts and are unaffected.
- `[in-repo]` **The e2e renderer hang is diagnosed: a memory race
  inside multi-threaded skwasm.** The old shape — one suite run in
  about four, a random spec stalls mid-step, page unresponsive,
  generic timeout — is the aftermath of a wasm fault. The page throws
  `RuntimeError: memory access out of bounds` inside skwasm's
  allocator on the paragraph-layout path (`ParagraphImpl::layout`,
  `TArray<Block>` copy, `sk_malloc`, `emscripten_builtin_malloc`), and
  from then on the renderer main thread and the skwasm render worker
  both spin at full CPU forever, so evaluate, rAF, and even compositor
  screenshot capture stall against it. Every spec now runs through
  `tests/fixtures.ts`, whose page fixture buffers console and
  pageerror from birth and, when a test fails or times out, races
  responsiveness probes (main thread, CDP, compositor, each worker)
  and snapshots every chromium thread twice — state, wait channel,
  CPU delta — into `hang-evidence.json` beside the trace. The first
  capture (audiobooks, second suite run of the night) showed exactly
  that dual spin with everything else idle. `e2e/skwasm-repro/`
  reproduces it with no WaxDeck code in three to five seconds: fresh
  multi-span paragraphs laid out every frame while the worker
  rasterizes the previous one. Captured stacks land in or under
  `SkStrike`, Skia's shared glyph cache, from both the layout side
  (`skhb_glyph_h_advances`) and the raster side
  (`onDrawGlyphRunList`), in four flavors including unaligned atomics
  on torn pointers. Forcing single-threaded skwasm — same build, the
  `forceSingleThreadedSkwasm` engine flag, injected suite-wide through
  a temporary knob during the investigation — ran the same hammer clean
  to its cap
  and ten suite runs without a hang (two of the ten failed on an
  unrelated desktop-loopback child-process flake, page responsive per
  the probe, under heavy background load). Engine revision
  83675ed27633283e7fc296c8bca22e841224c096, Flutter 3.44. Filed as
  flutter/flutter#190039, and the app now ships skwasm single-threaded
  (`web/index.html` owns the loader call and passes
  `forceSingleThreadedSkwasm` — the same block also sets
  `canvasKitBaseUrl` so the engine loads from the embedded bundle
  instead of Google's CDN, which the stock bootstrap reaches for and a
  LAN-only instance cannot). What remains is the un-forcing: when the
  issue closes or an engine upgrade lands, `e2e/skwasm-repro/` answers
  in seconds whether the race is gone, `WAXDECK_E2E_MT_SKWASM=1` runs
  the real suite multi-threaded to confirm, and the `perf-web` gate
  against the 100k corpus prices whatever raster-thread difference
  remains before the force is removed. Checked 2026-07-27: the issue is
  still open and the pinned engine has not moved
  (83675ed27633283e7fc296c8bca22e841224c096, Flutter 3.44.6), so the
  repro was not re-run and the force stays. The report was triaged that
  day, labeled for the web team and routed to it for evaluation, and a
  candidate fix is open as flutter/flutter#190048, "Link multithreaded
  skwasm in emscripten hybrid mode". That PR merging and an engine roll
  carrying it is the specific trigger to re-check, sharper than "when
  the issue closes": the issue can close on the PR alone, which changes
  nothing here until the pinned engine ships it.
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
- `[in-repo]` **Book and remaining metadata providers.** Hardcover
  (the ASIN to ISBN bridge), Google Books and Open Library fallbacks,
  and Discogs are not yet implemented as enrichment providers; Deezer,
  iTunes, Audnexus, and fanart.tv shipped. Each is one self-contained
  provider in the providers package.
- `[in-repo]` **The custom-metadata-provider spec is unpublished.** The
  documented OpenAPI contract that would let community regional
  providers plug in (the Audiobookshelf pattern) still needs writing;
  the in-process provider port it would bridge to is live.
- `[in-repo]` **The provider chain fills only the front artwork slot.**
  The art-role model (front, back, disc, booklet, background) ships on
  the read and write surfaces, but enrichment still fills the front
  cover alone: a provider candidate carries a single cover image, so
  fanning providers out to the auxiliary slots (a fanart.tv artist
  background, disc art) needs the candidate/provider model extended to
  carry per-role art first. The slots are readable and hand-settable
  meanwhile (docs/adr/0014).
- `[in-repo]` **No multi-slot artwork editor in the app.** The client
  can read `art-roles` and write any slot, and the metadata editor shows
  the own-versus-inherited cover indicator, but a surface to view every
  slot and upload or clear each one is unbuilt. It is a net-new UI (no
  artwork upload existed before), tracked rather than rushed into the
  art-role slice (docs/adr/0014).
- `[in-repo]` **Android folder picking is excluded from the upload
  surface.** File picking works on every platform (the endorsed
  `file_selector_android` implementation covers in-app file picks),
  but Android folder access means SAF tree URIs, which the
  `FilePickerPort` deliberately does not speak; the "Upload a folder"
  tile hides there (`canPickFolders`). Multi-select plus auto
  grouping covers the album case on Android meanwhile.
- `[in-repo]` **Upload quota counts imported sessions, so a filled quota
  never frees.** `UploadBytesInUse` sums every non-discarded session's
  declared size, imported ones included, and `DeleteUpload` refuses
  imported rows, so bytes that reached the library stay charged for
  good. Deleting the item does not help: `POST /library/items/delete`
  is shipped and permission-gated, but it never touches the uploads
  table, though `uploads.item_pid` is the link it would need. A user who
  fills a small quota stays locked out after following the refusal's own
  advice ("delete the item there").

  Decided: the quota means in-flight footprint, not total contribution.
  It caps what may sit in staging awaiting review, so an import releases
  the headroom it held. The fix is the accounting predicate (skip
  imported alongside discarded) plus honest naming, since "upload quota"
  reads as a storage-contribution cap to most people: the admin field
  becomes a pending-upload limit, and its helper text says that
  importing frees the space. The rejected reading, total contribution,
  wanted release-on-delete accounting that had to stay correct across
  trash, restore, purge, merge, dedup, and the health fixes, and it had
  no answer for a restore that would re-charge a user already at their
  cap.

  Lands with the admin users screen, which is what first makes a quota
  settable: every account runs uncapped today, so neither reading is
  observable and the label is where the decision becomes visible.
  Recorded because the setting is easily read as something it is not.
  This is a byte ceiling checked when a session opens, and enforced
  through the transfer (over-length bytes are truncated), not a rate
  limit or a time window; the only rate limiter in the server counts
  failed logins. It does not bound what a user adds to the library over
  time, and no free-space guard exists anywhere, so protecting the disk
  from a trusted but enthusiastic uploader is a separate unbuilt
  mechanism.
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
- `[in-repo]` **OpenSubsonic `explicitStatus` is not emitted for music.**
  Podcast episodes carry it now, mapped from the feed's own advisory
  flag. Music does not, and it is not the one-line addition it looks
  like: `ITUNESADVISORY` reaches WaxDeck only through the metadata
  editor's custom-tag surface, and the item read surface the Subsonic
  song mapping uses carries no custom tags, so filling the field means
  either widening that read surface deliberately or taking an extra
  read per song, which on a list response is an N+1. Whoever widens
  that read surface for another reason should take this with it. Note
  what the episode half does not do either: the field is only ever
  emitted in the positive direction, because the advisory parses to a
  bool and "declared clean" and "the source said nothing" are the same
  value, so claiming the former would be inventing an assertion.
- `[in-repo]` **Synced external playlists.** A YouTube playlist reaches
  the library two ways today and neither keeps a WaxDeck playlist in
  step with its source: "Add from URL" acquisition
  (`service/acquire.go`) downloads a playlist's videos once, clusters
  them into album review entries, and records no link back to the
  playlist; subscribing that same playlist as a show does sync on a
  schedule (the `feed-refresh` worker over the `feed_state` cursor) but
  models it as podcast episodes, not music tracks. The wanted feature
  binds a WaxDeck static playlist to an external source and reconciles
  its membership on a schedule. Most of the machinery exists: WaxTap
  enumerates a playlist in playlist order with a per-entry index,
  `waxtapsource` wraps that enumeration, the download path stamps
  `SOURCE_URL`/`SOURCE_ID`/`ACQUISITION_DATE` into every file,
  `feed_state` is the durable last-run/last-error/consecutive-failure
  record to copy, and `ReplacePlaylistItems` is the ordered-membership
  reconcile primitive (optimistic `baseUpdatedAt`). Net-new, all
  WaxDeck-side (a binding table in `waxdeck.db` keyed by playlist pid,
  per ADR-0003): (1) the binding row (source type, source ref,
  per-playlist sync mode, refresh interval, enumeration cursor); (2) a
  video-id-to-item map kept current as acquisitions resolve, since the
  provenance tag is never lifted into a queryable column and
  match/dedup/merge can move an item; (3) an eventually-consistent
  attach, because new tracks ride the normal review queue (chosen over
  auto-import) and join the playlist only once their review entry
  resolves into an item, in source order; (4) a raw ordered-entry
  accessor on `waxtapsource` (its current `Enumerate` is podcast-shaped:
  it drops currently-unavailable entries and carries an append-only
  newest-first cursor, neither of which suits a mutable playlist whose
  mirror must retain an already-downloaded track after its source video
  goes private). Decisions recorded so they are not re-litigated. Sync
  mode is per-playlist, not a global switch (one field on an
  already-per-playlist binding, one dropdown beside the interval; a
  faithful mirror and a seed-then-curate list are different intents),
  with three values: `append` (add new only, manual edits preserved),
  `mirror` (contents and order follow the source, manual edits
  overwritten, a removed video detaches but its file stays), and
  `mirror+trash` (mirror, and a removed video's file goes to the
  recoverable trash); default `mirror`, keeping files. Intervals are
  1/3/6/12/24 hours plus a manual sync-now; per ADR-0005 the scheduler
  and its failure accounting are WaxDeck's, so no new worker primitive
  is needed (extend the `feed-refresh` sweep or add a sibling that reads
  a per-binding due time). The binding is source-agnostic by design
  (chosen over YouTube-only): YouTube is the live re-fetchable source
  that auto-syncs, while matched sources (Spotify/Apple/CSV, already a
  one-shot import through `ImportStreamingPlaylist`'s portable-ref
  ladder) reconcile match-only and on demand until a live connector for
  them exists, downloading nothing and reporting misses rather than
  fetching. Refinements to fold in when this is built: a dry-run
  preview beside the manual sync-now (report would-add, would-remove,
  and unavailable counts before committing, mirroring the migration
  dry run and the rule preview); a sync-health surface reusing
  `feed_state`'s last-run, last-error, consecutive-failure, and
  auto-disable fields plus per-run add/remove/unavailable counts (the
  delivery-health shape the scrobble and notification rows already
  show); provenance dedup that reuses an in-library item matched by
  `SOURCE_ID` instead of re-downloading, with an append-mode tombstone
  so a track the user hand-removed is not re-added (mirror mode re-adds
  by design); and a sync notification event (added N, or failed) on the
  existing event catalog, which also closes the
  import-completed-notification gap recorded under Admin and ops. The
  worker gating is worth noting: the `feed-refresh` sweep only spawns
  when a podcast directory is configured, so a music-only instance
  wants a sibling sweeper (WaxDeck-owned composition-root wiring, no
  upstream), not an extension of that one. One cover rung rides this
  feature rather than the shipped playlist artwork: a synced list
  should prefer its source playlist's own thumbnail (the enumeration
  already surfaces one) over the mosaic built from members, which means
  fetching and storing it on bind and re-checking it on sync.

## Discovery and stats

- `[in-repo]` **Virtual tracks are not sonically analyzed.** A track
  carved out of a shared single-file rip by a cue sheet shares its
  backing file's audio essence, and embeddings are keyed by essence,
  so per-window analysis would collide with itself. The analysis
  sweep skips virtual tracks; they still appear in metadata-based
  mixes and inherit nothing sonic. Fixing it means keying embeddings
  by essence plus sample window and teaching the worker audio pull to
  serve the window (the stream surface already can).

  The waveform seek bar is the same gap seen from the catalog side and
  wants the same fix. `GET /items/{pid}/waveform` answers `unavailable`
  for a virtual track, because the peaks row belongs to the backing file
  and drawing the whole album's envelope under track three would be a
  convincing wrong answer. Windowing the stored buckets by the track's
  sample span is the cheaper half of this entry (no new analysis, just a
  slice of what is stored) and costs effective resolution, since a
  three-minute track out of a seventy-minute rip gets some forty of the
  thousand buckets. Whoever takes this entry should decide both together.
- `[in-repo]` **Time and mood mixes.** Daylist-style rotating mixes
  with scheduled auto-names are a scheduler and a naming table over
  the instant-mix engine that shipped; nothing else blocks them.
- `[roadmap]` **Search has no radio results.** The search screen's filter
  chips cover what `GET /library/search` answers: music, podcasts, and
  audiobooks. The layout gives it a Radio chip too, searching the station
  directory and offering "Add station" per result — that is the radio
  surface the radio slice rebuilds (logo proxy, add-station flow, the
  hub), and building a second one now is work that slice redoes. The chip
  lands with it.
- `[roadmap]` **Search is one tap further away from a phone's non-music
  domains.** The layout puts a search control in the top app bar below
  sidebar width, and the shell owns no top app bar — every screen brings
  its own — so the control lives on the screens rebuilt so far: the music
  hub, its indexes and listings, and the library grid, which is the
  compact landing screen. Podcasts, Radio, and the books screens get it
  as they are rebuilt, the same way the avatar does; until then search
  from one of them is Home and then the control.
- `[in-repo]` **A has-art signal on `FacetBucket`, once artist art
  exists.** The repeated-404 half of this is fixed — `ArtworkStore`
  keeps a negative cache, so a cover the server has answered 404 for is
  asked about once and drawn as a monogram from then on, and the artist
  dimension no longer asks at all — but the entry is kept because the
  reasoning behind those two choices is what the next agent tempted by a
  `hasArt` field needs, and because there is a real case left.

  **The premise the entry was written on was wrong.** It said item rows
  never 404 because the server omits `artUrl` when there is nothing
  behind it. They do: `summaryJSON` sets `ArtUrl` unconditionally, and
  `_shared.yaml` says so — "Always populated; the endpoint itself returns
  404 for items with no artwork." So this was never a bucket-only
  problem, which is why the fix is in the store, where it covers item
  rows too.

  **Two candidate probes were ruled out on evidence, and both would have
  shipped a regression.** A `hasArt` boolean computed from `ArtRoles`
  reports only the entity's own `art_map` rows, while scans store cover
  art at track level and album art is derived on read
  (`store/sqlite/art.go`: "Album art is derived on read from current
  track maps, so a re-cover, retag, or delete cannot leave a stale album
  mapping behind"). For a normally scanned album `/art` answers 200 and
  `ArtRoles(al-…)` is empty, so gating on it would have turned the album
  index into a wall of monograms. `ResolveArt(ref, front, 0)` is not the
  escape either: the `size <= 0` early return does skip the thumbnail,
  but it fires *after* the full source blob is loaded, so a 100-bucket
  page becomes 100 whole-image reads.

  **What is left.** Not asking for artist art is right because the answer
  is statically known: all three art-bearing enrichment providers gate on
  `enrich.TargetReleaseGroup`, and `SetEntityArtwork` is admin-only and
  human-driven, so nothing automatic ever writes artist-level art. The
  cost is that a hand-set artist cover stops appearing on the index row
  (it still appears on the artist's own screen, which reads the entity's
  art directly), and nothing in the UI explains the difference — the
  person most likely to hit it is the admin who set the cover. A contract
  field whose value is knowable statically is not worth the spec surface
  — so `hasArt` on `FacetBucket` becomes worth building when artist art
  starts existing, which is the provider chain filling auxiliary slots.
  Sequence it there, and the index row's silence closes with it.

  **The negative cache's own limit, for whoever touches it next.** It is
  cleared by a catalog invalidation, by a cover editor's `evict`, and by
  sign-out. Nothing else — so a cover that appears while the app is open
  and the sync channel is down stays a monogram until the channel
  reconnects and invalidates. That is the same window every other cached
  view has, and it closes the same way.
- `[upstream]` **The alphabet rail pages toward a letter rather than
  seeking to one.** `GET /library/facets` has no seek-to-letter, so
  tapping S on a long index asks for successive pages until an S-shaped
  bucket is loaded. Pages are 500 buckets served from one cached
  enumeration, so a long walk is a handful of cheap requests rather than
  a slow one — but it is still O(pages) round trips where a `startsAt`
  parameter (or the upstream `FacetPage` this endpoint's window is
  waiting on) would be one.
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

- `[in-repo]` **A degraded runtime library reports streaming trouble only
  on the audit entry.** Creating a library at runtime reconciles the
  streaming engine, and when that cannot happen (an engine too old to
  reload, or a path it cannot open) the reason is recorded on the
  `library.create` audit entry and logged, while the 201 itself is a
  plain success. Putting it in the response wants a `streamingWarning`
  on the create body; deferred because nothing consumes library creation
  yet -- there is no libraries screen in the app, so the field would be
  wire with no reader. Add it with that screen, which is where an
  administrator would actually see it.
- `[in-repo]` **Importers beyond Navidrome/Subsonic and
  Audiobookshelf.** The migration framework (portable-ref matching,
  backdated idempotent listen ingest, dry runs, task reports) is
  built; Jellyfin, Last.fm and ListenBrainz history, and the Spotify
  GDPR export ride it as fast-follows, as the roadmap allows.
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
  Device endpoints no longer walk into this: DLNA negotiation forces
  nothing at all when the renderer already plays the source's container,
  which is the same answer this entry wants and is reachable there
  because the decision is made with the source in hand. What is left is
  the client-pinned case, where the format arrives on the URL.
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
- `[in-repo]` **The read-only e2e scenario flips a switch the whole suite
  shares.** The two settings scenarios no longer race each other (one
  serial group), but read-only is server-global, so for the one request it
  is on, another worker's write would be refused too. The uploads specs
  are what that would hit; the window is a single round trip and it has
  not fired. Fix if it does: give the switch scenarios their own project
  after the parallel wave, as focus-a11y is.

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
