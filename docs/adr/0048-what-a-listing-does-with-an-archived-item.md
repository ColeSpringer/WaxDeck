# 48. What a listing does with an archived item

Date: 2026-08-05

## Status

Accepted. Amends ADR-0040, which owns the `/library/items` and
`/library/browse` filter and cursor design.

## Context

Deleting to trash archives an item: `state` becomes `archived`, the file
row goes, and the history stays so a restore can put it back. No item
read path filtered on state, so every listing kept answering with it.
Delete a track and it stays in the library screen, the browse lists, the
facet counts, the offline mirror, the home shelves, the instant mix, a
public share, the Subsonic index, and search. Reproduced directly: delete
to trash, poll the listing for twenty seconds, and the item never leaves.

A cue split is where it reads worst, because the archived carvings sit
beside their replacements under the same two titles, so nothing looking a
cue title up in the listing can tell the pair apart.
`TestCueSplitEndToEnd` asks by pid for exactly that reason, and had two
comments encoding the bug as expected behaviour.

The precedent for the answer was already in the tree. `health.go:254`
filters its grading query to `StatePresent`, with the comment that
archived, missing, and remote items have no local file to grade. What was
missing was the decision one level up: which of the four states belong in
a listing at all, and which surfaces are listings.

There are twenty-six places in `server/internal/service` that construct
an item or track query, and about half are user-facing listings. Writing
the predicate at each is how nine of them get missed, and nothing would
catch it.

## Decision

**`present`, `remote`, and `missing` belong in a listing. `archived` does
not.**

`remote` is an episode nobody has fetched and `missing` is a file the
last scan could not find; both are items the library still holds a claim
on, and both are things a listener asks about. `archived` is something
the listener deleted. It is kept only so a restore is possible, and the
trash listing is where it is visible.

### One helper, not twenty-six predicates

`Library.visibleItems()` and `Library.visibleTracks()` return the base
`*query.Builder` for their entity with the state predicate already
applied. Every catalog item read that is a listing goes through them.

The invariant spans two dozen call sites, so it is enforced rather than
remembered: `server/cmd/querylint` fails `make lint` on a bare
`query.New(query.EntityItems)` or `query.New(query.EntityTracks)` in
`internal/service` outside the helpers and the allowlist below. The
repo already ships a custom vet for exactly this shape of rule
(`spawnlint`, for hard rule 7), so the mechanism and the precedent both
existed.

### The exception list

These construct an item or track query and deliberately do not filter.
They are audits, sweeps, dedupe units, and coverage counts: surfaces
whose job is to see everything the catalog holds, including what was
deleted. `querylint` allows them by file and function, and this list is
the reason, so the next reader does not "fix" them:

| Site | Why it sees everything |
|---|---|
| `health.go:254` | already filters to `present`; grading needs a local file |
| `health.go:398`, `:424`, `:488`, `:776` | library health audit, organize plan, one-item issue drill |
| `genres.go:521` | genre vocabulary coverage |
| `matching.go:279` | album sibling lookup for matching |
| `enrichment.go:125`, `:134`, `:138` | enrichment coverage counts |
| `tools.go:899`, `:1025` | tool task selection over the whole catalog |
| `organize.go:90` | organize plans over everything on disk |
| `visibility.go:336` | path-prefix sweep for library attribution |

### The surfaces that hydrate by pid

`querylint` sees `query.New` and nothing else, so a surface that resolves
pids through `Get`/`GetMany` is invisible to it. Four filter, and three
deliberately do not; both halves belong here, because a list that names
only the ones that filter reads as though the rest were overlooked.

Filter:

- `playback.go` `RecentlyPositionedItems` hydrates pids from WaxDeck's
  own position stamps, and feeds the Subsonic resume surface
  (`adapter/subsonic/write.go`).
- `playlists.go` `PlaylistItems` and `shares.go` `playlistMemberViews`
  hydrate members through the catalog's playlist surface, which evaluates
  a smart rule internally. Both honour the `state` exemption below, and
  they have to honour it identically: a share publishes the owner's list
  rather than a second reading of it.
- `discovery.go`'s similarity neighbours arrive as pids from the
  similarity index, and feed the instant mix.

Do not:

- `stats.go` `groupTotals`. The listening report already keeps an item
  the catalog has dropped entirely, under an empty title, on the stated
  rule that time is never silently dropped from a per-item list. Dropping
  archived items would contradict that rule while leaving the harder case
  it was written for in place, and for the aggregate kinds the time an
  archived track earned an artist is still time that artist was listened
  to.
- `discoveries.go` walks the change log to open review units. A worker,
  not a listing.
- `playlistart.go` draws a playlist's generated cover from its full
  member list, deliberately (its own comment: the cover belongs to the
  playlist rather than to whoever is reading it).

### Item resolution by pid is untouched

The predicate goes in the query paths only, never in `getItem` or
`getVisibleItem`. Roughly forty-five call sites hang off `getVisibleItem`
and several must keep resolving an archived pid:

- the trash listing hydrates through `l.lib.Get` (`service/trash.go:55`),
- `DeleteItems` resolves each pid before permanently deleting it
  (`trash.go:195`),
- an offline client asks about a download it already holds
  (`download.go:68`).

An archived item is still a thing you can name. It is not a thing a
listing offers.

### Browse gives up its unfiltered short-circuit

`Browse` passed a query to the catalog only when the caller's filter
narrowed it (`reads.go:166-172`), because a built query always names its
entity, so an unconditional one would never be the zero `Query` the
catalog short-circuits on, and the catalog's `userStateJoin` validates a
non-empty `UserPID` even when the compiled query needs no user join.
`TestUnfilteredBrowseIgnoresAStaleUser` pinned that: an unfiltered browse
ignored a stale catalog user pid where a filtered one rejected it.

The state predicate is always present, so the short-circuit condition can
no longer be "did the caller narrow it". Browse now passes the query
unconditionally, and a stale catalog user pid is rejected uniformly
rather than only on filtered lists.

The alternative was pushing the state filter as a `read.BrowseOptions`
field, which is an upstream change and buys little: `ItemFilter` can only
name `kind`, the six entity-keyed facet fields, `year`, and a custom tag
key (`facetFilterField`, `applyFacetFilter`), none of which is a per-user
field, so the newly unconditional query still never needs the user join.
The lookup it adds is validation only. Uniform rejection is also the more
defensible behaviour: silently ignoring a bad user pid on one list while
rejecting it on the next is the surprising half, and a catalog user pid
that does not resolve already breaks star, rating, playback state, queue,
and entity state for that account.

### `cursorVersion` stays `"s1"`

The scope tuple a cursor hashes over is unchanged, so no envelope needs a
new version and no stored queue turns into a scope mismatch.

That is worth stating with its reason rather than asserted, because a
cursor minted before this change now points into a result set with rows
removed. It is benign because these are keyset cursors: they resume after
a remembered position rather than indexing into a count, so removing rows
shortens the remaining pages and never shifts a boundary onto the wrong
row. An offset cursor would have needed a version bump.

### Search filters after the fact, and takes the cap consequence

`read.SearchOptions` has no query field, so no predicate can reach the
FTS join. Item hits are dropped in `convItem` (`reads.go:379-401`)
instead. The `SearchOptions` widening is filed in
`docs/upstream-requests.md` as the real fix.

The per-group cap is applied by FTS before `convItem` runs, so archived
hits consume slots and a group comes back short. `convItem` already
dropped hits for library visibility, subscription scope, and the content
deny-list, so the shape is not new - **but the exposure is, and it is
worth being exact about rather than filing this under "same as the
others".** All three of those short-circuit for a full-visibility caller
(`itemVisible` returns true on `AllLibraries`, `contentAllowsPID` on
`Admin`, and subscriptions only scope episodes), so on a
single-administrator install, which is most of them, a search could not
come back short at all before this. The archived filter has no such
exemption.

Nor is the damage one stray hit. The rows most likely to be archived are
the ones a bulk delete just retired, and they match their own names
best, so they take the *top* of the ranking: deleting an album and then
searching its name can fill the whole page with hits that are then
filtered away, and the group comes back **empty**. That is not a short
page, it is a wrong answer, and
`TestSearchFillsItsGroupsAroundTrashedHits` reproduces it (0 of 3
survivors returned with the mitigation removed).

So `Search` runs a second pass when the first came back short:
`searchPass` reports whether any group was cut off by the cap *and* lost
hits to filtering *and* is still short, and only then does it re-ask with
`searchWidenFactor` times the per-group limit and truncate back to the
contract's cap. Conditional rather than a blanket over-fetch, because
the pass that pays for it is the rare one: multiplying the fetch on every
keystroke of a debounced field, and with it the hydration batch
`archivedHits` runs, would be paying constantly for a trash that is
usually empty - and a fixed multiplier would still not fill a group the
trash had emptied outright.

It is a mitigation, not a guarantee: a trash holding more than
`searchWidenFactor` times the limit worth of better-ranked matches can
still shorten a group, and the guarantee needs the upstream predicate.
`searchMaxCandidates` (5000) is unchanged and bounds the ranked pool
either way. Search returns no cursor at all (`api/spec/library.yaml`),
so there is no page boundary to drift.

**`convEntity` filters too, by one batched facet per kind.** Artist and
album hits come from entity FTS with no item join, so post-hoc filtering
cannot use the item's state the way `convItem` does. Left alone, an
artist whose every track is archived stays a search hit and opens onto an
empty facet drill, while the browse index drops the same artist because
`facetScopeQuery` aggregates over items. Search and browse would then
disagree, which is the same class of inconsistency
`TestFacetDimensionsDrillToTheirCount` exists to catch, on a different
axis.

The check is one `Facet` call per kind over the hit pids
(`artist_pid`/`album_pid` in an `Or`, with the state predicate), grouped
by the dimension the drill already pairs with. It answers which of the
hits still have a live member in one query rather than one count per hit,
and it costs two extra queries per search, including for full-visibility
callers, who skip the entity attribution batch entirely today.

### The sync mirror filters in one place

`itemSyncEntry` (`sync.go:555`) builds the upsert entry and is called by
both the snapshot (`sync.go:493`) and the delta (`sync.go:692`), so the
filter belongs there. Filtering only the delta would tombstone correctly
for a running client and still hand a fresh mirror every archived item on
first sync, shedding them only if some later change happened to touch
that pid.

Archiving emits `OpUpdate`, not `OpDelete`
(`waxbin/store/sqlite/trash.go:144`), so an item that hydrates as
`archived` is treated as a tombstone inside `itemSyncEntry` rather than
minting a new event kind. A restore re-scans to `present` and re-adds by
the same path. The snapshot drops the tombstone instead of emitting it: a
fresh mirror has nothing to tombstone, and emitting one per archived item
would pad first sync with deletes for rows the client never had.

**The download and its cached artwork stay.** Trash is reversible on both
sides, and deleting a user's downloaded file because of a server-side
trash operation would turn a reversible server action into an
irreversible client one: restore would put the item back and the bytes
would have to come down again. `download.go:68` already keeps resolving
an archived pid for exactly this reason, so an offline client can still
ask about a download it holds.

A delete that bypasses the trash is the event that genuinely orphans the
file, and it does reclaim both halves. That needs the two tombstones to
be told apart, which is what this ADR's own change made necessary:
before it, a `delete` entry meant only "the catalog dropped this", and a
client could act on it unconditionally. So `CatalogSyncEntry` gains a
`reason`:

| `reason` | What happened | What a client reclaims |
|---|---|---|
| `removed` | the server cannot put it back: the audio was deleted outright, or the catalog dropped the row | the download and its pinned artwork |
| `hidden` | it left this caller's view and is recoverable: trashed with its undo journal, a file re-homed out of their grant, or a read that failed this poll and will not the next | nothing |

An unsubscribe sends no tombstone at all, and is deliberately not on that
list: it bumps the caller's grant epoch, which retires their cursors and
forces a clean re-mirror.

**The reason is decided before the visibility check, not after, and the
order is load-bearing.** Archiving is what an item does when it loses its
last file, so an archived view carries no path - and `viewVisible`
answers false for every caller without `AllLibraries` the moment the path
is empty. Decided the other way round, every restricted caller took the
visibility branch, every tombstone they saw said `hidden`, and the whole
reclaim worked for administrators only.

The field is deliberately **not** a spec enum. A closed one generates a
Dart `EnumClass` whose serializer throws on an unrecognized wire value,
so adding a third reason later would fail the page's deserialization and
stop sync outright rather than degrade to the conservative half. `op` is
a bare string for the same reason.

**The catalog cannot answer which one it is, and that is the part worth
writing down, because "the row is gone" is the obvious first guess and
it is wrong.** `model.DeleteMode` says every mode "preserves the logical
item, archiving it when it loses its last file": trash and permanent
alike emit `OpUpdate` to `archived`, and neither ever drops the item
row. What differs is whether the bytes can come back, which the trash
journal answers. So `restorableItems` reads the active journal and
`tombstoneReason` calls an archived item `hidden` when its pid is in
there and `removed` when it is not. A journal read that fails answers
`hidden`, because keeping bytes that could have gone is cheaper than
deleting bytes that should have stayed.

That read is lazy, and deliberately: the journal query carries no `LIMIT`
(upstream adds one only for a positive limit) and the overwhelmingly
common delta page is all upserts with no tombstone on it at all. Reading
eagerly would put a full unbounded scan on every poll of every mirrored
device to answer a question most pages never ask, so `restorableItems`
hands back a thunk that reads at most once and only when something asks.

Both tombstone the mirror row identically; only the reclaim differs.
Additive and open, like `op`: a client that does not recognize a value
treats it as `hidden`, so an old client and a server too old to send the
field both land on the half that deletes nothing.

The client half is a stream, not a call: `SyncEngine.itemsRemoved`
publishes the `removed` pids and `sync_binder.dart` reclaims through
`DownloadsController.remove`, which is the one call that drops both the
audio and the artwork pin. The mirror stays `waxdeck_data`'s job and the
downloads store stays the app's.

**One case answers `hidden` and later stops being true**: an item
trashed and then purged was tombstoned when it was trashed, and emptying
the trash is not itself a catalog change, so no second entry follows it
and the client keeps those bytes. Tracked in `docs/deferred-work.md`;
closing it needs a signal the catalog does not currently emit.

### Smart playlists keep `state` as a rule field

`playlists.go:221` deliberately exposes `state`, documented as "present,
archived, remote, or missing", reachable through
`/playlists/rule-fields`, and part of the spec's rule vocabulary. A
blanket predicate in the evaluator would make `state is archived` return
nothing, quietly killing a contract-visible capability.

So: a smart playlist excludes archived members **unless its rule names
`state`**, in which case the rule is honoured as written. That keeps the
field working and matches what someone writing that rule means.

A static playlist filters unconditionally, since it has no rule to name
the field. Positions are unaffected: `PlaylistItems` numbers entries by
their index in the full member list, exactly as it already does for
members the caller cannot see, so a restore puts the row back where it
was.

### The facet cache needs nothing

`facetGeneration` is `{tail: l.CatalogTailSeq(), vocab: l.genres.version}`
(`facets.go:392`). An archive writes a catalog change-log entry, so the
tail moves and the enumeration recomputes under the new predicate on its
own. The cache is in-memory and dies with the process, so a deploy
carries nothing stale across either. No defensive invalidation is needed
and none should be added.

### The skip map answers unavailable when the bytes are gone

Same family, different mechanism: the catalog says `present` while the
file is gone behind the server's back, so `SkipMapFor`
(`service/skipmaps.go:60`) enqueued analysis and answered `pending`
forever while the worker dropped each entry as moot.

The facade exposes no state mutator, so `SkipMapFor` resolves the source
path through the same `analysisSource` the worker uses and answers
`unavailable` when there is nothing to measure, instead of queuing work
that will be dropped. The fuller fix, a catalog mark-missing the worker
can reach, is filed in `docs/upstream-requests.md`.

## Consequences

- Deleting to trash removes the item from every listing surface at once:
  the library screen, browse lists, facet counts and their drills, home
  shelves, the instant mix, similarity and mixes, public shares, episode
  listings, the Subsonic index, search, playlists, and the offline
  mirror. Restore puts it back everywhere by the same paths.
- A new item or track query in `internal/service` must go through
  `visibleItems`/`visibleTracks` or be added to `querylint`'s allowlist
  with a reason. `make lint` fails otherwise.
- An unfiltered `/library/browse` now resolves the acting user's catalog
  pid. An account whose catalog user row is missing sees browse fail
  where it previously succeeded; every per-user surface was already
  failing for that account.
- Search costs two extra catalog queries per call, and a third plus a
  wider pass when the trash actually cost it hits. A group can still come
  back short when the trash holds more matching items than the widening
  reaches.
- A smart playlist whose rule names `state` sees archived items. Every
  other playlist, smart or static, does not.
- An offline client reclaims a download when the audio was deleted
  outright, and keeps it when the item was trashed. Restoring from trash
  therefore costs no transfer. Emptying the trash afterwards does not
  reclaim it, which is the residual named above.
- The counts a listing reports and the counts an audit reports now differ
  by the archived population. That is intended: `health`, `organize`,
  enrichment coverage, and the tool surfaces are about what the catalog
  holds, not about what a listener is offered.
