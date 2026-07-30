# 35. Playlists, the rule editor, and the lost update

Date: 2026-07-30

## Status

Accepted.

## Context

Playlists were the last music surface still on the pre-overhaul screens: a
`ListTile` listing, a detail page whose only affordance was a drag handle,
and an 891-line rule editor built out of bare `DropdownButton`s. Four
things about them were unfinished rather than merely unstyled.

**The reorder had a precondition nobody consumed.** `PUT
/playlists/{pid}/items` takes an optional `baseUpdatedAt` and answers
`conflict` when the list moved underneath, and the client already sent it.
What it did with the refusal was show the server's sentence in a snackbar
and refetch, which reads as a failure rather than as what it is: another
device got there first, and nothing was lost.

**A playlist could only be filled from somewhere else.** Adding a track
meant finding it in the library, playing it, and using the player's
add-to-playlist dialog. Building a list of twelve tracks was twelve round
trips through the player.

**A smart playlist showed its rules only inside the editor.** The detail
page said "Smart playlist" and nothing about what made it one, so the only
way to see what a list was for was to open the thing that changes it.

**The editor refused `not`.** The rule contract has carried a `not` node
since the beginning and the editor had no surface for it, so a rule using
one opened read-only - the whole rule, including the parts it could draw.
Nothing in WaxDeck could produce such a rule, but the API is public and
`ImportStreamingPlaylist` is not the only door.

## Decision

### A lost race is a message, not an error

A refused replace sets a banner on the detail screen carrying **the
server's own sentence**, followed by "Nothing was changed; this is the list
as it stands." The row animates back because the screen refetches, and the
banner is what explains why.

The server's sentence rather than one of ours, because `conflict` covers
three different refusals - the lost-update precondition, members outside
your library visibility, and episodes of shows you do not follow - and only
the server knows which one happened. A client sentence about another device
would be wrong two times in three.

It is **widget state, not a provider**. The banner is about the drag this
screen just made; a second client looking at the same playlist has nothing
to be told. It is dismissible, because the condition is over once read.

Any refusal that is not `conflict` is a one-off failure and goes where
failures go.

**Appending does not carry the precondition at all.** `POST .../items`
appends, and adding one track should not stake a claim on the order every
other device is holding - which is the whole of what the precondition
guards. So the add row and the add-to-playlist sheet both append, and only
a drag can lose a race.

### A membership write drops the cover it just changed

The server builds a playlist's cover from its first few members and keys
it on a hash of the *ordered* member pids, so an append, a removal, and a
reorder each regenerate it. The URL does not change, and every cache keys
on the URL, so a client that just edited a list would keep painting the
cover of the list it used to be. Every write that can move it evicts it -
membership and the cover verbs alike - through one function, so the
invariant is not split across the controller and the screen.

Appending from elsewhere goes through the *listing* controller, not the
detail one. Reaching for `playlistDetailProvider(pid).notifier` to append
builds it, which is a playlist read plus every page of its members to add
one track; the listing is already alive and the `Playlist` it holds carries
the cover URL the eviction needs.

Run unconditionally rather than only where the cover is known to be
generated: the wire does not say whether a cover was uploaded or built,
and the cost of being wrong is one conditional request that answers 304.

The listing provider is deliberately *not* invalidated on a reorder, which
is the neighbouring thing to do and the wrong one: a reorder changes
nothing a card draws, the cover URL is stable, and a refetch of the JSON
would not have moved a single pixel. The staleness was never in the JSON.

### The detail page fills itself

A search field sits above the member list on any playlist this caller can
edit. It searches the library, offers tracks, books, and episodes, and
appends the one that is tapped. Artists and albums are deliberately absent:
they are headings, not members, and offering one would promise an append
the endpoint refuses.

Its own search rather than a trip to the search screen, because leaving and
coming back is exactly the trip the row exists to remove.

### Rules are readable outside the editor

`rule_vocabulary.dart` turns the wire's vocabulary into English in one
place - `albumArtist` into "Album artist", `gte` into "is at least",
`inTheLast` into "is in the last N days" - and both surfaces read it: the
editor's pickers and the detail header's chip row. One place because two
would drift, and a rule that says one thing while it is being written and
another once it is saved is worse than a rule that says nothing.

Field labels are **derived rather than tabulated**: a field the server adds
arrives readable instead of arriving as itself. A custom tag key is a
listener's own word and is left exactly as they typed it.

Values are read off their **shape**, not off the field's kind, because a
summary has no vocabulary loaded: an RFC 3339 instant reads as a day, and
`true`/`false` under an equality reads as the yes and no the editor draws.
Without that the header said "after 2026-01-15T00:00:00.000Z" where the
editor said "2026-01-15".

The chip row is **flat on purpose**. A chip row is a glance, and a nested
tree drawn as text is neither a glance nor an accurate tree. A rule whose
root is not a plain group of conditions says "Nested conditions" in one
chip and leaves the rest to the editor - the honest summary of a shape the
row cannot draw, rather than a partial one that looks complete.

### `not` becomes a group mode

A group has four modes: **All of**, **Any of**, **None of**, **Not all
of**. The last two serialise as a `not` wrapping an `any` or an `all`,
which is exactly the wire shape, and parse back the same way. A `not`
around a bare condition becomes a one-child "None of" group, which
evaluates identically and edits.

Read-only is now reserved for what it was always meant to mean: a node type
or a limit mode this client has never heard of. A rule from a future server
still opens and still shows itself; it just cannot be changed here.

Nothing else about a rule is rewritten by opening it either. A condition on
a field this vocabulary no longer lists keeps its operator, offered
alongside the fallback set, for the same reason the field itself is kept:
the server revalidates, and correcting `gte` to `is` on the way through
would change the rule just by looking at it. A sort on a field the
vocabulary no longer offers is corrected in the draft rather than drawn
over, so the picker never shows an order the save does not send.

### Handles are document order

The rule tree has no stable coordinate a spec could name - a condition's
position changes as groups are added above it - so `ruleField(0)`,
`ruleOp(0)`, and `ruleValue(0)` count in document order, which is what a
person reading the screen counts too. One counter per kind of control, so a
spec asking for the second field picker does not have to know how many
groups came before it. Only the outermost group's "Condition" and "Group"
buttons carry handles: the suite adds a condition to *the rule*, and the
rule is the group everything else hangs off.

### Two panes, one sticky bar

At sidebar width the editor is the tree beside its preview, each pane
scrolling itself, because a long condition tree must not push the match
count off screen - which is the whole point of showing it beside the thing
being written. Below that width the preview stacks under the tree and the
count moves into a bar pinned to the bottom of the scaffold, where it is
readable while conditions are being typed.

### The add-to-playlist dialog becomes a sheet

It is a list to pick from, it can be as long as a household's playlists,
and it is opened from a row's own menu on a phone, where a sheet comes up
under the thumb that opened it. A list already holding the item is marked
**and says so in words**: a check mark beside a row a screen reader reads
as a plain name is a fact only sighted people get. It stays tappable, since
the contract allows a playlist to repeat a track and refusing the tap would
decide otherwise on the listener's behalf.

### The import picker becomes a menu

Choosing where a playlist comes from decides what the paste box wants, so
it is the first question rather than a control sitting beside the answer.
One menu, one entry per source, each opening the box for that source.
Refusals are shown **inside** the dialog rather than as a snackbar, for the
reason the add-station dialog already records: a snackbar renders on the
scaffold behind the modal route, and the likeliest refusal of all would
have appeared under the dialog still asking for it.

### `MediaTileData.badge`

One word over the artwork, for the case where the kind of a thing changes
what it does rather than only what it holds. A smart playlist evaluates
itself, so it takes no reorder and no removal, and that is worth knowing
before the tap rather than from a caption two lines down. It is announced
with the title rather than after it.

Drawn on an **opaque** surface pair rather than on the scrim. The scrim is
translucent, and in light mode over a dark cover it composites to near-black
ink on a near-black ground - about 1.1:1. The contrast suite's scrim test
covers dark and OLED only, and no unit test can see a token composited over
an image, so the badge uses `surface1` and `textPrimary`, which the pair
matrix does cover.

## Consequences

The synced-playlist feature has its slots. The detail header's chip row
exists and already carries chips, so a sync-status chip is a chip rather
than a layout; the overflow is a declared enum with the cover verbs
grouped, so a "Sync settings" entry is one case. Both are named in the
deferred entry, which is otherwise unchanged.

`PlaylistCover` is gone. The mosaic and an owner's upload arrive at one URL
and the artwork store already sizes, bounds, and pins it, so the cards and
the header ask for artwork the way every other surface does and get the
monogram when there is none.

The rule editor grew from 893 lines to 1,277 and does more: negation,
typed value controls per field kind, tag keys with their counts, a
two-pane layout, and a keyboard contract where Enter in a value starts the
next condition. What did not survive is the shared `rule-field-select` key
every picker wore, which is why the widget tests used to pick with
`.last`.

A sheet or dialog that finishes a request after being dismissed no longer
pops. Popping a captured `NavigatorState` after an await pops whatever is
on top, which after a swipe-away is the screen underneath, so every pop
that follows an await is guarded by `mounted` first. The toast still goes
out where the work landed: the track did get added, and that is worth
saying wherever the listener ended up. Four call sites outside this phase
had the same shape - the add-station dialog's save and its directory add,
the book settings sheet, and the podcast subscription settings sheet - and
are fixed with it rather than left as a known defect in somebody else's
file.

Nothing new is deferred. Two candidates were considered and rejected: a
per-row overflow on playlist members (the row's tap plays it and its
remove button is beside it; a menu holding one verb is a menu holding
nothing) and undo on a removal (the row can be added back from the search
field directly above it, which is the same two taps an undo toast would
have cost and does not expire).
