# 26. The music indexes and search

Date: 2026-07-27

## Status

Accepted.

## Context

The music domain's stand-in was a tab bar over six browse dimensions.
Each tab listed its buckets biggest-first and each bucket opened its
items on a route that carried the bucket in memory: reload it and you
landed on the tabs, share it and the recipient did too. There was no
search screen at all - the endpoint has existed since the first slice and
nothing in the app called it.

Three things had to be settled to replace that with the route map's
`/music`, `/search`, and the four indexes beneath them.

**An index of ten thousand artists is looked at alphabetically.** The
facet endpoint sorted one way: by count, biggest first, which is the
right lead for a hub and useless under an alphabet rail. Ordering was
already scheduled as the plan's API item 3.

**A bucket has two handles.** The enumeration returns a `key` to drill
with and, for the entity dimensions, an `entityPid` for the entity behind
it. The route map addresses artists and albums by pid; the listing filter
takes the key. Whether one can be derived from the other was true of the
implementation and absent from the contract.

**Playlists had nowhere to belong.** The layout system groups the ways
into a domain under its hub, and until there were sub-items to group with
it, Playlists sat flat among Settings and the curation areas.

## Decision

**`sort=label` on `GET /library/facets`, with the order carried in the
cursor.** `count` stays the default. The label order is case-folded
(byte order puts "Zebra" ahead of "abba", and an index whose rail says Z
would be showing the a's) and sorts the unknown bucket last whatever its
sentinel spells. A cursor records the order it was issued under, and a
mismatched pair is `invalid-request` rather than a page that silently
skips buckets: the two orders interleave differently, so resuming one
from the other's boundary is not a near-miss.

Both orders come out of one aggregation. The catalog call is the
expensive half and the answers differ only in arrangement, so the
enumeration is sorted twice and both are published to the cache, which is
now keyed by (dimension, order). The upstream `FacetPage` ask is amended
to include the ordering parameter, per the plan's 11.1: a paged `Facet`
that could only walk the count order would leave the A-to-Z half on the
in-memory window that ask exists to retire.

**`entityPid` is documented as the bucket's `key` behind a type
prefix.** That was already true; saying so is what lets one location
carry both. `/music/artists/ar-<ulid>` names the entity the detail screen
will be addressed by, and the listing under it drills `facetKey=<ulid>`.

**Every index and every bucket is a location.** `/music`,
`/music/{artists,albums,tracks,genres,years}`, and
`/music/{dimension}/{handle}` are declared in the table and reached with
`go`; nothing under `/music` rides an in-memory payload, so a reload and
a shared link both land where they say. The bucket a dimension is absent
from has an empty key, and an empty path segment is not a location, so it
travels as the literal `unknown` - no real key collides, since entity
handles are prefixed ULIDs, year keys are digits, and a genre key is a
ULID. A listing handed no label names itself from what it loaded: the
first row of an artist's list knows the artist's name.

**A bucket is drilled exactly as its count was computed.** The music
dimensions already leave podcast episodes out server-side and take in
whatever else carries an artist or a year, which includes audiobooks. So
the listing sends no `mediaType`; only the tracks index does, because it
is "every track" rather than a bucket of anything. A count that disagrees
with the list it opens is the one thing faceted browse cannot do - and it
did, until an artist bucket of two audiobooks opened empty.

**Two orders, two defaults.** Artists and albums lead A-to-Z, because an
alphabet is how anyone looks for one; genres and years lead
biggest-first, because an alphabet of years is the years again. The rail
is drawn only over the alphabet: in count order the letters are scattered
down the list, and a rail that jumped to the first S-shaped bucket there
would be lying about what it does.

**The rail pages toward a letter rather than seeking to one.** There is
no seek-to-letter on the endpoint and this plan does not add one; the
rail asks for more pages until the letter is on the list or the dimension
runs out. Pages are 500 buckets and the server answers them from one
cached enumeration, so even a long walk is a handful of cheap requests.

**Search is a location with its query in it.** `/search?q=` lives in the
shared branch, not in a domain, because it is over all of them and
leaving it must not rewrite the stack of whichever one the visitor came
from. Typing is debounced 250 ms into one query; clearing takes effect at
once, because a quarter second of stale results after a clear reads as a
stuck screen. Groups cap at five with "Show all" expanding in place, and
`truncated` is said out loud rather than left to look complete.

**The bar follows the settled query, not the keystroke and not the Enter
key.** A result set is only a link if it is in the address bar without
anyone pressing Enter for it, so the screen writes the URL from the one
provider every route into a query ends at - typing, submitting, a recent
search, arriving on a link - rather than from four call sites that each
have to remember to. It writes with `replace` rather than `go`: search is
one location whose query changes, and on web `go` mints a history entry
per call, which would make Back walk back through every prefix somebody
typed. The query outlives the screen, so arriving at a bare `/search`
clears it; otherwise a second visit shows the last search's results under
an empty field.

**A bucket listing pages at the queue cap.** Playing a row plays the
bucket from there, and a screen can only hand over what it has loaded, so
a page smaller than the cap would queue a prefix of an artist and label
it the artist. At 500 every bucket the queue could hold whole is loaded
whole before the first row can be tapped, and a bucket bigger than that
is windowed by the queue itself from the row that was chosen - which is
the same answer a smaller page could not give. It costs a larger first
page on a long list, which is what the index already pages at for the
same reason.

**The sidebar's search field is a launcher.** It looks like the field the
layout system puts there and opens the screen that owns the query. Two
fields holding one query is a synchronisation problem nobody asked for,
and the search screen autofocuses its own field on arrival.

**Playlists moves under Music.** It is one of the ways into the
collection, so it joins the indexes in the sidebar's Music section and on
the hub's tiles. `WaxDestination` grew `children` for this: a parent
destination is somewhere you can go and its children are shortcuts into
what is already on it, which is why the tabs, the rail, and a collapsed
sidebar draw the parent alone - one tap further on, not unreachable.
That is the difference from a `WaxNavGroup`, whose header row is a label
because its children are all there is.

## Deviations from the plan

**The hub's shelves are not here.** Section 6.3 asks for recently-added,
most-played, starred, and mixes beneath the index tiles. They are the
home shelves with a filter on them and share a component with what P17
builds; what landed is the half the indexes need, which is the way in to
each of them. The tiles carry a bucket count where a page can answer one
(`500+` where the dimension runs past a page, which is the truth) and a
label alone where it cannot.

**Search has no Radio chip.** Section 6.2 gives it one, searching the
station directory with "Add station" per result. That is the radio
surface P14 rebuilds, logo proxy and add-station flow included, and
building a second one now would be work P14 redoes. The chips cover what
`/library/search` answers.

**`album-artist` and `kind` are no longer surfaced.** The route map names
four dimensions and the hub offers those four. The endpoint still serves
all six and the custom tag dimensions; nothing in the client asks.

**The queue's window refill is not here, and is rescheduled rather than
dropped.** P3 listed it against this phase, meaning the shuffled draw:
a shuffle over a scope too large to hold, drawing again as it drains
against the eviction rule that already exists. Its only producer is a
Shuffle entry point that mints such a window, and there is none - nothing
in the app passes `shuffle: true` and nothing sets `QueueSource.rolling`.
The first is the entity screens' Shuffle button, so the refill belongs
with it rather than shipping here as a mechanism no gesture reaches.

Chasing that turned up its ordered twin, and this one is reachable today:
a scope larger than the cap plays its window and stops, so a 5,000-track
genre started at its first track plays 500 and ends. ADR-0019 records
that as the deliberate answer; it is not what the product wants, and that
ADR's status now says so. Both draws want the same thing - a way back to
the scope the window was cut from - and it is queue work, not a screen's:
the source and its cursor have to travel with the state and survive a
restore, and Connect reports the window. Both go to the queue's own
phase, together.

What this phase can answer it does: paging bucket listings at the cap
makes every bucket the queue can hold whole arrive whole, so only scopes
past 500 wait on the refill.

**The compact search affordance is on the screens this phase owns.** The
layout system puts search in the top app bar below sidebar width, and the
shell owns no top app bar - every screen brings its own. So the control
is on the music hub, the indexes, the listings, and the library grid,
which is the compact landing screen; the domains rebuilt later add it as
they convert, the same way the avatar does. From Podcasts or Radio on a
phone, search is Home and then the control.

## Consequences

The old browse screens are gone, and with them the three `browse-*`
semantics identifiers no spec drove. Five specs settled on the Playlists
row as their post-login marker and now settle on Music, which is drawn at
every width; the ones that navigate to playlists open the Music section
first, which is the one click the move cost.

Two defects turned up only by driving the real build in a browser, and
neither could have been caught by a widget test.

The skip link's box covered the sidebar header. It is painted at the
leading corner at full size so it stays in the tab order, and on web the
semantics tree is real DOM: an element carrying a tap action takes the
browser's click for its whole rect whatever Flutter's own hit test says
about it. P8 fixed the Flutter half of this for the content pane; the DOM
half only became visible when something interactive moved under the box.
It reports one pixel while collapsed now - not zero, which would take it
out of the semantics tree and out of the tab order - and grows to its
pill when a keyboard reaches it.

`WaxFocusRing` returned its child unwrapped while unfocused and wrapped
in a `CustomPaint` while focused, which changes the shape of the element
tree at the moment focus arrives. A child whose parent changes type is
rebuilt from scratch, and for a text field that means losing its state
and its input connection on the way in: the field could be focused and
could not be typed into. The paint is always mounted now and only its
painter comes and goes.

Both were found by the first interactive control to land in either
position, which is what P10 put there.

A review pass after that found seven more, and the shape of most of them
is the same: a rule that held for the surfaces already built stopped
holding for the ones this phase added.

The chrome highlighted nothing on any index, bucket, or `/playlists`
location. The active target resolves by longest declared prefix, which
for `/music/artists` is the Artists destination - and the tabs, the rail,
and a collapsed sidebar are handed the domains only, so they compared a
name they had never been given. Before P10 there were no sub-destinations
for this to be wrong about. A destination now holds the selection for its
children wherever its children are not drawn, which is one rule in the
frame rather than three checks.

`SearchScreen` seeded itself in `initState` alone, and go_router keys a
page by its path and path parameters - a query is neither - so opening
`/search` from `/search?q=night` reused the same State: the field, the
results, and the URL all disagreed. The scope and the expanded groups
outlive the screen the same way, so arrival now puts all four back.

A bucket drill sends no media type, which is what makes its list match
its count, and books therefore appear in artist and year buckets. Tapping
a book opened its screen from the first commit; tapping a *track* handed
the whole list to the queue, books included. The queue is the part that
plays in sequence now.

Two were arithmetic that a fixed number can only get right at one text
scale: the hub tiles overflowed from about 1.25x, and the index toolbar's
chip row overflowed at phone width because a horizontal scroller takes
its intrinsic width unless something bounds it. Tiles ask for their
extent the way `MediaListRow.heightFor` is asked; the chip row is
`Flexible`. The rail's own offset, which had already been wrong once,
stopped being local arithmetic at all: `WaxScaffold.barHeight` owns it.

The paging listener wraps the whole index screen and only looked at
scroll numbers, so dragging the sort chips - pixel zero of a very short
extent - fetched a 500-bucket page. It reads the axis now.

And the two search entry points wore one identifier while both were on
screen, so the spec disambiguated by document order. They are two
identifiers.

Under those, one design-system consolidation. The launcher, the hub tile,
and `WaxIconButton` each excluded their subtree from semantics without
declaring the focusable flag back, which is the defect that shipped a
keyboard-unreachable sidebar in P8 - the chip was the only one that had
learned. `WaxTappable` is that lesson as a widget: semantics, focus, and
the focus ring together, so the next control gets all three by composing
instead of by remembering.
