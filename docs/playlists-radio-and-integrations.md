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

Two honest limitations, both recorded in docs/upstream-requests.md:
date conditions compare absolute dates (a rule meaning "recently"
must be re-saved to move its cutoff), and saving a rule change
reissues the playlist's internal id, which clients follow
automatically.

Playlists round-trip M3U8 for interop with path-based players. Import
lives on the playlists screen (paste a file's contents; the server
matches entries against the library and reports what it could not
place), and every playlist detail menu offers Export M3U with a copy
button.

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

Each user connects their own accounts under Settings, Scrobbling:

- **ListenBrainz**: paste the user token from your profile page. A
  compatible server (Maloja and friends) can be set as the API URL.
  API URLs on private network addresses are refused by default, since
  the server delivers to them; set
  `WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS=true` for a LAN instance.
- **Last.fm**: needs server API credentials
  (`WAXDECK_LASTFM_API_KEY` and `WAXDECK_LASTFM_SECRET`); users then
  link through the standard browser authorization.

Listens that cross the played threshold queue in a durable outbox and
deliver in the background with retries, so scrobbles survive restarts
and outages; offline listens replayed later scrobble with their
original timestamps. Tokens and session keys are sealed at rest.

Each connection row shows its delivery health: the last successful
delivery, or the standing error when deliveries are failing (a
revoked session key no longer fails silently). Reconnecting resets
the slate.

## Notifications

Administrators configure delivery under Settings, Notifications.
WaxDeck relays through an [Apprise](https://github.com/caronc/apprise)
API server: one integration, most notification services. Point the
Apprise URL at your instance's notify endpoint, optionally list target
URLs, choose which events deliver (new episode downloaded, podcast
feed disabled), and send a test.

Android clients can additionally register a UnifiedPush endpoint, so
per-user events push without any Google services; registrations are
listed and revocable in Settings.

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
