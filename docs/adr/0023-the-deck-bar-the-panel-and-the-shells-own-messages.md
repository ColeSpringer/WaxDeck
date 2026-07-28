# 23. The deck bar, the panel, and the shell's own messages

Date: 2026-07-26

## Status

Accepted.

## Context

ADR-0020 moved playback off the player screen, and ADR-0022 built the
chrome around a content pane with two slots left empty. That left the app
in a state worth naming: a session outlives every screen, and nothing on
screen says so. Backing out of the player leaves an item playing with no
affordance to reach it, the queue ADR-0019 built has no surface at all,
and the queue a launch finds is offered to nobody.

Three other things were open around the same slots. The layout system
asks for a right panel on wide windows and gives it nothing to host. The
self-host lifecycle surfaces (6.20) are unbuilt, so a server restart —
which this audience does constantly, with the web client embedded in the
binary — reads as actions failing one at a time. And the design system's
deck bar carries an `autoplayBlocked` state that nothing could ever set,
because no layer knew a browser had refused to start.

Filling the slots turned up a fourth thing, which is where this ADR
starts.

## Decision

**`AudioEnginePort.play()` resolves when playback starts, and a refusal
is announced on a stream of its own.** just_audio's `play()` resolves
when playback *stops* — its own documented contract ("completes when the
playback completes or is paused or stopped") — and `JustAudioEngine`
returned that future directly. Every caller reads the port's wording
instead, so `PlaybackSession.start` awaited the end of the item before
`NowPlayingController` published its session: on web and Android the
transport appeared only once the track had finished, and live radio, which
never finishes, never published one at all. The desktop bridge returns
promptly, which is why the conformance suite (mpv) never saw it, and the
e2e fixtures are two seconds long, which is why the browser suite passed.

The engine now issues the request and lets go. A platform that turns it
down errors on that request, and the engine puts just_audio's optimistic
playing flag back before announcing the refusal on `playbackRefused`, so
no surface reads as playing over silence. `AutoplayGate` listens for the
session's whole life — from `_SignedInScope`, not from the bar, which is
not mounted until there is something to show — and the deck bar says "Tap
to resume", which is the gesture the browser was waiting for.

**The deck bar is the shell's, and its position is a leaf.** `DeckBarHost`
sits in the frame's bottom slot, outside every branch navigator, and shows
in order: the station when live radio has the engine, the queue's current
entry, the queue a launch found, and otherwise nothing. It watches
identity — what is playing and whether it is — and feeds the live position
into the bar through a `ValueListenable` the bar consumes inside a
`RepaintBoundary`. The bar rebuilds on a track or transport change and not
otherwise, which is 8.8's requirement, and a widget test fails if the bar
widget is rebuilt by a tick.

**A control that cycles says which state it is in.** Shuffle and repeat
name their own state ("Shuffle off", "Repeat one") and carry the accent
when they are on, so greyscale and a screen reader can both tell; repeat
swaps its glyph for repeat-one. The two modes are the only thing the bar
reads from the queue, and it reads them through a `select`, because a
drag reorder emits a queue state per frame and the bar must not rebuild
with it.

**`NowPlayingController.resume()` replaces `retry()`.** Two states leave
an entry on the bar with nothing driving it — a start that failed, and an
item that handed the engine to live radio — and in both the queue never
moved, so nothing else would ever start it again. One verb covers both;
it asks again for the position the failed start was asked for, and for
the checkpoint otherwise, because a session that let go wrote one on its
way out. Without it, stopping a station left the item on the bar behind a
dead play button.

**Nothing unwired is drawn.** The bar's right cluster (queue, lyrics,
cast, overflow) draws only the controls the caller wired, so a surface a
later phase builds is absent rather than permanently greyed. The transport
is the opposite case and keeps its controls disabled where they cannot
act: a bar that loses its next button on the last track moves under the
hand.

**The panel is shell state, and it opens onto the queue.** `WaxPanel` names
what is open, `sidePanelProvider` holds it, and the frame docks it beside
the content on wide and lays it over the content's trailing edge on
expanded — scrim-free, because the page underneath stays usable, which is
the whole reason it is a panel and not a sheet. Narrower windows get no
panel at all: the compact queue is a route, and that route is the queue
surface's phase to build. Its first content is the queue, because a host
with nothing in it is a stripe of surface with a close button.

**The lifecycle banners are the shell's, above the content and below the
chrome.** A dropped live channel says it is reconnecting; a reconnect
re-probes `GET /health` and says so when the build or the API version has
changed under the client, with a Reload on web and a restart hint on
native. Both are `WaxBanner`, both are live regions, and neither pushes the
navigation down: the banners ride with the content pane, so the chrome
does not move under a cursor every time a socket blinks.

## Consequences

- **The deck bar's semantics went quiet.** Its container had been merging
  the title, the artist, and both timecodes into its own label, so the bar
  announced its elapsed time and re-announced it at every tick. The
  container is explicit about its children now, the loose text is excluded,
  and the position is announced by the one control that owns it — the seek
  bar, as a spoken time. The same merge silently swallowed the banner's
  Reload button until `explicitChildNodes` went on: a `Semantics` that is
  not a container folds into the nearest one that is, which is worth
  remembering for every composite surface in the design system.
- **The bar carries its own Material.** It is mounted straight into the
  frame, where there is none, and it is placed inside the bar's surface
  rather than around it so ink lands on top of the background rather than
  behind it.
- **The queue panel is half a queue surface.** Provenance, the current
  entry pinned, up next, jump, remove, clear, and the two mode toggles.
  Drag reordering, multi-select, the history strip, and the compact
  `/queue` route ride the queue surface's own phase. Rows name themselves
  from what playback already holds and fetch only what it does not, one
  row at a time, so a five-hundred-entry queue resolves what is looked at.
- **The bar does not reflect a remote session yet.** `NowPlayingData` has
  the field and the cast button opens the existing picker, but controlling
  another endpoint is a pushed screen with state of its own rather than
  something the shell knows about; making the bar follow it is the cast
  phase's, with the rest of the Connect UX.
- **No lyrics control.** There is no lyrics view, so the action is not
  wired and the control is not drawn. The endpoint exists; the surface
  rides the player-extras phase.
- **The restore offer stands in the bar's slot** rather than as a banner or
  a snackbar, at the same height, because it is the same promise and
  because a bar that appeared under the content and then jumped as playback
  started would move the page twice.
- **Two per-device knobs are still hard-coded**: the spoken-word skip
  intervals (15 back, 30 forward) and, from ADR-0020, wifi-only preloading.
  Both want the client-settings store and ride the settings phase. *The
  store landed early (ADR-0027); what these two still want is a control
  in Settings, and wifi-only a connectivity port besides.*
- **A sheet opened from the bar does not belong to the bar.** The bar is
  replaced by whatever playback does next — clearing the queue, a station
  taking the engine — and its overflow menu stays up across that. The
  menu captures the root navigator's context and the router when it
  opens, so the tap that follows still lands; reaching back through the
  bar's own context is how a dialog ends up pushed from an element that
  is no longer in the tree. The same rule applies to anything else the
  bar opens later.
- **"No session" is two states, and only one of them wants a play
  button.** An entry with no session is a start still loading *and* an
  item that handed the engine to radio. `resume()` refuses while a start
  is in flight, because starting again supersedes the load, re-mints its
  stream token and listen session, and drops the position it was asked
  for — a tap on a book's chapter twelve landing at the checkpoint
  instead. The controller records the start's own token for that, and
  clears it only if a newer start has not claimed the window.
- **A disposal callback may not touch `ref`.** Riverpod marks the
  element disposed before running these and asserts on its callback
  stack, and the container swallows what that throws — so a reset
  written there does not fail loudly, it just never happens. The sync
  binder holds the notifier from its build instead. This is the same
  rule the queue controller already records for letting go of a session.
- **The port's new promises are conformance-tested, per rule 4.** A case
  asks whether `play()` answers while the item is still playing, which
  is what one backend spent a phase not doing, and another asks that a
  start which was taken reports nothing on `playbackRefused`. A refusal
  itself cannot be provoked from a test — it takes a browser's autoplay
  policy — so the surfaces that read one are exercised against the fake.
- **Two fire-and-forget paths catch everything, deliberately.** The
  server-build probe and the engine's refusal handler both run with no
  caller to fail: the probe is `unawaited`, and the handler hangs off a
  `catchError` on a request nobody awaits. Narrowing either to the
  structured API error would put an unhandled zone error one deserialize
  failure away — and a response the generated code cannot build is the
  very shape of the event the probe exists to notice.
- The composites' deck bars are wired end to end now, which is what the
  "nothing unwired is drawn" rule made visible: their right clusters had
  been rendering greyed because the samples wired nothing. The
  `home_desktop` golden moves by four glyphs' worth of tint.
