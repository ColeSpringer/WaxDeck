# Configuration reference

Every knob the server and the compose stack read. You do not need this
page to run WaxDeck: `make up` (or the compose snippet in the README)
starts a working stack from `deploy/.env`, and that file's few lines
are the whole day-one surface. Come here when you want to change
something beyond them.

## How configuration reaches the server

Under compose, `.env` is handed to the waxdeck container verbatim
(`env_file`), so any `WAXDECK_*` variable you set there reaches the
server as-is - adding a line to `.env` is all it takes, with no compose
editing. The exceptions are the topology variables compose sets itself
to wire the containers together (`WAXDECK_DATA_DIR`,
`WAXDECK_LIBRARY_ROOTS`, `WAXDECK_AUDIOBOOK_ROOTS`, `WAXDECK_FLOW_CONFIG`,
`WAXDECK_FLOW_API_KEY`, `WAXDECK_SEAL_API_KEY`, `WAXDECK_PODCAST_DIR`,
`WAXDECK_PODCAST_ROOT_NAME`);
those win over `.env`, because changing them would detach the server
from its own volumes and sidecars. `WAXDECK_FLOW_URL` and
`WAXDECK_SEAL_URL` stay `.env` lines on purpose: each is half of the
switch that runs its sidecar (see [What runs beside the
server](#what-runs-beside-the-server)).

Running the bare binary instead, nearly every variable below is also a
command-line flag (`WAXDECK_COOKIE_SECURE` is `-cookie-secure`, and so
on; `WAXDECK_SECRET_KEY` is environment-only). `waxdeck -h` prints the
same descriptions, and a flag beats the environment.

A switch takes `true` or `false` (`1`, `0` and capitalized spellings
work too), and a number takes whole digits. Any other value, such as
`yes` or `30m`, stops the server at startup with a line naming the
variable, rather than letting it run on the default, unless the flag
is given too. The analyzer below reads its numbers the same way.

Defaults shown are the server's own. The compose stack overrides a few
of them where the topology demands it.

## Compose-only variables

Read by compose itself, not the server. Paths resolve beside
`compose.yaml` (`deploy/` in a clone).

- `WAXDECK_MUSIC` (default `./music`) and `WAXDECK_AUDIOBOOKS` (default
  `./audiobooks`): host paths of your music and your audiobooks. Both
  are mounted read-write into the server, which manages imports and
  sidecar files there, and read-only into the engine; they are the
  roots `music` and `books`, the second an audiobook root, so a folder
  of plain MP3 parts needs no tagging. An empty folder is fine.
- `WAXDECK_UID` / `WAXDECK_GID`: the user the server and the engine run
  as, so they can write into the folders above. The example sets
  `1000`, the usual first user; `make up` sets them to the user that
  runs it. The images' own user is 10001.
- `WAXDECK_INTERNAL_KEY`: the one secret the server shares with its
  sidecars. Compose hands it to the engine as its key list, to the
  server as the key it presents, and to WaxSeal as its single tenant
  key, so the key required and the key sent cannot drift apart. Any
  long random string; `make up` generates one, and the stack refuses
  to start without it.
- `WAXDECK_SEAL_KEY`: a key of WaxSeal's own, used in place of the shared
  one for that sidecar. WaxSeal takes its key on the command line, where
  any local user can read it, so on a host with other users a separate
  key keeps the engine's key out of sight.
- `WAXDECK_ENGINE` and `WAXDECK_SEAL` (default `1`): how many of the
  engine and of WaxSeal run, `1` or `0`. See [What runs beside the
  server](#what-runs-beside-the-server).
- `WAXDECK_TAG` and `WAXFLOW_TAG` (default `latest`): image tags of the
  server and of the engine, for pinning a release
  (`WAXDECK_TAG=v1.0.0`).

## Address, data, and identity

- `WAXDECK_ADDR` (default `:4420`): listen address. Under compose the
  server shares the host's network, so the default binds the host's
  port 4420 directly.
- `WAXDECK_DATA_DIR` (default `./data`): data directory (waxbin.db +
  waxdeck.db, the secret keyfile, and by default the podcast
  downloads).
- `WAXDECK_SECRET_KEY`: hex-encoded server secret (at least 16
  bytes). Unset, the server generates a keyfile in the data dir on
  first run, which is right for almost everyone; set it only to inject
  the secret from outside (a secrets manager). Backups should exclude
  this key: an archive holding both the databases and the key is
  plaintext-equivalent for every credential it protects.
- `WAXDECK_WEB_DIR`: serve the web UI from this directory instead of
  the embedded build (dev flag; `--web-dir app/app/build/web`). A
  directory without an `index.html` refuses to start; the startup log
  says which web UI the server serves (`source=dir`, `embedded` or
  `placeholder`).
- `WAXDECK_PUBLIC_BASE`: the externally reachable base URL as browsers
  see it, e.g. `https://wax.example.com`. Required for single sign-on
  (the OIDC callback derives from it), and what notification deliveries
  build their links from: without it a delivery says what happened but
  not where, rather than pointing at a host the reader cannot resolve.
  Harmless to leave empty otherwise.
- `WAXDECK_COOKIE_SECURE` (default `false`): set `true` whenever the
  deployed origin is HTTPS so session cookies never ride cleartext.
  See [Reverse proxy](reverse-proxy.md).
- `WAXDECK_SESSION_CAP` (default `250`): how many signed-in sessions one
  account may hold at once. Signing in past it ends that account's least
  recently used session, and anything it had open with it. There is no
  "no cap": a value below 1 stops the server at startup.
- `WAXDECK_TRUSTED_PROXIES`: comma-separated CIDRs or addresses of the
  reverse proxies in front of this server. Without it the login
  limiter counts the proxy rather than the caller, so five failed
  logins from one person lock the household out. The forwarded header
  is believed only for requests that actually arrive from one of
  these, so nobody can spoof it; empty keeps the socket address, and
  an unparseable value refuses to start.
- `WAXDECK_CORS_ORIGINS`: comma-separated origins allowed to call this
  server from a browser page served somewhere else - a self-hosted
  Feishin or Airsonic web app on its own origin, talking to the
  `/rest` surface. Empty (the default) serves same-origin only, which
  is what the bundled web app needs. Write each origin exactly as the
  browser sends it: scheme, host, and port, no path. The match is
  exact; a trailing slash is tolerated and nothing else is.
  Credentials are never allowed - Subsonic authenticates per request,
  so a browser client needs no cookie, and this way a named origin
  cannot act as somebody's signed-in session.
- `WAXDECK_METRICS_TOKEN`: bearer token protecting `GET /metrics`
  (Prometheus). Unset leaves the endpoint off.

## Library

- `WAXDECK_LIBRARY_ROOTS`: library roots as `name=path` pairs, comma
  separated. Root names must match the WaxFlow roots serving the same
  directories; under compose this is pinned to
  `music=/music,books=/audiobooks`. A root
  overlapping a library added in the console is left out, with a
  warning in the log. A root set here is registered as Mixed - each
  file classified by its own tags - unless `WAXDECK_AUDIOBOOK_ROOTS`
  names it; one whose type was later changed in the console keeps that
  change. A root listed here cannot be removed from the console. One
  taken out of the list stays in the catalog under its name, no longer
  marked as configured on the Libraries screen, until it is removed
  there (see [Removing a library](admin-and-ops.md#removing-a-library)).
- `WAXDECK_AUDIOBOOK_ROOTS`: root names (comma separated) that hold
  audiobooks. Every audio file in such a root is cataloged as a book, so
  a folder of plain MP3 parts needs no tagging. The setting wins at every
  start, so a named root is put back to Books whatever set it otherwise
  (the `waxbin` CLI, or the console before the root was named); the
  console does not offer to change it. Under compose this is pinned to
  `books`, the folder `WAXDECK_AUDIOBOOKS` names.
- `WAXDECK_MANAGED_ROOTS`: root names (comma separated) the catalog
  may place files into - uploads import there and the organizer may
  move files there; unlisted roots stay strictly in place. The compose
  folders are WaxDeck-managed by design, so the example seeds
  `music,books`; set it empty to keep them strictly scan-only, or name
  only `books` if your music is managed by beets or Picard.
- `WAXDECK_SCAN_ON_START` (default `true`): launch a library scan at
  startup. A scan is incremental - files whose size and mtime are
  unchanged are skipped. The rescan action (the admin libraries
  screen, or `POST /library/rescan` with `{"force": true}`) can
  instead re-read every file: the repair pass for rows written before
  a tag-parser fix (ALAC files scanned before waxlabel 1.4.2 store a
  wrong bit depth, and only a forced rescan heals them), or after a
  library is moved off Books when another job kept that move's own scan
  from starting, so its files are classified by their tags again.
  Curated edits survive it.
- `WAXDECK_LIBRARY_WATCH` (default `true`): watch the library roots
  and catalog files placed there by hand without waiting for a rescan.
  Network mounts (NFS, SMB, 9p) rarely deliver change events; disable
  it there and enable the daily scan schedule instead.
- `WAXDECK_UPLOAD_FORMATS`: file extensions uploads accept, comma
  separated. Replaces the default set (see
  [uploads](curation-and-metadata.md)) rather than extending it; empty
  keeps the default. DRM containers (aax, aaxc) are refused regardless.
  The effective set rides the `/health` payload, so clients filter
  their pickers and drop zones against what is configured here.
- `WAXDECK_RESET_CATALOG` (default `false`): when the catalog was
  built from a different schema baseline (which pre-1.0 is edited in
  place rather than migrated), move it aside and start on a fresh one
  instead of refusing to start. Discards play positions, ratings,
  stars, playlists, curation edits, podcast subscriptions and trash;
  accounts carry over, and media on disk is untouched and re-indexed
  by the startup scan.

## Streaming engine

WaxDeck works without an engine (originals stream directly); the
engine adds transcoding, gapless timelines, voice boost, and the file
tools. Under compose the engine runs by default and the three settings
below are wired; `WAXDECK_ENGINE=0` with an empty `WAXDECK_FLOW_URL` in
`.env` runs without it.

- `WAXDECK_FLOW_URL`: WaxFlow sidecar base URL (empty serves originals
  directly: no transcoding, gapless timelines or voice boost). The
  server starts whether or not the engine answers: one that is down at
  start, or goes away later, is retried in the background while
  originals play directly, and `/health` reports `streaming.connected`.
  An engine that answers without what the server needs (one that does
  not serve progressive streams) is logged once as an error naming what
  it lacks and stays not connected; the server keeps asking it, so an
  upgraded sidecar is taken on without a restart.
- `WAXDECK_FLOW_API_KEY`: the key WaxDeck presents to the sidecar, one
  of the engine's `WAXFLOW_API_KEYS`; under compose both are
  `WAXDECK_INTERNAL_KEY`.
- `WAXDECK_FLOW_CONFIG`: the sidecar's JSON config file as WaxDeck
  sees it. One that does not exist when the server starts is written
  with the configured roots, which is how the compose stack seeds it:
  the server starts first, and the engine then reads
  `/waxflow/waxflow.json` from the volume the two share. WaxDeck owns
  the file and rewrites its roots when a library
  is created at runtime, then asks the sidecar to reload, so the new
  root streams without a restart. While the sidecar is not answering, a
  removed root still leaves the file, and a new one waits for its
  answer, since only a reload checks that the sidecar can open it.

## Single sign-on

Optional OIDC; leave the issuer empty to disable. Local accounts
always keep working. Register the redirect URI
`<WAXDECK_PUBLIC_BASE>/api/v1/auth/oidc/callback` with your identity
provider.

- `WAXDECK_OIDC_ISSUER`: issuer URL (empty disables single sign-on).
- `WAXDECK_OIDC_ID` (default `sso`): provider id shown in start URLs.
- `WAXDECK_OIDC_NAME`: provider display name for login buttons.
- `WAXDECK_OIDC_CLIENT_ID` / `WAXDECK_OIDC_CLIENT_SECRET`: the client
  registration.
- `WAXDECK_OIDC_GROUPS_CLAIM`: ID-token claim holding groups (empty
  manages roles locally).
- `WAXDECK_OIDC_ADMIN_GROUP`: members of this group (via the claim
  above) get the admin role on every login.

## Podcasts

- `WAXDECK_PODCAST_DIR`: episode download directory - its own library,
  never inside a library root. Defaults to `<data-dir>/podcasts`; an
  explicit empty (`-podcast-dir=""`, or `WAXDECK_PODCAST_DIR` set and
  empty) disables podcasts: every subscribe is refused, in the apps, an
  OPML import and podcast apps alike, and the apps hide their podcast
  entry points.
- `WAXDECK_PODCAST_ROOT_NAME` (default `podcasts`): WaxFlow root name
  the podcast dir is mounted under.
- `WAXDECK_FEED_REFRESH_MINUTES` (default `30`): minutes between
  scheduled feed refreshes.
- `WAXDECK_PODCAST_RETENTION_DEFAULT` (default `0`): keep the newest N
  downloaded episode files per show, for subscribers who leave their
  own retention unset. 0 keeps everything; the effective policy per
  show is the most generous union across its subscribers.
- `WAXDECK_PODCAST_DIRECTORY_BASE`: podcast name-search API base URL
  (empty selects the public iTunes search endpoint).
- `WAXDECK_ALLOW_PRIVATE_FEED_HOSTS` (default `false`): set `true`
  when your feeds live on the LAN (a private podcast host on your own
  network); relaxes the private-address fetch guard.
- `WAXDECK_PODPING` (default `false`): watch the Hive blockchain for
  "this feed changed" notifications, so a subscribed show whose host
  publishes them refreshes within seconds instead of at the next
  scheduled refresh. Off by default: it is a standing outbound
  connection to a third-party public node, and the schedule above
  stays the floor either way.
- `WAXDECK_PODPING_NODE`: Hive API node the watcher reads (empty picks
  a public one).
- `WAXDECK_PODPING_WRITERS`: trusted Podping writer accounts, comma
  separated. Empty (the default) resolves the published podping.cloud
  writer set from the chain, which is how it is meant to be read; a
  list here pins it instead.

## Radio, scrobbling, and notifications

- `WAXDECK_RADIO_DIRECTORY_BASE`: radio-browser directory API base URL
  (empty selects the public instance).
- `WAXDECK_LASTFM_API_KEY` / `WAXDECK_LASTFM_SECRET`: Last.fm
  scrobbling needs server API credentials - each install registers its
  own API account at last.fm/api/account/create. Without them the
  Last.fm connect button in settings stays disabled. ListenBrainz
  needs nothing here (users paste their own token).
- `WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS` (default `false`): allow
  ListenBrainz-compatible API bases on private addresses (a LAN
  Maloja).
- `WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS` (default `false`): allow radio
  stream URLs on private addresses (a LAN icecast).
- `WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS` (default `false`): allow
  user-pointed notification destinations on private addresses (a LAN
  ntfy or Gotify).

The private-address guard behind these flags and
`WAXDECK_ALLOW_PRIVATE_FEED_HOSTS` also covers carrier-grade NAT
addresses (100.64.0.0/10, where Tailscale and similar overlay networks
put their hosts), and the same flags let them in.

Feeds, episode audio, transcripts, chapters, synced playlist covers,
radio streams, ListenBrainz and user-pointed notification destinations,
while `WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS` is off, are fetched directly,
never through `HTTP_PROXY` or `HTTPS_PROXY`: the guard on each judges
the address it dials, which behind a proxy would be the proxy's. A
deployment whose only way out is a proxy loses those.

## Matching and enrichment

- `WAXDECK_MATCHING` (default `true`): identify new and uploaded music
  against MusicBrainz (paced background lookups).
- `WAXDECK_ACOUSTID_KEY`: AcoustID API key; empty disables fingerprint
  evidence in matching.
- `WAXDECK_FANARTTV_KEY`: fanart.tv API key; empty leaves that artwork
  provider unconfigured. It answers art by role, so it supplies disc art
  and artist backgrounds as well as front covers. It knows release
  groups and artists, not single pressings, so it is asked at those two
  rungs only.
- `WAXDECK_ARTIST_ART` (default `true`): fill missing artist portraits
  during the catalog's enrichment pass, which walks every artist by
  name - the ones MusicBrainz matched and the ones it did not. fanart.tv
  answers by MusicBrainz artist id where its key is set; Deezer answers
  by name. Set `false` and the providers stop advertising artist art, so
  the pass never asks either service for one.
- `WAXDECK_DISCOGS_TOKEN`: Discogs personal access token; empty leaves
  that artwork and genre provider unconfigured.
- `WAXDECK_HARDCOVER_KEY`: Hardcover API token; empty leaves that
  audiobook provider unconfigured.
- `WAXDECK_GOOGLE_BOOKS_KEY`: Google Books API key; optional - the
  provider works keyless and a key only raises the quota. Open Library
  runs keyless alongside it.
- `WAXDECK_ENRICH_PROVIDER_URLS`: custom enrichment providers as
  `name=url` pairs, comma separated, each implementing the contract in
  `docs/custom-provider-api/`. Validated at startup (the capabilities
  document must answer and advertise a name) and asked first, ahead of
  the providers WaxDeck ships; once an administrator has saved an
  order, one wired later joins its end until it is moved.
- `WAXDECK_ENRICH_PROVIDER_AUTH`: bearer tokens for custom enrichment
  providers as `name=token` pairs, comma separated; names must match
  the URLs variable.
- `WAXDECK_MUSICBRAINZ_BASE`: MusicBrainz API base override (a local
  mirror) for matching, the ISRC upgrade and radio artwork. The
  catalog's enrichment pass always asks the public service.
- `WAXDECK_COVERART_BASE`: Cover Art Archive base override (a mirror)
  for radio artwork; the archive rung only exists when matching is on.
  The enrichment pass's Cover Art Archive source always uses the public
  host.
- `WAXDECK_ENRICHMENT_CONTACT`: MusicBrainz contact (an email or a
  URL) the whole-library enrichment pass identifies itself with.
  MusicBrainz requires an identifying agent, so empty leaves the
  identity phases disabled - matching artists, release groups and books
  against MusicBrainz, and the release match below. It also gates the
  catalog's built-ins (the Cover Art Archive's album art, MusicBrainz's
  and ListenBrainz's genres, LRCLIB's lyrics): none needs a key, but the
  catalog registers them only when it has an identifying agent to dial
  with. The phases that answer to WaxDeck's own providers
  run without a contact: artist art, release-group artwork, album art
  and lyrics where a provider supplies them, and the fields walks. The
  enrichment status surface reports both halves and names the phases a
  run would execute.
- `WAXDECK_ENRICHMENT_MATCH_RELEASES` (default `true`): during
  enrichment, resolve which pressing of a record the library holds
  from its barcode or catalog number, deciding ties on medium and
  country. Needs the contact above to have any effect.
- `WAXDECK_ENRICHMENT_RETRY_MISSES_DAYS` (default `30`): days a target
  nothing answered for waits before a pass asks about it again, so a
  source that has since learned it is reached without a forced run. `0`
  never asks again, and a negative value is refused at startup. A match
  is never re-asked.

The sources are asked custom ones first, then fanart.tv, Deezer, iTunes,
Discogs, Audnexus, Hardcover, Google Books and Open Library, then the
catalog's key-free built-ins (the Cover Art Archive, MusicBrainz's
genres, ListenBrainz, LRCLIB), unless an administrator sets another
order: **Enrichment** in the admin console moves each one up or down and
switches it off, built-ins included, without a restart. A pass keeps
the list it started with; the next one takes the new order. A source
switched off opens no phase and fills nothing, and nothing records that
it was off: switched back on, it is not asked about what a pass settled
meanwhile until a run forces those phases or, for a miss, the retry
window passes. Switching off the
MusicBrainz entry leaves its genres out; the identity lookups still
run.

## YouTube

The acquisition bridge is on by default: subscribe to a channel or
playlist as a podcast, or acquire a video, playlist, or channel into a
music or audiobook library by URL (URL acquisition needs a managed
root).

- `WAXDECK_YOUTUBE` (default `true`): set `false` to disable the
  downloader entirely.
- `WAXDECK_YOUTUBE_THUMBNAIL` (default `true`): embed the source
  thumbnail as cover art on acquired audio (cropped to its square
  where the source is letterboxed release art) until enrichment finds
  official artwork.
- `WAXDECK_YOUTUBE_SPONSORBLOCK` (default `sponsor,music_offtopic`):
  SponsorBlock categories to cut from acquired audio, comma separated;
  the default drops sponsor reads and the non-music parts of a music
  video. Set it empty to keep every second.
- `WAXDECK_SEAL_URL` / `WAXDECK_SEAL_API_KEY`: the optional WaxSeal
  attestation sidecar, which unlocks the full-quality path. Under
  compose it runs by default, `WAXDECK_SEAL=1` with
  `WAXDECK_SEAL_URL=http://waxseal:4416` in `.env`, and `0` with an
  empty URL runs without it; the key is the stack's `WAXDECK_INTERNAL_KEY`
  (or `WAXDECK_SEAL_KEY` when set),
  which compose gives to the daemon as its only tenant key and to
  WaxDeck as the key it sends, so the two cannot drift apart. Without
  the URL acquisitions stay on the key-free path. The container's
  health is the image's own probe, which since WaxSeal v1.3.0 needs no
  key: it
  checks the shared browser and relaunches a dead one. An image cached
  from before that answers a keyed daemon 401 and reports unhealthy
  until `docker compose pull waxseal`; the sidecar still serves.
  Compose runs `waxseal:latest`; this release was run against WaxSeal
  1.5.0.


  The daemon keeps 12 seconds between an in-page mint and establishing
  a browser context, so the first acquisition after a sidecar restart
  can wait that long before the audio starts moving. Later ones do not:
  the separation is per context, not per request.
- `WAXDECK_SOURCE_STUB_URL`: base URL of a `sourceserv` fixture host to
  use as the acquisition source. Test stacks only - the end-to-end
  suite drives acquisition and playlist syncing against it - and never
  a production bridge: no auth, no pacing, canned audio. Leave it
  unset.

## Casting and jukebox

See [Connect and casting](connect-and-casting.md) for the network
shapes. Under compose the server shares the host's network, so
discovery works as shipped; on Docker Desktop, or with the server moved
onto Docker's network, multicast never arrives, so list devices with
the two variables below and set `WAXDECK_ADVERTISE_BASE` to the host's
LAN address.

- `WAXDECK_ADVERTISE_BASE`: plain-HTTP LAN base URL cast devices fetch
  media from (empty auto-detects the LAN address).
- `WAXDECK_CAST_DISCOVERY` (default `true`): discover Chromecast and
  DLNA devices on the LAN (mDNS and SSDP).
- `WAXDECK_CAST_DEVICES`: static cast devices as `name=host:port`
  pairs, comma separated (networks without multicast).
- `WAXDECK_DLNA_DEVICES`: static DLNA renderer description URLs, comma
  separated.
- `WAXDECK_JUKEBOX` (default `false`): play out the server's own audio
  device as a selectable endpoint (needs the streaming engine, and
  under compose a `/dev/snd` device mount).
- `WAXDECK_JUKEBOX_CMD`: player command the jukebox pipes WAV into
  (default `aplay`; PipeWire hosts use `pw-cat -p -`).
- `WAXDECK_JUKEBOX_NAME` (default `Server audio`): display name of the
  jukebox endpoint.

## Sonic similarity

See [the similarity worker](similarity-worker.md) for the offloading
architecture.

- `WAXDECK_SONIC_ANALYSIS` (default `true`): boot default for
  background analysis with the embedded analyzer (powers instant
  mixes, similar tracks, and sonic paths). Administrators toggle it at
  runtime in the server settings; this is only the default before that
  setting is first saved.
- `WAXDECK_WORKER_TOKENS`: tokens the server accepts from external
  analysis workers, comma separated; empty disables the worker API.
  Pair a worker with
  `WAXDECK_SONIC_ANALYSIS=false` when the server should stop analyzing
  itself.
- `WAXDECK_WORKER_LOCAL_PATHS` (default `false`): expose
  library-relative source paths in work items, so a same-host worker
  with the library mounted read-only decodes locally instead of
  pulling audio over HTTP.

The `waxdeck-analyzer` binary (a release artifact, run on the other
machine as [the similarity worker](similarity-worker.md) shows) reads
its own variables:

- `WAXDECK_ANALYZER_URL`: the WaxDeck server to pull work from.
- `WAXDECK_ANALYZER_TOKEN`: one of the server's worker tokens,
  presented verbatim.
- `WAXDECK_ANALYZER_FORMAT` (default `wav`): transfer format; `flac`
  halves the bytes on the wire, `wav` needs no worker-side decode.
- `WAXDECK_ANALYZER_LIBRARY`: local library mount for the local-paths
  mode above.
- `WAXDECK_ANALYZER_POLL_SECONDS` (default `60`): idle sleep between
  polls when the server suggests none.
- `WAXDECK_ANALYZER_BATCH` (default `10`): work items leased and
  posted per cycle (1 to 50).

## What runs beside the server

Two optional parts, both on by default, each a `1`/`0` count in `.env`
plus the address the server reaches it at. Change both, then
`docker compose up -d` (`make up` from a clone, which also passes the
dev tags and your uid): a part at `0` has no container at all, and a
URL left behind points the server at a sidecar that is gone (a standing
warning for the engine, degraded acquisitions for WaxSeal). Both bind
the host's loopback on the host network, so the stack publishes no
port anywhere; the server reaches them through `extra_hosts`.

- The streaming engine: `WAXDECK_ENGINE=1` with
  `WAXDECK_FLOW_URL=http://waxflow:4418`. Without it originals play
  directly.
- WaxSeal, full-quality YouTube through a headless browser:
  `WAXDECK_SEAL=1` with `WAXDECK_SEAL_URL=http://waxseal:4416`.

Sonic analysis is the server's own (`WAXDECK_SONIC_ANALYSIS` and the
switch in the server settings); the worker binary is for another machine.
