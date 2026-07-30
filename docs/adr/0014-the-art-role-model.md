# 14. The art-role model and level-scoped reads

Date: 2026-07-23

## Status

Accepted.

## Context

Item and entity art held a single front cover. Back covers, disc art,
booklets, and artist backgrounds had nowhere to land, and the provider
chain could fill only the one slot. Two facts compounded it:

- The read and write surfaces exposed no artwork slot at all, so even a
  client that fetched a back cover from a provider could not store it.
- `ResolveArt` walks the fallback chain (item, album, release group,
  artist), so a caller could not tell an item's own cover from one it
  inherits from its album. The editor's has-artwork indicator read true
  for an item whose album carries the only cover, and there was no honest
  way to say "this track has no cover of its own."

Upstream WaxBin resolved both: `ArtRole` is a closed slot vocabulary
(`front`, `back`, `disc`, `booklet`, `background`); `ResolveArt`,
`SetItemArt`, and `SetEntityArt` take a role; `ArtRoles` reports the
slots an entity holds at its own level with their dimensions; and
`ArtBlob.Level` names which chain level answered a resolve. A `has_art`
query field also landed, but it counts an item's **own front cover
only** and reads 0 for inherited album art, by deliberate upstream
design.

## Decision

Adopt the role model across the contract:

- `GET /items/{pid}/art` takes an optional `role` (default `front`). Only
  `front` walks the fallback chain; the auxiliary slots resolve at the
  requested entity's own level and 404 when it holds no image there.
- The artwork write endpoints (`PUT`/`DELETE /items/{pid}/artwork`,
  `PUT /entities/{entityType}/{entityPid}/artwork`) take a `role`. Only a
  front cover writes back into files; the auxiliary slots are
  catalog-only.
- `GET /items/{pid}/art-roles` lists the slots an entity holds at its own
  level, each with format and pixel dimensions. It is the own-versus-
  inherited answer the front-cover read cannot give.
- The editor gains `hasOwnArtwork` alongside `hasArtwork`: the former is
  the item's own front cover (`ArtBlob.Level == the item's own level`),
  the latter the resolved cover including an inherited one.

**The health art rules stay on `ResolveArt`, not `has_art`.** This is the
non-obvious call. `has_art` is own-front-only, so a missing-art rule
built on it would flag every track that correctly inherits its album's
cover - a false positive on a healthy library. "Missing art" means no
cover anywhere in the chain, which is exactly what a `ResolveArt`
not-found reports; "small art" reads the resolved cover's dimensions,
which `ResolveArt` now returns. Both rules are already correct and
chain-aware. Moving them onto the own-only field to save a resolve would
regress correctness for an efficiency gain, so it is declined. The
own-versus-inherited distinction the field expresses is surfaced where it
belongs - the editor's `hasOwnArtwork` and the `art-roles` listing - not
folded into the health sweep.

## Consequences

- The small-artwork health rule is a live rule (upstream now reports
  resolved-art dimensions), closing that deferral.
- Filling the auxiliary slots from the provider chain does not ship here:
  a provider candidate carries a single cover image, so per-role art
  needs the candidate/provider model extended first. Tracked in
  `docs/deferred-work.md`.
- The client can read and write every slot, but the app ships only the
  own-versus-inherited indicator; a full multi-slot upload editor is a
  net-new surface, tracked in `docs/deferred-work.md`.
- A future release-group- or genre-level slot, or a portrait role
  distinct from `background`, would extend the closed vocabulary and is
  an upstream ask, not buildable here.
