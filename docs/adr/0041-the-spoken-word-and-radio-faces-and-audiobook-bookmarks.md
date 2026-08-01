# 41. The spoken-word and radio faces, and audiobook bookmarks

Date: 2026-08-01

## Status

Accepted.

## Context

ADR-0039 landed `PlayerScaffold` and the music face. Podcasts, books, and
radio got the scaffold and the controls they already had - a speed button
that cycled a fixed ladder, a silence-trim chip, a chapter button that
opened a sheet - which was deliberately less than the design asks of them.
Four things were held back and named: the speed sheet, smart rewind,
bookmarks, and the chapter, notes, and transcript regions.

Radio had no player face at all. A station took the engine, the deck bar
drew it, and the bar's expand control went to the hub the station was
tuned from - a listing of every station, rather than the one that is on.

Audiobook bookmarks were scheduled as a first-party REST addition "over
the storage the Subsonic adapter already exposes
(`getBookmarks`/`createBookmark`/`deleteBookmark`)". That premise is
wrong, and finding out is part of what this phase settled: the Subsonic
handlers map those three verbs onto **resume positions**
(`RecentlyPositionedItems` plus `Checkpoint`), because that is how the
clients calling them use them. There is no bookmark store under them, no
notes, and no more than one mark per item.

## Decision

### Bookmarks get their own table, and are a different thing from a resume point

`book_bookmarks` in the WaxDeck database, keyed by user and book, ordered
by position on the book timeline. A book has one resume position and any
number of bookmarks, and nothing about a bookmark moves as playback does.
The Subsonic surface is left exactly as it is: the clients that call it
want the resume position, and giving them real bookmarks instead would
break the parity it exists for.

Three endpoints, no cursor: `GET|POST /books/{pid}/bookmarks` and
`DELETE /books/{pid}/bookmarks/{bookmarkId}`, with a 200-mark cap per book
enforced inside the insert. A book holds a handful of these, and a
listing that pages would be machinery for a set that never needs it.

Two refusals are deliberate. A position past the book's own end is
rejected rather than stored, because the two ways to produce one - a
stale client, an arithmetic slip on a multi-part book - both make a mark
nothing can seek to. And the cap answers `invalid-request` rather than
`conflict`: it is something the listener can act on ("delete one first"),
where a conflict code sends a client looking for a concurrent write that
never happened. Deleting a bookmark that is already gone answers 204 -
the outcome asked for holds either way.

**Bookmarks are a live read, not mirrored state.** The sheet fetches on
open, the create places its answer rather than refetching, and nothing
enters the sync stream. That keeps a sync kind, a delta shape, a mirror
table, and an offline write queue out of the tree for a feature whose
only offline gap is marking a place on a plane - which is written down in
deferred work rather than built on spec.

Placing rather than refetching has one ordering rule: an edit waits for
the first read to land before it publishes. The button that opens the
sheet is drawn while that read is in flight, so a quick tap-and-mark
reaches the controller first, and a read issued before the mark existed
cannot carry it - it would land afterwards and take the mark straight
back off the screen.

`getBookDetail` also stopped handing the store's own error out. A
catalog miss becomes "no book with pid ..." at the service rather than
`store.ItemByPID: no such item: ...`, because the bookmark delete is the
first book route with two things that can be missing and therefore the
first one that answers with the error it was given rather than a message
it wrote itself.

### Smart rewind hangs off the engine's play transition, not off a control

The step is owed to whatever break preceded the play: the pause the
engine last made (device clock) or, for a session loaded without
playing, when the listener last left the item (`PlayState.updatedAt`).
It is spent on the play and never before it. Both are seeks, so listen
accounting is untouched - the time is heard twice and counted twice,
exactly as it would be if the listener scrubbed back by hand.

Two things follow from putting it on the transition rather than on a
button, and both are the point.

**It cannot be bypassed.** A play arrives from the lock screen, a
headset, a media key, and a routed Connect command as well as from a
WaxDeck control, and every one of those goes straight to the engine.
The overnight resume this feature exists for is most often one of them,
so a control-side step would have covered the path that is hardest to
reach and none of the ones a phone in a pocket actually uses. The pause
was already stamped this way; the play now reciprocates.

**It cannot walk a checkpoint backwards.** A queue put back at launch
loads without playing and may never be played at all, and the session
writes its position back when it lets go. Applying the step at load
would move what gets written, so ten cold starts nobody listened to
would lose five minutes of a book. The load stands where the checkpoint
says and the first play spends the step.

The one case that still applies it at load is a start that is itself a
play, where doing it as part of the load rather than as a seek after it
keeps the seam clean.

Three things it deliberately does not do. It never touches music: a track
resumed a week later starts where it stopped, and three seconds into a
song is noise rather than context. It never moves an **asked-for**
position - a chapter tap, a shared timestamp, a book resume - because
that is a request for a place rather than a resume, and stepping back
from it would land before the thing somebody asked for. And it never
steps past the head of the item.

The setting is `off` / `short` / `long`, per device, defaulting to
`short`, which is the ladder 5.3 states (3 s after 5 min, 10 s after 1 hr,
30 s after a day). `long` doubles it. Per device rather than per account
because it is about how this listener listens on this machine: a phone
picked up on a commute and a desktop left running overnight lose the
thread differently.

One caveat is worth naming rather than papering over: the cold-start gap
is measured between a server-written stamp and this device's clock, and
a self-hosted server whose time has drifted makes it wrong. The damage
is bounded by the ladder - the worst case is thirty seconds of replay
where three were owed, or none where some were - and a stamp that reads
as being in the future rewinds nothing. Within a session both ends come
from the same clock.

### The sleep timer's extension is a control, and it lives on the notification too

`extend()` buys ten minutes **from where the timer stood**, not from now:
extending with four minutes left is asking for fourteen. A fade already
running is a timer that has fired, so extending re-arms it, and the
generation bump that re-arm performs is what tells the ramp to put the
level back instead of pausing under a timer that is running again.
End-of-chapter mode extends into a countdown: there is no next boundary
to move to, and a listener pressing extend as the chapter ends wants more
time rather than the following chapter.

The notification's button is up for **the whole time a timer runs**,
rather than only during the final fade 5.6 describes. A listener who
wants another ten minutes usually knows before the sound starts going,
and a control that appears only in the last ten seconds is one most of
them never see. It costs one button on a notification that is already
there.

The wiring is a `MediaSessionHandle` in the app and a `MediaSessionPort`
in `waxdeck_player`: a holder rather than a provider override, because
the media session is registered after the container is built (it needs
the local mirror) and most platforms never register one at all. Callers
raise their control unconditionally and the holder absorbs the
difference. Shake-to-extend stays what 5.6 calls it - an optional stretch
- and is not built.

### Voice boost reopens the stream, because the server is what applies it

The boost is applied when the server mints the stream, so persisting the
setting alone would be a toggle that does nothing until the item is
loaded again. The chip persists and then reopens what is playing at the
same position, which is why it can be busy: a round trip and a reload
stand between the press and the sound changing.

A downloaded original carries no boost and cannot be given one, so the
offline branch is left alone: the setting is stored for the next online
play and the local file keeps playing. That is the honest behaviour, and
it is why the reopen is guarded rather than attempted.

The chip also answers for the write. A session whose per-show settings
could not be fetched has nothing to store the choice on, and unlike a
playback rate - which changes the engine whether or not it is
remembered - a boost that was not stored changes nothing at all. So the
toggle reports whether it took, the chip puts itself back when it did
not, and the reload is skipped rather than spent on a stream that would
come back identical.

Both effects explain themselves once per device, on the way on only. An
effect being switched off has already explained itself, and a sentence
that appears every time is one nobody reads. The flags are stored keys
rather than settings, and are deliberately absent from the settings
registry: "show me that hint again" is not a preference anybody has.

### The chapter list is the bottom region, and the region yields to the transport

5.3 puts chapters, notes, and transcript in the player's bottom region,
which replaces the chapter button and its sheet. The region takes a fifth
of the window, capped at 200 px, and scrolls inside that.

The cap is the decision worth stating. Built first at a third of the
window, the region pushed the transport below the fold on a 600 px window
- the play button was still in the tree, still had a paint position, and
was simply not on screen. The region is what an item says about itself
and the transport is what the screen is for, so the region is the half
that gives.

The scaffold's portrait column also stopped being able to overflow. Its
cluster stack is now bounded to the slot and scrollable inside it, so the
hero yields first while there is room and the clusters scroll past it
when there is not. As a free-height child they simply took what they
wanted, and any face whose action row wrapped to a second line overflowed
by exactly that much.

### The radio face is a face, and the deck bar expands into it

A station gets the scaffold with the slots that mean something: the logo
on a platter with a turning amber ring, the ICY line under the name, a
LIVE pill where the seek bar would be, one transport control that stops
rather than pauses, the local volume, the pin, and the sleep timer. No
seek, no next, no repeat, no speed - radio never enters the queue, and a
control that implied otherwise would be a lie.

The ring is the one piece of ambient motion in the app and the only
honest one available: a live stream has no position, so nothing about it
can be derived from playback except whether it is happening. It stops
under reduced motion, which is exactly what that setting is about.

The deck bar's radio face now expands to the player like every other face
of that bar. Expanding means "show me what is playing", and since this
phase that is the station's own face rather than the listing it was tuned
from; the hub is one row away in the face's overflow.

What the one control does belongs to the controller rather than to
either surface. A live stream ends on its own - a host that went away, a
network that dropped - and the engine simply stops; both surfaces read
that as "not playing", drew a play glyph, and called stop on it, so the
one control on a dead station said play and tore the station down. The
controller is the only thing that can tell a refused start (media still
loaded, wants the gesture the browser was waiting for) from a stream
that has to be opened again, so it owns the decision and both surfaces
ask it.

### Two deviations from 5.3, recorded

**The episode title is not a link.** 5.3 says "show name above episode
title, both tappable". The show name is a link and the title is not: the
player's bottom region now carries the notes, the chapters, and the
transcript, which is what the episode screen has, so a link from the
player to a screen that duplicates it is not an improvement. The
overflow's rows are 5.3's own list, and none of them is "go to episode".

**The chapter reads under the title, and the book's progress under the
bar.** 5.3 asks for the chapter title under the book title and the
percentage in a caption; both hold. What is not there is a second copy of
the chapter beside the bar it spans, which would be the same words twice
within sixty pixels.

## Consequences

- The plan's section 11 item 1 is corrected in this ADR rather than in
  the plan: the Subsonic adapter never had bookmark storage, and the
  first-party endpoints stand on a table of their own.
- `WaxSegmented` joins the design system, used by the book face's
  Chapter/Book toggle. `FilterChipRow` already documented itself as
  "the segmented control for choices that outgrow a segmented control";
  this is the control it was describing.
- `WaxPill` joins it too, and the reason is the splash rule: the
  player's surfaces are transparent Materials, so an ink response under
  an opaquely decorated Container never paints. Every pill in this phase
  had to know that, said so in its own comment, and two of them still
  disagreed about their unselected fill. One primitive says it once, and
  a caller on a raised surface names what it sits on so the pill lifts
  off it.
- The scaffold's landscape arrangement measures its own slot rather than
  the window. It never had to before: nothing sat under it until the
  spoken-word faces gained a bottom region, and a hero sized from the
  window overflowed a short landscape window by whatever that region
  took.
- `PlayerScaffold` gains three slots: `titleOverline` (a show name above
  the title), `subtitleOverride` (a line under the title that ticks), and
  `heroOverlay` (the platter ring). Each is filled by exactly one face.
- Marking a place needs the server. The offline gap is tracked.
- `spawnlint`, the contract gates, and the drift gate are unaffected: the
  new endpoints are generated like every other, and nothing here starts a
  goroutine.
