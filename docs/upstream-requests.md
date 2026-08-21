# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **`ExportNSP` cannot say what it would drop.** The converter is
  all-or-nothing in both directions, which is right for the default:
  half a rule is a different playlist. But it leaves no way to offer
  "export what maps and record the rest", because a caller cannot ask
  what stopped the export without re-implementing the field and
  operator tables to find out - which is the duplication the shared
  converter exists to prevent. A report alongside the refusal (the
  fields, operators, and modes with no `.nsp` form in this query) would
  let a caller present the loss and let the person decide, with one
  table still owning the answer.

  Answered upstream by `CheckNSPExport`/`CheckNSPImport` and the
  `ExportNSPPartial`/`ImportNSPPartial` pair; the entry stands until
  WaxDeck adopts them. Workaround today: an import refusal composes
  every gap the check reports, and the export still refuses with
  WaxBin's own first-offender sentence and offers nothing partial.

- **No art setter takes an already-stamped `*model.ArtImage`.** The
  provenance ask asked for two things, and one landed: `ArtEditOptions`
  carries the attribution, but `SetItemArt`/`SetEntityArt` still take raw
  bytes and re-derive the rest through `probeArtImage`, which now refuses
  an image `art.Describe` cannot name instead of dropping it. A producer
  that already knows the format from the transport - an HTTP `Content-Type`
  on a fetched cover - has nowhere to put it, so the same picture stores on
  the whole-library pass (which hands `enrich.Service` the whole
  `*model.ArtImage`) and is refused with `CodeInvalid` on a per-item write.
  A `SetItemArtImage`/`SetEntityArtImage` pair, or an `Image *model.ArtImage`
  on `ArtEditOptions` that wins over the raw bytes, closes it and makes the
  two paths agree.

  Workaround today: `providers.coverImage` fills the format from the media
  type, which serves the whole-library pass; WaxDeck's own enrich-now
  button passes `cand.Cover.Data` and loses it. The gap only bites bytes
  that neither decode nor magic-sniff - a truncated image, or an exotic
  container this build does not know - so a run reports "cover: no provider
  hit" for a picture it did fetch.

- **The provenance vocabulary cannot say "the server composed this".**
  `model.ProvenanceSource` is `tag|user|enrichment|sidecar|feed|organize`,
  and a generated playlist mosaic is none of them. WaxDeck composes one
  from the members' covers and stores it through `SetEntityArt`, which
  leaves two answers: record `user`, which claims a hand chose an image
  nobody ever saw before it was drawn, or record nothing and fail
  `ValidForArt`. It records `user`, so `X-Art-Source: user` on a
  playlist cover is a picture the server made. A `generated` value (or
  whatever names "this catalog's own derivation" - a mosaic is unlikely
  to be the last one) closes it, and the pairing rule writes itself: no
  provider, no source URL, same as `user`.

  Workaround today: the mosaic is written with `Lock: model.LockOff`
  and no source, so the store's `OrUser` default stamps `user`. No
  playlist surface draws a source mark, so the cost is the byte
  endpoint's headers alone - but they are the surface another client
  reads, which is exactly who would be misled.

## WaxLabel
