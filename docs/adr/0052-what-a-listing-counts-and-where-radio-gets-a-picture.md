# 52. What a listing counts, and where radio gets a picture

Date: 2026-08-07

## Status

Accepted. Completes the batch ADR-0051 opened: that one recorded what
the widened item view answers directly, this one records what the rest
of the answered upstream batch changed about counting, cursors, undo,
and artwork.

## Context

ADR-0048 put a state predicate on every listing, and did it in the two
places a listing can be built: inside the query where a query exists,
and in Go where the rows arrive already chosen. The seam between those
two is where this ADR's subjects live. Everywhere a limit, a count, a
cursor, or an index was computed on one side of the predicate and
consumed on the other, the two disagreed - and the disagreements were
quiet, because each half was locally right.

Radio's artwork is a separate subject and rides here because it landed
in the same batch.

## Decision

### A smart playlist evaluates its rule with the predicate inside it

`PlaylistItems` went through `Playlists().Items`, which evaluates the
stored rule in SQL - `Limit` and `LimitMode` included - and returns what
matched. The archived rows were then dropped in Go. So a `limit: 25`
list holding five trashed rows returned twenty while a hundred live
matches waited behind the cap, and `limitMode: minutes` lost the same
fraction of its budget. `PreviewRule` did the opposite and said so in a
comment: it conjoins the predicate into the query and evaluates that, so
the editor showed a full twenty-five and the saved list came back short.
That inversion is the exact one `PreviewRule` exists to prevent.

The member read now goes through `Library.Query(evaluableRule(rule),
ownerPID)` - the unpaged evaluator, the primitive `PreviewRule` already
used. Three things follow, and each is a decision rather than a
consequence.

**Not `QueryPage`,** which the bug report proposed. Its doc is explicit:
"q's own sort/limit/offset/limit-mode are ignored; the canonical
sort_key ordering owns the page." Paging a smart playlist through it
would silently discard the rule's `Sorts`, `Limit`, and `LimitMode` - a
"newest first" list would come back alphabetical and a budget rule would
return the entire matching set. That is worse than the bug being fixed,
and it is pinned by a test: an explicit descending sort reverses the
ascending one, a one-minute budget over short tracks takes more than one
of them, and a fixed `LimitSeed` draws the same two twice.

**The user pid is the owner's, not the caller's.** `PreviewRule` passes
the caller's because a preview is stateless and belongs to whoever is
typing. A saved list does not: `PlaylistItems` documents that "a smart
playlist evaluates against its owner's user state (the contract for
shared lists); the caller's own library visibility still filters what
they see." Pass the caller's pid and a shared `played = false` rule
starts evaluating against each reader's play state, which no
single-account test can see.

**The cover changes what it is built from.** `syncPlaylistCover` is fed
the member list deliberately - "the cover belongs to the playlist, like
its name, not to whoever is reading it" - and for a smart list that list
is now the rule's filtered evaluation. A trashed member stops
contributing cover art. That is probably an improvement and is certainly
a behaviour change, so it is written down here rather than left in a
diff.

The share page had a second, independent copy of the same filter one
layer up. It now calls the same member helper, and the double fetch it
carried (`Playlists().Get` re-issued to read the rule three lines after
`playlistNameAndOwner` had already read it) is gone with the same edit:
that helper hands back the playlist row instead of two fields off it.

### A playlist's reported count is what its listing hands back

The static branch of `playlistDTO` reported `pl.ItemCount`, the
catalog's stored member count, so a ten-member list with one member
trashed answered 10 from the playlist and 9 from its items,
indefinitely. The smart branch counted the rule but not the caller's own
visibility. Both now count the caller's own filtered membership.

`withCount` still gates the smart kind alone: it exists to keep a grid
of tiles from evaluating every stored rule, which is real work.

**Amended: both paths count live, and the cache is gone.** The split
below was written while playlist membership was the one item relation
the query engine could not express, so counting meant hydrating every
member. `playlist_pid` landed upstream, and with it
`Playlists().CountItems`, so a static list's count is one indexed
`COUNT` and a listing row can afford to be right. `cachedMemberCount`,
its key, its TTL, and the per-user map behind it are deleted; a trashed
member leaves a listing row immediately rather than within a minute.

Three things about the new shape are decisions rather than mechanics.

**The narrow mirrors `memberVisible` clause for clause,** and that
correspondence is the invariant: state, library grants, and the
subscription scope, written as a query node instead of a per-item check.
Both empty cases fail closed the way the per-item filter does - no
grants compiles to `1=0`, no subscriptions leaves "anything that is not
an episode". If a fourth clause is ever added to one, it has to be added
to the other or a count and its listing part ways again, which is the
failure this whole section exists about.

**Smart lists deliberately do not use `CountItems`,** even though it
serves both kinds exactly. WaxDeck evaluates a stored rule through
`evaluableRule`, which conjoins the archived predicate *before* the
rule's own limit (ADR-0051); `CountItems` evaluates the rule as stored.
For a limited rule over a list holding archived members the two
disagree, and the half that has to win is the one the member listing
uses. Smart lists keep hydrating, and keep reporting no count on a
listing page.

**The steady-state cost moved, on purpose.** A page of N static
playlists now runs N indexed counts instead of memoized hydration, so
the shape went from "cheap until UpdatedAt or the TTL moves, then
hydrate everything" to "always count, always cheap". That is what the
upstream ask and this ADR's own deletion condition both anticipated. The
one bulk-count primitive upstream, the `GroupPlaylist` facet, cannot
serve this listing: it counts distinct items where the listing counts
entries, and its bucket set is owner-or-shared rather than the caller's
page. If listing latency ever measures hot, a bulk count is a new
upstream ask on evidence, not something to build ahead of it.

Subsonic's `playlistTotals` cache stays. It reports a duration beside
the count, duration still needs the members hydrated, and one hydration
answers both - counting separately there would add a query without
removing a walk.

*What follows is the superseded reasoning, kept because it names the
pressure the listing path is under and why the obvious per-member
spelling is the cheap one.*

**The two paths take that count differently, and the split is the
decision.** A caller that asked for the count - a playlist opened - gets
it live, so it cannot disagree with the member listing beside it, which
is the whole bug. A listing row takes it from a cache, because that path
is far hotter than it looks: the client's playlists provider rides the
user-stream fan-out, so every star, rating, and play-state checkpoint
from any device re-runs the entire page, and none of those can change a
static list's membership. Computing it per row per event would be the
same read Subsonic's listing makes, at a rate no Subsonic client asks
for.

The cache is keyed the way Subsonic's `playlistTotals` is - the
playlist's own `UpdatedAt`, plus a one-minute TTL - and the TTL is what
covers what that timestamp cannot see: an item trashed or restored, a
grant changed, a subscription changed. So a tile can trail its playlist
by up to a minute after a trash and then agrees again, which is a
different thing from the disagreement this ADR is about: that one was
between two surfaces and permanent, this one is with itself and
self-healing.

**Not keyed on the catalog's data version,** which looks like the
precise answer and is the wrong one. `DataVersion` is a `PRAGMA` that
moves on any catalog write, play-state checkpoints included - so it
would invalidate on exactly the events the cache exists to absorb while
telling us nothing about whether the membership moved.

**And the cache is a workaround for one missing query field, filed
upstream rather than accepted.** Playlist membership is the only item
relation the query engine cannot express: the state predicate, the
library scope, and the subscription scope are all already query fields,
so a `playlist_pid` set field - the shape `genre_pid` and
`credit_artist_pid` already have - would make this a single indexed
`Count` with no cache, no TTL, and no staleness at all. When it lands,
`cachedMemberCount` and the split above are deleted and both paths
count live.

The per-member cost is what makes the live path affordable, and it is
worth naming because the obvious spelling is not the cheap one. The
filter asks `viewVisible`, which reads the library handle off the item
view it already holds - not `itemVisible`, which takes a pid and
resolves it through the located-path cache. That difference is one cache
lookup per member per playlist: a page of fifty three-hundred-member
lists is fifteen thousand of them, for an answer sitting in the row. It
is also the more correct of the two, for the same reason the sync paths
prefer it.

### A replace refuses a trashed member

`ReplacePlaylistItems` names the dimensions its guard covers, and
ADR-0048 added a third that was never added to it. A client PUTting back
the listing it can see stored a member list with the trashed row
silently dropped, and a restore never re-added it - which contradicts
`PlaylistItems`' own promise that positions count off the full list "so
a restore lands where it was". The archived arm joins the other two.
Reachable through Subsonic `createPlaylist`'s replace form too.

### Subsonic removes the track the client saw

Not on either tracked list, found while planning, and a wrong-track
deletion rather than a silent drop.

`renderPlaylist` iterates the caller's *filtered* membership and renders
`entryChild(idx, e.Item)`. The Subsonic response carries no position
field, so the array index is a client's only handle on a member.
`updatePlaylist` then passed `songIndexToRemove` straight to
`RemovePlaylistItemAt`, which is a raw catalog position. With a trashed
member at position 1, a client removing what it saw as index 3 removed
catalog position 3 - a different track, unrecoverable through that
client, which cannot see what it lost.

It is older and broader than ADR-0048: the library-visibility and
subscription filters skew the same index, so a partial-visibility user
already hit it. The fix is cheap because the data is already there.
`PlaylistEntry.Position` is the catalog position, so the client's index
maps through the filtered entries. An entry carrying no position is
refused rather than guessed at.

### The resume shelf reads past what it filters

`RecentPositionStamps` took a bare limit and `ORDER BY position_ns
DESC`, and the caller then applied four filters - kind, archived,
library visibility, subscription. Trashing the two most recently
positioned books emptied two slots of a ten-slot shelf with forty
positioned items behind the cap, and unlike the other three filters this
one bites full-visibility callers.

A bare multiplier is not the fix, because the last two filters can drop
arbitrarily many rows and an over-fetch gets one shot. The query takes
an offset and a total order (`position_ns DESC, item_pid DESC`, so
paging cannot skip a row stamped in the same nanosecond as another), and
the caller pages until the shelf is full or it has walked 2000 stamps.
The ceiling is the honest half: a listener whose recent stamps are all
music, all trashed, or all outside their libraries gets a short shelf
rather than a scan. Concurrent checkpoints can shift a row across a page
boundary, so the caller de-duplicates by pid.

### An embedding is pruned when its audio is gone, not when it is hidden

`SimilaritySweep` built its live set from `visibleItems()` and pruned
any embedding whose essence was not in it. The prune's comment - "a
truly deleted recording's vector is dead weight" - was true before
ADR-0048 made a trashed item archived, restorable, and still on disk, so
every trash and restore cost a full re-analysis of a file that never
moved.

**The plan's proposed probe was wrong and is corrected here.** It named
`l.lib.File(ctx, it.FilePID)` as the test for whether the audio is gone.
It is not: every delete mode "preserves the logical item, archiving it
when it loses its last file", so a trashed item and a permanently
deleted one both lose the file row and both fail that probe
identically. The trash journal is what tells them apart, and
`RestorableTrash` - batched, index-served, item-keyed, landed in this
same bump - is the primitive. The sweep collects the essences with no
live audio, asks the journal about the items they were recorded against
in one call, and keeps the restorable ones.

It keys on the item the vector was recorded against, so the residual
case - that item purged while a second item with the same audio is only
trashed - prunes and costs one re-analysis on restore. That is the
pre-existing price rather than a new one.

### Cursors are versioned where what they index into changed

Two, for the same reason and by the same rule.

`cursorVersion` moves `s1` to `s2` with `oldCursorVersions` left empty.
ADR-0048 moved `Items` onto `visibleItems()` and made `Browse` pass a
`Query` unconditionally, while the scope envelope hashes the list, the
seed, and the `ItemFilter` - not the state predicate. So a pre-deploy
cursor validated and walked a different result set, which waxbin
describes exactly: "Reusing a cursor across a changed query yields a
coherent-looking wrong window with no error." Leaving `s1` unretired
means a stored queue's cursor is handed to the catalog and answered
plausibly and wrongly; retiring it costs one placement walk per stored
queue, once.

The offset cursor gets the same treatment for the same reason, and it is
new here: `encodeOffsetCursor` was `base64("o:" + off)` with no version,
and a smart playlist's offset now indexes into the rule's filtered
evaluation rather than the unfiltered member list. The prefix carries a
version, so the old spelling stops parsing and a mid-scroll cursor
answers 400 instead of a shifted window. The blast radius is one
in-flight scroll, which is why 400 is cheap.

### Mark-finished is undoable

The completion rules are monotonic by construction: a position
checkpoint can mark an item played and finished and can never un-mark
it, and `markSpokenWordProgress` refuses to re-mark a played item on
purpose. So the book screen's Undo wrote the old position back and
nothing cleared the flags - nothing could - and a mis-tap put a book in
the Finished shelf permanently with the hub's unfinished filter hiding
it.

`playback.Service.SetPlayed` landed upstream and is the real fix rather
than the confirm dialog the plan had drafted as an interim. It is
exposed as `PUT /items/{pid}/played`, taking both flags plus a
three-way play count: null keeps the stored count, zero clears it, and a
positive value sets it exactly. An undo of a mis-tapped mark sends zero,
so the play the mis-tap added goes with it - unless the book was already
played, in which case its own count stands, because the catalog refuses
a played row with a zero count.

The client clears the flags first and writes the position second. The
position write is what can re-derive completion, so doing it last means
nothing runs after it to undo what it did.

### Unfetching an episode deletes bytes, not the episode

`RemoveEpisodeDownload` trashed the item, and every delete mode archives
an item on losing its last file, so `countShow` - which counts through
`visibleItems()` - stopped seeing an episode that `/podcasts/{pid}/episodes`
still listed. A three-episode feed read "2 unplayed" on the hub beside
three unplayed episodes on the show, for every subscriber at once,
because the file is one shared catalog row.

`podcast.Service.Unfetch` landed upstream and is what the operation
always meant: delete the file, return the episode to `remote`, keep the
subscription, the episode row, and every subscriber's play state. The
episode stays listed and stays streamable by enclosure passthrough. The
listing was the surface that was right, so the fix went to the verb
rather than to the filter. The spec's prose said "archive, never delete"
and now says what actually happens, including why the bytes are not
recoverable from the trash: an unfetched episode's audio is re-fetchable
from its source.

**What the swap gives up, deliberately.** `ApplyDelete` ran inside a job
holding the `fs-mutate` lease, which serialized it against scan and
organize; `Unfetch` calls `os.Remove` and `DropEpisodeFile` directly, and
the lease is not reachable from here (`fsMutateScope` and `l.jobs` are
both unexported, with no run-under-the-lease entry point). Filed
upstream. The exposure is one `os.Remove` of one file against a scanner
that already tolerates a file vanishing underneath it, and the
alternative is the count bug above. One visible consequence:
`DELETE /episodes/{pid}/fetch` no longer answers `catalog-busy`, so the
handler classifies plainly rather than translating a conflict nothing on
that path can raise.

**Amended: it takes a lease now, its own.** Upstream answered by giving
the podcast download tree a `podcast-fs` scope rather than folding it
into `fs-mutate`, so an unfetch serializes against the retention and
download passes that touch the same files without blocking on a scan
that cannot. `catalog-busy` is back on that endpoint, and the handler's
translation is live again. ADR-0059 records the rest of what the scope
changed, including the two delete surfaces that now refuse an episode.

### Radio artwork has two rungs and a fallback under both

A station face drew the matched track's cover, then the station logo,
then two initials on a flat swatch. Most stations arrive with no logo,
so the third state was the common one.

**The fallback is a designed state, and it landed first.** The
placeholder is a parameter now, and radio's surfaces ask for a wordmark:
the station's whole name, set over the domain hue with the same grain
the player backdrop tiles. It falls back to initials below a legibility
floor, which is what the deck bar's 48-pixel thumbnail gets - the call
sites declare intent and the component decides what fits, rather than
three call sites each carrying a size rule.

**The second rung is off by default.** On a local miss, the server
searches MusicBrainz for the announced artist and title, takes a release
id, and resolves a Cover Art Archive front cover, serving it from this
origin through the same raster-only check the station logo takes. It
shares the `providers` MusicBrainz client rather than opening a second
one: that client applies the mandatory contact User-Agent and the
one-per-second pacing, and an unthrottled second caller is how an
instance gets blocked.

**The image is addressed by a token, not by the station.** Play-info
answers a `nowPlayingArtKey` and the client passes it back as `v`; the
endpoint serves the cover held under that token and nothing else. Two
failures made this necessary rather than tidy. A URL that varied only by
station never changed as the station played on, so Flutter's image cache
answered every later track with the first one's decoded bytes and a day
of `Cache-Control` meant HTTP was never consulted either - the feature
worked exactly once per station. And an endpoint resolving against
whatever was announced *now* answered 404 whenever a title rolled over
between the fifteen-second poll and the image request, which the client's
artwork store remembers against that URL for the rest of the session. A
token fixes both at once, and it makes the long `Cache-Control` honest:
the bytes behind one URL never change.

**The toggle governs the read, not only the fetch.** An operator who
switches the rung off stops serving third-party covers from their own
origin immediately, rather than for as long as the week-long entries
stay fresh; the cache is dropped with the switch, so the bytes are gone
rather than merely unreachable.

**The key and the upstream query are built from the same normalized
pair.** Keying on the normalized form while querying the raw one
collapsed "Ornithology (Official Audio)" and "Ornithology" onto one
entry and let whichever arrived first decide the search - so the noisy
spelling, the one MusicBrainz misses, could cache a day-long miss
against a key the clean spelling would have resolved. The local-match
rung already normalized before searching; this is the same rule one rung
down.

**The cache is bounded by bytes and drops stale entries where it finds
them.** An entry count times the fetch cap is a resident ceiling in the
gigabytes, which is why the station-logo cache next door counts bytes;
and eviction only on insert means a server that met a few hundred titles
and then went quiet holds every one of those image bodies for the life
of the process.

Three properties are the design rather than details of it. The lookup
never blocks a request: the play-info poll starts it and reports what is
cached now, so the first poll after a title changes answers nothing and
a later one answers the image, on the fifteen-second cadence the contract
already asks for. One title is asked about once, held by a single-flight
claim, so a household of devices on one station makes one pair of calls
rather than one per device. And the two failures are cached differently:
answered-and-empty holds for a day, because a track released this week
can have no archive entry today and one tomorrow, while a service that
could not be reached holds for minutes, because caching one bad minute
upstream for a day turns it into a day of blank faces.

**The lookup runs on `procCtx`, and the obvious alternative is a trap.**
It has to outlive the request that started it, or a station nobody polls
twice never resolves - but `context.WithoutCancel` buys that by
stripping every cancellation, the shutdown signal included.
`Group.GoOnce` hands its context straight to the worker and `Group.Wait`
blocks until every worker returns, so an uncancellable lookup would hold
a shutdown open for the whole twenty-second budget while an HTTP call to
a paced third party ran to completion. `procCtx` is the context that
already means "outlives a request, ends with the process", and it is
what async catalog jobs launch on. `EnsureRadioNowPlayingArt` therefore
takes no context at all: nothing in it is the caller's to cancel, and a
request context in its signature would say otherwise.

The toggle is off because this sends a string a station chose off a
self-hosted server to a third party. That is the operator's decision,
and a much easier argument to have before shipping than after. The deck
bar keeps the station logo whatever the rungs answer: a bar whose
picture changed every few minutes would read as the station changing.

### The limiter counts the caller, where the operator says who the proxy is

`remoteIP` read the socket address and nothing else, deliberately, with
trusted-proxy support recorded as "a config surface for later". Behind a
reverse proxy that means `Allowed(login-ip:…)` keys on the proxy, so
five failed logins from one person lock out the household on a doubling
ladder.

`WAXDECK_TRUSTED_PROXIES` takes a CIDR list, and the walk begins only
when the socket address is itself on it. That is the property everything
rests on: a request that did not arrive through a configured proxy gets
no say in its own address, so nobody mints a fresh budget by sending a
header. The walk goes right to left over `X-Forwarded-For`, stops at the
first hop not on the list, and terminates rather than skipping past
anything that does not parse as an IP - an obfuscated token, a
placeholder, garbage. Ports and bracketed IPv6 literals unwrap. An empty
list is today's behaviour exactly; a list that does not parse refuses to
start, because a typo that silently trusted nothing would look like a
working configuration until somebody was locked out.

A flag, never `/admin/settings`. A runtime-mutable trusted-proxy list is
a way to disable the limiter from inside the product.

**The signup half needed no separate fix, and the plan was wrong that it
did.** `Signup` consuming budget on success is deliberate and documented
where it happens: "account creation is the expensive outcome. A NAT'd
household admitting a handful of members stays under the threshold; a
script farming accounts does not." What made it read as server-wide was
the shared key, and correct client addresses are the whole of that. No
`Success` call was added; adding one would defeat a documented
anti-abuse decision.

## Consequences

A static playlist's count is a member load rather than a stored column.
On the opened playlist that is a read per open; on the listing it is a
read per playlist per minute rather than per fan-out event, which is
what makes the correctness affordable on a page the user stream re-runs
constantly.

*Amended:* it is one indexed `COUNT` per static row now, on every read,
and the minute of staleness is gone with the cache. What a listing row
reports and what its member listing hands back can no longer differ,
which was the standing hazard: two numbers computed from two sources, of
which only one was checked by a test.

Cursors minted before this deploy answer 400 once. That is deliberate,
and the alternative is answering them plausibly and wrongly.

Radio may now make outbound requests, and only after an operator turns
it on. A station's announced artist and title are what leave the
machine; nothing about the listener does.

`mutators-admin` stays one worker in order, and the deferred entry
asking for its workers back stays open with a sharper reason than it had:
the blocker is not the two settings tests that read-modify-write one row,
which a `describe.serial` would answer, but the server-wide read-only
switch one of them holds for the length of its body - which refuses every
write the other five make. Freeing the workers means making that test
stop being global, not rescheduling around it.

The server's notification targets are an admin console section rather
than the tail of a listener's Integrations screen. Nothing about the
editor, its controller, or its endpoints changed - it was a surface in
the wrong parent.
