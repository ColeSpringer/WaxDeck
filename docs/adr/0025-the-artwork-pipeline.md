# 25. The artwork pipeline

Date: 2026-07-27

## Status

Accepted.

## Context

Artwork is the surface this product is looked at through, and until now
every screen fetched it the same crude way: `Image.network(artUrl)`, full
size, no credential, no bounds.

Three things were wrong with that, in rising order of severity.

**Native builds fetched artwork with no `Authorization` header at all.**
The art endpoint requires a session; the browser attaches its cookie for
free and a native `Image.network` attaches nothing, so every cover on
Android, iOS, and desktop 401'd and silently drew a placeholder. A
library full of art rendered as a grid of grey monograms, and nothing
reported an error, because a missing cover is a legitimate state.

**Every request asked for the original.** The endpoint has served
square-fit thumbnails from 16 to 2048 pixels for as long as it has
existed. A 48-pixel queue row was downloading a 3000-pixel scan and
decoding all of it.

**A warm grid revalidated every cover.** The handler set a strong `ETag`
and no `Cache-Control`, so a browser with all two hundred covers already
on disk still spent two hundred conditional GETs to paint them.

Flutter's decoded-image cache defaults (100 MB, 1000 entries) sit on top
of all of that, identical on a phone and a desktop.

## Decision

**One `ArtworkStore`, and every cover in the app comes through it.**
`imageFor(artUrl, px)`, `bytesFor`, `warm`, `pinForOffline`, `unpin`,
`evict`, `forgetEverything`. Native and web are different problems and
get different implementations behind it: native must attach a credential
the browser attaches for itself, keep a disk cache, and answer while
offline; web has the browser's cache, which is better than anything worth
reimplementing, and no offline mode at all.

**Artwork crosses into the design system as a function of size, not as an
image.** `WaxArtwork` is `ImageProvider? Function(int px)`.
`ArtworkImage` is the only thing that knows how big a cover will be
painted (its extent times the device pixel ratio), and the store is the
only thing that knows what a URL costs; the callback is the seam. The
design system keeps its rule of depending on Flutter alone, and no screen
is in a position to fetch a 2048-pixel scan for a 48-pixel row.

**Five rungs: 64, 128, 256, 512, 1024.** A draw takes the smallest rung
that covers it and the largest rung when nothing does — an undersized
fetch is visibly soft, and this is the surface people look at. Buckets,
because the server renders and caches a thumbnail per distinct size, and
a client asking for 337 here and 341 there would make it render one per
screen width in the house.

**What is fetched and what is decoded are two different sizes.** The rung
above a draw holds up to four times the pixels the screen shows, so the
decode is bounded to the painted size: `ResizeImage` with the `fit`
policy on web, a `getTargetSize` bounded on the longest edge in the
native provider. Bounded on the longest edge rather than the width, so a
portrait book cover keeps its shape.

**The painted size is rounded up to a step of 32 before it becomes a
decode.** Flutter's image cache holds one decoded copy per key and the
key includes the size decoded at, so a cover painted at 200 pixels in one
place and 206 in another is two bitmaps for no visible difference. That
is not hypothetical: a player hero is measured from the window, so a
drag-resize would mint a decode per frame. Rounding up, never down —
smaller than its box is soft — and never past the top rung, since nothing
larger is ever fetched. The rungs are multiples of the step, so rounding
a draw up can never change which rung is fetched for it.

**The image cache gets explicit per-platform bounds**: 64 MB on a phone,
160 MB on a desktop, 96 MB on web, from the arithmetic that a cell
painted at 336 pixels holds about 450 KB decoded, a phone screenful is a
dozen cells and a wide desktop window is forty, and about four screenfuls
plus a player hero is what makes scrolling back up repaint rather than
refetch.

**`Cache-Control: private, max-age=86400,
stale-while-revalidate=604800`, and `Vary: Cookie, Authorization`,** on
the art endpoint (API item 7), on the 200 and on the 304 alike. A 304
that repeats neither the validator nor the freshness leaves the cached
copy exactly as stale as it was, so the next paint revalidates again —
which is the round trip this exists to remove. `Vary` is not decoration:
artwork follows the item's visibility, the same URL can legitimately
answer 200 for one account and 404 for another, and this endpoint takes
either credential, so a cache holding a copy fetched with one must not
answer a request carrying the other. No `immutable`: the URL names a pid
and a size, not the bytes.

**Which is why replacing a cover asks under a new name.** A day of
freshness cuts both ways: the URL is stable across a cover change, so
after a write every cache between the widget and the disk goes on
serving the old image, and the browser's is one no code in this process
can reach into. Dropping the decoded copies is what the client can do
directly; the rest is an opaque `v` parameter (declared in the spec,
ignored by the server) that the store varies for any URL it has been
told was replaced. That is what keeps `evictPlaylistCover` — a control
that exists precisely because the URL does not change — true on web.

**Pins are not a cache.** Downloading an item promises it plays with the
server unreachable, and a promise kept as a grey monogram is not kept, so
a download pins two rungs — 1024 for a player hero, 256 for a grid cell —
as files the cache may not evict, recorded in the `ArtworkPins` table
mirror schema v2 already added. A re-pin presents the stored validator
and keeps what it has when the server says nothing changed, unless the
file it validates is gone, in which case presenting one would answer 304
and leave the row pointing at nothing.

**Nobody's host but ours gets the token.** Radio station logos are
fetched straight from the station until the logo proxy lands, so a
foreign URL is routine rather than hypothetical. The store asks whether a
URL is served by the WaxDeck server this app is signed in to before it
attaches a bearer header or a `size` parameter it would not understand,
and a foreign URL is never pinned. A path is same-origin by construction;
two slashes is not a path but a host with the scheme left to the caller,
and a feed is free to write one.

**The server's own 404 ends the search.** Every item carries an art URL
whether or not it has artwork, so most of an unenriched library's grid
answers 404, and that answer is different in kind from a failure to ask:
a stale copy or a pin would draw a cover the server has stopped serving,
and looking for one costs a database query per paint of every art-less
cell. Only a fetch that could not be made falls through to the cached
copy and the pin.

**Signing out forgets artwork.** The decoded cache, the disk cache, and
the pins with their files. It is the same reasoning that already made
sign-out forget the queue: this is a local copy of things the last
session was allowed to see.

## Consequences

- The screens written before the design system still draw artwork
  through an `ArtworkBox`, which measures itself and asks the store for
  the size it turned out to be. They are being rebuilt on `ArtworkImage`
  screen by screen; until then both paths ask the same store for the same
  rung, which is the point.
- `flutter_cache_manager` is promoted from a transitive dependency
  (`audio_service` already ships it) to a direct exact pin, behind the
  store per the plugin-wrapping rule. Its ETag revalidation reads the
  server's `max-age`, so the caching contract above earns its keep on
  native as well as in the browser.
- The bearer token goes on each request rather than into a
  `FileService` built once. Section 8.7 of the plan proposed the file
  service; per-request is simpler and strictly fresher, since the token
  rotates mid-session.
- Where the cache cannot answer, the store falls back rather than
  consulting a flag: the stale copy of exactly the right size, then the
  pin. Being offline is one of several reasons a fetch fails — a
  refused credential and an unreachable server look the same to a grid —
  and falling back on the failure covers all of them without asking
  anything to keep an offline flag current.
- Warming a scroll ahead fetches without decoding. A decode belongs to
  whatever paints, at the size it paints; a warm that guessed the size
  slightly wrong would leave a second copy in memory rather than saving a
  round trip. Fetching is keyed by rung, so the guess only has to land in
  the right bucket. It runs when a scroll stops, never during one, and
  three at a time — one at a time would put two dozen round trips end to
  end, which on anything but a local server is slower than the scroll it
  is trying to get ahead of, and all at once would queue the covers on
  screen behind the ones that are not.
- Every failure in the fetch path answers with no bytes rather than an
  exception, including the ones dio does not wrap (it casts the response
  body outside its own error handling, so a body that is not what was
  asked for arrives as a plain `TypeError`). The callers are background
  work nobody awaits — a warm-ahead, a pin beside a download — where an
  escaping error is an unhandled one, and where the drawn answer to every
  failure is the same monogram.
- Eviction is exact without any bookkeeping, and that is the step's
  second job: the sizes a decode can be keyed at are a fixed ladder, so
  forgetting a cover walks it. A URL is stable across a cover change
  (that is what makes a playlist's mosaic work), so replacing one has to
  name every size it was drawn at, and remembering them instead would
  mean a set that grows for as long as the window keeps being resized.
- `ArtworkImage` re-asks when its `size` changes, so a caller that
  animates that number animates the fetch with it. Animate the box —
  a scale, a hero flight — not the extent. Nothing does today; the
  player's drag physics arrive in a later phase and this is the rule they
  inherit.
- Native tests get the plain network store: a widget test has no
  application-support directory to cache into and no server to answer, so
  its covers are monograms, which is what a test that does not stub
  artwork should see. That store carries the bearer header on its image
  requests as well as its byte fetches, so it is not one changed
  condition away from being the unauthenticated fetch this whole phase
  exists to have got rid of. On web the header map is empty (the browser
  attaches a cookie), which is what keeps the browser-native decode path.
- A pin is written only once the audio is on disk. The wait a download
  button does ends on a failed transfer too, and a pinned cover for an
  item that cannot play is a promise about nothing.
- Replacing a cover re-pins it where one is held. Pins are written by
  downloads, so nothing else would ever revisit an item downloaded before
  its artwork changed, and it would keep the old cover offline for good.
- `unpin` is called by sign-out and, when it lands, by the downloads
  manager — the roadmap puts removing a download at all in that same
  phase, and `DownloadManagerPort.remove` has had no caller since it was
  written for exactly that reason. A pin lives as long as the download it
  belongs to, which is the whole of its contract.
- The store closes the cache manager it built. Closing one that never
  opened throws from inside the package, which is worth swallowing at a
  teardown and worth knowing about before calling it.
- The web build's HTTP cache still holds the last account's covers after
  a sign-out, and it is `Vary` rather than any client code that makes
  them unreachable to the next one.
