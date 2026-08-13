# waxdeck_api_gen (EXPERIMENTAL)
First-party REST API for WaxDeck: the self-hosted player, library manager,
and metadata completer for music, podcasts, and audiobooks.

Current scope: health, accounts and sessions (local passwords and OIDC),
user administration with roles and per-library visibility, per-user
preferences, library browse and search, item detail, artwork, lyrics,
play-info, playback state (resume, stars, ratings), listen session
ingest, library scanning, delta sync for offline-first clients (with
the WebSocket event channel specified in `api/events.md`; its frame
payloads are components in this document), offline downloads of
original files, app passwords for the compatibility APIs, podcasts
(per-user subscriptions over globally cataloged shows, episode
browsing with sanitized show notes, transcripts, OPML round trips,
server-side episode fetching, and YouTube channels as shows),
audiobooks (book detail with chapters and parts, chapter-aware
resume, per-book playback settings), silence skip maps for
client-side trimming, playlists (manual ordered lists and smart
playlists whose rules are evaluated per user on read, with a rule
preview and a field discovery endpoint for rule editors, plus M3U8
round trips), internet radio stations (a shared station library
with directory search), outbound scrobbling connections (Last.fm
and ListenBrainz per user, delivered from a durable server-side
queue), notification targets in two scopes (administrator-managed
server destinations for operations events and per-user personal
destinations with per-target event selection, delivering natively
to Pushover, ntfy, Gotify, Discord webhooks, generic webhooks, an
Apprise relay, and UnifiedPush endpoints), and multi-device
playback control (player endpoints,
playback sessions with server-side queues, transfer between
endpoints, gapless queue timelines through the streaming engine,
and cast preflight diagnostics; the live command bus rides the
WebSocket channel in `api/events.md`), and the curation surface:
the release matching review queue (scored candidates with
per-field distance breakdowns, approve, skip, keep-as-is, mark
unofficial, bulk decisions, revert, and calibration statistics),
resumable chunked uploads that flow through the same identify and
review pipeline, the full-depth metadata editor (every scalar
field, credits, lyrics, chapters, artwork, custom tags, entity
edits, field locks with provenance, database-first writes with
per-call file write-back), the metadata health dashboard with
bulk fixes, duplicate merge and quality upgrade resolution, the
template file organizer with dry-run previews, audiobook merge
and split tooling with chapter stamping and progress remapping,
CUE rip splitting, and library enrichment status and dispatch,
and the administration surface: granular per-account permissions
with tag allow and deny lists, self-serve signup requests with
admin approval and invite links, the admin-action audit log,
scheduled scans, backups, and pruning (cron expressions), backup
archives with staged restore, the deletion surface and the trash
(list, restore, empty), read-only library mode, transcoding
limits, and the migration assistant that imports listening state
from other servers, and the discovery and stats surface: sonic
similarity over per-track audio embeddings (computed by an
optional external analysis worker speaking the worker API in
this document), similar tracks, instant mixes from any seed
with an adventurousness knob, sonic paths between two tracks,
listening statistics (time by period, calendar heatmaps with
streaks, top lists, the per-device session log, a time-saved
counter), a per-user and server-wide year in review, public
share links whose landing pages are server-rendered plain HTML,
and streaming-service playlist import with a missing-tracks
report plus portable playlist export for exchange between
catalogs. The shapes (keyset pagination, typed PIDs,
the structured error model, relative media URLs) are load-bearing
from day one.

Conventions:
- All endpoints live under `/api/v1` (this document's `servers` entry).
- Identifiers (`pid`) are type-prefixed ULIDs (`tr-` track, `al-` album,
  `ar-` artist, `pc-` podcast, `ep-` episode, `bk-` audiobook, `jb-` job,
  `lb-` library, `us-` user, `se-` session, `ap-` app password,
  `pl-` playlist, `rs-` radio station, `nt-` notification target,
  `pe-` player endpoint, `ps-` playback session, `rv-` review
  entry, `up-` upload, `tk-` tool task, `iv-` invite, `bu-` backup
  archive, `th-` trash entry, `sh-` share link).
- List endpoints use opaque keyset cursors (`cursor` in, `nextCursor` out),
  never offsets.
- Errors are always the `Error` schema. `code` is a stable machine-readable
  string; currently defined codes: `invalid-request`, `unauthenticated`,
  `forbidden`, `not-found`, `conflict`, `internal`, `rate-limited` (too
  many attempts; retry later), `stream-stale` (a minted media URL no longer
  matches the file on disk, a metadata-only retag included since the
  pin is byte identity; re-request the info endpoint that minted it), `catalog-maintenance`
  (the catalog is temporarily handed to a maintenance operation; retry
  shortly), `catalog-busy` (another job holds the catalog's shared
  file-mutation scope, so this file-moving request cannot start; unlike
  a plain `conflict` it clears on its own, so retrying it unattended is
  worth something), `sync-reset` (a sync cursor predates the retained change
  history; drop the local mirror and re-mirror from a fresh snapshot),
  `feed-unreachable` (an upstream feed could not be fetched or parsed;
  the feed's own server answered an error, timed out, or returned
  something that is not a feed, or refused the show's stored
  credentials for one of its episode enclosures), `source-unavailable`
  (the request
  needs an acquisition source integration, such as the YouTube bridge,
  that this server is not running), `directory-unavailable` (an
  external directory service, such as the radio station directory,
  could not be reached; try again later), `service-unreachable`
  (an external service this request depends on, such as a
  scrobbling provider, could not be reached; try again later),
  `feature-unavailable` (the request needs an optional capability,
  such as the streaming engine's queue timelines or a cast
  integration, that this server is not running),
  `endpoint-offline` (the target player endpoint is not currently
  connected; refresh the endpoint list), `quota-exceeded` (the
  upload would exceed the caller's storage quota, or an imported
  backup archive exceeds the server's size limit), `field-locked`
  (the edit targets a locked metadata field and did not set
  `force`), `unsupported-format` (the uploaded file's format
  is not accepted by this server), `read-only` (the target
  library, or the whole server, is in read-only mode: uploads,
  organizing, file write-back, deletion, and the file tools are
  refused while reads and playback keep working),
  `transcode-limited` (the server's or the caller's concurrent
  transcode session limit is reached; retry when a session ends,
  or play a direct-play format), and `timeout` (a command routed to
  a player endpoint got no answer within the routing deadline; the
  endpoint is still connected, unlike `endpoint-offline`, so
  retrying is more useful than refreshing the endpoint list).
  New codes may appear; clients must treat unknown codes as opaque.
- An error may also carry `params`, a flat map of strings holding the
  machine-readable detail a code alone cannot express, and `code` names
  which keys can turn up. It is best-effort per refusal rather than
  guaranteed by code: a refusal that has params fills them, and one
  that does not is an ordinary error of that code, so clients read
  params as a refinement and never require them. Under
  `feature-unavailable` - the umbrella for anything this server cannot
  do for a request - the defined keys are `feature`, the missing
  capability, and `pid`, the subject it was asked about; the values
  defined for `feature` so far are `multi-part-audiobook` (a book this
  server cannot yet split across a device endpoint) and
  `windowed-track` (a track that is a window into a larger file), and
  other refusals under that code carry no params yet. Values are
  strings even when they read as numbers. Clients must ignore keys
  they do not know, and an absent `params` means the plain code.
- Media URLs returned by the API (e.g. `PlayInfo.url`) are relative to the
  server origin, the same origin that serves this API and the web UI.
  They live outside `/api/v1` and are not declared as operations here:
  `/media/stream` (the streaming engine's output), `/media/download`
  (original bytes, ranged), `/media/enclosure` (a podcast episode's
  feed enclosure, relayed), `/media/radio/{pid}` (a station
  stream, relayed), and `/media/art` (an item's artwork, the same
  bytes and the same fallback chain as `/items/{pid}/art`). All of
  them authenticate by media token in the query
  string rather than by session or bearer credential, so bare `<audio>`
  elements, cast devices, and DLNA renderers that cannot send headers
  can fetch them. A media token binds one user to one item pid; expiry
  gates new opens rather than cutting a stream already running.
  `/media/enclosure` takes only that pid and token, never a target
  URL: the enclosure is read from the episode in the catalog, so a
  token for one episode reaches that episode's audio and nothing
  else, and the relay copies only `Content-Type`, `Content-Length`,
  `Content-Range`, `Accept-Ranges`, `ETag`, `Last-Modified`, and
  `Content-Encoding` back from the podcast host.
  The two relays that carry a third party's bytes
  (`/media/enclosure` and `/media/radio/{pid}`) are bounded, which
  is the one place token expiry is not the only thing that ends a
  transfer. An account holding too many relayed streams at once is
  refused a new one with `429 rate-limited`; retry when one ends.
  And a relay whose upstream stops sending, or (for an episode,
  which is a finite file) runs past a size ceiling or below a usable
  transfer rate, is ended mid-body: there are no trailers and no
  error document, so a client sees a truncated response and should
  treat it as it would any interrupted download. Time the server
  spends blocked writing to a slow client is never counted against
  these bounds, so a paused player is not a reason to be cut. `/media/art` exists because a device
  endpoint has no session to present: it takes an optional `size` (16
  to 2048, defaulting to 600) and is `no-store`, since the URL
  carries a credential and is minted per listener. First-party
  clients use `/items/{pid}/art`, which is cacheable.
- Public share links live at `/s/{token}` on the server origin, outside
  `/api/v1`. The landing page is server-rendered plain HTML (an audio
  element, artwork, OpenGraph and Twitter card tags) so link previews
  and app-less phones work; it never loads the SPA. `/s/{token}/stream`,
  `/s/{token}/art`, and `/s/{token}/download` serve the media. The token
  is a signed capability: possession grants access until the share
  expires or is revoked, no account needed. Share pages send
  `Referrer-Policy: no-referrer` and `X-Robots-Tag: noindex`, and
  anonymous listeners' transcodes and bandwidth are billed against the
  share owner's limits with per-share concurrency caps.
- The similarity worker API (`/similarity/work`,
  `/similarity/embeddings`, and the audio pull at
  `/media/analysis/{pid}`) authenticates with a server-configured
  worker token (`workerAuth`), not a user credential. Workers are a
  server-level integration: they see every item regardless of library
  visibility grants. The audio pull is a raw media route like
  `/media/stream`: it accepts `format=wav` (loopback workers) or
  `format=flac` (remote workers; losslessly identical input at roughly
  half the bytes), always decoded to 16 kHz mono with gain untouched.
- Cross-site request forgery: state-changing requests (POST, PUT, PATCH,
  DELETE) authenticated by the session cookie must carry an
  `X-CSRF-Token` header matching the session's CSRF token, which login
  and session inspection return in their bodies (a synchronizer token;
  it is never a cookie). Requests authenticated by a bearer token are
  exempt. A cookie-authenticated mutation without a matching token is
  rejected with `forbidden`. Login, logout, and the other endpoints
  declaring `security: []` are exempt (the residual forced-login and
  forced-logout CSRF nuisances are accepted; `SameSite=Lax` cookies
  and the single-origin UI bound them).
- The server never enables cross-origin credentialed access: no CORS
  headers are emitted, and session cookies stay `SameSite=Lax`. The
  CSRF-token readback model depends on this; deployments must not
  layer permissive CORS onto the API origin.
- Every item read and mutation is scoped to the libraries visible to the
  calling user: an item outside the caller's visibility behaves exactly
  as if it did not exist (`not-found`), and list endpoints omit such
  items (a page may carry fewer than `limit` items and still have a
  `nextCursor`).
- Podcast subscriptions additionally scope the caller's own catalog
  view: shows and their episodes appear in item listings, discovery
  browse, search, and catalog sync only while the caller subscribes
  to the show, so unsubscribing removes a show from your library
  surfaces while the catalog keeps everything (files, other users'
  subscriptions, playback history). Subscribing or unsubscribing
  therefore retires the caller's outstanding catalog sync cursors:
  the next delta answers `sync-reset` and the re-mirror reflects the
  new membership. Show detail, a show's episode list, and episode
  reads stay available to any caller who can see the podcast
  library, so shows can be browsed before subscribing.
- Playlists are per-user with a visibility flag: `private` playlists
  exist only for their owner (other callers get `not-found`),
  `shared` playlists are readable by every user but writable only
  by their owner. A shared smart playlist evaluates user-state
  rules (stars, ratings, play counts) against the owner's data:
  viewers see the owner's list, not their own recomputation. Item
  reads through a playlist still apply the caller's own library
  visibility, so a viewer may see fewer items than the owner.
  Replacing a smart playlist's rule applies in place: the pid is
  stable across rule edits, and the caller's server sync stream
  carries one `playlist` event hydrating the changed playlist. The
  deprecated `previousPid` property is retained for wire
  compatibility and is never populated.
- Player endpoints and playback sessions are ephemeral control-plane
  state, not mirrored data: reads always return current truth, there
  are no cursors, and lifecycle changes reach connected clients as
  `player`-topic invalidations on the WebSocket channel. A client
  endpoint (a signed-in first-party client that registered itself as
  controllable) is visible only to its owning user; device endpoints
  the server drives itself (cast targets, DLNA renderers, the
  jukebox output) are shared and visible to every user. A playback
  session is visible to its owner always, and to other users exactly
  when it plays on a shared endpoint (what a shared speaker plays is
  audible to the room; the queue behind it is not private either).
  Controlling a session follows visibility: your own sessions
  always, another user's only on a shared endpoint.
- Curation surfaces (the review queue, the metadata editor and
  entity edits, health fixes, duplicate merges, organizing, the
  audiobook and CUE tools, enrichment dispatch) mutate the shared
  catalog, so their mutations require the `admin` role. Uploads
  and acquisitions are the exception: any user granted upload
  rights can create them, sees their own sessions and the review
  entries they produced, may decide those entries (the files land
  only in a library the caller can see), and keeps item-scoped
  editing rights over the items their own uploads and
  acquisitions brought into the library (scalar fields, credits,
  lyrics, chapters, artwork, custom tags, release status,
  rematch, and per-item enrichment; entity-level edits stay
  administrative). That last rule is what makes hand-curating
  content with no canonical source practical: the person who
  brought in an unofficial remix is the person who can name it.
  Metadata edits write the catalog database first and touch
  files only when the request opts into write-back; a write-back
  that fails after the catalog committed reports the failure
  detail in the response instead of failing the edit, and the
  affected files surface as out-of-sync diagnostics until a
  later write-back or rescan reconciles them.


This Dart package is automatically generated by the [OpenAPI Generator](https://openapi-generator.tech) project:

- API version: 0.11.0
- Generator version: 7.14.0
- Build package: org.openapitools.codegen.languages.DartDioClientCodegen
For more information, please visit [https://github.com/ColeSpringer/WaxDeck](https://github.com/ColeSpringer/WaxDeck)

## Requirements

* Dart 2.15.0+ or Flutter 2.8.0+
* Dio 5.0.0+ (https://pub.dev/packages/dio)

## Installation & Usage

### pub.dev
To use the package from [pub.dev](https://pub.dev), please include the following in pubspec.yaml
```yaml
dependencies:
  waxdeck_api_gen: 0.1.0
```

### Github
If this Dart package is published to Github, please include the following in pubspec.yaml
```yaml
dependencies:
  waxdeck_api_gen:
    git:
      url: https://github.com/GIT_USER_ID/GIT_REPO_ID.git
      #ref: main
```

### Local development
To use the package from your local drive, please include the following in pubspec.yaml
```yaml
dependencies:
  waxdeck_api_gen:
    path: /path/to/waxdeck_api_gen
```

## Getting Started

Please follow the [installation procedure](#installation--usage) and then run the following:

```dart
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart';


final api = WaxdeckApiGen().getAdminApi();

try {
    final response = await api.analyzeLibrary();
    print(response);
} catch on DioException (e) {
    print("Exception when calling AdminApi->analyzeLibrary: $e\n");
}

```

## Documentation for API Endpoints

All URIs are relative to */api/v1*

Class | Method | HTTP request | Description
------------ | ------------- | ------------- | -------------
[*AdminApi*](doc/AdminApi.md) | [**analyzeLibrary**](doc/AdminApi.md#analyzelibrary) | **POST** /library/analyze | Start the analyze pass
[*AdminApi*](doc/AdminApi.md) | [**cancelStagedRestore**](doc/AdminApi.md#cancelstagedrestore) | **DELETE** /admin/backups/restore | Cancel the staged restore
[*AdminApi*](doc/AdminApi.md) | [**createBackup**](doc/AdminApi.md#createbackup) | **POST** /admin/backups | Create a backup now
[*AdminApi*](doc/AdminApi.md) | [**createGenreNormalization**](doc/AdminApi.md#creategenrenormalization) | **POST** /admin/genre-normalize | Normalize every genre in the catalog
[*AdminApi*](doc/AdminApi.md) | [**createLibrary**](doc/AdminApi.md#createlibrary) | **POST** /libraries | Create a library at runtime
[*AdminApi*](doc/AdminApi.md) | [**createMigration**](doc/AdminApi.md#createmigration) | **POST** /admin/migrations | Import listening state from another server
[*AdminApi*](doc/AdminApi.md) | [**deleteBackup**](doc/AdminApi.md#deletebackup) | **DELETE** /admin/backups/{backupId} | Delete a backup archive
[*AdminApi*](doc/AdminApi.md) | [**downloadBackup**](doc/AdminApi.md#downloadbackup) | **GET** /admin/backups/{backupId}/archive | Download a backup archive
[*AdminApi*](doc/AdminApi.md) | [**emptyTrash**](doc/AdminApi.md#emptytrash) | **POST** /admin/trash/empty | Empty the trash
[*AdminApi*](doc/AdminApi.md) | [**getAdminSettings**](doc/AdminApi.md#getadminsettings) | **GET** /admin/settings | Read the server&#39;s runtime settings
[*AdminApi*](doc/AdminApi.md) | [**getBackup**](doc/AdminApi.md#getbackup) | **GET** /admin/backups/{backupId} | Inspect a backup
[*AdminApi*](doc/AdminApi.md) | [**getGenreTree**](doc/AdminApi.md#getgenretree) | **GET** /admin/genre-tree | Read the canonical genre vocabulary
[*AdminApi*](doc/AdminApi.md) | [**getJob**](doc/AdminApi.md#getjob) | **GET** /jobs/{pid} | Get one job&#39;s state
[*AdminApi*](doc/AdminApi.md) | [**getLibraryReadOnly**](doc/AdminApi.md#getlibraryreadonly) | **GET** /libraries/{pid}/read-only | Read a library&#39;s read-only mode
[*AdminApi*](doc/AdminApi.md) | [**getScrobblingConfig**](doc/AdminApi.md#getscrobblingconfig) | **GET** /admin/scrobbling | Read the server&#39;s scrobbling credentials state
[*AdminApi*](doc/AdminApi.md) | [**getStagedRestore**](doc/AdminApi.md#getstagedrestore) | **GET** /admin/backups/restore | Inspect the staged restore
[*AdminApi*](doc/AdminApi.md) | [**getTranscodingActivity**](doc/AdminApi.md#gettranscodingactivity) | **GET** /admin/transcoding/activity | Read what the transcoder is doing right now
[*AdminApi*](doc/AdminApi.md) | [**getTranscodingLimits**](doc/AdminApi.md#gettranscodinglimits) | **GET** /admin/transcoding | Read the transcoding limits
[*AdminApi*](doc/AdminApi.md) | [**importBackup**](doc/AdminApi.md#importbackup) | **POST** /admin/backups/import | Upload a backup archive
[*AdminApi*](doc/AdminApi.md) | [**listAuditEvents**](doc/AdminApi.md#listauditevents) | **GET** /admin/audit | List admin-action audit events
[*AdminApi*](doc/AdminApi.md) | [**listBackups**](doc/AdminApi.md#listbackups) | **GET** /admin/backups | List backup archives
[*AdminApi*](doc/AdminApi.md) | [**listJobs**](doc/AdminApi.md#listjobs) | **GET** /jobs | List recent catalog jobs
[*AdminApi*](doc/AdminApi.md) | [**listLibraries**](doc/AdminApi.md#listlibraries) | **GET** /libraries | List libraries
[*AdminApi*](doc/AdminApi.md) | [**listSchedules**](doc/AdminApi.md#listschedules) | **GET** /admin/schedules | List the scheduled jobs
[*AdminApi*](doc/AdminApi.md) | [**listTrash**](doc/AdminApi.md#listtrash) | **GET** /admin/trash | List the trash
[*AdminApi*](doc/AdminApi.md) | [**purgeTrashEntry**](doc/AdminApi.md#purgetrashentry) | **DELETE** /admin/trash/{trashId} | Purge one trashed file
[*AdminApi*](doc/AdminApi.md) | [**putAdminSettings**](doc/AdminApi.md#putadminsettings) | **PUT** /admin/settings | Replace the server&#39;s runtime settings
[*AdminApi*](doc/AdminApi.md) | [**putGenreTree**](doc/AdminApi.md#putgenretree) | **PUT** /admin/genre-tree | Replace the canonical genre vocabulary
[*AdminApi*](doc/AdminApi.md) | [**putSchedule**](doc/AdminApi.md#putschedule) | **PUT** /admin/schedules/{kind} | Set a scheduled job&#39;s cron and enabled state
[*AdminApi*](doc/AdminApi.md) | [**putScrobblingConfig**](doc/AdminApi.md#putscrobblingconfig) | **PUT** /admin/scrobbling | Set the server&#39;s Last.fm API credentials
[*AdminApi*](doc/AdminApi.md) | [**putTranscodingLimits**](doc/AdminApi.md#puttranscodinglimits) | **PUT** /admin/transcoding | Replace the transcoding limits
[*AdminApi*](doc/AdminApi.md) | [**rescanLibrary**](doc/AdminApi.md#rescanlibrary) | **POST** /library/rescan | Start a library rescan
[*AdminApi*](doc/AdminApi.md) | [**restoreTrashEntry**](doc/AdminApi.md#restoretrashentry) | **POST** /admin/trash/{trashId}/restore | Restore a trashed file
[*AdminApi*](doc/AdminApi.md) | [**setLibraryReadOnly**](doc/AdminApi.md#setlibraryreadonly) | **PUT** /libraries/{pid}/read-only | Set a library&#39;s read-only mode
[*AdminApi*](doc/AdminApi.md) | [**stageRestore**](doc/AdminApi.md#stagerestore) | **POST** /admin/backups/{backupId}/restore | Stage a restore from a backup
[*AuthApi*](doc/AuthApi.md) | [**bootstrap**](doc/AuthApi.md#bootstrap) | **POST** /auth/bootstrap | Create the first administrator
[*AuthApi*](doc/AuthApi.md) | [**exchangeOidcCode**](doc/AuthApi.md#exchangeoidccode) | **POST** /auth/oidc/exchange | Exchange a one-time OIDC code for a session
[*AuthApi*](doc/AuthApi.md) | [**getBootstrapStatus**](doc/AuthApi.md#getbootstrapstatus) | **GET** /auth/bootstrap | Check whether first-run setup is needed
[*AuthApi*](doc/AuthApi.md) | [**getSession**](doc/AuthApi.md#getsession) | **GET** /auth/session | Inspect the current session
[*AuthApi*](doc/AuthApi.md) | [**listOidcProviders**](doc/AuthApi.md#listoidcproviders) | **GET** /auth/oidc/providers | List configured OIDC providers
[*AuthApi*](doc/AuthApi.md) | [**listSessions**](doc/AuthApi.md#listsessions) | **GET** /auth/sessions | List the caller&#39;s sessions and devices
[*AuthApi*](doc/AuthApi.md) | [**login**](doc/AuthApi.md#login) | **POST** /auth/login | Log in and establish a session
[*AuthApi*](doc/AuthApi.md) | [**logout**](doc/AuthApi.md#logout) | **POST** /auth/logout | End the current session
[*AuthApi*](doc/AuthApi.md) | [**oidcCallback**](doc/AuthApi.md#oidccallback) | **GET** /auth/oidc/callback | OIDC provider callback
[*AuthApi*](doc/AuthApi.md) | [**refreshToken**](doc/AuthApi.md#refreshtoken) | **POST** /auth/refresh | Rotate the caller&#39;s bearer token
[*AuthApi*](doc/AuthApi.md) | [**renameSession**](doc/AuthApi.md#renamesession) | **PATCH** /auth/sessions/{sessionId} | Rename one of the caller&#39;s sessions
[*AuthApi*](doc/AuthApi.md) | [**revokeSession**](doc/AuthApi.md#revokesession) | **DELETE** /auth/sessions/{sessionId} | Revoke one of the caller&#39;s sessions
[*AuthApi*](doc/AuthApi.md) | [**signup**](doc/AuthApi.md#signup) | **POST** /auth/signup | Request an account
[*AuthApi*](doc/AuthApi.md) | [**startOidc**](doc/AuthApi.md#startoidc) | **GET** /auth/oidc/start | Start an OIDC login
[*BooksApi*](doc/BooksApi.md) | [**createBookmark**](doc/BooksApi.md#createbookmark) | **POST** /books/{pid}/bookmarks | Mark a place in a book
[*BooksApi*](doc/BooksApi.md) | [**deleteBookmark**](doc/BooksApi.md#deletebookmark) | **DELETE** /books/{pid}/bookmarks/{bookmarkId} | Remove one bookmark
[*BooksApi*](doc/BooksApi.md) | [**getBook**](doc/BooksApi.md#getbook) | **GET** /books/{pid} | Get one audiobook&#39;s detail
[*BooksApi*](doc/BooksApi.md) | [**getBookResume**](doc/BooksApi.md#getbookresume) | **GET** /books/{pid}/resume | Where the caller left off in a book
[*BooksApi*](doc/BooksApi.md) | [**listBookmarks**](doc/BooksApi.md#listbookmarks) | **GET** /books/{pid}/bookmarks | List the caller&#39;s bookmarks in a book
[*BooksApi*](doc/BooksApi.md) | [**putBookSettings**](doc/BooksApi.md#putbooksettings) | **PUT** /books/{pid}/settings | Replace the caller&#39;s playback settings for a book
[*DiscoveryApi*](doc/DiscoveryApi.md) | [**createInstantMix**](doc/DiscoveryApi.md#createinstantmix) | **POST** /mixes/instant | Instant mix
[*DiscoveryApi*](doc/DiscoveryApi.md) | [**getSimilarTracks**](doc/DiscoveryApi.md#getsimilartracks) | **GET** /items/{pid}/similar | Similar tracks
[*DiscoveryApi*](doc/DiscoveryApi.md) | [**getSonicPath**](doc/DiscoveryApi.md#getsonicpath) | **GET** /mixes/path | Sonic path between two tracks
[*EnrichmentApi*](doc/EnrichmentApi.md) | [**getEnrichmentStatus**](doc/EnrichmentApi.md#getenrichmentstatus) | **GET** /library/enrichment | Enrichment status and coverage
[*EnrichmentApi*](doc/EnrichmentApi.md) | [**runEnrichment**](doc/EnrichmentApi.md#runenrichment) | **POST** /library/enrichment/run | Run a whole-library enrichment pass
[*HealthApi*](doc/HealthApi.md) | [**fixHealthIssues**](doc/HealthApi.md#fixhealthissues) | **POST** /library/health/fix | Bulk-fix a health rule
[*HealthApi*](doc/HealthApi.md) | [**getDiagnosticSummary**](doc/HealthApi.md#getdiagnosticsummary) | **GET** /library/diagnostics/summary | Summarize per-file diagnostics
[*HealthApi*](doc/HealthApi.md) | [**getLibraryHealth**](doc/HealthApi.md#getlibraryhealth) | **GET** /library/health | Metadata health summary
[*HealthApi*](doc/HealthApi.md) | [**listDuplicates**](doc/HealthApi.md#listduplicates) | **GET** /library/duplicates | List duplicate entities
[*HealthApi*](doc/HealthApi.md) | [**listFileDiagnostics**](doc/HealthApi.md#listfilediagnostics) | **GET** /library/diagnostics | Query per-file diagnostics
[*HealthApi*](doc/HealthApi.md) | [**listHealthIssues**](doc/HealthApi.md#listhealthissues) | **GET** /library/health/issues | List items failing health rules
[*HealthApi*](doc/HealthApi.md) | [**listUpgrades**](doc/HealthApi.md#listupgrades) | **GET** /library/upgrades | List quality upgrade groups
[*HealthApi*](doc/HealthApi.md) | [**mergeDuplicates**](doc/HealthApi.md#mergeduplicates) | **POST** /library/duplicates/merge | Merge duplicate entities
[*HealthApi*](doc/HealthApi.md) | [**resolveUpgrade**](doc/HealthApi.md#resolveupgrade) | **POST** /library/upgrades/resolve | Keep the best encoding
[*HealthApi*](doc/HealthApi.md) | [**sweepLibraryHealth**](doc/HealthApi.md#sweeplibraryhealth) | **POST** /library/health/sweep | Re-sweep health now
[*LibraryApi*](doc/LibraryApi.md) | [**browseList**](doc/LibraryApi.md#browselist) | **GET** /library/browse | Browse a discovery list
[*LibraryApi*](doc/LibraryApi.md) | [**deleteLibraryItems**](doc/LibraryApi.md#deletelibraryitems) | **POST** /library/items/delete | Delete library items
[*LibraryApi*](doc/LibraryApi.md) | [**getAlbum**](doc/LibraryApi.md#getalbum) | **GET** /albums/{pid} | Get one album&#39;s identity
[*LibraryApi*](doc/LibraryApi.md) | [**getItem**](doc/LibraryApi.md#getitem) | **GET** /items/{pid} | Get one item&#39;s detail
[*LibraryApi*](doc/LibraryApi.md) | [**getItemArt**](doc/LibraryApi.md#getitemart) | **GET** /items/{pid}/art | Get artwork
[*LibraryApi*](doc/LibraryApi.md) | [**getItemArtRoles**](doc/LibraryApi.md#getitemartroles) | **GET** /items/{pid}/art-roles | List the artwork slots an entity holds
[*LibraryApi*](doc/LibraryApi.md) | [**getItemLyrics**](doc/LibraryApi.md#getitemlyrics) | **GET** /items/{pid}/lyrics | Get an item&#39;s lyrics
[*LibraryApi*](doc/LibraryApi.md) | [**listFacets**](doc/LibraryApi.md#listfacets) | **GET** /library/facets | Enumerate a browse dimension
[*LibraryApi*](doc/LibraryApi.md) | [**listItems**](doc/LibraryApi.md#listitems) | **GET** /library/items | Browse library items
[*LibraryApi*](doc/LibraryApi.md) | [**resolveEntities**](doc/LibraryApi.md#resolveentities) | **POST** /library/entities | Resolve a list of entity PIDs to cards
[*LibraryApi*](doc/LibraryApi.md) | [**search**](doc/LibraryApi.md#search) | **GET** /library/search | Search the library
[*MetadataApi*](doc/MetadataApi.md) | [**bulkEditMetadata**](doc/MetadataApi.md#bulkeditmetadata) | **POST** /items/bulk-edit | Edit fields on many items
[*MetadataApi*](doc/MetadataApi.md) | [**clearEntityArtwork**](doc/MetadataApi.md#clearentityartwork) | **DELETE** /entities/{entityType}/{entityPid}/artwork | Clear entity artwork
[*MetadataApi*](doc/MetadataApi.md) | [**clearItemArtwork**](doc/MetadataApi.md#clearitemartwork) | **DELETE** /items/{pid}/artwork | Clear item artwork
[*MetadataApi*](doc/MetadataApi.md) | [**clearItemLyrics**](doc/MetadataApi.md#clearitemlyrics) | **DELETE** /items/{pid}/lyrics | Clear lyrics
[*MetadataApi*](doc/MetadataApi.md) | [**clearItemTag**](doc/MetadataApi.md#clearitemtag) | **DELETE** /items/{pid}/tags/{key} | Clear a custom tag
[*MetadataApi*](doc/MetadataApi.md) | [**editEntity**](doc/MetadataApi.md#editentity) | **PATCH** /entities/{entityType}/{entityPid} | Edit entity fields
[*MetadataApi*](doc/MetadataApi.md) | [**editItemMetadata**](doc/MetadataApi.md#edititemmetadata) | **PATCH** /items/{pid}/metadata | Edit scalar fields
[*MetadataApi*](doc/MetadataApi.md) | [**enrichItem**](doc/MetadataApi.md#enrichitem) | **POST** /items/{pid}/enrich | Enrich one item now
[*MetadataApi*](doc/MetadataApi.md) | [**getEntityCuration**](doc/MetadataApi.md#getentitycuration) | **GET** /entities/{entityType}/{entityPid}/curation | Read entity edit provenance
[*MetadataApi*](doc/MetadataApi.md) | [**getItemMetadata**](doc/MetadataApi.md#getitemmetadata) | **GET** /items/{pid}/metadata | Read an item&#39;s full metadata
[*MetadataApi*](doc/MetadataApi.md) | [**getMetadataFields**](doc/MetadataApi.md#getmetadatafields) | **GET** /metadata/fields | Discover the editable field vocabulary
[*MetadataApi*](doc/MetadataApi.md) | [**rematchItem**](doc/MetadataApi.md#rematchitem) | **POST** /items/{pid}/rematch | Requeue an item for matching
[*MetadataApi*](doc/MetadataApi.md) | [**setBookChapters**](doc/MetadataApi.md#setbookchapters) | **PUT** /books/{pid}/chapters | Replace a book&#39;s chapters
[*MetadataApi*](doc/MetadataApi.md) | [**setEntityArtwork**](doc/MetadataApi.md#setentityartwork) | **PUT** /entities/{entityType}/{entityPid}/artwork | Set entity artwork
[*MetadataApi*](doc/MetadataApi.md) | [**setItemArtwork**](doc/MetadataApi.md#setitemartwork) | **PUT** /items/{pid}/artwork | Set item artwork
[*MetadataApi*](doc/MetadataApi.md) | [**setItemCredits**](doc/MetadataApi.md#setitemcredits) | **PUT** /items/{pid}/credits | Replace one credit role
[*MetadataApi*](doc/MetadataApi.md) | [**setItemLocks**](doc/MetadataApi.md#setitemlocks) | **PUT** /items/{pid}/locks | Lock or unlock fields
[*MetadataApi*](doc/MetadataApi.md) | [**setItemLyrics**](doc/MetadataApi.md#setitemlyrics) | **PUT** /items/{pid}/lyrics | Set lyrics
[*MetadataApi*](doc/MetadataApi.md) | [**setItemTag**](doc/MetadataApi.md#setitemtag) | **PUT** /items/{pid}/tags/{key} | Set a custom tag
[*MetadataApi*](doc/MetadataApi.md) | [**setReleaseStatus**](doc/MetadataApi.md#setreleasestatus) | **PUT** /items/{pid}/release-status | Mark content unofficial
[*NotificationsApi*](doc/NotificationsApi.md) | [**createMyNotificationTarget**](doc/NotificationsApi.md#createmynotificationtarget) | **POST** /users/me/notification-targets | Create a personal notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**createPushRegistration**](doc/NotificationsApi.md#createpushregistration) | **POST** /users/me/push-registrations | Register a UnifiedPush endpoint
[*NotificationsApi*](doc/NotificationsApi.md) | [**createServerNotificationTarget**](doc/NotificationsApi.md#createservernotificationtarget) | **POST** /admin/notification-targets | Create a server-scope notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**deleteAllPushRegistrations**](doc/NotificationsApi.md#deleteallpushregistrations) | **DELETE** /users/me/push-registrations | Remove all of the caller&#39;s push registrations
[*NotificationsApi*](doc/NotificationsApi.md) | [**deleteMyNotificationTarget**](doc/NotificationsApi.md#deletemynotificationtarget) | **DELETE** /users/me/notification-targets/{targetId} | Delete a personal notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**deletePushRegistration**](doc/NotificationsApi.md#deletepushregistration) | **DELETE** /users/me/push-registrations/{registrationId} | Remove a push registration
[*NotificationsApi*](doc/NotificationsApi.md) | [**deleteServerNotificationTarget**](doc/NotificationsApi.md#deleteservernotificationtarget) | **DELETE** /admin/notification-targets/{targetId} | Delete a server-scope notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**listMyNotificationTargets**](doc/NotificationsApi.md#listmynotificationtargets) | **GET** /users/me/notification-targets | List the caller&#39;s notification targets
[*NotificationsApi*](doc/NotificationsApi.md) | [**listNotificationEvents**](doc/NotificationsApi.md#listnotificationevents) | **GET** /notifications/events | List the notification event catalog
[*NotificationsApi*](doc/NotificationsApi.md) | [**listPushRegistrations**](doc/NotificationsApi.md#listpushregistrations) | **GET** /users/me/push-registrations | List the caller&#39;s push registrations
[*NotificationsApi*](doc/NotificationsApi.md) | [**listServerNotificationTargets**](doc/NotificationsApi.md#listservernotificationtargets) | **GET** /admin/notification-targets | List the server-scope notification targets
[*NotificationsApi*](doc/NotificationsApi.md) | [**testMyNotificationTarget**](doc/NotificationsApi.md#testmynotificationtarget) | **POST** /users/me/notification-targets/{targetId}/test | Test a personal notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**testServerNotificationTarget**](doc/NotificationsApi.md#testservernotificationtarget) | **POST** /admin/notification-targets/{targetId}/test | Test a server-scope notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**updateMyNotificationTarget**](doc/NotificationsApi.md#updatemynotificationtarget) | **PUT** /users/me/notification-targets/{targetId} | Update a personal notification target
[*NotificationsApi*](doc/NotificationsApi.md) | [**updateServerNotificationTarget**](doc/NotificationsApi.md#updateservernotificationtarget) | **PUT** /admin/notification-targets/{targetId} | Update a server-scope notification target
[*OrganizeApi*](doc/OrganizeApi.md) | [**applyOrganize**](doc/OrganizeApi.md#applyorganize) | **POST** /organize/apply | Apply an organize pass
[*OrganizeApi*](doc/OrganizeApi.md) | [**listOrganizeProfiles**](doc/OrganizeApi.md#listorganizeprofiles) | **GET** /organize/profiles | List organize profiles
[*OrganizeApi*](doc/OrganizeApi.md) | [**previewOrganize**](doc/OrganizeApi.md#previeworganize) | **POST** /organize/preview | Dry-run an organize pass
[*PlaybackApi*](doc/PlaybackApi.md) | [**getAlbumPlayState**](doc/PlaybackApi.md#getalbumplaystate) | **GET** /albums/{pid}/play-state | Get the caller&#39;s star and rating for an album
[*PlaybackApi*](doc/PlaybackApi.md) | [**getArtistPlayState**](doc/PlaybackApi.md#getartistplaystate) | **GET** /artists/{pid}/play-state | Get the caller&#39;s star and rating for an artist
[*PlaybackApi*](doc/PlaybackApi.md) | [**getDownloadInfo**](doc/PlaybackApi.md#getdownloadinfo) | **GET** /items/{pid}/download-info | Resolve an offline download for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getPlayInfo**](doc/PlaybackApi.md#getplayinfo) | **GET** /items/{pid}/play-info | Resolve a playable stream for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getPlayState**](doc/PlaybackApi.md#getplaystate) | **GET** /items/{pid}/play-state | Get the caller&#39;s playback state for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getSkipMap**](doc/PlaybackApi.md#getskipmap) | **GET** /items/{pid}/skip-map | Get an item&#39;s silence skip map
[*PlaybackApi*](doc/PlaybackApi.md) | [**getWaveform**](doc/PlaybackApi.md#getwaveform) | **GET** /items/{pid}/waveform | Get an item&#39;s waveform overview
[*PlaybackApi*](doc/PlaybackApi.md) | [**listPlayStates**](doc/PlaybackApi.md#listplaystates) | **POST** /play-states | Read the caller&#39;s playback state for many items
[*PlaybackApi*](doc/PlaybackApi.md) | [**listStarredEntities**](doc/PlaybackApi.md#liststarredentities) | **GET** /starred-entities | List the caller&#39;s starred artists and albums
[*PlaybackApi*](doc/PlaybackApi.md) | [**putPlayState**](doc/PlaybackApi.md#putplaystate) | **PUT** /items/{pid}/play-state | Checkpoint the caller&#39;s playback position
[*PlaybackApi*](doc/PlaybackApi.md) | [**reportListens**](doc/PlaybackApi.md#reportlistens) | **POST** /listens | Report listen sessions
[*PlaybackApi*](doc/PlaybackApi.md) | [**setAlbumRating**](doc/PlaybackApi.md#setalbumrating) | **PUT** /albums/{pid}/rating | Rate an album
[*PlaybackApi*](doc/PlaybackApi.md) | [**setAlbumStar**](doc/PlaybackApi.md#setalbumstar) | **PUT** /albums/{pid}/star | Star or unstar an album
[*PlaybackApi*](doc/PlaybackApi.md) | [**setArtistRating**](doc/PlaybackApi.md#setartistrating) | **PUT** /artists/{pid}/rating | Rate an artist
[*PlaybackApi*](doc/PlaybackApi.md) | [**setArtistStar**](doc/PlaybackApi.md#setartiststar) | **PUT** /artists/{pid}/star | Star or unstar an artist
[*PlaybackApi*](doc/PlaybackApi.md) | [**setPlayed**](doc/PlaybackApi.md#setplayed) | **PUT** /items/{pid}/played | Set or clear an item&#39;s played and finished flags
[*PlaybackApi*](doc/PlaybackApi.md) | [**setRating**](doc/PlaybackApi.md#setrating) | **PUT** /items/{pid}/rating | Rate an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**setStar**](doc/PlaybackApi.md#setstar) | **PUT** /items/{pid}/star | Star or unstar an item
[*PlayerApi*](doc/PlayerApi.md) | [**createPlaybackSession**](doc/PlayerApi.md#createplaybacksession) | **POST** /player/sessions | Start playback on an endpoint
[*PlayerApi*](doc/PlayerApi.md) | [**createQueueTimeline**](doc/PlayerApi.md#createqueuetimeline) | **POST** /player/timeline | Mint a gapless queue timeline
[*PlayerApi*](doc/PlayerApi.md) | [**deletePlaybackSession**](doc/PlayerApi.md#deleteplaybacksession) | **DELETE** /player/sessions/{sessionId} | End a playback session
[*PlayerApi*](doc/PlayerApi.md) | [**getCastPreflight**](doc/PlayerApi.md#getcastpreflight) | **GET** /player/cast/preflight | Check cast reachability
[*PlayerApi*](doc/PlayerApi.md) | [**getPlaybackSession**](doc/PlayerApi.md#getplaybacksession) | **GET** /player/sessions/{sessionId} | Get one playback session
[*PlayerApi*](doc/PlayerApi.md) | [**listPlaybackSessionHistory**](doc/PlayerApi.md#listplaybacksessionhistory) | **GET** /player/sessions/history | List the caller&#39;s ended playback sessions
[*PlayerApi*](doc/PlayerApi.md) | [**listPlaybackSessions**](doc/PlayerApi.md#listplaybacksessions) | **GET** /player/sessions | List playback sessions
[*PlayerApi*](doc/PlayerApi.md) | [**listPlayerEndpoints**](doc/PlayerApi.md#listplayerendpoints) | **GET** /player/endpoints | List player endpoints
[*PlayerApi*](doc/PlayerApi.md) | [**transferPlaybackSession**](doc/PlayerApi.md#transferplaybacksession) | **POST** /player/sessions/{sessionId}/transfer | Transfer a session to another endpoint
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**addPlaylistItems**](doc/PlaylistsApi.md#addplaylistitems) | **POST** /playlists/{pid}/items | Append items to a static playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**createPlaylist**](doc/PlaylistsApi.md#createplaylist) | **POST** /playlists | Create a playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**deletePlaylist**](doc/PlaylistsApi.md#deleteplaylist) | **DELETE** /playlists/{pid} | Delete a playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**exportPlaylistM3u**](doc/PlaylistsApi.md#exportplaylistm3u) | **GET** /playlists/{pid}/m3u | Export a playlist as M3U8
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**exportPlaylistPortable**](doc/PlaylistsApi.md#exportplaylistportable) | **GET** /playlists/{pid}/portable | Export a playlist as portable refs
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**getPlaylist**](doc/PlaylistsApi.md#getplaylist) | **GET** /playlists/{pid} | Get one playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**getRuleFields**](doc/PlaylistsApi.md#getrulefields) | **GET** /playlists/rule-fields | Discover smart rule fields
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**importPlaylist**](doc/PlaylistsApi.md#importplaylist) | **POST** /playlists/import | Import a streaming-service playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**importPlaylistM3u**](doc/PlaylistsApi.md#importplaylistm3u) | **POST** /playlists/m3u | Import an M3U8 playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**listPlaylistItems**](doc/PlaylistsApi.md#listplaylistitems) | **GET** /playlists/{pid}/items | List a playlist&#39;s items
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**listPlaylists**](doc/PlaylistsApi.md#listplaylists) | **GET** /playlists | List playlists visible to the caller
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**previewSmartRule**](doc/PlaylistsApi.md#previewsmartrule) | **POST** /playlists/preview | Preview a smart rule
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**removePlaylistItemAt**](doc/PlaylistsApi.md#removeplaylistitemat) | **DELETE** /playlists/{pid}/items/{position} | Remove one member by position
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**replacePlaylistItems**](doc/PlaylistsApi.md#replaceplaylistitems) | **PUT** /playlists/{pid}/items | Replace a static playlist&#39;s members
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**updatePlaylist**](doc/PlaylistsApi.md#updateplaylist) | **PATCH** /playlists/{pid} | Update a playlist
[*PodcastsApi*](doc/PodcastsApi.md) | [**captureEpisodeTranscript**](doc/PodcastsApi.md#captureepisodetranscript) | **POST** /episodes/{pid}/transcript | Capture an episode&#39;s transcript for search
[*PodcastsApi*](doc/PodcastsApi.md) | [**exportOpml**](doc/PodcastsApi.md#exportopml) | **GET** /podcasts/opml | Export the caller&#39;s subscriptions as OPML
[*PodcastsApi*](doc/PodcastsApi.md) | [**fetchEpisode**](doc/PodcastsApi.md#fetchepisode) | **POST** /episodes/{pid}/fetch | Fetch an episode&#39;s audio to the server
[*PodcastsApi*](doc/PodcastsApi.md) | [**getEpisode**](doc/PodcastsApi.md#getepisode) | **GET** /episodes/{pid} | Get one episode&#39;s detail
[*PodcastsApi*](doc/PodcastsApi.md) | [**getEpisodeTranscript**](doc/PodcastsApi.md#getepisodetranscript) | **GET** /episodes/{pid}/transcript | Get an episode&#39;s transcript
[*PodcastsApi*](doc/PodcastsApi.md) | [**getPodcast**](doc/PodcastsApi.md#getpodcast) | **GET** /podcasts/{pid} | Get one show with the caller&#39;s subscription state
[*PodcastsApi*](doc/PodcastsApi.md) | [**importOpml**](doc/PodcastsApi.md#importopml) | **POST** /podcasts/opml | Import subscriptions from OPML
[*PodcastsApi*](doc/PodcastsApi.md) | [**listEpisodes**](doc/PodcastsApi.md#listepisodes) | **GET** /podcasts/{pid}/episodes | List a show&#39;s episodes
[*PodcastsApi*](doc/PodcastsApi.md) | [**listSubscribedEpisodes**](doc/PodcastsApi.md#listsubscribedepisodes) | **GET** /podcasts/episodes | List episodes across the caller&#39;s subscriptions
[*PodcastsApi*](doc/PodcastsApi.md) | [**listSubscriptions**](doc/PodcastsApi.md#listsubscriptions) | **GET** /podcasts | List the caller&#39;s podcast subscriptions
[*PodcastsApi*](doc/PodcastsApi.md) | [**putSubscriptionSettings**](doc/PodcastsApi.md#putsubscriptionsettings) | **PUT** /podcasts/{pid}/settings | Replace the caller&#39;s settings for a subscription
[*PodcastsApi*](doc/PodcastsApi.md) | [**refreshPodcast**](doc/PodcastsApi.md#refreshpodcast) | **POST** /podcasts/{pid}/refresh | Refresh a show&#39;s feed now
[*PodcastsApi*](doc/PodcastsApi.md) | [**removeEpisodeDownload**](doc/PodcastsApi.md#removeepisodedownload) | **DELETE** /episodes/{pid}/fetch | Remove an episode&#39;s fetched audio from the server
[*PodcastsApi*](doc/PodcastsApi.md) | [**searchPodcastDirectory**](doc/PodcastsApi.md#searchpodcastdirectory) | **GET** /podcasts/directory | Search the podcast directory
[*PodcastsApi*](doc/PodcastsApi.md) | [**subscribePodcast**](doc/PodcastsApi.md#subscribepodcast) | **POST** /podcasts | Subscribe to a podcast
[*PodcastsApi*](doc/PodcastsApi.md) | [**unsubscribePodcast**](doc/PodcastsApi.md#unsubscribepodcast) | **DELETE** /podcasts/{pid} | Unsubscribe from a show
[*RadioApi*](doc/RadioApi.md) | [**createRadioStation**](doc/RadioApi.md#createradiostation) | **POST** /radio/stations | Add a radio station
[*RadioApi*](doc/RadioApi.md) | [**deleteRadioSavedSong**](doc/RadioApi.md#deleteradiosavedsong) | **DELETE** /radio/saved/{pid} | Drop a saved song
[*RadioApi*](doc/RadioApi.md) | [**deleteRadioStation**](doc/RadioApi.md#deleteradiostation) | **DELETE** /radio/stations/{pid} | Delete a radio station
[*RadioApi*](doc/RadioApi.md) | [**getRadioNowPlayingArt**](doc/RadioApi.md#getradionowplayingart) | **GET** /radio/stations/{pid}/now-playing-art | Get cover art for a station&#39;s announced track
[*RadioApi*](doc/RadioApi.md) | [**getRadioPlayInfo**](doc/RadioApi.md#getradioplayinfo) | **GET** /radio/stations/{pid}/play-info | Resolve a playable station stream
[*RadioApi*](doc/RadioApi.md) | [**getRadioSavedSongArt**](doc/RadioApi.md#getradiosavedsongart) | **GET** /radio/saved/{pid}/art | Get a saved song&#39;s snapshot cover
[*RadioApi*](doc/RadioApi.md) | [**getRadioStation**](doc/RadioApi.md#getradiostation) | **GET** /radio/stations/{pid} | Get one radio station
[*RadioApi*](doc/RadioApi.md) | [**getRadioStationLogo**](doc/RadioApi.md#getradiostationlogo) | **GET** /radio/stations/{pid}/logo | Get a station logo
[*RadioApi*](doc/RadioApi.md) | [**listRadioSavedSongs**](doc/RadioApi.md#listradiosavedsongs) | **GET** /radio/saved | List songs kept off the air
[*RadioApi*](doc/RadioApi.md) | [**listRadioStations**](doc/RadioApi.md#listradiostations) | **GET** /radio/stations | List radio stations
[*RadioApi*](doc/RadioApi.md) | [**saveRadioSong**](doc/RadioApi.md#saveradiosong) | **POST** /radio/saved | Keep the song a station is playing
[*RadioApi*](doc/RadioApi.md) | [**searchRadioDirectory**](doc/RadioApi.md#searchradiodirectory) | **GET** /radio/directory | Search the station directory
[*RadioApi*](doc/RadioApi.md) | [**updateRadioStation**](doc/RadioApi.md#updateradiostation) | **PUT** /radio/stations/{pid} | Update a radio station
[*ReviewApi*](doc/ReviewApi.md) | [**decideReviewBulk**](doc/ReviewApi.md#decidereviewbulk) | **POST** /review/decide | Decide many review entries
[*ReviewApi*](doc/ReviewApi.md) | [**decideReviewEntry**](doc/ReviewApi.md#decidereviewentry) | **POST** /review/queue/{entryId}/decide | Decide a review entry
[*ReviewApi*](doc/ReviewApi.md) | [**getLibraryMatching**](doc/ReviewApi.md#getlibrarymatching) | **GET** /libraries/{pid}/matching | Read a library&#39;s matching mode
[*ReviewApi*](doc/ReviewApi.md) | [**getReviewEntry**](doc/ReviewApi.md#getreviewentry) | **GET** /review/queue/{entryId} | Inspect one review entry
[*ReviewApi*](doc/ReviewApi.md) | [**getReviewStats**](doc/ReviewApi.md#getreviewstats) | **GET** /review/stats | Review and calibration statistics
[*ReviewApi*](doc/ReviewApi.md) | [**listReviewQueue**](doc/ReviewApi.md#listreviewqueue) | **GET** /review/queue | List review queue entries
[*ReviewApi*](doc/ReviewApi.md) | [**reidentifyReviewEntry**](doc/ReviewApi.md#reidentifyreviewentry) | **POST** /review/queue/{entryId}/identify | Search again for a review entry
[*ReviewApi*](doc/ReviewApi.md) | [**revertReviewEntry**](doc/ReviewApi.md#revertreviewentry) | **POST** /review/queue/{entryId}/revert | Revert an applied match
[*ReviewApi*](doc/ReviewApi.md) | [**setLibraryMatching**](doc/ReviewApi.md#setlibrarymatching) | **PUT** /libraries/{pid}/matching | Set a library&#39;s matching mode
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**connectListenBrainz**](doc/ScrobblingApi.md#connectlistenbrainz) | **PUT** /users/me/scrobblers/listenbrainz | Connect ListenBrainz
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**disconnectLastfm**](doc/ScrobblingApi.md#disconnectlastfm) | **DELETE** /users/me/scrobblers/lastfm | Disconnect Last.fm
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**disconnectListenBrainz**](doc/ScrobblingApi.md#disconnectlistenbrainz) | **DELETE** /users/me/scrobblers/listenbrainz | Disconnect ListenBrainz
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**lastfmCallback**](doc/ScrobblingApi.md#lastfmcallback) | **GET** /scrobble/lastfm/callback | Last.fm authorization callback
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**listScrobblers**](doc/ScrobblingApi.md#listscrobblers) | **GET** /users/me/scrobblers | List the caller&#39;s scrobbling connections
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**startLastfmConnect**](doc/ScrobblingApi.md#startlastfmconnect) | **POST** /users/me/scrobblers/lastfm/connect | Start linking a Last.fm account
[*SharesApi*](doc/SharesApi.md) | [**createShare**](doc/SharesApi.md#createshare) | **POST** /shares | Create a share link
[*SharesApi*](doc/SharesApi.md) | [**listShares**](doc/SharesApi.md#listshares) | **GET** /shares | List share links
[*SharesApi*](doc/SharesApi.md) | [**revokeShare**](doc/SharesApi.md#revokeshare) | **DELETE** /shares/{shareId} | Revoke a share link
[*SimilarityApi*](doc/SimilarityApi.md) | [**getSimilarityStatus**](doc/SimilarityApi.md#getsimilaritystatus) | **GET** /similarity/status | Similarity analysis status
[*SimilarityApi*](doc/SimilarityApi.md) | [**pullSimilarityWork**](doc/SimilarityApi.md#pullsimilaritywork) | **GET** /similarity/work | Pull analysis work (worker)
[*SimilarityApi*](doc/SimilarityApi.md) | [**reportEmbeddings**](doc/SimilarityApi.md#reportembeddings) | **POST** /similarity/embeddings | Post computed embeddings (worker)
[*StatsApi*](doc/StatsApi.md) | [**getListeningHeatmap**](doc/StatsApi.md#getlisteningheatmap) | **GET** /stats/heatmap | Calendar heatmap and streaks
[*StatsApi*](doc/StatsApi.md) | [**getListeningStats**](doc/StatsApi.md#getlisteningstats) | **GET** /stats/listening | Listening time statistics
[*StatsApi*](doc/StatsApi.md) | [**getServerYearInReview**](doc/StatsApi.md#getserveryearinreview) | **GET** /stats/server-year-in-review | Server-wide year in review
[*StatsApi*](doc/StatsApi.md) | [**getTopList**](doc/StatsApi.md#gettoplist) | **GET** /stats/top | Top artists, albums, genres, or shows
[*StatsApi*](doc/StatsApi.md) | [**getYearInReview**](doc/StatsApi.md#getyearinreview) | **GET** /stats/year-in-review | Year in review
[*StatsApi*](doc/StatsApi.md) | [**listListenLog**](doc/StatsApi.md#listlistenlog) | **GET** /stats/sessions | Listen session log
[*SyncApi*](doc/SyncApi.md) | [**syncCatalog**](doc/SyncApi.md#synccatalog) | **GET** /sync/catalog | Mirror the catalog (snapshot or changed-since delta)
[*SyncApi*](doc/SyncApi.md) | [**syncServer**](doc/SyncApi.md#syncserver) | **GET** /sync/server | Mirror the caller&#39;s server-side state (changed-since delta)
[*SystemApi*](doc/SystemApi.md) | [**getHealth**](doc/SystemApi.md#gethealth) | **GET** /health | Liveness and version probe
[*ToolsApi*](doc/ToolsApi.md) | [**clearFinishedToolTasks**](doc/ToolsApi.md#clearfinishedtooltasks) | **POST** /tools/tasks/clear-finished | Clear finished tasks
[*ToolsApi*](doc/ToolsApi.md) | [**deleteToolTask**](doc/ToolsApi.md#deletetooltask) | **DELETE** /tools/tasks/{taskId} | Delete a finished tool task
[*ToolsApi*](doc/ToolsApi.md) | [**getToolTask**](doc/ToolsApi.md#gettooltask) | **GET** /tools/tasks/{taskId} | Inspect a tool task
[*ToolsApi*](doc/ToolsApi.md) | [**listToolTasks**](doc/ToolsApi.md#listtooltasks) | **GET** /tools/tasks | List tool tasks
[*ToolsApi*](doc/ToolsApi.md) | [**mergeBook**](doc/ToolsApi.md#mergebook) | **POST** /books/{pid}/merge | Merge a multi-file book
[*ToolsApi*](doc/ToolsApi.md) | [**splitBook**](doc/ToolsApi.md#splitbook) | **POST** /books/{pid}/split | Split a book at its chapters
[*ToolsApi*](doc/ToolsApi.md) | [**splitCueRip**](doc/ToolsApi.md#splitcuerip) | **POST** /items/{pid}/split-cue | Split a CUE rip into real files
[*ToolsApi*](doc/ToolsApi.md) | [**streamToolTaskEvents**](doc/ToolsApi.md#streamtooltaskevents) | **GET** /tools/tasks/{taskId}/events | Stream a tool task&#39;s progress
[*UploadsApi*](doc/UploadsApi.md) | [**completeUpload**](doc/UploadsApi.md#completeupload) | **POST** /uploads/{uploadId}/complete | Finish an upload
[*UploadsApi*](doc/UploadsApi.md) | [**completeUploadBatch**](doc/UploadsApi.md#completeuploadbatch) | **POST** /uploads/batches/{batchId}/complete | Finalize an upload batch
[*UploadsApi*](doc/UploadsApi.md) | [**createAcquisition**](doc/UploadsApi.md#createacquisition) | **POST** /acquisitions | Acquire audio from a URL
[*UploadsApi*](doc/UploadsApi.md) | [**createUpload**](doc/UploadsApi.md#createupload) | **POST** /uploads | Start an upload
[*UploadsApi*](doc/UploadsApi.md) | [**createUploadBatch**](doc/UploadsApi.md#createuploadbatch) | **POST** /uploads/batches | Open an upload batch
[*UploadsApi*](doc/UploadsApi.md) | [**deleteUpload**](doc/UploadsApi.md#deleteupload) | **DELETE** /uploads/{uploadId} | Abandon an upload
[*UploadsApi*](doc/UploadsApi.md) | [**getUpload**](doc/UploadsApi.md#getupload) | **GET** /uploads/{uploadId} | Inspect an upload
[*UploadsApi*](doc/UploadsApi.md) | [**listUploads**](doc/UploadsApi.md#listuploads) | **GET** /uploads | List the caller&#39;s uploads
[*UploadsApi*](doc/UploadsApi.md) | [**putUploadData**](doc/UploadsApi.md#putuploaddata) | **PUT** /uploads/{uploadId}/data | Send upload bytes
[*UsersApi*](doc/UsersApi.md) | [**approveSignupRequest**](doc/UsersApi.md#approvesignuprequest) | **POST** /users/requests/{userId}/approve | Approve a signup request
[*UsersApi*](doc/UsersApi.md) | [**createAppPassword**](doc/UsersApi.md#createapppassword) | **POST** /users/me/app-passwords | Create an app password
[*UsersApi*](doc/UsersApi.md) | [**createInvite**](doc/UsersApi.md#createinvite) | **POST** /invites | Create an invite
[*UsersApi*](doc/UsersApi.md) | [**createUser**](doc/UsersApi.md#createuser) | **POST** /users | Create an account
[*UsersApi*](doc/UsersApi.md) | [**deleteUser**](doc/UsersApi.md#deleteuser) | **DELETE** /users/{userId} | Delete an account
[*UsersApi*](doc/UsersApi.md) | [**getPrefs**](doc/UsersApi.md#getprefs) | **GET** /users/me/prefs | Get the caller&#39;s preferences
[*UsersApi*](doc/UsersApi.md) | [**getUser**](doc/UsersApi.md#getuser) | **GET** /users/{userId} | Get one account
[*UsersApi*](doc/UsersApi.md) | [**listAppPasswords**](doc/UsersApi.md#listapppasswords) | **GET** /users/me/app-passwords | List the caller&#39;s app passwords
[*UsersApi*](doc/UsersApi.md) | [**listInvites**](doc/UsersApi.md#listinvites) | **GET** /invites | List invites
[*UsersApi*](doc/UsersApi.md) | [**listSignupRequests**](doc/UsersApi.md#listsignuprequests) | **GET** /users/requests | List pending signup requests
[*UsersApi*](doc/UsersApi.md) | [**listUsers**](doc/UsersApi.md#listusers) | **GET** /users | List accounts
[*UsersApi*](doc/UsersApi.md) | [**putPrefs**](doc/UsersApi.md#putprefs) | **PUT** /users/me/prefs | Replace the caller&#39;s preferences
[*UsersApi*](doc/UsersApi.md) | [**rejectSignupRequest**](doc/UsersApi.md#rejectsignuprequest) | **POST** /users/requests/{userId}/reject | Reject a signup request
[*UsersApi*](doc/UsersApi.md) | [**revokeAppPassword**](doc/UsersApi.md#revokeapppassword) | **DELETE** /users/me/app-passwords/{appPasswordId} | Revoke an app password
[*UsersApi*](doc/UsersApi.md) | [**revokeInvite**](doc/UsersApi.md#revokeinvite) | **DELETE** /invites/{inviteId} | Revoke an invite
[*UsersApi*](doc/UsersApi.md) | [**revokeUserSessions**](doc/UsersApi.md#revokeusersessions) | **DELETE** /users/{userId}/sessions | Revoke all of an account&#39;s sessions
[*UsersApi*](doc/UsersApi.md) | [**setPassword**](doc/UsersApi.md#setpassword) | **PUT** /users/{userId}/password | Set an account&#39;s password
[*UsersApi*](doc/UsersApi.md) | [**updateUser**](doc/UsersApi.md#updateuser) | **PATCH** /users/{userId} | Update an account


## Documentation For Models

 - [AcquisitionFormat](doc/AcquisitionFormat.md)
 - [AcquisitionRequest](doc/AcquisitionRequest.md)
 - [AdminSettings](doc/AdminSettings.md)
 - [AlbumDetail](doc/AlbumDetail.md)
 - [AppPassword](doc/AppPassword.md)
 - [AppPasswordCreate](doc/AppPasswordCreate.md)
 - [AppPasswordCreated](doc/AppPasswordCreated.md)
 - [AppPasswordList](doc/AppPasswordList.md)
 - [ArtRole](doc/ArtRole.md)
 - [ArtRoleInfo](doc/ArtRoleInfo.md)
 - [ArtRoles](doc/ArtRoles.md)
 - [AuditEvent](doc/AuditEvent.md)
 - [AuditEventPage](doc/AuditEventPage.md)
 - [Backup](doc/Backup.md)
 - [BackupList](doc/BackupList.md)
 - [BookDetail](doc/BookDetail.md)
 - [BookMergeRequest](doc/BookMergeRequest.md)
 - [BookPart](doc/BookPart.md)
 - [BookResume](doc/BookResume.md)
 - [BookSettings](doc/BookSettings.md)
 - [BookSplitRequest](doc/BookSplitRequest.md)
 - [Bookmark](doc/Bookmark.md)
 - [BookmarkCreate](doc/BookmarkCreate.md)
 - [BookmarkList](doc/BookmarkList.md)
 - [BootstrapRequest](doc/BootstrapRequest.md)
 - [BootstrapStatus](doc/BootstrapStatus.md)
 - [BulkEdit](doc/BulkEdit.md)
 - [BulkEditResult](doc/BulkEditResult.md)
 - [CandidateComponent](doc/CandidateComponent.md)
 - [CandidatePairing](doc/CandidatePairing.md)
 - [CandidateSummary](doc/CandidateSummary.md)
 - [CastPreflight](doc/CastPreflight.md)
 - [CastPreflightBase](doc/CastPreflightBase.md)
 - [CatalogSyncEntry](doc/CatalogSyncEntry.md)
 - [CatalogSyncPage](doc/CatalogSyncPage.md)
 - [ChapterMark](doc/ChapterMark.md)
 - [ChaptersEdit](doc/ChaptersEdit.md)
 - [CoverageCount](doc/CoverageCount.md)
 - [Credit](doc/Credit.md)
 - [CreditsEdit](doc/CreditsEdit.md)
 - [CueSplitRequest](doc/CueSplitRequest.md)
 - [CustomTag](doc/CustomTag.md)
 - [DeleteItemsRequest](doc/DeleteItemsRequest.md)
 - [DeleteItemsResult](doc/DeleteItemsResult.md)
 - [DeletePlanEntry](doc/DeletePlanEntry.md)
 - [DeviceSession](doc/DeviceSession.md)
 - [DiagnosticCount](doc/DiagnosticCount.md)
 - [DiagnosticSummary](doc/DiagnosticSummary.md)
 - [DiscoveryList](doc/DiscoveryList.md)
 - [DownloadFile](doc/DownloadFile.md)
 - [DownloadInfo](doc/DownloadInfo.md)
 - [DuplicateEntity](doc/DuplicateEntity.md)
 - [DuplicateGroup](doc/DuplicateGroup.md)
 - [DuplicateGroups](doc/DuplicateGroups.md)
 - [DuplicateWarning](doc/DuplicateWarning.md)
 - [EditableField](doc/EditableField.md)
 - [EmbeddingIngestResult](doc/EmbeddingIngestResult.md)
 - [EmbeddingReport](doc/EmbeddingReport.md)
 - [EmbeddingUpload](doc/EmbeddingUpload.md)
 - [EnrichItemRequest](doc/EnrichItemRequest.md)
 - [EnrichItemResult](doc/EnrichItemResult.md)
 - [EnrichmentCoverage](doc/EnrichmentCoverage.md)
 - [EnrichmentLastRun](doc/EnrichmentLastRun.md)
 - [EnrichmentProvider](doc/EnrichmentProvider.md)
 - [EnrichmentRunRequest](doc/EnrichmentRunRequest.md)
 - [EnrichmentRunResult](doc/EnrichmentRunResult.md)
 - [EnrichmentStatus](doc/EnrichmentStatus.md)
 - [EntityCard](doc/EntityCard.md)
 - [EntityCardList](doc/EntityCardList.md)
 - [EntityCardQuery](doc/EntityCardQuery.md)
 - [EntityCuratedField](doc/EntityCuratedField.md)
 - [EntityCuration](doc/EntityCuration.md)
 - [EntityEdit](doc/EntityEdit.md)
 - [EntityPlayState](doc/EntityPlayState.md)
 - [EntityTypeFields](doc/EntityTypeFields.md)
 - [Episode](doc/Episode.md)
 - [EpisodeFilter](doc/EpisodeFilter.md)
 - [EpisodePage](doc/EpisodePage.md)
 - [EpisodeSummary](doc/EpisodeSummary.md)
 - [Error](doc/Error.md)
 - [FacetBucket](doc/FacetBucket.md)
 - [FacetPage](doc/FacetPage.md)
 - [FacetSort](doc/FacetSort.md)
 - [FeedPerson](doc/FeedPerson.md)
 - [FieldProvenance](doc/FieldProvenance.md)
 - [FileDiagnostic](doc/FileDiagnostic.md)
 - [FileDiagnosticPage](doc/FileDiagnosticPage.md)
 - [GenreNode](doc/GenreNode.md)
 - [GenreNormalizeRequest](doc/GenreNormalizeRequest.md)
 - [GenreTree](doc/GenreTree.md)
 - [GenreTreeUpdate](doc/GenreTreeUpdate.md)
 - [Health](doc/Health.md)
 - [HealthFixRequest](doc/HealthFixRequest.md)
 - [HealthFixResult](doc/HealthFixResult.md)
 - [HealthIssue](doc/HealthIssue.md)
 - [HealthIssuePage](doc/HealthIssuePage.md)
 - [HealthRuleCount](doc/HealthRuleCount.md)
 - [HealthSummary](doc/HealthSummary.md)
 - [HeatmapDay](doc/HeatmapDay.md)
 - [InstantMix](doc/InstantMix.md)
 - [InstantMixRequest](doc/InstantMixRequest.md)
 - [Invite](doc/Invite.md)
 - [InviteCreate](doc/InviteCreate.md)
 - [InviteCreated](doc/InviteCreated.md)
 - [InviteList](doc/InviteList.md)
 - [Item](doc/Item.md)
 - [ItemMetadata](doc/ItemMetadata.md)
 - [ItemPage](doc/ItemPage.md)
 - [ItemSummary](doc/ItemSummary.md)
 - [Job](doc/Job.md)
 - [JobList](doc/JobList.md)
 - [KindFields](doc/KindFields.md)
 - [LastfmConnectStart](doc/LastfmConnectStart.md)
 - [Libraries](doc/Libraries.md)
 - [LibraryAccess](doc/LibraryAccess.md)
 - [LibraryCreate](doc/LibraryCreate.md)
 - [LibraryCreated](doc/LibraryCreated.md)
 - [LibraryMatching](doc/LibraryMatching.md)
 - [LibraryReadOnly](doc/LibraryReadOnly.md)
 - [LinkedIdentity](doc/LinkedIdentity.md)
 - [ListenBrainzConnect](doc/ListenBrainzConnect.md)
 - [ListenIngestResult](doc/ListenIngestResult.md)
 - [ListenLogEntry](doc/ListenLogEntry.md)
 - [ListenLogPage](doc/ListenLogPage.md)
 - [ListenReport](doc/ListenReport.md)
 - [ListenSession](doc/ListenSession.md)
 - [ListeningBucket](doc/ListeningBucket.md)
 - [ListeningHeatmap](doc/ListeningHeatmap.md)
 - [ListeningStats](doc/ListeningStats.md)
 - [LocksEdit](doc/LocksEdit.md)
 - [LocksResult](doc/LocksResult.md)
 - [LoginRequest](doc/LoginRequest.md)
 - [LoginResponse](doc/LoginResponse.md)
 - [Lyrics](doc/Lyrics.md)
 - [LyricsEdit](doc/LyricsEdit.md)
 - [LyricsState](doc/LyricsState.md)
 - [M3uImport](doc/M3uImport.md)
 - [M3uImportResult](doc/M3uImportResult.md)
 - [MediaType](doc/MediaType.md)
 - [MediaTypeListening](doc/MediaTypeListening.md)
 - [MergeRequest](doc/MergeRequest.md)
 - [MergeResult](doc/MergeResult.md)
 - [MetadataEdit](doc/MetadataEdit.md)
 - [MetadataEditResult](doc/MetadataEditResult.md)
 - [MetadataFields](doc/MetadataFields.md)
 - [MigrationCreate](doc/MigrationCreate.md)
 - [MigrationOptions](doc/MigrationOptions.md)
 - [MixBasis](doc/MixBasis.md)
 - [ModelLibrary](doc/ModelLibrary.md)
 - [MonthListening](doc/MonthListening.md)
 - [NotificationEvent](doc/NotificationEvent.md)
 - [NotificationEventList](doc/NotificationEventList.md)
 - [NotificationScope](doc/NotificationScope.md)
 - [NotificationTarget](doc/NotificationTarget.md)
 - [NotificationTargetCreate](doc/NotificationTargetCreate.md)
 - [NotificationTargetKind](doc/NotificationTargetKind.md)
 - [NotificationTargetList](doc/NotificationTargetList.md)
 - [NotificationTargetUpdate](doc/NotificationTargetUpdate.md)
 - [OidcExchangeRequest](doc/OidcExchangeRequest.md)
 - [OidcProvider](doc/OidcProvider.md)
 - [OidcProviders](doc/OidcProviders.md)
 - [OpmlImport](doc/OpmlImport.md)
 - [OpmlImportEntry](doc/OpmlImportEntry.md)
 - [OpmlImportResult](doc/OpmlImportResult.md)
 - [OrganizeAction](doc/OrganizeAction.md)
 - [OrganizeFailure](doc/OrganizeFailure.md)
 - [OrganizePlan](doc/OrganizePlan.md)
 - [OrganizeProfile](doc/OrganizeProfile.md)
 - [OrganizeProfiles](doc/OrganizeProfiles.md)
 - [OrganizeReport](doc/OrganizeReport.md)
 - [OrganizeRequest](doc/OrganizeRequest.md)
 - [PasswordChange](doc/PasswordChange.md)
 - [Permissions](doc/Permissions.md)
 - [PlayInfo](doc/PlayInfo.md)
 - [PlayState](doc/PlayState.md)
 - [PlayStateList](doc/PlayStateList.md)
 - [PlayStateQuery](doc/PlayStateQuery.md)
 - [PlayStateUpdate](doc/PlayStateUpdate.md)
 - [PlaybackSession](doc/PlaybackSession.md)
 - [PlaybackSessionCreate](doc/PlaybackSessionCreate.md)
 - [PlaybackSessionEntry](doc/PlaybackSessionEntry.md)
 - [PlaybackSessionHistoryEntry](doc/PlaybackSessionHistoryEntry.md)
 - [PlaybackSessionHistoryList](doc/PlaybackSessionHistoryList.md)
 - [PlaybackSessionList](doc/PlaybackSessionList.md)
 - [PlaybackSessionTransfer](doc/PlaybackSessionTransfer.md)
 - [PlayedUpdate](doc/PlayedUpdate.md)
 - [PlayerEndpoint](doc/PlayerEndpoint.md)
 - [PlayerEndpointList](doc/PlayerEndpointList.md)
 - [Playlist](doc/Playlist.md)
 - [PlaylistCreate](doc/PlaylistCreate.md)
 - [PlaylistEntry](doc/PlaylistEntry.md)
 - [PlaylistImportMiss](doc/PlaylistImportMiss.md)
 - [PlaylistImportRequest](doc/PlaylistImportRequest.md)
 - [PlaylistImportResult](doc/PlaylistImportResult.md)
 - [PlaylistItemsPage](doc/PlaylistItemsPage.md)
 - [PlaylistItemsUpdate](doc/PlaylistItemsUpdate.md)
 - [PlaylistPage](doc/PlaylistPage.md)
 - [PlaylistPreview](doc/PlaylistPreview.md)
 - [PlaylistUpdate](doc/PlaylistUpdate.md)
 - [PodcastDetail](doc/PodcastDetail.md)
 - [PodcastDirectoryEntry](doc/PodcastDirectoryEntry.md)
 - [PodcastDirectoryResults](doc/PodcastDirectoryResults.md)
 - [PodcastFunding](doc/PodcastFunding.md)
 - [PodcastShow](doc/PodcastShow.md)
 - [PortablePlaylist](doc/PortablePlaylist.md)
 - [PortableRef](doc/PortableRef.md)
 - [Prefs](doc/Prefs.md)
 - [PushRegistration](doc/PushRegistration.md)
 - [PushRegistrationCreate](doc/PushRegistrationCreate.md)
 - [PushRegistrationList](doc/PushRegistrationList.md)
 - [RadioDirectoryEntry](doc/RadioDirectoryEntry.md)
 - [RadioDirectoryResults](doc/RadioDirectoryResults.md)
 - [RadioPlayInfo](doc/RadioPlayInfo.md)
 - [RadioSavedSong](doc/RadioSavedSong.md)
 - [RadioSavedSongCreate](doc/RadioSavedSongCreate.md)
 - [RadioSavedSongPage](doc/RadioSavedSongPage.md)
 - [RadioStation](doc/RadioStation.md)
 - [RadioStationEdit](doc/RadioStationEdit.md)
 - [RadioStationList](doc/RadioStationList.md)
 - [RatingUpdate](doc/RatingUpdate.md)
 - [RefreshResult](doc/RefreshResult.md)
 - [RejectedEmbedding](doc/RejectedEmbedding.md)
 - [RejectedListen](doc/RejectedListen.md)
 - [ReleaseStatusEdit](doc/ReleaseStatusEdit.md)
 - [RematchResult](doc/RematchResult.md)
 - [ResolveRungCounts](doc/ResolveRungCounts.md)
 - [RestorePlan](doc/RestorePlan.md)
 - [ReviewBulkDecision](doc/ReviewBulkDecision.md)
 - [ReviewBulkOutcome](doc/ReviewBulkOutcome.md)
 - [ReviewBulkResult](doc/ReviewBulkResult.md)
 - [ReviewCandidate](doc/ReviewCandidate.md)
 - [ReviewDecideResult](doc/ReviewDecideResult.md)
 - [ReviewDecision](doc/ReviewDecision.md)
 - [ReviewEntry](doc/ReviewEntry.md)
 - [ReviewEntryDetail](doc/ReviewEntryDetail.md)
 - [ReviewEntryPage](doc/ReviewEntryPage.md)
 - [ReviewIdentifyRequest](doc/ReviewIdentifyRequest.md)
 - [ReviewStats](doc/ReviewStats.md)
 - [ReviewTrack](doc/ReviewTrack.md)
 - [Role](doc/Role.md)
 - [RuleField](doc/RuleField.md)
 - [RuleFields](doc/RuleFields.md)
 - [RuleNode](doc/RuleNode.md)
 - [RuleSort](doc/RuleSort.md)
 - [RuleTagKey](doc/RuleTagKey.md)
 - [Schedule](doc/Schedule.md)
 - [ScheduleKind](doc/ScheduleKind.md)
 - [ScheduleList](doc/ScheduleList.md)
 - [SchedulePut](doc/SchedulePut.md)
 - [Scrobbler](doc/Scrobbler.md)
 - [ScrobblerList](doc/ScrobblerList.md)
 - [ScrobblingAdminConfig](doc/ScrobblingAdminConfig.md)
 - [ScrobblingAdminConfigPut](doc/ScrobblingAdminConfigPut.md)
 - [SealedCasualty](doc/SealedCasualty.md)
 - [SearchHit](doc/SearchHit.md)
 - [SearchResults](doc/SearchResults.md)
 - [ServerSyncEvent](doc/ServerSyncEvent.md)
 - [ServerSyncPage](doc/ServerSyncPage.md)
 - [ServerYearInReview](doc/ServerYearInReview.md)
 - [SessionInfo](doc/SessionInfo.md)
 - [SessionList](doc/SessionList.md)
 - [SessionRename](doc/SessionRename.md)
 - [Share](doc/Share.md)
 - [ShareCreate](doc/ShareCreate.md)
 - [SharePage](doc/SharePage.md)
 - [SignupApproval](doc/SignupApproval.md)
 - [SignupRequest](doc/SignupRequest.md)
 - [SignupResult](doc/SignupResult.md)
 - [SimilarTracks](doc/SimilarTracks.md)
 - [SimilarityStatus](doc/SimilarityStatus.md)
 - [SimilarityWorkItem](doc/SimilarityWorkItem.md)
 - [SimilarityWorkPage](doc/SimilarityWorkPage.md)
 - [SkipMap](doc/SkipMap.md)
 - [SkipSpan](doc/SkipSpan.md)
 - [SmartRule](doc/SmartRule.md)
 - [SonicPath](doc/SonicPath.md)
 - [Soundbite](doc/Soundbite.md)
 - [StarUpdate](doc/StarUpdate.md)
 - [StarredEntities](doc/StarredEntities.md)
 - [SubscribeRequest](doc/SubscribeRequest.md)
 - [Subscription](doc/Subscription.md)
 - [SubscriptionPage](doc/SubscriptionPage.md)
 - [SubscriptionSettings](doc/SubscriptionSettings.md)
 - [SyncedLine](doc/SyncedLine.md)
 - [TagEdit](doc/TagEdit.md)
 - [TagEditResult](doc/TagEditResult.md)
 - [TagRule](doc/TagRule.md)
 - [TimelineBoundary](doc/TimelineBoundary.md)
 - [TimelineCreate](doc/TimelineCreate.md)
 - [TimelineInfo](doc/TimelineInfo.md)
 - [ToolTask](doc/ToolTask.md)
 - [ToolTaskPage](doc/ToolTaskPage.md)
 - [ToolTasksCleared](doc/ToolTasksCleared.md)
 - [TopEntry](doc/TopEntry.md)
 - [TopList](doc/TopList.md)
 - [TranscodingActivity](doc/TranscodingActivity.md)
 - [TranscodingLimits](doc/TranscodingLimits.md)
 - [Transcript](doc/Transcript.md)
 - [TranscriptCue](doc/TranscriptCue.md)
 - [TrashEmptyResult](doc/TrashEmptyResult.md)
 - [TrashEntry](doc/TrashEntry.md)
 - [TrashList](doc/TrashList.md)
 - [TrashPurgeResult](doc/TrashPurgeResult.md)
 - [UpgradeGroup](doc/UpgradeGroup.md)
 - [UpgradeGroups](doc/UpgradeGroups.md)
 - [UpgradeMember](doc/UpgradeMember.md)
 - [UpgradeResolveRequest](doc/UpgradeResolveRequest.md)
 - [UpgradeResolveResult](doc/UpgradeResolveResult.md)
 - [Upload](doc/Upload.md)
 - [UploadBatch](doc/UploadBatch.md)
 - [UploadBatchCreate](doc/UploadBatchCreate.md)
 - [UploadCreate](doc/UploadCreate.md)
 - [UploadGrouping](doc/UploadGrouping.md)
 - [UploadPage](doc/UploadPage.md)
 - [UploadQuota](doc/UploadQuota.md)
 - [User](doc/User.md)
 - [UserAccount](doc/UserAccount.md)
 - [UserCreate](doc/UserCreate.md)
 - [UserPage](doc/UserPage.md)
 - [UserUpdate](doc/UserUpdate.md)
 - [Waveform](doc/Waveform.md)
 - [WriteBackFailure](doc/WriteBackFailure.md)
 - [WriteBackIssue](doc/WriteBackIssue.md)
 - [WsAckFrame](doc/WsAckFrame.md)
 - [WsCommandFrame](doc/WsCommandFrame.md)
 - [WsCommandResultFrame](doc/WsCommandResultFrame.md)
 - [WsEndpointCommandFrame](doc/WsEndpointCommandFrame.md)
 - [WsErrorFrame](doc/WsErrorFrame.md)
 - [WsEventFrame](doc/WsEventFrame.md)
 - [WsPingFrame](doc/WsPingFrame.md)
 - [WsPongFrame](doc/WsPongFrame.md)
 - [WsRegisterEndpointFrame](doc/WsRegisterEndpointFrame.md)
 - [WsSessionFrame](doc/WsSessionFrame.md)
 - [WsSessionReportFrame](doc/WsSessionReportFrame.md)
 - [WsSubscribeFrame](doc/WsSubscribeFrame.md)
 - [WsWatchFrame](doc/WsWatchFrame.md)
 - [YearInReview](doc/YearInReview.md)


## Documentation For Authorization


Authentication schemes defined for the API:
### cookieAuth

- **Type**: API key
- **API key parameter name**: waxdeck_session
- **Location**: 

### bearerAuth

- **Type**: HTTP Bearer Token authentication

### workerAuth

- **Type**: HTTP Bearer Token authentication


## Author



