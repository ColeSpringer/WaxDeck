import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart' show FullType;
import 'package:built_value/json_object.dart';
import 'package:dio/dio.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'api/admin_api.dart';
import 'api/auth_api.dart';
import 'api/books_api.dart';
import 'api/discovery_api.dart';
import 'api/enrichment_api.dart';
import 'api/health_api.dart';
import 'api/library_api.dart';
import 'api/media_urls_api.dart';
import 'api/metadata_api.dart';
import 'api/notifications_api.dart';
import 'api/organize_api.dart';
import 'api/playback_api.dart';
import 'api/player_api.dart';
import 'api/playlists_api.dart';
import 'api/podcasts_api.dart';
import 'api/radio_api.dart';
import 'api/review_api.dart';
import 'api/scrobbling_api.dart';
import 'api/shares_api.dart';
import 'api/similarity_api.dart';
import 'api/stats_api.dart';
import 'api/sync_api.dart';
import 'api/system_api.dart';
import 'api/tools_api.dart';
import 'api/uploads_api.dart';
import 'api/users_api.dart';
import 'mapping.dart';
import 'models.dart';

/// What feature code programs against. [WaxDeckClient] is the real
/// implementation; tests substitute fakes without touching the network.
abstract interface class WaxDeckRepository
    implements
        SystemApi,
        AuthApi,
        UsersApi,
        LibraryApi,
        PodcastsApi,
        BooksApi,
        PlaylistsApi,
        RadioApi,
        ScrobblingApi,
        NotificationsApi,
        PlaybackApi,
        PlayerApi,
        SyncApi,
        AdminApi,
        ReviewApi,
        UploadsApi,
        MetadataApi,
        HealthApi,
        OrganizeApi,
        ToolsApi,
        EnrichmentApi,
        DiscoveryApi,
        StatsApi,
        SharesApi,
        SimilarityApi,
        MediaUrlsApi {
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

/// Thin repository layer over the generated dart-dio client.
class WaxDeckClient implements WaxDeckRepository {
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
    final transport = dio ?? Dio();
    transport.options.baseUrl = '$trimmed/api/v1';
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
    transport.options.connectTimeout = const Duration(seconds: 10);
    transport.options.receiveTimeout = const Duration(seconds: 30);
    return WaxDeckClient._(
      trimmed,
      gen.WaxdeckApiGen(dio: transport),
      chunkStall,
      wholeRequestCut ?? _isWebBuild,
    );
  }

  /// Marks a call whose server side does its whole job before the
  /// response line, so the ordinary receive budget would call a healthy
  /// operation dead. Set through the generated methods' `extra` map.
  static const String _longOperation = 'waxdeck-long-operation';

  /// How long such a call may take to answer; an upload's seal is one.
  static const longOperationBudget = Duration(minutes: 30);

  /// Marks an upload chunk's send on a transport that would cut the whole
  /// request ([_wholeRequestCut]); set through `extra` like the above.
  static const String _chunkSend = 'waxdeck-chunk-send';

  WaxDeckClient._(
    this._baseUrl,
    this._gen,
    this._chunkStall,
    this._wholeRequestCut,
  ) {
    _gen.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Importing a backup archive io.Copies and fsyncs the lot
          // before it answers 201, and on web the XHR timeout covers
          // the upload too - thirty seconds would fail a healthy
          // import and invite a duplicate-archive retry. Widened per
          // call rather than loosening every request's budget.
          if (options.extra[_longOperation] == true) {
            options.receiveTimeout = longOperationBudget;
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

  /// Puts this client's credential on an outgoing request.
  ///
  /// The one author of "bearer where one is held, the CSRF token where
  /// the cookie is the credential". Every ordinary call reaches it
  /// through the interceptor; [exitRequests] calls it directly, because
  /// what it builds is sent by the browser rather than by Dio and would
  /// otherwise be a second copy of this policy that nothing would
  /// notice going stale - a beacon that authenticates is indistinguishable
  /// from one that does not, since neither is waited for.
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

  @override
  String get baseUrl => _baseUrl;

  final String _baseUrl;
  final gen.WaxdeckApiGen _gen;

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
  String? _authToken;
  String? _csrfToken;

  /// Moves at every sign-in and sign-out, so a session probe that was out
  /// across one keeps its answer's CSRF token, the old session's, to
  /// itself.
  var _credentials = 0;

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
    _credentials++;
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
    final streaming = body.streaming;
    return ServerHealth(
      status: body.status,
      version: body.version,
      apiVersion: body.apiVersion,
      uploadFormats: body.uploadFormats?.toList(),
      rejectedFormats: body.rejectedFormats?.toList(),
      streaming: streaming == null
          ? null
          : ServerStreaming(
              configured: streaming.configured,
              connected: streaming.connected,
              timelines: streaming.timelines,
              voiceBoost: streaming.voiceBoost,
              fileTools: streaming.fileTools,
            ),
      podcasts: body.podcasts,
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
    final asked = _credentials;
    final body = _require((await _gen.getAuthApi().getSession()).data);
    // Unauthenticated probes carry no CSRF token; dropping a stale one is
    // correct because the session it belonged to is gone.
    if (asked == _credentials) _csrfToken = body.csrfToken;
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
    _credentials++;
    _authToken = null;
    _csrfToken = null;
  });

  @override
  Future<List<DeviceSession>> listSessions() => _guard(() async {
    final body = _require((await _gen.getAuthApi().listSessions()).data);
    return body.sessions.map(deviceSessionFromGen).toList();
  });

  @override
  Future<DeviceSession> renameSession(String sessionId, String deviceName) =>
      _guard(() async {
        final body = _require(
          (await _gen.getAuthApi().renameSession(
            sessionId: sessionId,
            sessionRename: gen.SessionRename((b) => b..deviceName = deviceName),
          )).data,
        );
        return deviceSessionFromGen(body);
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
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getLibraryApi().listItems(
      mediaType: mediaType == null ? null : mediaTypeToGen(mediaType),
      facet: facet,
      // The server keys the pair on `facet`, so an unknown-bucket drill
      // sends an empty key rather than omitting it.
      facetKey: facet == null ? null : facetKey ?? '',
      cursor: cursor,
      limit: limit,
    );
    return itemPageFromGen(_require(response.data), baseUrl: _baseUrl);
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
    final response = await _gen.getLibraryApi().listFacets(
      dimension: dimension,
      sort: sort == null ? null : facetSortToGen(sort),
      cursor: cursor,
      startsAt: startsAt,
      facet: facet,
      // Empty included, as on the drill: an empty key is the unknown
      // bucket, which is a real scope.
      facetKey: facet == null ? null : facetKey ?? '',
      limit: limit,
    );
    return facetPageFromGen(_require(response.data));
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
    final response = await _gen.getLibraryApi().browseList(
      list: discoveryListToGen(list),
      mediaType: mediaType == null ? null : mediaTypeToGen(mediaType),
      facet: facet,
      // Empty included: an empty key is the unknown bucket.
      facetKey: facet == null ? null : facetKey ?? '',
      cursor: cursor,
      limit: limit,
      seed: seed,
    );
    return itemPageFromGen(_require(response.data), baseUrl: _baseUrl);
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
  Future<EntityResolution> resolveEntities(List<String> pids) =>
      _guard(() async {
        // Nothing pinned is nothing to ask: the endpoint would answer an
        // empty list, and a shelf that draws nothing should not spend a round
        // trip finding that out.
        if (pids.isEmpty) return const EntityResolution(cards: []);
        final response = await _gen.getLibraryApi().resolveEntities(
          entityCardQuery: gen.EntityCardQuery(
            (b) => b..pids = ListBuilder<String>(pids),
          ),
        );
        final list = _require(response.data);
        return EntityResolution(
          cards: list.entities.map(entityCardFromGen).nonNulls.toList(),
          departed: list.departed?.toList() ?? const <String>[],
        );
      });

  @override
  Future<ItemResolution> resolveItems(List<String> pids) => _guard(() async {
    if (pids.isEmpty) return const ItemResolution(items: []);
    final response = await _gen.getLibraryApi().resolveItems(
      itemResolveQuery: gen.ItemResolveQuery(
        (b) => b..pids = ListBuilder<String>(pids),
      ),
    );
    final list = _require(response.data);
    return ItemResolution(
      items: [
        for (final item in list.items)
          itemSummaryFromGen(item, baseUrl: _baseUrl),
      ],
      departed: list.departed?.toList() ?? const <String>[],
    );
  });

  @override
  Future<AlbumDetail> getAlbum(String pid) => _guard(() async {
    final response = await _gen.getLibraryApi().getAlbum(pid: pid);
    return albumDetailFromGen(_require(response.data));
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
    int? maxBitrateKbps,
    bool? hls,
  }) => _guard(() async {
    final response = await _gen.getPlaybackApi().getPlayInfo(
      pid: pid,
      positionMs: positionMs,
      voiceBoost: voiceBoost,
      maxBitrateKbps: maxBitrateKbps,
      hls: hls,
    );
    return playInfoFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<QueueTimeline> createQueueTimeline(
    List<String> pids, {
    double? crossfadeSeconds,
    List<String>? formats,
  }) => _guard(() async {
    try {
      final response = await _gen.getPlayerApi().createQueueTimeline(
        timelineCreate: gen.TimelineCreate(
          (b) => b
            ..itemPids.addAll(pids)
            ..crossfadeSeconds = crossfadeSeconds
            ..formats = formats == null
                ? null
                : ListBuilder<gen.TimelineFormat>(
                    formats.map(gen.TimelineFormat.valueOf),
                  ),
        ),
        // A 202 carries a job, not a timeline, and the generated call
        // deserializes the success shape whatever the status is - which
        // would surface "still measuring" as a parse failure. Rejecting
        // it here keeps the answer intact on the exception.
        validateStatus: (status) => status == 201,
      );
      return queueTimelineFromGen(_require(response.data), baseUrl: _baseUrl);
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
  });

  @override
  Future<void> releaseQueueTimeline(String pid) => _guard(() async {
    await _gen.getPlayerApi().releaseQueueTimeline(pid: pid);
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
  Future<PlayState> setPlayed(
    String pid, {
    required bool played,
    required bool finished,
    int? playCount,
    int? positionMs,
    DateTime? recordedAt,
  }) => _guard(() async {
    final response = await _gen.getPlaybackApi().setPlayed(
      pid: pid,
      playedUpdate: gen.PlayedUpdate(
        (b) => b
          ..played = played
          ..finished = finished
          ..playCount = playCount
          ..positionMs = positionMs
          ..recordedAt = recordedAt?.toUtc(),
      ),
    );
    return playStateFromGen(_require(response.data));
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
    final api = _gen.getPlaybackApi();
    final response = _isArtistPid(pid)
        ? await api.getArtistPlayState(pid: pid)
        : await api.getAlbumPlayState(pid: pid);
    return entityPlayStateFromGen(_require(response.data));
  });

  @override
  Future<EntityPlayState> setEntityStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) => _guard(() async {
    final api = _gen.getPlaybackApi();
    final update = gen.StarUpdate(
      (b) => b
        ..starred = starred
        ..recordedAt = recordedAt?.toUtc(),
    );
    final response = _isArtistPid(pid)
        ? await api.setArtistStar(pid: pid, starUpdate: update)
        : await api.setAlbumStar(pid: pid, starUpdate: update);
    return entityPlayStateFromGen(_require(response.data));
  });

  @override
  Future<EntityPlayState> setEntityRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) => _guard(() async {
    final api = _gen.getPlaybackApi();
    final update = gen.RatingUpdate(
      (b) => b
        ..rating = rating
        ..recordedAt = recordedAt?.toUtc(),
    );
    final response = _isArtistPid(pid)
        ? await api.setArtistRating(pid: pid, ratingUpdate: update)
        : await api.setAlbumRating(pid: pid, ratingUpdate: update);
    return entityPlayStateFromGen(_require(response.data));
  });

  @override
  Future<StarredEntities> listStarredEntities() => _guard(() async {
    final response = await _gen.getPlaybackApi().listStarredEntities();
    return starredEntitiesFromGen(_require(response.data));
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
  Future<List<String>> syncCatalogRemoved(List<String> pids) =>
      _guard(() async {
        final response = await _gen.getSyncApi().syncCatalogRemoved(
          removedItemsQuery: gen.RemovedItemsQuery((b) => b..pids.addAll(pids)),
        );
        return _require(response.data).pids.toList();
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
  Future<List<PodcastDirectoryEntry>> searchPodcastDirectory(
    String query, {
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getPodcastsApi().searchPodcastDirectory(
      query: query,
      limit: limit,
    );
    return _require(
      response.data,
    ).entries.map(podcastDirectoryEntryFromGen).toList(growable: false);
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
  Future<RefreshResult> refreshPodcast(String pid) => _guard(() async {
    final response = await _gen.getPodcastsApi().refreshPodcast(pid: pid);
    return RefreshResult(newEpisodes: _require(response.data).newEpisodes);
  });

  @override
  Future<EpisodePage> listSubscribedEpisodes({
    SubscribedEpisodes filter = SubscribedEpisodes.latest,
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getPodcastsApi().listSubscribedEpisodes(
      filter: filter.wireName,
      cursor: cursor,
      limit: limit,
    );
    return episodePageFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<BookDetail> getBook(String pid) => _guard(() async {
    final response = await _gen.getBooksApi().getBook(pid: pid);
    return bookDetailFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<BookSeriesPage> listBookSeries({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getBooksApi().listBookSeries(
          cursor: cursor,
          limit: limit,
        );
        return bookSeriesPageFromGen(_require(response.data));
      });

  @override
  Future<BookSeriesDetail> getBookSeries(String pid) => _guard(() async {
    final response = await _gen.getBooksApi().getBookSeries(pid: pid);
    return bookSeriesDetailFromGen(_require(response.data), baseUrl: _baseUrl);
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
  Future<List<Bookmark>> listBookmarks(String pid) => _guard(() async {
    final response = await _gen.getBooksApi().listBookmarks(pid: pid);
    return _require(response.data).bookmarks.map(bookmarkFromGen).toList();
  });

  @override
  Future<Bookmark> createBookmark(
    String pid,
    int positionMs, {
    String? note,
    String? id,
  }) => _guard(() async {
    final response = await _gen.getBooksApi().createBookmark(
      pid: pid,
      bookmarkCreate: gen.BookmarkCreate(
        (b) => b
          ..id = id
          ..positionMs = positionMs
          ..note = note,
      ),
    );
    return bookmarkFromGen(_require(response.data));
  });

  @override
  Future<void> deleteBookmark(String pid, String bookmarkId) => _guard(
    () async {
      await _gen.getBooksApi().deleteBookmark(pid: pid, bookmarkId: bookmarkId);
    },
  );

  @override
  Future<SkipMap> getSkipMap(String pid, {int? partIndex}) => _guard(() async {
    final response = await _gen.getPlaybackApi().getSkipMap(
      pid: pid,
      partIndex: partIndex,
    );
    return skipMapFromGen(_require(response.data));
  });

  @override
  Future<Waveform> getWaveform(String pid, {bool wholeItem = false}) =>
      _guard(() async {
        final response = await _gen.getPlaybackApi().getWaveform(
          pid: pid,
          span: wholeItem ? 'item' : null,
        );
        return waveformFromGen(_require(response.data));
      });

  @override
  Future<Lyrics?> getItemLyrics(String pid) => _guard(() async {
    try {
      final response = await _gen.getLibraryApi().getItemLyrics(pid: pid);
      return lyricsFromGen(_require(response.data));
    } on DioException catch (e) {
      // An item with no words is a state, not an error, for callers.
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  });

  @override
  Future<String> exportOpml() => _guard(() async {
    return _require((await _gen.getPodcastsApi().exportOpml()).data);
  });

  @override
  Future<List<OpmlImportOutcome>> importOpml(String opml) => _guard(() async {
    final response = await _gen.getPodcastsApi().importOpml(
      // Every feed is subscribed, one after another, before it answers.
      extra: const {_longOperation: true},
      opmlImport: gen.OpmlImport((b) => b..opml = opml),
    );
    return _require(
      response.data,
    ).results.map(opmlImportOutcomeFromGen).toList(growable: false);
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
    return playlistPageFromGen(_require(response.data), baseUrl: _baseUrl);
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
    return playlistFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<Playlist> getPlaylist(String pid) => _guard(() async {
    final response = await _gen.getPlaylistsApi().getPlaylist(pid: pid);
    return playlistFromGen(_require(response.data), baseUrl: _baseUrl);
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
    return playlistFromGen(_require(response.data), baseUrl: _baseUrl);
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
  Future<void> removePlaylistItemAt(
    String pid,
    int position, {
    String? itemPid,
  }) => _guard(() async {
    await _gen.getPlaylistsApi().removePlaylistItemAt(
      pid: pid,
      position: position,
      itemPid: itemPid,
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
      // Every line is resolved before the answer, each relative one a scan
      // of the catalog's files.
      extra: const {_longOperation: true},
      m3uImport: gen.M3uImport(
        (b) => b
          ..name = name
          ..content = content
          ..visibility = visibility,
      ),
    );
    return m3uImportResultFromGen(_require(response.data), baseUrl: _baseUrl);
  });

  @override
  Future<M3uPreview> previewPlaylistM3u(String content) => _guard(() async {
    final response = await _gen.getPlaylistsApi().previewPlaylistM3u(
      // Resolved line by line before the answer, as the import is.
      extra: const {_longOperation: true},
      m3uPreviewRequest: gen.M3uPreviewRequest((b) => b..content = content),
    );
    return m3uPreviewFromGen(_require(response.data), baseUrl: _baseUrl);
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
  Future<PlaylistSource> getPlaylistSource(String pid) => _guard(() async {
    final response = await _gen.getPlaylistsApi().getPlaylistSource(pid: pid);
    return playlistSourceFromGen(_require(response.data));
  });

  @override
  Future<PlaylistSource> setPlaylistSource(
    String pid, {
    required String mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().setPlaylistSource(
      pid: pid,
      playlistSourceUpdate: _playlistSourceUpdateToGen(
        mode: mode,
        url: url,
        source: source,
        payload: payload,
        refs: refs,
        intervalHours: intervalHours,
      ),
    );
    return playlistSourceFromGen(_require(response.data));
  });

  @override
  Future<void> unbindPlaylistSource(String pid) => _guard(() async {
    await _gen.getPlaylistsApi().unbindPlaylistSource(pid: pid);
  });

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
    final response = await _gen.getPlaylistsApi().previewPlaylistSync(
      pid: pid,
      playlistSourceUpdate: mode == null
          ? null
          : _playlistSourceUpdateToGen(
              mode: mode,
              url: url,
              source: source,
              payload: payload,
              refs: refs,
              intervalHours: intervalHours,
            ),
    );
    return playlistSyncPreviewFromGen(_require(response.data));
  });

  @override
  Future<ToolTask> syncPlaylistSource(String pid) => _guard(() async {
    final response = await _gen.getPlaylistsApi().syncPlaylistSource(pid: pid);
    return toolTaskFromGen(_require(response.data));
  });

  static gen.PlaylistSourceUpdate _playlistSourceUpdateToGen({
    required String mode,
    String? url,
    String? source,
    String? payload,
    List<PortableRef>? refs,
    int? intervalHours,
  }) => gen.PlaylistSourceUpdate(
    (b) => b
      ..mode = _playlistSourceModeToGen(mode)
      ..url = url
      ..source_ = source == null
          ? null
          : gen.PlaylistSourceUpdateSource_Enum.valueOf(source)
      ..payload = payload
      ..refs = refs == null
          ? null
          : ListBuilder<gen.PortableRef>(refs.map(portableRefToGen))
      ..intervalHours = intervalHours,
  );

  /// An explicit switch rather than `valueOf`: built_value's lookup
  /// takes Dart identifiers, so the wire's `mirror-trash` would fall
  /// to the unknown-default constant and serialize as garbage the
  /// server refuses. `append`/`mirror` only work by the accident of
  /// their Dart names equalling their wire values.
  static gen.PlaylistSourceUpdateModeEnum _playlistSourceModeToGen(
    String mode,
  ) => switch (mode) {
    'append' => gen.PlaylistSourceUpdateModeEnum.append,
    'mirror' => gen.PlaylistSourceUpdateModeEnum.mirror,
    'mirror-trash' => gen.PlaylistSourceUpdateModeEnum.mirrorTrash,
    _ => gen.PlaylistSourceUpdateModeEnum.valueOf(mode),
  };

  @override
  Future<NspReport> reportPlaylistNspExport(String pid) => _guard(() async {
    final response = await _gen.getPlaylistsApi().reportPlaylistNspExport(
      pid: pid,
    );
    return nspReportFromGen(_require(response.data));
  });

  // The two NSP calls post the document as pasted: the generated body is
  // a map of JsonObject, which has no form for a top-level null.
  @override
  Future<NspReport> checkNspImport(Map<String, Object?> document) =>
      _guard(() async {
        final response = await _gen.dio.post<Object?>(
          '/playlists/nsp/report',
          data: document,
        );
        return nspReportFromGen(
          _require(
            gen.standardSerializers.deserializeWith(
              gen.NspReport.serializer,
              response.data,
            ),
          ),
        );
      });

  @override
  Future<Playlist> importNsp(
    Map<String, Object?> document, {
    bool partial = false,
    String? name,
  }) => _guard(() async {
    final response = await _gen.dio.post<Object?>(
      '/playlists/nsp',
      data: document,
      queryParameters: <String, Object?>{
        if (name != null) 'name': name,
        if (partial) 'partial': true,
      },
    );
    return playlistFromGen(
      _require(
        gen.standardSerializers.deserializeWith(
          gen.Playlist.serializer,
          response.data,
        ),
      ),
      baseUrl: _baseUrl,
    );
  });

  @override
  Future<Map<String, Object?>> exportPlaylistNsp(
    String pid, {
    bool partial = false,
    String? ruleHash,
  }) => _guard(() async {
    final response = await _gen.getPlaylistsApi().exportPlaylistNsp(
      pid: pid,
      // Only when it is asked for: the parameter defaults false on the
      // wire, and sending it always would put a query string on every
      // strict export for nothing.
      partial: partial ? true : null,
      ruleHash: ruleHash,
    );
    // The document is another server's grammar, carried verbatim. It
    // stays a map: nothing here reads it, and a model of it would be a
    // second place to keep in step with a format WaxDeck does not own.
    return <String, Object?>{
      for (final entry in _require(response.data).entries)
        entry.key: entry.value.value,
    };
  });

  @override
  Future<SharePage> listShares({
    String? cursor,
    int? limit,
    bool all = false,
  }) => _guard(() async {
    final response = await _gen.getSharesApi().listShares(
      all: all ? true : null,
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
  Future<List<PlaybackSessionHistoryEntry>> listPlaybackSessionHistory() =>
      _guard(() async {
        final response = await _gen.getPlayerApi().listPlaybackSessionHistory();
        return _require(
          response.data,
        ).sessions.map(playbackHistoryFromGen).toList(growable: false);
      });

  @override
  Future<PlaybackSessionInfo> createPlaybackSession({
    required String endpointId,
    required List<String> itemPids,
    int index = 0,
    int positionMs = 0,
    bool play = true,
    double? rate,
    String? repeat,
    bool? shuffle,
    String? handoffFrom,
  }) => _guard(() async {
    final response = await _gen.getPlayerApi().createPlaybackSession(
      playbackSessionCreate: gen.PlaybackSessionCreate(
        (b) => b
          ..endpointId = endpointId
          ..itemPids.replace(itemPids)
          ..index = index
          ..positionMs = positionMs
          ..play = play
          ..rate = rate
          ..repeat = repeat
          ..shuffle = shuffle
          ..handoffFrom = handoffFrom,
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
  Future<List<CastPreflightBase>> getCastPreflight() => _guard(() async {
    final response = await _gen.getPlayerApi().getCastPreflight();
    return _require(
      response.data,
    ).bases.map(castPreflightBaseFromGen).toList(growable: false);
  });

  @override
  Future<CastDeviceProbe> probeCastEndpoint(String endpointId) =>
      _guard(() async {
        final response = await _gen.getPlayerApi().probeCastEndpoint(
          // The server drives a real device through every candidate
          // address before it answers, and each one gets ten seconds
          // to fetch: the whole job happens before the response line,
          // and the ordinary receive budget would call a healthy check
          // dead at exactly the moment it had something to say.
          extra: const {_longOperation: true},
          endpointId: endpointId,
        );
        return castDeviceProbeFromGen(_require(response.data));
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
      nowPlayingItemPid: info.nowPlayingItemPid,
      nowPlayingArtKey: info.nowPlayingArtKey,
      nowPlayingArtSource: artSourceFromGen(info.nowPlayingArtSource),
      nowPlayingSaved: info.nowPlayingSaved ?? false,
      nowPlayingSavedPid: info.nowPlayingSavedPid,
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
  Future<RadioSavedSongPage> listRadioSavedSongs({
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getRadioApi().listRadioSavedSongs(
      cursor: cursor,
      limit: limit,
    );
    return radioSavedSongPageFromGen(_require(response.data));
  });

  @override
  Future<RadioSavedSong> saveRadioSong({
    required String stationPid,
    required String nowPlaying,
  }) => _guard(() async {
    final response = await _gen.getRadioApi().saveRadioSong(
      radioSavedSongCreate: gen.RadioSavedSongCreate(
        (b) => b
          ..stationPid = stationPid
          ..nowPlaying = nowPlaying,
      ),
    );
    return radioSavedSongFromGen(_require(response.data));
  });

  @override
  Future<void> deleteRadioSavedSong(String pid) => _guard(() async {
    await _gen.getRadioApi().deleteRadioSavedSong(pid: pid);
  });

  @override
  String radioSavedArtUrlFor(String pid) => resolveMediaUrl(
    _baseUrl,
    '/api/v1/radio/saved/${Uri.encodeComponent(pid)}/art',
  );

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
    bool muted = false,
    int minIntervalSeconds = 0,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .createServerNotificationTarget(
          notificationTargetCreate: _targetCreateToGen(
            kind: kind,
            label: label,
            config: config,
            enabledEvents: enabledEvents,
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
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
    bool muted = false,
    int minIntervalSeconds = 0,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .updateServerNotificationTarget(
          targetId: pid,
          notificationTargetUpdate: _targetUpdateToGen(
            label: label,
            config: config,
            enabledEvents: enabledEvents,
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
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
    bool muted = false,
    int minIntervalSeconds = 0,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .createMyNotificationTarget(
          notificationTargetCreate: _targetCreateToGen(
            kind: kind,
            label: label,
            config: config,
            enabledEvents: enabledEvents,
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
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
    bool muted = false,
    int minIntervalSeconds = 0,
  }) => _guard(() async {
    final response = await _gen
        .getNotificationsApi()
        .updateMyNotificationTarget(
          targetId: pid,
          notificationTargetUpdate: _targetUpdateToGen(
            label: label,
            config: config,
            enabledEvents: enabledEvents,
            muted: muted,
            minIntervalSeconds: minIntervalSeconds,
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
  Future<ServerNotificationPage> listMyNotifications({
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getNotificationsApi().listMyNotifications(
      cursor: cursor,
      limit: limit,
    );
    return serverNotificationPageFromGen(_require(response.data));
  });

  @override
  Future<void> markMyNotificationsRead({List<String> ids = const <String>[]}) =>
      _guard(() async {
        await _gen.getNotificationsApi().markMyNotificationsRead(
          notificationReadRequest: gen.NotificationReadRequest(
            (b) => b..ids.replace(ids),
          ),
        );
      });

  @override
  Future<void> deleteMyNotification(String id) => _guard(() async {
    await _gen.getNotificationsApi().deleteMyNotification(notificationId: id);
  });

  @override
  Future<void> clearMyNotifications() => _guard(() async {
    await _gen.getNotificationsApi().clearMyNotifications();
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
      // The server rewrites every file's tags before it answers.
      extra: const {_longOperation: true},
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
      // Restoring the snapshot retags every file before it answers.
      extra: const {_longOperation: true},
      entryId: entryId,
    );
    return reviewEntryFromGen(_require(response.data));
  });

  @override
  Future<ReviewEntry> reidentifyReviewEntry(
    String entryId, {
    String? artist,
    String? album,
    String? title,
  }) => _guard(() async {
    final response = await _gen.getReviewApi().reidentifyReviewEntry(
      entryId: entryId,
      reviewIdentifyRequest: gen.ReviewIdentifyRequest(
        (b) => b
          ..artist = artist
          ..album = album
          ..title = title,
      ),
    );
    return reviewEntryFromGen(_require(response.data));
  });

  @override
  Future<List<ReviewBulkOutcome>> decideReviewBulk(
    List<String> entryIds, {
    required String action,
  }) => _guard(() async {
    final response = await _gen.getReviewApi().decideReviewBulk(
      // Every entry's files are retagged before the server answers.
      extra: const {_longOperation: true},
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
  Future<List<LibraryInfo>> listLibraries({bool counts = false}) =>
      _guard(() async {
        final response = await _gen.getAdminApi().listLibraries(counts: counts);
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
    bool? allowAbsent,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().createLibrary(
      libraryCreate: gen.LibraryCreate(
        (b) => b
          ..name = name
          ..path = path
          ..media = gen.LibraryCreateMediaEnum.valueOf(media ?? 'mixed')
          ..managed = managed ?? false
          ..allowAbsent = allowAbsent ?? false,
      ),
    );
    return libraryCreatedFromGen(_require(response.data));
  });

  @override
  Future<Job> removeLibrary(String libraryPid) => _guard(() async {
    final response = await _gen.getAdminApi().removeLibrary(pid: libraryPid);
    return jobFromGen(_require(response.data));
  });

  @override
  Future<Job> rescanLibrary({bool force = false}) => _guard(() async {
    // The body is optional on the wire; a plain rescan keeps posting
    // none, which is what pre-options servers accept.
    final response = await _gen.getAdminApi().rescanLibrary(
      rescanOptions: force ? gen.RescanOptions((b) => b..force = true) : null,
    );
    return jobFromGen(_require(response.data));
  });

  @override
  Future<GenreTree> getGenreTree() => _guard(() async {
    final response = await _gen.getAdminApi().getGenreTree();
    return genreTreeFromGen(_require(response.data));
  });

  @override
  Future<GenreTree> putGenreTree(List<GenreNode> genres) => _guard(() async {
    final response = await _gen.getAdminApi().putGenreTree(
      genreTreeUpdate: gen.GenreTreeUpdate(
        (b) =>
            b..genres = ListBuilder<gen.GenreNode>(genres.map(genreNodeToGen)),
      ),
    );
    return genreTreeFromGen(_require(response.data));
  });

  @override
  Future<ToolTask> normalizeGenres({bool dryRun = false}) => _guard(() async {
    final response = await _gen.getAdminApi().createGenreNormalization(
      genreNormalizeRequest: gen.GenreNormalizeRequest(
        (b) => b..dryRun = dryRun,
      ),
    );
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<LibraryMatching> getLibraryMatching(String libraryPid) =>
      _guard(() async {
        final response = await _gen.getReviewApi().getLibraryMatching(
          pid: libraryPid,
        );
        return libraryMatchingFromGen(_require(response.data));
      });

  @override
  Future<LibraryMatching> setLibraryMatching(
    String libraryPid,
    LibraryMatching matching,
  ) => _guard(() async {
    final response = await _gen.getReviewApi().setLibraryMatching(
      pid: libraryPid,
      libraryMatching: libraryMatchingToGen(matching),
    );
    return libraryMatchingFromGen(_require(response.data));
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
    bool? identify,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createUpload(
      uploadCreate: gen.UploadCreate(
        (b) => b
          ..fileName = fileName
          ..sizeBytes = sizeBytes
          ..mediaType = uploadMediaTypeToGen(mediaType)
          ..libraryPid = libraryPid
          ..sha256 = sha256
          ..batchId = batchId
          ..batchPath = batchPath
          ..identify = identify,
      ),
    );
    return uploadSessionFromGen(_require(response.data));
  });

  @override
  Future<List<UploadTarget>> listUploadTargets() => _guard(() async {
    final response = await _gen.getUploadsApi().listUploadTargets();
    return _require(response.data).targets
        .map(
          (t) => UploadTarget(
            pid: t.pid,
            name: t.name,
            mediaTypes: t.mediaTypes.map(mediaTypeFromGen).toList(),
            managed: t.managed,
          ),
        )
        .toList();
  });

  @override
  Future<UploadBatch> createUploadBatch({
    required UploadGrouping grouping,
    required String mediaType,
    String? libraryPid,
    bool? identify,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createUploadBatch(
      uploadBatchCreate: gen.UploadBatchCreate(
        (b) => b
          ..grouping = uploadGroupingToGen(grouping)
          ..mediaType = uploadMediaTypeToGen(mediaType)
          ..libraryPid = libraryPid
          ..identify = identify,
      ),
    );
    return uploadBatchFromGen(_require(response.data));
  });

  @override
  Future<UploadBatch> completeUploadBatch(String batchId) => _guard(() async {
    final response = await _gen.getUploadsApi().completeUploadBatch(
      // The finalize imports every declined entry before it answers.
      extra: const {_longOperation: true},
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
        final response = await _gen.getUploadsApi().putUploadData(
          uploadId: uploadId,
          offset: offset,
          body: MultipartFile.fromStream(pieces, bytes.length),
          // The length is what makes a native transport report progress.
          headers: {Headers.contentLengthHeader: '${bytes.length}'},
          extra: _wholeRequestCut ? const {_chunkSend: true} : null,
          cancelToken: cancel,
          onSendProgress: (sent, _) {
            handedOver = sent >= bytes.length;
            arm();
          },
        );
        return uploadSessionFromGen(_require(response.data));
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
  Future<UploadSession> completeUpload(String uploadId) => _guard(() async {
    final response = await _gen.getUploadsApi().completeUpload(
      // The seal fingerprints, and may import, before it answers.
      extra: const {_longOperation: true},
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
    bool? identify,
  }) => _guard(() async {
    final response = await _gen.getUploadsApi().createAcquisition(
      acquisitionRequest: gen.AcquisitionRequest(
        (b) => b
          ..url = url
          ..mediaType = uploadMediaTypeToGen(mediaType.wireName)
          ..libraryPid = libraryPid
          ..identify = identify
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
  Future<ItemPermissions> getItemPermissions(String pid) => _guard(() async {
    final response = await _gen.getMetadataApi().getItemPermissions(pid: pid);
    return itemPermissionsFromGen(_require(response.data));
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
  Future<MetadataCommitResult> commitItemMetadata(
    String pid,
    MetadataCommit commit,
  ) => _guard(() async {
    final response = await _gen.getMetadataApi().commitItemMetadata(
      pid: pid,
      metadataCommit: metadataCommitToGen(commit),
    );
    return metadataCommitResultFromGen(_require(response.data));
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
  Future<void> clearItemLyrics(String pid, {bool writeBack = false}) =>
      _guard(() async {
        await _gen.getMetadataApi().clearItemLyrics(
          pid: pid,
          writeBack: writeBack,
        );
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
  Future<ArtRoles> getItemArtRoles(String pid) => _guard(() async {
    final response = await _gen.getLibraryApi().getItemArtRoles(pid: pid);
    return artRolesFromGen(_require(response.data));
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
  Future<void> clearEntityArtwork(
    String entityType,
    String entityPid, {
    String role = 'front',
  }) => _guard(() async {
    await _gen.getMetadataApi().clearEntityArtwork(
      entityType: entityType,
      entityPid: entityPid,
      role: gen.ArtRole.valueOf(role),
    );
  });

  @override
  Future<bool> getEntityArtworkLock(
    String entityType,
    String entityPid, {
    String role = 'front',
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().getEntityArtworkLock(
      entityType: entityType,
      entityPid: entityPid,
      role: gen.ArtRole.valueOf(role),
    );
    return _require(response.data).locked;
  });

  @override
  Future<bool> setEntityArtworkLock(
    String entityType,
    String entityPid, {
    required bool locked,
    String role = 'front',
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setEntityArtworkLock(
      entityType: entityType,
      entityPid: entityPid,
      role: gen.ArtRole.valueOf(role),
      artworkLock: gen.ArtworkLock((b) => b.locked = locked),
    );
    return _require(response.data).locked;
  });

  @override
  Future<MetadataEditResult> setItemAcquisition(
    String pid, {
    required String sourceType,
    String? sourceUrl,
    String? sourceId,
    String? provider,
    DateTime? acquiredAt,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemAcquisition(
      pid: pid,
      itemAcquisitionEdit: gen.ItemAcquisitionEdit(
        (b) => b
          ..sourceType = sourceType
          ..sourceUrl = sourceUrl
          ..sourceId = sourceId
          ..provider = provider
          ..acquiredAt = acquiredAt?.toUtc()
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return metadataEditResultFromGen(_require(response.data));
  });

  @override
  Future<void> clearItemAcquisition(
    String pid, {
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    await _gen.getMetadataApi().clearItemAcquisition(
      pid: pid,
      writeBack: writeBack,
      lock: lock,
      force: force,
    );
  });

  @override
  Future<TagEditResult> setItemTag(
    String pid,
    String key, {
    required List<String> values,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemTag(
      pid: pid,
      key: key,
      tagEdit: gen.TagEdit(
        (b) => b
          ..values = ListBuilder<String>(values)
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return tagEditResultFromGen(_require(response.data));
  });

  @override
  Future<void> clearItemTag(String pid, String key, {bool writeBack = false}) =>
      _guard(() async {
        await _gen.getMetadataApi().clearItemTag(
          pid: pid,
          key: key,
          writeBack: writeBack,
        );
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
  Future<Job> setItemKind(
    List<String> pids, {
    required String mediaType,
    bool writeBack = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setItemKind(
      setItemKindRequest: gen.SetItemKindRequest(
        (b) => b
          ..pids.replace(pids)
          ..mediaType = gen.SetItemKindRequestMediaTypeEnum.valueOf(mediaType)
          ..writeBack = writeBack,
      ),
    );
    return jobFromGen(_require(response.data));
  });

  @override
  Future<DetachResult> detachItem(String pid, {bool writeBack = false}) =>
      _guard(() async {
        final response = await _gen.getMetadataApi().detachItem(
          pid: pid,
          detachRequest: gen.DetachRequest((b) => b..writeBack = writeBack),
        );
        return detachResultFromGen(_require(response.data));
      });

  @override
  Future<EntityRenameResult> renameEntity(
    String entityType,
    String entityPid, {
    required Map<String, String> fields,
    bool writeBack = false,
    bool lock = true,
    bool force = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().renameEntity(
      entityType: entityType,
      entityPid: entityPid,
      entityRename: gen.EntityRename(
        (b) => b
          ..fields = MapBuilder<String, String>(fields)
          ..writeBack = writeBack
          ..lock = lock
          ..force = force,
      ),
    );
    return entityRenameResultFromGen(_require(response.data));
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
    bool writeBack = false,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().setReleaseStatus(
      pid: pid,
      releaseStatusEdit: gen.ReleaseStatusEdit(
        (b) => b
          ..unofficial = unofficial
          ..writeBack = writeBack,
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
    EnrichProposal? proposal,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().enrichItem(
      pid: pid,
      enrichItemRequest: gen.EnrichItemRequest(
        (b) => b
          ..want = ListBuilder<gen.EnrichItemRequestWantEnum>(
            want.map(gen.EnrichItemRequestWantEnum.valueOf),
          )
          ..proposal = proposal == null
              ? null
              : enrichProposalToGen(proposal).toBuilder(),
      ),
    );
    return enrichItemResultFromGen(_require(response.data));
  });

  @override
  Future<EnrichPreview> previewEnrichItem(
    String pid, {
    required List<String> want,
  }) => _guard(() async {
    final response = await _gen.getMetadataApi().previewEnrichItem(
      pid: pid,
      enrichItemRequest: gen.EnrichItemRequest(
        (b) => b
          ..want = ListBuilder<gen.EnrichItemRequestWantEnum>(
            want.map(gen.EnrichItemRequestWantEnum.valueOf),
          ),
      ),
    );
    return enrichPreviewFromGen(_require(response.data));
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
  Future<HealthFixStart> fixHealthIssues({
    required String rule,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _gen.getHealthApi().fixHealthIssues(
      healthFixRequest: gen.HealthFixRequest(
        (b) => b
          ..rule = rule
          ..itemPids = itemPids == null ? null : ListBuilder<String>(itemPids),
      ),
    );
    return healthFixStartFromGen(_require(response.data));
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
    return MergeOutcome(
      merged: body.merged,
      childrenMoved: body.childrenMoved,
      folds: body.folds.toList(growable: false),
    );
  });

  @override
  Future<EntityFoldPage> listEntityFolds({String? cursor, int? limit}) =>
      _guard(() async {
        final response = await _gen.getHealthApi().listEntityFolds(
          cursor: cursor,
          limit: limit,
        );
        final page = _require(response.data);
        return EntityFoldPage(
          folds: page.folds.map(entityFoldFromGen).toList(growable: false),
          nextCursor: page.nextCursor,
        );
      });

  @override
  Future<void> unfoldEntities({
    required String entityType,
    required List<String> keys,
  }) => _guard(() async {
    await _gen.getHealthApi().unfoldEntities(
      unfoldRequest: gen.UnfoldRequest(
        (b) => b
          ..entityType = unfoldEntityTypeToGen(entityType)
          ..keys = ListBuilder<String>(keys),
      ),
    );
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
    List<String> removeItemPids = const [],
    String? keepFilePid,
    List<String> removeFilePids = const [],
  }) => _guard(() async {
    final response = await _gen.getHealthApi().resolveUpgrade(
      upgradeResolveRequest: gen.UpgradeResolveRequest((b) {
        b.keepItemPid = keepItemPid;
        if (removeItemPids.isNotEmpty) {
          b.removeItemPids = ListBuilder<String>(removeItemPids);
        }
        if (keepFilePid != null) b.keepFilePid = keepFilePid;
        if (removeFilePids.isNotEmpty) {
          b.removeFilePids = ListBuilder<String>(removeFilePids);
        }
      }),
    );
    return _require(response.data).trashed;
  });

  @override
  Future<OrganizeProfiles> listOrganizeProfiles() => _guard(() async {
    final response = await _gen.getOrganizeApi().listOrganizeProfiles();
    return organizeProfilesFromGen(_require(response.data));
  });

  @override
  Future<OrganizeProfile> putOrganizeProfile(
    String name, {
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    bool tagWrite = false,
    String? compilationFolder,
  }) => _guard(() async {
    // The generated client puts a path parameter in as typed.
    final response = await _gen.getOrganizeApi().putOrganizeProfile(
      name: Uri.encodeComponent(name),
      organizeProfileInput: gen.OrganizeProfileInput(
        (b) => b
          ..musicTemplate = musicTemplate
          ..audiobookTemplate = audiobookTemplate
          ..podcastTemplate = podcastTemplate
          ..tagWrite = tagWrite
          ..compilationFolder = compilationFolder,
      ),
    );
    return organizeProfileFromGen(_require(response.data));
  });

  @override
  Future<void> deleteOrganizeProfile(String name) => _guard(() async {
    await _gen.getOrganizeApi().deleteOrganizeProfile(
      name: Uri.encodeComponent(name),
    );
  });

  @override
  Future<OrganizeSample> previewOrganizeProfile({
    String? name,
    String musicTemplate = '',
    String audiobookTemplate = '',
    String podcastTemplate = '',
    String? compilationFolder,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().previewOrganizeProfile(
      organizeProfilePreview: gen.OrganizeProfilePreview(
        (b) => b
          ..name = name
          ..musicTemplate = musicTemplate
          ..audiobookTemplate = audiobookTemplate
          ..podcastTemplate = podcastTemplate
          ..compilationFolder = compilationFolder,
      ),
    );
    return organizeSampleFromGen(_require(response.data));
  });

  @override
  Future<LibraryInfo> setLibraryProfile(String libraryPid, String profile) =>
      _guard(() async {
        final response = await _gen.getAdminApi().setLibraryProfile(
          pid: libraryPid,
          libraryProfile: gen.LibraryProfile((b) => b..profile = profile),
        );
        return libraryInfoFromGen(_require(response.data));
      });

  @override
  Future<OrganizePlan> previewOrganize({
    String? profile,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().previewOrganize(
      // A library-wide plan looks at every file, which on a network share
      // takes minutes, as the apply's own planning does; one over a few
      // items answers at once, so a hung mount fails it on the ordinary
      // budget.
      extra: itemPids == null ? const {_longOperation: true} : null,
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
    String? profile,
    List<String>? itemPids,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().applyOrganize(
      // It answers once its run has moved every file.
      extra: const {_longOperation: true},
      organizeRequest: gen.OrganizeRequest(
        (b) => b
          ..profile = profile
          ..itemPids = itemPids == null ? null : ListBuilder<String>(itemPids),
      ),
    );
    return organizeReportFromGen(_require(response.data));
  });

  @override
  Future<OrganizeHistoryPage> listOrganizeHistory({
    String? cursor,
    int? limit,
  }) => _guard(() async {
    final response = await _gen.getOrganizeApi().listOrganizeHistory(
      cursor: cursor,
      limit: limit,
    );
    final page = _require(response.data);
    return OrganizeHistoryPage(
      runs: page.batches.map(organizeBatchFromGen).toList(growable: false),
      nextCursor: page.nextCursor,
    );
  });

  @override
  Future<OrganizeReport> undoOrganize(String jobPid) => _guard(() async {
    final response = await _gen.getOrganizeApi().undoOrganize(
      // It answers once its run has moved every file back.
      extra: const {_longOperation: true},
      organizeUndoRequest: gen.OrganizeUndoRequest((b) => b..jobPid = jobPid),
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
  Future<void> deleteToolTask(String taskId) => _guard(() async {
    await _gen.getToolsApi().deleteToolTask(taskId: taskId);
  });

  @override
  Future<ToolTasksCleared> clearFinishedToolTasks({bool all = false}) =>
      _guard(() async {
        final response = await _gen.getToolsApi().clearFinishedToolTasks(
          clearFinishedTasksRequest: gen.ClearFinishedTasksRequest(
            (b) => b
              ..scope = all
                  ? gen.ClearFinishedTasksRequestScopeEnum.all
                  : gen.ClearFinishedTasksRequestScopeEnum.mine,
          ),
        );
        final data = _require(response.data);
        return ToolTasksCleared(deleted: data.deleted, kept: data.kept);
      });

  @override
  Future<EnrichmentStatus> getEnrichmentStatus() => _guard(() async {
    final response = await _gen.getEnrichmentApi().getEnrichmentStatus();
    return enrichmentStatusFromGen(_require(response.data));
  });

  @override
  Future<String> runEnrichment({
    bool force = false,
    List<String> forcePhases = const [],
    List<String> phases = const [],
  }) => _guard(() async {
    final response = await _gen.getEnrichmentApi().runEnrichment(
      enrichmentRunRequest: gen.EnrichmentRunRequest((b) {
        b.force = force;
        if (forcePhases.isNotEmpty) {
          b.forcePhases.addAll(forcePhases.map(enrichmentPhaseToGen));
        }
        if (phases.isNotEmpty) {
          b.phases.addAll(phases.map(enrichmentPhaseToGen));
        }
      }),
    );
    return _require(response.data).jobPid;
  });

  @override
  Future<EnrichmentStatus> putEnrichmentSources(
    List<EnrichmentSource> sources,
  ) => _guard(() async {
    final response = await _gen.getEnrichmentApi().putEnrichmentSources(
      enrichmentSourcesUpdate: enrichmentSourcesToGen(sources),
    );
    return enrichmentStatusFromGen(_require(response.data));
  });

  @override
  Future<EnrichmentCacheReport> getEnrichmentCache() => _guard(() async {
    final response = await _gen.getAdminApi().getEnrichmentCache();
    return enrichmentCacheReportFromGen(_require(response.data));
  });

  @override
  Future<EnrichmentCachePruneResult> pruneEnrichmentCache({
    int? olderThanSeconds,
    int? maxBytes,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().pruneEnrichmentCache(
      enrichmentCachePruneRequest: gen.EnrichmentCachePruneRequest(
        (b) => b
          ..olderThanSeconds = olderThanSeconds
          ..maxBytes = maxBytes,
      ),
    );
    final result = _require(response.data);
    return EnrichmentCachePruneResult(
      removed: result.removed,
      freedBytes: result.freedBytes,
    );
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
  Future<void> deleteUser(String userId, {String playlists = 'transfer'}) =>
      _guard(() async {
        await _gen.getUsersApi().deleteUser(
          userId: userId,
          playlists: playlists,
        );
      });

  @override
  Future<void> setUserPassword(
    String userId,
    String newPassword, {
    String? currentPassword,
  }) => _guard(() async {
    await _gen.getUsersApi().setPassword(
      userId: userId,
      passwordChange: gen.PasswordChange(
        (b) => b
          ..newPassword = newPassword
          ..currentPassword = currentPassword,
      ),
    );
  });

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
  Future<AdminSettings> putAdminSettings(AdminSettingsChange change) =>
      _guard(() async {
        final response = await _gen.getAdminApi().putAdminSettings(
          adminSettingsChange: adminSettingsChangeToGen(change),
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
  Future<TranscodingActivity> getTranscodingActivity() => _guard(() async {
    final response = await _gen.getAdminApi().getTranscodingActivity();
    return transcodingActivityFromGen(_require(response.data));
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
    return _require(response.data).schedules
        // A kind this build predates arrives as the generator's
        // sentinel, and the kind is the path a save PUTs to: drawing the
        // row would offer an edit that cannot land. Left out instead.
        .where((s) => s.kind != gen.ScheduleKind.unknownDefaultOpenApi)
        .map(scheduleFromGen)
        .toList(growable: false);
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
      extra: const {_longOperation: true},
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
    String? serverUrl,
    String? username,
    String? password,
    String? token,
    String? accountId,
    String? exportId,
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
          ..accountId = accountId
          ..exportId = exportId
          ..options = options == null
              ? null
              : migrationOptionsToGen(options).toBuilder()
          ..dryRun = dryRun,
      ),
    );
    return toolTaskFromGen(_require(response.data));
  });

  @override
  Future<MigrationExport> stageMigrationExport({
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) => _guard(() async {
    final response = await _gen.getAdminApi().stageMigrationExport(
      body: MultipartFile.fromStream(openRead, sizeBytes),
      // A stream body is sent chunked unless the length is declared,
      // and the server checks its room and its cap against what the
      // request says it is sending: without this both checks meet a
      // body of unknown size and only fire once it is already on disk.
      headers: {Headers.contentLengthHeader: sizeBytes},
      extra: const {_longOperation: true},
    );
    return migrationExportFromGen(_require(response.data));
  });

  @override
  Future<void> discardMigrationExport(String pid) => _guard(() async {
    await _gen.getAdminApi().discardMigrationExport(exportId: pid);
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
      skippedReadOnly: body.skippedReadOnly,
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
  Future<ThumbnailCacheReport> getThumbnailCache() => _guard(() async {
    final body = _require((await _gen.getAdminApi().getThumbnailCache()).data);
    return ThumbnailCacheReport(
      rows: body.rows,
      bytes: body.bytes,
      sources: body.sources,
      artSources: body.artSources,
      artSourceBytes: body.artSourceBytes,
      oldestAt: body.oldestAt,
      newestAt: body.newestAt,
      rungs: body.rungs
          .map((r) => ThumbnailRung(size: r.size, rows: r.rows, bytes: r.bytes))
          .toList(growable: false),
    );
  });

  @override
  Future<ThumbnailPruneResult> pruneThumbnailCache({
    int? olderThanSeconds,
    int? maxBytes,
  }) => _guard(() async {
    final body = _require(
      (await _gen.getAdminApi().pruneThumbnailCache(
        // Left unset rather than defaulted: an absent bound is
        // unbounded on that axis, and a zero is a real bound, so the
        // two cannot be folded into one number on the way out.
        thumbnailPruneRequest: gen.ThumbnailPruneRequest(
          (b) => b
            ..olderThanSeconds = olderThanSeconds
            ..maxBytes = maxBytes,
        ),
      )).data,
    );
    return ThumbnailPruneResult(
      removed: body.removed,
      freedBytes: body.freedBytes,
    );
  });

  @override
  Future<CatalogConsistency> getCatalogConsistency() => _guard(() async {
    // The check counts the whole catalog before it answers.
    final body = _require(
      (await _gen.getAdminApi().getCatalogConsistency(
        extra: const {_longOperation: true},
      )).data,
    );
    return CatalogConsistency(
      itemsMissingFromSearch: body.itemsMissingFromSearch,
      orphanSearchRows: body.orphanSearchRows,
      artistRollupDrift: body.artistRollupDrift,
      genreRollupDrift: body.genreRollupDrift,
      releaseGroupRollupDrift: body.releaseGroupRollupDrift,
      sortKeyDrift: body.sortKeyDrift,
      bookDurationDrift: body.bookDurationDrift,
      bookIsbnKeyDrift: body.bookIsbnKeyDrift,
      albumYearDrift: body.albumYearDrift,
      releaseYearDrift: body.releaseYearDrift,
      playlistPositionDrift: body.playlistPositionDrift,
      orphanArtSources: body.orphanArtSources,
      orphanThumbnails: body.orphanThumbnails,
      orphanTagProvenance: body.orphanTagProvenance,
      strandedTagRows: body.strandedTagRows,
      consistent: body.consistent,
      reclaimable: body.reclaimable,
    );
  });

  @override
  Future<ToolTask> repairCatalog() => _guard(() async {
    final response = await _gen.getAdminApi().repairCatalog();
    return toolTaskFromGen(_require(response.data));
  });

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
    // Through the generated serializers rather than a hand-written map:
    // these are contract bodies, and a second spelling of them beside
    // the one `make generate` produces is a spelling that drifts.
    String encode(Object value, FullType type) => jsonEncode(
      gen.standardSerializers.serialize(value, specifiedType: type),
    );

    return <ExitRequest>[
      if (pid != null && positionMs != null)
        ExitRequest(
          path: '$_baseUrl/api/v1/items/${Uri.encodeComponent(pid)}/play-state',
          method: 'PUT',
          headers: headers,
          body: encode(
            gen.PlayStateUpdate((b) => b..positionMs = positionMs),
            const FullType(gen.PlayStateUpdate),
          ),
        ),
      if (listen != null)
        ExitRequest(
          path: '$_baseUrl/api/v1/listens',
          method: 'POST',
          headers: headers,
          body: encode(
            gen.ListenReport(
              (b) => b..sessions.add(listenSessionToGen(listen)),
            ),
            const FullType(gen.ListenReport),
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

  @override
  Future<List<Job>> listJobs() => _guard(() async {
    final response = await _gen.getAdminApi().listJobs();
    return _require(response.data).jobs.map(jobFromGen).toList(growable: false);
  });

  @override
  Future<int> clearFinishedJobs() => _guard(() async {
    final response = await _gen.getAdminApi().clearFinishedJobs();
    return _require(response.data).cleared;
  });

  @override
  Future<Job> getJob(String pid) => _guard(() async {
    final response = await _gen.getAdminApi().getJob(pid: pid);
    return jobFromGen(_require(response.data));
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
  Future<bool> setLibraryMedia(String libraryPid, String media) =>
      _guard(() async {
        final response = await _gen.getAdminApi().setLibraryMedia(
          pid: libraryPid,
          libraryMedia: gen.LibraryMedia(
            (b) => b..media = gen.LibraryMediaMediaEnum.valueOf(media),
          ),
        );
        return _require(response.data).scanStarted;
      });

  @override
  Future<bool> setLibraryFolderFallback(String libraryPid, bool on) =>
      _guard(() async {
        final response = await _gen.getAdminApi().setLibraryFolderFallback(
          pid: libraryPid,
          libraryFolderFallback: gen.LibraryFolderFallback(
            (b) => b..folderFallback = on,
          ),
        );
        return _require(response.data).folderFallback;
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

  @override
  Future<List<ItemFile>> getItemFiles(String pid) => _guard(() async {
    final response = await _gen.getLibraryApi().getItemFiles(pid: pid);
    return _require(response.data).files.map(itemFileFromGen).toList();
  });

  @override
  Future<DeleteItemsResult> deleteItemFiles({
    required String pid,
    required List<String> filePids,
    String? mode,
    bool dryRun = false,
  }) => _guard(() async {
    final response = await _gen.getLibraryApi().deleteItemFiles(
      pid: pid,
      deleteItemFilesRequest: gen.DeleteItemFilesRequest(
        (b) => b
          ..filePids = ListBuilder<String>(filePids)
          ..mode = mode == null
              ? null
              : gen.DeleteItemFilesRequestModeEnum.valueOf(mode)
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
      // Client-minted like 'transport' beside it, and not the spec's
      // `internal`: a truncated answer says nothing about whether the
      // server faulted, so wording the two alike would send a reader to
      // report a bug that may not exist.
      throw const WaxDeckApiException(
        code: 'transport-empty',
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
        params: errorParamsFromWire(data['params']),
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
  required bool muted,
  required int minIntervalSeconds,
}) {
  return gen.NotificationTargetCreate(
    (b) => b
      ..kind = gen.NotificationTargetKind.valueOf(kind)
      ..label = label
      ..config = _configToGen(config)
      ..enabledEvents = ListBuilder<String>(enabledEvents)
      ..muted = muted
      ..minIntervalSeconds = minIntervalSeconds,
  );
}

gen.NotificationTargetUpdate _targetUpdateToGen({
  String? label,
  required Map<String, Object?> config,
  required List<String> enabledEvents,
  required bool muted,
  required int minIntervalSeconds,
}) {
  return gen.NotificationTargetUpdate(
    (b) => b
      ..label = label
      ..config = _configToGen(config)
      ..enabledEvents = ListBuilder<String>(enabledEvents)
      ..muted = muted
      ..minIntervalSeconds = minIntervalSeconds,
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
