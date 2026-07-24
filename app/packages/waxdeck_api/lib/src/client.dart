import 'dart:convert';
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:dio/dio.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'mapping.dart';
import 'models.dart';

/// What feature code programs against. [WaxDeckClient] is the real
/// implementation; tests substitute fakes without touching the network.
abstract interface class WaxDeckRepository {
  /// Bearer token applied to every request. [login], [bootstrap],
  /// [oidcExchange], and [refreshToken] set it; native clients persist it
  /// and restore it here before the startup session probe. Web builds
  /// leave it null and rely on the HttpOnly session cookie.
  abstract String? authToken;

  /// `GET /health`: liveness and version probe.
  Future<ServerHealth> health();

  /// `GET /auth/bootstrap`: whether first-run setup is needed.
  Future<BootstrapStatus> bootstrapStatus();

  /// `POST /auth/bootstrap`: creates the server's first administrator and
  /// logs it in, exactly like [login]. Fails with `conflict` once any
  /// account exists.
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  });

  /// `POST /auth/login`: establishes a session. On success the client keeps
  /// the returned bearer token and applies it to subsequent calls; web
  /// builds additionally get the HttpOnly session cookie from the browser.
  /// [deviceName] labels the session in the device list.
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  });

  /// `GET /auth/session`: whether the caller is authenticated, and as whom.
  /// Unauthenticated callers get a false state, never an error.
  Future<SessionState> getSession();

  /// `POST /auth/refresh`: rotates the caller's bearer token. The presented
  /// token stays valid for a short overlap window. Bearer-authenticated
  /// callers only.
  Future<LoginResult> refreshToken();

  /// `POST /auth/logout`: revokes the current session.
  Future<void> logout();

  /// `GET /auth/sessions`: every live session belonging to the calling
  /// user, newest first. Doubles as the device list.
  Future<List<DeviceSession>> listSessions();

  /// `DELETE /auth/sessions/{id}`: revokes one of the caller's sessions.
  /// Revoking the session serving the request acts as a logout.
  Future<void> revokeSession(String sessionId);

  /// `GET /auth/oidc/providers`: configured single-sign-on providers, for
  /// rendering login buttons. Empty when SSO is not configured.
  Future<List<OidcProvider>> oidcProviders();

  /// `POST /auth/oidc/exchange`: redeems a one-time OIDC code for a
  /// session, exactly like [login]. [verifier] is required when the flow
  /// sent a challenge; first-party clients always send one.
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  });

  /// `GET /library/items`: keyset-paginated library listing, optionally
  /// filtered by media type.
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? cursor,
    int? limit,
  });

  /// `GET /library/browse`: keyset-paginated discovery lists. [seed] keeps
  /// paging through the random list stable.
  Future<ItemPage> browse(
    DiscoveryList list, {
    String? cursor,
    int? limit,
    int? seed,
  });

  /// `GET /library/search`: grouped full-text search.
  Future<SearchResults> search(String q, {int? limit});

  /// `GET /items/{pid}/similar`: tracks similar to a seed track, most
  /// similar first. The result names which engine answered (`sonic`
  /// embeddings or the `metadata` fallback).
  Future<SimilarTracks> getSimilarTracks(String pid, {int? limit});

  /// `POST /mixes/instant`: computes an instant mix from a seed track
  /// or artist ([seedPid]) or a [genre]; exactly one must be set.
  /// [adventurousness] (0 to 1) sets how far the mix wanders from the
  /// seed; [excludePids] leaves out already-played tracks.
  Future<InstantMix> createInstantMix({
    String? seedPid,
    String? genre,
    double? adventurousness,
    int? size,
    List<String> excludePids,
  });

  /// `GET /mixes/path`: a sonic path [from] one track [to] another,
  /// starting track first. An incomplete path still drifts toward the
  /// target.
  Future<SonicPath> getSonicPath({
    required String from,
    required String to,
    int? length,
  });

  /// `GET /items/{pid}`: full detail for one item.
  Future<ItemDetail> getItem(String pid);

  /// `GET /items/{pid}/play-info`: short-TTL stream resolution. The returned
  /// URL is already resolved against the client base URL. For multi-file
  /// audiobooks [positionMs] (book-timeline milliseconds) selects the part
  /// containing that position; [voiceBoost] requests server-side loudness
  /// normalization, overriding the caller's stored setting when present.
  Future<PlayInfo> getPlayInfo(String pid, {int? positionMs, bool? voiceBoost});

  /// `GET /items/{pid}/play-state`: the caller's resume state for one item.
  Future<PlayState> getPlayState(String pid);

  /// `POST /play-states`: the caller's states for a batch of items (at
  /// most 500). Items with zero state are absent from the result.
  Future<List<PlayState>> listPlayStates(List<String> pids);

  /// `PUT /items/{pid}/play-state`: checkpoints the resume position.
  /// [recordedAt] marks an offline-queue replay; the server reconciles
  /// it per medium instead of applying it blindly.
  Future<void> putPlayState(String pid, int positionMs, {DateTime? recordedAt});

  /// `PUT /items/{pid}/star`: stars or unstars one item, returning the
  /// updated play state. [recordedAt] marks an offline-queue replay.
  Future<PlayState> setStar(String pid, bool starred, {DateTime? recordedAt});

  /// `PUT /items/{pid}/rating`: rates one item, 0 to 100, or clears the
  /// rating with null. Returns the updated play state. [recordedAt]
  /// marks an offline-queue replay.
  Future<PlayState> setRating(String pid, int? rating, {DateTime? recordedAt});

  /// `POST /listens`: reports listen sessions. Idempotent per session ID, so
  /// retrying a failed batch is always safe.
  Future<ListenOutcome> reportListens(List<ListenSession> sessions);

  /// `GET /stats/listening`: the caller's aggregated listening time.
  /// [range] is `7d`, `30d`, `90d`, `365d`, or `all`; [bucket] is
  /// `day`, `week`, or `month`. Absent values ride the server
  /// defaults (`30d`, `day`).
  Future<ListeningStats> getListeningStats({String? range, String? bucket});

  /// `GET /stats/heatmap`: the caller's per-day listening for one
  /// calendar [year] (default: the current year), plus streaks.
  Future<ListeningHeatmap> getListeningHeatmap({int? year});

  /// `GET /stats/top`: one ranked top list. [kind] is `artists`,
  /// `albums`, `genres`, or `shows`; [range] as in
  /// [getListeningStats].
  Future<TopList> getTopList({required String kind, String? range, int? limit});

  /// `GET /stats/sessions`: the caller's keyset-paginated listen log,
  /// newest first, optionally filtered to one reporting [client].
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  });

  /// `GET /stats/year-in-review`: the caller's listening recap for one
  /// calendar [year] (default: the current year).
  Future<YearInReview> getYearInReview({int? year});

  /// `GET /stats/server-year-in-review`: the whole server's recap for
  /// one calendar [year], aggregated across users who have not opted
  /// out of shared stats.
  Future<ServerYearInReview> getServerYearInReview({int? year});

  /// `GET /sync/catalog`: snapshot (no [since]) or changed-since delta
  /// of the catalog, feeding the client mirror. A `sync-reset` error
  /// means drop the mirror and snapshot again.
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  });

  /// `GET /sync/server`: the caller's own server-side state changes.
  /// Without [since] it mints a fresh cursor and returns no events.
  Future<ServerSyncPage> syncServer({String? since, int? limit});

  /// `GET /items/{pid}/download-info`: resolves an offline download of
  /// the item's original bytes. URLs are resolved against the client
  /// base URL.
  Future<DownloadInfo> getDownloadInfo(String pid);

  /// `GET /users/me/app-passwords`: the caller's app passwords.
  Future<List<AppPassword>> listAppPasswords();

  /// `POST /users/me/app-passwords`: creates an app password; the
  /// returned secret is visible exactly once.
  Future<AppPasswordCreated> createAppPassword(String label);

  /// `DELETE /users/me/app-passwords/{id}`: revokes an app password.
  Future<void> revokeAppPassword(String id);

  /// `GET /users/me/prefs`: the caller's synced preferences.
  Future<Prefs> getPrefs();

  /// `PUT /users/me/prefs`: replaces the caller's synced preferences and
  /// returns the stored document. Replace semantics: start from [getPrefs].
  Future<Prefs> putPrefs(Prefs prefs);

  /// `GET /podcasts`: keyset-paginated list of the caller's podcast
  /// subscriptions, ordered by show title then pid.
  Future<SubscriptionPage> listSubscriptions({String? cursor, int? limit});

  /// `POST /podcasts`: subscribes the caller to a show, cataloging it on
  /// first subscription. [sourceType] is `rss` (default) or `youtube`;
  /// supplying credentials marks the show private.
  Future<Subscription> subscribePodcast({
    required String url,
    String? sourceType,
    String? username,
    String? password,
    String? folder,
  });

  /// `GET /podcasts/{pid}`: show detail with the caller's subscription
  /// state, for any cataloged show.
  Future<PodcastDetail> getPodcast(String pid);

  /// `DELETE /podcasts/{pid}`: removes the caller's subscription. Never
  /// destructive to the catalog; a no-op when not subscribed. With
  /// [removeDownloads], and only when the caller was the show's last
  /// subscriber, the downloaded audio moves to the server trash.
  Future<void> unsubscribePodcast(String pid, {bool removeDownloads});

  /// `PUT /podcasts/{pid}/settings`: full replace of the caller's
  /// per-subscription settings; absent fields reset to defaults, so
  /// senders start from the stored value.
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  );

  /// `GET /podcasts/{pid}/episodes`: keyset-paginated episodes, newest
  /// first.
  Future<EpisodePage> listEpisodes(String pid, {String? cursor, int? limit});

  /// `GET /episodes/{pid}`: full episode detail with sanitized show
  /// notes and chapter marks.
  Future<EpisodeDetail> getEpisode(String pid);

  /// `GET /episodes/{pid}/transcript`: the episode's transcript as
  /// time-coded cues; the first call may take a moment while the server
  /// fetches and caches it.
  Future<Transcript> getEpisodeTranscript(String pid);

  /// `POST /episodes/{pid}/transcript`: indexes the episode's transcript
  /// text for search without downloading the audio, so a streamed episode
  /// turns up in transcript search. A no-op success when already indexed.
  Future<void> captureEpisodeTranscript(String pid);

  /// `POST /episodes/{pid}/fetch`: queues a server-side download of the
  /// episode's audio. A no-op success when already downloaded or queued.
  Future<void> fetchEpisode(String pid);

  /// Removes an episode's fetched audio from the server (archive, not
  /// delete: playback state survives and the episode stays fetchable).
  Future<void> removeEpisodeDownload(String pid);

  /// `GET /books/{pid}`: full audiobook detail with chapters, parts, and
  /// the caller's per-book settings.
  Future<BookDetail> getBook(String pid);

  /// `GET /books/{pid}/resume`: the caller's cross-device resume point
  /// on the book timeline.
  Future<BookResume> getBookResume(String pid);

  /// `PUT /books/{pid}/settings`: full replace of the caller's per-book
  /// playback settings.
  Future<BookSettings> putBookSettings(String pid, BookSettings settings);

  /// `GET /items/{pid}/skip-map`: precomputed silence spans for
  /// client-side trimming; [partIndex] selects one part of a multi-file
  /// audiobook, with spans in that part's own timeline.
  Future<SkipMap> getSkipMap(String pid, {int? partIndex});

  /// `GET /podcasts/opml`: the caller's subscriptions as an OPML 2.0
  /// document.
  Future<String> exportOpml();

  /// `POST /podcasts/opml`: subscribes the caller to every feed in the
  /// document; per-feed failures do not fail the import.
  Future<void> importOpml(String opml);

  /// `GET /playlists`: the caller's playlists plus every shared one.
  /// [containsItem] restricts to static playlists holding that item.
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  });

  /// `POST /playlists`: creates a static or smart playlist. A smart
  /// playlist requires [rule]; a static one may seed [itemPids].
  Future<Playlist> createPlaylist({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids,
  });

  /// `GET /playlists/{pid}`: one playlist, with a computed count for
  /// smart lists.
  Future<Playlist> getPlaylist(String pid);

  /// `PATCH /playlists/{pid}`: partial update. Replacing a smart rule
  /// applies in place under the same pid; the returned playlist carries
  /// the updated rule.
  Future<Playlist> updatePlaylist(
    String pid, {
    String? name,
    String? visibility,
    SmartRule? rule,
  });

  /// `DELETE /playlists/{pid}`: deletes an owned playlist.
  Future<void> deletePlaylist(String pid);

  /// `GET /playlists/{pid}/items`: the members in order, with stored
  /// positions for static playlists.
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  });

  /// `PUT /playlists/{pid}/items`: full ordered replace, which is also
  /// the reorder primitive. [baseUpdatedAt] is the lost-update guard.
  Future<void> replacePlaylistItems(
    String pid,
    List<String> itemPids, {
    DateTime? baseUpdatedAt,
  });

  /// `POST /playlists/{pid}/items`: appends members.
  Future<void> addPlaylistItems(String pid, List<String> itemPids);

  /// `DELETE /playlists/{pid}/items/{position}`: removes the member at
  /// one stored position.
  Future<void> removePlaylistItemAt(String pid, int position);

  /// `POST /playlists/preview`: evaluates a rule without storing it.
  Future<PlaylistPreview> previewSmartRule(SmartRule rule, {int? limit});

  /// `GET /playlists/rule-fields`: the rule vocabulary for editors.
  Future<RuleFields> getRuleFields();

  /// `GET /playlists/{pid}/m3u`: the playlist as an M3U8 document.
  Future<String> exportPlaylistM3u(String pid);

  /// `POST /playlists/m3u`: imports an M3U8 document as a static
  /// playlist, reporting unmatched entries.
  Future<M3uImportResult> importPlaylistM3u({
    required String name,
    required String content,
    String? visibility,
  });

  /// `POST /playlists/import`: imports a playlist export as a static
  /// playlist. [source] is `spotify`, `applemusic`, `ytmusic`, `csv`,
  /// `text`, or `portable`; [payload] carries the export text for the
  /// text sources, [refs] the portable refs for `portable`. The result
  /// reports unmatched entries and per-rung match confidence.
  Future<PlaylistImportResult> importPlaylist({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  });

  /// `GET /playlists/{pid}/portable`: the playlist as portable refs,
  /// for re-importing on another WaxDeck server.
  Future<PortablePlaylist> exportPlaylistPortable(String pid);

  /// `GET /shares`: the caller's share links, newest first.
  Future<SharePage> listShares({String? cursor, int? limit});

  /// `POST /shares`: mints a public share link for a track, playlist,
  /// book, or episode [pid]. [expiresInHours] bounds its lifetime
  /// (absent: never expires); [positionMs] is the episode
  /// copy-link-at-timestamp start.
  Future<Share> createShare({
    required String pid,
    int? expiresInHours,
    bool allowDownload,
    int? positionMs,
  });

  /// `DELETE /shares/{shareId}`: revokes a share link.
  Future<void> revokeShare(String shareId);

  /// `GET /similarity/status`: coverage of the sonic-similarity
  /// surface, for deciding whether to show sonic affordances.
  Future<SimilarityStatus> getSimilarityStatus();

  /// `GET /radio/stations`: the shared station library.
  Future<List<RadioStation>> listRadioStations();

  /// `GET /player/endpoints`: outputs the caller can play to.
  Future<List<PlayerEndpoint>> listPlayerEndpoints();

  /// `GET /player/sessions`: visible active playback sessions.
  Future<List<PlaybackSessionInfo>> listPlaybackSessions();

  /// `POST /player/sessions`: start playback on an endpoint.
  Future<PlaybackSessionInfo> createPlaybackSession({
    required String endpointId,
    required List<String> itemPids,
    int index = 0,
    int positionMs = 0,
    bool play = true,
  });

  /// `GET /player/sessions/{sessionId}`: one session snapshot.
  Future<PlaybackSessionInfo> getPlaybackSession(String sessionId);

  /// `DELETE /player/sessions/{sessionId}`: end a session.
  Future<void> deletePlaybackSession(String sessionId);

  /// `POST /player/sessions/{sessionId}/transfer`: move live playback
  /// to another endpoint, keeping queue and position.
  Future<PlaybackSessionInfo> transferPlaybackSession(
    String sessionId,
    String endpointId,
  );

  /// `POST /radio/stations`: adds a station.
  Future<RadioStation> createRadioStation({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  });

  /// `PUT /radio/stations/{pid}`: replaces a station's fields.
  Future<RadioStation> updateRadioStation(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  });

  /// `DELETE /radio/stations/{pid}`: removes a station.
  Future<void> deleteRadioStation(String pid);

  /// `GET /radio/stations/{pid}/play-info`: a tokenized proxied stream
  /// URL, absolute against the client base URL.
  Future<RadioPlayInfo> getRadioPlayInfo(String pid);

  /// `GET /radio/directory`: searches the public station directory.
  Future<List<RadioDirectoryEntry>> searchRadioDirectory(
    String query, {
    int? limit,
  });

  /// `GET /users/me/scrobblers`: the caller's scrobbling connection
  /// slots.
  Future<List<Scrobbler>> listScrobblers();

  /// `PUT /users/me/scrobblers/listenbrainz`: validates and stores a
  /// ListenBrainz token. [apiUrl] points at a compatible server.
  Future<Scrobbler> connectListenBrainz(String token, {String? apiUrl});

  /// `DELETE /users/me/scrobblers/listenbrainz`: disconnects.
  Future<void> disconnectListenBrainz();

  /// `POST /users/me/scrobblers/lastfm/connect`: mints the Last.fm
  /// authorization URL to open in a browser.
  Future<String> startLastfmConnect();

  /// `DELETE /users/me/scrobblers/lastfm`: disconnects.
  Future<void> disconnectLastfm();

  /// `GET /users/me/push-registrations`: the caller's UnifiedPush
  /// registrations.
  Future<List<PushRegistration>> listPushRegistrations();

  /// `POST /users/me/push-registrations`: registers a UnifiedPush
  /// endpoint.
  Future<PushRegistration> createPushRegistration({
    required String endpoint,
    String? label,
  });

  /// `DELETE /users/me/push-registrations/{id}`: removes one
  /// registration.
  Future<void> deletePushRegistration(String pid);

  /// `GET /notifications/events`: the event catalog for the
  /// per-target checklist.
  Future<List<NotifyEvent>> listNotificationEvents();

  /// `GET /admin/notification-targets`: the server-scope targets
  /// (administrators).
  Future<List<NotificationTarget>> listServerNotificationTargets();

  /// `POST /admin/notification-targets`: creates a server-scope
  /// target (administrators).
  Future<NotificationTarget> createServerNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  });

  /// `PUT /admin/notification-targets/{id}`: replaces a server-scope
  /// target's label, config, and events (administrators).
  Future<NotificationTarget> updateServerNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  });

  /// `DELETE /admin/notification-targets/{id}` (administrators).
  Future<void> deleteServerNotificationTarget(String pid);

  /// `POST /admin/notification-targets/{id}/test`: queues one test
  /// delivery; the outcome lands on the target's health fields
  /// (administrators).
  Future<void> testServerNotificationTarget(String pid);

  /// `GET /users/me/notification-targets`: the caller's personal
  /// targets.
  Future<List<NotificationTarget>> listMyNotificationTargets();

  /// `POST /users/me/notification-targets`: creates a personal
  /// target.
  Future<NotificationTarget> createMyNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  });

  /// `PUT /users/me/notification-targets/{id}`: replaces a personal
  /// target's label, config, and events.
  Future<NotificationTarget> updateMyNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  });

  /// `DELETE /users/me/notification-targets/{id}`.
  Future<void> deleteMyNotificationTarget(String pid);

  /// `POST /users/me/notification-targets/{id}/test`: queues one test
  /// delivery; the outcome lands on the target's health fields.
  Future<void> testMyNotificationTarget(String pid);

  /// `GET /review/queue`: keyset-paginated review entries, optionally
  /// filtered by lifecycle [status].
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  });

  /// `GET /review/queue/{entryId}`: one entry with its local tracks
  /// and every candidate.
  Future<ReviewEntryDetail> getReviewEntry(String entryId);

  /// `POST /review/queue/{entryId}/decide`: decides one entry.
  /// [action] is `approve`, `as-is`, `unofficial`, `skip`, or
  /// `discard`; `approve` takes [candidateMbid] to pick a candidate
  /// other than the best.
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  });

  /// `POST /review/queue/{entryId}/revert`: undoes a decided entry's
  /// applied metadata and returns it to pending.
  Future<ReviewEntry> revertReviewEntry(String entryId);

  /// `POST /review/decide`: applies one [action] to many entries,
  /// reporting per-entry outcomes instead of failing the batch.
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  });

  /// `GET /review/stats`: queue counters by lifecycle state.
  Future<ReviewStats> getReviewStats();

  /// `GET /libraries`: every catalog library.
  Future<List<LibraryInfo>> listLibraries();

  /// `POST /libraries`: registers a new library root at runtime,
  /// returning the created library. Administrators only.
  Future<LibraryInfo> createLibrary({
    required String name,
    required String path,
    String? media,
    bool? managed,
  });

  /// `GET /libraries/{pid}/matching`: the library's matching mode
  /// (`auto`, `review`, or `off`).
  Future<String> getLibraryMatching(String libraryPid);

  /// `PUT /libraries/{pid}/matching`: sets the library's matching
  /// mode, returning the stored mode.
  Future<String> setLibraryMatching(String libraryPid, String mode);

  /// `GET /uploads`: keyset-paginated upload sessions visible to the
  /// caller.
  Future<UploadPage> listUploads({String? cursor, int? limit});

  /// `POST /uploads`: opens a resumable upload session. [sha256] lets
  /// the server flag byte-identical duplicates before any transfer.
  /// [batchId] joins the session to an open batch; [batchPath] is the
  /// file's directory relative to the picked folder, the `auto`
  /// grouping's clustering hint.
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
  });

  /// `POST /uploads/batches`: opens a batch grouping several sessions
  /// into review units by the declared intent.
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
  });

  /// `POST /uploads/batches/{batchId}/complete`: finalizes a batch —
  /// members staged so far are grouped and their review entries open.
  /// Idempotent.
  Future<UploadBatch> completeUploadBatch(String batchId);

  /// `GET /uploads/{uploadId}`: one session's progress and state.
  Future<UploadSession> getUpload(String uploadId);

  /// `DELETE /uploads/{uploadId}`: discards a session and its staged
  /// bytes.
  Future<void> deleteUpload(String uploadId);

  /// `PUT /uploads/{uploadId}/data`: appends one chunk at byte
  /// [offset], returning the updated session. Resume by re-reading
  /// the session's receivedBytes and continuing from there.
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  });

  /// `POST /uploads/{uploadId}/complete`: seals a fully received
  /// session and hands it to the review pipeline.
  Future<UploadSession> completeUpload(String uploadId);

  /// `POST /acquisitions`: downloads audio from a source URL (a
  /// single video, or a playlist or channel) through the acquisition
  /// bridge as a background task; the files stage like uploads and
  /// flow through the review pipeline.
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    String? libraryPid,
    String? format,
  });

  /// `GET /metadata/fields`: the metadata editor vocabulary.
  Future<MetadataFields> getMetadataFields();

  /// `GET /items/{pid}/metadata`: everything the metadata editor
  /// shows for one item.
  Future<ItemMetadata> getItemMetadata(String pid);

  /// `PATCH /items/{pid}/metadata`: edits item fields. [lock] pins
  /// the edited fields against later automatic updates; [force]
  /// overwrites locked fields; [writeBack] also rewrites file tags.
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `POST /items/bulk-edit`: applies one field edit to many items.
  /// [skipLocked] passes over locked fields instead of failing.
  Future<BulkEditResult> bulkEditMetadata({
    required List<String> itemPids,
    required Map<String, String> fields,
    bool writeBack = false,
    bool skipLocked = false,
    bool force = false,
  });

  /// `PUT /items/{pid}/credits`: replaces one credited [role]'s
  /// [names], in order.
  Future<MetadataEditResult> setItemCredits(
    String pid, {
    required String role,
    required List<String> names,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `PUT /items/{pid}/lyrics`: stores synced ([lrc]) and/or [plain]
  /// lyrics for a track.
  Future<MetadataEditResult> setItemLyrics(
    String pid, {
    String? lrc,
    String? plain,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `DELETE /items/{pid}/lyrics`: removes the stored lyrics; files
  /// are untouched.
  Future<void> clearItemLyrics(String pid);

  /// `PUT /books/{pid}/chapters`: replaces an audiobook's chapter
  /// marks.
  Future<MetadataEditResult> setBookChapters(
    String pid, {
    required List<ChapterEdit> chapters,
    bool lock = true,
    bool force = false,
  });

  /// `GET /items/{pid}/art-roles`: the artwork slots an item, album, or
  /// artist holds at its own level (not inherited from the chain), each
  /// with its stored format and pixel dimensions.
  Future<List<ArtRoleInfo>> getItemArtRoles(String pid);

  /// `PUT /items/{pid}/artwork`: replaces an item's artwork in one slot
  /// ([role], default `front`) with the uploaded image [bytes].
  Future<MetadataEditResult> setItemArtwork(
    String pid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
    bool lock = true,
  });

  /// `DELETE /items/{pid}/artwork`: removes the curated artwork in one
  /// slot ([role], default `front`).
  Future<void> clearItemArtwork(String pid, {String role = 'front'});

  /// `PUT /entities/{entityType}/{entityPid}/artwork`: replaces a
  /// browse entity's artwork in one slot ([role], default `front`) with
  /// the uploaded image [bytes].
  Future<MetadataEditResult> setEntityArtwork(
    String entityType,
    String entityPid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
  });

  /// `PUT /items/{pid}/tags/{key}`: replaces one custom tag's values.
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool lock = true,
    bool force = false,
  });

  /// `DELETE /items/{pid}/tags/{key}`: removes one custom tag.
  Future<void> clearItemTag(String pid, String key);

  /// `PUT /items/{pid}/locks`: locks or unlocks [fields], returning
  /// the item's full locked-field list.
  Future<List<String>> setItemLocks(
    String pid, {
    required List<String> fields,
    required bool locked,
  });

  /// `PATCH /entities/{entityType}/{entityPid}`: edits a browse
  /// entity's curated fields.
  Future<MetadataEditResult> editEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> edits,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  });

  /// `GET /entities/{entityType}/{entityPid}/curation`: the entity's
  /// curated field overrides.
  Future<List<EntityCuratedField>> getEntityCuration(
    String entityType,
    String entityPid,
  );

  /// `PUT /items/{pid}/release-status`: marks an item's release
  /// official or unofficial.
  Future<MetadataEditResult> setReleaseStatus(
    String pid, {
    required bool unofficial,
  });

  /// `POST /items/{pid}/rematch`: reopens identification for the
  /// item's release, returning the review entry id to watch.
  Future<String> rematchItem(String pid);

  /// `POST /items/{pid}/enrich`: fetches the wanted artifacts
  /// (`cover`, `lyrics`, `genres`, `book`) for one item now.
  Future<EnrichItemResult> enrichItem(String pid, {required List<String> want});

  /// `GET /library/health`: the library health scoreboard.
  Future<HealthSummary> getLibraryHealth();

  /// `GET /library/health/issues`: keyset-paginated failing items,
  /// optionally filtered to one [rule].
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  });

  /// `GET /library/diagnostics`: per-file diagnostics across the library,
  /// optionally narrowed by [origin], [code], [severity], or [library], and
  /// keyset-paginated. Administrators only.
  Future<FileDiagnosticPage> listFileDiagnostics({
    String? origin,
    String? code,
    String? severity,
    String? library,
    String? cursor,
    int? limit,
  });

  /// `GET /library/diagnostics/summary`: diagnostic counts grouped by
  /// writer, code, and severity, most severe first. Administrators only.
  Future<List<DiagnosticCount>> getDiagnosticSummary({
    String? origin,
    String? code,
    String? severity,
    String? library,
  });

  /// `POST /library/health/sweep`: queues a full health re-evaluation.
  Future<void> sweepLibraryHealth();

  /// `POST /library/health/fix`: queues automatic repairs for one
  /// [rule], on [itemPids] or on every failing item, returning the
  /// queued count.
  Future<int> fixHealthIssues({required String rule, List<String>? itemPids});

  /// `GET /library/duplicates`: detected duplicate entity clusters.
  Future<List<DuplicateGroup>> listDuplicates();

  /// `POST /library/duplicates/merge`: merges [loserPids] into
  /// [survivorPid]. [entityType] is `album`, `artist`,
  /// `release-group`, or `genre`.
  Future<MergeOutcome> mergeDuplicates({
    required String entityType,
    required String survivorPid,
    required List<String> loserPids,
  });

  /// `GET /library/upgrades`: recordings present in more than one
  /// quality.
  Future<List<UpgradeGroup>> listUpgrades();

  /// `POST /library/upgrades/resolve`: keeps one member and trashes
  /// the rest, returning the trashed count.
  Future<int> resolveUpgrade({
    required String keepItemPid,
    required List<String> removeItemPids,
  });

  /// `GET /organize/profiles`: the configured file organization
  /// profiles.
  Future<List<OrganizeProfile>> listOrganizeProfiles();

  /// `POST /organize/preview`: dry-runs a profile over [itemPids] or
  /// the whole library.
  Future<OrganizePlan> previewOrganize({
    required String profile,
    List<String>? itemPids,
  });

  /// `POST /organize/apply`: applies a profile's moves.
  Future<OrganizeReport> applyOrganize({
    required String profile,
    List<String>? itemPids,
  });

  /// `POST /books/{pid}/merge`: joins a multi-file audiobook into one
  /// file, returning the queued task. [titles] overrides the derived
  /// chapter titles.
  Future<ToolTask> mergeBook(
    String pid, {
    List<String>? titles,
    bool keepOriginals = false,
  });

  /// `POST /books/{pid}/split`: splits a single-file audiobook at its
  /// chapter marks, returning the queued task.
  Future<ToolTask> splitBook(String pid, {bool keepOriginals = false});

  /// `POST /items/{pid}/split-cue`: carves a CUE-backed rip into real
  /// per-track files, returning the queued task.
  Future<ToolTask> splitCueRip(String pid, {bool keepOriginals = false});

  /// `GET /tools/tasks`: keyset-paginated tool tasks, newest first.
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit});

  /// `GET /tools/tasks/{taskId}`: one task's progress and outcome.
  Future<ToolTask> getToolTask(String taskId);

  /// `GET /library/enrichment`: provider roster and coverage.
  Future<EnrichmentStatus> getEnrichmentStatus();

  /// `POST /library/enrichment/run`: starts a library-wide enrichment
  /// pass, returning the job pid. [force] refetches artifacts that
  /// already exist.
  Future<String> runEnrichment({bool force = false});

  /// `GET /users`: keyset-paginated accounts (administrators).
  Future<UserPage> listUsers({String? cursor, int? limit});

  /// `POST /users`: creates an account (administrators).
  Future<UserAccount> createUser({
    required String username,
    required String password,
    String? displayName,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  });

  /// `PATCH /users/{userId}`: partial account update (administrators).
  /// Absent fields keep their stored values.
  Future<UserAccount> updateUser(
    String userId, {
    String? displayName,
    List<String>? roles,
    bool? disabled,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  });

  /// `GET /users/{userId}`: one account (administrators).
  Future<UserAccount> getUser(String userId);

  /// `DELETE /users/{userId}`: deletes an account (administrators).
  Future<void> deleteUser(String userId);

  /// `PUT /users/{userId}/password`: administrator password reset;
  /// no current password required.
  Future<void> setUserPassword(String userId, String newPassword);

  /// `DELETE /users/{userId}/sessions`: revokes every live session of
  /// one account (administrators).
  Future<void> revokeUserSessions(String userId);

  /// `POST /auth/signup`: requests an account. Anonymous; the result
  /// says whether the account is active now (invite or open signup
  /// with auto-approval) or pending administrator approval.
  Future<SignupResult> signup({
    required String username,
    required String password,
    String? displayName,
    String? inviteToken,
  });

  /// `GET /users/requests`: pending signup requests, oldest first
  /// (administrators).
  Future<UserPage> listSignupRequests({String? cursor, int? limit});

  /// `POST /users/requests/{userId}/approve`: activates a pending
  /// signup, optionally overriding roles, access, and permissions
  /// (administrators).
  Future<UserAccount> approveSignupRequest(
    String userId, {
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
  });

  /// `POST /users/requests/{userId}/reject`: rejects and removes a
  /// pending signup (administrators).
  Future<void> rejectSignupRequest(String userId);

  /// `GET /invites`: every invite, revoked and expired included
  /// (administrators).
  Future<List<Invite>> listInvites();

  /// `POST /invites`: mints an invite; the returned token is visible
  /// exactly once (administrators).
  Future<InviteCreated> createInvite({
    String? note,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? maxUses,
    DateTime? expiresAt,
  });

  /// `DELETE /invites/{inviteId}`: revokes an invite (administrators).
  Future<void> revokeInvite(String inviteId);

  /// `GET /admin/audit`: keyset-paginated audit events, newest first.
  /// [action] filters by action prefix (administrators).
  Future<AuditEventPage> listAuditEvents({
    String? cursor,
    int? limit,
    String? action,
    String? actorId,
    String? targetPid,
  });

  /// `GET /admin/settings`: the server-wide switches (administrators).
  Future<AdminSettings> getAdminSettings();

  /// `PUT /admin/settings`: replaces the server-wide switches
  /// (administrators).
  Future<AdminSettings> putAdminSettings(AdminSettings settings);

  /// `GET /admin/transcoding`: the transcoding limits (administrators).
  Future<TranscodingLimits> getTranscodingLimits();

  /// `PUT /admin/transcoding`: replaces the transcoding limits
  /// (administrators).
  Future<TranscodingLimits> putTranscodingLimits(TranscodingLimits limits);

  /// `GET /admin/scrobbling`: whether the server holds Last.fm API
  /// credentials and where they came from; the shared secret is never
  /// read back (administrators).
  Future<ScrobblingAdminConfig> getScrobblingConfig();

  /// `PUT /admin/scrobbling`: stores a Last.fm API credential pair.
  /// Both values empty clears the stored pair, falling back to
  /// environment credentials when the server has them; a half-set pair
  /// fails with `invalid-request` (administrators).
  Future<ScrobblingAdminConfig> putScrobblingConfig({
    required String apiKey,
    required String secret,
  });

  /// `GET /admin/schedules`: the three maintenance schedules
  /// (administrators).
  Future<List<Schedule>> listSchedules();

  /// `PUT /admin/schedules/{kind}`: replaces one schedule's cron and
  /// enablement; [kind] is `scan`, `backup`, or `prune`
  /// (administrators).
  Future<Schedule> putSchedule(
    String kind, {
    required String cron,
    required bool enabled,
  });

  /// `GET /admin/backups`: every backup archive, newest first
  /// (administrators).
  Future<List<Backup>> listBackups();

  /// `POST /admin/backups`: starts a backup now (administrators).
  Future<Backup> createBackup();

  /// `GET /admin/backups/{backupId}`: one archive's state
  /// (administrators).
  Future<Backup> getBackup(String backupId);

  /// `DELETE /admin/backups/{backupId}`: deletes an archive
  /// (administrators).
  Future<void> deleteBackup(String backupId);

  /// URL of `GET /admin/backups/{backupId}/archive`, for opening in a
  /// browser or handing to a download manager; the bytes are never
  /// pulled through this client.
  String backupArchiveUrl(String backupId);

  /// `POST /admin/backups/import`: uploads an archive produced by
  /// another instance (administrators). The zip streams from
  /// [openRead] — archives carry whole databases and easily exceed
  /// what should sit in memory, so the body is never buffered whole.
  Future<Backup> importBackup({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  });

  /// `POST /admin/backups/{backupId}/restore`: stages the archive for
  /// restore at the next server restart, returning the plan
  /// (administrators).
  Future<RestorePlan> stageRestore(String backupId);

  /// `GET /admin/backups/restore`: the currently staged restore, or
  /// null when none is staged (administrators).
  Future<RestorePlan?> getStagedRestore();

  /// `DELETE /admin/backups/restore`: unstages the pending restore
  /// (administrators).
  Future<void> cancelStagedRestore();

  /// `POST /admin/migrations`: starts a server-side import from
  /// another server as a background task; [source] is
  /// `navidrome`, `subsonic`, or `audiobookshelf` (administrators).
  Future<ToolTask> createMigration({
    required String source,
    required String serverUrl,
    String? username,
    String? password,
    String? token,
    MigrationOptions? options,
    bool dryRun = false,
  });

  /// `GET /admin/trash`: the server-side trash (administrators).
  Future<TrashList> listTrash({bool includeRestored = false, int? limit});

  /// `POST /admin/trash/{trashId}/restore`: puts one trashed file back
  /// (administrators).
  Future<void> restoreTrashEntry(String trashId);

  /// `POST /admin/trash/empty`: purges the trash for good
  /// (administrators).
  Future<TrashEmptyResult> emptyTrash();

  /// `DELETE /admin/trash/{trashId}`: purges one trashed file for good,
  /// returning the bytes reclaimed (administrators).
  Future<int> purgeTrashEntry(String trashId);

  /// `GET /jobs`: currently known background jobs (administrators).
  Future<List<Job>> listJobs();

  /// `GET /libraries/{pid}/read-only`: whether one library refuses
  /// content mutations (administrators).
  Future<bool> getLibraryReadOnly(String libraryPid);

  /// `PUT /libraries/{pid}/read-only`: sets one library's read-only
  /// flag, returning the stored value (administrators).
  Future<bool> setLibraryReadOnly(String libraryPid, bool readOnly);

  /// `POST /library/items/delete`: deletes library items' files to
  /// the trash (or permanently). With [dryRun] nothing is touched and
  /// the result is the plan.
  Future<DeleteItemsResult> deleteLibraryItems({
    required List<String> pids,
    String? mode,
    bool dryRun = false,
  });
}

/// Thin repository layer over the generated dart-dio client.
class WaxDeckClient implements WaxDeckRepository {
  /// [baseUrl] is the server origin. On web builds pass an empty string:
  /// relative URLs resolve against the single origin serving the SPA.
  ///
  /// [dio] is a test hook: the package's own tests inject a Dio carrying a
  /// recording adapter to pin request headers without a network.
  factory WaxDeckClient({String baseUrl = '', Dio? dio}) {
    // Strip trailing slashes so a baseUrl like "http://host:4420/" doesn't
    // produce "//api/v1", a non-canonical path the server 301-redirects,
    // which can drop the body on POST /auth/login.
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final transport = dio ?? Dio();
    transport.options.baseUrl = '$trimmed/api/v1';
    return WaxDeckClient._(trimmed, gen.WaxdeckApiGen(dio: transport));
  }

  WaxDeckClient._(this._baseUrl, this._gen) {
    _gen.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _authToken;
          if (token != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Cookie-authenticated mutations (web after a reload: no bearer
          // in memory, the HttpOnly cookie authenticates) must echo the
          // CSRF token from login/getSession. Bearer requests are exempt.
          final csrf = _csrfToken;
          if (token == null &&
              csrf != null &&
              _isMutation(options.method) &&
              !options.headers.containsKey('X-CSRF-Token')) {
            options.headers['X-CSRF-Token'] = csrf;
          }
          handler.next(options);
        },
      ),
    );
  }

  static bool _isMutation(String method) {
    return switch (method.toUpperCase()) {
      'GET' || 'HEAD' || 'OPTIONS' => false,
      _ => true,
    };
  }

  final String _baseUrl;
  final gen.WaxdeckApiGen _gen;
  String? _authToken;
  String? _csrfToken;

  /// Bearer token applied to every request as an Authorization header.
  ///
  /// [login] sets it automatically on native platforms; clients that
  /// persist the token across restarts can restore it here before
  /// calling anything else. Web builds never hold it and rely on the
  /// HttpOnly session cookie plus the CSRF header.
  @override
  String? get authToken => _authToken;
  @override
  set authToken(String? token) => _authToken = token;

  /// Adopts a login-shaped response: keeps the CSRF token, and on native
  /// platforms the bearer token, then maps to the plain result.
  ///
  /// Web builds deliberately do NOT retain the bearer: the HttpOnly
  /// session cookie is the credential there, and holding a JS-readable
  /// copy of an equivalent long-lived token would hand an XSS exactly
  /// the portable credential the HttpOnly flag exists to deny. Without
  /// a bearer, the interceptor rides the cookie and sends the CSRF
  /// header on mutations.
  LoginResult _adoptLogin(gen.LoginResponse body) {
    _csrfToken = body.csrfToken;
    final result = loginResultFromGen(body);
    if (!_isWebBuild) {
      _authToken = result.token;
    }
    return result;
  }

  /// True in browser builds. Detected via library availability so this
  /// pure-Dart package needs no Flutter dependency.
  static const _isWebBuild = bool.fromEnvironment('dart.library.js_interop');

  @override
  Future<ServerHealth> health() => _guard(() async {
    final body = _require((await _gen.getSystemApi().getHealth()).data);
    return ServerHealth(
      status: body.status,
      version: body.version,
      apiVersion: body.apiVersion,
    );
  });

  @override
  Future<BootstrapStatus> bootstrapStatus() => _guard(() async {
    final body = _require((await _gen.getAuthApi().getBootstrapStatus()).data);
    return BootstrapStatus(
      required: body.required_,
      signupEnabled: body.signupEnabled ?? false,
    );
  });

  @override
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) => _guard(() async {
    final response = await _gen.getAuthApi().bootstrap(
      bootstrapRequest: gen.BootstrapRequest(
        (b) => b
          ..username = username
          ..password = password
          ..displayName = displayName,
      ),
    );
    return _adoptLogin(_require(response.data));
  });

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) => _guard(() async {
    final response = await _gen.getAuthApi().login(
      loginRequest: gen.LoginRequest(
        (b) => b
          ..username = username
          ..password = password
          ..deviceName = deviceName,
      ),
    );
    return _adoptLogin(_require(response.data));
  });

  @override
  Future<SessionState> getSession() => _guard(() async {
    final body = _require((await _gen.getAuthApi().getSession()).data);
    // Unauthenticated probes carry no CSRF token; dropping a stale one is
    // correct because the session it belonged to is gone.
    _csrfToken = body.csrfToken;
    return sessionStateFromGen(body);
  });

  @override
  Future<LoginResult> refreshToken() => _guard(() async {
    final response = await _gen.getAuthApi().refreshToken();
    return _adoptLogin(_require(response.data));
  });

  @override
  Future<void> logout() => _guard(() async {
    await _gen.getAuthApi().logout();
    _authToken = null;
    _csrfToken = null;
  });

  @override
  Future<List<DeviceSession>> listSessions() => _guard(() async {
    final body = _require((await _gen.getAuthApi().listSessions()).data);
    return body.sessions.map(deviceSessionFromGen).toList();
  });

  @override
  Future<void> revokeSession(String sessionId) => _guard(() async {
    await _gen.getAuthApi().revokeSession(sessionId: sessionId);
  });

  @override
  Future<List<OidcProvider>> oidcProviders() => _guard(() async {
    final body = _require((await _gen.getAuthApi().listOidcProviders()).data);
    return body.providers
        .map((p) => oidcProviderFromGen(p, baseUrl: _baseUrl))
        .toList();
  });

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) => _guard(() async {
    final response = await _gen.getAuthApi().exchangeOidcCode(
      oidcExchangeRequest: gen.OidcExchangeRequest(
        (b) => b
          ..code = code
          ..verifier = verifier
          ..deviceName = deviceName,
      ),
    );
    return _adoptLogin(_require(response.data));
  });

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getLibraryApi().listItems(
      mediaType: mediaType == null ? null : mediaTypeToGen(mediaType),
      cursor: cursor,
      limit: limit,
    );
    return itemPageFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<ItemPage> browse(
    DiscoveryList list, {
    String? cursor,
    int? limit,
    int? seed,
  }) => _guard(() async {
    final response = await _gen.getLibraryApi().browseList(
      list: discoveryListToGen(list),
      cursor: cursor,
      limit: limit,
      seed: seed,
    );
    return itemPageFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<SearchResults> search(String q, {int? limit}) => _guard(() async {
    final response = await _gen.getLibraryApi().search(q: q, limit: limit);
    return searchResultsFromGen(_require(response.data));
  });

  @override
  Future<SimilarTracks> getSimilarTracks(String pid, {int? limit}) =>
      _guard(() async {
        final response = await _gen.getDiscoveryApi().getSimilarTracks(
          pid: pid,
          limit: limit,
        );
        return similarTracksFromGen(_require(response.data), baseUrl: _baseUrl);
      });

  @override
  Future<InstantMix> createInstantMix({
    String? seedPid,
    String? genre,
    double? adventurousness,
    int? size,
    List<String> excludePids = const [],
  }) => _guard(() async {
    final response = await _gen.getDiscoveryApi().createInstantMix(
      instantMixRequest: instantMixRequestToGen(
        seedPid: seedPid,
        genre: genre,
        adventurousness: adventurousness,
        size: size,
        excludePids: excludePids,
      ),
    );
    return instantMixFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<SonicPath> getSonicPath({
    required String from,
    required String to,
    int? length,
  }) => _guard(() async {
    final response = await _gen.getDiscoveryApi().getSonicPath(
      from: from,
      to: to,
      length: length,
    );
    return sonicPathFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<ItemDetail> getItem(String pid) => _guard(() async {
    final response = await _gen.getLibraryApi().getItem(pid: pid);
    return itemDetailFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<PlayInfo> getPlayInfo(
    String pid, {
    int? positionMs,
    bool? voiceBoost,
  }) => _guard(() async {
    final response = await _gen.getPlaybackApi().getPlayInfo(
      pid: pid,
      positionMs: positionMs,
      voiceBoost: voiceBoost,
    );
    return playInfoFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<PlayState> getPlayState(String pid) => _guard(() async {
    final response = await _gen.getPlaybackApi().getPlayState(pid: pid);
    return playStateFromGen(_require(response.data));
  });

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) => _guard(() async {
    final response = await _gen.getPlaybackApi().listPlayStates(
      playStateQuery: gen.PlayStateQuery((b) => b..pids.addAll(pids)),
    );
    return _require(response.data).states.map(playStateFromGen).toList();
  });

  @override
  Future<void> putPlayState(
    String pid,
    int positionMs, {
    DateTime? recordedAt,
  }) => _guard(() async {
    await _gen.getPlaybackApi().putPlayState(
      pid: pid,
      playStateUpdate: gen.PlayStateUpdate(
        (b) => b
          ..positionMs = positionMs
          ..recordedAt = recordedAt?.toUtc(),
      ),
    );
  });

  @override
  Future<PlayState> setStar(String pid, bool starred, {DateTime? recordedAt}) =>
      _guard(() async {
        final response = await _gen.getPlaybackApi().setStar(
          pid: pid,
          starUpdate: gen.StarUpdate(
            (b) => b
              ..starred = starred
              ..recordedAt = recordedAt?.toUtc(),
          ),
        );
        return playStateFromGen(_require(response.data));
      });

  @override
  Future<PlayState> setRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) => _guard(() async {
    final response = await _gen.getPlaybackApi().setRating(
      pid: pid,
      ratingUpdate: gen.RatingUpdate(
        (b) => b
          ..rating = rating
          ..recordedAt = recordedAt?.toUtc(),
      ),
    );
    return playStateFromGen(_require(response.data));
  });

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getSyncApi().syncCatalog(
      since: since,
      cursor: cursor,
      limit: limit,
    );
    return catalogSyncPageFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) =>
      _guard(() async {
        final response = await _gen.getSyncApi().syncServer(
          since: since,
          limit: limit,
        );
        return serverSyncPageFromGen(_require(response.data));
      });

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) => _guard(() async {
    final response = await _gen.getPlaybackApi().getDownloadInfo(pid: pid);
    return downloadInfoFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<List<AppPassword>> listAppPasswords() => _guard(() async {
    final body = _require((await _gen.getUsersApi().listAppPasswords()).data);
    return body.appPasswords.map(appPasswordFromGen).toList();
  });

  @override
  Future<AppPasswordCreated> createAppPassword(String label) =>
      _guard(() async {
        final response = await _gen.getUsersApi().createAppPassword(
          appPasswordCreate: gen.AppPasswordCreate((b) => b..label = label),
        );
        final body = _require(response.data);
        return AppPasswordCreated(
          id: body.id,
          label: body.label,
          createdAt: body.createdAt,
          lastUsedAt: body.lastUsedAt,
          secret: body.secret,
        );
      });

  @override
  Future<void> revokeAppPassword(String id) => _guard(() async {
    await _gen.getUsersApi().revokeAppPassword(appPasswordId: id);
  });

  @override
  Future<ListenOutcome> reportListens(List<ListenSession> sessions) =>
      _guard(() async {
        final response = await _gen.getPlaybackApi().reportListens(
          listenReport: gen.ListenReport(
            (b) => b..sessions.addAll(sessions.map(listenSessionToGen)),
          ),
        );
        return listenOutcomeFromGen(_require(response.data));
      });

  @override
  Future<ListeningStats> getListeningStats({String? range, String? bucket}) =>
      _guard(() async {
        final response = await _gen.getStatsApi().getListeningStats(
          range: range,
          bucket: bucket,
        );
        return listeningStatsFromGen(_require(response.data));
      });

  @override
  Future<ListeningHeatmap> getListeningHeatmap({int? year}) => _guard(() async {
    final response = await _gen.getStatsApi().getListeningHeatmap(year: year);
    return listeningHeatmapFromGen(_require(response.data));
  });

  @override
  Future<TopList> getTopList({
    required String kind,
    String? range,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getStatsApi().getTopList(
      kind: kind,
      range: range,
      limit: limit,
    );
    return topListFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getStatsApi().listListenLog(
      client: client,
      cursor: cursor,
      limit: limit,
    );
    return listenLogPageFromGen(_require(response.data));
  });

  @override
  Future<YearInReview> getYearInReview({int? year}) => _guard(() async {
    final response = await _gen.getStatsApi().getYearInReview(year: year);
    return yearInReviewFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<ServerYearInReview> getServerYearInReview({int? year}) =>
      _guard(() async {
        final response = await _gen.getStatsApi().getServerYearInReview(
          year: year,
        );
        return serverYearInReviewFromGen(
          _require(response.data),
          baseUrl: _baseUrl,
        );
      });

  @override
  Future<Prefs> getPrefs() => _guard(() async {
    return prefsFromGen(_require((await _gen.getUsersApi().getPrefs()).data));
  });

  @override
  Future<Prefs> putPrefs(Prefs prefs) => _guard(() async {
    final response = await _gen.getUsersApi().putPrefs(
      prefs: prefsToGen(prefs),
    );
    return prefsFromGen(_require(response.data));
  });

  @override
  Future<SubscriptionPage> listSubscriptions({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getPodcastsApi().listSubscriptions(
          cursor: cursor,
          limit: limit,
        );
        return subscriptionPageFromGen(
          _require(response.data),
          baseUrl: _baseUrl,
        );
      });

  @override
  Future<Subscription> subscribePodcast({
    required String url,
    String? sourceType,
    String? username,
    String? password,
    String? folder,
  }) => _guard(() async {
    final response = await _gen.getPodcastsApi().subscribePodcast(
      subscribeRequest: gen.SubscribeRequest(
        (b) => b
          ..url = url
          ..sourceType = sourceType
          ..username = username
          ..password = password
          ..folder = folder,
      ),
    );
    return subscriptionFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<PodcastDetail> getPodcast(String pid) => _guard(() async {
    final response = await _gen.getPodcastsApi().getPodcast(pid: pid);
    return podcastDetailFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<void> unsubscribePodcast(String pid, {bool removeDownloads = false}) =>
      _guard(() async {
        await _gen.getPodcastsApi().unsubscribePodcast(
          pid: pid,
          removeDownloads: removeDownloads ? true : null,
        );
      });

  @override
  Future<Subscription> putSubscriptionSettings(
    String pid,
    SubscriptionSettings settings,
  ) => _guard(() async {
    final response = await _gen.getPodcastsApi().putSubscriptionSettings(
      pid: pid,
      subscriptionSettings: subscriptionSettingsToGen(settings),
    );
    return subscriptionFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<EpisodePage> listEpisodes(String pid, {String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getPodcastsApi().listEpisodes(
          pid: pid,
          cursor: cursor,
          limit: limit,
        );
        return episodePageFromGen(_require(response.data), baseUrl: _baseUrl);
      });

  @override
  Future<EpisodeDetail> getEpisode(String pid) => _guard(() async {
    final response = await _gen.getPodcastsApi().getEpisode(pid: pid);
    return episodeDetailFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<Transcript> getEpisodeTranscript(String pid) => _guard(() async {
    final response = await _gen.getPodcastsApi().getEpisodeTranscript(pid: pid);
    return transcriptFromGen(_require(response.data));
  });

  @override
  Future<void> captureEpisodeTranscript(String pid) => _guard(() async {
    await _gen.getPodcastsApi().captureEpisodeTranscript(pid: pid);
  });

  @override
  Future<void> removeEpisodeDownload(String pid) => _guard(() async {
    await _gen.getPodcastsApi().removeEpisodeDownload(pid: pid);
  });

  @override
  Future<void> fetchEpisode(String pid) => _guard(() async {
    await _gen.getPodcastsApi().fetchEpisode(pid: pid);
  });

  @override
  Future<BookDetail> getBook(String pid) => _guard(() async {
    final response = await _gen.getBooksApi().getBook(pid: pid);
    return bookDetailFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<BookResume> getBookResume(String pid) => _guard(() async {
    final response = await _gen.getBooksApi().getBookResume(pid: pid);
    return bookResumeFromGen(_require(response.data));
  });

  @override
  Future<BookSettings> putBookSettings(String pid, BookSettings settings) =>
      _guard(() async {
        final response = await _gen.getBooksApi().putBookSettings(
          pid: pid,
          bookSettings: bookSettingsToGen(settings),
        );
        return bookSettingsFromGen(_require(response.data));
      });

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) => _guard(() async {
    final response = await _gen.getPlaybackApi().getSkipMap(
      pid: pid,
      partIndex: partIndex,
    );
    return skipMapFromGen(_require(response.data));
  });

  @override
  Future<String> exportOpml() => _guard(() async {
    return _require((await _gen.getPodcastsApi().exportOpml()).data);
  });

  @override
  Future<void> importOpml(String opml) => _guard(() async {
    await _gen.getPodcastsApi().importOpml(
      opmlImport: gen.OpmlImport((b) => b..opml = opml),
    );
  });

  @override
  Future<PlaylistPage> listPlaylists({
    String? cursor,
    int? limit,
    String? containsItem,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().listPlaylists(
      cursor: cursor,
      limit: limit,
      containsItem: containsItem,
    );
    return playlistPageFromGen(_require(response.data));
  });

  @override
  Future<Playlist> createPlaylist({
    required String name,
    required String kind,
    String? visibility,
    SmartRule? rule,
    List<String> itemPids = const [],
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().createPlaylist(
      playlistCreate: gen.PlaylistCreate(
        (b) => b
          ..name = name
          ..kind = kind
          ..visibility = visibility
          ..rule = rule == null ? null : smartRuleToGen(rule).toBuilder()
          ..itemPids = itemPids.isEmpty ? null : ListBuilder<String>(itemPids),
      ),
    );
    return playlistFromGen(_require(response.data));
  });

  @override
  Future<Playlist> getPlaylist(String pid) => _guard(() async {
    final response = await _gen.getPlaylistsApi().getPlaylist(pid: pid);
    return playlistFromGen(_require(response.data));
  });

  @override
  Future<Playlist> updatePlaylist(
    String pid, {
    String? name,
    String? visibility,
    SmartRule? rule,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().updatePlaylist(
      pid: pid,
      playlistUpdate: gen.PlaylistUpdate(
        (b) => b
          ..name = name
          ..visibility = visibility
          ..rule = rule == null ? null : smartRuleToGen(rule).toBuilder(),
      ),
    );
    return playlistFromGen(_require(response.data));
  });

  @override
  Future<void> deletePlaylist(String pid) => _guard(() async {
    await _gen.getPlaylistsApi().deletePlaylist(pid: pid);
  });

  @override
  Future<PlaylistItemsPage> listPlaylistItems(
    String pid, {
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().listPlaylistItems(
      pid: pid,
      cursor: cursor,
      limit: limit,
    );
    return playlistItemsPageFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<void> replacePlaylistItems(
    String pid,
    List<String> itemPids, {
    DateTime? baseUpdatedAt,
  }) => _guard(() async {
    await _gen.getPlaylistsApi().replacePlaylistItems(
      pid: pid,
      playlistItemsUpdate: gen.PlaylistItemsUpdate(
        (b) => b
          ..itemPids = ListBuilder<String>(itemPids)
          ..baseUpdatedAt = baseUpdatedAt?.toUtc(),
      ),
    );
  });

  @override
  Future<void> addPlaylistItems(String pid, List<String> itemPids) =>
      _guard(() async {
        await _gen.getPlaylistsApi().addPlaylistItems(
          pid: pid,
          playlistItemsUpdate: gen.PlaylistItemsUpdate(
            (b) => b..itemPids = ListBuilder<String>(itemPids),
          ),
        );
      });

  @override
  Future<void> removePlaylistItemAt(String pid, int position) =>
      _guard(() async {
        await _gen.getPlaylistsApi().removePlaylistItemAt(
          pid: pid,
          position: position,
        );
      });

  @override
  Future<PlaylistPreview> previewSmartRule(SmartRule rule, {int? limit}) =>
      _guard(() async {
        final response = await _gen.getPlaylistsApi().previewSmartRule(
          smartRule: smartRuleToGen(rule),
          limit: limit,
        );
        return playlistPreviewFromGen(
          _require(response.data),
          baseUrl: _baseUrl,
        );
      });

  @override
  Future<RuleFields> getRuleFields() => _guard(() async {
    final response = await _gen.getPlaylistsApi().getRuleFields();
    return ruleFieldsFromGen(_require(response.data));
  });

  @override
  Future<String> exportPlaylistM3u(String pid) => _guard(() async {
    return _require(
      (await _gen.getPlaylistsApi().exportPlaylistM3u(pid: pid)).data,
    );
  });

  @override
  Future<M3uImportResult> importPlaylistM3u({
    required String name,
    required String content,
    String? visibility,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().importPlaylistM3u(
      m3uImport: gen.M3uImport(
        (b) => b
          ..name = name
          ..content = content
          ..visibility = visibility,
      ),
    );
    return m3uImportResultFromGen(_require(response.data));
  });

  @override
  Future<PlaylistImportResult> importPlaylist({
    required String source,
    String? name,
    String? payload,
    List<PortableRef>? refs,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().importPlaylist(
      playlistImportRequest: gen.PlaylistImportRequest(
        (b) => b
          ..source_ = gen.PlaylistImportRequestSource_Enum.valueOf(source)
          ..name = name
          ..payload = payload
          ..refs = refs == null
              ? null
              : ListBuilder<gen.PortableRef>(refs.map(portableRefToGen)),
      ),
    );
    return playlistImportResultFromGen(_require(response.data));
  });

  @override
  Future<PortablePlaylist> exportPlaylistPortable(String pid) =>
      _guard(() async {
        final response = await _gen.getPlaylistsApi().exportPlaylistPortable(
          pid: pid,
        );
        return portablePlaylistFromGen(_require(response.data));
      });

  @override
  Future<SharePage> listShares({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getSharesApi().listShares(
          cursor: cursor,
          limit: limit,
        );
        return sharePageFromGen(_require(response.data), baseUrl: _baseUrl);
      });

  @override
  Future<Share> createShare({
    required String pid,
    int? expiresInHours,
    bool allowDownload = false,
    int? positionMs,
  }) => _guard(() async {
    final response = await _gen.getSharesApi().createShare(
      shareCreate: gen.ShareCreate(
        (b) => b
          ..pid = pid
          ..expiresInHours = expiresInHours
          ..allowDownload = allowDownload
          ..positionMs = positionMs,
      ),
    );
    return shareFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<void> revokeShare(String shareId) => _guard(() async {
    await _gen.getSharesApi().revokeShare(shareId: shareId);
  });

  @override
  Future<SimilarityStatus> getSimilarityStatus() => _guard(() async {
    final response = await _gen.getSimilarityApi().getSimilarityStatus();
    return similarityStatusFromGen(_require(response.data));
  });

  @override
  Future<List<RadioStation>> listRadioStations() => _guard(() async {
    final response = await _gen.getRadioApi().listRadioStations();
    return _require(
      response.data,
    ).stations.map(radioStationFromGen).toList(growable: false);
  });

  @override
  Future<List<PlayerEndpoint>> listPlayerEndpoints() => _guard(() async {
    final response = await _gen.getPlayerApi().listPlayerEndpoints();
    return _require(
      response.data,
    ).endpoints.map(playerEndpointFromGen).toList(growable: false);
  });

  @override
  Future<List<PlaybackSessionInfo>> listPlaybackSessions() => _guard(() async {
    final response = await _gen.getPlayerApi().listPlaybackSessions();
    return _require(
      response.data,
    ).sessions.map(playbackSessionFromGen).toList(growable: false);
  });

  @override
  Future<PlaybackSessionInfo> createPlaybackSession({
    required String endpointId,
    required List<String> itemPids,
    int index = 0,
    int positionMs = 0,
    bool play = true,
  }) => _guard(() async {
    final response = await _gen.getPlayerApi().createPlaybackSession(
      playbackSessionCreate: gen.PlaybackSessionCreate(
        (b) => b
          ..endpointId = endpointId
          ..itemPids.replace(itemPids)
          ..index = index
          ..positionMs = positionMs
          ..play = play,
      ),
    );
    return playbackSessionFromGen(_require(response.data));
  });

  @override
  Future<PlaybackSessionInfo> getPlaybackSession(String sessionId) =>
      _guard(() async {
        final response = await _gen.getPlayerApi().getPlaybackSession(
          sessionId: sessionId,
        );
        return playbackSessionFromGen(_require(response.data));
      });

  @override
  Future<void> deletePlaybackSession(String sessionId) => _guard(() async {
    await _gen.getPlayerApi().deletePlaybackSession(sessionId: sessionId);
  });

  @override
  Future<PlaybackSessionInfo> transferPlaybackSession(
    String sessionId,
    String endpointId,
  ) => _guard(() async {
    final response = await _gen.getPlayerApi().transferPlaybackSession(
      sessionId: sessionId,
      playbackSessionTransfer: gen.PlaybackSessionTransfer(
        (b) => b..endpointId = endpointId,
      ),
    );
    return playbackSessionFromGen(_require(response.data));
  });

  @override
  Future<RadioStation> createRadioStation({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) => _guard(() async {
    final response = await _gen.getRadioApi().createRadioStation(
      radioStationEdit: radioStationEditToGen(
        name: name,
        streamUrl: streamUrl,
        homepageUrl: homepageUrl,
        logoUrl: logoUrl,
      ),
    );
    return radioStationFromGen(_require(response.data));
  });

  @override
  Future<RadioStation> updateRadioStation(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) => _guard(() async {
    final response = await _gen.getRadioApi().updateRadioStation(
      pid: pid,
      radioStationEdit: radioStationEditToGen(
        name: name,
        streamUrl: streamUrl,
        homepageUrl: homepageUrl,
        logoUrl: logoUrl,
      ),
    );
    return radioStationFromGen(_require(response.data));
  });

  @override
  Future<void> deleteRadioStation(String pid) => _guard(() async {
    await _gen.getRadioApi().deleteRadioStation(pid: pid);
  });

  @override
  Future<RadioPlayInfo> getRadioPlayInfo(String pid) => _guard(() async {
    final response = await _gen.getRadioApi().getRadioPlayInfo(pid: pid);
    final info = _require(response.data);
    return RadioPlayInfo(
      url: resolveMediaUrl(_baseUrl, info.url),
      nowPlaying: info.nowPlaying,
    );
  });

  @override
  Future<List<RadioDirectoryEntry>> searchRadioDirectory(
    String query, {
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getRadioApi().searchRadioDirectory(
      query: query,
      limit: limit,
    );
    return _require(
      response.data,
    ).entries.map(radioDirectoryEntryFromGen).toList(growable: false);
  });

  @override
  Future<List<Scrobbler>> listScrobblers() => _guard(() async {
    final response = await _gen.getScrobblingApi().listScrobblers();
    return _require(
      response.data,
    ).scrobblers.map(scrobblerFromGen).toList(growable: false);
  });

  @override
  Future<Scrobbler> connectListenBrainz(String token, {String? apiUrl}) =>
      _guard(() async {
        final response = await _gen.getScrobblingApi().connectListenBrainz(
          listenBrainzConnect: gen.ListenBrainzConnect(
            (b) => b
              ..token = token
              ..apiUrl = apiUrl,
          ),
        );
        return scrobblerFromGen(_require(response.data));
      });

  @override
  Future<void> disconnectListenBrainz() => _guard(() async {
    await _gen.getScrobblingApi().disconnectListenBrainz();
  });

  @override
  Future<String> startLastfmConnect() => _guard(() async {
    final response = await _gen.getScrobblingApi().startLastfmConnect();
    return _require(response.data).authUrl;
  });

  @override
  Future<void> disconnectLastfm() => _guard(() async {
    await _gen.getScrobblingApi().disconnectLastfm();
  });

  @override
  Future<List<PushRegistration>> listPushRegistrations() => _guard(() async {
    final response = await _gen.getNotificationsApi().listPushRegistrations();
    return _require(
      response.data,
    ).registrations.map(pushRegistrationFromGen).toList(growable: false);
  });

  @override
  Future<PushRegistration> createPushRegistration({
    required String endpoint,
    String? label,
  }) => _guard(() async {
    final response = await _gen.getNotificationsApi().createPushRegistration(
      pushRegistrationCreate: gen.PushRegistrationCreate(
        (b) => b
          ..endpoint = endpoint
          ..label = label,
      ),
    );
    return pushRegistrationFromGen(_require(response.data));
  });

  @override
  Future<void> deletePushRegistration(String pid) => _guard(() async {
    await _gen.getNotificationsApi().deletePushRegistration(
      registrationId: pid,
    );
  });

  @override
  Future<List<NotifyEvent>> listNotificationEvents() => _guard(() async {
    final response = await _gen.getNotificationsApi().listNotificationEvents();
    return _require(
      response.data,
    ).events.map(notifyEventFromGen).toList(growable: false);
  });

  @override
  Future<List<NotificationTarget>> listServerNotificationTargets() =>
      _guard(() async {
        final response = await _gen
            .getNotificationsApi()
            .listServerNotificationTargets();
        return _require(
          response.data,
        ).targets.map(notificationTargetFromGen).toList(growable: false);
      });

  @override
  Future<NotificationTarget> createServerNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .createServerNotificationTarget(
          notificationTargetCreate: _targetCreateToGen(
            kind: kind,
            label: label,
            config: config,
            enabledEvents: enabledEvents,
          ),
        );
    return notificationTargetFromGen(_require(response.data));
  });

  @override
  Future<NotificationTarget> updateServerNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .updateServerNotificationTarget(
          targetId: pid,
          notificationTargetUpdate: _targetUpdateToGen(
            label: label,
            config: config,
            enabledEvents: enabledEvents,
          ),
        );
    return notificationTargetFromGen(_require(response.data));
  });

  @override
  Future<void> deleteServerNotificationTarget(String pid) => _guard(() async {
    await _gen.getNotificationsApi().deleteServerNotificationTarget(
      targetId: pid,
    );
  });

  @override
  Future<void> testServerNotificationTarget(String pid) => _guard(() async {
    await _gen.getNotificationsApi().testServerNotificationTarget(
      targetId: pid,
    );
  });

  @override
  Future<List<NotificationTarget>> listMyNotificationTargets() =>
      _guard(() async {
        final response = await _gen
            .getNotificationsApi()
            .listMyNotificationTargets();
        return _require(
          response.data,
        ).targets.map(notificationTargetFromGen).toList(growable: false);
      });

  @override
  Future<NotificationTarget> createMyNotificationTarget({
    required String kind,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .createMyNotificationTarget(
          notificationTargetCreate: _targetCreateToGen(
            kind: kind,
            label: label,
            config: config,
            enabledEvents: enabledEvents,
          ),
        );
    return notificationTargetFromGen(_require(response.data));
  });

  @override
  Future<NotificationTarget> updateMyNotificationTarget({
    required String pid,
    String? label,
    required Map<String, Object?> config,
    required List<String> enabledEvents,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .updateMyNotificationTarget(
          targetId: pid,
          notificationTargetUpdate: _targetUpdateToGen(
            label: label,
            config: config,
            enabledEvents: enabledEvents,
          ),
        );
    return notificationTargetFromGen(_require(response.data));
  });

  @override
  Future<void> deleteMyNotificationTarget(String pid) => _guard(() async {
    await _gen.getNotificationsApi().deleteMyNotificationTarget(targetId: pid);
  });

  @override
  Future<void> testMyNotificationTarget(String pid) => _guard(() async {
    await _gen.getNotificationsApi().testMyNotificationTarget(targetId: pid);
  });

  @override
  Future<ReviewEntryPage> listReviewQueue({
    String? status,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getReviewApi().listReviewQueue(
      status: status,
      cursor: cursor,
      limit: limit,
    );
    return reviewEntryPageFromGen(_require(response.data));
  });

  @override
  Future<ReviewEntryDetail> getReviewEntry(String entryId) => _guard(() async {
    final response = await _gen.getReviewApi().getReviewEntry(entryId: entryId);
    return reviewEntryDetailFromGen(_require(response.data));
  });

  @override
  Future<ReviewDecideResult> decideReviewEntry(
    String entryId, {
    required String action,
    String? candidateMbid,
  }) => _guard(() async {
    final response = await _gen.getReviewApi().decideReviewEntry(
      entryId: entryId,
      reviewDecision: gen.ReviewDecision(
        (b) => b
          ..action = reviewActionToGen(action)
          ..candidateMbid = candidateMbid,
      ),
    );
    final body = _require(response.data);
    return ReviewDecideResult(
      entry: reviewEntryFromGen(body.entry),
      warnings: body.warnings?.toList() ?? const [],
    );
  });

  @override
  Future<ReviewEntry> revertReviewEntry(String entryId) => _guard(() async {
    final response = await _gen.getReviewApi().revertReviewEntry(
      entryId: entryId,
    );
    return reviewEntryFromGen(_require(response.data));
  });

  @override
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  }) => _guard(() async {
    final response = await _gen.getReviewApi().decideReviewBulk(
      reviewBulkDecision: gen.ReviewBulkDecision(
        (b) => b
          ..entryIds = ListBuilder<String>(entryIds)
          ..action = reviewBulkActionToGen(action),
      ),
    );
    return _require(
      response.data,
    ).results.map(reviewBulkOutcomeFromGen).toList(growable: false);
  });

  @override
  Future<ReviewStats> getReviewStats() => _guard(() async {
    final response = await _gen.getReviewApi().getReviewStats();
    return reviewStatsFromGen(_require(response.data));
  });

  @override
  Future<List<LibraryInfo>> listLibraries() => _guard(() async {
    final response = await _gen.getAdminApi().listLibraries();
    return _require(
      response.data,
    ).libraries.map(libraryInfoFromGen).toList(growable: false);
  });

  @override
  Future<LibraryInfo> createLibrary({
    required String name,
    required String path,
    String? media,
    bool? managed,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().createLibrary(
      libraryCreate: gen.LibraryCreate(
        (b) => b
          ..name = name
          ..path = path
          ..media = gen.LibraryCreateMediaEnum.valueOf(media ?? 'mixed')
          ..managed = managed ?? false,
      ),
    );
    return libraryInfoFromGen(_require(response.data));
  });

  @override
  Future<String> getLibraryMatching(String libraryPid) => _guard(() async {
    final response = await _gen.getReviewApi().getLibraryMatching(
      pid: libraryPid,
    );
    return libraryMatchingModeFromGen(_require(response.data));
  });

  @override
  Future<String> setLibraryMatching(String libraryPid, String mode) =>
      _guard(() async {
        final response = await _gen.getReviewApi().setLibraryMatching(
          pid: libraryPid,
          libraryMatching: libraryMatchingModeToGen(mode),
        );
        return libraryMatchingModeFromGen(_require(response.data));
      });

  @override
  Future<UploadPage> listUploads({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getUploadsApi().listUploads(
          cursor: cursor,
          limit: limit,
        );
        return uploadPageFromGen(_require(response.data));
      });

  @override
  Future<UploadSession> createUpload({
    required String fileName,
    required int sizeBytes,
    required String mediaType,
    String? libraryPid,
    String? sha256,
    String? batchId,
    String? batchPath,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createUpload(
      uploadCreate: gen.UploadCreate(
        (b) => b
          ..fileName = fileName
          ..sizeBytes = sizeBytes
          ..mediaType = gen.MediaType.valueOf(mediaType)
          ..libraryPid = libraryPid
          ..sha256 = sha256
          ..batchId = batchId
          ..batchPath = batchPath,
      ),
    );
    return uploadSessionFromGen(_require(response.data));
  });

  @override
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createUploadBatch(
      uploadBatchCreate: gen.UploadBatchCreate(
        (b) => b
          ..grouping = uploadGroupingToGen(grouping)
          ..mediaType = gen.MediaType.valueOf(mediaType)
          ..libraryPid = libraryPid,
      ),
    );
    return uploadBatchFromGen(_require(response.data));
  });

  @override
  Future<UploadBatch> completeUploadBatch(String batchId) => _guard(() async {
    final response = await _gen.getUploadsApi().completeUploadBatch(
      batchId: batchId,
    );
    return uploadBatchFromGen(_require(response.data));
  });

  @override
  Future<UploadSession> getUpload(String uploadId) => _guard(() async {
    final response = await _gen.getUploadsApi().getUpload(uploadId: uploadId);
    return uploadSessionFromGen(_require(response.data));
  });

  @override
  Future<void> deleteUpload(String uploadId) => _guard(() async {
    await _gen.getUploadsApi().deleteUpload(uploadId: uploadId);
  });

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().putUploadData(
      uploadId: uploadId,
      offset: offset,
      body: MultipartFile.fromBytes(bytes),
    );
    return uploadSessionFromGen(_require(response.data));
  });

  @override
  Future<UploadSession> completeUpload(String uploadId) => _guard(() async {
    final response = await _gen.getUploadsApi().completeUpload(
      uploadId: uploadId,
    );
    return uploadSessionFromGen(_require(response.data));
  });

  @override
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    String? libraryPid,
    String? format,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createAcquisition(
      acquisitionRequest: gen.AcquisitionRequest(
        (b) => b
          ..url = url
          ..mediaType = mediaTypeToGen(mediaType)
          ..libraryPid = libraryPid
          // "best" is the server default, so it rides as an absent field.
          ..format = switch (format) {
            null || '' || 'best' => null,
            final f => gen.AcquisitionFormat.valueOf(f),
          },
      ),
    );
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<MetadataFields> getMetadataFields() => _guard(() async {
    final response = await _gen.getMetadataApi().getMetadataFields();
    return metadataFieldsFromGen(_require(response.data));
  });

  @override
  Future<ItemMetadata> getItemMetadata(String pid) => _guard(() async {
    final response = await _gen.getMetadataApi().getItemMetadata(pid: pid);
    return itemMetadataFromGen(_require(response.data));
  });

  @override
  Future<MetadataEditResult> editItemMetadata(
    String pid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().editItemMetadata(
      pid: pid,
      metadataEdit: gen.MetadataEdit(
        (b) => b
          ..fields = MapBuilder<String, String>(fields)
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<BulkEditResult> bulkEditMetadata({
    required List<String> itemPids,
    required Map<String, String> fields,
    bool writeBack = false,
    bool skipLocked = false,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().bulkEditMetadata(
      bulkEdit: gen.BulkEdit(
        (b) => b
          ..itemPids = ListBuilder<String>(itemPids)
          ..fields = MapBuilder<String, String>(fields)
          ..writeBack = writeBack
          ..skipLocked = skipLocked
          ..force = force,
      ),
    );
    return bulkEditResultFromGen(_require(response.data));
  });

  @override
  Future<MetadataEditResult> setItemCredits(
    String pid, {
    required String role,
    required List<String> names,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemCredits(
      pid: pid,
      creditsEdit: gen.CreditsEdit(
        (b) => b
          ..role = role
          ..names = ListBuilder<String>(names)
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<MetadataEditResult> setItemLyrics(
    String pid, {
    String? lrc,
    String? plain,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemLyrics(
      pid: pid,
      lyricsEdit: gen.LyricsEdit(
        (b) => b
          ..lrc = lrc
          ..plain = plain
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<void> clearItemLyrics(String pid) => _guard(() async {
    await _gen.getMetadataApi().clearItemLyrics(pid: pid);
  });

  @override
  Future<MetadataEditResult> setBookChapters(
    String pid, {
    required List<ChapterEdit> chapters,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setBookChapters(
      pid: pid,
      chaptersEdit: gen.ChaptersEdit(
        (b) => b
          ..chapters = ListBuilder<gen.ChapterMark>(
            chapters.map(chapterEditToGen),
          )
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<List<ArtRoleInfo>> getItemArtRoles(String pid) => _guard(() async {
    final response = await _gen.getLibraryApi().getItemArtRoles(pid: pid);
    return _require(
      response.data,
    ).roles.map(artRoleInfoFromGen).toList(growable: false);
  });

  @override
  Future<MetadataEditResult> setItemArtwork(
    String pid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
    bool lock = true,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemArtwork(
      pid: pid,
      body: MultipartFile.fromBytes(bytes),
      role: gen.ArtRole.valueOf(role),
      writeBack: writeBack,
      lock: lock,
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<void> clearItemArtwork(String pid, {String role = 'front'}) =>
      _guard(() async {
        await _gen.getMetadataApi().clearItemArtwork(
          pid: pid,
          role: gen.ArtRole.valueOf(role),
        );
      });

  @override
  Future<MetadataEditResult> setEntityArtwork(
    String entityType,
    String entityPid, {
    required Uint8List bytes,
    String role = 'front',
    bool writeBack = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setEntityArtwork(
      entityType: entityType,
      entityPid: entityPid,
      body: MultipartFile.fromBytes(bytes),
      role: gen.ArtRole.valueOf(role),
      writeBack: writeBack,
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemTag(
      pid: pid,
      key: key,
      tagEdit: gen.TagEdit(
        (b) => b
          ..values = ListBuilder<String>(values)
          ..lock = lock
          ..force = force,
      ),
    );
    return tagEditResultFromGen(_require(response.data));
  });

  @override
  Future<void> clearItemTag(String pid, String key) => _guard(() async {
    await _gen.getMetadataApi().clearItemTag(pid: pid, key: key);
  });

  @override
  Future<List<String>> setItemLocks(
    String pid, {
    required List<String> fields,
    required bool locked,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemLocks(
      pid: pid,
      locksEdit: gen.LocksEdit(
        (b) => b
          ..fields = ListBuilder<String>(fields)
          ..locked = locked,
      ),
    );
    return _require(response.data).lockedFields.toList(growable: false);
  });

  @override
  Future<MetadataEditResult> editEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> edits,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().editEntity(
      entityType: entityType,
      entityPid: entityPid,
      entityEdit: gen.EntityEdit(
        (b) => b
          ..edits = MapBuilder<String, String>(edits)
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<List<EntityCuratedField>> getEntityCuration(
    String entityType,
    String entityPid,
  ) => _guard(() async {
    final response = await _gen.getMetadataApi().getEntityCuration(
      entityType: entityType,
      entityPid: entityPid,
    );
    return _require(
      response.data,
    ).curated.map(entityCuratedFieldFromGen).toList(growable: false);
  });

  @override
  Future<MetadataEditResult> setReleaseStatus(
    String pid, {
    required bool unofficial,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setReleaseStatus(
      pid: pid,
      releaseStatusEdit: gen.ReleaseStatusEdit(
        (b) => b..unofficial = unofficial,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<String> rematchItem(String pid) => _guard(() async {
    final response = await _gen.getMetadataApi().rematchItem(pid: pid);
    return _require(response.data).reviewEntryId;
  });

  @override
  Future<EnrichItemResult> enrichItem(
    String pid, {
    required List<String> want,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().enrichItem(
      pid: pid,
      enrichItemRequest: gen.EnrichItemRequest(
        (b) => b
          ..want = ListBuilder<gen.EnrichItemRequestWantEnum>(
            want.map(gen.EnrichItemRequestWantEnum.valueOf),
          ),
      ),
    );
    return enrichItemResultFromGen(_require(response.data));
  });

  @override
  Future<HealthSummary> getLibraryHealth() => _guard(() async {
    final response = await _gen.getHealthApi().getLibraryHealth();
    return healthSummaryFromGen(_require(response.data));
  });

  @override
  Future<HealthIssuePage> listHealthIssues({
    String? rule,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().listHealthIssues(
      rule: rule,
      cursor: cursor,
      limit: limit,
    );
    return healthIssuePageFromGen(_require(response.data));
  });

  @override
  Future<FileDiagnosticPage> listFileDiagnostics({
    String? origin,
    String? code,
    String? severity,
    String? library,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().listFileDiagnostics(
      origin: origin,
      code: code,
      severity: severity,
      library_: library,
      cursor: cursor,
      limit: limit,
    );
    return fileDiagnosticPageFromGen(_require(response.data));
  });

  @override
  Future<List<DiagnosticCount>> getDiagnosticSummary({
    String? origin,
    String? code,
    String? severity,
    String? library,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().getDiagnosticSummary(
      origin: origin,
      code: code,
      severity: severity,
      library_: library,
    );
    return _require(
      response.data,
    ).counts.map(diagnosticCountFromGen).toList(growable: false);
  });

  @override
  Future<void> sweepLibraryHealth() => _guard(() async {
    await _gen.getHealthApi().sweepLibraryHealth();
  });

  @override
  Future<int> fixHealthIssues({required String rule, List<String>? itemPids}) =>
      _guard(() async {
        final response = await _gen.getHealthApi().fixHealthIssues(
          healthFixRequest: gen.HealthFixRequest(
            (b) => b
              ..rule = rule
              ..itemPids = itemPids == null
                  ? null
                  : ListBuilder<String>(itemPids),
          ),
        );
        return _require(response.data).queued;
      });

  @override
  Future<List<DuplicateGroup>> listDuplicates() => _guard(() async {
    final response = await _gen.getHealthApi().listDuplicates();
    return _require(
      response.data,
    ).groups.map(duplicateGroupFromGen).toList(growable: false);
  });

  @override
  Future<MergeOutcome> mergeDuplicates({
    required String entityType,
    required String survivorPid,
    required List<String> loserPids,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().mergeDuplicates(
      mergeRequest: gen.MergeRequest(
        (b) => b
          ..entityType = mergeEntityTypeToGen(entityType)
          ..survivorPid = survivorPid
          ..loserPids = ListBuilder<String>(loserPids),
      ),
    );
    final body = _require(response.data);
    return MergeOutcome(merged: body.merged, childrenMoved: body.childrenMoved);
  });

  @override
  Future<List<UpgradeGroup>> listUpgrades() => _guard(() async {
    final response = await _gen.getHealthApi().listUpgrades();
    return _require(
      response.data,
    ).groups.map(upgradeGroupFromGen).toList(growable: false);
  });

  @override
  Future<int> resolveUpgrade({
    required String keepItemPid,
    required List<String> removeItemPids,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().resolveUpgrade(
      upgradeResolveRequest: gen.UpgradeResolveRequest(
        (b) => b
          ..keepItemPid = keepItemPid
          ..removeItemPids = ListBuilder<String>(removeItemPids),
      ),
    );
    return _require(response.data).trashed;
  });

  @override
  Future<List<OrganizeProfile>> listOrganizeProfiles() => _guard(() async {
    final response = await _gen.getOrganizeApi().listOrganizeProfiles();
    return _require(
      response.data,
    ).profiles.map(organizeProfileFromGen).toList(growable: false);
  });

  @override
  Future<OrganizePlan> previewOrganize({
    required String profile,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().previewOrganize(
      organizeRequest: gen.OrganizeRequest(
        (b) => b
          ..profile = profile
          ..itemPids = itemPids == null ? null : ListBuilder<String>(itemPids),
      ),
    );
    return organizePlanFromGen(_require(response.data));
  });

  @override
  Future<OrganizeReport> applyOrganize({
    required String profile,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().applyOrganize(
      organizeRequest: gen.OrganizeRequest(
        (b) => b
          ..profile = profile
          ..itemPids = itemPids == null ? null : ListBuilder<String>(itemPids),
      ),
    );
    return organizeReportFromGen(_require(response.data));
  });

  @override
  Future<ToolTask> mergeBook(
    String pid, {
    List<String>? titles,
    bool keepOriginals = false,
  }) => _guard(() async {
    final response = await _gen.getToolsApi().mergeBook(
      pid: pid,
      bookMergeRequest: gen.BookMergeRequest(
        (b) => b
          ..titles = titles == null ? null : ListBuilder<String>(titles)
          ..keepOriginals = keepOriginals,
      ),
    );
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<ToolTask> splitBook(String pid, {bool keepOriginals = false}) =>
      _guard(() async {
        final response = await _gen.getToolsApi().splitBook(
          pid: pid,
          bookSplitRequest: gen.BookSplitRequest(
            (b) => b..keepOriginals = keepOriginals,
          ),
        );
        return toolTaskFromGen(_require(response.data));
      });

  @override
  Future<ToolTask> splitCueRip(String pid, {bool keepOriginals = false}) =>
      _guard(() async {
        final response = await _gen.getToolsApi().splitCueRip(
          pid: pid,
          cueSplitRequest: gen.CueSplitRequest(
            (b) => b..keepOriginals = keepOriginals,
          ),
        );
        return toolTaskFromGen(_require(response.data));
      });

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getToolsApi().listToolTasks(
          cursor: cursor,
          limit: limit,
        );
        return toolTaskPageFromGen(_require(response.data));
      });

  @override
  Future<ToolTask> getToolTask(String taskId) => _guard(() async {
    final response = await _gen.getToolsApi().getToolTask(taskId: taskId);
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<EnrichmentStatus> getEnrichmentStatus() => _guard(() async {
    final response = await _gen.getEnrichmentApi().getEnrichmentStatus();
    return enrichmentStatusFromGen(_require(response.data));
  });

  @override
  Future<String> runEnrichment({bool force = false}) => _guard(() async {
    final response = await _gen.getEnrichmentApi().runEnrichment(
      enrichmentRunRequest: gen.EnrichmentRunRequest((b) => b..force = force),
    );
    return _require(response.data).jobPid;
  });

  @override
  Future<UserPage> listUsers({String? cursor, int? limit}) => _guard(() async {
    final response = await _gen.getUsersApi().listUsers(
      cursor: cursor,
      limit: limit,
    );
    return userPageFromGen(_require(response.data));
  });

  @override
  Future<UserAccount> createUser({
    required String username,
    required String password,
    String? displayName,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) => _guard(() async {
    final response = await _gen.getUsersApi().createUser(
      userCreate: gen.UserCreate(
        (b) => b
          ..username = username
          ..password = password
          ..displayName = displayName
          ..roles = rolesToGen(roles)
          ..libraryAccess = libraryAccess == null
              ? null
              : libraryAccessToGen(libraryAccess).toBuilder()
          ..uploadEnabled = uploadEnabled
          ..uploadQuotaBytes = uploadQuotaBytes
          ..permissions = permissions == null
              ? null
              : permissionsToGen(permissions).toBuilder(),
      ),
    );
    return userAccountFromGen(_require(response.data));
  });

  @override
  Future<UserAccount> updateUser(
    String userId, {
    String? displayName,
    List<String>? roles,
    bool? disabled,
    LibraryAccess? libraryAccess,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
    Permissions? permissions,
  }) => _guard(() async {
    final response = await _gen.getUsersApi().updateUser(
      userId: userId,
      userUpdate: gen.UserUpdate(
        (b) => b
          ..displayName = displayName
          ..roles = rolesToGen(roles)
          ..disabled = disabled
          ..libraryAccess = libraryAccess == null
              ? null
              : libraryAccessToGen(libraryAccess).toBuilder()
          ..uploadEnabled = uploadEnabled
          ..uploadQuotaBytes = uploadQuotaBytes
          ..permissions = permissions == null
              ? null
              : permissionsToGen(permissions).toBuilder(),
      ),
    );
    return userAccountFromGen(_require(response.data));
  });

  @override
  Future<UserAccount> getUser(String userId) => _guard(() async {
    final response = await _gen.getUsersApi().getUser(userId: userId);
    return userAccountFromGen(_require(response.data));
  });

  @override
  Future<void> deleteUser(String userId) => _guard(() async {
    await _gen.getUsersApi().deleteUser(userId: userId);
  });

  @override
  Future<void> setUserPassword(String userId, String newPassword) => _guard(
    () async {
      await _gen.getUsersApi().setPassword(
        userId: userId,
        passwordChange: gen.PasswordChange((b) => b..newPassword = newPassword),
      );
    },
  );

  @override
  Future<void> revokeUserSessions(String userId) => _guard(() async {
    await _gen.getUsersApi().revokeUserSessions(userId: userId);
  });

  @override
  Future<SignupResult> signup({
    required String username,
    required String password,
    String? displayName,
    String? inviteToken,
  }) => _guard(() async {
    final response = await _gen.getAuthApi().signup(
      signupRequest: gen.SignupRequest(
        (b) => b
          ..username = username
          ..password = password
          ..displayName = displayName
          ..inviteToken = inviteToken,
      ),
    );
    return SignupResult(state: _require(response.data).state.name);
  });

  @override
  Future<UserPage> listSignupRequests({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getUsersApi().listSignupRequests(
          cursor: cursor,
          limit: limit,
        );
        return userPageFromGen(_require(response.data));
      });

  @override
  Future<UserAccount> approveSignupRequest(
    String userId, {
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? uploadQuotaBytes,
  }) => _guard(() async {
    final response = await _gen.getUsersApi().approveSignupRequest(
      userId: userId,
      signupApproval: gen.SignupApproval(
        (b) => b
          ..roles = rolesToGen(roles)
          ..libraryAccess = libraryAccess == null
              ? null
              : libraryAccessToGen(libraryAccess).toBuilder()
          ..permissions = permissions == null
              ? null
              : permissionsToGen(permissions).toBuilder()
          ..uploadEnabled = uploadEnabled
          ..uploadQuotaBytes = uploadQuotaBytes,
      ),
    );
    return userAccountFromGen(_require(response.data));
  });

  @override
  Future<void> rejectSignupRequest(String userId) => _guard(() async {
    await _gen.getUsersApi().rejectSignupRequest(userId: userId);
  });

  @override
  Future<List<Invite>> listInvites() => _guard(() async {
    final response = await _gen.getUsersApi().listInvites();
    return _require(
      response.data,
    ).invites.map(inviteFromGen).toList(growable: false);
  });

  @override
  Future<InviteCreated> createInvite({
    String? note,
    List<String>? roles,
    LibraryAccess? libraryAccess,
    Permissions? permissions,
    bool? uploadEnabled,
    int? maxUses,
    DateTime? expiresAt,
  }) => _guard(() async {
    final response = await _gen.getUsersApi().createInvite(
      inviteCreate: gen.InviteCreate(
        (b) => b
          ..note = note
          ..roles = rolesToGen(roles)
          ..libraryAccess = libraryAccess == null
              ? null
              : libraryAccessToGen(libraryAccess).toBuilder()
          ..permissions = permissions == null
              ? null
              : permissionsToGen(permissions).toBuilder()
          ..uploadEnabled = uploadEnabled
          ..maxUses = maxUses
          ..expiresAt = expiresAt?.toUtc(),
      ),
    );
    return inviteCreatedFromGen(_require(response.data));
  });

  @override
  Future<void> revokeInvite(String inviteId) => _guard(() async {
    await _gen.getUsersApi().revokeInvite(inviteId: inviteId);
  });

  @override
  Future<AuditEventPage> listAuditEvents({
    String? cursor,
    int? limit,
    String? action,
    String? actorId,
    String? targetPid,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().listAuditEvents(
      cursor: cursor,
      limit: limit,
      action: action,
      actorId: actorId,
      targetPid: targetPid,
    );
    return auditEventPageFromGen(_require(response.data));
  });

  @override
  Future<AdminSettings> getAdminSettings() => _guard(() async {
    final response = await _gen.getAdminApi().getAdminSettings();
    return adminSettingsFromGen(_require(response.data));
  });

  @override
  Future<AdminSettings> putAdminSettings(AdminSettings settings) =>
      _guard(() async {
        final response = await _gen.getAdminApi().putAdminSettings(
          adminSettings: adminSettingsToGen(settings),
        );
        return adminSettingsFromGen(_require(response.data));
      });

  @override
  Future<TranscodingLimits> getTranscodingLimits() => _guard(() async {
    final response = await _gen.getAdminApi().getTranscodingLimits();
    return transcodingLimitsFromGen(_require(response.data));
  });

  @override
  Future<TranscodingLimits> putTranscodingLimits(TranscodingLimits limits) =>
      _guard(() async {
        final response = await _gen.getAdminApi().putTranscodingLimits(
          transcodingLimits: transcodingLimitsToGen(limits),
        );
        return transcodingLimitsFromGen(_require(response.data));
      });

  @override
  Future<ScrobblingAdminConfig> getScrobblingConfig() => _guard(() async {
    final response = await _gen.getAdminApi().getScrobblingConfig();
    return scrobblingAdminConfigFromGen(_require(response.data));
  });

  @override
  Future<ScrobblingAdminConfig> putScrobblingConfig({
    required String apiKey,
    required String secret,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().putScrobblingConfig(
      scrobblingAdminConfigPut: gen.ScrobblingAdminConfigPut(
        (b) => b
          ..lastfmApiKey = apiKey
          ..lastfmSecret = secret,
      ),
    );
    return scrobblingAdminConfigFromGen(_require(response.data));
  });

  @override
  Future<List<Schedule>> listSchedules() => _guard(() async {
    final response = await _gen.getAdminApi().listSchedules();
    return _require(
      response.data,
    ).schedules.map(scheduleFromGen).toList(growable: false);
  });

  @override
  Future<Schedule> putSchedule(
    String kind, {
    required String cron,
    required bool enabled,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().putSchedule(
      kind: gen.ScheduleKind.valueOf(kind),
      schedulePut: gen.SchedulePut(
        (b) => b
          ..cron = cron
          ..enabled = enabled,
      ),
    );
    return scheduleFromGen(_require(response.data));
  });

  @override
  Future<List<Backup>> listBackups() => _guard(() async {
    final response = await _gen.getAdminApi().listBackups();
    return _require(
      response.data,
    ).backups.map(backupFromGen).toList(growable: false);
  });

  @override
  Future<Backup> createBackup() => _guard(() async {
    final response = await _gen.getAdminApi().createBackup();
    return backupFromGen(_require(response.data));
  });

  @override
  Future<Backup> getBackup(String backupId) => _guard(() async {
    final response = await _gen.getAdminApi().getBackup(backupId: backupId);
    return backupFromGen(_require(response.data));
  });

  @override
  Future<void> deleteBackup(String backupId) => _guard(() async {
    await _gen.getAdminApi().deleteBackup(backupId: backupId);
  });

  @override
  String backupArchiveUrl(String backupId) =>
      '$_baseUrl/api/v1/admin/backups/$backupId/archive';

  @override
  Future<Backup> importBackup({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().importBackup(
      // fromStream defers the read to request time, so the archive
      // flows through in transport-sized pieces instead of being
      // buffered whole.
      body: MultipartFile.fromStream(openRead, sizeBytes),
    );
    return backupFromGen(_require(response.data));
  });

  @override
  Future<RestorePlan> stageRestore(String backupId) => _guard(() async {
    final response = await _gen.getAdminApi().stageRestore(backupId: backupId);
    return restorePlanFromGen(_require(response.data));
  });

  @override
  Future<RestorePlan?> getStagedRestore() => _guard(() async {
    try {
      final response = await _gen.getAdminApi().getStagedRestore();
      return restorePlanFromGen(_require(response.data));
    } on DioException catch (e) {
      // No staged restore is a state, not an error, for callers.
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  });

  @override
  Future<void> cancelStagedRestore() => _guard(() async {
    await _gen.getAdminApi().cancelStagedRestore();
  });

  @override
  Future<ToolTask> createMigration({
    required String source,
    required String serverUrl,
    String? username,
    String? password,
    String? token,
    MigrationOptions? options,
    bool dryRun = false,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().createMigration(
      migrationCreate: gen.MigrationCreate(
        (b) => b
          ..source_ = source
          ..serverUrl = serverUrl
          ..username = username
          ..password = password
          ..token = token
          ..options = options == null
              ? null
              : migrationOptionsToGen(options).toBuilder()
          ..dryRun = dryRun,
      ),
    );
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<TrashList> listTrash({bool includeRestored = false, int? limit}) =>
      _guard(() async {
        final response = await _gen.getAdminApi().listTrash(
          includeRestored: includeRestored,
          limit: limit,
        );
        return TrashList(
          entries: _require(
            response.data,
          ).entries.map(trashEntryFromGen).toList(growable: false),
        );
      });

  @override
  Future<void> restoreTrashEntry(String trashId) => _guard(() async {
    await _gen.getAdminApi().restoreTrashEntry(trashId: trashId);
  });

  @override
  Future<TrashEmptyResult> emptyTrash() => _guard(() async {
    final body = _require((await _gen.getAdminApi().emptyTrash()).data);
    return TrashEmptyResult(
      purged: body.purged,
      errored: body.errored,
      reclaimedBytes: body.reclaimedBytes,
    );
  });

  @override
  Future<int> purgeTrashEntry(String trashId) => _guard(() async {
    final body = _require(
      (await _gen.getAdminApi().purgeTrashEntry(trashId: trashId)).data,
    );
    return body.reclaimedBytes;
  });

  @override
  Future<List<Job>> listJobs() => _guard(() async {
    final response = await _gen.getAdminApi().listJobs();
    return _require(response.data).jobs.map(jobFromGen).toList(growable: false);
  });

  @override
  Future<bool> getLibraryReadOnly(String libraryPid) => _guard(() async {
    final response = await _gen.getAdminApi().getLibraryReadOnly(
      pid: libraryPid,
    );
    return _require(response.data).readOnly;
  });

  @override
  Future<bool> setLibraryReadOnly(String libraryPid, bool readOnly) =>
      _guard(() async {
        final response = await _gen.getAdminApi().setLibraryReadOnly(
          pid: libraryPid,
          libraryReadOnly: gen.LibraryReadOnly((b) => b..readOnly = readOnly),
        );
        return _require(response.data).readOnly;
      });

  @override
  Future<DeleteItemsResult> deleteLibraryItems({
    required List<String> pids,
    String? mode,
    bool dryRun = false,
  }) => _guard(() async {
    final response = await _gen.getLibraryApi().deleteLibraryItems(
      deleteItemsRequest: gen.DeleteItemsRequest(
        (b) => b
          ..pids = ListBuilder<String>(pids)
          ..mode = mode == null
              ? null
              : gen.DeleteItemsRequestModeEnum.valueOf(mode)
          ..dryRun = dryRun,
      ),
    );
    return deleteItemsResultFromGen(_require(response.data));
  });

  /// Runs [body], mapping transport failures to the structured error model.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (e) {
      throw apiExceptionFromDio(e);
    }
  }

  T _require<T>(T? body) {
    if (body == null) {
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'empty response body',
      );
    }
    return body;
  }
}

/// Maps transport-level failures to the spec's structured error model.
///
/// Dio only parses the body when the response advertises a JSON content
/// type; an intermediary that drops the header leaves a raw string, so
/// strings get one decode attempt before falling back to a transport
/// error.
WaxDeckApiException apiExceptionFromDio(DioException e) {
  var data = e.response?.data;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } on FormatException {
      // Not JSON; the transport fallback below reports it.
    }
  }
  if (data is Map) {
    final code = data['code'];
    final message = data['message'];
    if (code is String && message is String) {
      return WaxDeckApiException(
        code: code,
        message: message,
        statusCode: e.response?.statusCode,
      );
    }
  }
  return WaxDeckApiException(
    code: 'transport',
    message: e.message ?? 'network error',
    statusCode: e.response?.statusCode,
  );
}

/// Builds the generated create body for a notification target. Config
/// values wrap as JsonObject; nulls are dropped (absent, not null, on
/// the wire).
gen.NotificationTargetCreate _targetCreateToGen({
  required String kind,
  String? label,
  required Map<String, Object?> config,
  required List<String> enabledEvents,
}) {
  return gen.NotificationTargetCreate(
    (b) => b
      ..kind = gen.NotificationTargetKind.valueOf(kind)
      ..label = label
      ..config = _configToGen(config)
      ..enabledEvents = ListBuilder<String>(enabledEvents),
  );
}

gen.NotificationTargetUpdate _targetUpdateToGen({
  String? label,
  required Map<String, Object?> config,
  required List<String> enabledEvents,
}) {
  return gen.NotificationTargetUpdate(
    (b) => b
      ..label = label
      ..config = _configToGen(config)
      ..enabledEvents = ListBuilder<String>(enabledEvents),
  );
}

MapBuilder<String, JsonObject?> _configToGen(Map<String, Object?> config) {
  final builder = MapBuilder<String, JsonObject?>();
  for (final entry in config.entries) {
    final value = entry.value;
    if (value == null) continue;
    builder[entry.key] = JsonObject(value);
  }
  return builder;
}
