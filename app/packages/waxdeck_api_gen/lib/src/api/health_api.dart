//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/diagnostic_summary.dart';
import 'package:waxdeck_api_gen/src/model/duplicate_groups.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/file_diagnostic_page.dart';
import 'package:waxdeck_api_gen/src/model/health_fix_request.dart';
import 'package:waxdeck_api_gen/src/model/health_fix_result.dart';
import 'package:waxdeck_api_gen/src/model/health_issue_page.dart';
import 'package:waxdeck_api_gen/src/model/health_summary.dart';
import 'package:waxdeck_api_gen/src/model/merge_request.dart';
import 'package:waxdeck_api_gen/src/model/merge_result.dart';
import 'package:waxdeck_api_gen/src/model/upgrade_groups.dart';
import 'package:waxdeck_api_gen/src/model/upgrade_resolve_request.dart';
import 'package:waxdeck_api_gen/src/model/upgrade_resolve_result.dart';

class HealthApi {

  final Dio _dio;

  final Serializers _serializers;

  const HealthApi(this._dio, this._serializers);

  /// Bulk-fix a health rule
  /// Starts the fix that matches one rule, across the named items or, when &#x60;itemPids&#x60; is absent, every item currently failing the rule. Only a rule the summary reports &#x60;fixable&#x60; has one; any other answers &#x60;invalid-request&#x60; naming the rule, and the summary&#39;s &#x60;fixBlocked&#x60; says what the install lacks for a rule that could be fixed with it. Administrators only.  An unscoped fix of &#x60;missing-art&#x60;, &#x60;missing-lyrics&#x60;, &#x60;missing-genre&#x60;, &#x60;missing-narrator&#x60; or &#x60;missing-asin&#x60; runs the catalog&#39;s enrichment pass as a catalog job whose pid is &#x60;jobPid&#x60;, with those of the phases that fill the rule which this server runs forced to re-ask everything they reach (either of &#x60;missing-art&#x60;&#39;s two picture phases is enough); the pass&#39;s other phases walk their ordinary sweeps, as any pass does. &#x60;missing-genre&#x60; re-asks MusicBrainz about every album. A scoped fix, and every fix of &#x60;path-mismatch&#x60; or &#x60;write-unsynced&#x60;, runs as a &#x60;health-fix&#x60; tool task whose id is &#x60;taskId&#x60;, working item by item. Either runs in the background and is listed where its kind is (&#x60;GET /jobs&#x60;, &#x60;GET /tools/tasks&#x60;); on finishing it re-checks the items it reached (a pass, every item failing the rule) and files a &#x60;health-fix-finished&#x60; notification for the administrator who started it, saying what it filled or why it failed. The &#x60;health&#x60; sync marker goes out when a fix starts and when its re-check lands, and the rule&#39;s &#x60;fixing&#x60; is true in between. The score waits for the next full sweep. &#x60;queued&#x60; is the number of items the fix set out to reach. While an enrichment pass is running, another fix that needs one answers &#x60;conflict&#x60;, as does any fix for a rule whose &#x60;fixing&#x60; is true.  The fixes of &#x60;path-mismatch&#x60; and &#x60;write-unsynced&#x60; write files: while the server is read-only they answer &#x60;read-only&#x60; (and the summary reports them blocked), and a library flagged read-only on its own keeps its files as they are, its items counted as skipped. A fix already running when the server goes read-only skips what it has not reached. 
  ///
  /// Parameters:
  /// * [healthFixRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [HealthFixResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<HealthFixResult>> fixHealthIssues({ 
    required HealthFixRequest healthFixRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/health/fix';
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
      const _type = FullType(HealthFixRequest);
      _bodyData = _serializers.serialize(healthFixRequest, specifiedType: _type);

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

    HealthFixResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(HealthFixResult),
      ) as HealthFixResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<HealthFixResult>(
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

  /// Summarize per-file diagnostics
  /// Diagnostic counts grouped by writer, code, and severity, most severe first, over the whole match. The same origin, code, severity, and library filters as the listing apply; paging does not. A dashboard reads this for its at-a-glance counts without walking the files. Administrators only. 
  ///
  /// Parameters:
  /// * [origin] - Restrict to one writer.
  /// * [code] - Restrict to one diagnostic code.
  /// * [severity] - Restrict to one severity.
  /// * [library_] - Restrict to files under one library root.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [DiagnosticSummary] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<DiagnosticSummary>> getDiagnosticSummary({ 
    String? origin,
    String? code,
    String? severity,
    String? library_,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/diagnostics/summary';
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
      if (origin != null) r'origin': encodeQueryParameter(_serializers, origin, const FullType(String)),
      if (code != null) r'code': encodeQueryParameter(_serializers, code, const FullType(String)),
      if (severity != null) r'severity': encodeQueryParameter(_serializers, severity, const FullType(String)),
      if (library_ != null) r'library': encodeQueryParameter(_serializers, library_, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    DiagnosticSummary? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(DiagnosticSummary),
      ) as DiagnosticSummary;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<DiagnosticSummary>(
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

  /// Metadata health summary
  /// The library completeness score with its per-rule breakdown. Health is computed by a background sweep; &#x60;warmingUp&#x60; is true until the first sweep covers the library (a fresh install shows honest progress instead of a wall of red), and &#x60;sweptAt&#x60; dates the numbers. Items marked unofficial are exempt from rules that assume a canonical release. Rule names are server-defined strings; the current set is &#x60;missing-art&#x60;, &#x60;small-art&#x60;, &#x60;missing-mbid&#x60;, &#x60;missing-year&#x60;, &#x60;missing-genre&#x60;, &#x60;genre-whitelist&#x60;, &#x60;missing-lyrics&#x60;, &#x60;missing-narrator&#x60;, &#x60;missing-asin&#x60;, &#x60;path-mismatch&#x60;, &#x60;write-unsynced&#x60;, &#x60;legacy-tags&#x60;, &#x60;corrupt-audio&#x60;, and &#x60;duration-mismatch&#x60;. &#x60;duration-mismatch&#x60; flags an analyzed file whose header states a length its decoded audio does not have, off by more than two seconds and two percent; it has no bulk fix. A multi-file book fails a file&#39;s rule (&#x60;corrupt-audio&#x60;, &#x60;write-unsynced&#x60;, &#x60;legacy-tags&#x60;, &#x60;duration-mismatch&#x60;) when any of its parts does. &#x60;genre-whitelist&#x60; flags an item carrying a genre the server&#39;s genre tree does not know; it is deliberately not bulk-fixable, because the background normalizer already rewrites everything the tree does know, so what remains is answered by editing the tree (&#x60;/admin/genre-tree&#x60;), not the item. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [HealthSummary] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<HealthSummary>> getLibraryHealth({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/health';
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

    HealthSummary? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(HealthSummary),
      ) as HealthSummary;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<HealthSummary>(
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

  /// List duplicate entities
  /// Duplicate artist, album, release group, and genre groups from the catalog audit, each with a suggested survivor (the audit orders each finding survivor first). Merging re-parents every child (tracks, albums, credits, play history rides along) and the survivor keeps its pid, so a later rescan does not resurrect the loser. The list is bounded to the first two hundred groups; merge and re-list for more. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [DuplicateGroups] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<DuplicateGroups>> listDuplicates({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/duplicates';
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

    DuplicateGroups? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(DuplicateGroups),
      ) as DuplicateGroups;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<DuplicateGroups>(
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

  /// Query per-file diagnostics
  /// Persisted per-file diagnostics (what scan, organize, replaygain, enrichment, tag write-back, and the analyze pass recorded about individual files) across the library in a stable path order, optionally narrowed by origin, code, severity, or library. This is the query surface a diagnostics dashboard reads instead of auditing item by item. Administrators only. 
  ///
  /// Parameters:
  /// * [origin] - Restrict to one writer.
  /// * [code] - Restrict to one diagnostic code.
  /// * [severity] - Restrict to one severity.
  /// * [library_] - Restrict to files under one library root.
  /// * [cursor] - Opaque cursor from a previous page's `nextCursor`. Omit for the first page. 
  /// * [limit] - Maximum diagnostics per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [FileDiagnosticPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<FileDiagnosticPage>> listFileDiagnostics({ 
    String? origin,
    String? code,
    String? severity,
    String? library_,
    String? cursor,
    int? limit = 100,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/diagnostics';
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
      if (origin != null) r'origin': encodeQueryParameter(_serializers, origin, const FullType(String)),
      if (code != null) r'code': encodeQueryParameter(_serializers, code, const FullType(String)),
      if (severity != null) r'severity': encodeQueryParameter(_serializers, severity, const FullType(String)),
      if (library_ != null) r'library': encodeQueryParameter(_serializers, library_, const FullType(String)),
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

    FileDiagnosticPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(FileDiagnosticPage),
      ) as FileDiagnosticPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<FileDiagnosticPage>(
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

  /// List items failing health rules
  /// Keyset-paginated items with outstanding issues, optionally restricted to one rule, worst first (most failed rules, then title). Each row carries every rule the item currently fails so the list doubles as a per-item worklist. 
  ///
  /// Parameters:
  /// * [rule] - Restrict to one rule name.
  /// * [cursor] - Opaque keyset cursor from a previous page's `nextCursor`. Omit for the first page. 
  /// * [limit] - Maximum items per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [HealthIssuePage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<HealthIssuePage>> listHealthIssues({ 
    String? rule,
    String? cursor,
    int? limit = 100,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/health/issues';
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
      if (rule != null) r'rule': encodeQueryParameter(_serializers, rule, const FullType(String)),
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

    HealthIssuePage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(HealthIssuePage),
      ) as HealthIssuePage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<HealthIssuePage>(
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

  /// List quality upgrade groups
  /// Groups of the same recording in different encodings, found through the fingerprint index, best quality first within each group. The resolve endpoint keeps the best and trashes the rest; play history merges onto the kept item. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [UpgradeGroups] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<UpgradeGroups>> listUpgrades({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/upgrades';
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

    UpgradeGroups? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(UpgradeGroups),
      ) as UpgradeGroups;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<UpgradeGroups>(
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

  /// Merge duplicate entities
  /// Merges the losers into the survivor atomically. The losers&#39; children, credits, and play history re-parent onto the survivor; identifiers union. Administrators only. 
  ///
  /// Parameters:
  /// * [mergeRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MergeResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MergeResult>> mergeDuplicates({ 
    required MergeRequest mergeRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/duplicates/merge';
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
      const _type = FullType(MergeRequest);
      _bodyData = _serializers.serialize(mergeRequest, specifiedType: _type);

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

    MergeResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MergeResult),
      ) as MergeResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MergeResult>(
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

  /// Keep the best encoding
  /// Keeps one item of an upgrade group and moves the named inferior encodings to the trash (recoverable within the retention window). A named encoding in a read-only library, or any while the server is read-only, refuses the whole call with &#x60;read-only&#x60;. Administrators only. 
  ///
  /// Parameters:
  /// * [upgradeResolveRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [UpgradeResolveResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<UpgradeResolveResult>> resolveUpgrade({ 
    required UpgradeResolveRequest upgradeResolveRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/upgrades/resolve';
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
      const _type = FullType(UpgradeResolveRequest);
      _bodyData = _serializers.serialize(upgradeResolveRequest, specifiedType: _type);

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

    UpgradeResolveResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(UpgradeResolveResult),
      ) as UpgradeResolveResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<UpgradeResolveResult>(
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

  /// Re-sweep health now
  /// Queues a full health sweep instead of waiting for the scheduled one. Administrators only. The summary&#39;s &#x60;sweeping&#x60; is true from the request until the sweep finishes, and the &#x60;health&#x60; sync marker tells every account when to read the summary again: once when the sweep is queued and once when it finishes. A sweep that fails answers the request too, and the summary&#39;s &#x60;sweepFailed&#x60; says so until a sweep lands; of a run of failures, only the first is marked. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> sweepLibraryHealth({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/health/sweep';
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

    return _response;
  }

}
