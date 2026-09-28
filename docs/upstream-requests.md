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

- **The enrichment provider list is fixed at open, and the built-ins are
  out of reach.** WaxDeck lets an operator order and switch its own
  injected providers, but `enrich.New` takes the slice once, so WaxDeck
  injects one slot per rank that answers as whichever provider holds
  that rank (named `slot-N` only while the rank is empty), and holds a
  new order back while any enrich job runs so a reorder cannot move a
  provider mid-walk. Done markers are kept per phase and item, not per
  provider, so a source switched back on is not asked about what others
  finished while it was off unless a run forces its phases. The key-free built-ins
  (`coverartarchive`, `listenbrainz`, `lrclib`) are registered after the
  injected ones and cannot be moved or switched off at all. Wanted: a
  runtime order hook (or a provider list read per pass), the built-ins
  exposed to it, and done markers kept per provider. Shipped workaround: the slots; the built-ins
  are listed pinned last and read-only.

- **The coverage read counts no lyrics.** `EnrichmentCoverage` reports
  artists, release groups and books, so the Enrichment screen can say how
  many music tracks there are but not how many carry lyrics. Wanted: a
  per-track lyrics count on the coverage read. Shipped workaround: the
  lyrics tile reads "Not counted" over the track total.

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

- **An NSP gap's reason is only an English sentence.** `NSPGap.Reason`
  names fields in the engine's or the file's spelling (`added`,
  `dateadded`), so WaxDeck respells the field a sentence ends on and the
  terms of the dropped-sort sentence, and any other wording passes
  through untranslated. Wanted: a reason code with its parameters on
  each gap, so a client can say it in its own words and language.
  Shipped workaround: that respelling; the dialog heads each sentence
  with the rule editor's name for its field.

- **NSP's favourite flag is `loved`, and `filepath` and `duration` are
  unmapped.** The NSP field map has a `starred` key, which Navidrome
  never writes: its field is `loved`. So a Navidrome rule on favourites
  is refused on import, and a rule on `starred` exports under a name
  Navidrome does not know. `filepath` and `duration` (seconds, where the
  catalog keeps milliseconds) map neither way. Wanted: `loved` both
  ways, `filepath` to `path`, and `duration` rescaled. Shipped
  workaround: none; the import description names the fields that map.

- **A waveform does not say how much audio its buckets span.**
  `PeaksData` carries a bucket count and the data, so WaxDeck places a
  cue-carved track's window by the file's stated duration, while the
  buckets cover the audio as decoded. A header that understates its
  length (a VBR MP3 with no Xing frame) mis-scales every window of that
  file. Wanted: the sample count or duration the buckets were measured
  over, on the peaks read. Shipped workaround: windows placed by the
  stated length; a window it cannot hold answers unavailable.

- **A sync's commit is not part of the provider contract.** WaxDeck's
  YouTube provider hands a premiere it found after the cursor passed it
  to the catalog under a token it adds to the enumeration's ETag, and
  the next poll's ETag is its receipt that the episode was written.
  That rests on `UpsertFeed` storing the ETag in the transaction that
  writes the episodes, which `source.Provider` does not promise; were
  the two written apart, a receipt could outlive episodes that never
  landed, and the provider would let an entry go the catalog never
  wrote. Wanted: that atomicity stated in the provider contract, or a
  call to the provider once a sync's writes commit. Shipped workaround:
  the receipt, relying on today's single transaction.

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
