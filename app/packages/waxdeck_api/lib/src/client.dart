import 'dart:convert';

import 'package:built_collection/built_collection.dart';
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
  /// reissues the pid; the returned playlist carries the new pid with
  /// `previousPid` set.
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

  /// `GET /admin/notifications`: the relay configuration
  /// (administrators).
  Future<NotificationConfig> getNotificationConfig();

  /// `PUT /admin/notifications`: replaces the relay configuration
  /// (administrators).
  Future<NotificationConfig> putNotificationConfig({
    required String appriseUrl,
    String? targets,
    required List<String> enabledEvents,
  });

  /// `POST /admin/notifications/test`: queues a test notification
  /// (administrators).
  Future<void> testNotifications();
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
    return BootstrapStatus(required: body.required_);
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
  Future<NotificationConfig> getNotificationConfig() => _guard(() async {
    final response = await _gen.getNotificationsApi().getNotificationConfig();
    return notificationConfigFromGen(_require(response.data));
  });

  @override
  Future<NotificationConfig> putNotificationConfig({
    required String appriseUrl,
    String? targets,
    required List<String> enabledEvents,
  }) => _guard(() async {
    final response = await _gen.getNotificationsApi().putNotificationConfig(
      notificationConfigUpdate: gen.NotificationConfigUpdate(
        (b) => b
          ..appriseUrl = appriseUrl
          ..targets = targets
          ..enabledEvents = ListBuilder<String>(enabledEvents),
      ),
    );
    return notificationConfigFromGen(_require(response.data));
  });

  @override
  Future<void> testNotifications() => _guard(() async {
    await _gen.getNotificationsApi().testNotifications();
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
