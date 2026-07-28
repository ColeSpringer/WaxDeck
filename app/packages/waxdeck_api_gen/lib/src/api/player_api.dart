//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/cast_preflight.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/job.dart';
import 'package:waxdeck_api_gen/src/model/playback_session.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_create.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_history_list.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_list.dart';
import 'package:waxdeck_api_gen/src/model/playback_session_transfer.dart';
import 'package:waxdeck_api_gen/src/model/player_endpoint_list.dart';
import 'package:waxdeck_api_gen/src/model/timeline_create.dart';
import 'package:waxdeck_api_gen/src/model/timeline_info.dart';

class PlayerApi {

  final Dio _dio;

  final Serializers _serializers;

  const PlayerApi(this._dio, this._serializers);

  /// Start playback on an endpoint
  /// Loads a queue onto an endpoint and starts a server-tracked playback session there (\&quot;play on the kitchen speaker\&quot;). An endpoint plays at most one session: starting a new session on an endpoint that already has one ends the old session first, whoever owned it (physical outputs are last-writer-wins, like the speaker itself). Item pids must all be visible to the caller; the server shapes stream delivery for the target endpoint&#39;s capabilities, re-minting URLs as needed, so the same queue plays on a phone, a cast device, or a renderer without the caller caring about formats. Sessions on device endpoints are server-authoritative; a session created on one of the caller&#39;s own client endpoints is loaded onto that client and then mirrors the client&#39;s local playback. Conflict with code &#x60;endpoint-offline&#x60; means the target endpoint is not connected right now, and &#x60;timeout&#x60; means it is connected but did not answer in time. A queue the target cannot play answers &#x60;feature-unavailable&#x60; naming the pid — a multi-part audiobook or a windowed track sent to a device endpoint, say — which a controller can turn into an offer to play it somewhere that can, rather than a bare failure. When the target is a client endpoint, that client&#39;s own refusal code and message are what arrive here. 
  ///
  /// Parameters:
  /// * [playbackSessionCreate] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlaybackSession] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlaybackSession>> createPlaybackSession({ 
    required PlaybackSessionCreate playbackSessionCreate,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(PlaybackSessionCreate);
      _bodyData = _serializers.serialize(playbackSessionCreate, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlaybackSession? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlaybackSession),
      ) as PlaybackSession;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlaybackSession>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Mint a gapless queue timeline
  /// Renders an ordered queue of visible items as one continuous stream through the streaming engine: sample-exact seams, no discontinuities, with optional equal-power crossfade. The response&#39;s single HLS URL plays the whole queue; &#x60;boundaries&#x60; map each item onto the combined timeline (offsets in samples at &#x60;envelopeRate&#x60;; under a crossfade consecutive members overlap), so a client can render per-track position and seek across members without probing. Timelines are immutable: editing the queue means minting a new timeline and switching URLs. The URL is media-token authenticated, and the token lives at least the timeline&#39;s duration plus margin (&#x60;expiresAt&#x60; reflects it), so a queue never expires mid-listen; a member file changing on disk surfaces as &#x60;stream-stale&#x60;, and a timeline aged out of the engine&#39;s store answers &#x60;not-found&#x60; on fetch. Re-request this endpoint in either case. Minting may first need to measure member lengths (MP3 sources are scanned); the server absorbs short measurements into this request, and when one outlasts the request budget it answers 202 with a job to poll, after which re-requesting answers 201 immediately. Requires the streaming engine with timeline support (&#x60;feature-unavailable&#x60; otherwise). Items whose delivery cannot join a timeline (unfetched podcast episodes, unsupported sources) answer &#x60;conflict&#x60; naming the pid, and a &#x60;crossfadeSeconds&#x60; longer than the shortest queue member can carry answers &#x60;invalid-request&#x60; naming it. 
  ///
  /// Parameters:
  /// * [timelineCreate] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [TimelineInfo] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<TimelineInfo>> createQueueTimeline({ 
    required TimelineCreate timelineCreate,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/timeline';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(TimelineCreate);
      _bodyData = _serializers.serialize(timelineCreate, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    TimelineInfo? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(TimelineInfo),
      ) as TimelineInfo;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<TimelineInfo>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// End a playback session
  /// Stops playback on the session&#39;s endpoint and ends the session. Ending another user&#39;s session requires it to be on a shared endpoint, the same rule as controlling it. 
  ///
  /// Parameters:
  /// * [sessionId] - Playback session PID (e.g. `ps-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> deletePlaybackSession({ 
    required String sessionId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions/{sessionId}'.replaceAll('{' r'sessionId' '}', encodeQueryParameter(_serializers, sessionId, const FullType(String)).toString());
    final _options = Options(
      method: r'DELETE',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _response;
  }

  /// Check cast reachability
  /// Server-side diagnosis of the bases a cast device would fetch media from, before the user hits a silent cast failure. For each candidate advertise base (the configured public base and the auto-detected LAN address), the server verifies it can fetch itself through that base and reports plain-language notes about scheme, certificate, and name-resolution problems (cast devices require publicly trusted certificates for HTTPS and often ignore LAN DNS; the plain-HTTP LAN base exists so casting works with zero TLS setup). A reachable base here does not guarantee the device can reach it, but an unreachable one reliably predicts failure. Exposing the configured and detected bases to every authenticated user is intentional: casting is a household activity, and any LAN peer learns these addresses trivially. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [CastPreflight] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<CastPreflight>> getCastPreflight({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/cast/preflight';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    CastPreflight? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(CastPreflight),
      ) as CastPreflight;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<CastPreflight>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Get one playback session
  /// One session&#39;s current state. Position is a snapshot: &#x60;positionMs&#x60; was true at &#x60;positionAt&#x60;, and controllers extrapolate forward with &#x60;rate&#x60; while &#x60;playing&#x60; (live updates ride the WebSocket &#x60;watch&#x60; flow). A session outside the caller&#39;s visibility answers &#x60;not-found&#x60;. 
  ///
  /// Parameters:
  /// * [sessionId] - Playback session PID (e.g. `ps-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlaybackSession] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlaybackSession>> getPlaybackSession({ 
    required String sessionId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions/{sessionId}'.replaceAll('{' r'sessionId' '}', encodeQueryParameter(_serializers, sessionId, const FullType(String)).toString());
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlaybackSession? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlaybackSession),
      ) as PlaybackSession;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlaybackSession>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// List the caller&#39;s ended playback sessions
  /// What was playing, where, and how far in — for the sessions that have stopped. This is the queue-restore surface: an entry carries the whole queue with its index and position, so \&quot;pick up where I left off\&quot; needs no second call. Distinct from &#x60;/player/sessions&#x60;, which lists what is playing now and never includes these rows. Only the caller&#39;s own sessions appear, whatever they played on: a shared speaker&#39;s sessions are visible to housemates while they are live, and become private history when they end. The server retains a small number of recent sessions per user (five at present) and prunes the rest, so this list is short and unpaged by design; it is a resume affordance, not a listening log. Ended sessions are also what a restart leaves behind, since playback never resumes by itself: the session interrupted by a server restart is a history entry too, and resuming it is the caller&#39;s choice. A session ended through &#x60;DELETE /player/sessions/{sessionId}&#x60; appears here as soon as that call answers. One that ends any other way — a playing client disconnecting, a device leaving the network, a server restart — appears shortly after, and its position is the last one checkpointed rather than the last one played. Checkpoints run every few seconds while a session is playing, so the gap is small, but it is a gap. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlaybackSessionHistoryList] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlaybackSessionHistoryList>> listPlaybackSessionHistory({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions/history';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlaybackSessionHistoryList? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlaybackSessionHistoryList),
      ) as PlaybackSessionHistoryList;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlaybackSessionHistoryList>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// List playback sessions
  /// Active playback sessions visible to the caller: the caller&#39;s own sessions on any endpoint, plus other users&#39; sessions playing on shared endpoints. Ordered by most recent activity. Unpaginated for the same reason as the endpoint list (an endpoint plays at most one session). 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlaybackSessionList] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlaybackSessionList>> listPlaybackSessions({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlaybackSessionList? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlaybackSessionList),
      ) as PlaybackSessionList;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlaybackSessionList>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// List player endpoints
  /// Every endpoint the caller can play to or control: the caller&#39;s own registered client endpoints (first-party clients connected over the WebSocket that declared themselves controllable) plus shared device endpoints the server drives itself (cast targets, DLNA renderers, the jukebox output). Client endpoints exist while their WebSocket connection lives; device endpoints reflect the most recent discovery sweep and carry &#x60;online&#x60; accordingly. Unpaginated: a household has tens of endpoints, not thousands. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlayerEndpointList] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlayerEndpointList>> listPlayerEndpoints({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/endpoints';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlayerEndpointList? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlayerEndpointList),
      ) as PlayerEndpointList;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlayerEndpointList>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Transfer a session to another endpoint
  /// Moves live playback to another endpoint, keeping the queue and the extrapolated position (\&quot;pick up where you left off\&quot;). The server snapshots the session, loads the target with stream URLs shaped for its capabilities, then stops playback on the source; the session keeps its id and changes &#x60;endpointId&#x60;, so controllers keep following the same session. Transferring to a client endpoint hands the queue to that client, which resumes local playback and reports back (&#x60;authority&#x60; becomes &#x60;mirror&#x60;); transferring to a device endpoint makes the session server-authoritative. A brief overlap or gap at the seam is inherent; position is carried, not resynthesized. Authorization follows control with one tightening: your own sessions may transfer to any endpoint you can see, while a session you do not own may only be transferred to a shared endpoint (moving someone&#39;s queue onto your private device would take it out of their sight). Transferring a session to the endpoint it is already on is a no-op answering 200. Conflict with code &#x60;endpoint-offline&#x60; means the target endpoint is not connected, and &#x60;timeout&#x60; means it is connected but did not answer in time. A queue the target cannot play answers &#x60;feature-unavailable&#x60; naming the pid, on the same terms as starting a session there; when the target is a client endpoint, that client&#39;s own refusal code and message are what arrive here. The tightening above is a &#x60;forbidden&#x60;, not a &#x60;not-found&#x60;: the session is one the caller can see and control, and it is the target endpoint that is out of bounds. 
  ///
  /// Parameters:
  /// * [sessionId] - Playback session PID (e.g. `ps-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [playbackSessionTransfer] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PlaybackSession] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PlaybackSession>> transferPlaybackSession({ 
    required String sessionId,
    required PlaybackSessionTransfer playbackSessionTransfer,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/player/sessions/{sessionId}/transfer'.replaceAll('{' r'sessionId' '}', encodeQueryParameter(_serializers, sessionId, const FullType(String)).toString());
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'apiKey',
            'name': 'cookieAuth',
            'keyName': 'waxdeck_session',
            'where': '',
          },{
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(PlaybackSessionTransfer);
      _bodyData = _serializers.serialize(playbackSessionTransfer, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PlaybackSession? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PlaybackSession),
      ) as PlaybackSession;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PlaybackSession>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

}
