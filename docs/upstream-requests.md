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
