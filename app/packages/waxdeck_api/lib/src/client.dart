import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api/media_urls_api.dart';
import 'gen/api.g.dart';
import 'gen/codec.g.dart';
import 'hand_models.dart';
import 'models.dart';
import 'wire.dart';

part 'gen/calls.g.dart';

/// What feature code programs against. [WaxDeckClient] is the real
/// implementation; tests substitute fakes without touching the network.
abstract interface class WaxDeckRepository implements WaxDeckApi, MediaUrlsApi {
  /// The server origin this repository reaches, empty on web, where every
  /// URL is origin-relative. Another address is another server to what
  /// the device holds: a download records the one it came from.
  String get baseUrl;

  /// Bearer token applied to every request. [login], [bootstrap],
  /// [oidcExchange], and [refreshToken] set it; native clients persist it
  /// and restore it here before the startup session probe. Web builds
  /// leave it null and rely on the HttpOnly session cookie.
  abstract String? authToken;
}

/// Marks a call whose server side does its whole job before the
/// response line, so the ordinary receive budget would call a healthy
/// operation dead. Set through the generated methods' `extra` map.
const String _longOperation = 'waxdeck-long-operation';

/// Marks an upload chunk's send on a transport that would cut the whole
/// request ([WaxDeckClient._wholeRequestCut]); set through `extra` like
/// the above.
const String _chunkSend = 'waxdeck-chunk-send';

/// The Dio the generated calls send through, with the deadlines and the
/// credentials every request carries.
abstract class _WaxDeckTransport {
  _WaxDeckTransport(this._baseUrl, this._dio)
    : _wire = WireContext(baseUrl: _baseUrl) {
    _dio.options.baseUrl = '$_baseUrl/api/v1';
    _dio.transformer = _AnswerTransformer();
    // Deadlines, so a request that never lands becomes an error instead
    // of a future nobody ever completes. A hung first build is what kept
    // the live fan-out's retry timer re-arming for the life of a session.
    //
    // The receive budget caps the wait for the response line and then
    // runs between chunks, so a slow but flowing download never trips
    // it and an upload's body is sent before the timer starts - but a
    // handler that does its whole job before answering is on the clock
    // for all of it, which is what the long-operation flag below is
    // for. On web the adapter has no chunk view at all: it sets the
    // XHR timeout to connect+receive over the entire request, upload
    // included. sendTimeout stays unset on purpose: it budgets the
    // request body, and a 1 MB chunk on a slow uplink is a legitimate
    // slow send.
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Importing a backup archive io.Copies and fsyncs the lot
          // before it answers 201, and on web the XHR timeout covers
          // the upload too - thirty seconds would fail a healthy
          // import and invite a duplicate-archive retry. Widened per
          // call rather than loosening every request's budget.
          if (options.extra[_longOperation] == true) {
            options.receiveTimeout = WaxDeckClient.longOperationBudget;
          }
          // A chunk's send where the transport would cut the whole
          // request at connect plus receive: a chunk on a slow uplink
          // could never finish inside that, so the send's own progress
          // deadline ([putUploadData]) is the only one it has.
          if (options.extra[_chunkSend] == true) {
            options
              ..connectTimeout = Duration.zero
              ..receiveTimeout = Duration.zero;
          }
          _applyAuth(options.headers, options.method);
          handler.next(options);
        },
      ),
    );
  }

  final String _baseUrl;
  final Dio _dio;

  /// What the codec resolves media URLs against.
  final WireContext _wire;

  String? _authToken;
  String? _csrfToken;

  /// Moves at every sign-in and sign-out, so a session probe that was out
  /// across one keeps its answer's CSRF token, the old session's, to
  /// itself.
  var _credentials = 0;

  /// Puts this client's credential on an outgoing request.
  ///
  /// The one author of "bearer where one is held, the CSRF token where
  /// the cookie is the credential". Every ordinary call reaches it
  /// through the interceptor; [WaxDeckClient.exitRequests] calls it
  /// directly, because what it builds is sent by the browser rather than
  /// by Dio and would otherwise be a second copy of this policy that
  /// nothing would notice going stale - a beacon that authenticates is
  /// indistinguishable from one that does not, since neither is waited
  /// for.
  ///
  /// Cookie-authenticated mutations (web after a reload: no bearer in
  /// memory, the HttpOnly cookie authenticates) must echo the CSRF token
  /// from login/getSession. Bearer requests are exempt.
  void _applyAuth(Map<String, dynamic> headers, String method) {
    final token = _authToken;
    if (token != null && !headers.containsKey('Authorization')) {
      headers['Authorization'] = 'Bearer $token';
    }
    final csrf = _csrfToken;
    if (token == null &&
        csrf != null &&
        _isMutation(method) &&
        !headers.containsKey('X-CSRF-Token')) {
      headers['X-CSRF-Token'] = csrf;
    }
  }

  static bool _isMutation(String method) {
    return switch (method.toUpperCase()) {
      'GET' || 'HEAD' || 'OPTIONS' => false,
      _ => true,
    };
  }

  /// One request of a generated call. Typed `dynamic` so Dio keeps the
  /// [responseType] asked for: under `String` it forces plain, and under any
  /// other type argument it forces JSON, bytes and stream aside.
  Future<Response<Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    String? contentType,
    Map<String, Object?>? headers,
    Map<String, Object?>? extra,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    bool Function(int?)? validateStatus,
    ResponseType? responseType,
  }) async {
    final response = await _dio.request<dynamic>(
      path,
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      options: Options(
        method: method,
        headers: headers,
        extra: extra,
        contentType: contentType,
        validateStatus: validateStatus,
        responseType: responseType,
      ),
    );
    // Every 2xx a JSON call gets from the server is JSON or empty. Checked
    // here for all of them, because a call that returns nothing never reads
    // its body, and a captive portal's page would pass as delivered.
    final status = response.statusCode ?? 0;
    if (response.data case final _NotJson page when status ~/ 100 == 2) {
      throw page.exception(status);
    }
    return response;
  }

  /// Runs [body], mapping transport failures to the structured error model.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (e) {
      throw apiExceptionFromDio(e);
    }
  }

  /// [response]'s body through [read], [at] naming it in errors. An answer
  /// that does not read, a value or the whole of it of the wrong shape,
  /// fails as `transport-decode` with the reason naming the field; each
  /// failure keeps the status the answer came with. A body that is not JSON
  /// at all is something other than the server answering: `transport`.
  T _decode<T>(Response<Object?> response, String at, WireRead<T> read) {
    final body = response.data;
    if (body is _NotJson) throw body.exception(response.statusCode);
    if (body == null) {
      // Client-minted like 'transport' beside it, and not the spec's
      // `internal`: a truncated answer says nothing about whether the
      // server faulted, so wording the two alike would send a reader to
      // report a bug that may not exist.
      throw WaxDeckApiException(
        code: 'transport-empty',
        message: 'empty response body',
        statusCode: response.statusCode,
      );
    }
    try {
      return read(body, at);
    } on FormatException catch (e) {
      throw WaxDeckApiException(
        code: 'transport-decode',
        message: e.message,
        statusCode: response.statusCode,
      );
    }
  }
}

/// [WaxDeckRepository] over the calls generated from the API spec, one
/// mixin per tag, with the methods the generator leaves to hand.
class WaxDeckClient extends _WaxDeckCalls implements WaxDeckRepository {
  /// [baseUrl] is the server origin. On web builds pass an empty string:
  /// relative URLs resolve against the single origin serving the SPA.
  ///
  /// [dio] is a test hook: the package's own tests inject a Dio carrying a
  /// recording adapter to pin request headers without a network.
  ///
  /// [chunkStall] is how long an upload chunk's attempt may go without
  /// progress before it is given up as a timeout ([putUploadData]); a test
  /// hook too. [wholeRequestCut] says the transport cuts a whole request at
  /// its connect plus receive budget, as a browser's does, which the build
  /// decides; given only by tests that stand in for a browser.
  factory WaxDeckClient({
    String baseUrl = '',
    Dio? dio,
    Duration chunkStall = defaultChunkStall,
    bool? wholeRequestCut,
  }) {
    // Strip trailing slashes so a baseUrl like "http://host:4420/" doesn't
    // produce "//api/v1", a non-canonical path the server 301-redirects,
    // which can drop the body on POST /auth/login.
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return WaxDeckClient._(
      trimmed,
      dio ?? Dio(),
      chunkStall,
      wholeRequestCut ?? _isWebBuild,
    );
  }

  WaxDeckClient._(
    super.baseUrl,
    super.dio,
    this._chunkStall,
    this._wholeRequestCut,
  );

  /// How long a call marked as a long operation may take to answer; an
  /// upload's seal is one.
  static const longOperationBudget = Duration(minutes: 30);

  @override
  String get baseUrl => _baseUrl;

  /// How long an upload chunk's attempt may go without progress: before
  /// any of its body goes, between pieces of it, and after the last for
  /// the answer. Thirty seconds, the receive budget's own length. A native
  /// send has no other deadline while its body goes (the send timeout
  /// would cut a slow but moving chunk), and in a browser the transport's
  /// own would cut the whole request at forty seconds, so a stuck send
  /// ends here and a slow one that keeps moving is never cut.
  static const defaultChunkStall = Duration(seconds: 30);

  /// The longest a chunk whose body the transport took whole waits on the
  /// server's word that it is still reading it, once its stall is due:
  /// a try still ends within forty seconds without one.
  static const _readingCheck = Duration(seconds: 10);

  /// The pieces an upload chunk's body is handed to the transport in: a
  /// native transport reports progress as it takes each.
  static const _chunkPiece = 64 * 1024;

  final Duration _chunkStall;

  /// Whether the transport cuts a whole request at its connect plus receive
  /// budget, as a browser's does: a chunk's send then goes without that
  /// budget and keeps only its progress deadline.
  final bool _wholeRequestCut;

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

  /// Adopts a login-shaped answer: reads its CSRF token, which the model
  /// leaves out, and decodes the result, then keeps the CSRF token and, on
  /// native platforms, the result's bearer token. An answer that fails
  /// either read changes nothing.
  ///
  /// Web builds deliberately do NOT retain the bearer: the HttpOnly
  /// session cookie is the credential there, and holding a JS-readable
  /// copy of an equivalent long-lived token would hand an XSS exactly
  /// the portable credential the HttpOnly flag exists to deny. Without
  /// a bearer, the interceptor rides the cookie and sends the CSRF
  /// header on mutations.
  LoginResult _adoptLogin(Map<String, Object?> json) {
    final csrfToken = readRequired(
      json,
      'csrfToken',
      'LoginResult',
      wireString,
    );
    final result = decodeLoginResult(json, _wire);
    _credentials++;
    _csrfToken = csrfToken;
    if (!_isWebBuild) {
      _authToken = result.token;
    }
    return result;
  }

  /// True in browser builds. Detected via library availability so this
  /// pure-Dart package needs no Flutter dependency.
  static const _isWebBuild = bool.fromEnvironment('dart.library.js_interop');

  @override
  Future<LoginResult> bootstrap({
    required String username,
    required String password,
    String? displayName,
  }) => _guard(() async {
    final response = await _bootstrap(
      body: BootstrapRequest(
        username: username,
        password: password,
        displayName: displayName,
      ),
    );
    return _decode(
      response,
      'bootstrap',
      (v, at) => _adoptLogin(wireObject(v, at)),
    );
  });

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
    String? deviceName,
  }) => _guard(() async {
    final response = await _login(
      body: LoginRequest(
        username: username,
        password: password,
        deviceName: deviceName,
      ),
    );
    return _decode(
      response,
      'login',
      (v, at) => _adoptLogin(wireObject(v, at)),
    );
  });

  @override
  Future<SessionState> getSession() => _guard(() async {
    final asked = _credentials;
    final response = await _getSession();
    return _decode(response, 'getSession', (v, at) {
      final json = wireObject(v, at);
      final csrfToken = readOptional(
        json,
        'csrfToken',
        'SessionState',
        wireString,
      );
      final session = decodeSessionState(json, _wire);
      // Unauthenticated probes carry no CSRF token; dropping a stale one is
      // correct because the session it belonged to is gone.
      if (asked == _credentials) _csrfToken = csrfToken;
      return session;
    });
  });

  @override
  Future<LoginResult> refreshToken() => _guard(() async {
    final response = await _refreshToken();
    return _decode(
      response,
      'refreshToken',
      (v, at) => _adoptLogin(wireObject(v, at)),
    );
  });

  @override
  Future<void> logout() => _guard(() async {
    await _logout();
    _credentials++;
    _authToken = null;
    _csrfToken = null;
  });

  @override
  Future<LoginResult> oidcExchange({
    required String code,
    String? verifier,
    String? deviceName,
  }) => _guard(() async {
    final response = await _exchangeOidcCode(
      body: OidcExchangeRequest(
        code: code,
        verifier: verifier,
        deviceName: deviceName,
      ),
    );
    return _decode(
      response,
      'exchangeOidcCode',
      (v, at) => _adoptLogin(wireObject(v, at)),
    );
  });

  /// The key a facet-scoped read sends beside [facet]. The server keys the
  /// pair on `facet`, so a facet without a key sends an empty one rather
  /// than omitting it: an empty key is the unknown bucket, which is a real
  /// scope.
  static String? _facetKeyFor(String? facet, String? facetKey) =>
      facet == null ? null : facetKey ?? '';

  @override
  Future<ItemPage> listItems({
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _listItems(
      mediaType: mediaType,
      facet: facet,
      facetKey: _facetKeyFor(facet, facetKey),
      cursor: cursor,
      limit: limit,
    );
    return _decode(
      response,
      'listItems',
      (v, at) => decodeItemPage(wireObject(v, at), _wire),
    );
  });

  @override
  Future<FacetPage> listFacets(
    String dimension, {
    FacetSort? sort,
    String? cursor,
    String? startsAt,
    String? facet,
    String? facetKey,
    int? limit,
  }) => _guard(() async {
    final response = await _listFacets(
      dimension: dimension,
      sort: sort,
      cursor: cursor,
      startsAt: startsAt,
      facet: facet,
      facetKey: _facetKeyFor(facet, facetKey),
      limit: limit,
    );
    return _decode(
      response,
      'listFacets',
      (v, at) => decodeFacetPage(wireObject(v, at), _wire),
    );
  });

  @override
  Future<ItemPage> browse(
    DiscoveryList list, {
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
    int? seed,
  }) => _guard(() async {
    final response = await _browseList(
      list: list,
      mediaType: mediaType,
      facet: facet,
      facetKey: _facetKeyFor(facet, facetKey),
      cursor: cursor,
      limit: limit,
      seed: seed,
    );
    return _decode(
      response,
      'browseList',
      (v, at) => decodeItemPage(wireObject(v, at), _wire),
    );
  });

  @override
  String artUrlFor(String pid, {String? role}) {
    final query = <String, String>{
      if (role != null && role != 'front') 'role': role,
    };
    final path = Uri(
      path: '/api/v1/items/${Uri.encodeComponent(pid)}/art',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return resolveMediaUrl(_baseUrl, path);
  }

  @override
  Future<EntityResolution> resolveEntities(List<String> pids) =>
      _guard(() async {
        // Nothing pinned is nothing to ask: the endpoint would answer an
        // empty list, and a shelf that draws nothing should not spend a round
        // trip finding that out.
        if (pids.isEmpty) return const EntityResolution(cards: []);
        final response = await _resolveEntities(
          body: EntityCardQuery(pids: pids),
        );
        return _decode(
          response,
          'resolveEntities',
          (v, at) => decodeEntityResolution(wireObject(v, at), _wire),
        );
      });

  @override
  Future<ItemResolution> resolveItems(List<String> pids) => _guard(() async {
    if (pids.isEmpty) return const ItemResolution(items: []);
    final response = await _resolveItems(body: ItemResolveQuery(pids: pids));
    return _decode(
      response,
      'resolveItems',
      (v, at) => decodeItemResolution(wireObject(v, at), _wire),
    );
  });

  @override
  Future<QueueTimeline> createQueueTimeline(
    List<String> pids, {
    double? crossfadeSeconds,
    List<String>? formats,
  }) => _guard(() async {
    final Response<Object?> response;
    try {
      response = await _createQueueTimeline(
        body: TimelineCreate(
          itemPids: pids,
          crossfadeSeconds: crossfadeSeconds,
          formats: formats,
        ),
        // A 202 carries a job, not a timeline, which would surface "still
        // measuring" as an answer that does not decode. Rejecting it here
        // keeps the answer intact on the exception.
        validateStatus: (status) => status == 201,
      );
    } on DioException catch (e) {
      final measuring = _measuringJob(e);
      if (measuring == null) rethrow;
      throw WaxDeckApiException(
        code: 'timeline-measuring',
        message: 'the server is still measuring this queue',
        statusCode: 202,
        params: <String, String>{'job': measuring},
      );
    }
    return _decode(
      response,
      'createQueueTimeline',
      (v, at) => decodeQueueTimeline(wireObject(v, at), _wire),
    );
  });

  /// The job pid from a 202 answer to a timeline mint, or null for any
  /// other failure. A 202 with no readable job is still a 202: the
  /// caller's move is to fall back to per-item playback either way,
  /// and an empty pid says only that polling is not on offer.
  static String? _measuringJob(DioException e) {
    final response = e.response;
    if (response?.statusCode != 202) return null;
    final body = response?.data;
    if (body is Map && body['pid'] is String) return body['pid'] as String;
    return '';
  }

  /// Entity star and rating calls route on the pid's own prefix: the
  /// artist and album paths are separate operations in the contract but
  /// one surface to callers, so the prefix picks the operation rather
  /// than every call site knowing which endpoint it wants.
  ///
  /// Only those two prefixes name a catalog entity. Anything else is a
  /// caller mistake (an item pid, a typo) and is refused here rather
  /// than sent to the album endpoint to come back as a confusing
  /// "no album with pid tr-...".
  static bool _isArtistPid(String pid) {
    if (pid.startsWith('ar-')) return true;
    if (pid.startsWith('al-')) return false;
    throw ArgumentError.value(
      pid,
      'pid',
      'not a catalog entity pid; expected an ar- artist or al- album',
    );
  }

  @override
  Future<EntityPlayState> getEntityPlayState(String pid) => _guard(() async {
    final response = _isArtistPid(pid)
        ? await _getArtistPlayState(pid)
        : await _getAlbumPlayState(pid);
    return _decode(
      response,
      'getEntityPlayState',
      (v, at) => decodeEntityPlayState(wireObject(v, at), _wire),
    );
  });

  @override
  Future<EntityPlayState> setEntityStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) => _guard(() async {
    final update = StarUpdate(starred: starred, recordedAt: recordedAt);
    final response = _isArtistPid(pid)
        ? await _setArtistStar(pid, body: update)
        : await _setAlbumStar(pid, body: update);
    return _decode(
      response,
      'setEntityStar',
      (v, at) => decodeEntityPlayState(wireObject(v, at), _wire),
    );
  });

  @override
  Future<EntityPlayState> setEntityRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) => _guard(() async {
    final update = RatingUpdate(rating: rating, recordedAt: recordedAt);
    final response = _isArtistPid(pid)
        ? await _setArtistRating(pid, body: update)
        : await _setAlbumRating(pid, body: update);
    return _decode(
      response,
      'setEntityRating',
      (v, at) => decodeEntityPlayState(wireObject(v, at), _wire),
    );
  });

  @override
  Future<Waveform> getWaveform(String pid, {bool wholeItem = false}) => _guard(
    () async {
      final response = await _getWaveform(pid, span: wholeItem ? 'item' : null);
      return _decode(
        response,
        'getWaveform',
        (v, at) => decodeWaveform(wireObject(v, at), _wire),
      );
    },
  );

  @override
  Future<PlaylistSyncPreview> previewPlaylistSync(
    String pid, {
    String? mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  }) => _guard(() async {
    final response = await _previewPlaylistSync(
      pid,
      body: mode == null
          ? null
          : PlaylistSourceUpdate(
              mode: mode,
              url: url,
              source: source,
              payload: payload,
              refs: refs,
              intervalHours: intervalHours,
            ),
    );
    return _decode(
      response,
      'previewPlaylistSync',
      (v, at) => decodePlaylistSyncPreview(wireObject(v, at), _wire),
    );
  });

  @override
  String radioLogoUrlFor(String pid) => resolveMediaUrl(
    _baseUrl,
    '/api/v1/radio/stations/${Uri.encodeComponent(pid)}/logo',
  );

  @override
  String radioNowPlayingArtUrlFor(String pid, String key) => resolveMediaUrl(
    _baseUrl,
    '/api/v1/radio/stations/${Uri.encodeComponent(pid)}'
    '/now-playing-art?v=${Uri.encodeQueryComponent(key)}',
  );

  @override
  String radioSavedArtUrlFor(String pid) => resolveMediaUrl(
    _baseUrl,
    '/api/v1/radio/saved/${Uri.encodeComponent(pid)}/art',
  );

  @override
  Future<Job> rescanLibrary({bool force = false}) => _guard(() async {
    // The body is optional on the wire; a plain rescan keeps posting
    // none, which is what pre-options servers accept.
    final response = await _rescanLibrary(
      body: force ? const RescanOptions(force: true) : null,
    );
    return _decode(
      response,
      'rescanLibrary',
      (v, at) => decodeJob(wireObject(v, at), _wire),
    );
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
    bool? identify,
  }) => _guard(() async {
    final response = await _createUpload(
      body: UploadCreate(
        fileName: fileName,
        sizeBytes: sizeBytes,
        mediaType: _uploadMediaType(mediaType),
        libraryPid: libraryPid,
        sha256: sha256,
        batchId: batchId,
        batchPath: batchPath,
        identify: identify,
      ),
    );
    return _decode(
      response,
      'createUpload',
      (v, at) => decodeUploadSession(wireObject(v, at), _wire),
    );
  });

  @override
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
    bool? identify,
  }) => _guard(() async {
    final response = await _createUploadBatch(
      body: UploadBatchCreate(
        grouping: grouping,
        mediaType: _uploadMediaType(mediaType),
        libraryPid: libraryPid,
        identify: identify,
      ),
    );
    return _decode(
      response,
      'createUploadBatch',
      (v, at) => decodeUploadBatch(wireObject(v, at), _wire),
    );
  });

  @override
  Future<UploadSession> putUploadData(
    String uploadId, {
    required int offset,
    required Uint8List bytes,
  }) async {
    // The attempt is given up once it has made no progress for
    // [_chunkStall] (none of the body sent yet, a send stuck, or no answer
    // after the last of it): a slow chunk that keeps moving is never cut,
    // and a stuck one ends in the retry its caller makes of any timeout.
    // Progress is what the transport reports: the pieces a native one
    // takes, the upload events a browser fires. Both count bytes handed
    // to the network stack, whose buffers a slow link can still be
    // draining long after the last, so a body taken whole is cut only
    // once the server says it is not reading it.
    final cancel = CancelToken();
    Timer? stall;
    var stalled = false;
    var handedOver = false;
    var ended = false;
    void arm() {
      stall?.cancel();
      late final Timer due;
      // Acts after the check only while still the armed stall: progress
      // during the check armed a fresher one, which judges instead.
      due = Timer(_chunkStall, () async {
        if (handedOver && await _stillReading(uploadId)) {
          if (!ended && identical(stall, due)) arm();
          return;
        }
        if (ended || !identical(stall, due)) return;
        stalled = true;
        cancel.cancel('the chunk stopped moving');
      });
      stall = due;
    }

    Stream<List<int>> pieces() async* {
      for (var at = 0; at < bytes.length; at += _chunkPiece) {
        yield Uint8List.sublistView(
          bytes,
          at,
          math.min(at + _chunkPiece, bytes.length),
        );
      }
    }

    arm();
    try {
      return await _guard(() async {
        final response = await _putUploadData(
          uploadId,
          offset: offset,
          body: pieces(),
          // The length is what makes a native transport report progress.
          length: bytes.length,
          extra: _wholeRequestCut ? const {_chunkSend: true} : null,
          cancelToken: cancel,
          onSendProgress: (sent, _) {
            handedOver = sent >= bytes.length;
            arm();
          },
        );
        return _decode(
          response,
          'putUploadData',
          (v, at) => decodeUploadSession(wireObject(v, at), _wire),
        );
      });
    } on WaxDeckApiException {
      if (!stalled) rethrow;
      throw const WaxDeckApiException(
        code: 'transport-timeout',
        message: 'the chunk stopped moving',
      );
    } finally {
      ended = true;
      stall?.cancel();
    }
  }

  /// Whether the server is reading a chunk's body for [uploadId] now, which
  /// it says by an idle of zero; asked within [_readingCheck], and no
  /// answer is a no.
  Future<bool> _stillReading(String uploadId) async {
    try {
      final session = await getUpload(
        uploadId,
      ).timeout(_chunkStall < _readingCheck ? _chunkStall : _readingCheck);
      return session.state == 'receiving' && session.idle == Duration.zero;
    } on Object {
      return false;
    }
  }

  @override
  Future<ToolTask> createAcquisition({
    required String url,
    required MediaType mediaType,
    String? libraryPid,
    String? format,
    bool? identify,
  }) => _guard(() async {
    final response = await _createAcquisition(
      body: AcquisitionRequest(
        url: url,
        mediaType: _uploadMediaType(mediaType.wireName),
        libraryPid: libraryPid,
        identify: identify,
        // "best" is the server default, so it rides as an absent field.
        format: switch (format) {
          null || '' || 'best' => null,
          final f => f,
        },
      ),
    );
    return _decode(
      response,
      'createAcquisition',
      (v, at) => decodeToolTask(wireObject(v, at), _wire),
    );
  });

  /// What a file is uploaded or acquired as, from a media type's wire
  /// name. Refused here for anything else rather than sent: a podcast is
  /// subscribed to, not uploaded.
  static String _uploadMediaType(String wireName) {
    return switch (wireName) {
      'music' || 'audiobook' => wireName,
      _ => throw ArgumentError.value(
        wireName,
        'mediaType',
        'podcasts are added by subscribing to a feed, and only music and '
            'audiobooks are uploaded',
      ),
    };
  }

  @override
  Future<OrganizePlan> previewOrganize({
    String? profile,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _previewOrganize(
      // A library-wide plan looks at every file, which on a network share
      // takes minutes, as the apply's own planning does; one over a few
      // items answers at once, so a hung mount fails it on the ordinary
      // budget.
      extra: itemPids == null ? const {_longOperation: true} : null,
      body: OrganizeRequest(profile: profile, itemPids: itemPids),
    );
    return _decode(
      response,
      'previewOrganize',
      (v, at) => decodeOrganizePlan(wireObject(v, at), _wire),
    );
  });

  @override
  Future<ToolTasksCleared> clearFinishedToolTasks({bool all = false}) =>
      _guard(() async {
        final response = await _clearFinishedToolTasks(
          body: ClearFinishedTasksRequest(scope: all ? 'all' : 'mine'),
        );
        return _decode(
          response,
          'clearFinishedToolTasks',
          (v, at) => decodeToolTasksCleared(wireObject(v, at), _wire),
        );
      });

  @override
  String backupArchiveUrl(String backupId) =>
      '$_baseUrl/api/v1/admin/backups/$backupId/archive';

  @override
  List<ExitRequest> exitRequests({
    String? pid,
    int? positionMs,
    ListenSession? listen,
    List<String> timelinePids = const <String>[],
  }) {
    // Whatever the interceptor would have added, added by the same
    // code: these go out through the browser rather than through Dio,
    // and building them here is the only way to have a credential on
    // them at all. Both are mutations, which is what decides the CSRF
    // half.
    final headers = <String, String>{};
    _applyAuth(headers, 'POST');
    // Through the generated codec rather than a hand-written map: these
    // are contract bodies, and a second spelling of them beside the one
    // `make generate` produces is a spelling that drifts.
    return <ExitRequest>[
      if (pid != null && positionMs != null)
        ExitRequest(
          path: '$_baseUrl/api/v1/items/${Uri.encodeComponent(pid)}/play-state',
          method: 'PUT',
          headers: headers,
          body: jsonEncode(
            encodePlayStateUpdate(PlayStateUpdate(positionMs: positionMs)),
          ),
        ),
      if (listen != null)
        ExitRequest(
          path: '$_baseUrl/api/v1/listens',
          method: 'POST',
          headers: headers,
          body: jsonEncode(
            encodeListenReport(ListenReport(sessions: [listen])),
          ),
        ),
      for (final pid in timelinePids)
        ExitRequest(
          path:
              '$_baseUrl/api/v1/player/timeline/'
              '${Uri.encodeComponent(pid)}',
          method: 'DELETE',
          headers: headers,
          body: '',
        ),
    ];
  }
}

/// The size at which Dio's own default transformer (dio_mixin.dart) decodes
/// an answer in a background isolate, so a catalog page of several hundred
/// KB does not stall the calling isolate.
const int _isolateThreshold = 50 * 1024;

/// A JSON call's body that does not parse as JSON, whatever the answer's
/// Content-Type says. A type of its own, because a bare string would read
/// as a JSON answer that is a string. It keeps nothing of the body: an
/// answer that fails to parse can still be the server's, with a credential
/// in it, and this reaches logs.
final class _NotJson {
  const _NotJson({this.contentType, this.length});

  /// The media type the answer came under, without its parameters.
  final String? contentType;

  /// The size the server declared, when it did.
  final int? length;

  /// [status] is the status of the answer that carried it.
  WaxDeckApiException exception(int? status) => WaxDeckApiException(
    code: 'transport',
    message:
        'the answer is not JSON (${contentType ?? 'no content type'}'
        '${length == null ? '' : ', $length bytes'})',
    statusCode: status,
  );
}

/// Dio's default transformer, with one rule added for a JSON call: its answer
/// is read as JSON whatever the Content-Type says, and a body that does not
/// parse is a [_NotJson] rather than an error thrown out of the transport
/// with no response, which would read as the server being out of reach. Dio
/// does the decoding, in an isolate for a large answer; an answer under
/// another type reaches it as a view of the same stream that reads as JSON.
/// Other response types are Dio's own.
class _AnswerTransformer extends FusedTransformer {
  _AnswerTransformer()
    : super(contentLengthIsolateThreshold: _isolateThreshold);

  @override
  Future<Object?> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    if (options.responseType != ResponseType.json) {
      return super.transformResponse(options, responseBody);
    }
    final type = responseBody.headers[Headers.contentTypeHeader]?.first;
    try {
      return await super.transformResponse(
        options,
        Transformer.isJsonMimeType(type) ? responseBody : _asJson(responseBody),
      );
    } on FormatException {
      final mediaType = type?.split(';').first.trim();
      return _NotJson(
        contentType: mediaType == null || mediaType.isEmpty ? null : mediaType,
        length: int.tryParse(
          responseBody.headers[Headers.contentLengthHeader]?.first ?? '',
        ),
      );
    }
  }

  /// [body] with a JSON Content-Type, over the same stream.
  static ResponseBody _asJson(ResponseBody body) => ResponseBody(
    body.stream,
    body.statusCode,
    statusMessage: body.statusMessage,
    isRedirect: body.isRedirect,
    redirects: body.redirects,
    headers: {
      ...body.headers,
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  )..extra = body.extra;
}

/// [text] as the JSON it holds, or null when it holds none.
Object? _jsonOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Maps transport-level failures to the spec's structured error model.
///
/// A JSON call's error body is already read by the client's transformer; a
/// call that asked for text or bytes gets its error body undecoded, so it
/// gets one decode attempt before falling back to a transport error. A body
/// that is no error object, one that did not parse as JSON included, is
/// `transport` with the status it came with.
WaxDeckApiException apiExceptionFromDio(DioException e) {
  // A deadline first, and by type rather than by body: there is no
  // response to read a code out of, and callers that tell a timeout
  // from a refusal need a name for it rather than the generic
  // transport fallback. The name is client-minted like 'transport'
  // beside it, and deliberately NOT the spec's `timeout` - that enum
  // value means a player-routed command whose endpoint is still
  // connected (the connect bus mints it), and a handler written to
  // that meaning must not also catch plain HTTP deadlines.
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return WaxDeckApiException(
        code: 'transport-timeout',
        message: e.message ?? 'the server did not answer in time',
      );
    default:
      break;
  }
  var data = e.response?.data;
  if (data is List<int>) data = utf8.decode(data, allowMalformed: true);
  if (data is String) data = _jsonOrNull(data);
  final status = e.response?.statusCode;
  return apiErrorFromWire(data, statusCode: status) ??
      WaxDeckApiException(
        code: 'transport',
        message: e.message ?? 'network error',
        statusCode: status,
      );
}
