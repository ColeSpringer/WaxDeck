# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **A re-ask TTL on a missed art marker.** The artist-art and
  auxiliary-art backfills mark a target nothing answered for, and the
  marker is a plain existence check with no expiry: an artist Deezer
  does not hold today is never asked about again, however long the
  catalog runs. Providers gain images, so "nothing found once" is not a
  durable fact the way a match is. Wanted: an age on the marker, so a
  walk re-asks a miss after some window (a config knob, or a fixed one
  in the tens of days) without a forced run re-searching everything.
  Shipped workaround: none that is cheap - a forced enrichment run
  re-asks every target, matched ones included, so WaxDeck documents the
  rule in the curation doc rather than working around it.

- **A barcode on the release-rung art request.** The release-rung art
  request carries the group's MBID, title and artist and no printed
  identifier, so a provider keyed on one cannot tell which pressing is
  being asked about - and a picture chosen by title search on that rung
  is the wrong edition's as often as not, which is the failure the rung
  exists to avoid. The fields walk already carries `Barcode` on the same
  target for exactly this reason. Wanted: `Barcode` filled on the
  release-rung art request too, so a UPC-keyed provider can answer for
  the pressing rather than for the record. Shipped workaround: Deezer
  declines art on that rung and answers only its fields, so a
  per-edition cover comes from the Cover Art Archive alone.

## WaxTap

- **A bounded enrich option on `EnumerateOptions`.** Enumeration runs
  its own enrichment internally, and that loop is the only place the
  metadata-throttle rotation happens - a throttled response there is
  minted as `ErrTemporarilyUnavailable` and retried against a rotated
  identity. A caller that wants the same protection for its own budget
  ("enrich the first n entries") has no way to ask: it must call `Info`
  per entry outside enumeration, where a throttle arrives as a plain
  `ErrVideoUnavailable` indistinguishable from a removed video, with no
  rotation behind it. Wanted: a bounded enrich option on
  `EnumerateOptions` (enrich the first n entries) so a caller's budget
  runs inside the loop that already knows how to rotate, without
  exporting identity rotation itself. Shipped workaround: WaxDeck
  mirrors the unexported throttle shape (a `*waxerr.PlayabilityError`
  with status `UNPLAYABLE` wrapping `ErrVideoUnavailable`), keeps such
  an entry unenriched rather than unavailable, and stops spending the
  run's budget. That recovers the entries, at two costs this ask would
  remove: the predicate is a copy of an unexported one, which drifts
  silently the day the shape changes, and a throttled run enriches
  nothing at all where a rotation would have enriched everything.

## WaxSeal

- **A keyed daemon fails its own image healthcheck.** `/ping` is
  tenant-gated and the image's baked-in healthcheck
  (`waxseal ping --addr 127.0.0.1:4416 --strict`) sends no key, so the
  daemon answers its own probe 401 the moment it is started with
  `--tenant-keys`. Every operator who keys the sidecar has to override
  the healthcheck to fix it. Wanted: the image's own probe carrying a
  key - an entrypoint that passes the daemon's single tenant key, an
  environment variable the healthcheck reads, or a loopback exemption
  on `/ping` so a local liveness probe needs no tenant at all. Shipped
  workaround: WaxDeck's compose replaces the healthcheck with the same
  probe plus `--key ${WAXDECK_SEAL_API_KEY}`, which works because the
  `ping` subcommand does take a key; what is missing is the image
  doing it without being told.

## WaxLabel

(nothing outstanding)
