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

Albums and queues cast to a Chromecast play gapless when the
streaming engine is configured: the whole queue renders as one
continuous stream with sample-exact seams.

Two settings shape that stream, both under Settings, Playback, and both
on your account rather than on one device - the server re-renders a cast
queue whenever you edit it, and it does that from what it holds.

- **Casting crossfade** fades each seam instead of butting the tracks
  together. Zero is the gapless default.
- **Level casting volume** plays the whole queue at one loudness. It
  reads the measurements the analyze pass stores per file, so a library
  that has never been analyzed plays unlevelled whatever this says; run
  the analyze pass first if you want it. One level applies to the whole
  queue, because there is no seam in a rendered stream at which it could
  change.

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

`GET /api/v1/player/cast/preflight` (or the diagnostics surface that
fronts it) checks each candidate address server-side and explains, in
plain language, what a cast device would likely make of it.

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
