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
queue), server notifications (an Apprise relay configured by
administrators), UnifiedPush registrations for push-transported
events, and multi-device playback control (player endpoints,
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
CUE rip splitting, and library enrichment status and dispatch.
The shapes (keyset pagination, typed PIDs, the structured error
model, relative media URLs) are load-bearing from day one.

Conventions:
- All endpoints live under `/api/v1` (this document's `servers` entry).
- Identifiers (`pid`) are type-prefixed ULIDs (`tr-` track, `al-` album,
  `ar-` artist, `pc-` podcast, `ep-` episode, `bk-` audiobook, `jb-` job,
  `lb-` library, `us-` user, `se-` session, `ap-` app password,
  `pl-` playlist, `rs-` radio station, `pr-` push registration,
  `pe-` player endpoint, `ps-` playback session, `rv-` review
  entry, `up-` upload, `tk-` tool task).
- List endpoints use opaque keyset cursors (`cursor` in, `nextCursor` out),
  never offsets.
- Errors are always the `Error` schema. `code` is a stable machine-readable
  string; currently defined codes: `invalid-request`, `unauthenticated`,
  `forbidden`, `not-found`, `conflict`, `internal`, `rate-limited` (too
  many attempts; retry later), `stream-stale` (a minted media URL no longer
  matches the file on disk, a metadata-only retag included since the
  pin is byte identity; re-request the info endpoint that minted it), `catalog-maintenance`
  (the catalog is temporarily handed to a maintenance operation; retry
  shortly), `sync-reset` (a sync cursor predates the retained change
  history; drop the local mirror and re-mirror from a fresh snapshot),
  `feed-unreachable` (an upstream feed could not be fetched or parsed;
  the feed's own server answered an error, timed out, or returned
  something that is not a feed), `source-unavailable` (the request
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
  upload would exceed the caller's storage quota), `field-locked`
  (the edit targets a locked metadata field and did not set
  `force`), and `unsupported-format` (the uploaded file's format
  is not accepted by this server).
  New codes may appear; clients must treat unknown codes as opaque.
- Media URLs returned by the API (e.g. `PlayInfo.url`) are relative to the
  server origin, the same origin that serves this API and the web UI.
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
  Replacing a smart playlist's rule reissues its pid: the update
  response carries the new pid with `previousPid` set to the old
  one, the old pid stops resolving, and `createdAt` restarts. The
  caller's server sync stream carries exactly two `playlist`
  events for a reissue, the old pid absent and the new pid
  present (the new pid's hydrated playlist carries
  `previousPid`), so mirrors relink instead of seeing an
  unrelated delete and create. A client whose rule-replace
  response was lost recovers by re-listing and matching
  `previousPid`. Clients treat the pid as stable only between
  rule changes.
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

- API version: 0.8.0
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
final String pid = pid_example; // String | Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).

try {
    final response = await api.getJob(pid);
    print(response);
} catch on DioException (e) {
    print("Exception when calling AdminApi->getJob: $e\n");
}

```

## Documentation for API Endpoints

All URIs are relative to */api/v1*

Class | Method | HTTP request | Description
------------ | ------------- | ------------- | -------------
[*AdminApi*](doc/AdminApi.md) | [**getJob**](doc/AdminApi.md#getjob) | **GET** /jobs/{pid} | Get one job&#39;s state
[*AdminApi*](doc/AdminApi.md) | [**listLibraries**](doc/AdminApi.md#listlibraries) | **GET** /libraries | List libraries
[*AdminApi*](doc/AdminApi.md) | [**rescanLibrary**](doc/AdminApi.md#rescanlibrary) | **POST** /library/rescan | Start a library rescan
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
[*AuthApi*](doc/AuthApi.md) | [**revokeSession**](doc/AuthApi.md#revokesession) | **DELETE** /auth/sessions/{sessionId} | Revoke one of the caller&#39;s sessions
[*AuthApi*](doc/AuthApi.md) | [**startOidc**](doc/AuthApi.md#startoidc) | **GET** /auth/oidc/start | Start an OIDC login
[*BooksApi*](doc/BooksApi.md) | [**getBook**](doc/BooksApi.md#getbook) | **GET** /books/{pid} | Get one audiobook&#39;s detail
[*BooksApi*](doc/BooksApi.md) | [**getBookResume**](doc/BooksApi.md#getbookresume) | **GET** /books/{pid}/resume | Where the caller left off in a book
[*BooksApi*](doc/BooksApi.md) | [**putBookSettings**](doc/BooksApi.md#putbooksettings) | **PUT** /books/{pid}/settings | Replace the caller&#39;s playback settings for a book
[*EnrichmentApi*](doc/EnrichmentApi.md) | [**getEnrichmentStatus**](doc/EnrichmentApi.md#getenrichmentstatus) | **GET** /library/enrichment | Enrichment status and coverage
[*EnrichmentApi*](doc/EnrichmentApi.md) | [**runEnrichment**](doc/EnrichmentApi.md#runenrichment) | **POST** /library/enrichment/run | Run a whole-library enrichment pass
[*HealthApi*](doc/HealthApi.md) | [**fixHealthIssues**](doc/HealthApi.md#fixhealthissues) | **POST** /library/health/fix | Bulk-fix a health rule
[*HealthApi*](doc/HealthApi.md) | [**getLibraryHealth**](doc/HealthApi.md#getlibraryhealth) | **GET** /library/health | Metadata health summary
[*HealthApi*](doc/HealthApi.md) | [**listDuplicates**](doc/HealthApi.md#listduplicates) | **GET** /library/duplicates | List duplicate entities
[*HealthApi*](doc/HealthApi.md) | [**listHealthIssues**](doc/HealthApi.md#listhealthissues) | **GET** /library/health/issues | List items failing health rules
[*HealthApi*](doc/HealthApi.md) | [**listUpgrades**](doc/HealthApi.md#listupgrades) | **GET** /library/upgrades | List quality upgrade groups
[*HealthApi*](doc/HealthApi.md) | [**mergeDuplicates**](doc/HealthApi.md#mergeduplicates) | **POST** /library/duplicates/merge | Merge duplicate entities
[*HealthApi*](doc/HealthApi.md) | [**resolveUpgrade**](doc/HealthApi.md#resolveupgrade) | **POST** /library/upgrades/resolve | Keep the best encoding
[*HealthApi*](doc/HealthApi.md) | [**sweepLibraryHealth**](doc/HealthApi.md#sweeplibraryhealth) | **POST** /library/health/sweep | Re-sweep health now
[*LibraryApi*](doc/LibraryApi.md) | [**browseList**](doc/LibraryApi.md#browselist) | **GET** /library/browse | Browse a discovery list
[*LibraryApi*](doc/LibraryApi.md) | [**getItem**](doc/LibraryApi.md#getitem) | **GET** /items/{pid} | Get one item&#39;s detail
[*LibraryApi*](doc/LibraryApi.md) | [**getItemArt**](doc/LibraryApi.md#getitemart) | **GET** /items/{pid}/art | Get artwork
[*LibraryApi*](doc/LibraryApi.md) | [**getItemLyrics**](doc/LibraryApi.md#getitemlyrics) | **GET** /items/{pid}/lyrics | Get an item&#39;s lyrics
[*LibraryApi*](doc/LibraryApi.md) | [**listItems**](doc/LibraryApi.md#listitems) | **GET** /library/items | Browse library items
[*LibraryApi*](doc/LibraryApi.md) | [**search**](doc/LibraryApi.md#search) | **GET** /library/search | Search the library
[*MetadataApi*](doc/MetadataApi.md) | [**bulkEditMetadata**](doc/MetadataApi.md#bulkeditmetadata) | **POST** /items/bulk-edit | Edit fields on many items
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
[*NotificationsApi*](doc/NotificationsApi.md) | [**createPushRegistration**](doc/NotificationsApi.md#createpushregistration) | **POST** /users/me/push-registrations | Register a UnifiedPush endpoint
[*NotificationsApi*](doc/NotificationsApi.md) | [**deleteAllPushRegistrations**](doc/NotificationsApi.md#deleteallpushregistrations) | **DELETE** /users/me/push-registrations | Remove all of the caller&#39;s push registrations
[*NotificationsApi*](doc/NotificationsApi.md) | [**deletePushRegistration**](doc/NotificationsApi.md#deletepushregistration) | **DELETE** /users/me/push-registrations/{registrationId} | Remove a push registration
[*NotificationsApi*](doc/NotificationsApi.md) | [**getNotificationConfig**](doc/NotificationsApi.md#getnotificationconfig) | **GET** /admin/notifications | Read the notification configuration
[*NotificationsApi*](doc/NotificationsApi.md) | [**listPushRegistrations**](doc/NotificationsApi.md#listpushregistrations) | **GET** /users/me/push-registrations | List the caller&#39;s push registrations
[*NotificationsApi*](doc/NotificationsApi.md) | [**putNotificationConfig**](doc/NotificationsApi.md#putnotificationconfig) | **PUT** /admin/notifications | Replace the notification configuration
[*NotificationsApi*](doc/NotificationsApi.md) | [**testNotifications**](doc/NotificationsApi.md#testnotifications) | **POST** /admin/notifications | Send a test notification
[*OrganizeApi*](doc/OrganizeApi.md) | [**applyOrganize**](doc/OrganizeApi.md#applyorganize) | **POST** /organize/apply | Apply an organize pass
[*OrganizeApi*](doc/OrganizeApi.md) | [**listOrganizeProfiles**](doc/OrganizeApi.md#listorganizeprofiles) | **GET** /organize/profiles | List organize profiles
[*OrganizeApi*](doc/OrganizeApi.md) | [**previewOrganize**](doc/OrganizeApi.md#previeworganize) | **POST** /organize/preview | Dry-run an organize pass
[*PlaybackApi*](doc/PlaybackApi.md) | [**getDownloadInfo**](doc/PlaybackApi.md#getdownloadinfo) | **GET** /items/{pid}/download-info | Resolve an offline download for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getPlayInfo**](doc/PlaybackApi.md#getplayinfo) | **GET** /items/{pid}/play-info | Resolve a playable stream for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getPlayState**](doc/PlaybackApi.md#getplaystate) | **GET** /items/{pid}/play-state | Get the caller&#39;s playback state for an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**getSkipMap**](doc/PlaybackApi.md#getskipmap) | **GET** /items/{pid}/skip-map | Get an item&#39;s silence skip map
[*PlaybackApi*](doc/PlaybackApi.md) | [**listPlayStates**](doc/PlaybackApi.md#listplaystates) | **POST** /play-states | Read the caller&#39;s playback state for many items
[*PlaybackApi*](doc/PlaybackApi.md) | [**putPlayState**](doc/PlaybackApi.md#putplaystate) | **PUT** /items/{pid}/play-state | Checkpoint the caller&#39;s playback position
[*PlaybackApi*](doc/PlaybackApi.md) | [**reportListens**](doc/PlaybackApi.md#reportlistens) | **POST** /listens | Report listen sessions
[*PlaybackApi*](doc/PlaybackApi.md) | [**setRating**](doc/PlaybackApi.md#setrating) | **PUT** /items/{pid}/rating | Rate an item
[*PlaybackApi*](doc/PlaybackApi.md) | [**setStar**](doc/PlaybackApi.md#setstar) | **PUT** /items/{pid}/star | Star or unstar an item
[*PlayerApi*](doc/PlayerApi.md) | [**createPlaybackSession**](doc/PlayerApi.md#createplaybacksession) | **POST** /player/sessions | Start playback on an endpoint
[*PlayerApi*](doc/PlayerApi.md) | [**createQueueTimeline**](doc/PlayerApi.md#createqueuetimeline) | **POST** /player/timeline | Mint a gapless queue timeline
[*PlayerApi*](doc/PlayerApi.md) | [**deletePlaybackSession**](doc/PlayerApi.md#deleteplaybacksession) | **DELETE** /player/sessions/{sessionId} | End a playback session
[*PlayerApi*](doc/PlayerApi.md) | [**getCastPreflight**](doc/PlayerApi.md#getcastpreflight) | **GET** /player/cast/preflight | Check cast reachability
[*PlayerApi*](doc/PlayerApi.md) | [**getPlaybackSession**](doc/PlayerApi.md#getplaybacksession) | **GET** /player/sessions/{sessionId} | Get one playback session
[*PlayerApi*](doc/PlayerApi.md) | [**listPlaybackSessions**](doc/PlayerApi.md#listplaybacksessions) | **GET** /player/sessions | List playback sessions
[*PlayerApi*](doc/PlayerApi.md) | [**listPlayerEndpoints**](doc/PlayerApi.md#listplayerendpoints) | **GET** /player/endpoints | List player endpoints
[*PlayerApi*](doc/PlayerApi.md) | [**transferPlaybackSession**](doc/PlayerApi.md#transferplaybacksession) | **POST** /player/sessions/{sessionId}/transfer | Transfer a session to another endpoint
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**addPlaylistItems**](doc/PlaylistsApi.md#addplaylistitems) | **POST** /playlists/{pid}/items | Append items to a static playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**createPlaylist**](doc/PlaylistsApi.md#createplaylist) | **POST** /playlists | Create a playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**deletePlaylist**](doc/PlaylistsApi.md#deleteplaylist) | **DELETE** /playlists/{pid} | Delete a playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**exportPlaylistM3u**](doc/PlaylistsApi.md#exportplaylistm3u) | **GET** /playlists/{pid}/m3u | Export a playlist as M3U8
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**getPlaylist**](doc/PlaylistsApi.md#getplaylist) | **GET** /playlists/{pid} | Get one playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**getRuleFields**](doc/PlaylistsApi.md#getrulefields) | **GET** /playlists/rule-fields | Discover smart rule fields
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**importPlaylistM3u**](doc/PlaylistsApi.md#importplaylistm3u) | **POST** /playlists/m3u | Import an M3U8 playlist
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**listPlaylistItems**](doc/PlaylistsApi.md#listplaylistitems) | **GET** /playlists/{pid}/items | List a playlist&#39;s items
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**listPlaylists**](doc/PlaylistsApi.md#listplaylists) | **GET** /playlists | List playlists visible to the caller
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**previewSmartRule**](doc/PlaylistsApi.md#previewsmartrule) | **POST** /playlists/preview | Preview a smart rule
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**removePlaylistItemAt**](doc/PlaylistsApi.md#removeplaylistitemat) | **DELETE** /playlists/{pid}/items/{position} | Remove one member by position
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**replacePlaylistItems**](doc/PlaylistsApi.md#replaceplaylistitems) | **PUT** /playlists/{pid}/items | Replace a static playlist&#39;s members
[*PlaylistsApi*](doc/PlaylistsApi.md) | [**updatePlaylist**](doc/PlaylistsApi.md#updateplaylist) | **PATCH** /playlists/{pid} | Update a playlist
[*PodcastsApi*](doc/PodcastsApi.md) | [**exportOpml**](doc/PodcastsApi.md#exportopml) | **GET** /podcasts/opml | Export the caller&#39;s subscriptions as OPML
[*PodcastsApi*](doc/PodcastsApi.md) | [**fetchEpisode**](doc/PodcastsApi.md#fetchepisode) | **POST** /episodes/{pid}/fetch | Fetch an episode&#39;s audio to the server
[*PodcastsApi*](doc/PodcastsApi.md) | [**getEpisode**](doc/PodcastsApi.md#getepisode) | **GET** /episodes/{pid} | Get one episode&#39;s detail
[*PodcastsApi*](doc/PodcastsApi.md) | [**getEpisodeTranscript**](doc/PodcastsApi.md#getepisodetranscript) | **GET** /episodes/{pid}/transcript | Get an episode&#39;s transcript
[*PodcastsApi*](doc/PodcastsApi.md) | [**getPodcast**](doc/PodcastsApi.md#getpodcast) | **GET** /podcasts/{pid} | Get one show with the caller&#39;s subscription state
[*PodcastsApi*](doc/PodcastsApi.md) | [**importOpml**](doc/PodcastsApi.md#importopml) | **POST** /podcasts/opml | Import subscriptions from OPML
[*PodcastsApi*](doc/PodcastsApi.md) | [**listEpisodes**](doc/PodcastsApi.md#listepisodes) | **GET** /podcasts/{pid}/episodes | List a show&#39;s episodes
[*PodcastsApi*](doc/PodcastsApi.md) | [**listSubscriptions**](doc/PodcastsApi.md#listsubscriptions) | **GET** /podcasts | List the caller&#39;s podcast subscriptions
[*PodcastsApi*](doc/PodcastsApi.md) | [**putSubscriptionSettings**](doc/PodcastsApi.md#putsubscriptionsettings) | **PUT** /podcasts/{pid}/settings | Replace the caller&#39;s settings for a subscription
[*PodcastsApi*](doc/PodcastsApi.md) | [**refreshPodcast**](doc/PodcastsApi.md#refreshpodcast) | **POST** /podcasts/{pid}/refresh | Refresh a show&#39;s feed now
[*PodcastsApi*](doc/PodcastsApi.md) | [**removeEpisodeDownload**](doc/PodcastsApi.md#removeepisodedownload) | **DELETE** /episodes/{pid}/fetch | Remove an episode&#39;s fetched audio from the server
[*PodcastsApi*](doc/PodcastsApi.md) | [**subscribePodcast**](doc/PodcastsApi.md#subscribepodcast) | **POST** /podcasts | Subscribe to a podcast
[*PodcastsApi*](doc/PodcastsApi.md) | [**unsubscribePodcast**](doc/PodcastsApi.md#unsubscribepodcast) | **DELETE** /podcasts/{pid} | Unsubscribe from a show
[*RadioApi*](doc/RadioApi.md) | [**createRadioStation**](doc/RadioApi.md#createradiostation) | **POST** /radio/stations | Add a radio station
[*RadioApi*](doc/RadioApi.md) | [**deleteRadioStation**](doc/RadioApi.md#deleteradiostation) | **DELETE** /radio/stations/{pid} | Delete a radio station
[*RadioApi*](doc/RadioApi.md) | [**getRadioPlayInfo**](doc/RadioApi.md#getradioplayinfo) | **GET** /radio/stations/{pid}/play-info | Resolve a playable station stream
[*RadioApi*](doc/RadioApi.md) | [**getRadioStation**](doc/RadioApi.md#getradiostation) | **GET** /radio/stations/{pid} | Get one radio station
[*RadioApi*](doc/RadioApi.md) | [**listRadioStations**](doc/RadioApi.md#listradiostations) | **GET** /radio/stations | List radio stations
[*RadioApi*](doc/RadioApi.md) | [**searchRadioDirectory**](doc/RadioApi.md#searchradiodirectory) | **GET** /radio/directory | Search the station directory
[*RadioApi*](doc/RadioApi.md) | [**updateRadioStation**](doc/RadioApi.md#updateradiostation) | **PUT** /radio/stations/{pid} | Update a radio station
[*ReviewApi*](doc/ReviewApi.md) | [**decideReviewBulk**](doc/ReviewApi.md#decidereviewbulk) | **POST** /review/decide | Decide many review entries
[*ReviewApi*](doc/ReviewApi.md) | [**decideReviewEntry**](doc/ReviewApi.md#decidereviewentry) | **POST** /review/queue/{entryId}/decide | Decide a review entry
[*ReviewApi*](doc/ReviewApi.md) | [**getLibraryMatching**](doc/ReviewApi.md#getlibrarymatching) | **GET** /libraries/{pid}/matching | Read a library&#39;s matching mode
[*ReviewApi*](doc/ReviewApi.md) | [**getReviewEntry**](doc/ReviewApi.md#getreviewentry) | **GET** /review/queue/{entryId} | Inspect one review entry
[*ReviewApi*](doc/ReviewApi.md) | [**getReviewStats**](doc/ReviewApi.md#getreviewstats) | **GET** /review/stats | Review and calibration statistics
[*ReviewApi*](doc/ReviewApi.md) | [**listReviewQueue**](doc/ReviewApi.md#listreviewqueue) | **GET** /review/queue | List review queue entries
[*ReviewApi*](doc/ReviewApi.md) | [**revertReviewEntry**](doc/ReviewApi.md#revertreviewentry) | **POST** /review/queue/{entryId}/revert | Revert an applied match
[*ReviewApi*](doc/ReviewApi.md) | [**setLibraryMatching**](doc/ReviewApi.md#setlibrarymatching) | **PUT** /libraries/{pid}/matching | Set a library&#39;s matching mode
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**connectListenBrainz**](doc/ScrobblingApi.md#connectlistenbrainz) | **PUT** /users/me/scrobblers/listenbrainz | Connect ListenBrainz
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**disconnectLastfm**](doc/ScrobblingApi.md#disconnectlastfm) | **DELETE** /users/me/scrobblers/lastfm | Disconnect Last.fm
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**disconnectListenBrainz**](doc/ScrobblingApi.md#disconnectlistenbrainz) | **DELETE** /users/me/scrobblers/listenbrainz | Disconnect ListenBrainz
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**lastfmCallback**](doc/ScrobblingApi.md#lastfmcallback) | **GET** /scrobble/lastfm/callback | Last.fm authorization callback
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**listScrobblers**](doc/ScrobblingApi.md#listscrobblers) | **GET** /users/me/scrobblers | List the caller&#39;s scrobbling connections
[*ScrobblingApi*](doc/ScrobblingApi.md) | [**startLastfmConnect**](doc/ScrobblingApi.md#startlastfmconnect) | **POST** /users/me/scrobblers/lastfm/connect | Start linking a Last.fm account
[*SyncApi*](doc/SyncApi.md) | [**syncCatalog**](doc/SyncApi.md#synccatalog) | **GET** /sync/catalog | Mirror the catalog (snapshot or changed-since delta)
[*SyncApi*](doc/SyncApi.md) | [**syncServer**](doc/SyncApi.md#syncserver) | **GET** /sync/server | Mirror the caller&#39;s server-side state (changed-since delta)
[*SystemApi*](doc/SystemApi.md) | [**getHealth**](doc/SystemApi.md#gethealth) | **GET** /health | Liveness and version probe
[*ToolsApi*](doc/ToolsApi.md) | [**getToolTask**](doc/ToolsApi.md#gettooltask) | **GET** /tools/tasks/{taskId} | Inspect a tool task
[*ToolsApi*](doc/ToolsApi.md) | [**listToolTasks**](doc/ToolsApi.md#listtooltasks) | **GET** /tools/tasks | List tool tasks
[*ToolsApi*](doc/ToolsApi.md) | [**mergeBook**](doc/ToolsApi.md#mergebook) | **POST** /books/{pid}/merge | Merge a multi-file book
[*ToolsApi*](doc/ToolsApi.md) | [**splitBook**](doc/ToolsApi.md#splitbook) | **POST** /books/{pid}/split | Split a book at its chapters
[*ToolsApi*](doc/ToolsApi.md) | [**splitCueRip**](doc/ToolsApi.md#splitcuerip) | **POST** /items/{pid}/split-cue | Split a CUE rip into real files
[*UploadsApi*](doc/UploadsApi.md) | [**completeUpload**](doc/UploadsApi.md#completeupload) | **POST** /uploads/{uploadId}/complete | Finish an upload
[*UploadsApi*](doc/UploadsApi.md) | [**createAcquisition**](doc/UploadsApi.md#createacquisition) | **POST** /acquisitions | Acquire audio from a URL
[*UploadsApi*](doc/UploadsApi.md) | [**createUpload**](doc/UploadsApi.md#createupload) | **POST** /uploads | Start an upload
[*UploadsApi*](doc/UploadsApi.md) | [**deleteUpload**](doc/UploadsApi.md#deleteupload) | **DELETE** /uploads/{uploadId} | Abandon an upload
[*UploadsApi*](doc/UploadsApi.md) | [**getUpload**](doc/UploadsApi.md#getupload) | **GET** /uploads/{uploadId} | Inspect an upload
[*UploadsApi*](doc/UploadsApi.md) | [**listUploads**](doc/UploadsApi.md#listuploads) | **GET** /uploads | List the caller&#39;s uploads
[*UploadsApi*](doc/UploadsApi.md) | [**putUploadData**](doc/UploadsApi.md#putuploaddata) | **PUT** /uploads/{uploadId}/data | Send upload bytes
[*UsersApi*](doc/UsersApi.md) | [**createAppPassword**](doc/UsersApi.md#createapppassword) | **POST** /users/me/app-passwords | Create an app password
[*UsersApi*](doc/UsersApi.md) | [**createUser**](doc/UsersApi.md#createuser) | **POST** /users | Create an account
[*UsersApi*](doc/UsersApi.md) | [**deleteUser**](doc/UsersApi.md#deleteuser) | **DELETE** /users/{userId} | Delete an account
[*UsersApi*](doc/UsersApi.md) | [**getPrefs**](doc/UsersApi.md#getprefs) | **GET** /users/me/prefs | Get the caller&#39;s preferences
[*UsersApi*](doc/UsersApi.md) | [**getUser**](doc/UsersApi.md#getuser) | **GET** /users/{userId} | Get one account
[*UsersApi*](doc/UsersApi.md) | [**listAppPasswords**](doc/UsersApi.md#listapppasswords) | **GET** /users/me/app-passwords | List the caller&#39;s app passwords
[*UsersApi*](doc/UsersApi.md) | [**listUsers**](doc/UsersApi.md#listusers) | **GET** /users | List accounts
[*UsersApi*](doc/UsersApi.md) | [**putPrefs**](doc/UsersApi.md#putprefs) | **PUT** /users/me/prefs | Replace the caller&#39;s preferences
[*UsersApi*](doc/UsersApi.md) | [**revokeAppPassword**](doc/UsersApi.md#revokeapppassword) | **DELETE** /users/me/app-passwords/{appPasswordId} | Revoke an app password
[*UsersApi*](doc/UsersApi.md) | [**revokeUserSessions**](doc/UsersApi.md#revokeusersessions) | **DELETE** /users/{userId}/sessions | Revoke all of an account&#39;s sessions
[*UsersApi*](doc/UsersApi.md) | [**setPassword**](doc/UsersApi.md#setpassword) | **PUT** /users/{userId}/password | Set an account&#39;s password
[*UsersApi*](doc/UsersApi.md) | [**updateUser**](doc/UsersApi.md#updateuser) | **PATCH** /users/{userId} | Update an account


## Documentation For Models

 - [AcquisitionFormat](doc/AcquisitionFormat.md)
 - [AcquisitionRequest](doc/AcquisitionRequest.md)
 - [AppPassword](doc/AppPassword.md)
 - [AppPasswordCreate](doc/AppPasswordCreate.md)
 - [AppPasswordCreated](doc/AppPasswordCreated.md)
 - [AppPasswordList](doc/AppPasswordList.md)
 - [BookDetail](doc/BookDetail.md)
 - [BookMergeRequest](doc/BookMergeRequest.md)
 - [BookPart](doc/BookPart.md)
 - [BookResume](doc/BookResume.md)
 - [BookSettings](doc/BookSettings.md)
 - [BookSplitRequest](doc/BookSplitRequest.md)
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
 - [DeviceSession](doc/DeviceSession.md)
 - [DiscoveryList](doc/DiscoveryList.md)
 - [DownloadFile](doc/DownloadFile.md)
 - [DownloadInfo](doc/DownloadInfo.md)
 - [DuplicateEntity](doc/DuplicateEntity.md)
 - [DuplicateGroup](doc/DuplicateGroup.md)
 - [DuplicateGroups](doc/DuplicateGroups.md)
 - [DuplicateWarning](doc/DuplicateWarning.md)
 - [EditableField](doc/EditableField.md)
 - [EnrichItemRequest](doc/EnrichItemRequest.md)
 - [EnrichItemResult](doc/EnrichItemResult.md)
 - [EnrichmentCoverage](doc/EnrichmentCoverage.md)
 - [EnrichmentProvider](doc/EnrichmentProvider.md)
 - [EnrichmentRunRequest](doc/EnrichmentRunRequest.md)
 - [EnrichmentRunResult](doc/EnrichmentRunResult.md)
 - [EnrichmentStatus](doc/EnrichmentStatus.md)
 - [EntityCuratedField](doc/EntityCuratedField.md)
 - [EntityCuration](doc/EntityCuration.md)
 - [EntityEdit](doc/EntityEdit.md)
 - [EntityTypeFields](doc/EntityTypeFields.md)
 - [Episode](doc/Episode.md)
 - [EpisodePage](doc/EpisodePage.md)
 - [EpisodeSummary](doc/EpisodeSummary.md)
 - [Error](doc/Error.md)
 - [FieldProvenance](doc/FieldProvenance.md)
 - [Health](doc/Health.md)
 - [HealthFixRequest](doc/HealthFixRequest.md)
 - [HealthFixResult](doc/HealthFixResult.md)
 - [HealthIssue](doc/HealthIssue.md)
 - [HealthIssuePage](doc/HealthIssuePage.md)
 - [HealthRuleCount](doc/HealthRuleCount.md)
 - [HealthSummary](doc/HealthSummary.md)
 - [Item](doc/Item.md)
 - [ItemMetadata](doc/ItemMetadata.md)
 - [ItemPage](doc/ItemPage.md)
 - [ItemSummary](doc/ItemSummary.md)
 - [Job](doc/Job.md)
 - [KindFields](doc/KindFields.md)
 - [LastfmConnectStart](doc/LastfmConnectStart.md)
 - [Libraries](doc/Libraries.md)
 - [LibraryAccess](doc/LibraryAccess.md)
 - [LibraryMatching](doc/LibraryMatching.md)
 - [LinkedIdentity](doc/LinkedIdentity.md)
 - [ListenBrainzConnect](doc/ListenBrainzConnect.md)
 - [ListenIngestResult](doc/ListenIngestResult.md)
 - [ListenReport](doc/ListenReport.md)
 - [ListenSession](doc/ListenSession.md)
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
 - [MergeRequest](doc/MergeRequest.md)
 - [MergeResult](doc/MergeResult.md)
 - [MetadataEdit](doc/MetadataEdit.md)
 - [MetadataEditResult](doc/MetadataEditResult.md)
 - [MetadataFields](doc/MetadataFields.md)
 - [ModelLibrary](doc/ModelLibrary.md)
 - [NotificationConfig](doc/NotificationConfig.md)
 - [NotificationConfigUpdate](doc/NotificationConfigUpdate.md)
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
 - [PlayInfo](doc/PlayInfo.md)
 - [PlayState](doc/PlayState.md)
 - [PlayStateList](doc/PlayStateList.md)
 - [PlayStateQuery](doc/PlayStateQuery.md)
 - [PlayStateUpdate](doc/PlayStateUpdate.md)
 - [PlaybackSession](doc/PlaybackSession.md)
 - [PlaybackSessionCreate](doc/PlaybackSessionCreate.md)
 - [PlaybackSessionEntry](doc/PlaybackSessionEntry.md)
 - [PlaybackSessionList](doc/PlaybackSessionList.md)
 - [PlaybackSessionTransfer](doc/PlaybackSessionTransfer.md)
 - [PlayerEndpoint](doc/PlayerEndpoint.md)
 - [PlayerEndpointList](doc/PlayerEndpointList.md)
 - [Playlist](doc/Playlist.md)
 - [PlaylistCreate](doc/PlaylistCreate.md)
 - [PlaylistEntry](doc/PlaylistEntry.md)
 - [PlaylistItemsPage](doc/PlaylistItemsPage.md)
 - [PlaylistItemsUpdate](doc/PlaylistItemsUpdate.md)
 - [PlaylistPage](doc/PlaylistPage.md)
 - [PlaylistPreview](doc/PlaylistPreview.md)
 - [PlaylistUpdate](doc/PlaylistUpdate.md)
 - [PodcastDetail](doc/PodcastDetail.md)
 - [PodcastShow](doc/PodcastShow.md)
 - [Prefs](doc/Prefs.md)
 - [PushRegistration](doc/PushRegistration.md)
 - [PushRegistrationCreate](doc/PushRegistrationCreate.md)
 - [PushRegistrationList](doc/PushRegistrationList.md)
 - [RadioDirectoryEntry](doc/RadioDirectoryEntry.md)
 - [RadioDirectoryResults](doc/RadioDirectoryResults.md)
 - [RadioPlayInfo](doc/RadioPlayInfo.md)
 - [RadioStation](doc/RadioStation.md)
 - [RadioStationEdit](doc/RadioStationEdit.md)
 - [RadioStationList](doc/RadioStationList.md)
 - [RatingUpdate](doc/RatingUpdate.md)
 - [RefreshResult](doc/RefreshResult.md)
 - [RejectedListen](doc/RejectedListen.md)
 - [ReleaseStatusEdit](doc/ReleaseStatusEdit.md)
 - [RematchResult](doc/RematchResult.md)
 - [ReviewBulkDecision](doc/ReviewBulkDecision.md)
 - [ReviewBulkOutcome](doc/ReviewBulkOutcome.md)
 - [ReviewBulkResult](doc/ReviewBulkResult.md)
 - [ReviewCandidate](doc/ReviewCandidate.md)
 - [ReviewDecideResult](doc/ReviewDecideResult.md)
 - [ReviewDecision](doc/ReviewDecision.md)
 - [ReviewEntry](doc/ReviewEntry.md)
 - [ReviewEntryDetail](doc/ReviewEntryDetail.md)
 - [ReviewEntryPage](doc/ReviewEntryPage.md)
 - [ReviewStats](doc/ReviewStats.md)
 - [ReviewTrack](doc/ReviewTrack.md)
 - [Role](doc/Role.md)
 - [RuleField](doc/RuleField.md)
 - [RuleFields](doc/RuleFields.md)
 - [RuleNode](doc/RuleNode.md)
 - [RuleSort](doc/RuleSort.md)
 - [RuleTagKey](doc/RuleTagKey.md)
 - [Scrobbler](doc/Scrobbler.md)
 - [ScrobblerList](doc/ScrobblerList.md)
 - [SearchHit](doc/SearchHit.md)
 - [SearchResults](doc/SearchResults.md)
 - [ServerSyncEvent](doc/ServerSyncEvent.md)
 - [ServerSyncPage](doc/ServerSyncPage.md)
 - [SessionInfo](doc/SessionInfo.md)
 - [SessionList](doc/SessionList.md)
 - [SkipMap](doc/SkipMap.md)
 - [SkipSpan](doc/SkipSpan.md)
 - [SmartRule](doc/SmartRule.md)
 - [StarUpdate](doc/StarUpdate.md)
 - [SubscribeRequest](doc/SubscribeRequest.md)
 - [Subscription](doc/Subscription.md)
 - [SubscriptionPage](doc/SubscriptionPage.md)
 - [SubscriptionSettings](doc/SubscriptionSettings.md)
 - [SyncedLine](doc/SyncedLine.md)
 - [TagEdit](doc/TagEdit.md)
 - [TagEditResult](doc/TagEditResult.md)
 - [TimelineBoundary](doc/TimelineBoundary.md)
 - [TimelineCreate](doc/TimelineCreate.md)
 - [TimelineInfo](doc/TimelineInfo.md)
 - [ToolTask](doc/ToolTask.md)
 - [ToolTaskPage](doc/ToolTaskPage.md)
 - [Transcript](doc/Transcript.md)
 - [TranscriptCue](doc/TranscriptCue.md)
 - [UpgradeGroup](doc/UpgradeGroup.md)
 - [UpgradeGroups](doc/UpgradeGroups.md)
 - [UpgradeMember](doc/UpgradeMember.md)
 - [UpgradeResolveRequest](doc/UpgradeResolveRequest.md)
 - [UpgradeResolveResult](doc/UpgradeResolveResult.md)
 - [Upload](doc/Upload.md)
 - [UploadCreate](doc/UploadCreate.md)
 - [UploadPage](doc/UploadPage.md)
 - [User](doc/User.md)
 - [UserAccount](doc/UserAccount.md)
 - [UserCreate](doc/UserCreate.md)
 - [UserPage](doc/UserPage.md)
 - [UserUpdate](doc/UserUpdate.md)
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


## Documentation For Authorization


Authentication schemes defined for the API:
### cookieAuth

- **Type**: API key
- **API key parameter name**: waxdeck_session
- **Location**: 

### bearerAuth

- **Type**: HTTP Bearer Token authentication


## Author



