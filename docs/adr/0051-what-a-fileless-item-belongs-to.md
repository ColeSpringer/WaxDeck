# 51. What a fileless item belongs to

Date: 2026-08-07

## Status

Accepted. Refines ADR-0048, which decided which item states belong in a
listing; this decides which *library* an item belongs to when it has no
file to attribute.

## Context

Library visibility used to be answered by attributing a file path. The
service kept a table of every registered root, sorted longest path
first, and walked it per read (`libraryForPath` in
`internal/service/visibility.go`). Nested roots resolved to the deepest
match, and an item whose path matched no root was attributed to no
library.

The catalog now projects the answer directly. `model.ItemView.LibraryPID`
is the registered root the item's primary file sits under, and
`pidpath.Location` carries the same handle, so the three visibility
predicates read a field instead of walking a table. The path table
survives only for the callers that genuinely attribute a *directory* —
the podcast dir, an upload target, an admin settings path — which have
no item view to read.

That change is mechanical. What is not mechanical, and what a future
agent will re-litigate, is the negative case.

**An item with no file has no `LibraryPID`.** An undownloaded podcast
episode is the common one: it is `remote`, ADR-0048 keeps it in listings,
and it has no path and no library. The empty handle is not "unknown" and
not NULL-as-in-SQL — upstream is explicit that it is empty "only for a
fileless item and never because an entity is missing", and that it
selects exactly what `library isMissing` and the facet's `[No File]`
bucket select.

The trap is that the query grammar's `in` and `notIn` are **not
complements** over such a row. WaxBin's `store/sqlite/fields.go` says so
directly: `notIn` *keeps* a handle-less row, so `library notIn [every
root]` returns every fileless item while `library in [every root]`
returns none. That is deliberate — it is the deny-list contract a stale
entry needs — but it means a scope written one way includes undownloaded
episodes and the same scope written the other way excludes them.

## Decision

**A fileless item is attributed to no library, and a library-scoped
visibility check refuses it.**

This is what the path-based code already did — no path meant no root
meant not visible — so it is a restatement, not a change. It is written
down because the mechanism moved and the old mechanism made it obvious.

Three consequences follow, and each is the part worth keeping:

**1. Visibility predicates fail closed on an empty handle, explicitly.**
`itemVisible`, `viewVisible`, and every future sibling test the handle
for emptiness before the map lookup. A bare `uc.Libraries[string(it.LibraryPID)]`
happens to give the same answer today, because no library has the empty
pid, but it reads as an accident. The explicit guard says the refusal is
the decision.

**2. A deny-list scope must not grow an `OR library IS NULL` arm.**
Because `notIn` already keeps handle-less rows, hand-writing the null
case would double-count it, and because `in` already drops them, hand
-writing it there would contradict this ADR. Neither is needed. Any
future scope builder that reaches for one is working around the contract
rather than using it.

**3. Podcast surfaces reach undownloaded episodes through the
subscription scope, not the library scope.** This is why refusing them
at the library check costs nothing: an episode is visible because its
show is subscribed (`subscriptionFilter`), and the library dimension was
never what admitted it. A reader who confuses the two will conclude that
refusing fileless items hides every unfetched episode, which it does
not.

## Consequences

The visibility predicates cost no reads where they used to cost a table
walk, and `itemVisible` keeps its located-path cache while dropping the
walk behind it. The library handle is also the more durable of the two
signals: a relocate rewrites every root's paths and leaves the library
pids alone, so an attribution that used to be invalidated by a move now
survives it.

`libraryForPath` and its attribution table stay, smaller, for the
directory callers. They have no item and so no projected handle; the
table is the only thing that can answer them.

The library item count on the admin console changed shape with this:
counting by `library` is an indexed integer comparison, where the path
-prefix form compiled to `LIKE ? ESCAPE '\'` and SQLite disables its LIKE
optimization whenever an ESCAPE clause is present, so it scanned. The
count is the same number; it is no longer the reason the listing is
opt-in.

The risk this accepts is that an item can lose its library handle without
losing its subscription or its play state — a file deleted behind the
server's back, before the scan notices. Such an item goes invisible to
restricted users while staying visible to full-visibility ones. That is
the same behaviour the path form had (a path that no longer resolves
attributed to nothing), and it resolves itself when the catalog marks the
item `missing`.
