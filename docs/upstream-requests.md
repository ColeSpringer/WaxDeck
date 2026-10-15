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

## WaxLabel

(nothing outstanding)
