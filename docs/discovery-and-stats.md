# Discovery and listening stats

This page covers sonic discovery (similar tracks, instant mixes,
sonic paths), the listening statistics dashboards, and the year in
review.

## Discovery works with zero setup

Every discovery surface has a metadata baseline that needs nothing
beyond your library: instant mixes and similar-tracks lists blend the
seed's genre and artist neighborhoods with a slice of the wider
catalog. Responses carry a `basis` field (`metadata` or `sonic`) so
clients can tell which engine answered.

As the server's background analysis works through the library (on by
default; see [sonic analysis](similarity-worker.md)), the same
surfaces upgrade to sonic answers: every analyzed track carries an
audio embedding, similarity is measured on the sound itself, and two
extra things become possible that metadata cannot do at all: the
adventurousness knob gets real teeth, and sonic paths exist.

## Instant mixes

`POST /api/v1/mixes/instant` builds a mix from a seed: a track pid, an
artist pid, an album pid, or a genre name. An album seed anchors on its
own tracks, addressed by entity identity rather than a display-string
match. In the apps it is the "Instant mix" action on the playing track,
the item menus on track rows, the artist and genre cards on home, and
the album screen's overflow and album rows, which seed by the album pid.

The `adventurousness` knob (0 to 1) controls how far the mix wanders.
At 0 a sonic mix hugs the seed's closest neighbors; at 1 it samples
far into the neighborhood. On the metadata baseline the knob loosens
the genre bound instead, mixing in more of the wider catalog.

Mixes are computed fresh per request and never persisted. For endless
radio, request another mix and pass what already played in
`excludePids`. The response's `excluded` count says how many candidates
that list dropped, which is what tells an empty mix whose candidates
are all queued apart from a seed with none at all. The apps exclude
only the current track and what is still coming, so played history is
mixable again.

## Similar tracks

`GET /api/v1/items/{pid}/similar` answers tracks similar to a seed
track, most similar first. Sonic when the seed has an embedding, the
metadata baseline otherwise. The seed itself is never in the list.

## Sonic paths

`GET /api/v1/mixes/path?from=&to=` builds a listening path between two
tracks: each hop moves along precomputed nearest-neighbor edges, so
the sequence drifts gradually from the first track's sound to the
second's. Paths are the one surface with no metadata fallback; both
endpoints need embeddings, and without them the request answers
`feature-unavailable`.

Path queries never scan vectors. When the worker posts an embedding,
the server also computes that track's top nearest neighbors into a
graph, and pathfinding is plain traversal over those precomputed
edges. The graph maintains itself incrementally at ingest; deletions
prune edges and lazily repair only the affected nodes.

## Third-party clients

The Subsonic surface serves `getSimilarSongs` and `getSimilarSongs2`
(metadata fallback included, so they always answer), and advertises
the `sonicSimilarity` OpenSubsonic extension with two views:
`getSonicSimilarTracks` (empty rather than a metadata guess when the
seed has no embedding) and `findSonicPath` (`fromId`, `toId`,
optional `length`).

## Listening stats

Every client reports listen sessions with idempotency ids, so plays
are deduplicated across devices and offline replays never
double-count. Radio is the exception, and the reason is that nothing
on a listener's end knows it is playing something the stats can name:
the server's own stream proxy measures a tune-in while it relays it,
checkpointing as it goes so a long listen survives a restart. One row
per connection, so reconnecting counts as a second session while the
time stays right. The stats surface aggregates all of it:

- `GET /api/v1/stats/listening` - listening time over a range (7d to
  all time), bucketed by day, week, or month for charts, split by
  media type, with the time-saved counter (what silence trimming and
  faster playback saved you, as reported by clients).
- `GET /api/v1/stats/heatmap` - a calendar year of per-day listening
  plus streaks. The current streak counts runs ending today or
  yesterday, and streaks cross year boundaries honestly.
- `GET /api/v1/stats/top` - top artists, albums, genres, shows, or
  stations by listening time over a range. Music kinds count only music
  sessions, shows only podcast sessions, and stations only radio, so
  spoken-word hours never drown a music chart.
- `GET /api/v1/stats/sessions` - the raw session log, newest first,
  with the reporting client, so "what played on which device when" is
  answerable. Filter by client label.

All calendar bucketing happens in your preferred timezone (the
`timezone` preference; UTC when unset). Sessions store UTC and the
server does the calendar math per user, so a midnight-crossing session
lands on the right day for you, not for the server.

## Year in review

`GET /api/v1/stats/year-in-review` is your listening recap for any
calendar year: totals, the month-by-month shape, top artists, tracks,
genres, and shows, the longest streak, the time-saved counter, and
how much joined the library that year. It is always available and
always current (rolling stats, not a December-only event); ask for
any year with data.

`GET /api/v1/stats/server-year-in-review` is the same recap for the
whole server, aggregated across users. Participation is opt-out: the
`sharedStatsOptOut` preference removes your listening from every
server-wide figure while leaving your personal stats untouched. Each
participant's sessions are bucketed in their own timezone.
