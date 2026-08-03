# 32. The episode's location, and what decides an episode can play

Date: 2026-07-29

## Status

Accepted.

## Context

The podcast surfaces were the last three screens still on the shapes
they were first written in: a subscription list with a floating add
button, a show that was a header over a flat episode list, and an
episode detail that was show notes plus a transcript. Everything the
plan's 6.8 asks for beyond that (what is half-listened-to, what is new,
folders, filters, batch actions, the backlog problem on a new
subscription) had nowhere to live.

Two decisions were left open for this phase on purpose.

The first is the episode's URL. `/episodes/:pid` names no show, so an
episode could only ever be *pushed* from its show: `go` would have built
the hub beneath it, and leaving an episode would have landed on a list
of shows rather than on the show. The route map recorded that cost and
left the choice to the phase that would know what the episode's surfaces
need.

The second is what "play" means now that enclosure passthrough has
landed (ADR-0030). The server stopped refusing an unfetched episode
months of client code before the client noticed: `show_screen.dart` was
still branching on `downloaded`, so tapping an episode that would have
streamed queued a download and asked the listener to wait.

## Decision

**The episode's canonical location carries its show:
`/podcasts/:showPid/episodes/:pid`.** An episode's ancestry is real:
every episode belongs to exactly one show, so putting it in the path
makes the location honest rather than merely unique. A stranger opening
the link gets the episode with its show underneath, so back lands on the
show from a shared link exactly as it does from a tap, the address bar
follows the hop, and the shell lights Podcasts by prefix like any other
drill-in. 4.2's route map is amended.

**The show-less `/episodes/:pid` stays, and is not deprecated.** Search
hits carry a pid, a kind, and display text and nothing else, so the flat
location is the one that surface can build; it also keeps every link the
old route minted working. A screen opened there has no ancestry, so it
is pushed and leaves to the hub. This is not a compatibility shim to
sweep later: "an episode with no show in hand" is a real caller, and
the two locations say two different true things.

**A row goes to the nested location and pushes the flat one.** The rule
is 8.3's, and P11 already landed both halves of it for albums: a
location is *gone to* from the surface that declares it (the show's own
episode list) and *pushed* from anywhere else, because `go` would
rebuild the declared ancestry and throw away the surface the visitor is
standing in. The hub's Latest strip pushes; so does search.

**`downloaded` no longer decides whether an episode plays;
`hasEnclosure` does.** `EpisodeActions.playable` is `downloaded ||
hasEnclosure`, in one place, because the show's list, the episode's own
screen, and anything that grows a play affordance later have to agree,
and a second copy of that rule is how two surfaces come to disagree.
What fetching adds is local bytes and the analysis that rides them
(silence trim, voice boost, the skip map), so it stays worth offering
and stops being the gate.

**The fetch-wait path survives for exactly one case.** An episode that
is not downloaded and whose feed named no enclosure cannot play at all;
tapping it queues the download and says why in those words. The row says
so before it is tapped, too, which is the part worth having: the
listener learns it from the list rather than from a control that appears
to do nothing.

**The hub's shelves get an endpoint of their own:
`GET /podcasts/episodes`.** The first draft sifted the cross-domain
discovery lists for podcast items, and that was the wrong shape twice
over. A discovery list is over the whole library, so a music collection
dilutes it and a hub pays to page past music it is not asking about; and
it answers generic summary rows, which carry neither `showPid` nor
`hasEnclosure`, the two fields that decide where an episode row links
and whether it can offer to play at all. So the Latest strip could not
play, and its rows could not reach the canonical location.

The listing is over the caller's own subscriptions, with three filters
that are three real questions: `latest` (everything), `unplayed` (what
is new to me), `in-progress` (where was I). Ordering follows the filter,
because the two questions want different orders: newest published for
what is new, most recently played for what to pick up. Section 11's item
4, a `mediaType` filter on `/library/browse`, stays unclaimed: this
does not need it, and Home's shelves are a different question (across
domains, not within one).

**`in-progress` orders by last played, not by when the play state last
changed.** They are different columns and the difference is visible:
starring a half-heard episode from two years ago must not put it at the
top of "where was I".

**A cross-show cursor carries the filter it was issued under.** The two
orders interleave differently, so a key issued against publication time
read as a last-played time would land the keyset search somewhere
plausible and wrong. Reusing one across filters is `invalid-request`.

**`unplayedCount` joins `Subscription`, and it is the whole backlog.**
That is the number a tile shows, and it is precisely the number a client
cannot compute: counting the page it happens to hold would report a
window as the backlog. It costs a walk of the show's episodes and a
batched play-state read per subscription, so it is opt-in per caller:
the API's own listing asks for it, and the Subsonic adapter, which pages
every subscription and then lists their episodes anyway, does not, since
nothing in that protocol carries the number. It is computed *after* the
keyset slice, so a page of twenty costs twenty walks rather than the
whole list's worth.

**Absent and zero are different answers, so the field is nullable all
the way down.** Only the listing computes it; subscribing and saving
settings answer without one. A hard zero there would tell a client that
had just followed a four-hundred-episode show that it has nothing
waiting.

**The tile's other two numbers ride the same walk.** A subscription row
used to carry neither `episodeCount` nor `lastPublishedAt` (`showDTO`
skips both unless asked, and the listing did not ask), which quietly
made the hub's default "Recent" sort a no-op that fell through to title
order, and made the tile's "N episodes" fallback unreachable. The walk
that counts the backlog has the episodes in hand, so all three come from
it. Two walks for one tile would be the alternative, and a sort that
silently does nothing is the thing to avoid.

**Both of those reads assemble the catalog in Go, and that is the wrong
layer.** The count walks a show's episodes; the cross-show listing walks
every subscribed show's, sorts the lot, and pages the slice per request.
It is what `Episodes` already did for one show, so it is the file's own
idiom rather than a new one, and at a listener's scale (tens of shows,
twelve rows asked for, no paging from the hub) it is correct and
affordable. It is still a walk where a query belongs, and it does not
survive a power user's OPML import. WaxDeck cannot write that query:
WaxBin's item field map has `podcast` (the show's *title*) and no
`podcast_pid`, so there is nothing to filter an indexed count or an
indexed keyset page by. Filed as an upstream ask with the workaround
recorded beside it, which is this file's standing contract for a gap
like that.

*Amended 2026-07-31: half of that is no longer true.* `podcast_pid`
landed, and the tile's three numbers are two counting queries and a
one-row read for any caller who may see explicit content. The walk
survives only for a restricted account, because the gate it applies
(`ep.Explicit && !uc.Explicit`) has no item query field behind it; that
is the remaining upstream ask. The cross-show listing is still a slice
in Go, and the correction is that `podcast_pid` was never going to fix
it: `QueryPage` owns `sort_key` ordering and ignores a query's own sort,
so a newest-published cross-show listing has no keyset primitive behind
it at all. See ADR-0040.

*Amended 2026-08-02: the walk is gone entirely.* The `explicit` and
`podcast_explicit` item fields landed, so the gate pushes down and the
tile's three numbers are the same two counts and one browse for every
caller. Restricted callers gate on **both** flags, which changed one
answer deliberately: a restricted subscriber to a channel-level explicit
show now reads zero rather than that show's unflagged episodes, which is
what `allowedByContent` and the show detail's 404 already told them. The
show detail header counts the same way, so it can no longer contradict
the episode listing drawn beneath it.

`recent-episodes` landed too, so the cross-show listing is a keyset
browse of the catalog and no longer assembles every followed show in Go.
Two consequences ride with it. Episodes with no publication date drop
out of `latest` and `unplayed` - the list is ordered by a date they do
not have - while still appearing on their own show's listing and still
counting toward `unplayedCount`; the spec says so. And `in-progress`
stays ranked in Go, because a checkpoint never stamps `last_played_at`,
so no discovery list can define either its membership or its order. It
reads its membership from `position_ms gt 0 AND finished is 0` and ranks
the result, which is a strictly smaller population than the walk held.

**"Mark older episodes as played" is one request per episode, and the
dialog says so.** Played is derived server-side from the position
reached against the item's duration, so there is no flag to set: saying
an episode is played means checkpointing it at its own duration. There
is no bulk endpoint and this decision does not ask for one. The
operation is rare, it is the listener's own backlog, and a progress bar
over a bounded loop is a better answer than a new endpoint whose
semantics would have to be invented. The loop runs oldest first, so a
run interrupted halfway has cleared the oldest dots rather than a random
scatter, and it reads the backlog from the repository rather than from
the screen's loaded pages, because the backlog this exists for is
exactly the part nobody scrolled to.

**An episode whose feed declared no duration is skipped rather than
checkpointed at zero.** Zero is "not started", so writing it would be
the opposite of what was asked. The batch says how many it skipped and
why.

**Filters, search-within-show, and multi-select are client-side over the
loaded pages, and the copy does not pretend otherwise.** There is no
per-show search on the wire and no filtered episode listing; narrowing
what is on screen is what the field and the chips promise. Seasons join
the same chip row as Unplayed and Downloaded because they are the same
question (which of these episodes), and a feed that numbers no seasons
offers none.

That has a trap in it worth naming, because the obvious empty state
walks straight into it: a filter that matches nothing on the loaded
pages leaves a list with no rows, and a list with no rows does not
scroll, so the notification that pages the next one can never fire. A
show whose first page is all played would show "nothing matches" with
five hundred unplayed episodes behind it and no gesture that could reach
them. Where there are more pages, the empty state carries a button
instead. The way out has to be a control, because the gesture is
exactly what is missing.

**"Add to queue" appends and does not play.** It went out calling the
replace-the-queue-and-start verb, which on a batch of six is both the
opposite of what the label says and destructive of whatever was already
playing. It is the one action on the screen that promises not to
interrupt anything. Episodes whose feed named no audio are dropped from
the batch and counted in the toast rather than queued as entries that
die on arrival.

**The progress read is windowed, not accumulated.** The batch is keyed
by the pids it covers, so keying it on the whole loaded list meant every
`loadMore` minted a new provider that re-read every page before it: the
fifth page of a show costing five pages of play states. Windows are the
listing's own page size and the listing only ever appends, so a
completed window is answered once and a new page disturbs at most the
last one.

**The keyword filter is two comma-separated lines, not a chip editor.**
A filter is two or three words in practice, and a line of text is the
shape a listener can read back at a glance and paste between shows. An
empty filter is saved as *absent* rather than as two empty lists,
because absent is what the contract calls "take everything" and an empty
document invites the next reader to think a filter is set. The sheet
says the filter applies to future arrivals only and needs auto-download
on, because both are true and neither is visible from the control.

**OPML export is a copyable document, import is a file pick.** The same
answer the playlist export gives, for the same reason: the web build has
no file-save surface, and an OPML document on the clipboard pastes into
every other podcast client's import box. Import is hidden without a file
picker, which is the contract every pick affordance in this app follows.

## Consequences

The design system grew three things rather than the screens growing
private copies. `WaxMenuButton` is the overflow every rebuilt screen
needs, with one semantics handle per row (the chrome's own private menu
already worked this way, and the reason is the same: a `PopupMenuButton`
draws a second node for one control). `MediaListRow` learned a resume
sliver, a downloaded glyph, an unplayed dot, a leading text slot for a
publication date, per-row actions, and a selection checkbox.

That last change exposed a real defect and fixing it is the part worth
remembering. The row wrapped its whole subtree in
`Semantics(excludeSemantics: true)` to announce itself once, correct
while a row was only ever a label with a tap, and wrong the moment a row
hosts controls, because excluding the subtree takes their nodes down
with it. Every per-row fetch, remove, and details button would have been
invisible to a screen reader and to the suite while looking perfectly
fine on screen. The label now sits on the row's *content region*, with
the controls beside it as siblings. This is the third time this shape of
bug has landed (P8's keyboard-unreachable chrome, P10's overlay covering
the sidebar field): a node that speaks for a subtree silences it.

Two smaller layout rules came out of the same work, both pinned by
goldens. The resume sliver only wraps the row in a `Column` when there
is a position to draw, because a `Column` around every row would take
the vertical centring in the min-height box away from every list in the
app to serve the one that resumes. And the unplayed dot only introduces
a `Row` around the title where there is a dot, because an `Expanded`
title lays out to the full width rather than to its own: invisible in a
normal render and immediately visible in the obscured-text goldens,
which measure exactly that.

The queue grew `NowPlayingController.enqueue`: adding to the end without
disturbing what is playing had no verb, and the summaries are recorded
first for the reason `play` records them, so a queue row does not read
"Loading" for something the screen was showing a title for.

`refreshPodcast` was in the spec and the generated client and had never
been wrapped by the repository layer; the show's overflow is its first
caller.

**A fixture, mistaken for a bug, and worth recording as both.** Marking
a backlog played appeared to do nothing: the crossing is derived from
the position reached against the item's duration, and an episode nobody
has fetched has no *measured* one. The first fix was a fallback that
looked the feed's declared length up from the episode row. That fallback
was dead code. The catalog's item view already coalesces to the feed's
duration for a fileless item, so the threshold worked all along; what
was actually broken was the fixture feed, which declared no duration at
all and so exercised nothing. The feed declares one now, the fallback is
gone, and the integration test says out loud that the episodes it marks
are unfetched, which is the property that matters and the one nothing
was pinning.

Deleting it mattered for more than tidiness. It fired before any
threshold test, so it was an extra read on every checkpoint for a
fileless episode, and passthrough makes streaming an unfetched episode
the ordinary case, with a checkpoint every few seconds while one plays.
A dead fallback in the wrong place is a read per tick.

The mark-older loop landed sequential and is not: each checkpoint is its
own round trip, so three hundred episodes was thirty seconds of staring
at a bar on any real network, and latency rather than the server was the
whole of it. Six ride at once now. That costs a little of the
oldest-first guarantee (a stopped run can leave up to a batch ragged at
the boundary), which is a much smaller lie than the scatter an unbounded
fan-out would leave, and the ordering is the point of walking oldest
first at all.

Two defects in that dialog, both found by writing the test before the
fix and both about a run outliving the surface that started it.

The pop was guarded on `mounted`, which is not the question it looks
like: popping a route begins a transition, so the State stays mounted
for the length of the dismissal animation, and a checkpoint landing
inside that window found `mounted` true and popped again, taking the
show screen with it. The flag the Stop button sets is what actually
means "this dialog is on its way out", and `dispose` sets the same one.

And the invalidation was reachable only on the path where nothing had
gone wrong, so stopping halfway left the episodes it *had* marked
showing unplayed dots. It runs on the way out now, through the provider
container rather than `ref`, because that is the whole point: the writes
outlive the widget, and what they wrote has to reach the screens
underneath whether or not anybody is still looking at the dialog.

One trap, found by a test that timed out rather than failed: the batched
play-state read is a family keyed by a *string* of sorted pids, not by a
`List`. A family keys its instances by `==`, a `List` has identity
equality, and a screen that builds its key during `build` mints a fresh
provider every frame, each one fetching and settling into another
rebuild. The key builder is the only way to make one.

A second, found the same way: the shell test navigated to an episode the
fake did not have, and Riverpod's automatic retry on the failed read left
a timer pending past the test. The fixture now holds the episode it
navigates to, which is what a chrome test should have been asserting
against anyway.
