# Upstream requests

The standing list of things WaxDeck wants from the sibling Wax repos.
Every entry is a candidate for whenever upstream work is next
scheduled; nothing here implies timing, and none of it is a WaxDeck
prerequisite (each entry notes the shipped workaround WaxDeck runs on
today). Agents: when you defer something because it needs upstream
support, add it here in the same change; do not bury it in a progress
note.

Earlier request batches (twenty items across three sprints, covering
the facade surface, metadata vocabulary, podcast preservation, and the
sidecar injection seam) all landed and are not repeated here.

## WaxBin

- **In-place playlist rule update.** The playlists facade has no way
  to change a smart playlist's rule under a stable pid, so WaxDeck
  reissues the pid and links the generations with `previousPid`
  (docs/adr/0006). An engine-side rule setter dissolves that whole
  seam: the reissue contract, the two-event sync story, and the
  client-side follow logic.
- **Relative date operators in the query engine.** Conditions compare
  absolute timestamps only, so a rule meaning "played in the last 30
  days" must be re-saved to move its cutoff. WaxDeck's contract
  documents the gap (docs/adr/0006).
- **Smart-list limit modes beyond item count.** Random-sample, total
  minutes, and total megabytes limits have no engine primitive; the
  API exposes a count limit only.
- **Entity-level library attribution.** Artists and albums cannot be
  attributed to library roots, so users restricted to a subset of
  roots lose entity search entirely (docs/adr/0004). WaxDeck filters
  at the item level and hides entity surfaces from restricted users.
- **Search match cap or rank pruning.** Worst-case common-term FTS on
  a 100k corpus costs hundreds of milliseconds because BM25 ranks
  every match; rare terms are single-digit. WaxDeck absorbs it with
  debounced search-as-you-type today.
- **Identifier format validation.** ISRC, ISBN, ASIN, and barcode
  values are accepted unvalidated; WaxDeck validates client-side, so
  other facade consumers get no protection.
- **Batch path lookup in pidpath.** Locate is per-pid; hydrating a
  large delta page does N lookups. Inside budget today, so this is an
  efficiency ask, not a correctness one.
- **Bulk art and lyrics presence.** The metadata-health sweep grades
  every present item and has no query field for "has front cover" or
  "has lyrics", so it does one `ResolveArt` and one `Lyrics` point read
  per music item; a 100k library is a few hundred thousand reads per
  sweep. A batch presence lookup (or presence flags on the item view /
  query engine) collapses that to one pass. The sweep is a paced,
  warming-up-gated background job today, so it is an efficiency ask, not
  a correctness one.
- **Bulk active-playback lookup.** Unsubscribing a podcast with
  download removal checks whether each downloaded episode is currently
  playing for any user, one `Playback().State(userPID, epPID)` per
  (episode, user) pair. Fine at self-host scale (few users), but an
  `ActiveStatesForEpisodes([]epPID)` (or a users-crossed variant) makes
  it one query. Efficiency ask; the action is rare and user-triggered.
- **Podcasting 2.0 funding, soundbites, medium, and person tags.**
  The feed parser skips them, so WaxDeck cannot surface them.
- **Chapter marks on multi-file books.** Chapters exist only for
  single-file books; a multi-file book falls back to its part
  boundaries as the navigation grain.
- **Sort names beyond artist and album.** Those are the only two
  editable sort fields; composers and book authors have none.
- **More than one artwork slot.** Item and entity art hold a single
  front cover; back covers, disc art, booklets, and artist
  backgrounds have nowhere canonical to land, so WaxDeck's provider
  chain can only fill the one slot.
- **A query surface for per-file diagnostics.** Persisted diagnostics
  are readable only through per-item Audit checks; the health
  dashboard wants to query and facet them across the library instead
  of sweeping item by item.
- **Entity facets in the item query grammar.** Items cannot be
  filtered by artist or album entity pid, only by display string,
  which is why the Subsonic surface mints its artist and album ids
  from strings. A real entity facet would retire the minted ids. The
  discovery and sharing surfaces added two more consumers: instant
  mixes cannot take an album pid as a seed (clients seed with a
  member track instead), and share links cannot target an album
  (users share a playlist of its tracks instead). Artist seeds work
  today only through a full artist facet scan that maps pid to
  display name; an entity lookup or entity-pid filter retires that
  scan too.
- **Runtime library-root addition.** Roots are fixed at Open
  (RelocateRoot exists for moving one, nothing adds one), so creating
  a new library today means editing the server's root flags and
  restarting; the admin-and-ops slice wants an admin creating a
  library at runtime. The streaming sidecar's matching root config
  has the same shape, so this ask spans both repos if it lands.
- **Per-field mutation stamps on play state.** The playback record
  carries one UpdatedAt (bumped by every checkpoint) and a StarredAt
  that zeroes on unstar, which makes offline-replay guards for stars
  and ratings unimplementable against it; WaxDeck mirrors its own
  per-field stamps in a play_state_stamps table. Upstream stamps
  would retire the mirror.
- **Scoped or per-item enrichment.** Enrich runs whole-catalog with a
  Force flag and a Limit; there is no way to re-enrich one item or one
  entity. WaxDeck's editor runs its own injected providers directly
  for the per-item fetch button, which works but bypasses the engine's
  provenance bookkeeping for the built-ins (CAA, ListenBrainz, LRCLIB
  cannot be invoked per item at all).
- **A multi-item edit batch with per-item field maps.** EditManyFields
  applies one value set to every item, which fits bulk retags but not
  a matching engine applying a different title and track number to
  each member of an album unit. The apply path loops per-item edits
  (atomic per item) and locks as it goes; an atomic per-unit batch
  would make "a unit never half applies" a transaction instead of a
  convention.
- **An exact-content-hash lookup on the facade.** Files carry content
  and essence hashes, but nothing resolves a hash to an item, so the
  upload surface's pre-transfer duplicate warning (hash sent before
  bytes move) can only answer from its own upload history. The
  completion-time essence check covers correctness; the ask is purely
  to make the early warning as good as the late one.
- **Age-scoped trash purge.** The trash facade offers list, restore,
  and EmptyTrash (everything at once); WaxDeck's admin surface wants a
  retention policy (purge entries older than N days), which needs a
  per-entry purge or an age-scoped empty. Until then the trash UI
  ships without automatic retention; empty-everything is the manual
  answer.
- **A level-scoped artwork read.** ResolveArt walks the fallback chain
  (item, album, release group, artist), so a caller cannot tell
  item-own art from inherited art; the editor's has-artwork indicator
  and the health sweep's missing-art rule both read true for an item
  whose album carries the only cover. A read that reports which level
  supplied the bytes (or an item-only probe) would make both honest.

## WaxFlow

- **Detector version in caps.** Skip-map caches can only refresh on
  essence change because learning the current silence-detector
  version requires running a job. A caps-level version report lets
  the cache invalidate on detector upgrades.
- **A jobs surface in the client package.** The published client
  deliberately ships no jobs API, so WaxDeck's bridge carries a
  raw-HTTP jobs client. Listed so the decision stays recorded: if the
  omission is permanent policy, this entry can be closed as
  wont-do and the bridge client becomes the documented answer.
- **Sample windows on timeline members.** Timeline srcs take whole
  files only, so a CUE-carved virtual track cannot join a gapless
  timeline (a queue holding one falls back to per-item URLs, and the
  timeline mint endpoint answers conflict for it). A per-member
  `from`/`to`, mirroring what `/stream` already accepts, would let
  carved rips ride gapless queue playback like everything else.

## Recorded upstream non-goals

Deliberate upstream decisions WaxDeck designs around; listed so they
are not re-filed as asks:

- Episode tag write-back is refused (episodes are not tagged files;
  edits stay DB-only).
- WaxTap rips refuse tag write-back and export no fingerprint
  (descriptive-rung matching only); WaxDeck stamps provenance via
  WaxLabel at ingest instead.
- Secret operations are not proxied to the standalone CLI; WaxDeck
  owns the entire secret lifecycle.
- Decoding the vendored exotics (WMA, APE, WavPack) stays out of
  WaxFlow; the few samples exist to prove graceful failure.
- fpcalc stays: it is the one runtime subprocess (WaxBin acoustic
  fingerprinting), kept by decision. The ffmpeg era is already over
  in every runtime path; ffmpeg appears only in WaxFlow's test
  utilities for cross-validation and a doctor diagnostic. Do not
  file native fingerprinting as an ask.
