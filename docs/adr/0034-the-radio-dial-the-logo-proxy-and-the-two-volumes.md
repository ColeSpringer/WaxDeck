# 34. The radio dial, the logo proxy, and the two volumes

Date: 2026-07-29

## Status

Accepted.

## Context

Four things had been waiting on the cast phase, and they turned out to
share one seam.

**Station logos could not be drawn.** `RadioStation.logoUrl` carried the
station host's own URL and the contract told clients to fetch it
directly. On the web build a picture on another origin has no CORS headers
to offer and an http logo is mixed content on an https page, so a large
share of logos simply could not be drawn; every fetch also handed the
listener's IP address to a station host, which rendering a picture does
not require. The spec's own text admitted half of this ("render the
placeholder in that case").

**The deck bar had no volume control at any width.** The layout system
gives the bar a slider under two separate conditions - local output on
desktop and web, and a remote endpoint that reports `volumeControl` - and
P7 built neither while recording only the second, which is how the first
went missing rather than being cut. Nothing local read or wrote
`AudioEnginePort.setVolume`: its only callers were the endpoint
controller's session report and its routed `set-volume` case, so another
device could turn this one down while its own user had no way to.

**The bar could not say where playback had gone.** Handing a session to
another endpoint routes a stop back to the source client, which clears the
local queue - so the bar went blank rather than saying "on Kitchen
speaker". The remote control was a pushed screen holding its own watch
subscription, so it was also the only thing following the session, and
walking away from it stopped the watch.

**Cast preflight had no surface.** The endpoint has answered
plain-language diagnostics since it shipped and nothing rendered them, so
reading them meant curling the API.

## Decision

### The contract

**`GET /radio/stations/{pid}/logo`** is section 11's item 12 and reverses
the recorded direct-fetch decision explicitly. The server fetches the
station's logo through the same guarded client the stream proxy uses - private
destinations refused at dial time after DNS resolution unless the
server permits LAN stations, redirects bounded - and serves it from this
origin. Bytes are capped at 512 KB and the answer must be an image: a
station host serving an HTML error page where a favicon used to be is a
station with no logo. The type is **sniffed from the bytes rather than
passed through**, because hosts label favicons every which way
(`image/x-icon`, `application/octet-stream`) and what a browser is handed
has to match what it is told.

**Raster only, and SVG is refused rather than sanitized.** This is the
one place the endpoint's design is driven by an attacker rather than by a
station: a logo URL is supplied by any account, pointing anywhere, and
the bytes come back from *WaxDeck's own origin* under the caller's
session. An SVG opened as a document runs its script there, so proxying
one would be stored XSS with a public write path into it. Sanitizing SVG
is a real and unforgiving job - namespaces, entities, `xlink`, CSS,
`foreignObject` - and not one worth doing for a decorative favicon with a
monogram fallback: a station whose mark is an SVG draws the monogram a
station with no mark draws. The sniff is what enforces it, with no branch
that takes a host's word for a type the sniffer disagrees with, so markup
labelled `image/png` is refused too. `nosniff` and
`default-src 'none'; sandbox` ride the response as the layer that keeps a
future mistake in that check a broken image rather than a same-origin
script.

The stream proxy had the same exposure from the other door and was fixed
with it: it relayed the station's own `Content-Type`, so a station
answering `text/html` would have had markup served from this origin. The
executable families now fall back to `audio/mpeg` and everything else
passes through - an allowlist would break playback for the long, odd set
of types real stations send (`audio/aacp`, `application/ogg`,
`audio/x-mpegurl`) to prevent nothing, so what is refused is only what a
browser would execute.

The type check has two stages and only one authority. The declared
`Content-Type` is a cheap pre-filter - it is what keeps a 2 MB HTML page
from being downloaded to discover it is a page - and the sniff is what
decides. A host that named **no type at all** therefore passes the filter:
that is ordinary for a favicon on a static host, and saying nothing is not
a claim of anything. (The first cut treated an absent header as a
disallowed claim and refused those stations, which read as the rule the
comment above it denied.)

`size` is accepted and ignored, documented as such, and **clients do not
send one**. Ignoring it means one identical body sits behind a URL per
rung, and the dial and the grid draw at different sizes: sizing a logo
would be a fetch per rung of the same bytes and two server-side cache
misses racing for them. So the artwork store treats this endpoint as
holding one rendition and asks for it plain, while the parameter stays
accepted so an older build and a hand-typed URL still land. The server
does not re-encode either way - rescaling would have to pick an output
format, and the transparency most station marks carry does not survive
that choice.

One fetch at a time per station. A dial and a grid draw the same station
on one paint and two devices paint at once, so concurrent misses are the
ordinary case rather than the exotic one: without coordination each is its
own ten-second wait against the station host, and the loser's answer
overwrites the winner's for no gain. The second caller is handed the
running fetch's channel and reads the cache it fills. One wait is the
limit - the fetch waited on may have stored nothing because *its* caller
went away, and queueing behind a chain of those would report a logo
missing that is not, so a caller that falls through fetches beside the
next one. And a miss never replaces a logo that is still fresh: of two
answers about one station, the one with a picture in it is the one to
keep.

`Cache-Control` is `private, max-age=86400` with **no `Vary`**, unlike
item artwork: the station library is shared by every user, so these bytes
do not depend on who asked. `private` all the same, because the request
needs a session and a shared cache must not answer one without. Answers
carry a content-addressed `ETag` and honour `If-None-Match`.

**404 covers every way there is no picture** - no logo configured, host
unreachable, refused destination, non-image answer, body over the cap -
because a client can act on none of the differences: it draws a monogram
disc. Each of them is worth not retrying per paint, so all of them are
cached alike, misses for an hour against a day for a hit. A cancelled
request is the exception and is not remembered: it says nothing about the
station, and a grid load somebody navigated away from must not blank a
logo for an hour.

The cache is in memory, bounded by bytes (24 MB) rather than by count, and
dropped when a station's logo URL is edited - the cache is keyed by pid,
which an edit does not change, so a new URL would otherwise be shadowed by
a day-old copy of the old one.

`RadioDirectoryEntry.logoUrl` gets no proxy: the proxy addresses a station
by pid and a directory match has none until it is added. A search result
draws a monogram and the logo appears once the station is in the library.

Additive, `oasdiff` clean.

### The two volumes are two pieces of state, and they are drawn by one control

`waxdeck_ui` had no slider primitive at all - the seek bar is bespoke, and
the pre-design-system remote screen used Material's. **`WaxSlider`** is
the house one: a semantic slider announcing a percentage, with an optional
glyph that mutes. The seek bar is deliberately *not* rebuilt on it - it
draws a buffered band and an optional waveform, announces a spoken time,
and is the one control on the bar whose value moves several times a second
on its own. What the two share is drag handling, which is a dozen lines.

`NowPlayingData.volume` says there is a level; `DeckBarActions.onVolume`
says it can be moved; the bar draws the slider only when both are present,
because a level with no setter is a readout and the bar has no room to be
one.

**Local output is followed, never stored.** `OutputVolumeController` is a
follower of `AudioEnginePort.volumeStream`, which the port grew for this:
the engine's gain is written from three places no widget hears about - a
routed `set-volume` from another device, the sleep timer's fade, and the
slider - so a control holding its own copy of the number would draw a
loudness the output no longer has. Mute is a remembered level rather than a
flag, because that is what the engine has, and a level set from elsewhere
forgets the memory so the glyph stays honest about what it will do. The
port's volume had no conformance cases at all before this; it has four now.

**The platform gate is a provider, not a function.**
`localVolumeAvailableProvider` answers desktop-and-web, because hardware
buttons own local volume on mobile and a software slider fights the OS
volume stack rather than driving it. A provider rather than a bare
predicate so a test can say which platform it is standing on without
moving a foundation debug global the harness checks nobody has moved.
P16's settings and P21's volume keys read the same answer.

**Deviation from 5.2, with the measurement behind it.** The layout gives
mobile the endpoint slider "in the bar", and the compact bar cannot hold
one: 64 px of height and one line holding 48 px of artwork, a title block,
and a transport. So the endpoint's level is drawn in the bar wherever the
bar has a right cluster (sidebar width), and on the **remote screen** at
every width, which is one tap from the bar and already existed. Both of
5.2's conditions are built; where each is reachable is stated rather than
left to be discovered.

The three-zone bar's own budget moved too: the slider is the largest thing
ever added to the right cluster, and at 840 px it took the left zone below
what its artwork, star, and needle need. The track scales with the bar's
measured width (80 px at 1000 and up, 52 below), which is what the
existing overflow test caught before anything shipped.

### The remote session belongs to the shell, not to a screen

`RemoteSessionController` holds which session this client is driving
elsewhere, follows it over watch frames, extrapolates its position against
the bus clock, and reports the endpoint's capabilities from the endpoint
list. This is the move P4 made for local playback: the controller owns the
session, and `RemoteControlScreen` is a viewer of it. That is what lets
the deck bar keep following a session after the screen is left, and what
makes `/remote` a payload-free location - redirected home when nothing is
adopted, from the one redirect that can read a provider.

**The remote face sits below local playback in the bar's order**, which is
the ordering decision worth stating. The bar's promise is "this is what
you are listening to", and local playback is what is coming out of this
device. Handing a session away stops local playback, so the remote face is
what fills the silence - the case the deferred entry named. Opening
someone else's session to skip a track while an album plays here does not
take the bar away from the album; the pushed remote screen is where that
session is driven.

The endpoint's declared `volumeControl` gates the slider, not the presence
of `session.volume`. The server refuses `set-volume` on an endpoint that
reports none, so gating on the reported level would ship a control whose
every use is an error.

### The picker says what stepping away means

Endpoints group by what they are - WaxDeck apps, speakers and displays,
this server, and "other devices" for the open `kind` vocabulary - because
the kinds behave differently and a listener knows it. Capability hints
ride the row's subtitle rather than becoming two more glyphs: they answer a
question asked *before* picking.

**The picker is told what it was opened over, and does not infer it.** Both
faces of the deck bar can be live at once: opening somebody else's session
to skip a track deliberately leaves the bar on the album playing here (see
above), so "is there a remote session?" is not the question "what should
move". The first cut asked exactly that and got it wrong - casting from
the local face transferred the *observed* session to the picked endpoint
and left the album where it was. The face passes a `CastSource` instead,
which also decides two smaller things: which row is marked as where
playback is going from, and that the endpoint a session already sits on
gets no tap. The server answers a transfer to the current endpoint with a
200 no-op, so a live row there is one that teaches people the picker's rows
do nothing - the same reason "This device" is not a control while playback
is already here.

The sheet reaches the app through handles captured where it opened - the
root navigator, the router, the messenger - never through the host's
`WidgetRef`. A sheet outlives the surface that opened it, and this one is
opened from a deck bar that is replaced by clearing the queue, by a routed
Connect command, or by a station taking the engine, all while the sheet is
still up; a callback reaching back through the bar's element then talks to
something that has left the tree. The bar's own action sheet already made
this capture for this reason, and the picker had to.

Selecting "This device" while driving a remote session opens the
three-way choice 5.5 asks for. Both wrong guesses are unrecoverable -
silencing a room somebody is listening to, or walking away from a queue
and finding it still going an hour later - so it is spelled out rather
than inferred. The same three are on the remote screen, because that is
where somebody standing over a remote session decides what happens to it.

Refusals render the server's own message, with one exception: the
multi-part audiobook refusal is coded `feature-unavailable` precisely so a
picker can offer the alternative, and it reads "Multi-part audiobooks
can't play on [device] yet. Play it on this device instead." The
server-side fix stays tracked; the UI shows no dead end.

That exception is a phrase match on the server's prose, which is a smell
and stays one on purpose. `feature-unavailable` is the umbrella code for
everything a target cannot play - a windowed track sent to a device
answers it too, and a client endpoint's own refusal arrives under it - so the
code alone cannot say which refusal this is. Minting a second code
would put a permanent contract token in the spec to describe a limitation
that is tracked for removal. What the coupling needed was not a new code
but to stop being invisible: the message is built by one named function,
its client reader is cited from there, and `TestMultiPartRefusalWording`
fails if the phrase moves. The deferred entry says to delete both when
part-aware device playback lands.

The connection check hangs off the picker's overflow, where 5.5 puts it. It
prints the server's notes verbatim - they name certificates, schemes, and
DNS, and rewording them here would be a second vocabulary for one set of
facts - with the endpoint's own caveat said once at the bottom rather than
per row.

### The dial is a shortcut and the grid is the surface

`StationDial` is the favourites strip: circular logos on a tick-marked
band under a fixed amber needle, snapping to whole stations, with snap
haptics on the platforms that have them and a static row under reduced
motion. Two decisions about it:

**The logo band is excluded from the semantics tree; the caption, the tune
control, and the needle itself are not.** 6.10 says the dial is skipped by
screen-reader traversal because the grid carries the semantics, and the
grid does have a row per station - but reading that as "exclude the whole
dial" would drop controls rather than a decoration. Twelve circular logos
in the traversal order buy nothing and cost the way out of them; one large
button naming what it will do is as useful to a screen reader as to anyone.

That first draft went one step too far and a review caught it: excluding
the band left the tune control stuck on whatever station the dial *opened*
on, because moving the needle was a flick or a mouse tap on a logo and
neither is available to a keyboard or a screen reader. The dial's own node
is adjustable now - increase and decrease step the needle, and its value
reads "Coastal FM, 1 of 3" - so the needle moves without a pointer at two
nodes rather than thirteen.

**Favourites are per account, in the synced preference document, which
reverses 6.10.** The plan called them client prefs, and its reason was
that the server keeps no per-user station state - an observation about
what existed rather than an argument for where they belong. ADR-0027's own
test is whether a preference describes the *machine* or the *account*, and
which six of the household's stations are yours plainly describes you: a
collapsed sidebar is a fact about a screen and a pointer, and a dial is
not. So `Prefs` grew `radioFavorites`, an ordered list of station pids,
and a pin made on the desktop is on the phone. Signing out takes them with
the account rather than leaving them on a shared machine, which is the
per-device store's weakest case.

Three details the field's shape turns on. It is **ordered and the order is
the client's** - new pins go on the end, so a dial does not reshuffle
under a thumb. It is **not resolved on write**: a station another
household member deleted leaves its pid in somebody's dial, and failing a
whole preference write over one departed station would make it cost a
listener their theme, so the server validates shape and clients render the
pids they can still find. And it is **stored in the canonical upper-case
form the pattern declares**, whatever case a write used - two things at
once, because Crockford base32 parses either case, so `rs-01H...` and
`rs-01h...` are one station and would otherwise be two entries: two dial
slots for it, and a star that could not unpin the one it drew.

Absent and empty are one answer, deliberately. Unpinning everything drops
the field rather than storing `[]`, and nothing on either side reads a
default set of pins out of an absent list, so both mean none pinned. What
the last unpin actually needs is for an *empty list on the way out* to be a
value rather than a "keep", which `copyWith` already gives it - only null
means keep. (An earlier draft claimed the wire distinction had to survive,
in three comments and an e2e note, over a server that collapses it and
readers that never look. Threading a pointer-to-slice through the service
and API layers for a distinction with no reader is speculative generality;
saying the true thing costs four comments.)

**The dial's cap of twelve is a display bound, not a storage one**, and
holding both at once was a way to lose somebody else's data: presenting the
stored list through the dial's cap and writing that back turns another
client's thirteenth pin into a deletion. So the notifier holds the document
whole (to the contract's 64), `radioDialProvider` takes twelve, and a
thirteenth pin from *this* client is refused with a sentence rather than
swallowed - dropping it silently and PUTting the unchanged list back is a
tap that reports success and does nothing. The toggle is optimistic with a
rollback, because a star that waits for a round trip before it fills reads
as a dropped tap; it answers the refusal rather than throwing it, since the
callers are a 16-pixel glyph and a menu item, neither of which is a place
an unhandled rejection can be seen.

Writes are serialised in `PrefsController` rather than per caller, because
the unit at risk is the document: PUT replaces all of it and the server
takes the last writer, so two overlapping writes each build from the same
loaded value and the second has never heard of the first. Stars tapped in a
run make that easy to hit; a pin racing a theme change loses the theme just
as quietly. Additive, `oasdiff` clean.

### Search's radio chip is not part of "All"

The other three chips filter an answer `GET /library/search` already gave.
Radio asks a different question of a different surface: the public station
directory, over the internet, for stations this server does not have. So
it is excluded from `all` - a keystroke with no chip chosen must not fire a
directory call - and it answers *before* the empty-query branch, because
the recent searches are queries put to the library and offering them under
this chip would be a shortcut to the wrong surface. Every row's action is
"Add station", through the hub's own add flow.

## Consequences

Five deferred entries close: cast preflight has no UI surface, cast device
artwork (which landed server-side ahead of the phase and is consumed by
the queue loads the picker starts), the deck bar's remote-session face, the
deck bar's volume slider, and search's radio results. A sixth goes with
them for a different reason: the entry tracking the compact search control
described a gap that did not exist. The library grid has carried the
control since P10 and *is* the home screen, so what remained was the P17
`WaxScaffold` conversion that P17's own row already covers - the entry had
been carried forward and edited rather than checked, which is how a stale
note becomes a claim that a phone cannot search from home.

Nothing new is deferred. The one candidate - per-device favourites - was
built per account instead, above.

Two bugs older than this phase were found and fixed on the way, neither in
radio or cast. A chosen filter chip did not survive the next keystroke:
the address bar follows the settled query, and the screen adopted the query
the location arrived with - including the one it had just written itself.
Picking Podcasts and typing put the chips back to All. And the deck bar drew
a **disabled star** over live radio, because the star was the one left-zone
control not gated on being wired; a station has no per-user state to star,
and a permanently greyed control reads as broken rather than as absent.

`WaxOptionRow` is new beside `MediaListRow`: a glyph, a name, a line under
it, and something on the right, for lists that are not media. The leading
slot is the difference and it is not a small one - a media row's leading
slot is artwork, which means a monogram when there is none, and a speaker
drawn as the letter K is not a speaker. It carries P12's lesson in its
shape: the label sits on the content region and the trailing control keeps
its own node, because excluding a whole row's subtree so it announces once
takes its own controls out of the semantics tree while leaving them
perfectly visible.

`routedHost` grew an `at:` parameter for screens that write their own
location. Hosted at a path of its own, such a screen is *replaced* by the
app's real route when it publishes, so a fresh State is built - which is
how the filter-chip bug hid from a suite that had a test for arriving on a
shared link.

Four primitives took a rule callers were getting wrong, on the principle
that a guard belongs where it cannot be forgotten. `WaxSlider` reads a
level of zero as muted whatever the caller said. `WaxSeekBar` offers no
seek over a zero-length track: every position it computes is a fraction of
the duration, so at zero a scrub or a screen reader's step seeks to the
start, and callers reach that without meaning to - an item whose duration
has not resolved, a session frame that carries none. `WaxOptionRow` grew
`activeLabel`, because its highlight is occasionally not about playback and
the connection check was announcing every reachable cast address as one the
sound was coming out of. And `MediaCard.gridFor` is the measured
column count that shows, books, and station logos each had their own copy
of, differing in nothing but the tile extent - a copy that is easy to get
subtly wrong, since disagreeing with `heightFor` overflows.

Two lifetimes were tightened. `RemoteSessionController` follows the
endpoint list only while it holds a session: it is watched by the deck bar
and so never disposed, while `playerEndpointsProvider` is auto-dispose, and
a listen held from `build` pinned it - every idle client fetching the
endpoint list at launch and refetching on every player invalidation to
answer a question only a driven session asks. And `searchResultsProvider`
selects the one thing about the chip it cares about, so switching between
the library scopes filters the answer in hand instead of refiring the
identical query behind a skeleton.

Known non-closure, unchanged: cast UX acceptance here is against the
wire-honest fakes and the loopback stack. The real-device cast checklist
stays hardware-gated and stays open.
