# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **The album-art walk's auxiliary half has no rung gate.** It runs when
  any provider advertises `CapAuxArt`, but fanart.tv advertises it for
  release groups and artists and answers nothing for a release, so with
  its key set every identified album with an empty back, disc, booklet
  or background slot is walked for a certain miss, again every retry
  window, and the walk spends the nightly cap ahead of the book, lyrics
  and fields walks. Wanted: a way for a provider to say it serves
  auxiliary art at the release rung (a capability of its own, or a
  per-rung declaration), so the half runs only when one does. Shipped
  workaround: none; the misses cost no requests, only the cap.

- **The facade exports no phase list.** WaxDeck reports the phases a
  run would execute and refuses a forced phase the install does not
  run, so it mirrors the catalog's gating in `enrichPhaseTable` and a
  test pins the copy phase by phase through `StartEnrich`. Wanted: the
  built phase list for this install (say `Library.EnrichmentPhases()`),
  so the status surface reads the catalog's own. Shipped workaround: the
  mirror and its pin.

- **A provider's failure is recorded as a miss.** The art, fields,
  lyrics and artist-art walks skip a provider that errors and then mark
  the target exactly as if every provider had answered no, so a network
  blip or a quota window leaves it unasked for the whole retry window.
  The release match already leaves a transient failure queued. Wanted:
  the same for these walks, so a target whose provider failed is asked
  again next pass. Shipped workaround: Deezer waits out its own quota
  window once before failing; any other failure waits out the retry
  window (30 days by default).

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

(nothing outstanding)

## WaxLabel

(nothing outstanding)
