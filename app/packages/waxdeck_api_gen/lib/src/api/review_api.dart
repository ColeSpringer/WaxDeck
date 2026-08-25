//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/library_matching.dart';
import 'package:waxdeck_api_gen/src/model/review_bulk_decision.dart';
import 'package:waxdeck_api_gen/src/model/review_bulk_result.dart';
import 'package:waxdeck_api_gen/src/model/review_decide_result.dart';
import 'package:waxdeck_api_gen/src/model/review_decision.dart';
import 'package:waxdeck_api_gen/src/model/review_entry.dart';
import 'package:waxdeck_api_gen/src/model/review_entry_detail.dart';
import 'package:waxdeck_api_gen/src/model/review_entry_page.dart';
import 'package:waxdeck_api_gen/src/model/review_identify_request.dart';
import 'package:waxdeck_api_gen/src/model/review_stats.dart';

class ReviewApi {

  final Dio _dio;

  final Serializers _serializers;

  const ReviewApi(this._dio, this._serializers);

  /// Decide many review entries
  /// Applies one decision to many pending entries in a single call, for keyboard-driven bulk triage. &#x60;approve&#x60; uses each entry&#39;s own ranked best candidate (a per-entry candidate choice needs the single-entry endpoint). Entries are decided independently: one failure does not stop the rest, and the response reports each outcome. 
  ///
  /// Parameters:
  /// * [reviewBulkDecision] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewBulkResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewBulkResult>> decideReviewBulk({ 
    required ReviewBulkDecision reviewBulkDecision,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/decide';
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
      const _type = FullType(ReviewBulkDecision);
      _bodyData = _serializers.serialize(reviewBulkDecision, specifiedType: _type);

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

    ReviewBulkResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewBulkResult),
      ) as ReviewBulkResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewBulkResult>(
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

  /// Decide a review entry
  /// Applies one decision to a pending entry. &#x60;approve&#x60; applies the chosen candidate&#39;s metadata to the whole unit (the ranked best when &#x60;candidateMbid&#x60; is absent), locking the applied fields so a rescan cannot undo the acceptance; for entries staging new files (uploads and imports) the files enter the library first. &#x60;as-is&#x60; accepts the unit&#39;s current metadata unchanged (staged files enter the library as they are). &#x60;unofficial&#x60; is &#x60;as-is&#x60; plus a locked &#x60;RELEASESTATUS&#x60; custom tag of &#x60;unofficial&#x60;, which excludes the items from future match retries and from health penalties (content with no canonical release is a terminal state, not an error). &#x60;skip&#x60; dismisses the entry without touching anything (staged files stay staged). &#x60;discard&#x60; deletes staged files and exists only for entries that carry them. Deciding an already-decided entry answers &#x60;conflict&#x60;. Administrators may decide anything; other callers only entries from their own uploads. A metadata write that partially fails after the catalog committed reports per-file detail in &#x60;warnings&#x60; and the entry still counts as decided. 
  ///
  /// Parameters:
  /// * [entryId] - Review entry PID (e.g. `rv-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [reviewDecision] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewDecideResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewDecideResult>> decideReviewEntry({ 
    required String entryId,
    required ReviewDecision reviewDecision,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/queue/{entryId}/decide'.replaceAll('{' r'entryId' '}', encodeQueryParameter(_serializers, entryId, const FullType(String)).toString());
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
      const _type = FullType(ReviewDecision);
      _bodyData = _serializers.serialize(reviewDecision, specifiedType: _type);

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

    ReviewDecideResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewDecideResult),
      ) as ReviewDecideResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewDecideResult>(
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

  /// Read a library&#39;s matching behavior
  /// The library&#39;s automatic matching behavior: the mode and the singles auto-apply switch. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [LibraryMatching] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<LibraryMatching>> getLibraryMatching({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/libraries/{pid}/matching'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    LibraryMatching? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(LibraryMatching),
      ) as LibraryMatching;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<LibraryMatching>(
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

  /// Inspect one review entry
  /// The full entry: the unit&#39;s files with their current metadata, and every scored candidate with its per-field distance breakdown, track pairings (the side-by-side diff renders from these), missing tracks, and extra files. Candidates are ranked best first. Visibility follows the queue listing. 
  ///
  /// Parameters:
  /// * [entryId] - Review entry PID (e.g. `rv-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewEntryDetail] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewEntryDetail>> getReviewEntry({ 
    required String entryId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/queue/{entryId}'.replaceAll('{' r'entryId' '}', encodeQueryParameter(_serializers, entryId, const FullType(String)).toString());
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

    ReviewEntryDetail? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewEntryDetail),
      ) as ReviewEntryDetail;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewEntryDetail>(
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

  /// Review and calibration statistics
  /// Queue depth and auto-apply calibration: how many entries auto applied and how many of those were later reverted. The revert rate is the trust signal the review surface shows next to the auto-apply behavior; it is deliberately not the accuracy metric that tunes thresholds (reverts are sparse and lagging). 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewStats] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewStats>> getReviewStats({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/stats';
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

    ReviewStats? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewStats),
      ) as ReviewStats;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewStats>(
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

  /// List review queue entries
  /// Keyset-paginated review queue, newest first. Administrators see every entry; other callers see only entries produced by their own uploads. Each entry is one album-sized unit: it applies or declines as a whole, never track by track. &#x60;status&#x60; filters to one lifecycle state (&#x60;pending&#x60; is the working queue; decided entries remain listable for calibration and undo). 
  ///
  /// Parameters:
  /// * [status] - Restrict to one status. Statuses are server-defined strings; the current set is `pending`, `applied`, `auto-applied`, `as-is`, `unofficial`, `skipped`, `discarded`, and `reverted`. Unknown values yield an empty page rather than an error. 
  /// * [cursor] - Opaque keyset cursor from a previous page's `nextCursor`. Omit for the first page. 
  /// * [limit] - Maximum entries per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewEntryPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewEntryPage>> listReviewQueue({ 
    String? status,
    String? cursor,
    int? limit = 50,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/queue';
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
      if (status != null) r'status': encodeQueryParameter(_serializers, status, const FullType(String)),
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

    ReviewEntryPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewEntryPage),
      ) as ReviewEntryPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewEntryPage>(
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

  /// Search again for a review entry
  /// Requeues a pending entry for identification, optionally searching for values the reviewer typed rather than the ones the files claim. The body **replaces** whatever override the entry already carried, so an empty body (or one with every field blank) clears it and runs the plain derivation again.  The typed values stand in for the unit&#39;s own for the search only: &#x60;artist&#x60; for both the artist and the album artist, &#x60;album&#x60; for the album title, &#x60;title&#x60; for the track title. Nothing is written to the files or to the catalog, and the entry&#39;s stored evidence keeps the tags the files actually carry - what changes is only what is looked up. The override persists on the entry, so a retry after a provider failure searches for the same thing.  Typed values are searched for verbatim. The cleanup that reads \&quot;Artist - Track\&quot; out of a video title, peels \&quot;(Official Video)\&quot;, and drops a \&quot; - Topic\&quot; channel suffix exists to rescue titles a machine wrote, and it does not run over these: a title that genuinely contains \&quot; - \&quot; is searched for whole, and a typed artist is not replaced by one a descriptive title happens to name. A field left blank is not an instruction, so it falls back to what the files imply.  Pending entries only; a decided one answers &#x60;conflict&#x60;. The permission is the deciding permission: administrators may re-identify anything, other callers only entries from their own uploads. 
  ///
  /// Parameters:
  /// * [entryId] - Review entry PID (e.g. `rv-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [reviewIdentifyRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewEntry] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewEntry>> reidentifyReviewEntry({ 
    required String entryId,
    ReviewIdentifyRequest? reviewIdentifyRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/queue/{entryId}/identify'.replaceAll('{' r'entryId' '}', encodeQueryParameter(_serializers, entryId, const FullType(String)).toString());
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
      const _type = FullType(ReviewIdentifyRequest);
      _bodyData = reviewIdentifyRequest == null ? null : _serializers.serialize(reviewIdentifyRequest, specifiedType: _type);

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

    ReviewEntry? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewEntry),
      ) as ReviewEntry;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewEntry>(
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

  /// Revert an applied match
  /// Restores the metadata snapshot taken before an &#x60;applied&#x60; or &#x60;auto-applied&#x60; entry was applied, unlocks the fields the apply locked, and marks the entry &#x60;reverted&#x60;. Reverts of auto applied entries feed the calibration statistics. Only administrators and the deciding user may revert. Reverting anything but an applied entry answers &#x60;conflict&#x60;. 
  ///
  /// Parameters:
  /// * [entryId] - Review entry PID (e.g. `rv-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ReviewEntry] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ReviewEntry>> revertReviewEntry({ 
    required String entryId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/review/queue/{entryId}/revert'.replaceAll('{' r'entryId' '}', encodeQueryParameter(_serializers, entryId, const FullType(String)).toString());
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
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ReviewEntry? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ReviewEntry),
      ) as ReviewEntry;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ReviewEntry>(
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

  /// Set a library&#39;s matching behavior
  /// &#x60;auto&#x60; lets confident matches apply themselves and queues the rest for review (the default), &#x60;review&#x60; queues everything (no auto-apply), and &#x60;off&#x60; never matches the library&#39;s content (as-is libraries: already-curated collections the engine must not touch). Under &#x60;auto&#x60;, one-file units still queue unless &#x60;singlesAutoApply&#x60; is on. The body replaces the whole object. Administrators only. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [libraryMatching] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [LibraryMatching] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<LibraryMatching>> setLibraryMatching({ 
    required String pid,
    required LibraryMatching libraryMatching,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/libraries/{pid}/matching'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
    final _options = Options(
      method: r'PUT',
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
      const _type = FullType(LibraryMatching);
      _bodyData = _serializers.serialize(libraryMatching, specifiedType: _type);

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

    LibraryMatching? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(LibraryMatching),
      ) as LibraryMatching;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<LibraryMatching>(
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
