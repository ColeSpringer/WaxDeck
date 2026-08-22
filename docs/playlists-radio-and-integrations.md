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
for (`bitrate`, `size`, `bpm`, the `mbz_*` identifiers, and the rest),
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

### Covers

Every playlist gets a cover without being given one. The server tiles
the first four member covers that differ into one square image,
deduplicated by the artwork itself, so a playlist drawn from a single
album shows that album's cover once instead of four times; below four
distinct covers it shows the first member's. The cover refreshes when
the membership moves or when a member's own artwork changes, which for a
smart playlist means the next time anyone opens it.

An owner can upload a cover instead (playlist menu, Set cover). It
replaces the generated one everywhere at once, and Reset cover hands
the slot back rather than leaving the playlist bare. Covers serve at
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
calls mapped onto podcast and audiobook resume positions. Clients
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
