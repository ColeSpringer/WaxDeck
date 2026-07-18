import 'dart:convert';

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
  /// URL is already resolved against the client base URL.
  Future<PlayInfo> getPlayInfo(String pid);

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
  Future<PlayInfo> getPlayInfo(String pid) => _guard(() async {
    final response = await _gen.getPlaybackApi().getPlayInfo(pid: pid);
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
