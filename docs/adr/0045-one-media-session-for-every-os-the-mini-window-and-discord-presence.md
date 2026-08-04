# 45. One media session for every OS, the mini window, and Discord presence

Date: 2026-08-04

## Status

Accepted.

## Context

Four features that all live outside the app's own window: the surfaces an
OS draws for whatever is playing (lock screen, head unit, MPRIS, the
Windows transport controls, macOS's now-playing panel), a desktop mini
window and tray, a Discord status, and the up-next list a head unit
renders.

The starting state was narrower than it looked. `audio_service` was
registered on Android alone, and even there it published a
`PlaybackState` and never a `MediaItem`: the transport worked and the
notification carried no title, no artist, and no cover. Nothing published
a queue. Neither desktop had a window verb of any kind.

## Decision

### The desktops are federated halves of the session that already exists

`audio_service` is a federated plugin, and MPRIS and the Windows
transport controls have published implementations of its platform
interface (`audio_service_mpris`, pure Dart over D-Bus;
`audio_service_win`). macOS and web are inside `audio_service` itself.
So the whole of 5.6's "OS media integration" is one registration widened
from Android to every platform, plus two exact pins that are never
imported.

No `MediaIntegrationPort`, which section 8.9 anticipated. A port per
desktop would be three descriptions of one thing that is playing and
three chances for them to disagree; `WaxDeckAudioHandler` is already the
WaxDeck-owned seam the wrapping rule asks for, and it is the seam all
five platforms read. The rejected alternative was `smtc_windows`, which
is not an `audio_service` implementation and pulls `flutter_rust_bridge`,
putting a Rust toolchain in the Windows build for a transport bar.

A registration that fails is caught and logged. A Linux session with no
D-Bus must cost the lock screen and nothing else; an app that will not
launch because the shell it was started from has no notification area is
the worse failure.

### The port grew metadata and a queue, and the feed is one method

`MediaSessionPort` gains `publish(MediaSessionItem?)` and
`publishQueue`, beside the extra control the sleep timer already raised.
`MediaSessionItem` is a plain view-data struct for the same reason the
design system takes one: `waxdeck_player` knows nothing about the
catalog.

`MediaSessionFeed` has a single `update` taking radio, playback, the
remote session and the queue together, rather than a callback per
source. What the OS shows is a decision *across* all four - a station
ending has to republish the item underneath it, a handover to another
endpoint has to clear both - and split into a listener each, every one of
those crossings is a surface left showing what stopped.

Two guards keep it from being a signal storm: the item is compared on
what an OS surface can draw, and the queue on its pids and index. MPRIS
and the Windows controls emit a change signal per publish, and the
position tick reaches this several times a second.

### A remote session publishes nothing

When another endpoint owns playback, no OS surface here names anything.
This is the reading of 5.6's "truthful ... including remote-session
control states": the sound is coming out of a speaker in another room,
and a lock screen claiming otherwise is a transport over silence with a
play button that starts nothing. The deck bar is the surface for a
session playing elsewhere, because it can say *where* - "on the kitchen
speaker" - which a notification cannot.

### Artwork is a file on native and a URL on web

Every OS surface fetches covers itself, out of process, carrying none of
this app's credentials, and every WaxDeck art URL wants a bearer token.
So native fetches the bytes through the store that already authenticates
and caches them, and writes one file per cover for the OS to read - one
file *per cover*, not one reused, because those surfaces cache by URI and
a path that never changes is a lock screen still showing the last album
three tracks later. The write is temp-in-target-dir, fsync, atomic
rename, which is not ceremony here: the reader is another process that
may open the path at any moment.

Web hands over the server URL, where the page and the art endpoint share
an origin and the browser attaches its own cookie.

The queue's rows carry no artwork. A head unit draws that list as text,
and resolving five hundred covers would be five hundred fetches for a
list nobody reads with their eyes on the road.

### The head unit steps by index

`skipToQueueItem` is an index, and `QueueGateway` grows a `jumpTo` to
match. The same item queued twice is ordinary and a pid would step to the
wrong one of the pair - which is also why a queue row nothing has named
yet is published as "Queued item" rather than dropped: a list with its
holes closed up puts every index behind them out by one.

### The mini window is the same window, and the compositor is asked first

There is one window; entering the mini player shrinks it and swaps what
is drawn. `MiniWindowPort` probes what the session will allow *before*
asking for it, reading `XDG_SESSION_TYPE`/`WAYLAND_DISPLAY` rather than
attempting frameless-and-on-top and rolling back. Under Wayland the
compositor owns framing, stacking and placement, and a window that
flickered frameless and back is worse than one that never tried; the
fallback is a plain fixed-size window, which is what 5.6 asks for.

The app underneath is kept mounted and stops being drawn, not replaced.
Every provider the signed-in scope owns - the sync engine, playback, the
download queue, this phase's own media feed - hangs off that subtree, and
swapping it out would tear all of them down every time somebody made the
window small.

`MiniPlayer` is a new `waxdeck_ui` component rather than a shrunken
`DeckBar`. The bar is a strip docked under a screen and says so; this is
the entire window, so it has to be draggable by its own background (a
frameless window has no title bar to grab), it has a way *back* rather
than a way in, and it stands on a border of its own. The drag is a
callback the app hands to the port: the design system knows nothing about
windows.

The drag handle is the artwork and the title and **stops before the
transport**, which is a correctness matter rather than a layout one. A
pan recognizer wrapping the whole row competes with the buttons inside it
for every click, and against a mouse it wins: the hit slop for a precise
pointer is a single pixel, so a hand that moves while pressing Play drags
the window instead of playing. A test presses Play through four pixels of
travel and asserts both halves.

Entering the mini window has to lower the window's minimum size to get
under it, and `window_manager` offers no way to read back what the
minimum was. So the ordinary floor is a constant this package owns, set
at startup and put back on the way out - otherwise leaving the mini
player would restore "no minimum at all" and the window would drag down
to a sliver for the rest of the session.

### `WaxCommand.offered`, distinct from `enabled`

ADR-0044 gave commands one predicate. Two questions were hiding in it,
and the reference sheet is where the difference shows. "Nothing is
playing yet" is not a reason to stop teaching the space bar, so the sheet
prints a command whose `enabled` is false. "This browser tab has no
window to shrink" is a reason never to print Ctrl+Shift+M, and no amount
of playing anything will change it. `offered` is read once by the
registry, which withholds the command entirely: not bound, not in the
palette, not taught. It is watched rather than read, because the mini
window's answer arrives from a platform probe a moment after launch.

`togglePlayback` moved onto `NowPlayingController`. The tray menu needs
it from outside the widget tree, and a `Ref` is not a `WidgetRef`; the
verb belongs to whatever owns playback, and the command is now a
one-line delegate.

### The tray glyph is the needle, and the tray is allowed to be absent

Play state is the meter's own deflection - parked while paused, swung up
while playing - rather than a badge in the corner, which is mush at 22
px. Three platform conventions from one drawing: a black template image
macOS tints for whichever menu bar it is in, the light/dark pair Windows
picks between, and the mark's own amber for Linux. They are generated by
`tools/generate-brand.py` like every other WaxDeck asset.

`TrayPort.install` answers false where there is no StatusNotifier host,
and nothing else in the app depends on it. The menu is rebuilt per
update because the plugin has no row-level edit, and it is rebuilt on
three fields only - a station's announced title moves every few minutes
and the position moves several times a second, and a tray menu redrawn at
that rate flickers shut under the pointer on some desktops.

### Discord presence is a pure-Dart IPC client and a setting nobody has to have

The protocol is a handshake and one command as JSON frames over a Unix
socket or a named pipe: a little-endian opcode, a little-endian length, a
UTF-8 body. All three published bindings wrap something heavy to send
exactly that - an FFI library, or `flutter_rust_bridge` again - so this
is written. Nothing in it is a credential: the application id is a public
snowflake, there is no bot and no OAuth, and the socket is local by
construction.

Updates coalesce to fifteen seconds and always send the newest state.
Discord drops updates past roughly that rate rather than queueing them,
so a listener skipping through three tracks must end on the third and not
the first. The position is deliberately not watched: Discord draws its
own progress bar from a start and an end timestamp, so a seek republishes
and a tick does not.

That start is *derived* - wall clock minus the position - which makes it
the one field that cannot be compared for equality. Two readings of one
continuous playback never agree to the microsecond, because the clock
moves between them and the position moves only when the feed ticks, so an
exact comparison finds every state different from itself and spends the
budget forever. It is compared with two seconds of slack instead: far
above the feed's granularity, far below the smallest seek any control
here performs.

**A pause drops the timestamps rather than the track.** Discord has no
notion of a stopped progress bar - given a start it runs the clock from
it regardless - so a listener who paused for lunch would come back to a
status claiming they were an hour into a four-minute song. Without the
pair, the track and the artist stand on their own, which is the part that
is still true. This is also why the binder listens to the engine's
transport directly: pause is not a provider event, and 5.6's "track and
pause changes" is half-built without it.

WaxDeck has an application of its own, so the id is a constant and the
setting beside the switch is an override for somebody who would rather
publish under theirs. That ordering is the decision: the id names what
Discord prints after "Listening to" and owns the images the cover is
drawn from, and a required field would make the feature look broken to
everybody who turned the switch on and never opened the second control.
The id is public by construction - it rides in the presence payload of
everyone who enables this - so it belongs in the source rather than in a
secret. The cover is that application's own asset key, and there is no
image behind it yet: the mark is still being drawn, and Discord renders
an activity with no large image when a key resolves to nothing, so
presence ships looking deliberate rather than broken. Two deferred
entries cover the image - the one that is waiting on the logo, and the
per-track album art that is waiting on something further away.

### Two gates that only ran on one machine, fixed in passing

Both were found by running the gates on a Mac, and both made
`make lint test` - the rule-2 gate on every change - something only an
Ubuntu host could pass.

**The CI goldens were host-specific.** Alchemist's CI variant obscures
text so font rasterisation cannot move it, which was taken to mean the
images were portable; shape antialiasing is not text, and every rounded
corner disagreed by a pixel here and there. Measured across the nine
that failed, about nine tenths of the disagreement was a single channel
off by one part in 255, and the worst image differed by 0.034% of its
pixels once anything under a delta of 8 was discounted.
`TolerantGoldenComparator` discounts exactly that: a pixel counts as
different only past a per-channel delta of 8, and an image fails past
0.1% of such pixels. It still bites - a one-pixel spacing change fails
six of the eleven, and a 16/255 shift in the accent colour fails ten.
The readable `goldens/linux/` set stays Linux-only, because the
difference it exists to catch is the same difference host font
rasterisation makes.

**`noticegen` assumed the toolchain's legal files sit in GOROOT.**
Homebrew installs GOROOT at `<prefix>/libexec` and lifts LICENSE to
`<prefix>`, leaving PATENTS behind, so the lookup falls back to the
parent directory per file. Still a hard error when neither has it: those
are terms the binary ships under, and a notices file that quietly lost
one is worse than a generator that stops.

## Consequences

Every platform WaxDeck ships on now names what it is playing on the
surface its OS provides, with a cover, and Android Auto renders an
up-next list that skipping actually steps. Two deferred entries close.

Four dependencies land, all exact-pinned and all behind a WaxDeck-owned
seam: `audio_service_mpris`, `audio_service_win`, `window_manager`,
`tray_manager`. The last two reach for `dart:io`, so both ports are
conditional imports whose web half is inert - the wasm build is the gate
that proves it.

`audio_service_win` is a 0.0.x package and the newest thing here; if it
disappoints, the interface it implements is the same one a minimal
in-house WinRT bridge would implement, and nothing above the handler
changes.

None of this is verifiable by the automated gates on their own: a tray
icon, a Wayland fallback, a lock screen, a head unit's up-next list and a
Discord status are all things that need the platform in front of them.
The units and widget tests pin the decisions and the seams; the surfaces
themselves ride the release checklist.
