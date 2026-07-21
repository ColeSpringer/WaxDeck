# Getting started

WaxDeck is a self-hosted player and library manager for music,
podcasts, and audiobooks. One server, one origin: the REST API, the
streaming surface, and the web UI all listen on port 4420.

There are two ways to run it. **`make up`** brings up the full,
realistic instance in Docker (the server plus the streaming engine),
and is the one to use for actual testing. **`make run`** is a faster
single-binary path for iterating on the app; it has no streaming
engine. Everything below the "Run with Docker Compose" section covers
`make run`.

## Run with Docker Compose

```sh
make up      # builds the images, generates deploy/.env, starts the stack
make logs    # follow the logs
make down    # stop it
```

`make up` writes `deploy/.env` with fresh internal keys on the first
run. Set `WAXDECK_LIBRARY` in it to point at your music (it defaults to
an empty `deploy/library`), then `make up` again. Open
`http://localhost:4420`; the server scans the library at startup, so
use the rescan endpoint or restart after adding files. Uploads and
YouTube downloads are enabled and land in the library out of the box.

The stack is two services. `waxdeck` owns the catalog, the API, and the
web UI, and is the only published port. `waxflow` is the streaming
engine (WaxDeck's own build of the WaxFlow engine, an optional upgrade
rather than a requirement; see below); it lives on the internal network
and every stream is proxied through the WaxDeck origin, so clients, cast
devices, and reverse proxies only ever need to reach one address.

(The underlying command is `docker compose -f deploy/compose.yaml up`;
`make up` just wraps it with the key generation.)

## Run from source

```sh
make run       # embeds the UI and serves on :4420
```

`make run` sources a gitignored `.env` in the repo root, so put your
config there once instead of retyping it:

```sh
# .env
WAXDECK_LIBRARY_ROOTS=lib=/path/to/music
WAXDECK_MANAGED_ROOTS=lib
```

It rebuilds the embedded web UI whenever the Dart sources changed, so
it never serves a stale build. (You can also run the binary directly
with the same env: `WAXDECK_LIBRARY_ROOTS=lib=/path ./server/waxdeck`
after `make web build`.)

That alone plays: without a streaming engine configured, WaxDeck
serves your original files directly (ranged and seekable, no
transcoding), and tracks carved out of single-file rips by cue sheets
still play as themselves in the first-party apps. What you give up is
transcoding for constrained networks and picky clients, gapless
timelines, and voice boost; on the web, playable formats are whatever
the browser decodes. To add all of that, run the bundled engine and
point the server at it, with the same root names on both sides:

```sh
cd server && go build -o waxflow-catalog ./cmd/waxflow-catalog
WAXFLOW_ADDR=127.0.0.1:4418 \
WAXFLOW_ROOTS=lib=/path/to/music \
WAXFLOW_API_KEYS=devkey \
./waxflow-catalog server
```

```sh
WAXDECK_LIBRARY_ROOTS=lib=/path/to/music \
WAXDECK_FLOW_URL=http://127.0.0.1:4418 \
WAXDECK_FLOW_API_KEY=devkey \
./server/waxdeck
```

## What works today

- Library scan of the configured roots (FLAC, MP3, Opus, Vorbis, AAC,
  ALAC, WAV, AIFF, and more), with rescan at
  `POST /api/v1/library/rescan`.
- Browse, discovery lists, and full-text search over the catalog.
- Playback in the web UI and over the API: play-info returns a
  short-lived tokenized stream URL playable by bare audio elements.
- Resume: playback positions checkpoint to the server, so a killed
  client picks up where it left off on any device.
- Listen accounting: clients report listen sessions with idempotency
  IDs, so offline replays never double-count.
- Real accounts: argon2id passwords, per-device sessions with remote
  sign-out, admin and user roles, per-library visibility, per-user
  stars, ratings, resume positions, and preferences.
- OIDC single sign-on (optional): configure an issuer and every form
  factor logs in through one server-registered redirect URI.

## First run

A fresh server has no accounts. Open the web UI (or call
`POST /api/v1/auth/bootstrap`) and create the first administrator;
the setup door closes permanently once any account exists. Further
accounts are created from the admin API. If the server is reached
over HTTPS, set `WAXDECK_COOKIE_SECURE=true`.

To enable single sign-on, set `WAXDECK_PUBLIC_BASE` and the
`WAXDECK_OIDC_*` variables (see `deploy/.env.example`) and register
`<public base>/api/v1/auth/oidc/callback` with the identity provider.
Local accounts keep working alongside; group-based role mapping is
available via `WAXDECK_OIDC_GROUPS_CLAIM` and
`WAXDECK_OIDC_ADMIN_GROUP`.

## Uploads and acquiring from YouTube

WaxDeck can bring new audio into the library two ways, both of which
land the files in the review queue (see `docs/curation-and-metadata.md`):
uploading them from a client, and acquiring them from a URL (a single
YouTube video, or a whole playlist or channel).

One thing has to be configured: **a managed library root.** Both paths
place files into the library, and WaxDeck never moves files into a
library it only scans, so mark at least one root managed. Managed
roots are named (by the same names as `WAXDECK_LIBRARY_ROOTS`) in
`WAXDECK_MANAGED_ROOTS`. Leave your existing beets- or Picard-managed
library out of it; use a separate root for imported audio.

The YouTube downloader is on by default (it embeds WaxTap; no external
tools). Disable it with `WAXDECK_YOUTUBE=false`.

```sh
WAXDECK_LIBRARY_ROOTS=music=/path/to/music \
WAXDECK_MANAGED_ROOTS=music \
./server/waxdeck
```

Then, in the web UI, the **+** button on the library adds audio: **Add
from URL** acquires from a video, playlist, or channel, and **Upload a
file** sends one from your device. The button uses the media type of
the section you are in (Music, Audiobooks), and podcasts are added by
subscribing to a feed instead. The **Uploads** screen (under the
curation menu) lists in-progress and past sessions. Either way the
download runs as a background task: the files arrive with the source's
own title, thumbnail, and provenance tags, cluster into album units,
and wait in the review queue where you approve a match, keep them as
is, or mark them unofficial (for remixes and rips with no canonical
release). A user with upload rights keeps editing rights over what
their own uploads and acquisitions bring in, so hand-naming an
unofficial track does not need an administrator.

By default an acquisition keeps the source's highest-quality audio with
no re-encode (Opus, in practice, for YouTube), delivered in a clean,
tag-and-cover-capable container, with the source thumbnail embedded as
cover art until enrichment finds official artwork. The **Add from URL**
dialog also offers a format choice (Best, Opus, M4A, MP3, FLAC) for
device compatibility; the others transcode, at some quality cost from a
lossy source. Embedded thumbnails can be turned off server-wide with
`WAXDECK_YOUTUBE_THUMBNAIL=false`.

Uploading also works from the API directly:
`POST /uploads` to open a session, `PUT /uploads/{id}/data` for each
chunk, `POST /uploads/{id}/complete`; acquisitions are one call,
`POST /acquisitions` with a `url` and `mediaType` (and an optional
`format`).

## Useful endpoints

Everything lives under `/api/v1` (see `api/openapi.yaml` for the full
contract):

| Endpoint | What it does |
| --- | --- |
| `POST /auth/bootstrap` | Create the first administrator (one shot) |
| `POST /auth/login` | Establish a session (cookie plus bearer token) |
| `GET /auth/sessions` | List sessions and devices; DELETE one to sign it out |
| `GET /users` | Account administration (admin) |
| `GET/PUT /users/me/prefs` | Per-user preferences (timezone, locale, theme) |
| `GET /library/items` | Page the library (`mediaType`, `cursor`, `limit`) |
| `GET /library/browse?list=recently-added` | Discovery lists |
| `GET /library/search?q=` | Grouped full-text search |
| `GET /items/{pid}/play-info` | Resolve a playable stream URL |
| `GET/PUT /items/{pid}/play-state` | Resume position |
| `PUT /items/{pid}/star` | Star or unstar an item |
| `PUT /items/{pid}/rating` | Rate an item (0 to 100, null clears) |
| `POST /listens` | Report listen sessions |
| `POST /library/rescan` | Start a scan; poll `GET /jobs/{pid}` (admin) |
| `POST /uploads` | Open a resumable upload session |
| `POST /acquisitions` | Acquire audio from a URL (YouTube; on by default) |
| `GET /review/queue` | The metadata review queue |
| `GET /tools/tasks/{id}` | Follow a background acquire, merge, or split task |

## Maintenance and the waxbin CLI

The server owns the catalog's write lock for its whole lifetime, and it
serves a local IPC socket (`waxbin.sock` in the data directory) that
the standalone `waxbin` CLI discovers automatically: CLI mutations and
long jobs proxy through the running server. Operations that need the
lock itself (rebuild, restore) put the server into a maintenance mode:
already-playing streams keep flowing, authentication and settings stay
live, and catalog reads answer with a typed `catalog-maintenance`
error until the hand-off ends. The socket is a local admin plane,
created 0600 for the server's own user.
