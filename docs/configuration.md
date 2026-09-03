# Configuration reference

Every knob the server and the compose stack read. You do not need this
page to run WaxDeck: `make up` (or the compose snippet in the README)
starts a working stack from `deploy/.env`, and that file's few lines
are the whole day-one surface. Come here when you want to change
something beyond them.

## How configuration reaches the server

Under compose, `deploy/.env` is handed to the waxdeck container
verbatim (`env_file`), so any `WAXDECK_*` variable you set there
reaches the server as-is - adding a line to `.env` is all it takes,
with no compose editing. The exceptions are the topology variables
compose sets itself to wire the containers together
(`WAXDECK_ADDR`, `WAXDECK_DATA_DIR`, `WAXDECK_LIBRARY_ROOTS`,
`WAXDECK_FLOW_URL`, `WAXDECK_FLOW_CONFIG`, `WAXDECK_PODCAST_DIR`,
`WAXDECK_PODCAST_ROOT_NAME`); those win over `.env`, because changing
them would detach the server from its own volumes and sidecar.

Running the bare binary instead, nearly every variable below is also a
command-line flag (`WAXDECK_COOKIE_SECURE` is `-cookie-secure`, and so
on; `WAXDECK_SECRET_KEY` is environment-only). `waxdeck -h` prints the
same descriptions, and a flag beats the environment.

Defaults shown are the server's own. The compose stack overrides a few
of them where the topology demands it.

## Compose-only variables

Read by compose itself, not the server.

- `WAXDECK_LIBRARY` (default `./library`, resolved beside
  `compose.yaml`): host path of your music library. WaxDeck mounts it
  read-write (it manages imports and sidecars); WaxFlow mounts the
  same path read-only.
- `WAXDECK_UID` / `WAXDECK_GID` (default `10001`): the user the
  containers run as, so they can write into the library above. `make
  up` sets them to the user that runs it; for a bare `docker compose
  up`, set them to the owner of `WAXDECK_LIBRARY`, or leave the image
  default and make the library writable by uid 10001.
- `WAXDECK_TAG` (default `latest`): image tag of the stack, for
  pinning a release (`WAXDECK_TAG=v1.0.0`).
- `WAXFLOW_API_KEYS`: API keys the WaxFlow sidecar accepts, comma
  separated; generate each with `openssl rand -hex 24`. `make up`
  seeds one. `WAXDECK_FLOW_API_KEY` must be one of these values.
- The optional WaxSeal sidecar takes no key list of its own: compose
  hands it `WAXDECK_SEAL_API_KEY` (see YouTube below) as its single
  tenant key, so the key the daemon requires and the key WaxDeck sends
  cannot drift apart. It reaches the daemon as a `--tenant-keys` flag
  rather than an environment variable, which is why compose spells the
  sidecar's whole command out. Left empty the sidecar runs keyless: it
  accepts any key, including none, from anything that can reach the
  internal network.

## Address, data, and identity

- `WAXDECK_ADDR` (default `:4420`): listen address. The one published
  port of the compose stack.
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
  the embedded build (dev flag; `--web-dir app/app/build/web`).
- `WAXDECK_PUBLIC_BASE`: the externally reachable base URL as browsers
  see it, e.g. `https://wax.example.com`. Required for single sign-on
  (the OIDC callback derives from it); harmless to leave empty
  otherwise.
- `WAXDECK_COOKIE_SECURE` (default `false`): set `true` whenever the
  deployed origin is HTTPS so session cookies never ride cleartext.
  See [Reverse proxy](reverse-proxy.md).
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
  directories; under compose this is pinned to `lib=/library`.
- `WAXDECK_MANAGED_ROOTS`: root names (comma separated) the catalog
  may place files into - uploads import there and the organizer may
  move files there; unlisted roots stay strictly in place. The compose
  library is WaxDeck-managed by design, so `deploy/.env` seeds `lib`;
  set it empty to keep the library strictly scan-only, or point it at
  a separate root if your main library is managed by beets or Picard.
- `WAXDECK_SCAN_ON_START` (default `true`): launch a library scan at
  startup. A scan is incremental - files whose size and mtime are
  unchanged are skipped. The rescan action (the admin libraries
  screen, or `POST /library/rescan` with `{"force": true}`) can
  instead re-read every file: the repair pass for rows written before
  a tag-parser fix (ALAC files scanned before waxlabel 1.4.2 store a
  wrong bit depth, and only a forced rescan heals them). Curated
  edits survive it.
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
  media on disk is untouched and re-indexed by the startup scan.

## Streaming engine

WaxDeck works without an engine (originals stream directly); the
engine adds transcoding, gapless timelines, and voice boost. Under
compose all three of these are wired for you.

- `WAXDECK_FLOW_URL`: WaxFlow sidecar base URL (empty disables
  streaming through the engine).
- `WAXDECK_FLOW_API_KEY`: the key WaxDeck presents to the sidecar;
  must be one of the values in `WAXFLOW_API_KEYS`.
- `WAXDECK_FLOW_CONFIG`: the sidecar's JSON config file as WaxDeck
  sees it. WaxDeck owns the file and rewrites its roots when a library
  is created at runtime, then asks the sidecar to reload, so the new
  root streams without a restart.

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
  explicit empty (`-podcast-dir=""`) disables podcasts.
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

## Matching and enrichment

- `WAXDECK_MATCHING` (default `true`): identify new and uploaded music
  against MusicBrainz (paced background lookups).
- `WAXDECK_ACOUSTID_KEY`: AcoustID API key; empty disables fingerprint
  evidence in matching.
- `WAXDECK_FANARTTV_KEY`: fanart.tv API key; empty leaves that artwork
  provider unconfigured. It is the only provider that answers art by
  role, so it supplies disc art and artist backgrounds as well as front
  covers, and it is registered ahead of the others because the
  enrichment engine stops asking once every slot is held.
- `WAXDECK_ARTIST_ART` (default `true`): fill missing artist portraits.
  Artists MusicBrainz matched are filled by the catalog's own
  enrichment pass, from fanart.tv when its key is set (keyed on the
  MusicBrainz artist id) and from Deezer otherwise; the artists that
  pass cannot reach, which are the ones with no MusicBrainz id, are
  filled by a daily background sweep asking Deezer by name. Set `false`
  and the server never asks either service for a portrait on either
  path.
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
  document must answer and advertise a name) and registered ahead of
  every built-in provider.
- `WAXDECK_ENRICH_PROVIDER_AUTH`: bearer tokens for custom enrichment
  providers as `name=token` pairs, comma separated; names must match
  the URLs variable.
- `WAXDECK_MUSICBRAINZ_BASE`: MusicBrainz API base override (a local
  mirror).
- `WAXDECK_COVERART_BASE`: Cover Art Archive base override (a mirror);
  the archive rung only exists when matching is on.
- `WAXDECK_ENRICHMENT_CONTACT`: MusicBrainz contact (an email or a
  URL) the whole-library enrichment pass identifies itself with.
  MusicBrainz requires an identifying agent, so empty leaves that pass
  disabled.
- `WAXDECK_ENRICHMENT_MATCH_RELEASES` (default `true`): during
  enrichment, resolve which pressing of a record the library holds
  from its barcode or catalog number, deciding ties on medium and
  country. Needs the contact above to have any effect.

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
- `WAXDECK_YOUTUBE_SPONSORBLOCK`: SponsorBlock categories to cut from
  acquired audio, comma separated (for example `sponsor,selfpromo`).
  Empty disables cutting.
- `WAXDECK_SEAL_URL` / `WAXDECK_SEAL_API_KEY`: the optional WaxSeal
  attestation sidecar, which unlocks the full-quality path. Under
  compose: start it with `--profile youtube` and uncomment
  `WAXDECK_SEAL_URL=http://waxseal:4416` in `deploy/.env`. Without that
  URL the sidecar runs and is never contacted, and acquisitions stay on
  the key-free path. `WAXDECK_SEAL_API_KEY` is the whole key story -
  `make up` mints one, compose gives it to the daemon as its only
  tenant key and to WaxDeck as the key it sends, and the sidecar's
  health check pings with it, so a container that goes healthy is one
  this server can actually mint against.


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
shapes; under compose, discovery needs the `cast` profile's
host-network instance because multicast never crosses the bridge.

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
  `make up` seeds one. Pair a worker with
  `WAXDECK_SONIC_ANALYSIS=false` when the server should stop analyzing
  itself.
- `WAXDECK_WORKER_LOCAL_PATHS` (default `false`): expose
  library-relative source paths in work items, so a same-host worker
  with the library mounted read-only decodes locally instead of
  pulling audio over HTTP.

The bundled worker (`--profile similarity`, or the standalone
`waxdeck-analyzer` binary) reads its own variables:

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

## Compose profiles

Optional services, started by name:

- `docker compose --profile youtube up -d`: the WaxSeal sidecar
  (full-quality YouTube).
- `docker compose --profile similarity up -d`: the bundled analysis
  worker.
- `docker compose --profile cast up -d`: a second waxdeck on host
  networking that can discover cast devices.

(`make up` reads `COMPOSE_PROFILES` from your environment, so
`COMPOSE_PROFILES=similarity make up` works too.)
