# 38. Home as shelves, and what the bell can honestly say

Date: 2026-07-31

## Status

Accepted.

## Context

Home was the library grid: every medium in one wall of covers with a
media-type filter over it, a continue-listening banner above it, and the
app-bar row that used to be the only navigation. Each medium has a hub of
its own now (music, podcasts, audiobooks, radio), and the layout system's
home is shelves - the handful of answers no domain hub can give, because
they are about the collection rather than about one part of it.

Three other things had been waiting on this phase, all recorded:

- **The account menu was in the tab bar.** The layout system puts the
  avatar in the top app bar; the shell owns no app bar, and until now no
  tab root had a `WaxScaffold` bar to host one, so it took a fixed cell at
  the trailing end of the compact tab bar (ADR-0024).
- **The music hub had no shelves.** Deferred by the music phase to the
  phase that builds the ones they share a component with (ADR-0026).
- **The shares list could only be pushed**, because `/shares` was declared
  beside settings rather than beneath it.

And two contract additions were scheduled here: a media-type filter on
the browse endpoint, and two collection lists the home shelves are built
on.

## Decision

### The two collection lists are queries, not orderings

`never-played` is `play_count is 0`; `rediscover` is `(starred is 1 OR
rating gte 80) AND last_played notInTheLast six months`. Both are answered
through the same query surface every other per-user filter uses, and
paged by the same keyset the item listing is - not through WaxBin's
`Browse`, which has no name for either.

That has one visible consequence and the contract states it: both come
back A to Z. Neither has an order a listener would recognise. A
never-played item has no play stamp to sort by, and sorting the other by
how stale it is would put the most forgotten thing first every time the
shelf is drawn, which is a shelf that never changes.

"Played" on both means what `playCount` counts, which is a listen session
past the medium's threshold rather than a saved position. So an item
abandoned early enough to have never crossed it is still sealed. That is
the honest reading of "never opened" the query surface can express: there
is no position field in it.

### The media-type filter narrows the window, and says so

`read.BrowseOptions` takes no query at all - the standing upstream ask -
so the filter is applied to the page the catalog answered. A filtered page
therefore comes back short of `limit` while still carrying a cursor, which
is exactly the shape a caller with restricted library visibility already
gets, and the contract documents it in both places.

Walking further per request was considered and rejected rather than left
undone. A page's cursor names its own end and there is no way to mint one
mid-window (`read.Page` carries no per-item order values), so filling a
page would mean consuming rows the answer could not report having
consumed - which drops items between pages. Short pages lose nothing. The
client's half of the deal is the other side of the same sentence: a shelf
asks for a generous limit and draws what it draws.

### Shelves hide when empty, and one read decides the first-run state

Every shelf that has nothing draws nothing, so a young library shows two
shelves and a full one shows eight and neither reads as broken. What
decides between the shelves and the designed first-run state is one cheap
read - does the library hold a single item - rather than eight empty
answers arriving one at a time.

Loading and empty look the same per shelf, deliberately. A shelf that
hides while it loads and appears when it lands is the layout jumping
under a thumb, and a skeleton per shelf would draw eight ghosts on a
library that has two. The screen's own skeleton covers the first frame.

### Cards are addressed by their shelf

The shelves overlap by construction: a fresh unplayed track is on
Recently added and on Never played at once. One handle on two cards makes
a click a strict-mode violation rather than a tap, so a card's identifier
carries its shelf (`shelf-{shelf}-{pid}`). The same reason the podcast
hub's two strips already have separate handles.

The handles say `shelf-` rather than `home-`, because the component is
not home's alone: the music hub draws the same shelves scoped to one
medium, and a music-hub card whose identifier claimed to be home's would
be a handle that lies about where the control is.

The wrapper that carries the handle is a semantics *region*
(`container` plus `explicitChildNodes`), which the first cut was not. A
plain `Semantics` merges with everything beneath it, so a shelf came out
as one node announcing itself as a button - its overline, its title, its
"Show all", and every card in one label, with nothing inside it
addressable. Found by the e2e run rather than by a widget test, and now
pinned by one.

### The mix cards carry seeds, not tracks

A mix is computed fresh per call and never persisted, so building the
"Made for you" shelf's contents would run the neighbour graph a dozen
times on every visit to home. The cards carry what to mix from - a top
genre by name, a top artist by pid - and the tap is what mints one. A top
entry with no pid is not offered at all, because a name that no longer
resolves is not a seed.

A listener with no history gets no shelf. An instant mix of a library
nobody has played is a random draw with a personal-sounding label on it.

### Offline, home draws what plays

The grid this replaces served the whole mirrored catalog with no network,
which listed mostly items with no local audio and failed on the tap. What
actually plays offline is what was downloaded, so that is the one shelf
offline draws, with the downloads manager behind it. The mirror listing
path (`mirrorItemsPage`) survives for Android Auto, which is its other
caller.

Its cards resume from the mirror's saved position, not from zero. That
is the whole reason a download row carries one - "this screen is the one
most likely to be open with no network" is the field's own doc - and the
first cut threw it away, which made the shelf most likely to be tapped
offline the one that restarted a half-heard book.

### The bell says what the client saw, which is markers

Section 6.19 asks for recent user-scope events the client observed over
the live channel. The live channel's frames carry no detail at all - a
topic name and nothing else - so the detail has to come from the user
sync stream, which is a *state-change* stream rather than an event log.

What survives from it as a notification is the marker kinds: `review`,
`upload`, and `task`. Each names a surface that moved and carries no
detail, which is exactly as much as the row claims, and each navigates to
that surface. The hydrated kinds do not become rows: a play state, a
preference, a book's settings are this client's own writes coming back as
often as anybody else's, and a notification for "your position was saved"
is noise with a bell on it.

Both transports end at one recorder by different routes, each minimal.
Native has a sync engine already reading this stream to keep its mirror
current, so it publishes what it read (`SyncEngine.serverEvents`). Web has
no engine and no cursor, so it mints one and walks the stream itself off
the same invalidation hint everything else refetches on.

**Neither reports its catch-up**, and that is one rule rather than two.
The web puller's first pull mints a cursor and says nothing, because a
session that just started has observed nothing and replaying last week as
"just now" would be a lie with a badge on it. The engine's cursor is
*persisted*, so its own first walk is that same backlog - a week of it if
the app has been closed a week - and it is silent for the same reason.
Getting this wrong would have made what the bell shows depend on which
build somebody was running, decided by a race.

Collection is bound to the session (`_SignedInScope`) rather than to the
bell. Watched from the widget it would start only once home had been
built, which a cold arrival on a deep link never does - so how much the
bell knew would have been decided by a rendering detail.

Rows deduplicate on their kind. The stream coalesces, but a scan opening
forty review entries still arrives as a burst of identical markers, and
forty rows saying one thing is worse than one row saying it most
recently. The list empties when the account changes, which the controller
watches for itself: a disposal callback may not modify another provider,
which riverpod asserts on in debug and swallows in release.

6.19's "episode downloaded" and "feed disabled" are not built. There is
no wire signal for either: a server-side episode fetch is a catalog
change with no user-stream event, and `SubscriptionSettings` carries no
auto-disabled flag. Recorded in `docs/deferred-work.md` rather than
approximated.

### The account control is compact-only

The frame draws none below rail width and the screens' bars carry it, so
the tab bar gets its cell back. It is not drawn in the app bar at rail or
sidebar width, where the rail's footer and the sidebar's already have
one: a second identical control on screen wearing one handle is the
problem the search field and the search action were split over.

`shellChromeProvider` is what makes that safe. Two places computing
"which targets may this account be offered, and what does its menu carry"
would be two places to get role gating wrong; the shell frame and the
app-bar control read one declaration.

## Consequences

- `library_screen.dart` and `library_controller.dart` are gone. The
  per-item handle `item-{pid}` moved to the tracks and bucket listing,
  which is the complete enumeration the grid was; the album and artist
  screens keep positional handles, because there the position is the
  point. Six e2e specs reach one known track through a shared helper
  instead of expecting it on the landing screen, and the a11y journey's
  browse step walks the chrome to the tracks index by accessible name -
  a shelf is a dozen cards off a discovery list, which is a fine landing
  surface and the wrong place to look for one named track.
- The perf gate's grid scenario is now login-to-home for the wait and the
  tracks index for the scroll. It has not been run - the measurement run
  is still the owed item it was.
- `WaxScaffold` grew `onRefresh`, `WaxFab` joined the design system, and
  `WaxMenuButton` grew a badge, an empty label, and an open hook.
  `ShelfRow` grew a handle for its "Show all", which it had drawn without
  one - a control the suite could see and not address.
- The player's back button has a handle now. It never needed one while
  the screen underneath it was the grid; with a drilled-in listing under
  it there are two buttons named "Back", and a spec picking by document
  order pops the wrong one. The icon set has no bell: the
  subsets are fixed at `make icons` time, which is network-bound and not
  part of `generate`, so the control wears the information glyph. Recorded
  rather than approximated with a warning triangle, which would say
  something false about every row.
- The bell is on home's app bar at every width, where 6.19 puts it on
  compact and beside the avatar on expanded. Home's bar exists at every
  width, so it is reachable everywhere; putting it beside the sidebar's
  avatar as well would mean the shell frame growing a slot for one
  control and two of them on screen at once. Same reasoning as the
  account control's, from the other direction.
- The "Pinned" shelf (6.1's second, marked optional there) is not built.
  It wants a per-account pref field and a pin affordance on every entity
  surface in the app; both are recorded.
- A mix that lands after the visitor has walked away still plays - the
  tap was a play command and the deck bar is where it shows - but does
  not push its track list and player over wherever they went. The router
  outlives the card, so that half is guarded and the playback is not.
- A shelf whose read failed hides, like an empty one. The screen already
  has an error surface - the probe that decides whether home has anything
  at all fails too when the server is not answering, and says so once
  rather than eight times. What is left after that is one list failing
  while the rest answer, which on an older server is a list it cannot
  serve; hiding it is the answer to that.
- Charts stayed `CustomPainter`s, restyled to tokens, and each now carries
  a spoken summary. A canvas announces nothing, and reading 365 bars is
  not a summary: what each says is the span it covers and where the peak
  landed.
