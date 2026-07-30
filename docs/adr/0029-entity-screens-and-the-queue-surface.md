# 29. Entity screens at the bucket's location, and one queue surface

Date: 2026-07-28

## Status

Accepted.

## Context

`/music/artists/ar-...` and `/music/albums/al-...` have been reachable since
the music indexes shipped, and what they rendered was the bucket's item
list. The contract makes that possible in the first place: a facet
bucket's `entityPid` is its `key` behind a type prefix, so one address
names the entity and filters the listing. What was missing was a screen
about the entity - its own artwork, its releases, the star and rating
row that has existed and been tested since before there was anywhere to
put it.

The queue had half a surface: a desktop panel with no reorder, no
history, and no compact answer at all, because the deck bar's queue
control was wired only where a panel could open.

## Decision

**An entity bucket opens the entity, at the same location.** The router
sends `/music/artists/:pid` and `/music/albums/:pid` to `ArtistScreen`
and `AlbumScreen`; genres and years, which are not entities, keep the
listing, and so does the unknown bucket of every dimension, which is the
items a dimension is absent from and has no entity behind it. Nothing
about the address changes, so every link already shared still opens, and
the two specs that asserted a listing here moved in this change.

**An artist's full list is one level down.** `/music/artists/:pid/tracks`
is the listing the artist screen's "Show all" opens, and a stranger who
opens it gets exactly that, so it is declared beneath the artist. It is
pushed rather than gone to for the entry-point reason below: the artist
above it may itself have been pushed.

**How you got to an entity decides how it opens.** ADR-0022 makes that a
property of the entry point, not of the route, and both of these have
more than one entry point. An album `go`es from the albums index, which
is where it is declared; it is **pushed** from an artist's release tile
and from a search hit, because `go` would rebuild the albums ancestry
and throw away the artist or the query you were standing in - back from
a release would land on the index rather than on the artist whose
release it is. The same holds for an artist opened from search. Back on
these screens is `context.leave(fallback: index)` rather than a bare
`go`, so it pops what pushed it and falls back to the index when nothing
did: one behaviour the app bar's arrow and the system gesture share,
which is the trap ADR-0022 records from the episode case.

**A summary row carries its entity handles.** `ItemSummary` grows
`artistPid` and `albumPid`, filled from the entity projections WaxBin
already puts on an item view. Grouping an artist's tracks into releases
by display text would merge two albums that share a title and split one
spelled two ways, and a title is not a location - an album card needs a
pid to open. The same delta moves `trackNumber` and `discNumber` from
the detail onto the summary: a listing arrives in the catalog's own
stable order, which is not track order, and these are what sort a
release back into itself without a fetch per row. Both are additive on
the wire (the move is between an `allOf` branch and its base, which the
breaking-change gate flattens), and they are useful well beyond this
phase.

**An entity screen holds what its bucket counted.** A bucket counts
whatever carried its artist, audiobooks included, and a screen showing
fewer than the count promised is the one thing faceted browse cannot do.
So the artist screen lists everything and queues only what plays in
sequence: Play and Shuffle are disabled for an author with no music, a
book row opens the book, and the section names what it actually holds.
The alternative - filtering the list to music - puts an audiobook
author's own screen at "nothing by this artist" while the index beside
it says two.

**The queue is one body at two widths.** `queueSlivers` builds the
provenance line, the standing modes, the current entry, the reorderable
up-next list, the collapsed played head, and the way back into an
earlier session; the desktop panel and the compact `/queue` screen each
concatenate it into their own scroll view. Slivers rather than a widget
because a scaffold builds a scroll view for its large title and a panel
has none to scroll under. `/queue` is pushed rather than gone to, like
the player: it is a view of live state with nothing of its own to
address.

**A drag is not the only way to move an entry.** `SliverReorderableList`
carries none of the move actions `ReorderableListView` adds for itself,
so each row declares "Move up" and "Move down" as custom semantics
actions. Swipe-to-remove sits beside a remove button rather than
replacing it, for the same reason.

**Session history is where a launch with no local queue looks.** The
restore offer reads the disk first and the server's ended sessions
second, which is the web build's only source (it keeps no mirror) and a
fresh native install's. Declining a server-sourced offer is recorded per
device in the client-settings store rather than deleting the session:
the history is the account's, and another device may still want it. What
is stored is when the declined session stopped, not which one it was -
the history is newest first, so a decline is about everything up to it,
and one id would have offered the next-oldest session at the following
launch and the one after that at the one after.

**Putting an earlier session back is undoable.** The rows are on screen
while something is playing, unlike the deck bar's launch offer, so a tap
there replaces a live queue. The queue layer already kept what a
replacement displaced and where it stood; this is the first caller to
ask for it back. The toast the plan wants on every replacing tap is
still missing everywhere else and is tracked.

## Consequences

The deferred entries for artist and album detail screens and for
rendering session history close. The queue surface's remaining halves -
multi-select for batch moves, and dragging a row from a listing into the
panel - are recorded in `docs/deferred-work.md`; neither is on the path
of anything else.

An album's track order is now the client's to compute, because
`QueryPage` orders by the catalog's own sort key and ignores the query's
sorts. Sorting by disc and track locally is complete for any album the
queue could hold whole, which is any album. If server-side ordering per
facet ever arrives, this becomes a deletion.
