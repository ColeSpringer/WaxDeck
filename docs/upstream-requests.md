# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **A reopen swaps the store's connection pools under concurrent reads.**
  `Store.Reopen` assigns the read and write pools under `wmu`, but reads
  take `s.read` without it, so a request that reads while a hand-off
  ends races the reopen (`go test -race` reports it between `Reopen` and
  `LatestChangeSeq`). WaxDeck keeps serving through a hand-off, and its
  maintenance watchdog probes the catalog while it waits. Wanted: the
  pools published safely, as atomic pointers or behind a read lock.
  Shipped workaround: the watchdog probes at most every ten seconds, and
  the tests drive it synchronously with the pid path cache's background
  poll off.
- **A template's `<` groups recurse without a bound.** `renderNodes`
  descends one Go frame per `<`, so a template of a few megabytes of
  nested groups overflows the stack, which no recover catches.
  `Profile.Validate` renders every template, so a save or a preview is
  enough. Wanted: a nesting limit, or a length limit, in the grammar.
  Shipped workaround: WaxDeck refuses a template longer than 1024
  characters before handing it over.

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
