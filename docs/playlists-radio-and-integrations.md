# Playlists, radio, and outbound integrations

This page covers the playlist system (manual and smart), the internet
radio library, outbound scrobbling, server notifications, and the
compatibility surfaces that expose them to third-party apps.

## Playlists

WaxDeck has two playlist kinds:

- **Manual playlists** are ordered lists you curate by hand: add from
  the player's add-to-playlist button, reorder by dragging, remove per
  row. Duplicates are allowed.
- **Smart playlists** are rules evaluated live: "rating at least 80",
  "unplayed podcasts under 30 minutes", "anything tagged MOOD=focus".
  Membership recomputes on every read, so a star or a rating change
  updates the list immediately, with no refresh job.

Both kinds are private by default. A shared playlist is visible to
every user on the server; only its owner can edit it. A shared smart
playlist always shows the owner's evaluation: "my top rated" means the
owner's ratings, and viewers see the owner's list.

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
(title, artist, album, genre, year, duration, codec, added date), the
spoken-word dimensions (show, season, published date), your own
listening state (starred, rating, play count, played, finished, last
played), and every custom tag as `tag.KEY`. Because listening state is
per user, the same smart playlist gives each user their own results.

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
button. M3U8 carries no cover: the format has no directive for one, so
an exported playlist is text and its cover stays on the server.

### Navidrome smart playlists (NSP)

A rule, unlike a member list, round-trips as a rule.
`POST /playlists/nsp` takes a Navidrome `.nsp` document as the request
body and creates a smart playlist from it; `GET /playlists/{pid}/nsp`
writes one back out. The conversion is the catalog's own, so the two
servers agree about what a field means rather than drifting apart as
either gains one.

`rating` is rescaled rather than copied: Navidrome rates 0 to 5 where
the catalog rates 0 to 100. An unscaled `rating gt 3` would mean
"rated above 3 out of 100", which is every rated track - a playlist
that looks imported and is not the one you had. On the way out, a
rating that is not a whole number of stars is refused rather than
written as a fraction Navidrome cannot mean.

That is the rule for both directions by default: **anything that cannot
be said exactly refuses the whole document, naming every part that
stopped it.** Half a rule is a different playlist, so nothing is
quietly dropped. On import that covers fields the catalog has no answer
for (`bitrate`, `size`, the `mbz_*` identifiers, and the rest),
`limitPercent` and any other unrecognised top-level key - including a
typo for `all`, which would otherwise import as a rule over your whole
library - `inPlaylist`, and the absolute date operators, whose naive
local dates have no faithful reading against stored instants. On export
it covers what the catalog can say and NSP cannot, which is more: every
negation but `notContains`, `gte` and `lte`, `isPresent` and
`isMissing`, custom `tag.KEY` fields, the budget limit modes, and the
fields NSP does not carry at all.

**A rule sorted on more than one term is one of them.** NSP orders on a
single `sort`, so a playlist ordered by play count and then by title
refuses rather than exporting with the second term silently gone - and
a rule may carry up to four, so this is a rule somebody has. Reordering
a playlist without saying so was worse than either answer.

You can accept the loss instead. **Export as NSP** asks first: a rule
that maps exactly hands back the document, and one that does not lists
every part that would go, in the converter's own words, before offering
to export without them. Import works the same way -
`POST /playlists/nsp/report` says what a document would lose, and
`?partial=true` on either operation takes it. Both still refuse when
nothing survives, since a rule with every condition dropped selects the
whole library rather than a smaller version of what was asked for.

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
there is no schedule either. The door is **Import playlist**, which
offers to keep the new playlist matched to what you pasted; it binds as
mirror, because the playlist is that export rather than a copy of it,
so a later re-match fills what the first pass missed and reconciles
away anything added by hand. That switch is the only way to make one
from the app: a playlist you already have cannot be bound to an export
here, and a matched binding's mode cannot be changed once it is made -
both are the API's to do.

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
playlist.

## Internet radio

The radio library is shared by the whole server: any user can add,
edit, or remove stations. Add stations by searching the public
radio-browser directory or by pasting a stream URL. Playback proxies
through the server's origin, so web clients are never blocked by a
station's missing CORS headers.

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

## Notifications

Every user picks where their events go on the **Notifications** screen,
which the sidebar carries a row for and which also holds what this
device has seen since the app opened (the same list the bell in the top
app bar peeks at). The targets are on Settings, Integrations, My
notifications as well. A target is one destination: native Pushover, ntfy,
or Gotify delivery, a Discord or generic webhook, an
[Apprise](https://github.com/caronc/apprise) API server (one
integration, most notification services), or the UnifiedPush endpoint
the Android client registers so events push without any Google
services. Each target selects its own events (new episode downloaded,
podcast feed disabled, review queue ready) from the server's event
catalog, has a per-target test button, and shows its delivery health:
the last successful delivery, or the standing error while deliveries
fail (a revoked token no longer fails silently). Configuration is
sealed at rest and round-trips verbatim to its owner for editing.

Server operations events (account requests, backup outcomes) are a
separate scope: administrators manage server-wide destinations under
Settings, Integrations, Server notifications, and can additionally subscribe their
own personal targets to server events, so a signup request reaching
an administrator's phone is a personal choice, not server
configuration.

User-pointed destination URLs (ntfy, Gotify, webhooks, Apprise)
refuse private addresses unless the server opts in with
`WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS` (for LAN ntfy or Gotify
instances). Pushover and Discord post to their services' own hosts,
and UnifiedPush endpoints are deliberately exempt: self-hosted LAN
distributors are legitimate.

## Third-party apps

The Subsonic surface now covers playlists (create, read, update,
delete, reorder), stars and ratings, `getStarred2`, scrobbling
(submissions become listens with full dedup; now-playing updates
forward to connected scrobblers), the radio library, and bookmark
calls mapped onto podcast and audiobook resume positions. Song and
album rows carry the OpenSubsonic `explicitStatus` advisory - episodes
from their feed's declared flag (their show's counts too), music from
an `ITUNESADVISORY` tag asserting explicit, albums from any flagged
member - emitted only in the positive direction, so an absent value
means unasserted, never clean. Clients
authenticate with app passwords, managed under Settings; the login
password never works there.

Real clients hit more than the ID3 core on startup, so the surface
also answers folder-mode browsing (`getIndexes`, `getMusicDirectory`,
`getAlbumList`, `getStarred`, emulated from tags with the same ids as
the ID3 views), `getRandomSongs` and `getSongsByGenre`,
`getScanStatus`, empty-but-valid `getArtistInfo`/`getArtistInfo2` and
`getTopSongs`, `getOpenSubsonicExtensions` (advertising
`apiKeyAuthentication` and `formPost`, both real), and read-only
podcasts (`getPodcasts`/`getNewestPodcasts`: your subscriptions, with
downloaded episodes streamable and everything else honestly marked).
The test suite replays the startup, browse, and play request
sequences of DSub, Feishin, and Symfonium against a live server on
every run, so a regression on any of those paths fails CI rather than
a user's first connection.
