# Playlists, radio, and outbound integrations

This page covers the playlist system (manual and smart), the internet
radio library, outbound scrobbling, server notifications, and the
compatibility surfaces that expose them to third-party apps.

## Playlists

WaxDeck has two playlist kinds:

- **Manual playlists** are ordered lists you curate by hand: add from
  the player's add-to-playlist button, reorder by dragging, remove per
  row. Duplicates are allowed. A removal made from a stale view of the
  list (another device changed it since) is refused rather than taking
  another track that moved into that row, and the list reloads.
- **Smart playlists** are rules evaluated live: "rating at least 80",
  "unplayed podcasts under 30 minutes", "anything tagged MOOD=focus".
  Membership recomputes on every read, so a star or a rating change
  updates the list immediately, with no refresh job.

Both kinds are private by default. A shared playlist is visible to
every user on the server; only its owner can edit it. A shared smart
playlist always shows the owner's evaluation: "my top rated" means the
owner's ratings, and viewers see the owner's list. Each reader sees
only the members they could open themselves: a track outside their
libraries, one their content settings deny, or an episode of a show
they do not follow is left out of the listing, the count, and both
exports, on the Subsonic API as on REST.

### The starter

Every account is created holding one smart playlist, **Most played**:
music you have played at least once, most played first, capped at 50.
It exists so a first sign-in lands on something rather than an empty
grid, and it is an ordinary playlist in every other way - yours to
rename, re-rule, share, or delete, and it is not special-cased
anywhere else in the server.

Deleting it sticks, permanently: the server remembers that the account
was offered the starter, so it does not come back on the next restart,
and it does not come back if the catalog is later rebuilt either. What
a rebuild does bring back is a starter nobody deleted, since that drops
the playlist while the record of the offer survives.

### The rule editor

Rules are groups of conditions. A group matches ALL of its children or
ANY of them, and groups nest, so "music AND (rating at least 80 OR
starred)" is three rows and one nested group. Fields cover the catalog
(title, artist, composer, album, genre, year, duration, codec, added
date, the file's path, MusicBrainz ids), the spoken-word dimensions
(show, season, published date), your own listening state (starred,
rating, play count, played, finished, last played), and every custom
tag as `tag.KEY`. Because listening state is per user, the same smart
playlist gives each user their own results.

Sort keys and a member limit turn rules into charts: "my 25 most
played this collection" is one condition, one sort, one limit. The
editor previews the match count live while you build.

Date conditions read either way. `before`, `after` and `inTheRange`
compare a fixed date; `inTheLast` and `notInTheLast` take a window in
days and anchor it at read time, so "added in the last 30 days" moves
its own cutoff and never needs re-saving. Editing a rule updates the
playlist in place, so its pid and every link to it survive the edit.

Playlists round-trip M3U8 for interop with path-based players. Import
lives on the playlists screen (paste a file's contents; the server
matches entries against the library and reports what it could not
place), and every playlist detail menu offers Export M3U with a copy
button. Every import matches only what the importing account can see:
an entry naming a track outside its libraries or denied by its content
settings is reported as unmatched, the same as one nothing matched. M3U8 carries no cover: the format has no directive for one, so
an exported playlist is text and its cover stays on the server.

### Navidrome smart playlists (NSP)

A rule, unlike a member list, round-trips as a rule.
`POST /playlists/nsp` takes a Navidrome `.nsp` document as the request
body and creates a smart playlist from it; `GET /playlists/{pid}/nsp`
writes one back out. The conversion is the catalog's own, so the two
servers agree about what a field means rather than drifting apart as
either gains one.

Most fields keep their name. The rest map onto the rule's own: `loved`
is `starred`, `duration` is `durationMs`, `filepath` is `relPath` (the
path under the library's root, which is what Navidrome keeps),
`catalognumber` is `albumCatalogNumber`, the three `mbz_*` ids for a
recording, an album and a release group are `recordingMbid`,
`albumMbid` and `releaseGroupMbid`, and the dates `dateadded`,
`lastplayed` and `dateloved` are `addedAt`, `lastPlayedAt` and
`starredAt`. A document an older WaxDeck exported calls the star
`starred`, which is not NSP's name for it, so the import reports it as
a field it cannot read: rename it to `loved`.

`rating` and `duration` are rescaled rather than copied: Navidrome rates
0 to 5 where the catalog rates 0 to 100, and counts seconds where a rule
counts milliseconds. An unscaled `rating gt 3` would mean "rated above 3
out of 100", which is every rated track: a playlist that looks imported
and is not the one you had. On the way out, a rating that is not a
whole number of stars, or a duration with a fraction of a millisecond,
is refused rather than written as a value Navidrome cannot mean.

That is the rule for both directions by default: **anything that cannot
be said exactly refuses the whole document, naming every part that
stopped it.** Half a rule is a different playlist, so nothing is
quietly dropped. On import that covers fields the catalog has no answer
for (`bitrate`, `size`, the artist `mbz_*` ids, and the rest),
`limitPercent` and any other unrecognised top-level key (including a
typo for `all`, which would otherwise import as a rule over your whole
library), `inPlaylist`, and every date comparison but a window of days
back (`inTheLast`, `notInTheLast`), since NSP's naive local dates have
no faithful reading against stored instants. On export it covers what
the catalog can say and NSP cannot, which is more: every negation but
`notContains`, `gte` and `lte`, `isPresent` and `isMissing` on a field
Navidrome never leaves empty, a date compared other than by a window of
days, custom `tag.KEY` fields, the budget limit modes, and the fields
NSP does not carry at all.

**A rule sorted on more than one term is one of them.** NSP orders on a
single `sort`, so a playlist ordered by play count and then by title
refuses rather than exporting with the second term silently gone - and
a rule may carry up to four, so this is a rule somebody has. Reordering
a playlist without saying so was worse than either answer.

You can accept the loss instead. **Export as NSP** asks first: a rule
that maps exactly hands back the document, and one that does not lists
every part that would go, each under the rule editor's name for its
field and in the app's language, then shows what the export keeps as
the same chips the playlist header draws, before offering to export
without them. The report carries a `ruleHash` the export takes
back, so a rule edited while the dialog is open (a shared playlist's
owner saving a change, say) is refused with `conflict` rather than
exported against a list that no longer describes it; the app reads the
new report and asks once more.

Import works the same way. On the playlists screen, **Import playlist**
then **Navidrome smart playlist** takes the pasted `.nsp` file, and
**Check** lists every part WaxDeck cannot read before anything is made:
**Import** when nothing is lost, **Import without them** (with what that
keeps) when something is. A damaged document (both an `all` and an
`any` group, a rule that is not one operator) is refused outright, since
a partial import of it would drop what somebody wrote without saying so.
A condition the rule editor would not save as written counts as a part
WaxDeck cannot read too: an operator its field does not take
(`contains` on `year`, `gt` on `title`), a value of the wrong type, a
window past 100000 days, or an `offset`, which a rule does not hold.
The document's `public` sets the **Shared with everyone** switch, which
decides; the new playlist opens when it is made. Through the API,
`POST /playlists/nsp/report` says what a document would lose and what a
partial import would keep, and `?partial=true` on either operation takes
it. Both still refuse when nothing survives, since a rule with every
condition dropped selects the whole library rather than a smaller
version of what was asked for.

The report is its own request rather than something a successful export
carries back: the export's body is the document *another server reads*,
and a report key beside `all` and `sort` would either be rejected over
there or change what the document means.

### Synced from a source

A manual playlist can be bound to an external source and kept in step
with it. The owner opens **Sync from source** in the playlist menu,
pastes a YouTube playlist URL, and picks a mode and an interval (1, 3,
6, 12, or 24 hours). From then on the server re-enumerates the source
on that schedule and whenever **Sync now** is pressed; new entries are
downloaded through the same acquisition path as "Add from URL", ride
the normal review queue, and join the playlist in source order once
their review entries resolve into items. A video the library already
holds from an earlier download - this playlist's, another synced
playlist's, or a manual acquisition's - is recognized and attached
without downloading again.

The mode is the intent. **Append** only adds: new source entries join
the end, your own edits are never touched, and a member you remove by
hand stays removed. **Mirror** makes membership and order follow the
source; a removed entry leaves the list but its file stays in the
library. **Mirror and trash** additionally moves a removed entry's
file to the recoverable trash - only files the sync itself brought in,
never something you added by hand - and selecting it needs the delete
right (administrators always hold it).

**Preview** dry-runs the same reconciler a sync runs and reports what
it would do - tracks that would join, downloads it would queue,
members that would leave, files that would go to the trash - without
changing anything, including before the binding is saved. Availability
is best-effort: enumeration inspects a bounded prefix of the source,
so a long playlist's later entries count as unknown until a download
is attempted.

A streaming export (Spotify, Apple Music, YouTube Music, CSV, text,
portable) can be recorded as a binding too. It reconciles match-only
and on demand: a sync re-runs the import resolve ladder against the
library, attaches what matched, and reports the misses, downloading
nothing - there is no live connector to re-fetch the export from, so
there is no schedule either. **Import playlist** offers to keep the new
playlist matched to what you pasted, and binds as mirror, because the
playlist is that export rather than a copy of it. The sync sheet is the
other door: a playlist you already have chooses between a link and an
export there, and pasting one binds it. A matched binding takes append
or mirror - it downloads nothing, so there are no files to trash.

Saving the sheet on a playlist that is already bound changes the
settings and nothing else: the export you pasted is not asked for
again, and a live binding's source is not re-fetched to change a mode.
Editing the URL on a live binding is what rebinds it.

Sync health rides the binding. The playlist header wears a chip
(Synced, Sync failing, Sync suspended - and, before any run has
completed, Sync scheduled for a live source or Matched for an export,
which has no schedule to be waiting for), the settings sheet shows the
last run's counts and the last error, and a binding that keeps failing
is suspended after ten consecutive misses - a successful manual sync
turns it back on. A sync never overwrites an edit you are making: a run
that collides with a concurrent change backs off whole and retries at
the next interval. The mirror modes also refuse a listing they cannot
trust - one cut short by the enumeration cap, or a clean empty answer
from a source that has synced before - rather than removing what a
partial page merely failed to show. **Stop syncing** removes the
binding and touches nothing else; the playlist keeps everything it
holds, and the source's thumbnail hands the cover back to the mosaic.

### Covers

Every playlist gets a cover without being given one. The server tiles
the first four member covers that differ into one square image,
deduplicated by the artwork itself, so a playlist drawn from a single
album shows that album's cover once instead of four times; below four
distinct covers it shows the first member's. The cover refreshes when
the membership moves or when a member's own artwork changes, which for a
smart playlist means the next time anyone opens it.

A synced playlist prefers its source's own thumbnail over the mosaic:
the sync fetches it when the playlist is bound and re-checks it on
every run, and an upstream source without a playlist-level image
contributes its first available entry's thumbnail, which is what the
platform itself shows for a playlist nobody gave a cover.

An owner can upload a cover instead (playlist menu, Set cover). It
replaces the generated one - and a synced list's source thumbnail -
everywhere at once, and Reset cover hands the slot back rather than
leaving the playlist bare. Covers serve at
the same artwork endpoint as everything else, under the playlist's own
id, so third-party Subsonic clients pick them up through `coverArt`
with no extra work; a private playlist's cover is as private as the
playlist. The cover belongs to the playlist, like its name, so a
shared list shows every reader the owner's mosaic, including covers of
members a reader's own access leaves out of their listing.

## Internet radio

The radio library is shared by the whole server: any user can add,
edit, or remove stations. Add stations by searching the public
radio-browser directory or by pasting a stream URL. Playback proxies
through the server's origin, so web clients are never blocked by a
station's missing CORS headers. The proxy relays audio only: a `.pls`
or `.m3u` playlist address is followed to the first stream it names,
and HLS station addresses are not supported.

Stream URLs pointing at private network addresses are refused by
default, since the server fetches them; set
`WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS=true` for a LAN icecast.

The proxy also reads the station's in-stream ICY metadata, so the
radio screen shows the current song title while you listen. The
metadata is stripped from the audio it forwards, and the title is
visible to any user asking about the station (stations are a shared
library, so an active title also reveals that someone on the server
is streaming it).

Subsonic clients see the same library through
`getInternetRadioStations` and can manage it with the create, update,
and delete calls.

## Scrobbling

Each user connects their own accounts under Settings, Integrations:

- **ListenBrainz**: paste the user token from your profile page. A
  compatible server (Maloja and friends) can be set as the API URL.
  API URLs on private network addresses are refused by default, since
  the server delivers to them; set
  `WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS=true` for a LAN instance.
- **Last.fm**: needs server API credentials - the pair that
  identifies this install as a Last.fm application (register one at
  last.fm/api/account/create). An administrator sets them right in
  Settings under the Last.fm row (sealed at rest), or through
  `WAXDECK_LASTFM_API_KEY` and `WAXDECK_LASTFM_SECRET`; a pair set in
  the UI wins over the environment one. Users then link their own
  accounts through the standard browser authorization. Changing the
  API key invalidates existing links (session keys belong to the
  application that minted them); reconnecting fixes them.

Radio scrobbles too, where a station's stream titles parse as
"Artist - Title" and a segment played long enough to count. That is
right for a music station with honest metadata and wrong for a talk
station whose titles happen to fit, so **Scrobble radio** in the same
section turns it off for your account without touching library
listening.

That switch is the whole dial. One station at a time is the same
choice made from the station's own menu, on the hub's tile or on the
player's radio face: **Do not scrobble this station** keeps that
station's segments off your scrobblers while the rest still report.
The row is offered only where it means something, so it appears once
you have a scrobbler connected and the dial is not already silenced.

**Radio plays scrobble too.** While you listen to a station through
the proxy, the in-stream title's transitions bound the tracks: a
segment scrobbles when the title changes away from it after at least
thirty seconds (radio carries no track lengths, so the minimum listen
stands in for the half-track rule). Only segments with an observed
ending scrobble - a station whose "title" never changes produces
nothing, and the unfinished track at disconnect stays off the record.
Titles that do not honestly parse as "Artist - Title" (station
slogans, URLs, ads) are dropped rather than guessed at.

Scrobbling and your own listening stats are separate questions with
separate answers. Scrobbling needs a parseable song title and can be
turned off; the listening record only needs the connection, so radio
time counts toward your totals, your heatmap, and a **Top stations**
list whatever a station's metadata says - or whether it sends any.

Listens that cross the played threshold queue in a durable outbox and
deliver in the background with retries, so scrobbles survive restarts
and outages; offline listens replayed later scrobble with their
original timestamps. Tokens and session keys are sealed at rest.

Each connection row shows its delivery health: the last successful
delivery, or the standing error when deliveries are failing (a
revoked session key no longer fails silently). Reconnecting resets
the slate.

## Discord presence

On a Linux or Windows desktop, **Show what I am listening to** (Settings,
Integrations) sets your Discord status through the Discord app running
on the same machine: the track, the artist, the album, and a progress
bar. The image beside it is the album's cover from the Cover Art
Archive when the album carries a MusicBrainz release ID and **Show
album covers** is on. It is the archive's 250 px thumbnail, the
smallest the archive serves, which is plenty for the size Discord
draws it at. This device asks the archive for it, so the archive sees
the release ID and this machine's address, and Discord fetches the
image. Otherwise it is the image uploaded to the application presence
publishes as, and so it is when Discord refuses an image URL (the app
stops sending them until Discord is dialled again).
Presence describes this machine's own playback, so a session you drive
on another device through Connect is not published.

## Notifications

Every user picks where their events go on the **Notifications** screen,
which the sidebar carries a row for and which also holds the account's
inbox (the same list the bell in the top app bar peeks at). The targets
are on Settings, Integrations, My notifications as well.

The inbox is the server's own record of what happened to an account,
written whether or not a delivery target was configured for the event:
a target is how news leaves the server, not where it is kept, so a
device that was closed at the time still finds the news, and so does a
second one. A row names the event, so a client words it in its own
language and falls back to the server's wording only for an event it
does not know. Rows are read rather than removed - going where one
points marks it read, "mark all read" clears the badge, and delete is
what removes one - and the server prunes them by age (ninety days) and
by a per-account cap. Emptying the inbox is on the screen and asks
first: it is durable, shared by every device on the account, and there
is nothing to undo it with. Beside the inbox the screen still lists what this
device did itself: a finished download is this machine's news and
nothing the server keeps. A target is one destination: native Pushover, ntfy,
or Gotify delivery, a Discord or generic webhook, an
[Apprise](https://github.com/caronc/apprise) API server (one
integration, most notification services), or the UnifiedPush endpoint
the Android client registers so events push without any Google
services. Each target selects its own events (a subscribed show's new
episode, an episode you asked for downloaded, a podcast feed disabled,
the review queue ready, an upload or acquisition filed without review,
a synced playlist pulling in changes or being suspended, and for an
administrator the end of a library job or a health fix they started)
from the server's event catalog, has
a per-target test button that waits for the delivery and says whether
it landed, and shows its delivery health:
the last successful delivery, or the standing error while deliveries
fail (a revoked token no longer fails silently). Configuration is
sealed at rest and round-trips verbatim to its owner for editing.

Server operations events (account requests, backup outcomes) are a
separate scope: administrators manage server-wide destinations under
Settings, Integrations, Server notifications, and can additionally subscribe their
own personal targets to server events, so a signup request reaching
an administrator's phone is a personal choice, not server
configuration.

Per-kind options beyond the destination itself. A **webhook** takes up
to eight extra request headers (typed a line at a time as `Name: value`;
the transport's own names are refused) and a **signing secret**: with
one set, every post carries `X-WaxDeck-Timestamp` (unix seconds) and
`X-WaxDeck-Signature`, which is
`sha256=<hex HMAC-SHA256(secret, timestamp + "." + body)>` over the
exact bytes sent, so a receiver can tell a real delivery from a forged
one. **ntfy** deliveries carry a click destination and an Open action;
**Discord** embeds carry a timestamp, a colour per event family and a
WaxDeck footer. Every link needs `WAXDECK_PUBLIC_BASE`: without it the
server does not know a URL anybody outside its own network could
follow, and leaves the link out rather than sending a dead one.

Two ways to turn a destination down without deleting it. **Muted**
pauses it, keeping the configuration and the event selection; anything
already queued for it is dropped rather than held for the unmute.
**Seconds between deliveries** paces it, holding a delivery that lands
inside the gap rather than failing it. The cap is an hour, and it bounds
the wait rather than the queue: a target fed faster than its interval
queues faster than it drains, and the deliveries that cannot be reached
inside the outbox's day are shed with a line in the log. A per-target
test ignores both, and does not start the gap either, so a destination
can be checked while it is silenced or slowed without parking the next
real delivery. A destination that answers 429 or 503 with a
`Retry-After` is waited out for as long as it asked, up to the backoff
ceiling.

User-pointed destination URLs (ntfy, Gotify, webhooks, Apprise)
refuse private addresses unless the server opts in with
`WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS` (for LAN ntfy or Gotify
instances). Pushover and Discord post to their services' own hosts,
and UnifiedPush endpoints are deliberately exempt: self-hosted LAN
distributors are legitimate.

## Third-party apps

Subsonic and OpenSubsonic clients sign in with an app password,
managed under Settings; the login password never works there.

Browsing covers the ID3 views and folder mode (`getIndexes`,
`getMusicDirectory`, `getAlbumList`, `getStarred`, emulated from tags
with the same ids as the ID3 views), search, `getRandomSongs`,
`getSongsByGenre`, `getGenres`, `getScanStatus` and cover art. A cover
that does not exist answers HTTP 404, so a client shows its own
placeholder. Music folders are your music libraries, each under an id
that stays put as libraries come and go; `musicFolderId` narrows
browsing, the album and song lists, search and the starred lists to one
of them, and an album with tracks in two libraries is in both.
Audiobook libraries and the podcast library are never music folders.
Books and episodes appear as songs in the starred lists (unless
`musicFolderId` narrows them), playlists, bookmarks, `getNowPlaying`
and `getSong` on their own ids, and episodes in `getPodcasts` and
`getNewestPodcasts`. They never appear in the browse views, the album
lists, search, `getRandomSongs`, `getSongsByGenre`, `getGenres`,
`getTopSongs` or the similar-song views, and `getScanStatus` counts
music alone.

Album lists answer every type: `random`, `newest` (recently added),
`recent` (recently played), `frequent` (most played, an album's tracks
added up), `highest` (your album ratings), `starred`,
`alphabeticalByName`, `alphabeticalByArtist`, `byYear` (either
direction; albums with no year only when the range starts at 0) and
`byGenre` (any album with a track of that genre). `recent`, `frequent`,
`highest` and `starred` are the signed-in account's own; `recent` and
`frequent` can lag a play by up to a minute. `newest` lists
every album: those of the 20,000 most recently added tracks in that
order, then the rest by name, so paging through it reaches the whole
library. Songs, albums, artists and folder-mode directories carry your
star (`starred`, with when you starred it) and your rating
(`userRating`, 1 to 5); songs and albums carry your play count and last
play, and when they were added; songs also carry their file's size and
bitrate, and `bookmarkPosition` where you hold a bookmark on them.
`getTopSongs` is your most played tracks by the artist. `getNowPlaying`
lists what the WaxDeck apps and devices are playing for you, and for
others on a device shared with you, a paused session until ten minutes
after it last moved; a Subsonic client's own plays are not sessions
there.

Stars and ratings write the same state the WaxDeck apps show, and so do
playlists (create, read, update, delete, reorder, remove by index,
several indexes in one write; an index from a listing the playlist has
since changed away from is refused rather than removing another track).
Scrobbles become listens with full dedup, and now-playing updates
forward to connected scrobblers. A scrobble time in seconds,
milliseconds, microseconds or nanoseconds lands when the play happened;
one before 2000 or more than a day ahead is stamped on arrival instead,
and a client resending an untimed scrobble straight away (within the
track's length, at most ten minutes) normally counts once, while one
submission naming a track twice counts twice. Bookmarks work for every
kind of item: every book and episode in progress is one, the position
the WaxDeck apps resume from (a finished one is not, unless you save a
bookmark on it), while a track's is kept on its own and leaves the
track's place alone, and stays when the track becomes a book. Comments
are kept, and an account holds up to 1000 bookmarks; those on items
hidden from you for now (a library or content setting) are kept without
counting, up to 1000 more, the oldest let go past that.

Song and album rows carry the OpenSubsonic `explicitStatus` advisory -
episodes from their feed's declared flag (their show's counts too),
music from an `ITUNESADVISORY` tag asserting explicit, albums from any
flagged member - emitted only in the positive direction, so an absent
value means unasserted, never clean. `getOpenSubsonicExtensions`
advertises `apiKeyAuthentication`, `formPost`, `sonicSimilarity` and,
on a server running the streaming engine, `transcodeOffset`, all real,
and `tokenInfo` names the account an API key belongs to. Podcasts are
read-only (`getPodcasts`, `getNewestPodcasts`: your subscriptions); an
episode plays whether or not the server has fetched it, relayed from
the feed's own file where the server can relay it, and its status says
whether it is on the server. The internet radio library is there too.

What clients will not find: `getPlayQueue` and `savePlayQueue` are
refused, artist biographies are empty, and there are no share, jukebox,
lyrics, scan or podcast-management verbs; `getUser` claims no share or
podcast role, so clients hide those controls. A response naming more
than 500 artists and albums carries their stars but no ratings; only
the first 500 files of a response carry a size, a bitrate and an added
time; a track cut from a CD image by a cue sheet carries no size; and
an album's added time is its first track's. `newest`, `recent` and
`frequent` read at most the first 20,000 tracks of the list each comes
from (a music folder's own, under `musicFolderId`).

The test suite replays the startup, browse, and play request
sequences of DSub, Feishin, and Symfonium against a live server on
every run, so a regression on any of those paths fails CI rather than
a user's first connection.

Streaming honors `maxBitRate`: a client that asks for a cap gets an
encode at that number, clamped to a range a codec can actually speak
and then to the account's own transcode ceiling, and a lossy track
already inside the cap streams untouched rather than being re-encoded
to satisfy it. The habit several clients have of sending `maxBitRate=0`
or an empty value means "no cap" and still serves the original bytes.
A `format` pinned alongside a cap is honored where the server can
produce it, so a client that asks for 192 kbps mp3 gets mp3 rather than
whatever the ladder would have picked; one the server cannot produce
falls back to the ladder. A client that names no format gets a capped
stream, its own cap or the account's ceiling, as MP3, which every
client decodes. `format=raw` beats a cap outright and serves
the file as it is, which is what that value means everywhere else in the
protocol; a book in parts has no one file, and gets the joined stream
described below. A `format` on its own, with no cap beside it, changes
nothing: there is no encode for it to aim.

`timeOffset` starts the stream that many whole seconds in, through the
streaming engine. A track that would otherwise play as the file is
encoded from that point instead and counts as a transcode like any
other: lossless stays lossless and a lossy file keeps its codec and
bitrate where the engine writes them, unless a cap or the account's
transcode ceiling calls for less. `format=raw` beats it, as it beats a
cap. A podcast episode whose audio the server has not fetched has only
the feed's own file to relay, which nothing can cut, so a stream of one
asked to start part way in is refused rather than played from its start
under a clock that says otherwise; from its start it plays as ever.

A book in parts is one song to these clients, so its stream is the whole
book whatever is asked: one MP3 encode from the part the offset falls in,
cut there (at the whole second of the book), through the book's last
part, at the book's own bitrate (held to 32 to 320 kbps, and lowered by a
cap or the account's transcode ceiling), and counted as one transcode.
MP3 is the one output whose parts join end to end, so a `format` does not
change it, and `format=raw` gets the same stream, offset included, at the
book's own bitrate. A server without the streaming engine joins a book
whose parts are all MP3 at one sample rate and one channel count the same
way, frame by frame with nothing encoded, from its start; any other book
in parts streams its first part as its file there.
