# Podcasts and audiobooks

WaxDeck treats podcasts and audiobooks as first-class media alongside
music: per-user subscriptions, chapter-aware book resume, silence
trimming, and a gpodder-compatible sync API for third-party podcast
apps.

## Setting up

Podcasts need a download directory of their own, outside your library
roots (episodes are managed files, not scanned ones):

```
WAXDECK_PODCAST_DIR=/podcasts
```

The compose file ships this wired: a `waxdeck-podcasts` volume mounted
read-write in `waxdeck` and read-only in `waxflow` under the matching
`podcasts=` root name. If you run the processes yourself, add the same
directory to `WAXFLOW_ROOTS` so episodes can stream.

If your feeds live on your own LAN (a private podcast host), set
`WAXDECK_ALLOW_PRIVATE_FEED_HOSTS=true`; by default WaxDeck refuses to
fetch feeds or enclosures from private addresses.

## Subscriptions are per user

Shows and episode files are cataloged once and shared; who follows what
is per user. Two people can follow the same show with different
settings and never interfere. Per subscription you can set:

- playback speed, silence trimming, voice boost, and intro and outro
  skip seconds for the show
- automatic download of new episodes
- a folder for organizing your subscription list
- how many downloaded episodes to keep (see retention below)

The show itself - unlike the settings above - is shared, and so is its
cover: it comes from the feed, and accounts that may manage podcasts
(administrators implicitly) can replace it through **Set cover** in the
show's menu. A hand-set cover is pinned so a feed sync never fetches
the feed's image over it; clearing it and lifting the pin hands the
slot back to the feed.

## Episodes live on the server

An episode streams once its audio is on the server. Fetch one on
demand (the fetch button, or `POST /api/v1/episodes/{pid}/fetch`) or
turn on automatic download for the subscription. The scheduled feed
refresh (default every 30 minutes, `WAXDECK_FEED_REFRESH_MINUTES`)
picks up new episodes; a feed that keeps failing is suspended from the
schedule and reactivates on a successful manual refresh.

The fetch has an inverse: any subscriber can remove a downloaded
episode (`DELETE /api/v1/episodes/{pid}/fetch`). The audio moves to
the library trash, everyone's positions and history survive, and the
episode can be fetched again at any time.

### PodPing

`WAXDECK_PODPING=true` lowers that thirty-minute floor to seconds for
the shows whose hosts publish [Podping](https://podping.org)
notifications. A host asks a podping.cloud writer to name the changed
feed on the Hive blockchain, and WaxDeck reads the chain and refreshes
that one show at once. It is a signal, never a replacement: a host that
does not publish, a writer having an afternoon, and a node WaxDeck
cannot reach all end the same way, with the scheduled refresh finding
the episode a few minutes later.

Off by default, because it is a standing outbound connection to a
third-party public node, and because the schedule already works. What
it reads is public and anonymous - blocks everyone can read - and it
sends nothing about this library anywhere; the only thing it can cause
is a refresh of a feed already subscribed here.

Two limits keep that from being worth much to anyone who tried to abuse
it. A show is refreshed at most once a minute this way no matter how
many notifications name it, and the floor is kept in the catalog rather
than in memory, so restarting WaxDeck does not reset it - which is the
same floor a subscriber's own manual refresh keeps. And a refresh that
fails does not count towards the ten consecutive failures that disable
a feed: those count this server's own scheduled attempts, because a
stranger relaying a busy host through a bad afternoon should not be
able to turn off a subscription nobody here asked to stop.

- `WAXDECK_PODPING_NODE` names a Hive API node (empty picks a public
  one).
- `WAXDECK_PODPING_WRITERS` pins the trusted writer accounts, comma
  separated. Empty, WaxDeck resolves the published podping.cloud writer
  set from the chain, refreshed hourly, which is how it is meant to be
  read. A notification from any other account is ignored - anyone may
  write to a public chain, so the writer's identity is the whole of the
  trust decision.

A feed suspended after repeated failures stays suspended: a stranger's
notification is not a manual refresh, and honouring it would undo the
backoff. A show already refreshed in the last thirty seconds is left
alone, so one publish that puts several notifications on the chain
still costs the host one request.

Unsubscribing keeps the show, its episodes, and your progress. When
the last subscriber leaves, the app asks whether the downloaded files
should go too; keeping them leaves the show ready for the next
subscriber, removing them reclaims the disk the same trash-backed way.
While anyone else still subscribes, their retention owns the files and
an unsubscribe never touches them.

## Retention: archive, never delete

Retention reclaims disk, not history. When a show's downloaded
episodes exceed the effective keep-newest-N, the oldest files are
removed, but every user's positions, stars, and play history survive,
and a reclaimed episode can always be fetched again.

The effective policy for a show is the most generous union across its
subscribers: if anyone keeps everything, everything stays; otherwise
the largest N wins. Episodes starred by any subscriber or sitting in
someone's play queue are kept regardless, and a file someone is
actively listening to is never reclaimed under them.

## Private feeds

Subscribe with a username and password for feeds behind basic auth.
Credentials are stored encrypted and never returned by any API. A
credentialed show (or any show a subscriber marks private) becomes
private permanently: its feed URL disappears from every API response
and every OPML export, because tokenized feed URLs are themselves
secrets. Privacy hides the URL, not the show: any user who can see the
podcast library can browse and play it.

## OPML

Export your subscriptions (private shows excluded) or import a
document from another app; folder outlines round-trip. In the API:
`GET /api/v1/podcasts/opml` and `POST /api/v1/podcasts/opml`.

## Third-party podcast apps (gpodder)

WaxDeck speaks the gpodder.net API, so AntennaPod and friends can sync
subscriptions and episode positions directly:

1. Create an app password in Settings (the same mechanism the Subsonic
   API uses; your login password never works here).
2. Point the app at your WaxDeck base URL with your username and the
   app password.

Subscription changes and play positions sync both ways; positions run
through the same per-medium reconciliation as first-party clients.
The test suite replays AntennaPod's actual sync sequence (login,
device registration, subscription diff, episode actions with its
timestamp format) against a live server on every run, so a regression
there fails CI rather than a user's sync.

## YouTube channels as shows

With the acquisition bridge enabled (`WAXDECK_YOUTUBE=true`), a
YouTube channel or playlist URL subscribes like a feed: new videos
appear as episodes and fetch as audio, stamped with their source URL
and acquisition date. The optional WaxSeal sidecar (compose profile
`youtube`) unlocks the full-quality path. SponsorBlock segment cutting
is available opt-in via `WAXDECK_YOUTUBE_SPONSORBLOCK`.

## Audiobooks

Books are one item with chapters on a single timeline, whether they
are a chaptered m4b or a folder of parts. Progress lives on the book
timeline, so resuming on another device lands in the right chapter of
the right part. The book screen offers chapter navigation, per-book
speed memory, and a sleep timer with an end-of-chapter mode.

A series is a name a book's tags carry, in the grouping field, with an
optional number after it ("Tidewater #2"). Books that name one get a
**Series** shelf on the hub and an index behind it; a series opens to
its books in the order the numbers put them, and the series line on a
book screen is the way in. The number is whatever the tags say, so it
can be decimal for an in-between entry and absent for a book that
names the series without one. Because a series is a spelling rather
than something anyone curates, two spellings are two series: an
administrator folds one into the other from the book screen's
overflow, and the books move while everything else about them stays.

## Silence trimming and voice boost

Silence trimming skips mapped quiet spans client-side by seeking over
them, so positions stay honest and the hours-saved counter is exact.
Maps are computed in the background by the streaming sidecar the first
time they are asked for; offline listening keeps trimming because
downloads store the map alongside the audio.

Voice boost levels spoken-word loudness. Clients with local audio
processing apply it themselves; for the web and other thin clients the
server applies it in the stream (compression plus leveling gain from
the measured loudness), at the cost of a transcode.
