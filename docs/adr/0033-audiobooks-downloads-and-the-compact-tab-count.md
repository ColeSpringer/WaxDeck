# 33. Audiobooks, the downloads manager, and the compact tab count

Date: 2026-07-29

## Status

Accepted.

## Context

Audiobooks were the domain with no front door. A book had a detail screen -
written before the design system, on a Material scaffold - and the only
way to one was a card on the library grid. There was no hub, so the
layout system's own rule kept the Audiobooks tab out of the shell: a tab
with nothing behind it has nowhere to send anyone.

Downloads were the reverse: a whole engine with no surface at all.
Original files have been fetched, resumed, and played offline since the
sync slice; nothing has ever listed them, said how much room they take,
or offered to reclaim it. Two capabilities had never had a single caller.
`DownloadManagerPort.remove` drops an item's audio, and
`ArtworkStore.unpin` drops the cover pinned beside it (ADR-0025) - and
they have to be called together, because the pin is kept by pid in a
table the downloads port knows nothing about.

Offline multi-part books were a known lie. The download path stores every
part; offline playback loaded `paths.first`, never sequenced the rest, and
applied a book-timeline resume position to file one. So a downloaded
twelve-hour book resumed at hour eight by playing forty minutes into part
one.

And adding the fifth domain forced a question the shell had been carrying
since the flip: 3.2 puts the account avatar in the top app bar, the shell
owns no app bar, so P8 gave it a fixed cell at the trailing end of the
tab bar. A fifth domain makes six targets on a phone.

## Decision

### The contract

**`DownloadFile` grows `durationMs`, and it is the file's duration, not
the item's.** This is section 11's item 5. The two differ in both
directions and the field says so: each part of a multi-file book reports
its own, which is what lets an offline client place a book-timeline
position without asking the server; a carved virtual track reports its
*containing* file's, with the span giving the item's window inside it. It
is optional, because a file no scan could probe has no duration to
report, and omitted rather than zeroed - a client sequencing parts has to
tell "forty minutes" from "nobody knows", and a zero would stack every
later part at the same offset. Additive, `oasdiff` clean.

**Offline part resolution mirrors the server's, and it is the same code
path above it.** `LocalPlayback` carries parts rather than paths, and
answers which part holds a book-timeline millisecond. `PlaybackSession`
sets the same four fields from it that play-info sets - part index, part
count, part start, loaded duration - so everything above resolution
behaves offline exactly as it does online: the display timeline,
checkpoints in book milliseconds, a seek that leaves the part, and the
roll into the next one.

**An item whose stored parts carry no durations is not sequenced, and
plays its first file.** That is what the code did for every book before
this, so a download taken under an earlier release is no worse than it
was - and it is better than the alternative, because a part's offset is
the sum of the ones before it and one missing value puts every later part
somewhere invented. Asking for the item again fills them in, which the
manager's stale sweep does; `download` also refreshes the record on the
path where it keeps the bytes, so a listener does not re-fetch a
gigabyte to gain a number.

**A book that loses the server mid-read carries on from its own files.**
Rolling into the next part used to end the session when play-info failed.
A downloaded book has the next part on disk, which is the whole point of
downloading one: the reader is on a train, not at a boundary the app
should stop at.

### The audiobooks hub

**One listing, arranged client-side.** `GET /library/items?mediaType=audiobook`
orders by title and offers no author or finished predicate, and a library
holds tens or hundreds of books rather than the tens of thousands of
tracks the music indexes page through. So the hub loads them and answers
every sort and filter from what it holds, instead of minting a cursor
space per chip. The page size is the queue cap, for the reason the music
listings use it: playing from the grid plays what the screen has.

**The author chips come from the loaded books, not from the facet
endpoint.** That endpoint enumerates artists across the whole library, so
its buckets count an author's music alongside their books and its keys
drill to a mixed listing. This is P11's bug seen from the other side - an
artist bucket counting two audiobooks opened to an empty music list - and
the authors worth offering are the ones on the shelf in front of you.

**"Recently added" reads off the pid.** A listing carries no added-at
field, and a pid is a ULID: it sorts lexicographically by mint time. So
the order the catalog took books in is available without a contract
addition, and it is what a listener wants when they open the hub after an
import.

**"6 hr left" is drawn and "6 hours left" is spoken.** A book's remainder
is a span, not a position, so a timecode is the wrong readout - "7:50:12
left" is telling you a clock time. `formatSpan` abbreviates it to what a
cell has room for, and `MediaTileData.trailingSpoken` carries the spelled
form for the ear, because "6 hr" read aloud is not feedback. That
distinction is `spellDuration`'s own reason for existing, now available
per tile.

**A filter that matches nothing is a different empty state from an empty
library.** The way out of "nothing matches" is the chips above it, not a
scan, so it says so and offers the control. This is P12's lesson about
empty states that hide a backlog, applied before it could bite.

### The book screen

**Resume names the chapter it will land in.** The verb is the promise:
"Resume Roast Mutton" beside "38 percent · 7 hr 50 min left". The chapter
comes from `GET /books/{pid}/resume`, which is the cross-device answer;
where that read has not landed the screen draws the batch play state's
position and a plain "Resume", so the button is never wrong, only less
specific.

**Mark finished and start over are position writes with an undo, and the
undo restores what was actually there.** Played and finished are derived
server-side from the position reached, so there is no flag to set: saying
a book is finished means checkpointing it at its own duration. The
previous position is read immediately before the write rather than taken
from what the screen last drew, because the resume point is the
cross-device one and an undo that put back a stale value would move the
listener somewhere they never were. The undo runs through the container,
not through the widget's `ref`: the write outlives the screen, and a book
left behind while the toast is still up must not take the undo with it.

**The current chapter is *selected*, not *playing*.** `playing` means the
engine is on this item, and the row draws animated bars over its leading
slot - which would take the timecode away from the one row whose position
a listener most wants to see, and claim playback for what may be nothing
but a saved place.

**A multi-file book says so, in a footnote where somebody is looking at
it.** "This book is 3 files, played as one timeline." The parts are an
implementation detail of the source, and the only person who needs to
know is the one wondering why their book is three rows in a file manager.

**The series line narrows the hub to the author.** The catalog has no
series dimension to drill, so a series is not a location. Sending the
listener to the author's books is where the rest of the series actually
is; the route lands when the dimension does.

### The downloads manager

**Removing a download is two calls, and this screen is the only caller
either has ever had.** `DownloadManagerPort.remove` for the audio,
`ArtworkStore.unpin` for the cover. The first is unmissable while
building the screen; the second is exactly what gets left behind, as
orphaned image files nothing short of a sign-out reclaims. Every removal
path goes through one controller method so there is one place to get it
right: a row, "Clear all", and "Remove finished episodes".

**The storage header reports what WaxDeck holds and not what the device
has left.** The plan asks for device free space; nothing in Dart's own
libraries answers how much room a volume has left, `Process.run` is
unavailable on iOS and there is no `df` on Windows, and pinning a plugin
for one number is a decision of its own. Used bytes by medium is the half
that can be honest and the half a listener can act on. The absent half is
recorded in deferred work rather than faked.

**"Re-download stale" asks for every held item again, and that *is* the
staleness check.** Nothing local can tell a stale file from a current
one: staleness is a comparison against what the server has now, and there
is no stored flag that could hold it. `download` already makes exactly
that comparison per file - it fetches download-info, keeps any file whose
essence hash still matches, and re-transfers the rest - so the sweep
costs one request per item and re-downloads only what moved.

**Pause answers whether it took.** A transfer the plugin cannot pause (a
server with no range support) stays running rather than being canceled
behind the listener's back, and the control says so instead of flipping
to Resume. Cancel is the honest verb there, and it is beside it.

**"Remove finished episodes" means episodes.** A book or an album played
through is one somebody may want again; an episode is the medium whose
whole point is that it is done with.

**Played state comes from the mirror, not the server.** This is the
screen most likely to be open with no network, and a played dot that
needs a round trip is no dot at all.

### The shell

**Audiobooks is a primary destination with its own branch, and
`/books/:pid` is re-homed beneath `/books`.** It hung off home because
the library grid was where books were reached from; now the hub is, so a
book is gone to from there and pushed from anywhere else (a search hit,
a shelf), which is 8.3's rule.

**Downloads is a native-only secondary.** 4.1 puts it in the sidebar and
the avatar menu rather than in the tabs, and it is hidden where the build
keeps nothing offline. Not a permission - a platform capability, and the
screen behind it has no data source at all on the web. The *route* is
still declared there, so a link pasted from a phone lands on an honest
empty screen rather than on not-found.

**The compact tab count: the fifth tab gives, conditionally, and the
account cell stays until P17.** This is the decision the phase was
holding, and it is 4.1's own mechanism rather than a new one - a domain
tab hides when the server has nothing behind it, and home absorbs the
gap. `emptyDomainsProvider` probes once per session with one
one-item request, and only audiobooks gates on it: it is the medium a
library most often has none of, and Podcasts and Radio stay
unconditional until their own phases have a count to gate on. An
unresolved probe *shows* the tab, because a tab arriving late shifts the
row under a thumb already moving, and the libraries that would gain one
are the ones nobody is aiming at it on.

The all-five case was measured rather than argued about, and it fits: at
five domains plus the account cell, each tab gets 59 px at 360 px of
window and the selection pill needs 54, with every label inside its cell.
At 320 px - a phone narrower than anything current - one label
("Podcasts", at 52.6 px in a 51.2 px cell) ellipsizes, which is reflow
rather than truncation: the glyph carries the meaning and the accessible
name is untouched. No overflow at any width or text scale tested.

The other two options were available and worse. Dropping the fifth tab
unconditionally would have contradicted the phase's own job. Moving the
avatar onto the screens' app bars is P17's, and it cannot be done here:
home and radio are still on Material scaffolds with no `WaxScaffold` bar
to host it, so an early move would put the avatar on three of five tab
roots and nowhere on the other two.

**Every branch is declared whether or not its tab is drawn.** The branch
index is `goBranch`'s contract, so a branch that came and went with a
count would renumber the ones after it. A domain with nothing behind it
loses its tab, not its routes, which is also what keeps a shared link
into one working.

## Consequences

**The play-state batch left podcasts.** The mechanism podcasts built - one
batched read keyed by a sorted pid string, windowed to the listing's
page size - is the same question a books hub asks, so it moved to
`src/player/play_progress.dart` as `PlayProgress` and friends rather than
being copied. A second copy would have been a second chance to step on
the trap that mechanism exists around: a family keys by `==`, a `List`
has identity equality, and a key built during `build` mints a fresh
provider every frame. It grew `updatedAt`, which is what orders a
continue-listening shelf across devices, and `remainingOf`, which three
surfaces were about to compute by hand.

Two widgets came out of `player_screen.dart` for the same reason. The
download control and the item star/rating row were private there and are
exactly what a book's header needs; `DownloadAction` and
`ItemStarRatingRow` are public siblings of the existing
`EntityStarRatingRow`. Promoting the download control is what put the
audio-and-cover pairing in one place on the *adding* side, matching what
the manager does on the removing side.

**`PlaybackSession._playInfo` is gone.** It existed to answer "how long
is the loaded media", and every one of its readers wanted that number
rather than the object. Reading it was also the bug: on the offline path
there is no play-info at all, so the part arithmetic - where a seek
leaves the loaded part, where the next part starts - summed to zero, and
`_advanceToNextPart` would have re-resolved part one forever. One
`_loadedDurationMs`, filled by both load paths, and neither has to know
which resolved it.

**A shelf card and a grid row are two controls, so they wear two
handles.** A half-heard book is on the continue shelf *and* in the grid
below it, and one identifier on both makes a click a strict-mode
violation rather than a tap - which is how the e2e journey failed before
the handles were split. The podcast hub had the same shape and shipped
with it: `unplayed` is below the played threshold and `in-progress` is
any saved position, so an episode a third of the way in is on both
shelves, and `podcasts.spec.ts` worked around it by never tapping a hub
row. That is fixed here rather than filed, because nothing later in the
plan re-opens that hub, and a workaround living as a comment in one spec
is invisible to the next author. `episodeContinue` beside `episode`,
`bookContinue` beside `book`, and a widget test on each hub that the same
item on screen twice carries two handles.

**Two design-system defects, both found by the books hub and both older
than it.** `MediaCard` never clamped its trailing readout, while
`heightFor` reserves exactly one caption line for it - so a readout that
wrapped overflowed the cell by exactly one line, which "1 hr 20 min left"
did. Any long trailing text would have done it; a book is just the first
thing with one. And the same card had no way to say a different thing to
a screen reader than it draws, which an abbreviated readout needs.

**The migration trap, caught by the test that exists for it.** A column
added by a migration has to be declared *last* in its drift table:
`ALTER TABLE ADD COLUMN` appends, so a column declared in the middle sits
in a different position on an upgraded database than on a fresh one. The
fresh-install equivalence test in `schema_migration_test.dart` failed on
exactly that, which is the third time that test has earned its place. The
v3 snapshot is now beside v1 and v2, because v3 is the only shape where
`download_records` exists without a duration while everything else is
current - the path this migration's one step actually runs on.

**A review round then landed four fixes, and the first two are the same
mistake seen twice: a comment asserting a property the code did not
have.** The undo toast's own comment said it ran "through the container
rather than through this widget's ref" and then passed the `WidgetRef` - so
walking away from a book while the toast was up and tapping Undo threw
`Bad state: Using "ref" when a widget is about to or has been unmounted`.
That is exactly the shape ADR-0032 records for the mark-older dialog, and
the fix is the same: capture the container and the repository before
showing the toast. The test for it was checked against the old code
first, because a test that would have passed either way is worth nothing
here.

And the offline part fallback was written into `_advanceToNextPart` alone,
which is only one of five ways to cross a part boundary. A seek, a chapter
tap, the deck bar's skip, and repeat-one's `replay` all go through
`_loadPartFor`, and three of those call sites do not await - so a server
that went away mid-book turned a seek into an *unhandled async error*
rather than a failure anyone could see. The fallback lives in
`_loadPartFor` now, which is where every crossing already passes, and it
rethrows for parts that cannot be placed on a timeline so `start`'s own
offline branch still owns those (it has the mirror's position and the clip
window; this does not).

Two in the download store, both about a transfer outliving the record it
belongs to. `remove` deleted rows and unlinked files while a transfer for
the same pid was still running, so the file landed back on disk with
nothing naming it and a completion fired against a deleted row - reachable
through "Clear all", which sweeps every row it holds, in flight included.
And the taskId-to-pid map only ever grew: `_forget` runs on the terminal
states, where no further update can arrive, so every map can drop the
entry. A paused task never reaches it and keeps its mapping, which is what
lets it resume.

**Both of those were found by reading rather than by a red test, and that
is what got fixed rather than filed.** `BackgroundDownloadManager` had no
coverage at all, because `FileDownloader` was a plugin singleton it
reached for directly - and this is the class that unlinks a listener's
files. `TransferEnginePort` is the seam: `start`, `pause`, `resume`,
`cancel`, and a stream of four states, with `BackgroundTransferEngine`
holding everything plugin-shaped behind it - the task objects, the status
vocabulary, the app-support directory, the resume-or-re-enqueue dance, and
the platform call that resolves a finished file's path. The plugin's own
types never cross the line, so nothing above can come to depend on its
data model, and the manager now deals in ids and four states.

The class went from zero tests to 26, and the shape of the two bugs is
what they are about: that `remove` stops transfers *before* touching rows
or files, that a canceled transfer reporting late touches nothing, that a
terminal id is forgotten so a repeated report cannot rewrite a settled row
or announce a completion twice, that a paused one is *not* forgotten
because resume needs it, and that the last reference is what unlinks a
file two items share. Each was checked against the pre-fix code, and the
first attempt at the map-growth test was thrown away for passing either
way: it asserted through `_tasks`, which the bug did not touch. A leak has
nothing to see on its own, so the test asserts the thing a stale mapping
makes possible instead.

**One review suggestion was declined, and the reason is now a comment
where it will be read.** Bulk removal loops sequentially and a
`Future.wait` would be faster, but `remove` decides whether to unlink by
asking whether any *other* row still holds the same essence hash. Two
items sharing one file - CUE siblings share an image - removed
concurrently would each see the other's row still present, each conclude
the file is shared, and leave it on disk with nothing pointing at it.
Clearing downloads is not latency-sensitive; correctness is the whole job.

**What did not land.** The hub has no series dimension, because the
catalog has none: the series line narrows to the author instead. Free
disk space is absent, recorded. And the account cell is still in the tab
bar, which stays P17's entry - this phase forced the count question and
answered it, which is what it was scheduled to do.
