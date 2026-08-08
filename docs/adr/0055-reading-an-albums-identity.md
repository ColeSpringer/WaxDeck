# 55. Reading an album's identity

Date: 2026-08-08

## Status

Accepted.

## Context

The catalog keeps five columns on the album entity that describe the
edition rather than the file: barcode, label, catalog number, media, and
country. WaxDeck reached them two ways already - smart rules filter on
`albumBarcode` and its four siblings, and an entity edit writes them -
but there was no way to *read* them.

Upstream keeps them off `model.ItemView` on purpose: the item row budgets
its columns, and these are entity-scoped. So the album screen, which
derives its whole header from the tracks it lists, could reach the title,
the artist, and the year and nothing else. `AlbumFacts.of` carried the
comment "there is no album endpoint to ask", which was true.

## Decision

**`GET /albums/{pid}` in the library tag**, over `Library.EntityByPID`,
shaped like `GET /items/{pid}`. A pid that is not an `al-` is
`not-found` rather than a wrong-shaped answer, and the entity's member
libraries gate visibility exactly as they do for a search hit.

The path lives in `library.yaml` while `playback.yaml` already declares
`/albums/{pid}/play-state` and friends. Those are per-user state writes
and these are catalog reads; the paths are distinct and the bundler
merges them.

`AlbumDetail` carries the identity five plus the counts and links the
entity already has. **No `artistPid`**: the catalog hangs an album's
artist off its release group rather than off the album, the album screen
derives artists from its tracks, and the pinned shelf does that hop
server-side. `GET /artists/{pid}` is not added for the same reason -
nothing needs it.

**The editor is a screen, not a panel.** `/metadata/:pid` branches on the
pid prefix: an `al-` opens `AlbumEditorScreen`, anything else opens the
per-item editor as before. A panel inside the item editor was the
alternative and is worse: the two halves write through different
endpoints with independent failure, so one Save over both would report
success for a pair of calls of which one failed.

The editor writes through the `editEntity` and `getEntityCuration`
endpoints that already existed and had no caller. Only changed fields are
sent, because the endpoint locks what it is sent and a one-word change
must not lock the other four.

**Display is verbatim; validation belongs to the write path.** A scan
stores the tag as written and an edit normalizes, so the two disagree by
policy: `entity info` shows a country an edit would refuse ("US &
Europe"). The screen shows what is stored and never client-validates,
and `editEntity`'s prose now says so - it also lists `media` and
`country`, which the catalog has always accepted and the spec omitted.

The identity block on the album screen is **not** behind the
technical-details setting that governs the codec chip beside it. That
setting draws the line between what the file is and what the release is,
and a catalog number is printed on the sleeve.

## Consequences

Most releases carry none of the five, so the block renders nothing at all
rather than five blank labels. The absence is not something a listener
can act on, and the editor is reached from the overflow either way.

A failed read is silent - the block disappears, like the "Appears on"
shelf above it. Identity is an extra and the screen is complete without
it. The read does not retry on a 4xx: an album the server does not have
will not appear on the fourth ask, and Riverpod's default backoff would
otherwise leave a header quietly re-asking forever for a pid that will
never resolve.
