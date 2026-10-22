# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **Concurrent catalog reads stop scaling at a few cores.** Under load
  the catalog-backed endpoints plateau near one client's throughput
  (`/items/{pid}` goes from 781 to 987 requests a second between 1 and
  50 clients, each request costing about three times the CPU), while
  endpoints that never touch the catalog reach 13k a second. The
  profile points at modernc.org/sqlite's libc: one allocator mutex
  around every malloc and free, and one LRU mutex per page fetch. WaxBin
  opens one writer and eight readers, so the pool is not the limit, and
  WaxBin owns the dependency. Wanted: a concurrent-read benchmark
  (`RunParallel` over the read paths) and the report to modernc with it
  attached. Shipped workaround: WaxDeck keeps the statements per request
  down (batch reads rather than a point read per row), which lowers the
  cost without lifting the ceiling.
- **Leaving thumbnails out of a backup costs a second full rewrite.**
  `port.TrimBackupFile` follows the `VACUUM INTO` with a `DELETE` and a
  plain `VACUUM` of the copy, which reads and writes it again and needs
  scratch space its size in SQLite's temp directory (in a container,
  usually the image layer rather than the data volume). Wanted: a copy
  that leaves tables out in one pass. Shipped workaround: WaxDeck's
  backups copy everything, thumbnails included.
- **Planning an organize pass stats every file.** `PlanOrganize` runs
  `Hold`, so a plan Lstats each source and lists each destination
  folder; on a network share that is minutes for a large library, and
  an unmounted root turns every move into a `missing` hold. Wanted: a
  plan without the disk pass, for a caller that needs only where each
  file belongs. Shipped workaround: WaxDeck's path-mismatch health rule
  counts a held move that still has a destination as misplaced, and
  pays the disk pass on its daily sweep.
- **`AddRoot` stats the root even with `AllowAbsent`, with no
  deadline.** `config.CheckFolder` stats the path to refuse a file, so
  a hung network mount blocks the call, and WaxDeck registers its
  configured roots during startup. Wanted: a bounded check, or none
  under `AllowAbsent`. Shipped workaround: WaxDeck logs each
  registration first, so a stalled start names the root it is on.
- **This build's catalog stamp is not exported.**
  `sqlite.BaselineFingerprint` is the only way to the value a catalog's
  `user_version` must hold, and hosts stay off `store/sqlite`. Wanted:
  the fingerprint, or a header check over a reader, from `port`, so an
  archived catalog can be judged without extracting it. Shipped
  workaround: restore staging compares the archived header with the
  live catalog's stamp, and the start validates the extracted file with
  `port.ValidateBackup` before swapping it in.
- **Ref resolution cannot be scoped to what a caller may hold.**
  `ResolveRefWith` settles a tie by taking the present item with the
  lowest pid, blind to the caller, so when that pick is in a library the
  importing account cannot see and a copy sits in one it can, the entry
  reads as missing. Wanted: a `ResolveOptions.Accept func(*model.ItemView)
  bool` applied to each rung's candidates before the tie is settled.
  Shipped workaround: WaxDeck resolves catalog-wide and turns every
  match the caller cannot see into a miss, which never leaks but can
  miss such a copy.
- **Exports write every member of a playlist.** `ExportM3U8` and
  `ExportPlaylistRefs` re-read the whole list themselves, so a host that
  may show a reader only some members cannot use them. Wanted: both
  over a caller-supplied pid list (`ExportM3U8For`, `ItemRefs`, a thin
  wrapper over `store.ItemIdentities`). Shipped workaround: WaxDeck
  writes the M3U document itself in the catalog's format, and pairs
  `ExportPlaylistRefs` with member reads taken on both sides of it
  (three reads of the list an attempt, the export's own included),
  checking each pair before keeping a visible member's ref; a random
  smart list with no pinned seed draws afresh on every read, so its one
  draw is resolved back to its items instead. Both go when the ask
  lands. Until then a smart list's portable export follows the
  catalog's own evaluation, which spends a limit before dropping
  trashed members, so a limited list holding trashed matches exports
  fewer entries than its listing and its M3U export show; and a
  shuffled list's draw leaves out a member its ref cannot name back, an
  episode never fetched being the usual one (no file, so no essence or
  fingerprint).
- **Series have no query field.** A query can facet on an item's album,
  artist or release group but not its series, so the series listing
  reads each series' books to learn whether a restricted reader may
  open any of them (the catalog places a series in every library
  holding a file of it, an alternate copy's included). Wanted: a
  `series_pid` item field (and a series facet group) like `album_pid`.
  Shipped workaround: WaxDeck reads the books per series and takes
  their tag verdicts for the whole page in one query.
- **Entity counts include the trash.** `EntityInfo.ItemCount` and
  `TotalDurationMS` count every member, trashed ones included, while
  every listing leaves the trash out, so an album or series holding a
  trashed member advertises one more than it lists. Wanted: the counts
  over members not in the trash, or a trashed count beside them.
  Shipped workaround: a series detail counts the books it lists; the
  album read and the series listing carry the catalog's numbers.
- **An import's report does not say which files joined an existing
  item.** `inbox.FileOutcome` names the item a file backs and whether
  it was attached as a copy, but not whether the item already existed:
  a further part folded into a book the library held, or a better
  encoding taking an item over, reads like a new item. Wanted: the
  scan's own verdict on each file (`ItemCreated`, and joined for a fold
  or a takeover) carried on `FileOutcome`. Shipped workaround: WaxDeck
  reads the change feed's tail right before each file's apply and
  counts the file's item as the import's only when its create row
  arrived after it; an unreadable feed grants nothing, and an item
  someone else creates during that one apply still reads as made.
- **A scan that changes items' kind reports no fold map.** A library
  moved onto Audiobooks, or tags that now make tracks one book, re-kind
  items on the scan: the first track becomes the book in place and the
  rest fold into it and are deleted. `SetItemKind`'s `KindReport` says
  what folded where; `scan.Result` does not. Wanted: the same report
  (`Converted`, `Absorbed`, `Created`) from a scan. Shipped workaround:
  a track's share link refuses to serve the book its track became, so
  nothing widens, but the folded tracks' listens, play-state stamps and
  health rows keep their deleted pids, and a split's new parts grant
  their book's uploader nothing.
- **A missing file's own row blocks the upload that would restore it.**
  The import's collision check (`DisplayPathExistsFold`) counts a
  missing file's catalog row, so re-uploading that very audio quarantines
  with "destination case-collides with a cataloged file" and cannot land.
  Wanted: a missing row of the same audio left out of the check, or the
  import taking the row back. Shipped workaround: WaxDeck keeps the
  staged copy and fails the decide with the planner's reason, rather
  than calling the file held and removing it.
- **A held lease and the kind refusals are told apart by their words.**
  `jobs` answers a lease another job holds with `CodeConflict` and the
  sentence "another job holds scope ...", which is also the code of a
  kind change's part not on disk, and `SetItemKind`'s refusals (a cue
  track, a shared file, a cue sheet beside) are `CodeInvalid` told apart
  by text that also embeds paths. Wanted: a typed lease-held marker
  (a sentinel or its own code) and typed kind refusals. Shipped
  workaround: WaxDeck matches the sentences, and a test drives a kind
  change into a real held lease so a reworded refusal fails there.
- **A file's two fingerprint forms take two fpcalc runs.** The
  compressed form AcoustID takes and the raw vector `ResolveRef`
  compares come from separate `fpcalc` runs (`-raw` prints one or the
  other), each decoding up to two minutes of audio. Wanted: an encoder
  of the compressed form from the raw vector in `fingerprint`, so one
  run serves both. Shipped workaround: an upload's completion runs the
  two side by side.
- **Custom tags are written one key per file rewrite.** `SetItemTag`
  takes one key, so a save that sets or clears several custom tags (or
  marks an item unofficial beside them) with write-back rewrites the
  whole file once per key, and the write-unsynced fix pays owed tags the
  same way. Wanted: a verb that sets and clears several keys in one
  write per file. Shipped workaround: one call per key.
- **A refused import action keeps no destination.** `settle` clears
  `Dst` and `RelDst` on every action that is not an import, so a file
  quarantined because its place is taken does not say which place, or
  whose file holds it, and the refusal is told only by its sentence
  ("destination already exists", "destination case-collides"). Wanted:
  a destination collision that keeps the rendered destination and names
  the occupying file, under a typed reason. Shipped workaround: WaxDeck
  counts an upload "held" (the library already has it where it would
  go) only on that refusal, matched by its words, and when the item
  holding its audio carries the file's own details, a stand-in for "the
  occupant is the holder's file" that refuses (and keeps the bytes) when
  unsure; the held-file tests drive real collisions, so a reworded
  sentence fails there.
- **Apply-time refusals are only counted.** `ApplyImport` quarantines an
  action whose library was flagged read-only since the plan, and
  `ApplyDelete` skips one whose library turned read-only or whose cue
  rip's tracks changed, each on a private copy of the plan, so the
  reports (`inbox.Report.Quarantined`, `trash.Report.Skipped`) count
  them and name neither the file nor why. Wanted: the reports naming
  each such action with its reason, as `Failures` names the errored ones.
  Shipped workaround: WaxDeck re-reads the target library's read-only
  flag for an import that landed nothing, and, for a delete, re-reads
  the items' files to find which stayed and words the cause from the
  library's flag.
- **A kind change's report is lost with a crash, and does not say where a
  split part came from.** `SetItemKind` writes its `KindReport` when the
  job finalizes, so a process killed mid-change (SIGKILL, OOM, power)
  leaves the job crashed with no result while files 1..k already
  converted, folded and split; and `KindReport.Created` is a flat list,
  so a part minted by a change that split several books cannot be told
  from which. Wanted: the report written as each file commits (or
  recoverable from the job's journal), and `Created` mapping each part to
  the item it came from. Shipped workaround: a crashed change remaps
  nothing (folded items keep their listens, play-state stamps, playlist
  entries and shares on their pids; split parts get no grant), and a
  multi-book split's parts are credited by album, by the only book split,
  or, when a non-administrator started it, to that starter.
- **A unit's files are planned one at a time.** `ImportAcquired` plans
  one file against the library as it stands, so a unit (a book's parts,
  an album) is planned twice: once up front, to refuse it whole before
  anything moves, and again right before each file after the first
  moves, since the earlier ones change what the later ones meet (a
  part joining the book the first made, two staged files claiming one
  place). Each plan hashes the file's audio. Wanted: one plan over the
  unit's files that sees each other's destinations and books. Shipped
  workaround: a multi-file decision hashes files 2..N twice, inside a
  request the client gives a long budget.
- **A duplicate audit finding's reason is only in its sentence.**
  `AuditFinding` has no field for why a duplicate group was paired
  ("shared MBID", "same collation key", `model.ReasonSameAlbumName`), so
  WaxDeck's duplicates listing parses `Message` ("duplicate <type>
  (<reason>): <names>; <advice>"). Wanted: a `Reason` field with exported
  constants. Shipped workaround: WaxDeck parses the sentence, and a test
  runs the real audit so a reworded sentence fails there.
- **A tag write owed does not say who set the value.** `FileDiagnostics`
  lists `tag_write_owed` rows with their `TagKey` alone, so telling a
  value a person or a source set from one a clean-up pass (a normalize)
  rewrote in the catalog only takes a `Provenance` read per item: after
  a genre normalize, every daily health sweep reads one for each file it
  touched, to set those keys aside. Wanted: the setter's source on the
  diagnostic, or a filter leaving normalize-owed keys out. Shipped
  workaround: one provenance read per item with owed keys per sweep.
- **An item's file list carries no file facts.** `ItemFiles` answers each
  file's pid, path, role and library, so a reader wanting when the files
  were first found, or their bitrate, reads each file's row with `File`.
  Wanted: `FirstSeen` and the quality fields on `ItemFileRef`, or a batch
  `Files`. Shipped workaround: an item's detail reads only its primary's
  row and each copy's, so a book's `addedAt` is when its primary part, or
  an earlier copy, was found, not its earliest part.
- **Search cannot be scoped to the shows a caller follows.**
  `SearchOptions` narrows by library and state only, so the episode group
  ranks every matching episode in the catalog and the per-group cap
  applies before WaxDeck drops the episodes of shows the caller does not
  follow. When another account follows a show whose episodes match best,
  the caller's episode group comes back short or empty while their own
  shows hold matches. Wanted: an episode scope on `SearchOptions`, the
  shows to admit or a `query.Node` applied before the cap. Shipped
  workaround: the subscription filter runs after the cap; the listings,
  which page, carry the scope in their query instead.
- **A feed's failure says why only in its words.** `AddSource` and
  `Sync` mark a failed enumeration as the provider's
  (`source.ProviderError`), but within it a page that is not a feed, a
  body over the size cap, a refused private address and the host's HTTP
  status differ only by text: `netsafe`, whose `TooLarge` tells the cap
  apart, is internal, and a status is a sentence ending `returned HTTP
  403`. Wanted: typed reasons on a provider failure (the status,
  too-large, blocked-address, not-a-feed), or `netsafe.TooLarge` and a
  status error exported. Shipped workaround: WaxDeck reads the reason
  off the stable fragments of those messages, and tests run each
  failure through the real client, so a change of wording fails there
  rather than reaching a listener as the wrong sentence.
- **Log lines name whole feed, cover and transcript addresses.** A
  private show's addresses can carry its token, and WaxBin logs them
  whole: `podcast image fetch failed`, `podcast image undecodable`,
  `chapters fetch failed`, `chapters parse failed` and `transcript fetch
  failed` (Debug) log `url` and an error that repeats it, `OPML import:
  feed failed` (Warn) logs the feed URL, and `watch: podcast sync failed`
  (Warn) logs a sync error whose text names the feed, as every `netsafe`
  error's text does. Wanted: the host alone in a log line, and `netsafe`
  errors that name the host rather than the URL, since their text
  reaches every caller's log. Shipped workaround: the logger WaxDeck
  hands WaxBin cuts every web address in a line, in its message or any
  value, to its scheme and host; WaxDeck's own feed, transcript and
  download failure lines log a reason and a cause, and its chapters
  lines the host and a cause, never the error.
- **A book's timeline runs a part by its chapter marks.** `bookChapters`
  advances the book timeline by each part's effective length (its chapter
  extent where CHAP frames or a chapter track run past the measured
  audio), so the marks and `TotalDurationMS` sit off the timeline the
  parts play on, and `BookDetail` does not say where each part starts on
  the catalog's. Stored places are remapped on that timeline too, while a
  player records positions on the audio's. Wanted: each part's catalog
  start (and effective length) on `BookDetail.Files`, or the timeline laid
  out by the measured durations where they are known. Shipped workaround:
  WaxDeck projects each mark onto the parts' own timeline (held to its
  part's audio, by its file offset) and serves the book's length as the
  end of its last part's audio, and maps a chapter edit back onto the
  catalog's timeline from part starts read off the marks themselves,
  which is exact unless a user-curated book has a part with no mark of
  its own whose embedded marks ran past its audio.
- **`CurrentChapter` names the next chapter in a gap between two.** Its
  doc promises the nearest preceding chapter when a position falls
  between spans, but the store's loop answers the first chapter ending
  after the position: with chapters at 0-60 s and 90-120 s, 75 s names
  the second. `BookResume` reads its chapter through the same loop.
  Wanted: the last chapter starting at or before the position (the first
  before any), as documented. Shipped workaround: WaxDeck calls neither;
  it names a resume's chapter from the marks it serves, the way its
  player names the chapter playing.
- **The older `/blob/master/` Podcasting 2.0 namespace spelling is not
  aliased.** `nsAliases` maps the GitHub address ending
  `/blob/main/docs/1.0.md` onto the current namespace, so a feed
  declaring that one parses with its credits, chapters and transcripts;
  one declaring the same address with `/blob/master/` reads as having
  none of them. No feed is known to use it. Wanted: that spelling in the
  same table. Shipped workaround: none needed today; a feed test pins
  the aliased spelling, so a WaxBin bump cannot lose it unnoticed.
- **An episode's chapters are read only by a download.** `Download`
  fetches the chapters document after attaching the file, and
  `PutEpisodeChapters` refuses an episode with no file, so one that is
  only streamed by enclosure never has chapters stored, while
  `FetchTranscript` fetches a transcript with no download. Wanted: a
  verb beside `FetchTranscript` that fetches and stores an episode's
  chapters without downloading it, which needs the store to hold them
  without a backing file. Shipped workaround: the episode detail read
  fetches the chapters document itself for display, through the guarded
  transcript client, and keeps the result in memory for hours (ten
  minutes when the fetch failed); chapters the catalog stored win. A
  credentialed show's document is read only for its subscribers, with the
  show's credentials sent to the feed's own host and no other.
- **Rated entities cannot be listed.** `StarredEntities` lists a user's
  starred artists or albums in one read, but nothing lists the rated
  ones: a rating comes only from `EntityPlayState`, one entity per read.
  Wanted: `RatedEntities(ctx, userPID, kind)` beside `StarredEntities`.
  Shipped workaround: the Subsonic surface reads every album's rating
  with a point read for `getAlbumList2 type=highest` (a starred one's
  rides its star read), memoized per user until that user rates the
  entity again, an artist or album change in the catalog, or a replaced
  catalog, within 1,000,000 answers shared by every account: past that,
  accounts idle for ten minutes give way, least recently used first, and
  what still does not fit is read again. Ratings go on a response only
  when it names at most 500 artists and albums (stars alone past that).
- **An item view carries no added time and no primary-file facts.**
  `model.ItemView` has no `CreatedAt` (the `playable_item.created_at`
  the recently-added list orders by) and nothing of its primary file's
  size or bitrate, so the Subsonic sweep cannot carry what `created`,
  `size` and `bitRate` need. Wanted: `CreatedAt`, `FileSize` and
  `Bitrate` of the primary file on `ItemView`. Shipped workaround: those
  are read per rendered song from the primary file's row (`File`), at
  most 500 a response, each answer held at most ten minutes; an album's
  `created` is its first track's file's `FirstSeen`, and `type=newest`
  folds the recently-added track list into albums (a music folder's own,
  for a folder).
- **The podcast library exists only after the first download.**
  `podcast.Service` creates it lazily (`EnsurePodcastLibrary`, reached
  from `Download` and `ImportEpisodeFile` only), and a host cannot
  register it itself: `AddRoot` and `Options.Roots` refuse a root that
  overlaps the podcast dir. Until something is fetched there is no pid
  to grant, so an account limited to chosen libraries cannot be given
  podcasts. Wanted: the library created when the podcast service opens
  with a dir configured, or an exported ensure. Shipped workaround: the
  docs tell an administrator to fetch one episode before granting it,
  and WaxDeck throttles the attribution reloads its lookups of the
  missing library cost.
- **A download sends a show's credentials to whatever host its enclosure
  names.** `HTTPProvider.Fetch` sets the show's stored basic auth on the
  enclosure URL, so a credentialed feed whose enclosures carry a
  measurement prefix or sit on another host hands the login to that
  host, and Go's redirect rule keeps it across a hop to another port, a
  scheme or a subdomain. The same rule drops it for the rest of a chain
  once a hop leaves for another domain, so audio a prefix sends back to
  the feed's own host is asked for there without it. Wanted: the
  credentials on every request at the feed's own origin (scheme, host
  and port), a redirect hop that lands there included, and on no other.
  Shipped workaround: WaxDeck's own requests for a show's files (the
  stream relay and its warm-up, transcripts and chapters) hold that
  rule; fetching an episode to the server still goes through the
  download.
- **A download's transcript and chapters are fetched with no login.**
  `Download` reads the episode's transcript and chapters documents
  through the guarded client with no basic auth, so a credentialed
  show's documents at its feed's own origin are refused on every
  download and the episode's transcript never reaches the search index.
  Wanted: the show's credentials on those requests at the feed's own
  origin, by the rule the entry above asks of the enclosure. Shipped
  workaround: WaxDeck reads a credentialed show's transcript and
  chapters itself, with the login at the feed's origin, and capturing
  the transcript hands its text to the index through `PutTranscript`.
- **A password that cannot be read still sends half a login.**
  `authFor` answers the user name alone on any `GetSecret` error, a
  store failure or a sealed secret with no cipher included, so the
  download goes out without the password and the host's refusal is
  counted against the episode. Wanted: a read failure other than
  not-found failing the download as the catalog's. Shipped workaround:
  WaxDeck's own requests send no login on such a failure and answer
  the server's error; a download still goes through `authFor`.
- **The download's type gate is not the relay's.** `HTTPProvider.Fetch`
  accepts `audio/*`, `video/*`, `application/ogg`, `application/mp4`
  and octet-stream, and requires a type, so a host labelling MP3
  `application/mpeg`, or sending no type, fails every fetch of an
  episode that streams fine, while a host answering a playlist or
  manifest type under `audio/` or `video/` (`audio/x-mpegurl`,
  `audio/x-scpls`) has the playlist stored as the episode. Wanted:
  `application/mpeg` and an untyped answer admitted, and the playlist
  and manifest types (M3U and HLS, PLS, ASX and its kin, RealMedia's,
  DASH) refused; or the accepted types and the required type as fetch
  options. Shipped workaround: WaxDeck queues nothing for an episode
  whose feed declares a playlist or manifest type, or whose host its
  relay saw answer one for the address the feed names, and drops such a
  fetch queued before anyone knew; an episode whose host labels its
  audio `application/mpeg` or leaves it untyped streams through the
  relay and cannot be fetched.
- **The feed client's address guard passes NAT64 forms of private
  addresses.** `netsafe`'s `isBlockedIP` judges an IPv4-mapped address by
  the IPv4 address in it but has no case for NAT64's well-known prefix,
  so `64:ff9b::a9fe:a9fe` (169.254.169.254) or `64:ff9b::a00:1`
  (10.0.0.1) passes it, and a subscribe, a sync, an episode download or
  a transcript capture dials it with `BlockPrivateIPs` set. Behind a
  translator that forwards non-global IPv4, that reaches the address
  the prefix carries. Wanted: a `64:ff9b::/96` address judged by the
  IPv4 address in its last four bytes. Shipped workaround: WaxDeck's own
  clients (the enclosure, transcript, chapters and radio relays,
  notifications, scrobbling) refuse the form, and a subscribe whose feed
  host is such a literal is refused with `blocked-address` (a name or a
  redirect that leads there is not); the catalog's fetches of addresses
  a feed names have none.
- **A re-add takes the re-adder's address as the show's.** `AddSource`
  upserts a show it already holds with `feed_url` set to the address it
  was just given, so a second subscriber's personal address (a token in
  its query, a login in its user info) becomes the address every reader
  of the show sees. Wanted: an add option that keeps a held show's stored
  address. Shipped workaround: WaxDeck gives each follower the address
  it subscribed by, and marks the show private, which hides its address
  from everyone who does not follow it, right after an add whose address
  carries a credential and before anything can refuse the subscribe; a
  read in the moment between the add and the mark still sees the new
  address.
- **Feed and episode titles are kept at any length.** The feed parser
  trims a channel's and an item's title but never cuts one, so a feed
  can carry a title as long as the 16 MiB a feed may be, and every
  listing, export and API answer that names the show or the episode
  repeats it. Wanted: titles cut at parse, to a thousand characters or
  so, far past any real one. Shipped workaround: WaxDeck cuts show and
  episode titles to their first 1,000 characters where it maps them, in
  its REST and Subsonic answers, its notifications and its OPML export.

## WaxTap

- **A chunked download has no stall timeout.** `Timeouts.ChunkRetry`
  bounds a whole ranged chunk request, so it has to be sized for the
  slowest link a download may run over, and the stall guard that bounds
  sequential and SABR deliveries does not cover ranged chunks. A long
  file runs four 10 MiB chunks at once, so WaxDeck's 10 minutes still
  fails one below about 560 kbit/s, and a chunk that stalls outright
  takes the same 10 minutes to be retried. Wanted: an idle timeout for
  a chunk that has stopped receiving bytes, so a slow link finishes and
  a hung connection fails fast. Shipped workaround: the 10-minute
  chunk deadline.

## WaxSeal

(nothing outstanding)

## WaxFlow

- **The in-process analyzer cannot measure a window's bound the way the
  streaming engine does.** `Slice` bounds a window by the declared
  length, and the server package measures an advisory or absent length
  first (`measureLength`, `sliceMeasured`) before slicing, which is not
  exported. So the built-in sonic analysis refuses a carved window past
  an understated length that `/media/analysis` serves. Wanted: that
  measure exported (or a `Slice` that measures an advisory length).
  Shipped workaround: such a track rests unanalyzed until its audio
  changes, instead of being queued again.
- **A live encode nobody reads any more runs to the end.** A stream cut
  with `t` is a fresh encode of the whole remainder, and the read-behind
  model finishes it even after its last reader leaves, holding a live slot
  all the while. In a browser WaxDeck positions capped and voice-boosted
  streams by minting a cut at the listener's position (the native apps
  seek an HLS rendering instead), so scrubbing through a long boosted
  book part there starts an encode per distinct second the listener
  lands on, each running to the end of the part. Subsonic clients seeking
  with `timeOffset` (every seek into a book in parts) start the same
  per-second encodes, uncoalesced. The app's failure probe reaches them
  too: it asks a failed stream with a GET from the top, the one request
  the engine admits and so the only one its busy refusal answers, and an
  item rendering's segment the same way, whose worker likewise runs to
  the rendering's end. Wanted: cancel a live pipeline, or a segment
  worker, once no reader is left on it. Shipped workaround: the server
  floors every cut it mints to a whole second of the item, or of the
  part it lands in, and a Subsonic client's offset into a book in parts
  to a whole second of the book, so repeats near one spot share an
  encode, and the first-party web client coalesces a run of seeks into
  one reload at the last target.
- **A gapless timeline has no progressive form.** A Subsonic client plays
  a book in parts as one song, so WaxDeck joins the parts' MP3 encodes
  end to end. Each part is its own encode: its encoder priming at the
  head and its last partial frame of padding at the tail stay in the
  joined stream, a few tens of milliseconds a seam, so the client's clock
  runs ahead of the book by that much for every part it crosses, and
  each part needs a live slot of the engine's own at its seam. Wanted:
  a timeline (`tl=`) served progressively on `/stream`, MP3 at least: one
  encoder over the members, gapless at every seam, holding one live slot
  for the whole run. Shipped workaround: the per-part encodes joined
  frame by frame, the trailing frames that are padding alone dropped,
  and the engine's overload at a seam waited out a few times.
- **The HLS playlist writer is internal.** `internal/hls` writes the
  master and media playlists the server answers, so a host that renders a
  presentation itself through the exported segmenter (WaxDeck's
  conformance fixtures render one item's presentation for the players to
  play offline) cannot write them the same way. Wanted: the writer
  exported (`Master` and `Media`, or a `SegmentPlan` method that writes
  the media playlist). Shipped workaround: `fixtures/presentation.go`
  writes both in the engine's form, and its test pins their shape.

## WaxLabel

(nothing outstanding)
