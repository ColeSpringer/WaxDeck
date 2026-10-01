# Deferred work

The tracked list of WaxDeck work that was cut from an otherwise
shipped slice.

Every entry carries a gate tag saying what actually blocks it:

- `[in-repo]` nothing blocks it; it was cut for scope and is ours to
  build whenever it is picked up.
- `[upstream]` needs sibling-repo work first; the ask itself lives in
  upstream-requests.md and the entry names it.
- `[hardware]` needs a device or environment the dev box lacks
  (a phone, a head unit, real cast hardware). Docker used to be on that
  list and is not: it is available here, and `make up`, `make dist`, and
  `make goldens-linux` all depend on it.
- `[roadmap]` deliberately rides a named later slice; listed here
  only because the cut happened mid-slice and would otherwise read
  as forgotten.
- `[third-party]` needs a fix in a dependency outside the Wax repos;
  the entry names the package and what WaxDeck does meanwhile.

## Playback and apps


- `[third-party]` **The Linux tray icon does not come back when the
  panel restarts.** cnativeapi (under tray_manager 0.6+) registers the
  StatusNotifierItem with the watcher once, at creation, and never
  watches the watcher's name; restart waybar, xfce4-panel or kded, or
  start a bar after the app, and the icon is gone until the app
  restarts. The appindicator library behind tray_manager 0.5 re-registered
  on `NameOwnerChanged`. Wanted from cnativeapi: watch the two watcher
  names and re-register when one appears. Meanwhile: none; the app is
  reachable from its window and the tray is a convenience.

- `[third-party]` **Installing the Linux tray icon can stall the UI for
  up to two seconds per watcher name.** cnativeapi registers with
  `g_dbus_connection_call_sync` and a 2000 ms timeout, tried for the
  KDE and then the Canonical watcher name, on the thread Flutter's UI
  runs on. A watcher that is present but slow to answer freezes the app
  right after sign-in. Wanted from cnativeapi: the asynchronous call, or
  registration off the UI thread. Meanwhile: none; a missing watcher
  answers at once and a slow one is rare.

- `[in-repo]` **A touch never holds the browser menu off before a
  sheet appears.** `WaxSecondaryTapRegion` is pointer-driven, and
  Flutter's mouse tracker raises enter and exit for mouse and stylus
  only. The window that matters is covered from the other side -
  `waxWithoutBrowserMenu` holds it across every menu route and option
  sheet, whatever opened it - which leaves only the long press itself,
  before the menu appears. On a canvas-drawn card no browser has much to
  offer there, so this is recorded rather than fixed: closing it means
  raising the hold on a touch pointer-down and releasing it on up, and a
  `Listener` per row on every platform is a poor trade for a menu that
  may never render.

- `[in-repo]` **A shell message raised from a public route is
  dropped.** `ShellMessageHost` (`shell_messages.dart`) draws
  `shellMessengerProvider` and is mounted in the signed-in scope
  (`router.dart`), so a message raised from login, setup, or any other
  public route reaches the notifier and is never drawn. Unreachable
  today: every raiser in the app is a signed-in screen, and
  `shell_messages_test.dart` covers the positions that occur (an
  ordinary screen, the player pushed over it, a lone overlay). Closing
  it means mounting the host where the public routes are built too, and
  checking that each public page has a Scaffold to present into. Worth
  doing when a public route first needs to say something, not before.

- `[in-repo]` **The rule editor does not say which fields can never
  reach `.nsp`.** An export's report names every loss after the fact;
  WaxBin's `playlist.NSPExportableFields()` lists the query fields that
  have an `.nsp` name at all, alias spellings included, which is enough
  to grey a field in the editor before it is picked. Not adopted: a
  field on the list can still be lost for its operator or value, which
  only the export report answers.

- `[in-repo]` **A platform call that never answers wedges the player
  until restart.** `JustAudioEngine` bounds loads, window edits, and a
  replay, and a load stuck behind a held edit reports the transport, but
  just_audio runs every playlist call in turn under one lock (media_kit
  adds its own on mpv), so one call that never returns holds every later
  load there for good. Recovering means building a new `AudioPlayer`,
  which a final `_player`, and the stream subscriptions every consumer
  holds on it, rule out today. The port's own `seek`, `pause`, `stop`, and `dispose`
  are still unbounded, so on such a player the seek a session's replay
  starts with waits forever before the bounded replay is reached.

- `[in-repo]` **Preferences have no offline copy.** A change made offline
  waits in the outbox and is laid over every read, but a launch with no
  server cannot read the document at all, so preference surfaces draw
  their defaults and a change waits for the first read. A mirror of the
  document beside the outbox would close it.

- `[in-repo]` **A persistent server error on an outbox entry makes the
  sync socket flap.** Reconcile drops the channel on any failure but a
  401, and the backoff resets on every successful connect, so an entry
  the server keeps answering with a 5xx reconnects the engine about every
  second for as long as it keeps failing. Whether such an entry should
  drop the socket at all, or be parked and retried on its own clock, is
  the open question.

- `[in-repo]` **The play-state mirror belongs to the server, not the
  account.** Signing out keeps `mirror_play_states`; only forgetting the
  server wipes it. The next account to sign in on the device reads the
  last one's play states offline, and its re-mint refreshes only
  downloaded items. Queued writes are keyed to their account and wait for
  it (one queued while signed out goes with whoever flushes next).
  The rest is a decision: drop the mirror at sign-out, or key its rows to
  the account the way the queue is.

- `[in-repo]` **The enrichment source set has never been reviewed as a
  set.** Operators order and switch the providers now, the catalog's
  built-ins among them, but the confidence numbers (Deezer 0.7, and
  friends) were picked one at a time and never compared, nothing says
  which provider a self-hoster with no keys ends up on, and iTunes sits
  awkwardly: its terms restrict artwork use to promoting store content,
  and it shares a per-IP budget with the radio path if both ever ask it.
  Radio's cover chain (`CoverChain` in
  `server/internal/providers/coverart.go`) deliberately does not follow
  the operator's order: it is built once at boot, Deezer first for speed
  and the archive behind it for coverage and licensing.

- `[hardware]` **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- `[in-repo]` **An artist screen has no biography.** "Appears on" landed
  on the `credit-artist` browse dimension. The biography still needs an
  enrichment field nothing writes yet: artist art filled the pictures
  half of that gap, but no provider supplies prose and no catalog field
  holds it, so this stays sequenced behind that rather than behind a
  query.
- `[in-repo]` **The downloads manager reports what WaxDeck holds and not
  what the device has left.** The storage header adds up used bytes by
  medium, which is the half a listener can act on; the layout also asks
  for device free space beside it, and that half is cut rather than faked.
  Nothing in Dart's own libraries answers how much room a volume has left:
  `dart:io` has no `statvfs`, there is no `df` on Windows, and shelling
  out on Android is at the mercy of SELinux policy, so the subprocess
  route is broken exactly where downloads live. What it
  wants is a plugin behind a WaxDeck-owned port per the wrapping rule,
  which is a pinned dependency and a decision of its own for one number.
  Worth taking with the next plugin that lands for another reason.
- `[in-repo]` **The web perf gate's measurement run is still owed.** Parked
  for the larger UI and UX overhaul rather than spot-fixed, and the code
  the run needs has now landed: the corpus writes one directory per album
  with its own synthesized cover (`corpusgen`, `-covers=false` for the
  comparison without art), the rAF collector and wheel loop are a
  reusable helper (`e2e/tests/support/scroll-pacing.ts`), and
  `perf-web.spec.ts` measures the music indexes, a bucket listing, and
  the tracks index with a track playing alongside the plain tracks-index
  scenario. What is left is running it and recording the numbers.

  **Still owed after the hardening phase, deliberately.** The phase that
  scheduled this is the one that flipped the URL strategy, swept the
  remnants, and recorded the bundle (`docs/releasing.md`); the run itself
  is a multi-hour manual job on a half-gigabyte corpus whose result is
  provisional while the skwasm force stands, which is the same reason it
  was split off in the first place. The miss policy below was named
  before the run so a red number is a decision rather than an argument,
  and it still stands.

  The scenarios moved with the shelf home: the landing wait is
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
  it just changed. The artwork pipeline already took the cheap
  levers - sized requests, bounded decodes, a day of client-side
  freshness - so a miss on the grid is a signal about the virtualized
  list rather than about artwork, and `-covers=false` is the run that
  tells the two apart.

- `[in-repo]` **How far ahead the artwork precacher warms is a guess.**
  The music listing and the music indexes call it when a scroll stops,
  naming the two viewports past the one on screen. Two viewports and "when the scroll stops" are
  the numbers the entry that wired this deliberately left for the perf
  run - one constant apiece (`_viewportsAhead`, the
  `ScrollEndNotification` gate) in `artwork_precache.dart`.

  Two things the run should weigh first, both about web. A warm is
  only plainly cheap where there is a cache of our own to fill: on web
  the cache is the browser's, the only way to fill it is a real request
  through dio into the Dart heap, and that request shares a connection
  pool and a main isolate with the media element. And the web warm asks
  the server a slightly different question than the draw does: the warm
  requests `size=artworkRung(px)` and the draw `size=artworkDrawSize(px)`.
  The server answers both from the same rung, but a browser caches by
  URL, and the two strings differ wherever the draw step is not itself a
  rung - a row's 40 points at pixel ratio 2 is 80, drawing at 96 and
  warming at 128 - so on such a display the warm fills a cache entry the
  row never reads. A note here once blamed a
  `web-gapless.spec.ts` failure on the web warm and switched it off; the
  failure was the sidecar's FLAC init segment declaring the wrong depth,
  since fixed upstream, which the precacher had nothing to do with. The
  switch is gone and the claim is withdrawn. Take it with the
  perf-measurement entry above.
- `[in-repo]` **The web build skips tracks the browser cannot decode.**
  Monkey's Audio, WavPack, WMA and Musepack stream as the file is, and a
  browser refuses them (media error 4), so the queue skips each one as a
  failed start. Play-info's `maxBitrateKbps` is not enough: it re-encodes
  only a lossless source (APE, WavPack, WMA Lossless) or a lossy one above
  the cap, so a 128 kbps WMA or a Musepack file would still stream as-is.
  The fix is for the client to say which formats it can decode (from
  `canPlayType`) and the server to encode the rest, counted against the
  caller's transcode limits.
- `[third-party]` **On Android a swipe that starts on selectable text
  selects it rather than changing tab.** Flutter's `SelectionArea` takes
  a horizontal touch drag as its own on Android (it waits for other
  gestures only on iOS) and exposes no way to change that, so on the
  admin users screen, the one swipeable `TabBarView`, a swipe begun on
  an empty state's words stays put. The tab bar still switches, and so
  does a swipe begun off the text. Fixing it means forwarding the drag
  to the enclosing scrollable from inside `WaxProse`, or a framework
  option to make the area wait.
- `[third-party]` **Every selectable area on desktop web mounts a
  context-menu view nothing uses.** Flutter's `SelectableRegion` puts a
  platform view over its text for the browser's own menu whenever that
  menu is on, and in this app the semantics tree sits over it, so it
  never gets a right-click; `WaxProse` raises its own menu instead. Each
  help line on a page is one more DOM element, layer and focus node (the
  focus node is kept out of Tab order). On Android each area likewise
  asks the platform for its text actions once as it mounts. Wanted from
  Flutter: a way to build an area without either.
- `[third-party]` **The web engine drops a node's e2e handle when the
  node changes role.** Flutter's web semantics builds a new element
  when a node's role changes - a control gaining or losing its adjust
  or tap actions - and re-applies only the fields that changed in that
  update, so the new element has no `flt-semantics-identifier` and a
  screen reader loses its place. The deck seek bar did it on every
  track load; `WaxSeekBar` now keeps its steps while it has no length,
  disabled and inert, so it never changes role. Any other identified
  control whose actions come and go loses its handle the same way.
  Wanted from Flutter: re-apply every field when a role is swapped.
- `[in-repo]` **Help under a Material `TextField` cannot be selected.**
  `WaxProse` makes the design system's help selectable, the
  `WaxTextField` helper line included, but a field built on Material's
  `TextField` draws `InputDecoration.helperText` inside the field's own
  gesture detector, where it stays inert. Sixteen fields: in
  `settings/integrations_sections.dart` the ListenBrainz token and API
  URL, the Last.fm key and secret, the Discord application id, the app
  password label, and the two notification fields; the timezone field in
  `settings/listening_sections.dart`; the invite note and expiry days in
  `admin/users_screen.dart`; the source server URL in
  `admin/migrate_screen.dart`; sign-up's invite code; and the include,
  exclude and retention fields in
  `podcasts/subscription_settings_sheet.dart`. Moving each onto
  `WaxTextField` is the fix.

## Connect and casting


## Curation and metadata

- `[in-repo]` **The MusicBrainz and Cover Art Archive base overrides
  stop short of enrichment.** `WAXDECK_MUSICBRAINZ_BASE` and
  `WAXDECK_COVERART_BASE` reach matching and radio artwork (the Cover
  Art Archive one radio artwork only), while the catalog's enrichment
  pass always asks the public services:
  `library.go` never hands WaxBin `MusicBrainzBaseURL` or
  `CoverArtBaseURL`. The wiring is a few lines, but the pass's
  private-address guard refuses a mirror on a private address unless
  `WAXDECK_ALLOW_PRIVATE_FEED_HOSTS` is on, so it wants a decision on
  whether a configured mirror is exempt.

## Localization

- `[in-repo]` **RTL is uncertified.** It rides the first Arabic or
  Hebrew locale. The design system is Directional-swept and the faces
  ship, but app code converted only what the sweep touched and nothing
  ratchets the rest - `EdgeInsets.only(left:/right:)` is still legal in
  an app screen - so an RTL locale wants a directional sweep of app
  code and a mirrored-layout pass before it ships.
- `[in-repo]` **Weblate is not onboarded.** ARB is what Weblate
  consumes, which is the GPL/F-Droid path to community locales. Two
  components, app and design system, sharing a vocabulary that only
  tests hold together (`durationHours` parity, the select-arm walk), so
  onboarding configures both or the tests catch the drift. The es
  corpus arrives bulk-marked needs-native-review through
  `@@x-machine-translated`. No service-side configuration exists in the
  repo yet.
- `[in-repo]` **Outbound notification prose leaves the app in
  English.** Titles and bodies are composed in Go ("Backup failed";
  "Backup completed" with its size and duration,
  `server/internal/service/backups.go`) and delivered through
  `EmitServerNotification` to ntfy, Discord, and webhooks - read
  outside the app, where no client table can follow. If it ever
  localizes it is server-side, and the reader is known: a delivery
  target belongs to an account, and accounts carry `Prefs.locale`, so
  the emitting path could word each delivery for its recipient -
  though one instance-wide notification locale is probably the honest
  size of the feature. Waits for someone to ask; recorded so the asker
  is not told it is a client gap.

## Infrastructure

- `[in-repo]` **A library cannot be removed.** Neither the console, the
  API nor the `waxbin` CLI has a verb for it, so a library added by
  mistake, or one a configured root now overlaps (which then boots left
  out with a warning), stays until the catalog is reset. Removal needs
  the catalog to drop the root and its items, WaxDeck to forget its
  stored name, and the streaming bridge to unmount it.
- `[in-repo]` **A live catalog restore leaves server rows naming the old
  catalog's pids.** Podcast subscriptions and feed state keep shows the
  restored catalog may lack, so the feed refresh keeps asking the
  catalog for them; health rows wait for the next sweep. Reconciling
  them at the replacement (dropping what the new catalog lacks, after
  telling each subscriber) is the fix.

- `[in-repo]` **The Android build turns Kotlin's incremental compiler
  off on Windows, and should stop having to.** Kotlin 2.3.20 opens a
  cache file it already holds open while closing it, and every module
  with Kotlin in it fails to compile: "Could not close incremental
  caches ... Storage for class-fq-name-to-source.tab is already
  registered". It reproduces from an empty build directory, so cleaning
  is no answer, and it is the platform rather than the project - the
  Linux runners that build the shipped APKs do the same from-scratch
  compile with incremental on and are green. `android/settings.gradle.kts`
  sets `kotlin.incremental=false` for Windows hosts only, and yields to
  an explicit `-Pkotlin.incremental`. Retire it at the next Kotlin bump
  that fixes the cache double-registration: delete the block, build an
  APK on Windows, and if it survives the flag is no longer needed. The
  Kotlin version it is pinned against sits ten lines above it in the
  same file.

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
- `[in-repo]` **`make test-app-chrome` cannot run on Windows.**
  flutter_tools' own test server answers every CanvasKit request with a
  404: `_localCanvasKitHandler` gates on
  `path.fromUri(request.url).startsWith('canvaskit/')`, and `fromUri`
  hands back backslashes on Windows. The web engine never boots and the
  suite never connects - a bare `flutter create` project fails the same
  way, so there is nothing in this repo to fix and no workaround short
  of patching the SDK. CI runs the browser suites on Linux, which is
  where they ratchet; the Makefile target carries the same note. Worth
  filing upstream (`path.posix.fromUri` is the one-line fix) if it is
  still there on the next Flutter bump. `--platform chrome` is itself
  deprecated: 3.44 hides the option and marks it as for testing the
  framework, removable at any time. It is still the only backend that
  runs an `@TestOn('browser')` suite, and `-d chrome` is not the
  replacement - `flutter test -d` applies to `package:integration_test`
  alone, which rejects web devices outright. If the flag does go, these
  two suites move to `flutter drive` plus chromedriver, or into the
  Playwright suite under `e2e/`.

## Discovery and stats

- `[in-repo]` **The web build has no downloads of its own to announce.**
  The bell now reports what this device finished transferring
  (`NotificationKind.download`), which the web build can never produce:
  it has no local download manager at all, so there is no transfer of
  its own whose completion it could announce. Not a platform-notification
  limitation and not a missing API - what is missing is the download
  manager. Recorded here so the next
  reader does not go looking for a notification API to fix it with.
  Server-side enclosure fetches are a different event and do reach every
  platform, through the `episode-downloaded` marker on the user stream.
- `[in-repo]` **Time and mood mixes.** Daylist-style rotating mixes
  with scheduled auto-names are a scheduler and a naming table over
  the instant-mix engine that shipped; nothing else blocks them.
- `[in-repo]` **A has-art signal on `FacetBucket`.** Kept for the
  reasoning, because the next agent tempted by a `hasArt` field needs
  the probe rulings below. The situation it was sequenced on has
  arrived: artist-level art is written now - by the catalog's
  enrichment pass for a matched artist and by the name-matched sweep
  for the rest - the artists index asks per row like the album one, and
  the misses land in
  `ArtworkStore`'s negative cache - asked once, drawn as a monogram
  from then on. What a contract field would still buy is trimming the
  first-session 404 per artless artist, which the negative cache
  already bounds, so it stays not worth the spec surface unless facet
  pages measurably suffer.

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

  **The negative cache's own limit, for whoever touches it next.** It is
  cleared by a catalog invalidation, by a cover editor's `evict`, and by
  sign-out. Nothing else - so a cover that appears while the app is open
  and the sync channel is down stays a monogram until the channel
  reconnects and invalidates. That is the same window every other cached
  view has, and it closes the same way.
- `[in-repo]` **Clip cards for episode shares are not built.** The
  year-in-review cards render, export, and now draw their top artists'
  covers. A clip card is the same shape of
  work for a different subject - a quotable span of an episode, cut to
  the same two canvases - and none of it exists: no span picker, no
  card, no export entry. The artwork half is solved and reusable
  (pre-fetch and decode before the one frame is captured, monogram
  where a cover is missing), which is what makes this a card to draw
  rather than a pipeline to design.
- `[hardware]` **The Android share path for a card is unverified.**
  Exporting a card on Android writes it into a FileProvider-scoped
  cache directory and opens `ACTION_SEND` over the `waxdeck/share`
  channel. There is no device here and no Android build
  in CI, so the Kotlin handler, the manifest `<provider>`, and the
  `res/xml/file_paths.xml` scope have never run. What to check: the
  chooser opens, the receiving app can read the image (a wrong
  authority or an unscoped path fails here), the temp-then-rename
  leaves no `.tmp` behind, and a second export of the same card
  replaces rather than duplicates.
