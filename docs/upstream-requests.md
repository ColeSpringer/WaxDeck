# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **A maintenance hand-off reopens the catalog without telling the
  host.** A CLI restore or rebuild proxied through the host's socket ends
  in `EndMaintenance`, which reopens the store and runs its post-open
  reconciliation, and the embedder hears nothing of it. State a host
  derives from the catalog at open goes stale: WaxDeck maps each account
  to its catalog user at start, so a restore that replaces the catalog's
  users leaves an account whose user it lacks failing every read it
  scopes with "no such user" until the next start. Wanted: a reopen
  notification, as an `Options` callback or a row on the change feed
  the host already follows. Shipped workaround: the mapping is rebuilt
  at every start.

- **The names the catalog reserves are not all exported.** `enrich.New`
  drops an injected provider named after a built-in or a marker label.
  The built-ins' names are exported (`enrich.ProviderMusicBrainz` and
  the rest) but the marker labels `musicbrainz:edition` and `none` are
  not, so WaxDeck copies them to refuse a custom provider under one at
  startup, and a label added upstream would let one through to be
  dropped without a word. Wanted: the labels exported, or the reserved
  list itself. Shipped workaround: the copy in
  `service.ReservedEnrichNames`, tested against the catalog's drops and
  its registered built-ins.

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
