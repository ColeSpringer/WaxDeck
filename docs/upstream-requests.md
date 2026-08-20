# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **The facade drops provenance the caller already knows.** Four write
  paths stamp `user` unconditionally even though the store layer under
  them is built to carry the real answer. `SetItemArt` and
  `SetEntityArt` take raw bytes and `probeArtImage` stamps `user`
  (`store/sqlite/curation.go`); `SetItemLyrics` forces
  `cp.Source, cp.Provider = model.SourceUser, ""`; and
  `Library.EditFields`/`EditManyFields` hardcode `model.SourceUser`
  (`waxbin.go`) although `store.EditItemFields` already takes a
  `source model.ProvenanceSource` and validates it with `ValidForField`.
  One ask, not four: carry provenance through the facade - a
  `Source`/`Provider` pair on `EditOptions` defaulting to `user`, which
  keeps every existing caller working, plus artifact setters that accept
  an already-stamped `*model.ArtImage` / `*model.Lyrics`.

  A smaller relative of the same shape, worth folding in: the facade
  cannot express "clear this cover and leave the pin as it stands".
  `SetEntityArt` writes the pin on every front-role write, so preserving
  one means reading `ArtLocked` first and passing it back - two calls,
  two transactions, and `force` set, which removes the guard that would
  otherwise catch the interleave. Two administrators editing one album's
  cover at the same moment silently lose one of the two pin decisions.
  A `ClearArt` that keeps the lock, or a lock argument that can say
  "unchanged", closes it.

  It matters because WaxDeck's per-item enrich-now writes covers through
  the first path and genres and book fields through the third, so the
  source mark reads "set by hand" for values a provider supplied. Two
  were reproduced against a running server: the editor's fetch-for-me
  answers `cover: itunes` and stores `source: user` with no provider,
  and the generated playlist mosaic - nobody's hand-set cover - answers
  `X-Art-Source: user` on the byte endpoint through `SetEntityArt`.

  Workaround today: enrichment run as the whole-library pass is stamped
  by `enrich.Service` itself and is right - a fetched cover comes back
  `source: enrichment, provider: itunes` with the URL it was fetched
  from, and lyrics `provider: lrclib` - as are the scan, sidecar and
  feed paths. Only the facade writes above are not. The playlist mosaic
  draws no mark today (no playlist surface passes one), so that path
  costs only the header's accuracy.

- **An unhashed cover is dropped by ingest and reported as success.**
  `attachEntityArtTxChanged` (`store/sqlite/art.go`) returns
  `(false, nil)` when `img.Hash == ""`, so a `*model.ArtImage` carrying
  perfectly good bytes but no content address is discarded silently:
  no error, no log, and the enrichment run that fetched it reports
  itself clean. Every one of WaxDeck's injected cover providers hit
  this - a picture downloaded from Deezer, iTunes, fanart.tv or
  Audnexus over somebody else's network, then thrown away - and it took
  instrumenting the provider chain to find, because nothing anywhere
  says it happened.

  The hash is derivable from the bytes the store already has
  (`art.Hash`), so the cheap fix is to compute it when the caller left
  it empty. Failing that, refuse the write: a caller handing over an
  image with no address has made an error, and an error is a better
  answer than a success that stores nothing. Workaround today:
  WaxDeck's `providers.coverImage` hashes and probes every cover before
  it leaves a provider, with a test per provider - but that is one
  repository remembering, and the next embedder to write a Provider
  re-lands the same silent discard.

- **No metadata-only art resolve.** `ResolveArt` reads the source bytes
  before it reports anything, so a caller that wants only the four
  provenance strings pays a full image read for them. The cheap path
  already exists inside the store - `artInChain` answers the level,
  source, provider, URL and timestamp without touching `art_source` -
  it is just not exported. An `ArtProvenance(ref, role)` beside
  `ArtRoles` would do it. Workaround today: WaxDeck's item, album and
  podcast detail reads call `ResolveArt` and discard the bytes, which is
  one wasted blob read per detail screen opened.

## WaxLabel
