# Getting started

WaxDeck is a self-hosted player and library manager for music,
podcasts, and audiobooks. One server, one origin: the REST API, the
streaming surface, and the web UI all listen on port 4420.

## Run with Docker Compose

```sh
cd deploy
cp .env.example .env    # set the API keys it names
docker compose up -d
```

Put audio files under the library directory (`./library` by default,
override with `WAXDECK_LIBRARY` in `.env`) and open
`http://localhost:4420`. The server scans the library at startup; use
the rescan endpoint or restart after adding files.

The stack is two services. `waxdeck` owns the catalog, the API, and the
web UI, and is the only published port. `waxflow` is the streaming
engine (WaxDeck's own build of the WaxFlow engine, and an optional
upgrade rather than a requirement; see below); it lives on the
internal network and every stream is proxied through the WaxDeck
origin, so clients, cast devices, and reverse proxies only ever need to
reach one address.

## Run from source

```sh
make web build     # Flutter web UI + server binary with it embedded
WAXDECK_LIBRARY_ROOTS=lib=/path/to/music \
./server/waxdeck
```

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
