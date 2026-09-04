# Connect and casting

Every signed-in WaxDeck client is both a remote control and a
controllable player. The device picker on the player screen (the cast
icon) lists everywhere your audio can go: your other signed-in
devices, Chromecast devices and speaker groups, DLNA renderers, and
the server's own audio output when the jukebox is enabled.

## Playing on another device

Tap the cast icon on the player screen and pick a target. If you were
already listening, playback moves there and keeps your position; the
same picker later moves it back, or anywhere else, mid-track. What a
shared speaker plays is visible to everyone in the household, and
anyone can pause, seek, or change its volume from their own device;
your own phones and laptops are visible only to you.

The picker also lists sessions already playing elsewhere. Tapping one
opens a remote control with live position, play and pause, seek,
skip, volume where the device supports it, and a "Play here" button
that pulls the audio onto the device in your hand.

A few rules follow from "a device plays one thing":

- Sending your audio somewhere else is a handoff, not a copy. The whole
  queue goes - the running order, where you are in it, the speed, repeat
  and shuffle - the target picks it up where you left off, and the
  device you sent it from goes quiet.
- A remote control reaches the session it is showing and nothing else.
  A device that has moved on since the list was drawn ignores what
  arrives for a session it is no longer playing, rather than pausing
  whatever it happens to be playing now.
- Live radio stays on the device that tuned it. A station is a stream
  rather than a queue, so there is nothing to hand over; the picker
  says so while one is playing, and sessions on your other devices stay
  controllable from there. Sending something to a device that is
  playing a station still works - the station stops and the queue
  starts.
- A speed change from another device is your own. Set on a show or a
  book it is remembered like any other, so the next episode plays at
  it; set on a track it lasts as long as a local one does, which is
  until the next track.

Audiobooks play on a Chromecast, a renderer, and the jukebox like
anything else, including the ones held as several files. The device is
handed the files and steps through them, so a chapter boundary that
falls on one of them has the device's own gap at it, and jumping to a
chapter in another file takes a moment to load; where you are is the
place in the book throughout, and it is what a resume anywhere picks up.

Albums and queues cast to a Chromecast play gapless when the
streaming engine is configured: the whole queue renders as one
continuous stream with sample-exact seams. A queue holding a
multi-file audiobook is the exception - the parts have a reading order
that one continuous stream cannot express - so such a queue plays file
by file until the book leaves it.

Two settings shape that stream, both under Settings, Playback, and both
on your account rather than on one device - the server re-renders a cast
queue whenever you edit it, and it does that from what it holds.

- **Crossfade** fades each seam instead of butting the tracks
  together. Zero is the gapless default.
- **Level the volume** plays the whole queue at one loudness. It
  reads the measurements the analyze pass stores per file, so a library
  that has never been analyzed plays unlevelled whatever this says; run
  the analyze pass first if you want it. One level applies to the whole
  queue, because there is no seam in a rendered stream at which it could
  change.

## Gapless in the browser

Every WaxDeck app crosses from one track to the next without a gap
except one: a browser, where an audio element takes a single source and
changing it is a load however it is arranged. Settings, Playback,
**Gapless playback** closes that, and it is a browser-only switch
because nothing else needs it.

What it does is play a music queue through the same rendering a cast
speaker gets: one stream for the whole queue, seams the server cut,
crossfade and levelling from the two settings above. So the switch
needs the streaming engine, and says so on its own row when a server
has none. Off by default, because it asks the server for work an
ordinary listen does not.

Only music, and only what follows it: a podcast or an audiobook in the
queue plays the ordinary way and ends the rendered run there. Editing
the queue never interrupts what is playing - a replacement is rendered
behind it and swapped in at the next seam. And a rendering counts
against the server's transcode limits, as one slot per listener; when
the server is full the browser says so rather than quietly playing with
gaps.

## Casting setup

Cast devices fetch media from the server themselves, so the one thing
casting needs is an address the device can reach:

- On a flat LAN this works out of the box: the server auto-detects
  its LAN address and offers plain-HTTP URLs, which the default cast
  receiver plays without any TLS setup.
- `WAXDECK_ADVERTISE_BASE` overrides the auto-detected address when
  the guess is wrong (multiple interfaces, NAT between the device and
  the server).
- An HTTPS public base works too, but cast devices require a
  publicly trusted certificate and often ignore LAN DNS; when in
  doubt, the LAN address is the reliable path.

The connection check, behind the device picker's overflow, is where
this is read. It has two halves. The first is this server reaching
itself through each candidate address and saying, in plain language,
what a cast device would likely make of it
(`GET /api/v1/player/cast/preflight`). The second is a real device
doing the reaching: pick a speaker under "Test on a device" and it is
handed a second of silence at each address in turn
(`POST /api/v1/player/cast/preflight/{endpointId}`). What counts is the
speaker actually coming and fetching it - not what it says about
itself, since a Chromecast reports that it is playing while it is
still looking up a name it will never find. That half is what catches
the failures the server cannot see, because they are the device's: a
name it resolves differently, a certificate authority it does not
trust, a route it does not have.

Testing takes the speaker over for a second, so it asks first. A
Chromecast running somebody else's app or playing for another sender,
a renderer playing or holding something paused, a speaker with a
WaxDeck queue on it, and one already being tested all refuse and say
what is there rather than interrupting it. The speaker is held for the
few seconds the test runs, so sending a queue to it meanwhile is
refused the same way instead of colliding with the test.

Discovery uses mDNS and SSDP, which are multicast and do not cross
Docker's default bridge network. Options, most common first:

- Run the `cast` compose profile, which starts the server on host
  networking where discovery works.
- List devices statically and skip discovery entirely:
  `WAXDECK_CAST_DEVICES="Kitchen speaker=192.168.1.50:8009"` and
  `WAXDECK_DLNA_DEVICES="http://192.168.1.60:8200/rootDesc.xml"`.
- A macvlan network or an avahi reflector, for setups that already
  use them.

DLNA renderers receive plain-HTTP URLs always (most speak no TLS) and
audio as mp3, or the original bytes for mp3 and wav sources.

## Jukebox

With `WAXDECK_JUKEBOX=true` the server's own audio output appears as
an endpoint named by `WAXDECK_JUKEBOX_NAME` (default "Server audio"):
the box wired to the amplifier becomes a target like any speaker. It
needs the streaming engine (audio arrives as WAV) and a player
command on the host, `aplay` by default; PipeWire hosts set
`WAXDECK_JUKEBOX_CMD="pw-cat -p -"`. Under Docker, mount the sound
device (`/dev/snd`).

## How control works

Controllers talk to the server, never to devices, so control survives
the controlling phone sleeping. Live verbs ride the same WebSocket
the app already holds; endpoint and session lists are plain API
surfaces (`/api/v1/player/endpoints`, `/api/v1/player/sessions`) any
client can use. A client playing its own audio applies your taps
instantly and mirrors state to the server about every five seconds,
so remote observers track it without playback ever waiting on the
network.
