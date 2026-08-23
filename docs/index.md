<p align="center">
  <img src="brand/lockup-640.png" width="360" alt="WaxDeck: a candle burning against a record">
</p>

# WaxDeck

WaxDeck is a self-hosted player, library manager, and metadata
completer for music, podcasts, and audiobooks. One server, one origin:
the REST API, the streaming surface, the web app, and the
compatibility APIs all live on port 4420.

Start with [Getting started](getting-started.md), which covers the
Docker Compose stack and the fast single-binary path.

## The guides

- [Getting started](getting-started.md): run the stack, point it at
  your library, first login.
- [Configuration reference](configuration.md): every knob the server
  and the compose stack read, and how a setting reaches the server.
- [Curation and metadata](curation-and-metadata.md): the matching
  engine, the review queue, the editor, the genre vocabulary, uploads,
  and acquiring from URLs.
- [Podcasts and audiobooks](podcasts-and-audiobooks.md): per-user
  subscriptions, episode fetching, chapters, and resume.
- [Playlists, radio, and integrations](playlists-radio-and-integrations.md):
  manual and smart playlists, internet radio, scrobbling, and the
  compatibility APIs third-party apps use.
- [Discovery and listening stats](discovery-and-stats.md): instant
  mixes, similar tracks, sonic paths, dashboards, and the year in
  review.
- [Public share links](sharing.md): share a track, playlist, book, or
  episode with anyone, no account needed.
- [The similarity worker](similarity-worker.md): the optional analysis
  container behind sonic discovery, and the worker contract.
- [Connect and casting](connect-and-casting.md): multi-device control,
  handoff, Chromecast, DLNA, and the jukebox.
- [Admin and ops](admin-and-ops.md): users and permissions, backups
  and restore, scheduled jobs, the audit log, and migration from
  other servers.
- [Reverse proxy guide](reverse-proxy.md): TLS in front, WebSockets,
  streaming, and the settings that matter.
