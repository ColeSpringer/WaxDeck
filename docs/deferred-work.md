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

- `[hardware]` **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- `[in-repo]` **A row cannot be dragged from a listing into the queue
  panel.** Multi-select landed (long press or a checkbox picks up-next
  rows; the set removes, moves to top, moves to bottom, and travels
  together under a drag), so what remains of ADR-0029's open half is the
  other gesture: picking a row up on an album, artist, listing, or index
  screen and dropping it on the panel. Pointer only when it lands -
  `LongPressDraggable` collides with the long press that starts a
  selection, and touch already has a path (pick the rows, or "Add to
  queue" from the row's own menu), so a touch drag would be a second
  gesture for a job that has one. Where a drop lands is the other
  decision: appending is the cheap answer and inserting at the row under
  the pointer wants a sliver-relative hit test, which is real work.
  Panel only either way, since the `/queue` screen covers what would be
  dragged from. See ADR-0029.
- `[in-repo]` **"Appears on" reads items where it wants album buckets.**
  The shelf draws album cards but the only scoped read available is
  `listItems(facet: credit-artist)`, so it downloads item rows and
  collapses them client-side. The dimension buckets an artist's own
  tracks too, so a prolific artist's first page can be entirely
  self-releases; the shelf pages past that, bounded at four, which fixes
  the empty shelf and makes the worst case a larger download. The real
  fix is a scope on `GET /library/facets` -- album buckets where
  `credit_artist_pid` is this artist -- which is bounded by construction
  and returns albums directly. Server-side that is `facetScopeQuery` plus
  `applyFacetFilter` on a dimension other than the one enumerated; the
  spec change is one optional facet/facetKey pair.
- `[in-repo]` **An artist screen has no biography.** "Appears on" landed
  on the `credit-artist` browse dimension. The biography still needs an
  enrichment field nothing writes yet - the same provider gap that keeps
  artist artwork from existing - so it stays sequenced behind that
  rather than behind a query.
- `[in-repo]` **The album screen and the metadata editor cannot show a
  release's identity.** The catalog carries barcode, label, catalog
  number, media, and country on the album entity, and WaxDeck reaches
  them two ways already: smart rules filter on `albumBarcode` and its
  four siblings, and an entity edit writes barcode, label, and catalog
  number. What is missing is a *read* surface. Upstream keeps these off
  `model.ItemView` on purpose - rows.go budgets its columns and these
  are entity-scoped - so they are served by `entity info album`, and
  WaxDeck exposes no album-entity endpoint at all: `AlbumFacts.of`
  derives the whole header from the tracks, with the comment "there is
  no album endpoint to ask". Surfacing them means adding one
  (`GET /albums/{pid}`, over `Library.EntityByPIDs`), which is a new
  route and DTO rather than a field on an existing one, and the editor's
  album panel then reads it. Media and country would join the entity
  edit's vocabulary in the same change: the catalog accepts them and the
  spec's `editEntity` prose still lists only the first three.
- `[in-repo]` **Nothing can be pinned to home.** Section 6.1's second
  shelf is user-curated - long-press any entity, "Pin to Home" - and is
  marked optional there, which is why the shelf home shipped without it
  (ADR-0038). It wants two things neither of which is a shelf: a list of
  pids that follows the account rather than the device, which is a
  `Prefs` field and a spec delta (the shape radio favourites already
  took), and a pin affordance on every entity surface in the app, which
  is where the work actually is. The shelf itself is one more `ItemShelf`
  over a provider that resolves pids to items.
- `[in-repo]` **The book player draws no waveform.** The server half
  landed: `GET /items/{pid}/waveform` takes a `partIndex` and answers
  the requested part's own envelope, so a multi-file audiobook is
  `ready` per part rather than `unavailable` whole (ADR-0040). The
  client still asks for one only when `mediaType == MediaType.music`
  (`player_screen.dart`), because a book's seek bar is a chapter's
  timeline rather than a file's, and deciding what a book scrubber
  draws is a player-face question rather than a contract one. A
  whole-book scrubber would not want the per-part endpoint at all: the
  catalog exposes `PeaksForItem(itemPID) []model.ItemPeaks`, every
  part's envelope in one read, which is the shape a book-timeline
  waveform is built from.
- `[in-repo]` **A place cannot be marked offline.** Audiobook bookmarks
  are a live read against the server (ADR-0041): the sheet fetches on
  open and marking one needs a round trip. Everything else a listener
  does to a book while offline is mirrored - the position checkpoints
  through the outbox, the audio plays from the download - so a plane is
  exactly where this shows. Making it work is the shape the checkpoint
  queue already has: a sync kind, a delta, a mirror table, and a queued
  create with a client-minted id the server accepts. Left out because a
  book holds a handful of these and nothing else about them wants a
  mirror, so the machinery would be built entirely for this one gap.
- `[in-repo]` **The downloads manager reports what WaxDeck holds and not
  what the device has left.** The storage header adds up used bytes by
  medium, which is the half a listener can act on; the layout also asks
  for device free space beside it, and that half is cut rather than faked.
  Nothing in Dart's own libraries answers how much room a volume has left:
  `dart:io` has no `statvfs`, `Process.run` is unavailable on iOS
  altogether, and there is no `df` on Windows, so the subprocess route is
  broken on the two platforms that matter most for downloads. What it
  wants is a plugin behind a WaxDeck-owned port per the wrapping rule,
  which is a pinned dependency and a decision of its own for one number.
  Worth taking with the next plugin that lands for another reason. See
  ADR-0033.
- `[in-repo]` **The language picker the layout blueprint specifies and
  Settings does not draw.** Blocked on the app being localized at all,
  which nothing here has started: no `flutter_localizations` in any
  pubspec in the workspace, no `l10n.yaml`, no `.arb`, and around 1,200
  user-facing string literals in `app/app/lib` by a conservative count -
  an undercount, because the help lines are written as multi-line
  concatenations a grep reads as several. `Prefs.locale` is carried
  through `PrefsController` so a write preserves it, and read by nothing.
  The size is not the whole of it: extraction is code and finishes,
  translation is people and does not, so a picker offered before there is
  a second language to pick is the same empty control as one offered
  before extraction. Worth taking when somebody is ready to own the
  translations, not before.
- `[in-repo]` **The web build's per-device settings binding is not covered
  by an automated test.** `BrowserClientSettingsStore` - the probe, the
  fallback to memory, the write-through shadow, the key semantics - is
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
  measures the music indexes, a bucket listing, and the tracks index with
  a track playing alongside the plain tracks-index scenario. What is left
  is running it and recording the numbers.

  **Still owed after the hardening phase, deliberately.** The phase that
  scheduled this is the one that flipped the URL strategy, swept the
  remnants, and recorded the bundle (`docs/releasing.md`); the run itself
  is a multi-hour manual job on a half-gigabyte corpus whose result is
  provisional while the skwasm force stands, which is the same reason it
  was split off in the first place. The miss policy below was named
  before the run so a red number is a decision rather than an argument,
  and it still stands.

  The scenarios moved with the shelf home (ADR-0038): the landing wait is
  login-to-home, which is eight browse reads rather than one grid page,
  and every scroll scenario is over a listing rather than over the
  deleted grid. The `gridMs` budget is unchanged and is now about a
  different thing, so the first run is the one that says whether 2.5
  seconds is still the right number.

  Two things to know before starting it. The corpus with covers is about
  half a gigabyte on disk (covers are roughly 400 KB each against 86 KB
  of audio per album), against well under a tenth of that without them.
  And the three scenarios are declared `mode: 'default'` so they run in
  one worker in order - running them at once would price the contention
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
  levers - sized requests, bounded decodes, a day of client-side
  freshness - so a miss on the grid is a signal about the virtualized
  list rather than about artwork, and `-covers=false` is the run that
  tells the two apart.

- `[in-repo]` **Discord presence has no image at all until the mark is
  final.** The status, the track, the artist, the album and the progress
  bar all render; the square beside them is blank, because Discord draws
  it from an art asset uploaded to the application and none has been
  uploaded. That is waiting on the logo rather than on any code: the
  client already sends the key (`kDiscordCoverAsset`, the string
  `waxdeck`, in `app/app/lib/src/desktop/discord_presence.dart`), and
  Discord renders an activity with no large image when the key resolves
  to nothing, which is why presence ships looking deliberate rather than
  broken. **To close it:** upload a square PNG under exactly that key in
  the developer portal's art assets for application
  `1534302390650405078`, and nothing needs rebuilding - the key is
  resolved by Discord at display time, so an existing install picks the
  image up. 512 px is the size the other surfaces settled on. If the
  final mark wants a different key, change the constant with it. Worth
  doing in the same pass as any other brand asset that lands with the
  logo, since `tools/generate-brand.py` will be re-run anyway.

- `[in-repo]` **Discord presence shows the application's own cover, not
  the album's.** Presence shipped in P22 (ADR-0045) with the status,
  the track, the artist, the album, and the timestamps that drive the
  progress bar; the image beside them is the asset uploaded against the
  Discord application (see the entry above - not yet uploaded), the same
  for every track whenever it is. The two richer sources
  named when this was first recorded are both out of reach today, and
  for different reasons. **Cover Art Archive** needs a MusicBrainz
  release id on the item read surface, which is an upstream ask (see
  `docs/upstream-requests.md`): `model.ItemView` carries no MBID, which
  is the same wall the `missing-mbid` health check ran into
  (`server/internal/service/health.go`). **The tokenized `/media/art`**
  a cast receiver uses would work on an instance the internet can reach,
  but the token is minted per play-info and the presence binder does not
  hold one: `PlaybackSession` fetches its `PlayInfo`, uses the stream
  URL, and lets it go, and asking for another would open a second
  server-side stream session. Either fix is a change to a layer that
  exists for something else, for a 512-pixel square in a chat client.
  Also unbuilt: presence for playback happening on *another* device this
  desktop is mirroring through Connect. The binder reads local playback
  only, which is the honest half - "listening to" is a claim about this
  machine's ears - and a remote session is what the deck bar names.

- `[hardware]` **The low-end validation pass has not run.** The overhaul's
  performance section asks for one pass on a low-end Android device
  profile and one against a Raspberry-Pi-class server before the work is
  called done - startup, listing scroll, player open, palette extraction
  timings. Neither device exists here: there is no Android hardware in
  this environment and no ARM single-board machine, and an emulator on a
  workstation prices the workstation. It is the same gate as the
  real-device cast checklist and waits on the same thing. Whoever runs it
  should take the web perf gate's corpus with them, since the two answer
  adjacent questions.

- `[in-repo]` **The artwork precacher is built, tested, and wired to
  nothing.** `ArtworkPrecacher` warms the covers just past the viewport
  when a scroll stops - batched three at a time, superseded by the next
  call, never during a fling - and `artworkPrecacherProvider` scopes one
  to the screen watching it. No screen watches it. The performance design
  lists idle precache alongside the sized rungs and the bounded decodes
  that did ship, so this is the one lever of that set that is still
  potential rather than actual. What it needs is a caller: a scrolling
  surface that notices its own scroll ending and can name the covers just
  past its viewport, which the music listing and the index screens both
  can (they already read `metrics.pixels` against `maxScrollExtent` to
  page). Left unwired rather than guessed at because "when a scroll stops"
  and "how far ahead" are numbers worth setting against the perf run's
  measurements rather than before them - so take it with the entry above.

- `[in-repo]` **The saved-radio list has no way in from a row.** Songs
  kept off the air list, mark themselves once the library holds them,
  search, and remove. What a row cannot do is hand itself to
  Add-from-URL or to the review queue's identify search - both are
  surfaces that already exist, and neither has a caller from here. A
  nicety over shipped machinery rather than new machinery.

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
  place mid-book. The refusal carries code `feature-unavailable`
  naming the pid, so a picker can offer "play here instead" rather
  than a dead end (P14's refusal explanations); client endpoints
  handle books fully. Needs part-aware loading and part-advance in
  the session manager. When it lands, delete the client's special
  case with it: `feature-unavailable` is the umbrella code for
  everything a target cannot play (a windowed track answers it too),
  so the picker tells this refusal apart by the phrase
  "multi-part audiobook" in the server's message - `multiPartRefusal` in
  `server/internal/api/player.go`,
  `_explain` in `app/app/lib/src/connect/device_picker.dart`, and
  `TestMultiPartRefusalWording` holding the two together.
- `[in-repo]` **Cast preflight verifies server-side only.** The
  reachability verdict is the server fetching itself through each
  candidate base; true device-side verification (loading a probe URL
  on the device and watching status) would catch DNS and cert
  failures the server cannot see.
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

## Compatibility

- `[in-repo]` **NSP import and export.**
- `[hardware]` **Driving a real client binary in CI.** No Docker in the dev
  distro, and the web-based Subsonic clients need CORS headers
  WaxDeck does not expose; the client trace suites (Subsonic and
  gpodder) are the automated stand-in and fail on missing endpoints.

## Infrastructure

- `[in-repo]` **The app installs no top-level error handler, so the
  defects its controllers deliberately rethrow reach nothing.** Every
  paged controller catches the expected transport failure, keeps what it
  has, and rethrows anything else - a decode failure, a bad cast - with
  a comment saying the error is left to "reach the zone's handler
  instead of vanishing here". There is no such handler: `main.dart` sets
  neither `PlatformDispatcher.instance.onError` nor `FlutterError.onError`
  and runs no guarded zone, and the nine call sites drop the future
  besides. So the rethrow is caught by the root zone, printed in debug,
  and silently discarded in release - the opposite of what the comments
  promise. Wrapping the call sites in `unawaited` would change nothing;
  what is missing is the handler, and what it should *do* is the
  decision: there is no logging or telemetry surface for it to report
  into, so "print it" and "show the listener something" and "send it
  somewhere" are three different products. Left for that decision rather
  than guessed at, and the comments corrected with it - they are the
  part actively misleading today. Found during phase 3 review; the
  pattern is older, and the saved-radio list shares it exactly.

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
  inside multi-threaded skwasm.** The old shape - one suite run in
  about four, a random spec stalls mid-step, page unresponsive,
  generic timeout - is the aftermath of a wasm fault. The page throws
  `RuntimeError: memory access out of bounds` inside skwasm's
  allocator on the paragraph-layout path (`ParagraphImpl::layout`,
  `TArray<Block>` copy, `sk_malloc`, `emscripten_builtin_malloc`), and
  from then on the renderer main thread and the skwasm render worker
  both spin at full CPU forever, so evaluate, rAF, and even compositor
  screenshot capture stall against it. Every spec now runs through
  `tests/fixtures.ts`, whose page fixture buffers console and
  pageerror from birth and, when a test fails or times out, races
  responsiveness probes (main thread, CDP, compositor, each worker)
  and snapshots every chromium thread twice - state, wait channel,
  CPU delta - into `hang-evidence.json` beside the trace. The first
  capture (audiobooks, second suite run of the night) showed exactly
  that dual spin with everything else idle. `e2e/skwasm-repro/`
  reproduces it with no WaxDeck code in three to five seconds: fresh
  multi-span paragraphs laid out every frame while the worker
  rasterizes the previous one. Captured stacks land in or under
  `SkStrike`, Skia's shared glyph cache, from both the layout side
  (`skhb_glyph_h_advances`) and the raster side
  (`onDrawGlyphRunList`), in four flavors including unaligned atomics
  on torn pointers. Forcing single-threaded skwasm - same build, the
  `forceSingleThreadedSkwasm` engine flag, injected suite-wide through
  a temporary knob during the investigation - ran the same hammer clean
  to its cap
  and ten suite runs without a hang (two of the ten failed on an
  unrelated desktop-loopback child-process flake, page responsive per
  the probe, under heavy background load). Engine revision
  83675ed27633283e7fc296c8bca22e841224c096, Flutter 3.44. Filed as
  flutter/flutter#190039, and the app now ships skwasm single-threaded
  (`web/index.html` owns the loader call and passes
  `forceSingleThreadedSkwasm` - the same block also sets
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
- `[in-repo]` **The live fan-out's accepted edges (ADR-0036).** The
  invalidation fan-out defers around in-flight first builds via a
  `ProviderObserver` ledger; three edges are known, each bounded, none
  observed outside construction. A first build that never lands (a hung
  request; no transport deadline exists) keeps its topic's retry timer
  re-arming every window for the life of the session - a set lookup per
  tick, no network; closes for free if request deadlines ever land. A
  watched instance invalidated mid-first-build from outside the fan-out
  rebuilds into a bare loading the notification gate suppresses, so that
  one instance rides plain pacing until a differing state lands - the
  pre-deferral behavior, not a new failure. And a nested `ProviderScope`
  overriding a fan-out target would sit outside `allProviders`'
  enumeration (children are excluded), unreachable by sweep and retry
  alike, as it already was by the plain invalidations before ADR-0036;
  no such scope exists, and whoever introduces one takes the fan-out's
  enumeration with it. The reasoning lives in the ADR's consequences
  section.
- `[in-repo]` **The components that landed after the design system have CI
  goldens and no readable ones.** The golden suite runs twice: CI goldens
  block out text and are compared with a tolerance, so they gate layout,
  spacing, and colour on any host; the readable platform goldens render
  real type and are the only thing that catches a wrong weight or a lost
  variable axis, and they are baselined on Linux and skipped everywhere
  else. `components_late_golden_test.dart` - the transport, settings
  rows, the console table, the entity header, the palette and its
  shortcut sheet, the station dial, the mini player, and the later
  controls - was written on a macOS host, which cannot produce a Linux
  baseline, so it declares itself CI-only rather than shipping a suite
  that goes red on CI. The gap is narrower than it sounds: the readable
  pass is a statement about `WaxType`, and the P0 set plus the composites
  already render the whole type ramp readably. To close it, run
  `flutter test test/components_late_golden_test.dart --update-goldens`
  on Linux and drop the `ciOnly` config from that file's `main`.

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
- `[in-repo]` **Android folder picking is excluded from the upload
  surface.** File picking works on every platform (the endorsed
  `file_selector_android` implementation covers in-app file picks),
  but Android folder access means SAF tree URIs, which the
  `FilePickerPort` deliberately does not speak; the "Upload a folder"
  tile hides there (`canPickFolders`). Multi-select plus auto
  grouping covers the album case on Android meanwhile.
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
- `[in-repo]` **The identify search takes no hand-typed query.** An entry's
  candidates come only from what the files claim - tags, fingerprints, and
  the cleaned "Artist - Track" parse - and nothing lets the reviewer say
  "search for this instead": review offers approve, as-is, unofficial, skip,
  and discard, and an item's rematch reruns the same derivation over the
  same tags. When the derivation misses, the person watching can see exactly
  why and still cannot help: a Topic-channel single titled "How Ya Livin'
  feat. Nas" recording-searches as that whole quoted phrase, MusicBrainz
  titles the recording without the suffix, and the entry closes with zero
  candidates. Wanted: editable artist, album title, and track title on the
  review entry and the rematch surface, offered always rather than gated on
  poor first results (a right-looking guess can still be the wrong release),
  feeding a re-identify that uses the typed values in place of the derived
  ones. The seam is narrow: identification already rebuilds its query from
  the entry payload on every run, so a stored per-entry override consulted
  by `recordingQuery` and the album search, plus a re-identify action that
  requeues a pending entry, reaches the whole pipeline without touching the
  engine.
- `[in-repo]` **A single-track unit is scored like a mostly-missing album.**
  The distance model charges every release track no staged file matched
  (the `missing` component, weight 0.9 per track), which is right for an
  album rip with gaps and wrong for a unit that only ever asked for one
  track: a single acquired video matched perfectly onto a twelve-track
  release still lands in the thirties, because the eleven tracks nobody
  asked for dominate the sum. Decided: the queue keeps showing the whole
  release (seeing the rest of the album is a feature, not a leak), and the
  percentage should reflect what was asked for - the unit's own tracks for
  a one-file unit (a single video, a single uploaded file), the full
  release exactly as today for album-shaped units (multi-file uploads and
  playlist acquisitions both arrive as multi-track units through the same
  clustering, so no per-source flag is needed; unit size is the intent
  signal). Two consequences to take deliberately rather than discover.
  Without the missing penalty every release carrying the recording - the
  album, each compilation, a single - scores nearly alike, so the top slot
  needs a preference (header agreement with the file's tags, an album over
  a compilation) to stay meaningful. And auto-apply becomes reachable for
  singles, which today the missing penalty forecloses by construction;
  whether a lone track should ever auto-pick among near-tied releases is a
  wrong-release-risk decision to make explicitly, not inherit.
- `[in-repo]` **Identification cannot be declined at submission.** Every
  upload and acquisition that opens a review entry is queued for
  identification unconditionally; the only off switch is the per-library
  matching mode, an administrator's setting over everyone's content.
  Wanted: a per-submission choice ("identify this", on by default) on the
  upload sheet and the Add-from-URL sheet, plus a per-user default in
  Settings, for the uploader who already curated their tags and wants the
  files taken as delivered. The wire is small - a flag on the upload
  session and acquisition create calls, a `Prefs` field for the default -
  and the pipeline half is one branch: an entry opened with identification
  declined skips the match queue and sits ready for its decision. The open
  question to settle when building it: whether declining still stops at
  review for a one-tap as-is confirm (safer, and the queue stays the audit
  trail) or imports straight through as-is with no stop (closer to what
  "leave my tags alone" means); confirm-first matches how upload review
  works today.
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
  existing event catalog, beside the `import-completed` event an
  auto-applied upload already emits. The
  worker gating is worth noting: the `feed-refresh` sweep only spawns
  when a podcast directory is configured, so a music-only instance
  wants a sibling sweeper (WaxDeck-owned composition-root wiring, no
  upstream), not an extension of that one. One cover rung rides this
  feature rather than the shipped playlist artwork: a synced list
  should prefer its source playlist's own thumbnail (the enumeration
  already surfaces one) over the mosaic built from members, which means
  fetching and storing it on bind and re-checking it on sync. The client
  slots this needs are in place as of the playlists rebuild (ADR-0035):
  the detail header already draws a chip row under it, so a sync-status
  chip is a chip rather than a layout, and the overflow is a declared
  action enum with the cover verbs grouped, so the settings sheet
  (source binding, sync mode, interval, sync-now with the dry run) is
  one more case in it.

## Discovery and stats

- `[in-repo]` **The web build has no downloads of its own to announce.**
  The bell now reports what this device finished transferring
  (`NotificationKind.download`), which the web build can never produce:
  it has no local download manager at all, so there is no transfer of
  its own whose completion it could announce. Not a platform-notification
  limitation and not a missing API - what is missing is the download
  manager, which is ADR-0033's whole subject. Recorded here so the next
  reader does not go looking for a notification API to fix it with.
  Server-side enclosure fetches are a different event and do reach every
  platform, through the `episode-downloaded` marker on the user stream.
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
- `[in-repo]` **A has-art signal on `FacetBucket`, once artist art
  exists.** The repeated-404 half of this is fixed - `ArtworkStore`
  keeps a negative cache, so a cover the server has answered 404 for is
  asked about once and drawn as a monogram from then on, and the artist
  dimension no longer asks at all - but the entry is kept because the
  reasoning behind those two choices is what the next agent tempted by a
  `hasArt` field needs, and because there is a real case left.

  **The premise the entry was written on was wrong.** It said item rows
  never 404 because the server omits `artUrl` when there is nothing
  behind it. They do: `summaryJSON` sets `ArtUrl` unconditionally, and
  `_shared.yaml` says so - "Always populated; the endpoint itself returns
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
  `ArtRoles(al-...)` is empty, so gating on it would have turned the album
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
  art directly), and nothing in the UI explains the difference - the
  person most likely to hit it is the admin who set the cover. A contract
  field whose value is knowable statically is not worth the spec surface - so
  `hasArt` on `FacetBucket` becomes worth building when artist art
  starts existing, which is the provider chain filling auxiliary slots.
  Sequence it there, and the index row's silence closes with it.

  **The negative cache's own limit, for whoever touches it next.** It is
  cleared by a catalog invalidation, by a cover editor's `evict`, and by
  sign-out. Nothing else - so a cover that appears while the app is open
  and the sync channel is down stays a monogram until the channel
  reconnects and invalidates. That is the same window every other cached
  view has, and it closes the same way.
- `[in-repo]` **Share cards carry no artwork.** The year-in-review
  cards render and export (docs/adr/0047), and everything on them is
  text and tokens: a top-artists card is a list of names rather than a
  mosaic of covers. The card is deliberately one frame with no network
  in it, so drawing covers wants the store's `bytesFor` threaded into
  the render as a pre-fetch step before the boundary is captured, plus
  a decision about what a card does when a cover is missing. Clip cards
  for episode shares are the same shape and are not built either.
- `[hardware]` **The Android share path for a card is unverified.**
  Exporting a card on Android writes it into a FileProvider-scoped
  cache directory and opens `ACTION_SEND` over the `waxdeck/share`
  channel (docs/adr/0047). There is no device here and no Android build
  in CI, so the Kotlin handler, the manifest `<provider>`, and the
  `res/xml/file_paths.xml` scope have never run. What to check: the
  chooser opens, the receiving app can read the image (a wrong
  authority or an unscoped path fails here), the temp-then-rename
  leaves no `.tmp` behind, and a second export of the same card
  replaces rather than duplicates.

## Admin and ops

- `[in-repo]` **Two admin console sections are declared and unbuilt.**
  The layout blueprint's 6.15 names three; notification targets landed
  (ADR-0052 - a re-parent, since the editor and its endpoints already
  existed under the listener's Integrations screen). Share links are
  still listed only for their owner and the `all=true` oversight listing
  has no screen; and the transcoding limits are set without the
  current-session context that would say what they are actually
  bounding. Each is a section registration and one screen against
  endpoints that already answer.
- `[in-repo]` **The first-run guided flow is the console, not a wizard.**
  6.14 describes a three-step card flow after the create-admin form (add
  a library, start a scan, "while it warms up"). What shipped is the
  console's own libraries screen, its Scan library action, and a
  warming-up card on the dashboard, which is where a new administrator
  lands and which now says something true - scan discoveries identify
  themselves. A wizard that walks somebody through those three screens
  in order is still worth building; it is a presentation of surfaces
  that all exist rather than new capability.
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
- `[in-repo]` **Radio scrobbling is off per account, not per station.**
  The account-wide switch ships (`Prefs.radioScrobbleOptOut`, ADR-0037),
  which covers the listener who wants none of it. What the original entry
  also floated is a per-station flag, for the household that scrobbles
  its music stations and not its talk ones. That wants a per-user
  per-station bit, and the only per-user station state that exists is the
  favourites list; whoever adds a second one should decide whether they
  share a shape.
- `[in-repo]` **`editing-prototype`'s right-click selection check is
  quarantined.** It drives a secondary click over selected canvas text,
  which on the web build opens the BROWSER's native context menu - an OS
  window, outside the DOM, dismissed by an Escape that a sibling stealing
  focus swallows. It passes alone and passes most full runs; across a few
  dozen it has failed twice, which is the bar this suite set for no
  longer believing a test (ADR-0050). Tagged `@quarantine`, so it is out
  of the blocking projects and still runs in the soak. To retire the
  entry: either pin the selection through something that does not depend
  on the native menu closing, or decide the prototype's go/no-go record
  no longer needs this probe and delete it.

- `[in-repo]` **`mutators-admin` runs seven tests single-file to protect
  one global switch.** The project sets `fullyParallel: false` and is
  itself a dependency barrier, so three of four workers idle for its
  length and that idling compounds into the back half of the run.
  Wrapping the two `/admin/settings` read-modify-writers in a
  `describe.serial` and dropping the flag looks like the fix and is not:
  one of that pair turns server-wide read-only on for the length of its
  body, and read-only refuses every write on the stack with a 409 - the
  trash round trip, the uploads, the runtime library. It is the same
  global switch the project chaining already exists to keep off the
  uploads project, seen from inside the file. What would actually free
  the workers is making the read-only test stop being global: its own
  project after this one, or a per-library read-only flag it can set on
  a library nothing else in the file touches. Weighed against ADR-0050's
  preference for scheduling facts living in the config, which is why the
  flag is written there.

- `[in-repo]` **A residual of ADR-0049's driver layer: duplicated
  shapes worth folding.** The driver itself landed; what is left is the
  drift inside it, measured rather than estimated. `text()` is defined
  nine times and has already diverged - seven copies return `.first()`,
  two (discovery, settings) take an `exact` flag and return the
  unfiltered locator, so the same call means "first match" on seven
  surfaces and a strict-mode violation on two, and two call sites paper
  over it by writing `.first()` themselves (`settings.spec.ts:77`,
  `discovery.spec.ts:42`). `constructor(private readonly ctx: Ctx) {}`
  appears twenty times across nineteen files and belongs on an abstract
  `Surface` in `driver/context.ts`. The hand-rolled retry unit appears
  five times with the same `2_000` literal, and `async function
  subsonic(...)` is defined twice (sync.spec.ts and playlists.spec.ts).
  Roughly thirty exported surface methods have no callers at all
  (Sharing.row/revoke/copy, Review.approve/skip/filter, Admin.console
  /section, Queue.screen/entry, Player.ready/control/choose,
  Playlists.open/overflow, Music.sort/anyItem, Auth.error/signOut,
  Shell.ready, Settings.ready, Books.hub, Radio.hub, Home.card,
  Stats.listenLog) - each an unexercised locator contract that a
  semantics-id rename rots silently, and `strict: true` without
  `noUnusedLocals` cannot see them.


## Decided, not deferred

Every browse validates the caller's pid, and that is a behaviour
change WaxDeck accepted rather than work it postponed. waxbin's
`browseFilter` short-circuits only when a query has neither an entity
nor a where clause, and since ADR-0048 a built query never is, so
`/music/tracks`, `/music/albums`, `/music/artists` and every
alphabetical browse now resolve `UserPID`. The cost was overstated when
this was first written down as a deferral: `userStateJoin` returns
early with no join clause when the query needs no user state, so it is
one indexed `userIDByPID` lookup per browse, not a join. What actually
changed is that `Browse(alphabetical, {UserPID: "bogus"})` errors where
the field used to be ignored, which waxbin warns about and WaxDeck
takes on purpose - validation beats a silent fallback to
default-scoped results. There is nothing to build and no upstream ask
behind it; do not file one.

Signup spends its rate-limit budget on success as well as failure, and
that is the anti-abuse decision rather than a missing `Success` call.
`signup.go` says so where it happens: "account creation is the expensive
outcome. A NAT'd household admitting a handful of members stays under
the threshold; a script farming accounts does not." What made it read as
a bug was the shared key - behind a reverse proxy every signup counted
against the proxy's address, so the cap was server-wide - and
`WAXDECK_TRUSTED_PROXIES` (ADR-0052) is the whole of that fix. With
correct client addresses the budget is per caller, which is what it was
always meant to be. Do not add a `Success` call on the success path; it
would undo the decision, not complete it.

The snapshot path's tombstone guard is deliberate belt, not dead code:
`sync.go`'s snapshot builds its page from `visibleItems()`, so
`archived(it)` inside `itemSyncEntry` cannot be true there and the
`entry.Op == syncOpDelete` half never fires. The comment beside it says
so ("The query above already drops them; this is the belt for the pids
the delta path tombstones"), and the same goes for the nil argument and
`tombstoneReason`'s nil branch. Removing them would make the delta path's
correctness depend on the snapshot query never changing.

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
