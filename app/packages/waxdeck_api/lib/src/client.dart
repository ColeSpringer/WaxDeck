import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'mapping.dart';
import 'models.dart';

/// What feature code programs against. [WaxDeckClient] is the real
/// implementation; tests substitute fakes without touching the network.
abstract interface class WaxDeckRepository {
  /// `GET /health`: liveness and version probe.
  Future<ServerHealth> health();

  /// `POST /auth/login`: establishes a session. On success the client keeps
  /// the returned bearer token and applies it to subsequent calls; web
  /// builds additionally get the HttpOnly session cookie from the browser.
  Future<LoginResult> login({
    required String username,
    required String password,
  });

  /// `GET /auth/session`: whether the caller is authenticated, and as whom.
  /// Unauthenticated callers get a false state, never an error.
  Future<SessionState> getSession();

  /// `POST /auth/logout`: revokes the current session.
  Future<void> logout();

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

  /// `PUT /items/{pid}/play-state`: checkpoints the resume position.
  Future<void> putPlayState(String pid, int positionMs);

  /// `POST /listens`: reports listen sessions. Idempotent per session ID, so
  /// retrying a failed batch is always safe.
  Future<ListenOutcome> reportListens(List<ListenSession> sessions);
}

/// Thin repository layer over the generated dart-dio client.
class WaxDeckClient implements WaxDeckRepository {
  /// [baseUrl] is the server origin. On web builds pass an empty string:
  /// relative URLs resolve against the single origin serving the SPA.
  factory WaxDeckClient({String baseUrl = ''}) {
    // Strip trailing slashes so a baseUrl like "http://host:4420/" doesn't
    // produce "//api/v1", a non-canonical path the server 301-redirects,
    // which can drop the body on POST /auth/login.
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return WaxDeckClient._(
      trimmed,
      gen.WaxdeckApiGen(dio: Dio(BaseOptions(baseUrl: '$trimmed/api/v1'))),
    );
  }

  WaxDeckClient._(this._baseUrl, this._gen) {
    _gen.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _authToken;
          if (token != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final String _baseUrl;
  final gen.WaxdeckApiGen _gen;
  String? _authToken;

  /// Bearer token applied to every request as an Authorization header.
  ///
  /// [login] sets it automatically; native clients that persist the token
  /// across restarts can restore it here before calling anything else. Web
  /// builds work without it via the session cookie.
  String? get authToken => _authToken;
  set authToken(String? token) => _authToken = token;

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
  Future<LoginResult> login({
    required String username,
    required String password,
  }) => _guard(() async {
    final response = await _gen.getAuthApi().login(
      loginRequest: gen.LoginRequest(
        (b) => b
          ..username = username
          ..password = password,
      ),
    );
    final result = loginResultFromGen(_require(response.data));
    _authToken = result.token;
    return result;
  });

  @override
  Future<SessionState> getSession() => _guard(() async {
    return sessionStateFromGen(
      _require((await _gen.getAuthApi().getSession()).data),
    );
  });

  @override
  Future<void> logout() => _guard(() async {
    await _gen.getAuthApi().logout();
    _authToken = null;
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
  Future<void> putPlayState(String pid, int positionMs) => _guard(() async {
    await _gen.getPlaybackApi().putPlayState(
      pid: pid,
      playStateUpdate: gen.PlayStateUpdate((b) => b..positionMs = positionMs),
    );
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
