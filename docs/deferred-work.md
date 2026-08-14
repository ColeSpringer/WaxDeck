# Deferred work

The tracked list of WaxDeck work that was cut from an otherwise
shipped slice. Roadmap items that have simply not started yet do not
belong here, and deliberate v1 scope exclusions live in the roadmap;
this list is for the residuals that would otherwise
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
  (a phone, a head unit, real cast hardware). Docker used to be on that
  list and is not: it is available here, and `make up`, `make dist`, and
  `make goldens-linux` all depend on it.
- `[roadmap]` deliberately rides a named later slice; listed here
  only because the cut happened mid-slice and would otherwise read
  as forgotten.

Most of this list is `[in-repo]` by design: the working rule is that
a slice ships when its acceptance holds, and polish residuals get
written down instead of silently dropped or half-shipped. Very little
here waits on upstream.

## Playback and apps

- `[in-repo]` **Download-notification polish.** The
  minimum is wired: a running/complete/error notification named by the original
  file, a progress bar, and a once-per-process permission request at the
  first download. Three things the plugin offers were left out. A denied
  permission is taken at face value, where `shouldShowRationale` is what
  would let the app explain itself before asking a second time. And
  `trackTasks()` plus `rescheduleKilledTasks()` are what make a download
  survive the OS killing the app - without them a transfer interrupted
  that way is neither resumed nor reported, and the manager finds out
  only when the record it is holding never completes. That last pair is
  the substantial one; it wants a decision about who owns the plugin's
  own task database next to WaxDeck's `downloadRecords`, which is why it
  is not a follow-up line in the same file. The third is grouping: the
  notification is per file, so a twenty-part book posts twenty of them.
  `groupNotificationId` collapses a batch into one row, but it also
  replaces the file name with a count, and one file is what most
  downloads are - so the answer is a group per item rather than a global
  one, which means carrying a group on `TransferRequest` and configuring
  the notification per group as items start.
- `[hardware]` **Android UnifiedPush distributor integration.** The server, API,
  and settings surface shipped; the client still needs the
  distributor plugin wrapped behind a WaxDeck-owned interface and a
  real device to verify against. Blocked on hardware access.
- `[in-repo]` **An artist screen has no biography.** "Appears on" landed
  on the `credit-artist` browse dimension. The biography still needs an
  enrichment field nothing writes yet - the same provider gap that keeps
  artist artwork from existing - so it stays sequenced behind that
  rather than behind a query.
- `[in-repo]` **A browse sort this client predates is erased by the
  next preference write.** `Prefs.browseSorts` values are a closed enum
  in the spec, so an order only a newer server knows deserializes to
  the generated sentinel. `prefsFromGen` drops that entry rather than
  let the sentinel's wire value fail every save, and because the PUT
  replaces the whole document, the next write of any preference -
  theme, autoplay, crossfade - takes that dimension's stored order off
  the server too. No client-side fix reaches it: the original string is
  gone before the mapping layer sees it. The fix is the contract, and
  it is small - make the values free strings, the way `Error.code` and
  `Share.targetKind` already are for the same reason, which removes the
  sentinel from this field and makes the round-trip preservation
  `Prefs.browseSorts` documents actually true. Worth taking with the
  next change to the sort vocabulary rather than on its own.
- `[in-repo]` **A place cannot be marked offline.** Audiobook bookmarks
  are a live read against the server: the sheet fetches on
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

- `[in-repo]` **Discord presence shows the application's own cover, not
  the album's.** Presence shipped in P22 with the status,
  the track, the artist, the album, and the timestamps that drive the
  progress bar; the image beside them is the `waxdeck` art
  asset uploaded against the Discord application (the emblem, since
  the official mark landed), the same for every track. The two richer sources
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
  so the refusal carries `params` (`feature: multi-part-audiobook`
  plus the `pid`) as the machine key a picker reads -
  `multiPartRefusal` in `server/internal/api/player.go`, `_explain`
  in `app/app/lib/src/connect/device_picker.dart` (still matching the
  message's phrase, which stays as the fallback for a server older
  than params), and `TestMultiPartRefusalWording` holding both
  channels together. A `cmd-result` from a client endpoint carries no
  params by decision: its codes are whitelisted before they reach the
  wire and an arbitrary map would need the same treatment designed
  for it. The other refusals under `feature-unavailable` - queue
  timelines, sonic paths, the file tools, the share surface, every
  service `KindFeature` - carry no params either; the spec calls them
  best-effort per refusal for that reason, and each gains a `feature`
  value when something needs to tell it apart.
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
- `[in-repo]` **The Subsonic index is rebuilt per request for
  library-restricted accounts.** The grouped index every browse and
  `search3` ride is cached tail-keyed for full-visibility callers and
  rebuilt from a whole-catalog `TrackFacts` sweep for anyone holding
  library grants - and a real client pages hard: Feishin discovers its
  track count by walking `search3` at rising offsets, so a restricted
  account on a 50k-track library pays a full sweep per page of a walk
  that takes dozens of pages. The fix shape is a second cache keyed on
  the catalog tail plus the caller's grant set, invalidated exactly as
  the shared one is; not taken yet because the sweep is honest, just
  repeated, and the compatibility surface's heavy users today are
  single-account instances.

## Localization

- `[in-repo]` **The app is not localized, and the language picker the
  layout blueprint specifies waits on it.** The plumbing is done and the
  sweep is not. `flutter_localizations` and `intl` are in both pubspecs,
  `l10n.yaml` and ARBs exist for `app/app` and for the design system, and
  `make generate` mints both tables under drift-check. `Prefs.locale`
  (a BCP 47 tag, `api/spec/users.yaml`) is read now: the app resolves
  system-first with the preference as the override. What is left is the
  screens - around 1,200 user-facing string literals in `app/app/lib`,
  which the `hardcoded-copy` ratchet counts per file so a sweep slice
  cannot stall half-done, and the count is an undercount because the help
  lines are multi-line concatenations a grep reads as several. Three
  things the plumbing half already answered, recorded because the
  original entry guessed otherwise: the design system needed an ARB of
  its own after all (its components carry ~80 strings no caller can pass
  in, so `WaxLocalizations` is a package-owned delegate on the
  `MaterialLocalizations` pattern); the formatting is done, with
  `format_bytes.dart` and every padLeft date helper folded into
  `WaxFormats` and the durations into `WaxLocalizations`; and the picker
  is what still waits, on the same reasoning as before:
  extraction is code and finishes, translation is people and does not,
  so a picker offered before there is a second language to pick is an
  empty control. ARB is what Weblate consumes, which is how a GPL
  project bound for F-Droid gets its second language. Already paid for
  or cheap: the e2e suite drives semantics identifiers, not visible
  labels, so translations cannot break it; the CI goldens block text
  out and the readable Linux ones render the default locale, so en
  stays the golden locale; a CJK UI locale needs `ensureScript` at
  startup for its own script, because the fonts warmup interceptor
  only sees text arriving in API responses and a static UI string
  never does (the owned-set mechanism the fonts paragraph under
  Decided records); and an Arabic or Hebrew UI locale would add a
  left/right-to-Directional sweep, with the faces themselves already
  shipped for content. Worth taking when somebody is ready to own the
  translations, not before.
- `[in-repo]` **Error surfaces speak the server's English.** The
  contract splits the roles - `code` is the stable machine value,
  `message` is "not stable, do not parse" (`api/spec/_shared.yaml`) -
  and the app inverts them: a couple hundred `.message` reads render
  the server's sentence verbatim (`SnackBar(content: Text(e.message))`
  is the dominant shape, the inline `AsyncValue.error` widgets the
  rest), and `code` picks words nowhere - its five uses are control
  flow. Localizing errors means moving the boundary to the code: a
  client table from the spec's code enum to localized sentences, with
  the server `message` kept as the fallback for a code the table does
  not know. The server never localizes - no Accept-Language on the
  API, messages stay developer English for the logs - which is what
  keeps the backend out of the translation business permanently. Two
  traps to take deliberately. Where one code covers many causes, a
  generic per-code sentence loses the specifics: `feature-unavailable`
  is the umbrella code, and the device picker tells the multi-part
  refusal apart by phrase-matching the message. The table exists
  now (`app/app/lib/src/l10n/explain_error.dart`: one sentence per code
  in both locales, guarded by a test that reads the code list out of the
  committed bundle rather than out of a second copy of it), the three
  transport codes `waxdeck_api` mints are worded there beside the
  server's, and the device picker keys the multi-part refusal on the
  `params` the schema now carries, with the phrase match demoted to the
  old-server fallback. What remains is adoption: `Text(e.message)` at
  some 45 snackbar sites, the `AsyncError` branches, and the
  `ErrorState` uses all still draw the server's sentence, and each
  screen slice converts its own as it is swept. Two things that adoption
  has to take with it. The app mints `internal` for three of its own
  local failures (`connect_bus.dart` :53's default,
  `connect_controller.dart` :344, `queue_gateway.dart` :272), and the
  table words that code as a server fault, so a listener whose seek
  failed on their own device would be told to report a server bug; those
  want client codes of their own, the way the transport mints got them,
  before any of those three surfaces adopts `context.explain`. And the
  socket's error frames carry `params` server-side while
  `connect_bus.dart`'s error arm reads only `code` and `message`, so the
  same refusal keeps its machine key over REST and loses it over the
  socket - the bus adopts it the way the picker just did.
- `[in-repo]` **A notification event a newer server adds draws its wire
  token as a heading.** The client maps the seven event names to titles
  and help of its own (`app/app/lib/src/settings/notify_labels.dart`),
  falling back to the server's description for help and to the raw token
  for the title, because the catalogue the server sends carries no title
  at all. The error codes and the health rules both have a completeness
  test that reads the vocabulary out of `api/openapi.yaml` and fails when
  the client has no arm for one; the events cannot have the same test,
  because the spec names only an example (`api/spec/notifications.yaml`)
  while the set itself lives in Go (`service/notify.go`'s catalogue). The
  fix is prose, not schema: enumerate the event names in the endpoint's
  description the way the health rules already are, then slice it the way
  `error_table_test.dart` slices the codes. Worth taking with the next
  event that lands, which is when the gap first costs something.
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
- `[upstream]` **Name ordering is ASCII-folded codepoint order.**
  Browse and the indexes ride WaxBin's stored `sort_key`, and
  `model.SortKey` says exactly what that is: lowercased,
  article-stripped, digit-padded, compared BINARY - "ASCII-level
  folding" by its own comment, with "Unicode collation can be added
  here without changing callers or the stored column" as the standing
  invitation. So "Édith" sorts after "z", and every non-Latin name
  sorts by codepoint: stable and grouped, wrong for any library that
  is not English. The ask lives in upstream-requests.md - Unicode
  folding in `SortKey`, locale-independent only, since a stored column
  is one ordering for everyone. What WaxDeck inherits when it lands:
  stored keys need recomputing (WaxBin's `sortKeyDrift` verifier
  already counts stale ones, so detection exists), and a keyset cursor
  minted across the upgrade walks the rest of its pages in the old
  order - bounded, worth knowing, not worth machinery.

- `[in-repo]` **The surfaces drawn from outside the element tree stay
  English.** Four of them, and they are one problem: the Android Auto
  browse tree's folder names (`auto/auto_browse.dart`), the desktop
  tray menu (`desktop/desktop_ports_io.dart`), the sleep timer's
  media-session extend button (`player/sleep_timer.dart`), and the
  notification-channel names and media-session action labels configured
  at engine init in `waxdeck_player`. Every one is built where there is
  no `BuildContext` to read a locale through - a port fed a database, a
  notifier, an operating-system menu - so `context.l10n` cannot reach
  them and the sweep left them as they are, with a comment at each site
  saying so. The fix is one mechanism rather than four: resolve
  `AppLocalizations` for the current locale into a provider (the
  delegate can `load` a locale off the tree), hand it to each port at
  construction, and re-hand it when the picker changes the locale.
  Worth doing with the first of them that somebody actually reads in
  another language; until then it is a table nobody consults.

## Infrastructure

- `[upstream]` **Six Go tests are red on a Windows dev box.** Book
  merge, book split, cue split, metadata write-back and the import
  failure case in `internal/api`, plus provenance stamping in
  `internal/waxtapsource`, all fail with "rename ... Access is denied".
  One cause, recorded in `upstream-requests.md`: WaxLabel's `saveBack`
  holds the source open across its own atomic rename, which Windows
  refuses. Nothing to do in this repo - the handle is internal to it -
  so `make test` stays red on Windows until that lands. Linux CI is
  unaffected, and no shipped target writes tags on Windows.

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
  meanwhile.
- `[in-repo]` **Android folder picking is excluded from the upload
  surface.** File picking works on every platform (the endorsed
  `file_selector_android` implementation covers in-app file picks),
  but Android folder access means SAF tree URIs, which the
  `FilePickerPort` deliberately does not speak; the "Upload a folder"
  tile hides there (`canPickFolders`). Multi-select plus auto
  grouping covers the album case on Android meanwhile.
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
  keyed by playlist pid): (1) the binding row (source type, source ref,
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
  1/3/6/12/24 hours plus a manual sync-now; the scheduler
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
  slots this needs are in place as of the playlists rebuild:
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
  manager. Recorded here so the next
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

## Admin and ops

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
  The account-wide switch ships (`Prefs.radioScrobbleOptOut`),
  which covers the listener who wants none of it. What the original entry
  also floated is a per-station flag, for the household that scrobbles
  its music stations and not its talk ones. That wants a per-user
  per-station bit, and the only per-user station state that exists is the
  favourites list; whoever adds a second one should decide whether they
  share a shape.

## Decided, not deferred

The macOS desktop and iOS targets are dropped, not deferred. Desktop
is Linux and Windows, mobile is Android, and a Mac or an iPhone
reaches WaxDeck through the web app the server already serves - or any
Subsonic client. What rode on the platform went with it: the DMG
packaging and its volume icon, the Homebrew cask, and the sandboxed
keychain question, which was answered before the drop and is worth
keeping: an unsigned sandboxed build cannot use the data-protection
keychain at all (`SecItemAdd` answers `errSecMissingEntitlement`, the
store swallows it by design, and every launch asks for a password
again), and the workaround that did work pinned the credential to the
exact binary, so a rebuild raised an authorization dialog. Fixing it
meant a developer certificate, which was never going to be bought.
One engine consequence, and it is a simplification: both shipped
desktops now route through media_kit/mpv, so the desktop conformance
suite holds one engine to the port contract instead of two.

Every browse validates the caller's pid, and that is a behaviour
change WaxDeck accepted rather than work it postponed. waxbin's
`browseFilter` short-circuits only when a query has neither an entity
nor a where clause, and a built query never is, so
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

The owned font set grows one face at a time, and that is the mechanism
rather than a stopgap. It now covers Latin, Greek, Cyrillic, Arabic,
Hebrew, Thai and CJK eagerly-or-on-demand as before, plus fifteen more
scripts (Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, Telugu,
Kannada, Malayalam, Sinhala, Khmer, Lao, Myanmar, Georgian, Armenian,
Ethiopic) and a colour emoji face, all deferred: about 34 MB of assets
that cost a startup nothing, because a library reaches for one only when
a title is written in that script. The engine's own CDN fallback stays
pointed at an unrouted same-origin path, so an instance still behaves
identically with and without internet. What is deliberately absent -
Oriya, Tibetan, and the rest - waits for the same evidence the fifteen
had: a real library that would otherwise render boxes. Adding one is a
row in `tools/fetch-fonts.sh`, a `WaxScript` value, and a detection
range, which is the whole of it.

The live fan-out's worst edge is closed, and the two that remain are
accepted rather than owed. The fan-out defers around in-flight first
builds through a `ProviderObserver` ledger, and the edge that mattered
was a first build that never landed at all: with no transport deadline
anywhere, a hung request kept its topic's retry timer re-arming every
window for the life of the session. Every transport now has one - the
API client 10s to connect and 30s between response chunks, artwork
10s/15s, the sync socket 10s to finish its upgrade and a 30s ping after
that - so a request that hangs ends as a `timeout`, and an error is a
landing the ledger prunes exactly as a value is. Two edges are left,
both bounded and neither worth machinery. A watched instance invalidated
mid-first-build from outside the fan-out rebuilds into a bare loading
the notification gate suppresses, so that one instance rides plain
pacing until a differing state lands, which is the pre-deferral
behaviour and not a new failure. And a nested `ProviderScope` overriding
a fan-out target would sit outside `allProviders`' enumeration (children
are excluded), unreachable by sweep and retry alike, as it already was
by the plain invalidations before the pacer; no such scope exists, and
whoever introduces one takes the fan-out's enumeration with it.

Cross-origin access is opt-in and stays that way. A browser client
served from somewhere else - a self-hosted Feishin, which CI now drives
against the stack - cannot call a server that does not name its origin,
so `WAXDECK_CORS_ORIGINS` names them: exact origins only, no wildcard
and no pattern, never with credentials (the compatibility surfaces carry
their own app-password auth, so nothing needs the cookie), applied to
the whole mux with the preflight answered before the router. Empty by
default, which is every deployment that just uses the bundled web app,
and an unconfigured server behaves exactly as it did. There is nothing
left to build here; a deployment that wants a browser client sets the
variable.

Signup spends its rate-limit budget on success as well as failure, and
that is the anti-abuse decision rather than a missing `Success` call.
`signup.go` says so where it happens: "account creation is the expensive
outcome. A NAT'd household admitting a handful of members stays under
the threshold; a script farming accounts does not." What made it read as
a bug was the shared key - behind a reverse proxy every signup counted
against the proxy's address, so the cap was server-wide - and
`WAXDECK_TRUSTED_PROXIES` is the whole of that fix. With
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

Declining identification imports with no stop, and the review queue is
not the record that makes that safe - the entry is. The open question
this list used to carry, whether a submission that says "leave my tags
alone" should still confirm once in review, is settled against
confirming: somebody who turned identification off has already said
what to do with the files, and asking again once per album is asking
twice. What lands is a review entry written `as-is` rather than
`pending`, so the import keeps the same record, the same undo, and the
same uploads-screen link a decided-by-hand one has. The stop survives
where it earns its keep: an import that refuses - a name collision, a
destination nothing may be written to - leaves the entry pending with
`identifyDeclined` on it, which is the only way one is ever seen.

Recorded so they are not re-read as gaps: gpodder episode delete
actions stay echo-only (a per-device client delete must not reclaim a
shared server file). Music has no first-class explicit boolean by
decision: no canonical source exists (MusicBrainz carries no explicit
flag), so files' own ITUNESADVISORY tags ride the custom-tag surface
(queryable, facetable, hand-settable, lockable) and enforcement is
the deny-list mechanism, not a per-track flag. Audiobooks have no
explicit convention anywhere; custom tags cover anyone who wants one.
Scope-level non-goals and accepted risks live in the roadmap's
post-v1 section.

What stays English is chosen, not overlooked. The Subsonic and
gpodder adapters answer third-party clients in protocol strings and
localize nothing. The API `Error.message` stays developer English
everywhere - the localization boundary is the `code`, per the
Localization entries - and so does the diagnostic prose on the admin
surfaces: a failed task's `error`, a job's progress note, a
migration's cautions. Translating diagnostics trades grep-ability
for polish on the one surface whose reader wants the grep.
