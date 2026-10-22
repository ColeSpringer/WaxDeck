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

Podcasts live in a library of their own, the podcast library, and an
account limited to chosen libraries sees and follows podcasts only when
it is granted that one; it then hears every episode, fetched or not.
The server creates the podcast library when it fetches its first
episode, so on a new server subscribe and fetch one episode as an
administrator before granting it. An account whose grant is taken away
lists no subscriptions and changes none, in the apps and in every
podcast or Subsonic client; its subscriptions are kept, and come back
with the grant. Meanwhile they bring no new-episode or disabled-feed
notice, download nothing automatically and have no say in how many
downloads a show keeps.

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

A feed's episode plays at once, relayed from the show's own host when
the feed names its audio. Fetching it puts the audio on the server,
which is what silence trimming, voice boost, the skip map and chapters
read from the file need; a YouTube episode plays only after a fetch.
Fetch one on demand (the fetch button, or
`POST /api/v1/episodes/{pid}/fetch`) or turn on automatic download for
the subscription. The scheduled feed refresh (default every 30 minutes,
`WAXDECK_FEED_REFRESH_MINUTES`) picks up new episodes and tells every
subscriber once, whether or not they download automatically; a fetch
you asked for tells you when its audio is on the server, however many
others asked for it too, and whether or not it was already on its way.
A feed that keeps failing is suspended from the schedule and
reactivates on a successful manual refresh. Only the feed's own
failures count: its host not answering, an answer that is not a feed,
or the YouTube source's error. A refresh this server cuts short (a
catalog error or maintenance, YouTube switched off, a restart) leaves
the count where it was.

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
many notifications name it, and the floor is kept in WaxDeck's own
database rather than in memory, so restarting WaxDeck does not reset
it - which is the same floor a subscriber's own manual refresh keeps.
And a refresh that fails does not count towards the ten consecutive
failures that disable a feed: those count this server's own attempts,
scheduled or a subscriber's manual refresh, because a stranger
relaying a busy host through a bad afternoon should not be able to
turn off a subscription nobody here asked to stop.

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
backoff. A show already refreshed in the last minute is left
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
the largest N wins. Episodes starred by any subscriber or sitting in a
subscriber's play queue are kept regardless, as is an episode a
subscriber asked the server for (fetched then, or already there),
until they finish it after asking or stop following the show, for as
long as they can see the podcast library; and a file someone is
actively listening to is never reclaimed under them. Automatic
download follows the same N: a new episode dated behind that many
downloads (an older one a feed adds late, or a YouTube stream that
ended after a newer upload) is left unfetched rather than fetched only
to be reclaimed.

## Private feeds

Subscribe with a username and password for feeds behind basic auth.
Credentials are stored encrypted and never returned by any API. You are
shown, and your export names, the address you subscribed a show by,
never one another account used; someone who does not follow the show is
shown the address the server holds it under. A credentialed show, one
subscribed by an address that carries a login or a token (user info, or
a query parameter such as `token`, `key` or `auth`), and any show a
subscriber marks private become private permanently: no one who does not
follow them is shown an address for them, because tokenized feed URLs
are themselves secrets; to follow one, subscribe by the address you were
given. The address you subscribed by stays yours, a login in it
included: you, your podcast apps and your own export are given it, since
an app needs it to sync a feed that carries its login. Privacy hides the
URL, not the show: any user who can see the podcast library can browse
it and play the episodes the server has fetched. What a private show's
address or login pays for is its subscribers' alone: an episode the
server has not fetched streams from the show's host, and every episode's
transcript and chapters are read from the feed, for them and no one
else, with the login sent to the feed's own host and nowhere else.
Chapters the server stored when it fetched an episode are shown to
anyone who can see that episode. Fetching an episode to the server sends
the login to the host the feed names for its audio, so audio on another
host that wants the login plays once fetched.

## OPML

Export your subscriptions (each feed under the address you subscribed
it by, private shows included; a stored login is never written) or
import a document from another app; folder outlines round-trip. In the
API: `GET /api/v1/podcasts/opml` and `POST /api/v1/podcasts/opml`.

## Third-party podcast apps (gpodder)

WaxDeck speaks the gpodder.net API, so AntennaPod and friends can sync
subscriptions and episode positions directly:

1. Create an app password in Settings (the same mechanism the Subsonic
   API uses; your login password never works here).
2. Point the app at your WaxDeck base URL with your username and the
   app password.

Your subscriptions are one list for the whole account, and every device
reads all of it. A device's full-list upload (the Simple API `PUT`, such
as gPodder desktop's *Replace list on server*) replaces that device's
own contribution: it adds what the device lists and removes only what no
other device and no WaxDeck app still holds, so a new device uploading
an empty list removes nothing, and neither does a list naming a feed
that cannot be fetched yet, until that feed lands or is given up. An
incremental remove, which is what AntennaPod sends when you unsubscribe
there, unsubscribes the whole account, and so does unsubscribing in
WaxDeck; a change that adds a show's new address and removes its old one
moves the app to the new one and keeps the show.

Each app is told a show by the address it knows it by: the one it last
sent or was sent, else the one you last subscribed by, never one another
account subscribed by, so a paid feed's personal link stays yours. An
app's own spelling of a show you follow stays that app's, and an app
that left a show, or was told you left it, lets go of the address it
knew, so if you follow the show again by another address it is told that
one. An app may name a show by any of those addresses, in any spelling
(`http` or `https`, a trailing slash), with no fetch. YouTube channels
you follow are not synced to podcast apps.

A feed a device adds that cannot be fetched right now, because its host
is down or answers an error, is tried again at growing intervals for a
week and joins the list when it lands, held for every device that asked
for it; until then no device sees it, and unsubscribing from the show,
in a podcast app or in WaxDeck, withdraws every device's ask for it,
including one that turns out to be the show only once fetched. While
your account cannot see the podcast library a waiting feed is not tried;
it lands once the grant is back, or is given up when its week runs out.
On a server with podcasts turned off (`-podcast-dir=""`) every add is
refused and nothing waits. An address that is not an http or https URL
naming a host is dropped as it arrives: the app is told to drop it on an
incremental upload, and nothing is said in your notifications. A feed
that cannot work as given (not a feed at all, a host that refuses or has
nothing at the address, an address on a local network this server does
not fetch from) is refused: the app is told to drop it (on an
incremental upload; a full-list upload has no answer to carry that), and
your WaxDeck notifications say why, as they do when a week of tries runs
out. A feed given up after its week is refused, not tried or parked
again, when an app asks for it in the month that follows, so a list
naming it still lets go of what it no longer names. A notification names
a feed by its host, never by its address. Each feed is said once a month
for each device that asks for it, whether or not you keep the
notification; for an upload naming many such feeds, the first few not
yet said are named and the rest counted, so each later sync names a few
more. A feed added while 200 others wait for another try is refused the
same way.

Play positions sync both ways and run through the same per-medium
reconciliation as first-party clients. Positions made in the WaxDeck
apps, and episodes marked played there, reach gpodder clients as `play`
actions from a device named `waxdeck`, for episodes whose length is
known: a play action without one is no position to a podcast app. The
server holds a show's episode links as fetched by the address of whoever
subscribed last; when that is another account's address and the show is
private, an episode is named by its guid and by its link without the
link's query or login, which carry that account's token. An
uploaded action this server cannot keep (a time it cannot read, or one
before 2000 or more than a day ahead, a field longer than it stores or
of the wrong type, a start, position or length on an action other than
`play`, a play's start or length without its position, a negative
position or one past thirty days or past the length the action gives) is
skipped and the rest of the upload stored. An action sent with no time
is stored at the time it arrives, and one sent again with its time is
kept once. Asked for the latest action of each episode, the episodes
download answers the one with the latest time, whoever uploaded last.

One upload names at most 2000 feeds (a full list, or a change's adds and
removes together) or 10,000 episode actions; a larger one is refused as
too large (HTTP 413) and changes nothing.

An account keeps up to 50 devices. A new device past that takes the
place of the one seen least recently, preferring one with no feeds of
its own; the removed device's feeds stay followed (or waiting for
another try), and your WaxDeck notifications say which device went when
it had any (by name for the first three in a day, then once that more
are going).

A login's session cookie lasts up to two weeks and ends sooner when the
app password that opened it is revoked, the app logs out, or the account
is disabled or signed out everywhere; a password change leaves it alone,
as it leaves the app password. One app password holds at most 20 logins,
and a 21st ends the oldest, one whose cookie never came back first, so
give each device its own app password rather than sharing one between
apps that log in often. The app then signs in again with its app
password on its own. A request signed with the app password itself is
answered such a cookie too, so an app that keeps cookies signs in once;
such a session renews itself once past half its two weeks while the app
keeps using it, and one app password holds 20 of these apart from its
logins, those whose cookies never came back going first.

The test suite replays both apps' syncs as their own code sends them,
against a live server on every run, so a regression there fails CI
rather than a user's sync: AntennaPod's (a login whose cookie carries
the rest, device registration, subscription changes and episode actions
in its timestamp format, a sign-out, and a sign-in again after a revoked
app password), and gPodder desktop's through its mygpoclient library
(credentials sent only when challenged, the device list and
registration, subscription pulls and changes, its replace-list upload,
and episode-action downloads and uploads, with the answers that library
requires).

## YouTube channels as shows

With the acquisition bridge enabled (`WAXDECK_YOUTUBE=true`), a
YouTube channel or playlist URL subscribes like a feed: new videos
appear as episodes and fetch as audio, stamped with their source URL
and acquisition date. The optional WaxSeal sidecar (compose profile
`youtube`) unlocks the full-quality path. SponsorBlock segment cutting
is available opt-in via `WAXDECK_YOUTUBE_SPONSORBLOCK`.

A YouTube episode plays once the server has fetched it. What the
channel lists is a video page rather than audio, so unlike a feed's
episode it does not stream before that, and the app marks it
**No audio to stream** until it is fetched.

A premiere or a stream that is still live when the channel is checked
cannot be downloaded yet, so the server remembers it and looks again on
later checks, a few at a time, and it arrives as an episode within a
few checks of its end, fetched like any new episode when automatic
download is on. One that turns out members-only, blocked in the
server's region, age-restricted or private is let go at once, and one
that never becomes downloadable 90 days after a check last saw it live.

## Audiobooks

Books are one item with chapters on a single timeline, whether they
are a chaptered m4b or a folder of parts. Progress lives on the book
timeline, so resuming on another device lands in the right chapter of
the right part. A chapter mark a file's tags place past the end of its
audio is held to where the audio ends, so every mark is somewhere there
is audio to play, and a book lasts as long as its parts' audio. The book
screen offers chapter navigation, per-book speed memory, and a sleep
timer with an end-of-chapter mode.

End of chapter stops playback at the head of the next chapter, so
pressing play picks up there, at any speed and whether or not the
chapter ends where a file does. At the end of the last chapter the book
simply stops: nothing queued after it starts under a sleeper. Seeking
past the chapter end lets the timer go. A podcast episode whose feed
publishes chapters offers the same mode, ending at those marks.

Bookmarks are places you mark on purpose, with an optional note, up to
200 a book. They work offline on the native apps: a mark made with no
connection shows **Not sent yet** and is sent when the server can be
reached again, under the same identity, so a retry never makes two, and
one removed on another device meanwhile stays removed, unless the device
was offline for over a year. A
mark the server then refuses (past the end of a book whose length was
corrected meanwhile, say) stays on the device with **Not saved** and the
reason, for you to remove. The device keeps the marks of the
books it has downloaded or opened, so the sheet reads them offline, and
each account's marks are its own even on a shared device.

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

### How a file becomes a book

The library the file sits in decides first. In a library that holds
Books, every audio file is a book, so a folder of plain MP3 parts (a
LibriVox download, a ripped CD set) needs no tagging: parts sharing an
album title and author are one book, and numbered parts with no album
tag join the book their folder holds. In a Music or Mixed library each
file is classified by its tags: it is a book when it is an `.m4b`,
carries the audiobook media type, names a narrator, or has the genre
Audiobook; Speech, Spoken Word and a composer on their own do not count.
In a Mixed library the other parts of a book its file type, media type
or narrator marks still join it; the genre marks only the file that
carries it. A
folder of untagged MP3s in a Music or Mixed library is music, so keep
audiobooks in a library of their own that holds Books (see
[adding a library](admin-and-ops.md#adding-a-library-at-runtime), or
`WAXDECK_AUDIOBOOK_ROOTS` in [configuration](configuration.md)).

A narrator added to a track does not make it a book. **Treat as
audiobook** on a track, or on an album to make its tracks one book,
changes what it is, and **Treat as music** on a book's overflow goes
back; the choice is kept through every later scan, and plays, stars
and playlist entries move with the item. Tracks folded into one book
lose their share links, which would otherwise open the whole book.
Tracks whose tags name a book the library already has join it, as
uploading them as a book would have: the book keeps whoever may edit
it, and their uploader gains nothing over it (where it sits in a
library they cannot open, the change says only that they joined
something there). An upload's media type does the same at import.

Subsonic clients list music only: books reach them through bookmarks,
so a library of MP3 audiobooks a Subsonic music client used to browse
as albums leaves its listings once it holds Books. Books play in the
WaxDeck apps. A book in parts that a Subsonic client plays from a
bookmark streams from there on through its later parts as one stream.
Without the streaming engine only a book whose parts are all MP3 at one
sample rate and one channel count does (from its start); any other plays
its first part.

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
