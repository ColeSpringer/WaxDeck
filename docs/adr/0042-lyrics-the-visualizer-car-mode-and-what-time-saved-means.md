# 42. Lyrics, the visualizer, car mode, and what time saved means

Date: 2026-08-02

## Status

Accepted.

## Decision

### The lyrics endpoint answers an absence, not a 404, to its callers

`GET /items/{pid}/lyrics` has been in the contract since the metadata
work; nothing read it. The client half is a repository method that
answers `Lyrics?` and turns 404 into null, the same shape
`getStagedRestore` already uses. Having no lyrics is what most tracks in
most libraries say - it is the ordinary state of the field, not a failure
- and translating that into an exception would put a try/catch in every
caller and a red pane behind a design that asks for a quiet empty state.
A server that cannot be reached still throws.

Synced lines are sorted on the way in. The contract promises them ordered
by `timeMs` and the karaoke view walks the list assuming it; the values
come out of a sidecar somebody else wrote, and an out-of-order file would
light the wrong line rather than merely reading oddly.

### One `LyricsView`, two shapes, and the panel-or-overlay rule the queue already has

Timed lines are a scrolling list that follows the playhead, tap-to-seek,
with following handed over on a manual scroll and offered back by a
button. Untimed words are a block at a 720 px measure with nothing
moving. Both are one component because they are one answer at two levels
of detail, and which one arrives is the source's decision rather than
the caller's.

The position crosses into the component as a `ValueListenable` and the
highlight moves on line boundaries. A caller rebuilding it per position
tick would repaint a screen of text to move a tick mark once every few
seconds.

The row height is the text's height plus a fixed gutter, not a constant.
A fixed 56 fit two lines of body type at exactly one hundred percent and
cut them at every notch above, which the layout system promises to honour
to two hundred. It is worth knowing how that fails, because it is not how
these usually do: a paragraph handed a maximum height reports that height
and paints the rest below the fold, so there is no overflow banner, no
thrown error, and a widget test asking what the text measured is told the
wrong number by construction. Only comparing against what the type
actually needs catches it. The transcript region carries the same numbers
and got the same fix.

Where it opens is `openLyrics`: the panel where the width has one and
there is something to put it beside, an overlay otherwise, decided in one
place rather than in each control that asks. `WaxPanel` gains `lyrics`.

The second half of that condition is the player. `/now-playing` is a
route pushed over the shell, so it covers the panel slot: opening the
panel from the player would light the control and change nothing anybody
could see. The player therefore always overlays, whatever the width, and
the deck bar - which is shell chrome rather than a page over it - gets
the panel.

`openQueue` takes the same argument and the player's three call sites
pass it. That one is older than this work: the Queue button beside the
new Lyrics button had the identical defect on every window wide enough to
have a panel, and nothing pinned it - the deck bar's test drives the deck
bar's control, and the e2e spec opens `/queue` by location, saying in a
comment that it is avoiding the bar's button for exactly this reason. Two
controls a thumb apart behaving differently is not a distinction worth
keeping, so both moved.

Two controls open it, which is 5.2 and 5.3 both: the music face's action
row, and the deck bar's right cluster, where `DeckBarActions.onLyrics`
has been a declared slot with no caller since the bar was built. Both are
music-only, because the three media that never carry lyrics are the three
other faces; the compact bar drops it with the rest of that cluster.

Both the sheet and the panel find what is playing through
`NowPlayingView` rather than being handed it. The sheet took a captured
session first, which reads as an economy and is a bug: the player keeps
its State across a queue advance, so a sheet left open showed one track's
words while the highlight ran off the next track's playhead, and a tap
seeked a session that had already let go. `PlaybackSession.seek` now
refuses once disposed as well, on the rule the shutdown already followed
for `stop` - a session that has let go must not move an engine a newer
one is driving.

The wire model is mapped into view data in the provider, not in the
widget. `LyricsView` resets a reader's scroll when handed a different
list, which is how a new track puts the highlight back at the top; a
widget mapping inline builds a new list every rebuild, so every parent
rebuild read as a new track and dragged a reader who had scrolled away
back to the playhead. A resolved provider value is one instance. The same
mapping is where a stored-but-empty record becomes an absence: the
contract promises one of the two fields is non-empty, and a client that
took that on trust painted a blank column under a header.

### The visualizer draws what was measured, and nothing else

Two modes: the whole track's peak landscape with the playhead sweeping
it, and the cover as a turning disc inside a ring of the same peaks.
Both are painted from the peaks the seek bar already reads plus the
position, and there is no third mode because there is no third thing this
app can honestly measure. A synthesised spectrum would be an animation
pretending to be a measurement, and the audience that runs its own music
server can tell.

Scrubbing the picture previews and commits on release, which is the
pipeline `WaxSeekBar` already describes. Seeking on every drag frame is a
seek per pointer event at the engine - a stutter on a phone, a burst of
range requests on a stream - and a press that turns into a drag would
have moved playback on its way past. The engine's own ticks are held off
the preview while a finger is down, so the playhead cannot jump back out
from under it.

A file the analyze pass has not measured has no picture and says so,
naming the pass. That is most files on a fresh server, so it is a real
state with a real sentence rather than a spinner that never resolves -
the same rule the seek bar follows for `unavailable`. It branches on the
whole async value rather than on its `value`, which is null while the
read is in flight too: the seek bar can share one branch because its
fallback is a plain bar, but a full-screen instruction to go and run an
analyze pass is not a thing to show somebody for the length of a round
trip.

The played part of the picture is drawn in `colors.accent`, not in the
artwork palette. The palette exposes no foreground colours on purpose:
extracted colour is atmosphere, and which half of a track has played is
meaning. The backdrop behind the picture is where the artwork's own
colour goes.

Controls fade out after three seconds and any pointer brings them back,
including the drag that scrubs: a listener scrubbing is a listener using
the surface, and hiding the controls mid-drag would be the screen arguing
with the hand on it. They keep their slot while hidden, so the picture
does not resize every three seconds.

The countdown does not run under a screen reader. Chrome faded to nothing
leaves the semantics tree with it, and the way back in is a pointer event
- so auto-hiding would put the transport, the mode switch, and the exit
beyond reach with no node left to touch. Accessible navigation is read as
the condition rather than reduced motion: what is wrong here is the
disappearance, not the fade.

Under reduced motion the disc holds still. What that setting turns off is
decoration, and a continuous rotation is the most decorative thing here;
the playhead still moves, because it is the information.

### Car mode forces its own theme, and the swipe is a fling

`CarModeTheme` imposes the OLED palette whatever the app is set to.
Brightness in a car is a safety property rather than a preference, and a
listener who set the app to paper did not set their dashboard to it. The
density setting travels with them, because that one is about their eyes.

Its own widget, wrapped around the whole screen rather than done inside
the scaffold, because the scaffold is only the branch where something is
playing. The idle state is text and a button on a hard-coded black, and
under the app's light theme that was primary text at less than 3:1 - on
the control that is the only way out.

The title block is flexible and scrolls; the transport is not. On a
landscape phone at a large text scale the fixed column ran off the bottom
and took the play button with it, which is the one thing here a driver
reaches for without looking. The hero already yields its whole slot on a
short window, so past that the type is what gives - and it gives by
scrolling rather than by being quietly set smaller, because 5.6 asks for
display size and a title a thumb can push is the better of the two
answers.

The transport is the design system's own `TransportCluster` at 96 px
rather than a second set of controls: the glyphs, the play/pause states,
and the accessible names are the ones every other surface uses, and
nothing about a car makes "Pause" a different word.

Swipe left is next and right is previous, and it is gated on velocity
rather than distance: a hand steadying itself against a dashboard mount
travels the width of the screen slowly, and that must not change tracks.
The gesture is excluded from the semantics tree for the reason the
player's dismiss drag is - left in it, a horizontal drag publishes scroll
actions, and a screen reader swiping to read would skip the album.

Spoken word gets no next and previous in car mode. There is no room for a
fourth control at this size, and a next button that walks out of an
episode is worse than a swipe that does nothing.

### Both are declared routes, pushed

Each is a whole surface with a way out, reachable from a menu today and
from the command palette next, so each gets a location. Neither is
somewhere a stranger's link can put anybody, so both are pushed, which
keeps them out of the URL - the same reading of 8.3 that `/now-playing`
and `/queue` already got. Opened with nothing playing, each says so and
offers the way out rather than drawing an empty frame.

### The wake lock is a plain object behind a `Provider`

`wakelock_plus` 1.7.0, exact-pinned, behind `WakePort`. `WakeLock` counts
claims, because the two surfaces that take one can stand at once and the
first to leave must not turn the screen off under the other. `KeepAwake`
holds a claim for as long as it is mounted, so every way out of car mode
- the exit control, a system back gesture, a route something else pushed
- releases it without remembering to.

It is a plain object with a `ValueNotifier` rather than a `Notifier<bool>`
holding Riverpod state, and that is not a style preference: claims are
taken in `initState` and released in `dispose`, where moving a provider's
state is forbidden outright and where `ref` is unusable. Both were
written the other way first and both threw.

Holding the screen awake and having taken over the screen are treated as
one fact. The idle watcher reads `held` to decide it has nothing to do,
because a machine already showing the visualizer is not a machine to open
the visualizer on. Anything new that takes this lock is claiming the
screen, which is the contract to keep rather than a coincidence to work
around.

### Time saved is a sum of the two things that save time, not a measurement

`ListenSession.skippedMs` has always meant "what silence trimming and
playing faster saved you". The client counted only the first, and the
stats labels said so.

It is now the two terms added, each accumulated where it happens: the
jump that skipped a silence span adds its own length, and every position
delta the listen accounting counts as playback is priced at the rate it
was heard at, so content heard at 2x contributes half of itself. A rate
changed mid-episode is priced from where it changed. A rate below 1x adds
nothing, because a listener slowing a lecture down is spending time
rather than saving it and this counter runs one way.

Content minus wall clock is the obvious formulation, was written first,
and is wrong twice over.

The first way is the one the deferred entry recorded: a trim jump and a
hand on the seek bar look identical as a position delta, so content read
off raw movement counts a scrub through an hour as an hour saved. That
one is avoidable - take content from the counted deltas rather than from
the position - and the wall-clock version did.

The second is not avoidable, and is why the formulation is gone. Wall
clock counts every second that passed, including all the ones that saved
nobody anything: a rebuffer, a phone asleep in a pocket, a browser tab
throttled in the background, a `playing` flag that means play intent
rather than audio arriving. Sixty seconds of playback, a forty-second
stall, and a thirty-second trim jump reported zero saved next to a trim
chip that said thirty. Subtracting real time from a claim about trimming
and speed lets anything at all quietly eat it.

Nothing is measured against a clock now, which also takes with it a
system clock stepped backwards, a coupling between the wall-clock term
and the engine's play *transitions* while the content term read its
current state, and the need to reason about which of those a given start
path fires.

The stats and year-in-review tiles read "time saved". The trim chip keeps
counting trim jumps alone, which is narrower on purpose: it is the trim
control, and crediting it with what the speed chip saved would put the
wrong number under the wrong toggle.

### Two settings, and one of them is desktop-only

"Car mode button" moves the verb out of the overflow and onto the player,
off by default: the menu reaches it for everybody, and a row of glyphs
everybody carries for the few who need one is how a player becomes a
toolbar. When it is on, the menu row goes - one verb, one handle, and the
same identifier twice in one tree is what a button and a menu row both
claiming it would be.

"Open the visualizer when idle" is desktop-only, which needed a
`desktopOnly` flag beside the registry's `nativeOnly`. This is about a
machine on a shelf across a room; a phone locks its own screen and a
browser tab is not a room's stereo, and a switch with nothing behind it
is the promise a settings screen must not make. The registry test now
stands on a desktop so its every-setting-is-drawn check still covers
every entry.

The watcher itself wraps the signed-in app, so being left alone on the
queue screen counts as being left alone, and it re-arms on any pointer or
key rather than on WaxDeck's own controls. It pushes, so leaving lands
back where the listener was.

## Consequences

- Four new packages in the lockfile: `wakelock_plus` and its platform
  interface, plus `package_info_plus` and its own, which the plugin pulls
  in. `dbus` and `win32` were already transitive.
- `EmptyState` gains `actionSemanticsId`. Its invitation had no handle,
  which was fine while nothing had to press one.
- `NowPlayingView` is new, and is what lets a surface mounted away from
  the player find its own session: the panel, the visualizer, and car
  mode are each openable on their own. The deck bar and the player face
  keep their own feeds - the bar has radio, remote, and restore-offer
  cases this does not model, and the face is handed a session that cannot
  be null.
- Share-with-timestamp, listed against this phase, was already whole:
  P17's dialog offers the toggle for episodes, the player and the deck
  bar hand it the live position, the episode screen has its own button,
  and the server's landing page starts the stream at `#t=`. The contract
  restricts it to episodes (`invalid-request` on other kinds), so there
  was nothing left to build.
- The vendored icon subset gains Phosphor `car` (U+E112), rebuilt with
  `make icons`. 59 glyphs, and about a quarter of a kilobyte on each of
  the two weights.
- The transcript region is now `LyricsView` with its cues mapped onto
  `LyricLine`. It was a near-verbatim copy - same controller, same
  following flag, same row arithmetic, same button - and the two had
  already drifted: the lyrics button scrolls to the line and the
  transcript's only flipped the flag. One component draws both, so the
  row-height fix lives in one place instead of two.
- "Open the visualizer when idle" is the only `desktopOnly` entry, and
  `searchSettings` takes `isDesktop` as a required argument rather than
  defaulting it. A default that means "yes" is one a future caller - the
  command palette is the one that is coming - compiles clean against and
  gets wrong, offering a row that opens a section not drawing it.
- The idle watcher is mounted only on desktop rather than mounted
  everywhere and guarded inside. On a phone or a browser tab it could
  never fire, and what it costs there is a five-minute timer, a pointer
  listener over every screen, and a global keyboard handler. The platform
  does not change under a running app; the setting does, and that one is
  read when the timer fires.
- The visualizer is offered on the music face only. The three
  populations that never carry peaks are the three other faces, and a
  menu row that opens an empty state is a row that exists to disappoint.
- The old deferred entry for speed-savings accounting is closed. The
  server side never needed anything: the field was always defined as both
  halves, and only the client was under-reporting.
