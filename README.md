<p align="center">
  <img src="docs/brand/lockup-640.png" width="360" alt="WaxDeck: a candle burning against a record">
</p>

# WaxDeck

Self-hosted player, library manager, and metadata completer for music,
podcasts, and audiobooks. One server, one origin: the REST API, the
streaming surface, the web app, and the compatibility APIs all live on
port 4420.

- Metadata completion: a matching engine, a review queue, and a full
  editor. New audio arrives by upload or straight from a URL.
- Podcasts and audiobooks are first-class: subscriptions, chapters,
  and resume are per-user and follow you across devices.
- Manual and smart playlists, internet radio, and scrobbling.
- Sonic discovery from analysis of your own files: instant mixes,
  similar tracks, sonic paths, and listening stats.
- Multi-device control and handoff, Chromecast, DLNA, and a jukebox.
- Public share links: hand anyone a track, playlist, book, or episode,
  no account needed.
- Subsonic and gpodder compatibility, so the apps you already use keep
  working.
- Accounts with per-library visibility and optional OIDC single
  sign-on; scheduled backups, an audit log, and migration from
  Navidrome or Audiobookshelf.

## Run it

```sh
git clone https://github.com/ColeSpringer/WaxDeck.git && cd WaxDeck
make up
```

The first run writes `deploy/.env`; point `WAXDECK_LIBRARY` in it at
your music and `make up` again. Open http://localhost:4420 and create
the administrator. `make down` stops the stack and keeps your data;
your library is bind-mounted, never copied.

Without Docker, `make run` (Go 1.26, Flutter 3.44) serves the same
thing as a single binary with the web UI embedded: originals stream
directly, and transcoding, gapless playback, and voice boost arrive
when you add the streaming engine.
[Getting started](docs/getting-started.md) covers both paths end to
end.

To run compose directly rather than through `make up`:

```sh
cd deploy && cp .env.example .env   # edit paths and keys
mkdir -p waxflow-config && cp waxflow-config.example.json waxflow-config/waxflow.json
docker compose up -d
```

## Clients

The web app ships inside the server. The same Flutter app builds for
Android, Linux, and Windows from `app/`, and any Subsonic client or
gpodder podcast app can connect to the compatibility APIs.

On Android, add the F-Droid repository and each release arrives as an
update (the fingerprint is part of the address):

```
https://colespringer.github.io/WaxDeck/repo?fingerprint=18BB5776333A744A3C0519BF9C019C09C745E0FFE5207AF5BF8F4D054D9CBE35
```

## Documentation

[docs/](docs/index.md) holds the guides: getting started, curation and
metadata, podcasts and audiobooks, playlists and integrations,
discovery, sharing, casting, administration, and running behind a
reverse proxy.

## Developing

`make generate` regenerates everything from the API contract and
`make lint test` is the gate on every change; the workflow lives in
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-only (see [LICENSE](LICENSE)). Contributions are accepted
under the project license with no CLA; see
[CONTRIBUTING.md](CONTRIBUTING.md).
