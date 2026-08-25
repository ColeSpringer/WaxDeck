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


- `[in-repo]` **Riverpod 3's automatic retry is unaudited across the
  app.** A provider that throws anything which is not an `Error` is
  re-run ten times over about thirteen seconds, and between attempts it
  reports `AsyncLoading` carrying the previous error - so `.future`
  does not settle until the backoff is exhausted. Right for a dropped
  connection, wrong for a refusal, and sharp for the nine places that
  `await` a provider's `.future` (`auth_controller`, `prefs_controller`,
  `account_sections`, `autoplay_gate`, `home_shelves`,
  `downloads_controller`, `add_to_library`, `diagnostics_screen`): each
  hangs for the whole backoff where it used to throw at once. Two
  providers already answer it locally and differently -
  `album_detail.dart`'s private `_retryUnlessRefused` (4xx is final,
  everything else keeps the default) and `trackWaveformProvider`'s flat
  `retry: (_, _) => null` - which is the shape of the fix: promote the
  predicate somewhere shared, then decide per provider whether a
  failure is final. Recorded rather than swept because the decision is
  per provider and there is no default that is right for all of them.
  The rule for new code is in CLAUDE.md.

- `[in-repo]` **Some content rows and tiles still have no menu to
  answer a secondary tap with.** Most item rows got theirs: album and
  playlist track rows, queue rows, search track and episode hits, the
  music listing rows, and home's item shelves open the shared item menu
  (`library/item_menu.dart`); home's episode cards open their own sheet
  (play, info, edit); search's album hits and the album index buckets
  open the release sheet, and artist and book hits and artist buckets
  keep the pin sheet. The door is a kebab or hover chip, a right click,
  or - where the surface has not spent it on multi-select - a long
  press (`MediaListRow` gives a wired `onLongPress` precedence over
  `onMore`, which is what lets the queue keep hold-to-select beside the
  menu). Still menu-less: book, podcast, and playlist tiles, home's mix
  shelf, the artist screen's top-track rows, the computed track lists
  (an instant mix's, similar-tracks'), and a show's episode rows, which
  spend their long press on multi-select and would need the kebab
  route. A right click on any of those hands back the browser's menu;
  what each menu should hold is a design question per surface rather
  than a wiring change.

  A second gap in the same policy, narrower: `WaxSecondaryTapRegion` is
  pointer-driven, and Flutter's mouse tracker raises enter and exit for
  mouse and stylus only, so a touch never holds the browser menu off.
  The window that matters is covered from the other side -
  `waxWithoutBrowserMenu` holds it across the menu route, whatever
  opened it - which leaves only the long press itself, before the menu
  appears. On a canvas-drawn card no browser has much to offer there, so
  this is recorded rather than fixed: closing it properly means raising
  the hold on a touch pointer-down and releasing it on up, and a
  `Listener` per row on every platform is a poor trade for a menu that
  may never render.

- `[in-repo]` **The command palette re-reads a track's waveform on every
  open.** `trackWaveformProvider` is `autoDispose`, the palette is a
  `showDialog` (so it unmounts on close), and `_visualizable` reads the
  envelope above the needle filter to decide whether to offer the
  visualizer - so with the player face unmounted the palette is the only
  listener and each open pays for a fresh read. Nothing revalidates it:
  the generated client sends no `If-None-Match` and dio carries no
  cache, so this is a full re-download of the peaks rather than a 304,
  and for the unanalyzed track the gate exists for the server answers
  `Cache-Control: no-store` anyway. The obvious fix - a short
  `ref.keepAlive()` grace on the family - was tried and backed out: a
  kept-alive provider never reaches `onDispose`, so its timer outlives
  the widget tree and fifteen widget tests fail on a pending timer.
  Doing it properly means a cache link the test binding can retire, or
  moving the gate off the envelope entirely.

- `[in-repo]` **A shell message raised from outside the shell is
  dropped.** `_listenForMessages` (`adaptive_shell.dart`) is what draws
  `shellMessengerProvider`, and it lives inside `AdaptiveShell` - which
  is mounted only for the locations in `shellRoutes()`. A message raised
  from login, setup, or any other public route reaches the notifier and
  is never drawn. Unreachable today: every raiser in the app is a
  signed-in screen inside the shell, and `shell_messages_test.dart`
  covers the two positions that do occur (an ordinary screen, and the
  player pushed over it). Closing it means a listener above the router
  in `app.dart`, which drags the rest of the shape with it - the
  snackbar would then present into an app-level Scaffold rather than the
  screen's own, so FAB lift and per-screen bottom insets stop applying
  to it, and `PlayerScreen`'s compensating Scaffold and `DeckBarHost`
  both want checking against the move. Worth doing when a public route
  first needs to say something, not before.

- `[in-repo]` **An NSP export's loss list is not pinned to the rule it
  was computed from.** The report is asked at one moment and
  `partial=true` is applied to whatever the rule is when the person taps
  through the dialog. `exportableRule` resolves through `resolvePlaylist`
  rather than `resolveOwnedPlaylist`, so a shared smart playlist's owner
  can save a rule change while a second viewer holds the dialog open:
  the viewer accepts a list naming A and B and the export drops C and D.
  A rule hash on the report, echoed as `If-Match` on the export, would
  close it - and would let the export reuse the walk the report already
  did rather than paying for a second catalog read on the lossless path.

- `[in-repo]` **The NSP loss dialog shows what goes, not what stays.**
  `GET /playlists/{pid}/nsp/report` answers the gaps, and the dialog
  before a partial export lists them in the converter's own sentences.
  For somebody deciding whether to accept the loss, the more answerable
  question is the other one: what does the exported playlist actually
  select? `playlist.ExportNSPPartial` already returns that as
  `NSPExport.Rule`, in WaxDeck's own rule vocabulary, so the mechanism
  is a nullable `rule` on the report (running `ExportNSPPartial`
  alongside `CheckNSPExport`) plus a rule-tree rendering in the dialog
  through the `rule_vocabulary.dart` the rule editor already uses. That
  is a second, larger UI than "can I accept this loss?", which is why
  the loss list shipped first.

  The same rendering would close a smaller thing on the way: the
  converter writes its refusal sentences against the query engine's
  spelling, so a `mediaType` condition is refused for `kind`. The gap's
  `field` is translated back to WaxDeck's vocabulary and the dialog
  leads each row with that name, but the sentence under it still says
  `kind` - as does the strict refusal's 501 message, which has no row
  to lead with at all.

  One more thing waits on the same rendering: the dialog's forward
  button reads "Export without them", which is right for a gap and
  wrong for a note - a note is a loss the format makes either way and
  that a partial export does not drop. Unreachable today, because
  `ruleToQuery` always builds `query.EntityItems` and WaxBin's single
  export note fires on `EntityTracks`, so no WaxDeck rule can produce a
  notes-only report.

  Upstream has since shipped the coarse half of the same question:
  `playlist.NSPExportableFields()` lists every WaxBin query field that
  has an `.nsp` name at all, alias spellings included. It is not the
  rendering above - a field on the list can still be dropped for the
  operator or the value it carries, which is what `CheckNSPExport`
  answers - but it is enough to grey an unexportable field in the rule
  editor, or to say up front that a rule can never export. Deliberately
  not adopted with the alias fix; it is here so whoever builds the
  rendering knows it exists.

- `[in-repo]` **Preference writes have no offline outbox.** Play-state
  and entity-state writes queue through `OptimisticStateController`,
  which holds an intent while the network is gone and replays it;
  `PrefsController` publishes optimistically and serializes writes but
  has no such branch, so a pin, a crossfade, or a browse sort made
  offline is reverted when its PUT fails rather than sent when the
  connection returns. The two are close enough in shape that folding
  the document controller onto the same protocol looks obvious - the
  reason it has not been done is that the outbox is per-pid and keyed
  to one entity's state, while this is one whole-document singleton
  whose "intent" is a function over the document rather than a value.

- `[in-repo]` **Ten screens still switch on an `AsyncValue`'s runtime
  type.** `AsyncSliverFace` (`shell/`) is the shape that fixes it -
  failure, then whatever value is held, then the skeleton - and the
  three hubs, the home screen, and the review queue take it. The rest
  still read `AsyncData(...) => rows, AsyncError(...) => error, _ =>
  skeleton`, which a refresh matches nowhere: `playlists_screen`,
  `downloads_screen`, `books_screen`, `show_screen`, `playlist_screen`,
  `album_screen`, `artist_screen`, `uploads_screen`, and
  `tasks_screen`. Several watch fan-out providers, so a catalog or user
  event blanks them to a skeleton and back. Not swept in one change
  because each one has its own empty and error faces to carry across,
  and a mechanical conversion is how an empty state gets lost; the
  search screen is deliberately *not* on this list, because its
  providers watch the query and a value carried across a rebuild
  answers the previous one.

- `[in-repo]` **The hover play affordance is on the item shelves only.**
  `ArtworkImage` takes an `onPlay` and draws a scrim and a glyph under a
  pointer for whoever passes one, and the home shelves do: their cards
  are catalog items, so "play this" is one queue write with a source of
  `single` (or `book`). Every other grid is entity tiles - an album, a
  show, a station, a playlist - where the verb is a different one over a
  different read: playing an album means fetching its running order
  first, and a podcast tile has no single thing to play at all. Those
  call sites opt in when each verb is decided; the affordance costs
  nothing on touch either way, because a `MouseRegion` reports no hover
  to a finger.

- `[in-repo]` **Every injected enrichment provider is cover-only.**
  Deezer, iTunes and Fanart.tv all advertise `enrich.CapCover` and
  nothing else, and all three refuse anything but `TargetReleaseGroup`,
  so the Service only ever asks them for an album cover. Two things
  follow. **Their fields go unused**: a Deezer track carries an ISRC, a
  BPM, a duration, a track position, an explicit flag and a release
  date, and a Deezer album carries a label, genres and a UPC - and the
  port already has the slots, `Candidate.Fields` (documented as
  "reserved for injected providers") and `Candidate.Genres`. We fill
  neither, so MusicBrainz is the only field source by omission rather
  than by decision. **And the per-edition cover rung has no injected
  producer**: with `MatchReleases` on, `enrich.go` asks for
  `TargetRelease` art once an album is matched to a pressing, every
  injected provider declines, and the Cover Art Archive takes it
  uncontested - the source measured at 24-37s per lookup with no hit
  when radio was leaning on it. Declining is what the port asks of a
  provider that only knows groups, so the fix is not simply to answer:
  it is to decide whether a Deezer or iTunes album is close enough to a
  named edition to answer for it, and to say so.

  Not a gap: there is no track-level cover search, and there should not
  be. `CapCover` is defined as release-group cover-art bytes and a track
  draws its album's picture, so an album search is the right query for a
  catalog cover. Radio is the exception that proves it - it searches by
  track because a station announces a song and nothing else, and it
  wants the album carrying it.

- `[in-repo]` **The enrichment source set has never been designed as a
  set.** It grew one provider at a time - Deezer, iTunes, Audnexus,
  Fanart.tv behind a key, MusicBrainz and the Cover Art Archive through
  matching - and what exists is a list, not an order. Nothing states
  which source is authoritative for which field, what happens when two
  disagree, or which one a self-hoster gets when they have no keys; the
  confidence numbers (Deezer 0.7, and friends) were picked one at a time
  and have never been compared against each other. Radio's artwork rung
  now has an explicit chain with a stated order and a documented reason
  for it (`CoverChain` in `server/internal/providers/coverart.go`,
  Deezer first for speed, the archive behind it for coverage and
  licensing); enrichment has no equivalent. Worth a pass that decides
  the defaults, the fallbacks, and the per-field precedence, and that
  revisits whether the set is the right one - iTunes in particular sits
  awkwardly, since its terms restrict artwork use to promoting store
  content and it shares a per-IP budget with the radio path if both
  ever ask it. Also unanswered: whether an operator should be able to
  order or disable sources individually rather than through one
  all-or-nothing toggle per subsystem.

- `[in-repo]` **The radio artwork wake is broadcast, not addressed.**
  A cover landing marks the `radio` topic on every connection
  (`hub.MarkRadioAll`), because the hub holds no record of who is tuned
  to what: the guard is the client's `if (pid == null) return`. Station
  identity exists at every producing layer - `radioTitles` is keyed by
  station pid, `GetRadioPlayInfo` holds both the pid and the caller -
  and is thrown away on the way to the hub. The cost is a socket write
  for listeners it does not concern, plus a mobile radio wakeup, and it
  is worst for a station that mints a fresh announced-art key on every
  poll. Blunted at both ends for now (never woken on a miss; paced on
  the client through `PacedRefresh`), and the fix is a per-connection
  interest registry the socket layer does not have yet - the same one a
  future per-station or per-user topic would want.

- `[in-repo]` **The radio face's artwork shape follows a URL, not a
  picture.** The face draws a square with no platter ring when the
  server matched the announced title to a library item, and a circle
  with the ring otherwise (`radio_face.dart`, `onTheRecord`). It decides
  from `radioNowPlayingArtProvider` being non-null, which only says the
  server found a match - `integrations.go` sets `NowPlayingItemPid`
  without checking that the item has cover art. So a matched track with
  no art draws the station wordmark cropped square with no ring, losing
  the one ambient cue that the stream is live. The shape is chosen when
  the widget builds and whether the image exists is known a round trip
  later, so neither half is a local fix. Two ways out: gate
  `NowPlayingItemPid` server-side on the item having art, which matches
  what the field's own description says it is for and is a spec change;
  or make artwork absence observable, since `ArtworkStore.knownAbsent`
  already holds the answer but the store is not listenable, so a face
  reading it flips shape whenever the next title poll happens to rebuild
  rather than when the 404 lands. The second rung (`nowPlayingArtKey`)
  is unaffected - the server only sends a key when it has the bytes.
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
  enrichment field nothing writes yet: the artist portrait sweep filled
  the artwork half of that gap, but no provider supplies prose and no
  catalog field holds it, so this stays sequenced behind that rather
  than behind a query.
- `[in-repo]` **A browse sort this client predates is erased by the
  next preference write.** `Prefs.browseSorts` values are a closed enum
  in the spec, so an order only a newer server knows deserializes to
  the generated sentinel. `prefsFromGen` drops that entry rather than
  let the sentinel's wire value fail every save, and because the PUT
  replaces the whole document, the next write of any preference -
  locale, autoplay, crossfade - takes that dimension's stored order off
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
  the official mark landed), the same for every track. Of the two richer
  sources named when this was first recorded, one has since come within
  reach. **Cover Art Archive** was blocked on a MusicBrainz release id
  the catalog would not project; that upstream ask landed, `model.ItemView`
  now carries `MBID`, `AlbumMBID` and `ReleaseGroupMBID`, and the
  `missing-mbid` health rule already reads the first of them
  (`server/internal/service/health.go`). What is left is WaxDeck's own
  contract: `mbid` is on the album schema, and the binder holds playback
  state, so it would take an album mbid on the surface the player reads -
  or an album detail read per track - before a `coverartarchive.org` URL
  could be built. That is a spec change and a binder change, not a wall.
  **The tokenized `/media/art`**
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

- `[in-repo]` **Switching servers leaves the old server's downloads
  behind.** Adopting a new address on the connect screen drops the
  bearer token and lets the mirror heal itself - sync cursors are
  generation-bound, so a genuinely different server answers
  `sync-reset` and the mirror rebuilds - but downloaded files and their
  records still name pids the new server never minted, and nothing
  offers to reclaim them. Tolerable for what the feature ships for
  (the same server reached a new way: a tailscale name, a reverse
  proxy); a real cross-server move wants a "forget this server" wipe
  that clears the mirror, the download store, and the artwork cache in
  one deliberate action.

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

- `[in-repo]` **The surfaces drawn from outside the element tree stay
  English.** Five of them, and they are one problem: the Android Auto
  browse tree's folder names (`auto/auto_browse.dart`), the stand-in
  title a media-session row falls back to when the catalog has not
  answered for a queued pid yet (`auto/media_session_feed.dart`), the
  desktop tray menu (`desktop/desktop_ports_io.dart`), the sleep
  timer's media-session extend button (`player/sleep_timer.dart`), the
  notification-channel names and media-session action labels
  configured at engine init in `waxdeck_player`, and the download
  notifications `waxdeck_data` posts (`transfer_engine_io.dart` :20-26,
  positional `TaskNotification` arguments). Every one is built where there is
  no `BuildContext` to read a locale through - a port fed a database, a
  notifier, an operating-system menu - so `context.l10n` cannot reach
  them and the sweep left them as they are, with a comment at each site
  saying so. The copy ratchet cannot see any of it either: it reads
  named arguments whose names end in its suffix list, so a
  `...Name:` argument (`androidNotificationChannelName`,
  `audio_service_handler.dart` :291) and a positional constructor
  argument both sit at a floor of zero while holding English. The fix is one mechanism rather than four: resolve
  `AppLocalizations` for the current locale into a provider (the
  delegate can `load` a locale off the tree), hand it to each port at
  construction, and re-hand it when the picker changes the locale.
  Worth doing with the first of them that somebody actually reads in
  another language; until then it is a table nobody consults.

## Infrastructure

- `[in-repo]` **`_ClampedBox` is a design-system primitive living
  private to a podcast screen.** It is a `SingleChildRenderObjectWidget`
  and a `RenderProxyBox` that lay a child out unbounded, take a pixel
  budget, clip what does not fit and report whether anything did
  (`show_screen.dart` around 850-975) - no podcast in it anywhere.
  CLAUDE.md rule 3 puts components in `waxdeck_ui`, and the package
  already hosts this exact shape next to `ReadingColumn`
  (`_SkipLinkBox`/`_RenderSkipLinkBox`, `components/navigation.dart`).
  Private to a screen it gets no catalogue entry and no golden, so the
  next surface that wants "clamp this and offer Show more" - an artist
  bio, an album description, a review note - either copies the render
  object or falls back to the `ConstrainedBox` + `ClipRect` +
  unconditional button this replaced, which is the arrangement that
  offered to unfold a one-line description. Move it with a catalogue
  entry and both golden passes, and take the tidying in the same change:
  the intrinsics paths no call site exercises, and two getters nothing
  reads.

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
- `[in-repo]` **The web has no gapless crossing, and a preload window
  is not the way to get one.** just_audio's web platform is a single
  `HTMLAudioElement` whose `src` is re-pointed on every source change,
  so a boundary there is a load and an audible gap no matter how the
  window is arranged. WaxDeck preloaded into it anyway until
  `JustAudioEngine.canPreload` was set false on the web, and that cost
  rather than bought: `concatenatingInsertAll` awaits
  `_currentAudioSourcePlayer.load()` unconditionally - even for an
  insert past the current index - which resets the playing item to
  zero, never fetches the appended one, and leaves a player that can
  never end, so the queue stopped dead on the track it was on and the
  listen was never reported. Two separate things could change, and only
  one of them is about gapless. The bug is a plausible upstream fix
  (reload only when the insert moved the current index, which is the
  `if` the call already sits outside of); real gapless needs a
  different web backend - two elements swapped at the boundary, or
  MSE/Web Audio - which is a plugin-sized piece of work and the only
  thing that would make `canPreload` worth flipping back. Do not flip
  it for the bug fix alone: without a backend that can cross without
  reloading, a working window still delivers a gap and still costs
  three round trips and a stream token a track. `now_playing_test.dart`'s
  no-window case and `ui.spec.ts:16` are what say whether a flip took.

## Curation and metadata

- `[in-repo]` **The editor's unified save is one press but many round
  trips.** The save bar commits the staged draft as sequential calls:
  one for the scalar fields, one per changed credit role, one per tag
  set or remove, one for lyrics, one for release status. Against the
  headline client - a phone on cellular reaching a home server through
  a reverse proxy - that is N x 100-300ms felt as lag on a single Save,
  and every gap between calls is a partial-failure window on a flaky
  link. The fix shape is a WaxDeck-only compound endpoint (a spec
  delta, not an upstream ask): one POST carrying the staged parts, run
  server-side in the same order, answering with per-part outcomes in
  the `bulkEditMetadata` edited/skipped/failures idiom plus the
  accumulated write-back failures. Deliberately not a transaction:
  write-back is best-effort by design, so end-to-end atomicity is
  unattainable, and catalog-only atomicity would need a combined-edit
  facade upstream that is not worth its weight - the client already
  reports partial commits honestly (committed parts adopt clean,
  refused parts stay staged with the refusal beside them), and that
  model carries over. The client keeps the sequential path as the
  fallback for older servers.
- `[upstream]` **The provider chain fills only the front artwork slot.**
  The art-role model (front, back, disc, booklet, background) ships on
  the read and write surfaces, but enrichment still fills the front
  cover alone: a provider candidate carries a single cover image, so
  fanning providers out to the auxiliary slots (a fanart.tv artist
  background, disc art) needs the candidate/provider model extended to
  carry per-role art first - the "per-role candidate art on the
  enrichment port" ask in `upstream-requests.md` (WaxBin). The slots
  are readable and hand-settable meanwhile.
- `[in-repo]` **The client's accepted-format set is a hardcoded mirror
  that a custom `WAXDECK_UPLOAD_FORMATS` makes wrong.** Folder picks
  and drops filter against `kAcceptedAudioExtensions` (the default
  13-format set) before anything reaches the server, so an operator
  who configures extra formats (`wv`, `ape`) sees them dropped
  client-side - and, when nothing else survives, announced as
  unsupported. File picks escape through the native dialogs'
  "All files" group; a `webkitdirectory` or `getDirectoryPath` pick
  has no such group. The real fix is the server exposing its accepted
  set (a field on an existing read, or the health payload) and the
  pickers filtering against that; until then the mirror and the docs
  both say the server-side check at session create is the actual gate.
- `[in-repo]` **Android folder picking is excluded from the upload
  surface.** File picking works on every platform (the endorsed
  `file_selector_android` implementation covers in-app file picks),
  but Android folder access means SAF tree URIs, which the
  `FilePickerPort` deliberately does not speak; the "Upload a folder"
  tile hides there (`canPickFolders`). It is now the only platform it
  hides on - the web build picks folders through an
  `<input webkitdirectory>` - so this is the last of the exclusion.
  Multi-select plus auto grouping covers the album case on Android
  meanwhile.
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
  value, so claiming the former would be inventing an assertion. A
  separate ceiling rides above whatever this builds: MP4's own `rtng`
  advisory atom never surfaces as a tag, so iTunes-tagged M4As stay
  uncovered either way - the mapping ask is recorded in
  `upstream-requests.md` (WaxLabel).
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
- `[in-repo]` **Stored ALAC bit depth is wrong (16) for files scanned
  before waxlabel v1.4.2.** The parser now reads the real depth from
  the magic cookie rather than trusting the sample description, but
  nothing re-reads an already-scanned file: the incremental scan
  fast-paths anything whose size and mtime are unchanged, and WaxDeck
  never sets `waxbin.ScanRequest.Force` (the field exists; all four
  construction sites - the two in `library.go`, `tools.go`, and the
  watcher's scoped scan at `watch.go:272` - leave it zero), so existing
  rows never heal. The
  essence digests did not change, so no rescan is forced either. It
  shows on the upgrades surface (`bitDepth`, `api/spec/health.yaml`),
  where a 24-bit ALAC reading 16 misranks upgrade candidates. Fix
  shape when taken: expose a forced rescan - an admin action or a
  one-time sweep - rather than special-casing ALAC.

## Discovery and stats

- `[in-repo]` **The per-media-type listening split is drawn by no client
  surface.** `ListeningStats.byMediaType` and `YearInReview.byMediaType`
  have always shipped and no screen reads either. Radio now has a slice
  in both - it is the reason the field gained a value - so the wire is
  answering a question nothing asks on screen. Recorded rather than
  answered here because the fix is a chart nobody specified, and the
  question of what the stats screen should show alongside the total is
  a design one.

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
- `[in-repo]` **A has-art signal on `FacetBucket`.** Kept for the
  reasoning, because the next agent tempted by a `hasArt` field needs
  the probe rulings below. The situation it was sequenced on has
  arrived: the artist portrait sweep writes artist-level art now, the
  artists index asks per row like the album one, and the misses land in
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
- `[in-repo]` **A role granted mid-session is not seen until the next
  sign-in.** `authControllerProvider` is written at launch, login,
  bootstrap and sign-out and nowhere else, and no server event carries an
  account change, so a promotion reaches this client only when it reads
  the session again. Everything role-gated inherits it - the nav rows,
  the Server settings section, the album editor - and the admin console's
  refusal page is where it now reads as an answer rather than as a
  missing row. The fix is server-side: an account-changed marker on the
  sync stream, which the redirect listener already has a shape for.
- `[in-repo]` **There is no durable notification inbox.** The
  Notifications screen and the bell both draw the same session-local
  list: what this client saw while it was running, emptied by a
  relaunch. `api/spec/notifications.yaml` is the event catalog and the
  delivery targets, not a history, so nothing on the server holds what
  happened to an account - which makes the list complete on the device
  that was open and empty on the one that was not. A real inbox is a
  server feature (a per-user table, a keyset-paged read, a read
  marker), and the screen that would draw it is already there and would
  swap its source.
- `[in-repo]` **Radio scrobbling is off per account, not per station.**
  The account-wide switch ships (`Prefs.radioScrobbleOptOut`),
  which covers the listener who wants none of it. What the original entry
  also floated is a per-station flag, for the household that scrobbles
  its music stations and not its talk ones. That wants a per-user
  per-station bit, and the only per-user station state that exists is the
  favourites list; whoever adds a second one should decide whether they
  share a shape.
- `[in-repo]` **Subsonic's `maxBitRate` is still documented-ignored.**
  The capped-transcode machinery it needs now exists
  (`flow.PlayOptions.MaxBitrateKbps`, minted as `fmt=`/`br=` on the
  stream URL and clamped against the per-user ceiling at both mint and
  fetch), so honoring the parameter is a small adapter change: read it
  where the stream view resolves, pass it through `PlayOptions`, and
  decide how it composes with a format the client may also pin - which
  is the same decision the "forcing the source's own format" entry
  above already holds.
