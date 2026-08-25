# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **Album rename-in-place.** Editing a release-keying field (`album`,
  `album_artist`, `year`) on an unidentified album's members re-resolves
  each member's entities in the edit transaction, so the release regroups
  onto a fresh `al-` pid and the old entity is left as a ghost until the
  orphan GC sweeps it. Track pids and playlist membership survive, but
  everything hung on the album pid - entity curation, artwork and its pin,
  a client's open route - is orphaned. Wanted: a facade verb that renames
  a release in place (rewrite the members' keying fields and the entity's
  identity together, keeping the pid and moving curation/art), or an
  album-key recompute that reuses an existing entity row when every member
  moves at once. Shipped workaround: the release workbench is built to the
  regroup - the bulk-edit response reports the album the edited members
  landed on (`resultingAlbumPid`), the rewrite section warns before it
  writes, and the workbench follows the tracks to the new entry -
  and `TestBulkEditAlbumFieldsRegroupsTheRelease` pins the behavior it is
  built to. Entity curation, artwork and pins on the old entity are still
  orphaned by the move, which is what rename-in-place would keep.

- **Per-role candidate art on the enrichment port.** `enrich.Candidate`
  carries one `Cover *model.ArtImage`, so a provider can only ever
  answer with a front cover, even though the art model has five roles
  (`front`, `back`, `disc`, `booklet`, `background`) on both the read
  and write surfaces. fanart.tv serves per-role assets natively - an
  artist thumb against a scenic artist background, cdart for the disc
  slot - and a provider holding all of them has one field to put one
  of them in. Wanted: the candidate model extended to carry role-tagged
  art (a `map[model.ArtRole]*model.ArtImage`, or a role field on a
  repeated image), with the engine's apply pass filling each offered
  role under the same fill-when-empty, lock-respecting,
  provenance-stamped rules the front cover gets; `Cover` can stay as
  the front alias so existing providers are untouched. Shipped
  workaround: enrichment fills `front` only, and the auxiliary slots
  are readable and hand-settable through the artwork endpoints. The
  planned artist-image sweep is unaffected - it writes portraits at
  `front` through the entity-artwork surface, which is the slot both
  artist read surfaces resolve - so this ask gates only the auxiliary
  roles (backgrounds, disc art), which sit empty unless a person fills
  them.

- **Capability-scoped provider calls on the enrichment port.**
  `enrich.Request` never says which capability the caller is
  gathering, so a multi-capability provider must answer everything on
  every call: the engine's separate `gatherCover` and `gatherGenres`
  passes each invoke a Discogs-shaped provider (CapCover|CapGenres) in
  full, and the genres pass downloads a cover image nobody reads -
  once per genre-less release group, up to 8 MiB each, twice per group
  when both passes run. Wanted: an additive want field on `Request`
  (an `enrich.Capability`, zero meaning everything so existing
  providers and embedders are untouched), set by the engine in each
  gather pass, so a provider skips work whose result only other
  capabilities would read. Shipped workaround: WaxDeck's own per-item
  paths type-assert a `ScopedEnricher` refinement
  (`EnrichScoped(ctx, req, want)`, implemented by Discogs and
  Audnexus) and pass the want themselves; the catalog's whole-library
  pass cannot, and keeps the wasted fetches until this lands. The
  refinement retires into a plain `req.Want` read the day it does.

## WaxLabel

- **Map the MP4 `rtng` advisory atom to a tag.** iTunes stores the
  explicit/clean advisory in the structured `rtng` atom (one byte:
  1 explicit, 2 clean, 0 none; a legacy 4 also meant explicit), and
  the mp4 codec never projects it: `mp4Text` has no entry, nothing
  decodes it, and the atom survives only as a preserved unknown item
  on rewrite (the verbatim carry in `internal/mp4/encode.go`). ID3 and
  Vorbis files carry the same fact as an `ITUNESADVISORY` custom tag,
  which reaches the catalog through the freeform/TXXX long tail - so
  an iTunes-bought M4A is the one common case where the advisory is in
  the file and never leaves it. Wanted: decode `rtng` into the
  `ITUNESADVISORY` custom tag on read, keeping the numeric values as
  they stand (consumers parse `1` as explicit and treat everything
  else as unasserted), and write it back from that tag on MP4 where
  the edit surface allows. Shipped workaround: none is possible
  downstream of the parser - the byte never leaves the file. The
  planned OpenSubsonic `explicitStatus` emission for music keys on the
  `ITUNESADVISORY` tag, so `rtng`-only files stay uncovered until this
  lands; emission is positive-only, so that absence reads as
  unasserted rather than wrongly clean.
