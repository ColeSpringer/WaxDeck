# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.


## WaxBin

- **A name-keyed artist-art walk.** The artist-art backfill queue picks
  its subjects with a predicate that requires `artist.mbid`, which the
  identity phase fills only for artists MusicBrainz matched. An artist
  that never matched - a local band, a mis-tagged name, anything the
  library holds that the database does not - is never asked about, so
  the pass that exists to fill artist portraits skips exactly the
  artists most likely to be missing one. Wanted: the queue widened to
  artists without an mbid, asking capable providers by name the way the
  release-group passes already fall back to title and artist text.
  Shipped workaround: WaxDeck keeps its own artist-art sweep, narrowed
  to mbid-less artists and asking Deezer by name, with a 30-day miss
  memory; the catalog pass covers the matched rest. The sweep retires
  the day this lands, and its header comment says so.

- **Engine application of `Candidate.Fields`.** A provider can return
  scalar fields on a candidate, and the engine ignores them: the slot
  is documented as reserved for injected providers, and only WaxDeck's
  own per-item propose/commit path reads it. That leaves any field a
  provider knows unreachable from the catalog's own passes - a
  recording-target BPM from Deezer is the case that wants it, since
  the tempo is per track and no capability bit asks for one. Wanted: a
  `CapFields` bit and an apply pass for `Candidate.Fields` under the
  same fill-when-empty, lock-respecting, provenance-stamped rules the
  other capabilities get, and one that distinguishes an entity-rung
  field from an item one. That last part is not a nicety: WaxDeck tried
  to fill a release's year and label from Deezer and iTunes through its
  own per-item path and reverted it, because `year` is in
  `editKeyFields` (writing it on one member forks that member off its
  album) and `label` is an entity column whose lock an item's
  provenance map cannot see. Gating also matters: the library-wide genre
  pass stamps `Want: CapGenres` and reads only `cand.Genres`, so a
  provider that answers facts under that bit pays an extra request per
  release group for a value the engine discards. Shipped workaround:
  WaxDeck reads `Candidate.Fields` itself in its per-item
  propose/commit path, which is how an Audnexus book gets its publisher
  and year - an item-scoped field on an item somebody asked about, and
  nowhere else. A per-track value (Deezer knows a track's BPM, ISRC and
  explicit flag) is out of reach entirely: it needs a recording-target
  request, and no capability bit asks for one. BPM arrives from tags
  instead.

- **`ArtRoleInfo.locked` cannot say which pin set it.** The field is the
  effective lock on a slot: the entity's whole-artwork pin, which gates
  the front cover and enrichment's fills in every other role, or that
  role's own `art.<role>` pin. A reader cannot tell the two apart, and
  neither can `ArtLocked`, which reports the same effective value. So a
  client drawing per-role pin controls cannot say whether unpinning one
  will do anything, and cannot caption a slot as held by the cover pin
  rather than its own. Wanted: the role's own lock beside the effective
  one - a second bool on `ArtRoleInfo`, or the effective one plus its
  source. Shipped workaround: WaxDeck offers the per-role toggle
  unconditionally and lets the read tell the truth afterwards. An
  earlier attempt to infer the distinction from an empty slot was worse
  than not knowing: it disabled the toggle on exactly the
  cleared-and-pinned slot the control exists to release.

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
