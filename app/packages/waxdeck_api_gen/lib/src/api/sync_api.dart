//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/catalog_sync_page.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/server_sync_page.dart';

class SyncApi {

  final Dio _dio;

  final Serializers _serializers;

  const SyncApi(this._dio, this._serializers);

  /// Mirror the catalog (snapshot or changed-since delta)
  /// The catalog half of delta sync, feeding client-side library mirrors with hydrated item summaries. Two modes. Without &#x60;since&#x60;: a snapshot, keyset-paged via &#x60;cursor&#x60;; every page carries &#x60;nextSince&#x60;, an opaque change cursor captured at or before the first page&#39;s read, which the client stores and syncs from after mirroring every page (changes landing mid-snapshot are covered by the first delta). With &#x60;since&#x60;: the changes after that cursor, as &#x60;upsert&#x60; entries carrying fresh summaries and &#x60;delete&#x60; tombstones for items that no longer exist or whose change left them outside the caller&#39;s library visibility (a file re-homed under an ungranted root keeps its item PID; a tombstone for an item never mirrored is a no-op); entries are coalesced within a page (an item may recur on later pages; application is idempotent, latest wins). The returned &#x60;nextSince&#x60; advances the cursor, and &#x60;more&#x60; signals another page should be fetched immediately. Snapshots contain only items the caller can see, and a change to the caller&#39;s visibility grants invalidates their catalog cursors, so the next delta answers 410 &#x60;sync-reset&#x60; and the re-snapshot reflects the new grants. 410 likewise answers any cursor the server can no longer serve contiguously (pruned change history, a rebuilt catalog): drop the mirror and snapshot again. Snapshot-minted cursors stay serviceable for at least the server&#39;s change retention horizon. The WebSocket channel (&#x60;api/events.md&#x60;) signals when to pull deltas; polling works without it. 
  ///
  /// Parameters:
  /// * [since] - Opaque change cursor from a previous response's `nextSince`. Mutually exclusive with `cursor`. 
  /// * [cursor] - Opaque keyset cursor from a previous snapshot page's `nextCursor`. Omit together with `since` for the first snapshot page. 
  /// * [limit] - Maximum entries per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [CatalogSyncPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<CatalogSyncPage>> syncCatalog({ 
    String? since,
    String? cursor,
    int? limit = 500,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/sync/catalog';
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

    final _queryParameters = <String, dynamic>{
      if (since != null) r'since': encodeQueryParameter(_serializers, since, const FullType(String)),
      if (cursor != null) r'cursor': encodeQueryParameter(_serializers, cursor, const FullType(String)),
      if (limit != null) r'limit': encodeQueryParameter(_serializers, limit, const FullType(int)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    CatalogSyncPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(CatalogSyncPage),
      ) as CatalogSyncPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<CatalogSyncPage>(
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

  /// Mirror the caller&#39;s server-side state (changed-since delta)
  /// The server half of delta sync: the calling user&#39;s own state changes (playback state, preferences), on the server change cursor. Without &#x60;since&#x60; it mints a fresh cursor (&#x60;nextSince&#x60; with no events): new mirrors start there and hydrate the play states they care about through &#x60;/play-states&#x60;, since play states are only meaningful for items a client holds. With &#x60;since&#x60; it returns the caller&#39;s events after that cursor with freshly hydrated state, coalesced within a page (an item may recur on later pages; application is idempotent), plus &#x60;more&#x60; for immediate continuation. Only the caller&#39;s own state ever appears here. A &#x60;since&#x60; the server can no longer serve contiguously answers 410 &#x60;sync-reset&#x60;: re-mint and re-hydrate. 
  ///
  /// Parameters:
  /// * [since] - Opaque server change cursor from a previous response's `nextSince`. Omit to mint a fresh cursor. 
  /// * [limit] - Maximum events per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ServerSyncPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ServerSyncPage>> syncServer({ 
    String? since,
    int? limit = 500,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/sync/server';
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

    final _queryParameters = <String, dynamic>{
      if (since != null) r'since': encodeQueryParameter(_serializers, since, const FullType(String)),
      if (limit != null) r'limit': encodeQueryParameter(_serializers, limit, const FullType(int)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ServerSyncPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ServerSyncPage),
      ) as ServerSyncPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ServerSyncPage>(
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
