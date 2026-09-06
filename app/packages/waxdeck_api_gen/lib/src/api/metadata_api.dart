//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/art_role.dart';
import 'package:waxdeck_api_gen/src/model/artwork_lock.dart';
import 'package:waxdeck_api_gen/src/model/bulk_edit.dart';
import 'package:waxdeck_api_gen/src/model/bulk_edit_result.dart';
import 'package:waxdeck_api_gen/src/model/chapters_edit.dart';
import 'package:waxdeck_api_gen/src/model/credits_edit.dart';
import 'package:waxdeck_api_gen/src/model/detach_request.dart';
import 'package:waxdeck_api_gen/src/model/detach_result.dart';
import 'package:waxdeck_api_gen/src/model/enrich_item_request.dart';
import 'package:waxdeck_api_gen/src/model/enrich_item_result.dart';
import 'package:waxdeck_api_gen/src/model/enrich_preview.dart';
import 'package:waxdeck_api_gen/src/model/entity_curation.dart';
import 'package:waxdeck_api_gen/src/model/entity_edit.dart';
import 'package:waxdeck_api_gen/src/model/entity_rename.dart';
import 'package:waxdeck_api_gen/src/model/entity_rename_result.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/item_acquisition_edit.dart';
import 'package:waxdeck_api_gen/src/model/item_metadata.dart';
import 'package:waxdeck_api_gen/src/model/item_permissions.dart';
import 'package:waxdeck_api_gen/src/model/locks_edit.dart';
import 'package:waxdeck_api_gen/src/model/locks_result.dart';
import 'package:waxdeck_api_gen/src/model/lyrics_edit.dart';
import 'package:waxdeck_api_gen/src/model/metadata_commit.dart';
import 'package:waxdeck_api_gen/src/model/metadata_commit_result.dart';
import 'package:waxdeck_api_gen/src/model/metadata_edit.dart';
import 'package:waxdeck_api_gen/src/model/metadata_edit_result.dart';
import 'package:waxdeck_api_gen/src/model/metadata_fields.dart';
import 'package:waxdeck_api_gen/src/model/release_status_edit.dart';
import 'package:waxdeck_api_gen/src/model/rematch_result.dart';
import 'package:waxdeck_api_gen/src/model/tag_edit.dart';
import 'package:waxdeck_api_gen/src/model/tag_edit_result.dart';

class MetadataApi {

  final Dio _dio;

  final Serializers _serializers;

  const MetadataApi(this._dio, this._serializers);

  /// Edit fields on many items
  /// Applies the same scalar field values to many items in one atomic catalog batch (a different value per item needs per-item calls). &#x60;skipLocked&#x60; skips items with locked target fields and reports them instead of failing the batch; without it a locked item fails the whole batch with &#x60;field-locked&#x60;. Write-back failures are reported per item and never undo the catalog batch. Every edited field is locked on every edited item, so a repeat edit of the same field needs &#x60;force&#x60; or &#x60;skipLocked&#x60;. Editing a release-keying field (&#x60;album&#x60;, &#x60;album_artist&#x60;, &#x60;year&#x60;) moves the edited tracks to a new release identity, and where they land depends on coverage: a batch holding **every** member of the album renames the release in place, so the album keeps its pid along with its artwork, curation and play state, while a batch holding only **some** of them forks those onto a fresh album entity and leaves the rest behind. A rename onto a name another release already owns merges into it. &#x60;resultingAlbumPid&#x60; reports where the edited items sit either way. 
  ///
  /// Parameters:
  /// * [bulkEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BulkEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BulkEditResult>> bulkEditMetadata({ 
    required BulkEdit bulkEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/bulk-edit';
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
      const _type = FullType(BulkEdit);
      _bodyData = _serializers.serialize(bulkEdit, specifiedType: _type);

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

    BulkEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(BulkEditResult),
      ) as BulkEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BulkEditResult>(
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

  /// Clear entity artwork
  /// Removes one artwork slot (&#x60;role&#x60;, default &#x60;front&#x60;) from an album, artist, release group, genre, playlist, or podcast entity. Files already carrying an embedded cover are untouched; this clears the catalog&#39;s copy. Clearing a playlist&#39;s uploaded cover hands the slot back to the mosaic the server builds from the members, so the playlist keeps a cover rather than going bare. Clearing a podcast show&#39;s cover hands the slot back to the feed, whose image refills on the next sync - provided no pin stands: setting a cover by hand pinned it, so resetting a hand-set show cover to the feed&#39;s image is two steps, unpin through the lock endpoint and then clear. Catalog entities are administrators-only; a playlist cover is cleared by its owner, and a podcast show cover by &#x60;managePodcasts&#x60; holders as well. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [role] - Which artwork slot to clear. Defaults to `front`.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> clearEntityArtwork({ 
    required String entityType,
    required String entityPid,
    ArtRole? role,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/artwork'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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

    final _queryParameters = <String, dynamic>{
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _response;
  }

  /// Remove an item&#39;s recorded origin
  /// Takes the origin row off, so the item reads the source it has without one: its show&#39;s type for an episode, and &#x60;local&#x60; for everything else. Idempotent - an item with no row answers 204 the same way.  &#x60;lock&#x60; defaults **true** here, and it is what makes the clear stick: the row came from evidence that is still in the file, so the next full scan re-derives it. &#x60;writeBack&#x60; is the durable half, stripping those tags outright, after which the origin stays gone with no lock holding it.  A write-back that fails on some files is **not** reported: the catalog row is gone either way, and a 204 carries no body to name them in. It is logged server-side, and the tags that stayed are what a later full rescan would re-derive from - so &#x60;PUT&#x60; back with &#x60;writeBack&#x60; if the clear has to be durable and this one did not take. The &#x60;PUT&#x60; reports its own write-back failures in &#x60;MetadataEditResult&#x60;. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [writeBack] - Strip the origin tags from the item's files too.
  /// * [lock] - Lock `acquisition` so a rescan cannot re-derive the row from tags still in the file. 
  /// * [force] - Clear through a standing lock.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> clearItemAcquisition({ 
    required String pid,
    bool? writeBack = false,
    bool? lock = true,
    bool? force = false,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/acquisition'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    final _queryParameters = <String, dynamic>{
      if (writeBack != null) r'writeBack': encodeQueryParameter(_serializers, writeBack, const FullType(bool)),
      if (lock != null) r'lock': encodeQueryParameter(_serializers, lock, const FullType(bool)),
      if (force != null) r'force': encodeQueryParameter(_serializers, force, const FullType(bool)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _response;
  }

  /// Clear item artwork
  /// Removes the stored item art in one slot (&#x60;role&#x60;, default &#x60;front&#x60;). A cleared front cover falls back to the entity chain (album, release group, artist); the other slots have no fallback and simply become absent. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [role] - Which artwork slot to clear. Defaults to `front`.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> clearItemArtwork({ 
    required String pid,
    ArtRole? role,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/artwork'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    final _queryParameters = <String, dynamic>{
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return _response;
  }

  /// Clear lyrics
  /// Removes the stored lyrics (files are untouched).
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
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> clearItemLyrics({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/lyrics'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

  /// Clear a custom tag
  /// Removes the tag and its lock. A reserved key (one the catalog owns through another surface) answers &#x60;invalid-request&#x60;, like setting one does. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [key] - The custom tag key. Keys canonicalize to uppercase ASCII; keys the catalog owns through another surface (TITLE, ARTIST, the credit roles, and the rest of the reserved set) are rejected with `invalid-request`. 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future]
  /// Throws [DioException] if API call or serialization fails
  Future<Response<void>> clearItemTag({ 
    required String pid,
    required String key,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/tags/{key}'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString()).replaceAll('{' r'key' '}', encodeQueryParameter(_serializers, key, const FullType(String)).toString());
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

  /// Commit a staged metadata draft in one request
  /// Runs every staged part of one item&#39;s editor draft server-side, in the order the editor&#39;s own sequential save uses: scalar fields, then each credit role, then lyrics (or their removal), then chapters, then each tag set, then each tag removal, then the release status. It exists for latency: the sequential save is one round trip per part, which on a phone reaching a home server through a reverse proxy is felt as lag on a single Save, and every gap between the calls is a partial-failure window on a flaky link.  At least one part is required. &#x60;writeBack&#x60;, &#x60;lock&#x60; and &#x60;force&#x60; are hoisted here rather than repeated per part, and each part takes the ones its own endpoint takes: chapters and tag sets take &#x60;lock&#x60; and &#x60;force&#x60;, a tag removal, a lyrics clear and the release status take none.  **Deliberately not a transaction.** Write-back is best-effort by design, so end-to-end atomicity is unattainable, and catalog-only atomicity would need a combined-edit facade upstream. Parts run until one is refused; that part reports &#x60;refused&#x60; with its &#x60;Error&#x60;, every later part reports &#x60;skipped&#x60;, and the parts before it stay committed. That is exactly what the sequential save produces, which is the point: the two paths are interchangeable, and a client keeps the sequential one as its fallback for an older server.  So a refusal is a &#x60;200&#x60; carrying a refused part, not a &#x60;4xx&#x60;: the write-back failures the committed parts accumulated are what the editor&#39;s banner is made of, and a status code would discard them. A lock conflict that &#x60;PATCH /items/{pid}/metadata&#x60; answers &#x60;409&#x60; arrives here as a part refused with &#x60;field-locked&#x60;, worded exactly as that endpoint words it.  One exception, and it is what the status codes below are for: a failure that says the server is temporarily unwell rather than that the edit was wrong - &#x60;catalog-maintenance&#x60;, &#x60;internal&#x60;, &#x60;catalog-busy&#x60; - answers with its own status code when it happens before anything has committed. Nothing is lost by doing so, and a client answers those with a banner and a retry rather than by showing them to the person who typed the value. Once a part has committed, the same failure rides as a part refusal, because discarding that part&#39;s report is the worse trade.  Gated per item like the sequential parts: administrators, or the user whose upload brought the item in. It is not the bulk edit and does not carry that operation&#39;s admin-only gate. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [metadataCommit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataCommitResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataCommitResult>> commitItemMetadata({ 
    required String pid,
    required MetadataCommit metadataCommit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/metadata/commit'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(MetadataCommit);
      _bodyData = _serializers.serialize(metadataCommit, specifiedType: _type);

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

    MetadataCommitResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataCommitResult),
      ) as MetadataCommitResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataCommitResult>(
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

  /// Detach a track from its release
  /// Pulls one track off an album chain a MusicBrainz id pins it to - the album&#39;s own release id, or an mbid-keyed release group above it - and onto the heuristic album its own tags and folder imply. This is the per-member counterpart of clearing that id on the whole entity, which is what a mis-scanned track sitting on the wrong release needs.  Refused with &#x60;invalid-request&#x60; for an item that is not a track, one on no album, one whose chain carries no MusicBrainz id, and an album&#39;s last member - that last one has nothing to detach onto, so clear the album&#39;s &#x60;mbid&#x60; instead.  &#x60;writeBack&#x60; also strips &#x60;MUSICBRAINZ_ALBUMID&#x60; and &#x60;MUSICBRAINZ_RELEASEGROUPID&#x60; from the track&#39;s file, which is what stops the next scan adopting it back; a file that cannot be written is reported in &#x60;failures&#x60; while the detach stands. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [detachRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [DetachResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<DetachResult>> detachItem({ 
    required String pid,
    DetachRequest? detachRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/detach'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(DetachRequest);
      _bodyData = detachRequest == null ? null : _serializers.serialize(detachRequest, specifiedType: _type);

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

    DetachResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(DetachResult),
      ) as DetachResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<DetachResult>(
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

  /// Edit entity fields
  /// Edits an entity&#39;s own fields: &#x60;sort&#x60; and &#x60;mbid&#x60; for artists; &#x60;sort&#x60;, &#x60;mbid&#x60;, and &#x60;type&#x60; for release groups; &#x60;sort&#x60;, &#x60;mbid&#x60;, &#x60;barcode&#x60;, &#x60;label&#x60;, &#x60;catalog_number&#x60;, &#x60;media&#x60;, and &#x60;country&#x60; for albums. Entity edits carry their own provenance, readable below. &#x60;writeBack&#x60; pushes the values that have tag forms into member files.  &#x60;barcode&#x60; and &#x60;country&#x60; are normalized on the way in, where a scan stores the tag verbatim, so an edit refuses values &#x60;GET /albums/{pid}&#x60; will happily show (\&quot;US &amp;amp; Europe\&quot; is a country a scan can store and an edit cannot). &#x60;media&#x60; has no normalizer and is stored as typed.  Clearing an &#x60;mbid&#x60; re-keys the entity, which is the one edit that can move it: the chain falls back to the heuristic key, so the entity may merge into a twin that already held it (&#x60;mergedInto&#x60;) or, on a release group, shed differently titled albums into groups of their own (&#x60;movedAlbums&#x60;). With &#x60;writeBack&#x60; an album&#39;s or release group&#39;s &#x60;mbid&#x60; clear also strips that id from the member files, which is what stops the next scan putting the linkage back. A clear that merges is refused alongside any other field with code &#x60;conflict&#x60;, whose message names the survivor to edit instead, because the merge deletes the row those other values would be written to. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [entityEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> editEntity({ 
    required String entityType,
    required String entityPid,
    required EntityEdit entityEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
    final _options = Options(
      method: r'PATCH',
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
      const _type = FullType(EntityEdit);
      _bodyData = _serializers.serialize(entityEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Edit scalar fields
  /// Applies one or more scalar field edits atomically to the catalog. &#x60;writeBack&#x60; additionally writes the new values into the backing file&#39;s tags (refused by upstream design for episodes, virtual tracks, and files shared by several items; the edit still lands in the catalog and the response carries the per-file failures). &#x60;lock&#x60; (default true) locks each edited field against scans and enrichment; editing a field someone locked earlier requires &#x60;force&#x60; or answers &#x60;field-locked&#x60;. Unknown fields for the item&#39;s kind answer &#x60;invalid-request&#x60;. Identifier fields (ISRC, ISBN, ASIN, barcode) are format-checked here because upstream stores them unvalidated. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [metadataEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> editItemMetadata({ 
    required String pid,
    required MetadataEdit metadataEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/metadata'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
    final _options = Options(
      method: r'PATCH',
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
      const _type = FullType(MetadataEdit);
      _bodyData = _serializers.serialize(metadataEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Enrich one item now
  /// Runs the registered enrichment providers for the wanted artifacts (cover art, lyrics, genres, track fields, book metadata) against this one item synchronously and applies what they return, respecting locks and never overwriting a non-empty curated value. This is the editor&#39;s \&quot;fetch for me\&quot; button; the whole-library pass lives under &#x60;/library/enrichment&#x60;.  With a &#x60;proposal&#x60; in the body, nothing is fetched: the call commits exactly the proposal a preview returned, so what was approved is what lands - a fresh fetch could answer with a different value than the one the user saw. The proposal is validated whole before anything writes: its parts must answer the requested wants, its providers must be registered on this server, and a cover must be a storable image (decodable, at most 16 MiB) - a proposal that fails any of it is refused with nothing committed. The local guards still run at commit (a field locked or filled since the preview is skipped with the reason, never overwritten). The catalog&#39;s own key-free built-ins run fill-when-empty after the commit either way, as they do on a blind fetch: they live inside the catalog&#39;s engine and cannot propose without writing, so they are the un-previewable remainder. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [enrichItemRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [EnrichItemResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<EnrichItemResult>> enrichItem({ 
    required String pid,
    required EnrichItemRequest enrichItemRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/enrich'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(EnrichItemRequest);
      _bodyData = _serializers.serialize(enrichItemRequest, specifiedType: _type);

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

    EnrichItemResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(EnrichItemResult),
      ) as EnrichItemResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<EnrichItemResult>(
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

  /// Read an entity&#39;s artwork lock
  /// Whether one of an album, artist, release group, genre, or podcast&#39;s artwork slots is pinned against enrichment and scan re-derives. This is what explains an entity that shows no cover and refuses every attempt to give it one: the cover was cleared and the pin left standing, which says \&quot;do not refill this\&quot; rather than \&quot;this has no cover yet\&quot;. Administrators only, like every other catalog-entity curation read, except the podcast pin, which &#x60;managePodcasts&#x60; holders read too.  &#x60;locked&#x60; for an auxiliary role is the **effective** lock - the whole-artwork pin or that role&#39;s own - and &#x60;roleLocked&#x60; is the slot&#39;s own pin by itself, so the pair says which of the two set it. &#x60;ArtRoleInfo&#x60; on the artwork read carries the same pair. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [role] - Which artwork slot to read. Defaults to `front`.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ArtworkLock] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ArtworkLock>> getEntityArtworkLock({ 
    required String entityType,
    required String entityPid,
    ArtRole? role,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/artwork/lock'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ArtworkLock? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ArtworkLock),
      ) as ArtworkLock;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ArtworkLock>(
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

  /// Read entity edit provenance
  /// The entity&#39;s curated fields with source and time.
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [EntityCuration] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<EntityCuration>> getEntityCuration({ 
    required String entityType,
    required String entityPid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/curation'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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

    EntityCuration? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(EntityCuration),
      ) as EntityCuration;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<EntityCuration>(
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

  /// Read an item&#39;s full metadata
  /// Everything the editor shows for one item: the scalar fields, credits by role, lyrics presence, chapters (books), custom tags, locks and per-field provenance (who set a value: file tags, a user, enrichment, or organize), release status, file write-back health (out-of-sync and lost-value diagnostics), and whether the item is a virtual track carved from a shared file (whose edits are always database-only by upstream design). Readable by any user who can see the item; the item-scoped mutations below require &#x60;admin&#x60;, or ownership of the upload or acquisition that brought the item in, which is what &#x60;mayCurate&#x60; on the response answers - so a client can tell an editor it may save from one every save would be refused. 
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
  /// Returns a [Future] containing a [Response] with a [ItemMetadata] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ItemMetadata>> getItemMetadata({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/metadata'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    ItemMetadata? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ItemMetadata),
      ) as ItemMetadata;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ItemMetadata>(
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

  /// Read the caller&#39;s permissions on an item
  /// Whether the caller may run the item-scoped metadata mutations on this item: administrators always, everyone else exactly for the items their own uploads brought in. This is the whole &#x60;mayCurate&#x60; answer from the metadata read without the cost of the full editor document, for surfaces that only need to decide whether to show an edit door. The read does not confirm the item exists: an unknown pid answers &#x60;mayCurate: false&#x60; for a non-administrator, and &#x60;true&#x60; for an administrator, whose edits on it would answer &#x60;not-found&#x60; anyway. 
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
  /// Returns a [Future] containing a [Response] with a [ItemPermissions] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ItemPermissions>> getItemPermissions({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/permissions'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    ItemPermissions? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ItemPermissions),
      ) as ItemPermissions;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ItemPermissions>(
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

  /// Discover the editable field vocabulary
  /// The editor&#39;s form vocabulary: every editable scalar field per item kind (with which ones write back to files and which stay database-only), the credit roles per kind, and the entity edit fields per entity type. Editors build their forms from this instead of hardcoding the vocabulary, the same pattern as the smart playlist rule fields. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataFields] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataFields>> getMetadataFields({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/metadata/fields';
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

    MetadataFields? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataFields),
      ) as MetadataFields;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataFields>(
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

  /// Preview a one-item enrichment
  /// Runs the registered enrichment providers for the wanted artifacts against this one item and reports what they would change without writing anything. The answer is a proposal: pass it back on &#x60;enrichItem&#x60; to commit exactly these values. Skipped wants carry the same reasons the blind fetch reports (locked, already present, no provider, no provider hit). The catalog&#39;s key-free built-ins are absent here - they cannot be previewed - so a want this preview reports empty may still be filled by them when the apply runs. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [enrichItemRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [EnrichPreview] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<EnrichPreview>> previewEnrichItem({ 
    required String pid,
    required EnrichItemRequest enrichItemRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/enrich/preview'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(EnrichItemRequest);
      _bodyData = _serializers.serialize(enrichItemRequest, specifiedType: _type);

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

    EnrichPreview? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(EnrichPreview),
      ) as EnrichPreview;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<EnrichPreview>(
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

  /// Requeue an item for matching
  /// Rebuilds the album unit containing the item (its album siblings ride along; a unit is always matched whole) and runs the identify pipeline on it, opening a fresh pending review entry. Items marked unofficial are eligible here (an explicit rematch is the way back from that state). The entry id returns immediately; candidates fill in asynchronously and the entry updates over the event channel. 
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
  /// Returns a [Future] containing a [Response] with a [RematchResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<RematchResult>> rematchItem({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/rematch'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    RematchResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(RematchResult),
      ) as RematchResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<RematchResult>(
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

  /// Rename an entity in place
  /// Moves a whole album, release group, or artist onto a new name by rewriting the keying fields of every one of its members in one transaction. The entity row survives, so its pid, artwork, curation, stars, and enrichment marker all stay; editing the same fields through a bulk item edit would only move the members that edit covered, leaving the rest behind on the old key.  &#x60;genre&#x60;, &#x60;playlist&#x60;, and &#x60;podcast&#x60; carry no keying fields and answer &#x60;invalid-request&#x60;.  &#x60;outcome&#x60; says what happened to the identity key: &#x60;renamed&#x60; when it moved and the row stayed, &#x60;merged&#x60; when the new key was already taken and this entity folded into the incumbent named by &#x60;mergedInto&#x60;, &#x60;refreshed&#x60; when the new key equals the old one (a case-only rename).  The refusals are the cases that would otherwise split the entity silently: an empty name, a member whose keying field is locked (without &#x60;force&#x60;), an archived member with no primary file, members that would land on different keys, and a release group whose albums are titled apart. &#x60;writeBack&#x60; also writes the new values into every member file&#39;s tags, which is what makes the rename survive the next scan; a file that cannot be written is reported in &#x60;failures&#x60; while the rename stands. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [entityRename] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [EntityRenameResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<EntityRenameResult>> renameEntity({ 
    required String entityType,
    required String entityPid,
    required EntityRename entityRename,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/rename'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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
      const _type = FullType(EntityRename);
      _bodyData = _serializers.serialize(entityRename, specifiedType: _type);

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

    EntityRenameResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(EntityRenameResult),
      ) as EntityRenameResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<EntityRenameResult>(
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

  /// Replace a book&#39;s chapters
  /// Replaces an audiobook&#39;s chapter list (user chapters win over embedded ones on read). Chapters are addressed on the book timeline, ordered and non-overlapping; for a multi-file book the server splits the flat list across its parts. An empty list restores the embedded chapters. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [chaptersEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setBookChapters({ 
    required String pid,
    required ChaptersEdit chaptersEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/books/{pid}/chapters'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(ChaptersEdit);
      _bodyData = _serializers.serialize(chaptersEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Set entity artwork
  /// Stores the raw image bytes in one artwork slot (&#x60;role&#x60;, default &#x60;front&#x60;) of an album, artist, release group, genre, playlist, or podcast entity. Album front covers may additionally embed into member files with &#x60;writeBack&#x3D;true&#x60;; other slots and entity types are catalog-only. An artist portrait lands under &#x60;front&#x60; - the slot the artist screen and index tiles resolve, and the one enrichment&#39;s artist walk fills; &#x60;background&#x60; is the scenic slot, which no surface draws yet. Catalog entities are administrators-only, with two exceptions: a playlist cover is set by its owner, and replaces the cover the server generates from the members until it is cleared, and a podcast show cover is set by &#x60;managePodcasts&#x60; holders as well, replacing the feed&#39;s image until it is cleared. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [body] 
  /// * [role] - Which artwork slot to set. Defaults to `front`.
  /// * [writeBack] - Embed a front cover into member files (albums only; ignored elsewhere). 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setEntityArtwork({ 
    required String entityType,
    required String entityPid,
    required MultipartFile body,
    ArtRole? role,
    bool? writeBack = false,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/artwork'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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
      contentType: 'application/octet-stream',
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
      if (writeBack != null) r'writeBack': encodeQueryParameter(_serializers, writeBack, const FullType(bool)),
    };

    dynamic _bodyData;

    try {
      _bodyData = body.finalize();

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
          queryParameters: _queryParameters,
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
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Pin or unpin an entity&#39;s artwork
  /// Sets or clears one slot&#39;s pin without touching the image itself, which setting artwork cannot express: that always writes the image slot too, so unpinning through it would mean supplying the picture again. Unpinning here is the way out of a cover that was cleared and left pinned. Administrators only, except the podcast pin, which &#x60;managePodcasts&#x60; holders set too - the pin is what keeps a hand-set show cover from being refetched on the next feed sync, so it belongs to whoever may set the cover.  &#x60;role&#x60; decides the reach. The default &#x60;front&#x60; writes the entity&#39;s whole-artwork pin, which gates the front cover and also enrichment&#39;s fills in every other role; a named auxiliary role writes that slot&#39;s own pin alone. Unpinning one auxiliary role therefore does not lift a whole-artwork pin standing over it: the response&#39;s &#x60;locked&#x60; is the effective reading and still true, while &#x60;roleLocked&#x60; is the pin that was just cleared.  &#x60;playlist&#x60; is refused with &#x60;invalid-request&#x60;. A playlist&#39;s cover authority is its own custom/generated origin marker rather than this pin, and a pin left standing on one would make the mosaic the server builds from the members unwritable - which the read path retries on every read, forever. 
  ///
  /// Parameters:
  /// * [entityType] - The entity kind an entity operation targets. `playlist` is a WaxDeck-side entity rather than a catalog one: it carries artwork and nothing else, and its operations are owner-gated instead of administrators-only. `podcast` is a show's channel cover, whose operations accept the accounts that already curate shows: `managePodcasts` holders as well as administrators. 
  /// * [entityPid] - Entity PID (e.g. `al-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [artworkLock] 
  /// * [role] - Which artwork slot to pin. Defaults to `front`.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ArtworkLock] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ArtworkLock>> setEntityArtworkLock({ 
    required String entityType,
    required String entityPid,
    required ArtworkLock artworkLock,
    ArtRole? role,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/entities/{entityType}/{entityPid}/artwork/lock'.replaceAll('{' r'entityType' '}', encodeQueryParameter(_serializers, entityType, const FullType(String)).toString()).replaceAll('{' r'entityPid' '}', encodeQueryParameter(_serializers, entityPid, const FullType(String)).toString());
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

    final _queryParameters = <String, dynamic>{
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
    };

    dynamic _bodyData;

    try {
      const _type = FullType(ArtworkLock);
      _bodyData = _serializers.serialize(artworkLock, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
          queryParameters: _queryParameters,
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
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ArtworkLock? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ArtworkLock),
      ) as ArtworkLock;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ArtworkLock>(
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

  /// Correct an item&#39;s recorded origin
  /// Replaces the item&#39;s origin row - how and where it entered the library - and locks &#x60;acquisition&#x60; by default. It exists because the automatic recorder is merge-wise and never lowers a field: an event with an empty url leaves a standing one alone, so a wrong url, id or provider can only come off through here or through a clear.  **The editable columns are replaced as sent**: &#x60;sourceType&#x60;, &#x60;sourceId&#x60; and &#x60;provider&#x60;. An absent one is cleared, not kept, which is what makes correcting a wrong value possible at all. Two things the body cannot express are carried forward from the standing row instead of being lost - the provider version and the acquisition&#39;s stored options - and so is the acquired-at stamp when &#x60;acquiredAt&#x60; is absent.  &#x60;sourceUrl&#x60; is the exception, and has to be: the read **redacts** it (see &#x60;ItemAcquisition.sourceUrl&#x60;), so a client that echoed back what it was shown would replace a stored &#x60;?v&#x3D;XYZ&#x60; with the truncated form it could see. An absent &#x60;sourceUrl&#x60; therefore **keeps** what stands, and an explicit empty string clears it. Send it only when somebody typed one.  &#x60;writeBack&#x60; mirrors the correction into the files&#39; &#x60;SOURCE_URL&#x60;/&#x60;SOURCE_ID&#x60;/&#x60;ACQUISITION_DATE&#x60; tags, which is what makes it survive a rescan without leaning on the lock. The stamp only reaches a file when someone actually knows it: a brand-new row&#39;s acquired-at is scan time, an approximation the catalog holds honestly and a file cannot, so it is not written.  A locked origin answers &#x60;field-locked&#x60; unless &#x60;force&#x60; is set. Administrators, or the user whose upload brought the item in. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [itemAcquisitionEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setItemAcquisition({ 
    required String pid,
    required ItemAcquisitionEdit itemAcquisitionEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/acquisition'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(ItemAcquisitionEdit);
      _bodyData = _serializers.serialize(itemAcquisitionEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Set item artwork
  /// Stores the raw image bytes in one of the item&#39;s artwork slots (&#x60;role&#x60;, default &#x60;front&#x60;), locking the artifact by default. The body is the image itself, up to 16 MiB, in any format the catalog recognizes: JPEG, PNG, GIF, WebP, BMP and TIFF by decoding them, and AVIF and HEIC by their container magic. &#x60;writeBack&#x3D;true&#x60; embeds a front cover into every backing file (write-back applies to the front slot only). Existing art in the slot is replaced; the request never downgrades silently because the caller chose the image. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [body] 
  /// * [role] - Which artwork slot to set. Defaults to `front`.
  /// * [writeBack] - Also embed a front cover into the backing files.
  /// * [lock] - Lock the artwork against scans and enrichment.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setItemArtwork({ 
    required String pid,
    required MultipartFile body,
    ArtRole? role,
    bool? writeBack = false,
    bool? lock = true,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/artwork'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      contentType: 'application/octet-stream',
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      if (role != null) r'role': encodeQueryParameter(_serializers, role, const FullType(ArtRole)),
      if (writeBack != null) r'writeBack': encodeQueryParameter(_serializers, writeBack, const FullType(bool)),
      if (lock != null) r'lock': encodeQueryParameter(_serializers, lock, const FullType(bool)),
    };

    dynamic _bodyData;

    try {
      _bodyData = body.finalize();

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
          queryParameters: _queryParameters,
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
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Replace one credit role
  /// Replaces the named people for one contributor role (composer, lyricist, producer, narrator, and the rest of the per-kind role vocabulary from the fields endpoint). Names resolve to artist entities and deduplicate. An empty list clears the role. &#x60;writeBack&#x60; writes the role&#39;s tag keys where a round-trippable key exists (book translator and editor roles are database-only by upstream design; the response says so rather than failing).  An artist whose **every** credit in the library this call moves is **renamed in place**, keeping its pid along with its artwork, curation and stars, rather than being left behind while a fresh artist takes the credit. Naming several people renames onto the first of them and forks the rest onto new artists; a first name already taken by another artist merges the old one into it instead. An artist with credits this call does not touch is not renamed - the credit simply moves. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [creditsEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setItemCredits({ 
    required String pid,
    required CreditsEdit creditsEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/credits'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(CreditsEdit);
      _bodyData = _serializers.serialize(creditsEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Lock or unlock fields
  /// Locks or unlocks the named fields against scans, enrichment, and organize. Field names are the scalar vocabulary plus the namespaced artifacts: &#x60;lyrics&#x60;, &#x60;chapters&#x60;, &#x60;art&#x60;, &#x60;art.ROLE&#x60;, &#x60;acquisition&#x60;, &#x60;credit.ROLE&#x60;, and &#x60;tag.KEY&#x60;.  The two artwork spellings differ in reach. &#x60;art&#x60; is the whole pin: it gates the front cover and also enrichment&#39;s fills in every other role. &#x60;art.ROLE&#x60; (&#x60;art.back&#x60;, &#x60;art.disc&#x60;, &#x60;art.booklet&#x60;, &#x60;art.background&#x60;) gates that one slot, so a hand-set booklet scan can be held while the rest stay open. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [locksEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [LocksResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<LocksResult>> setItemLocks({ 
    required String pid,
    required LocksEdit locksEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/locks'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(LocksEdit);
      _bodyData = _serializers.serialize(locksEdit, specifiedType: _type);

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

    LocksResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(LocksResult),
      ) as LocksResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<LocksResult>(
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

  /// Set lyrics
  /// Stores synced lines (LRC text) and/or a plain unsynchronized block for a track, locking the lyrics artifact by default. &#x60;writeBack&#x60; also writes the &#x60;.lrc&#x60; sidecar next to the file (crash-safe write) and embeds where the format allows; the response surfaces typed drop warnings from the tag library (MP4 and Matroska refuse embedded synced lyrics, so only the sidecar carries them there) instead of silently losing content. Malformed LRC lines are reported with their line numbers. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [lyricsEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setItemLyrics({ 
    required String pid,
    required LyricsEdit lyricsEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/lyrics'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(LyricsEdit);
      _bodyData = _serializers.serialize(lyricsEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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

  /// Set a custom tag
  /// Replaces the ordered values of one custom tag on a track or book, locking &#x60;tag.KEY&#x60; by default. Custom tags are full browse dimensions: they filter, facet, and feed smart list rules. An empty value list clears the tag. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [key] - The custom tag key. Keys canonicalize to uppercase ASCII; keys the catalog owns through another surface (TITLE, ARTIST, the credit roles, and the rest of the reserved set) are rejected with `invalid-request`. 
  /// * [tagEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [TagEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<TagEditResult>> setItemTag({ 
    required String pid,
    required String key,
    required TagEdit tagEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/tags/{key}'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString()).replaceAll('{' r'key' '}', encodeQueryParameter(_serializers, key, const FullType(String)).toString());
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
      const _type = FullType(TagEdit);
      _bodyData = _serializers.serialize(tagEdit, specifiedType: _type);

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

    TagEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(TagEditResult),
      ) as TagEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<TagEditResult>(
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

  /// Mark content unofficial
  /// Marks an item as having no canonical release (YouTube rips, remixes, live sets, personal recordings) or clears the mark. Marking sets a locked &#x60;RELEASESTATUS&#x60; custom tag of &#x60;unofficial&#x60;, which excludes the item from match retries and health penalties; the state is first-class, browsable, and fully hand-editable, never an error condition. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [releaseStatusEdit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [MetadataEditResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<MetadataEditResult>> setReleaseStatus({ 
    required String pid,
    required ReleaseStatusEdit releaseStatusEdit,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/release-status'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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
      const _type = FullType(ReleaseStatusEdit);
      _bodyData = _serializers.serialize(releaseStatusEdit, specifiedType: _type);

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

    MetadataEditResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(MetadataEditResult),
      ) as MetadataEditResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<MetadataEditResult>(
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
