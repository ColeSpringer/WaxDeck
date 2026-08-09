//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'dart:typed_data';
import 'package:waxdeck_api_gen/src/api_util.dart';
import 'package:waxdeck_api_gen/src/model/album_detail.dart';
import 'package:waxdeck_api_gen/src/model/art_role.dart';
import 'package:waxdeck_api_gen/src/model/art_roles.dart';
import 'package:waxdeck_api_gen/src/model/delete_items_request.dart';
import 'package:waxdeck_api_gen/src/model/delete_items_result.dart';
import 'package:waxdeck_api_gen/src/model/discovery_list.dart';
import 'package:waxdeck_api_gen/src/model/entity_card_list.dart';
import 'package:waxdeck_api_gen/src/model/entity_card_query.dart';
import 'package:waxdeck_api_gen/src/model/error.dart';
import 'package:waxdeck_api_gen/src/model/facet_page.dart';
import 'package:waxdeck_api_gen/src/model/facet_sort.dart';
import 'package:waxdeck_api_gen/src/model/item.dart';
import 'package:waxdeck_api_gen/src/model/item_page.dart';
import 'package:waxdeck_api_gen/src/model/lyrics.dart';
import 'package:waxdeck_api_gen/src/model/media_type.dart';
import 'package:waxdeck_api_gen/src/model/search_results.dart';

class LibraryApi {

  final Dio _dio;

  final Serializers _serializers;

  const LibraryApi(this._dio, this._serializers);

  /// Browse a discovery list
  /// Keyset-paginated discovery lists over the whole library: newest, recently added, most played, recently played, random, starred, alphabetical, never played, and rediscover. Play-derived lists reflect the calling user&#39;s own listening state. Most lists span every media type. &#x60;newest&#x60; does not: it orders by release year, which a podcast episode has not got, so it covers music and audiobooks only. Pairing it with &#x60;mediaType&#x3D;podcast&#x60;, or drilling its &#x60;kind&#x60; dimension to &#x60;episode&#x60;, is &#x60;invalid-request&#x60; rather than an empty page that would read as \&quot;your library holds none\&quot;. Episodes ordered by publication date live on &#x60;/podcasts/episodes&#x60;. 
  ///
  /// Parameters:
  /// * [list] - Which discovery list to page through.
  /// * [mediaType] - Restrict the list to one media type, for a domain-scoped shelf (\"recently added albums\" on the music hub). Composes with every list, and narrows the list itself rather than the page, so a filtered page comes back full. A caller with restricted library visibility can still get a short page that carries a cursor, which is the contract's standing rule everywhere. 
  /// * [facet] - Restrict the list to one bucket of a browse dimension, taking the same dimension names `/library/facets` enumerates and the same bucket keys `/library/items` drills. Composes with `mediaType` and with every list, so a shuffle can be scoped to one artist, genre, or year, and it is the same filter the bucket's own listing uses: a bucket's count, the list it opens, and a shuffle over it can never disagree. Keyed on `facet` alone, exactly as on `/library/items`: an absent or empty `facetKey` selects the dimension's unknown bucket. 
  /// * [facetKey] - The bucket to scope to, as returned in the enumeration's `key`. Send it empty to select the dimension's unknown bucket; `kind` and custom tag dimensions have no unknown bucket and reject an empty key. Ignored without `facet`. 
  /// * [seed] - Shuffle seed for the `random` list. The same seed pages through the same shuffled order, so paging stays stable. When omitted the server picks a fresh seed and returns it as the page's `seed`; pass that value back with the cursor for later pages. 
  /// * [cursor] - Opaque keyset cursor from a previous page's `nextCursor`. Omit for the first page. A cursor carries the scope it was issued under - the list, the seed, and the `mediaType`/`facet`/`facetKey` filter - and reusing one under a different scope is `invalid-request`. It names a position in a seeded permutation, so under another seed it would name a position in a different permutation entirely; refusing it is the only honest answer. 
  /// * [limit] - Maximum items per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ItemPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ItemPage>> browseList({ 
    required DiscoveryList list,
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    int? seed,
    String? cursor,
    int? limit = 100,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/browse';
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
      r'list': encodeQueryParameter(_serializers, list, const FullType(DiscoveryList)),
      if (mediaType != null) r'mediaType': encodeQueryParameter(_serializers, mediaType, const FullType(MediaType)),
      if (facet != null) r'facet': encodeQueryParameter(_serializers, facet, const FullType(String)),
      if (facetKey != null) r'facetKey': encodeQueryParameter(_serializers, facetKey, const FullType(String)),
      if (seed != null) r'seed': encodeQueryParameter(_serializers, seed, const FullType(int)),
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

    ItemPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ItemPage),
      ) as ItemPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ItemPage>(
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

  /// Delete library items
  /// Deletes items&#39; files, to the catalog trash by default (reversible from the trash surface) or permanently (&#x60;mode&#x60; &#x60;permanent&#x60;, administrators only). &#x60;dryRun&#x60; answers the plan (which files, how many bytes) without deleting, and the response reports the same entries when it applies. Deleting needs the &#x60;delete&#x60; permission or the admin role, and every pid must be visible to the caller (&#x60;not-found&#x60; otherwise). Items keep their catalog identity: an item that loses its last file is archived, not erased, and play history survives. A read-only library answers &#x60;read-only&#x60;. 
  ///
  /// Parameters:
  /// * [deleteItemsRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [DeleteItemsResult] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<DeleteItemsResult>> deleteLibraryItems({ 
    required DeleteItemsRequest deleteItemsRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/items/delete';
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
      const _type = FullType(DeleteItemsRequest);
      _bodyData = _serializers.serialize(deleteItemsRequest, specifiedType: _type);

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

    DeleteItemsResult? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(DeleteItemsResult),
      ) as DeleteItemsResult;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<DeleteItemsResult>(
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

  /// Get one album&#39;s identity
  /// The release facts that belong to the album entity rather than to any of its tracks: barcode, label, catalog number, media, and country, beside the title and counts a header already derives.  These live on the entity because that is where the catalog keeps them - an item row carries what the file is, and an edition is what the release is - so a screen deriving an album from its tracks can reach the first set and not the second. This is the read half of the &#x60;editEntity&#x60; write surface.  The &#x60;pid&#x60; must be an album (&#x60;al-&#x60;); anything else is &#x60;not-found&#x60; rather than a wrong-shaped answer. Absent fields are omitted: most releases carry none of the five, and an album with nothing to say answers the identity fields empty rather than blank. 
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
  /// Returns a [Future] containing a [Response] with a [AlbumDetail] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AlbumDetail>> getAlbum({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/albums/{pid}'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    AlbumDetail? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AlbumDetail),
      ) as AlbumDetail;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AlbumDetail>(
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

  /// Get one item&#39;s detail
  /// Full detail for a single library item.
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
  /// Returns a [Future] containing a [Response] with a [Item] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Item>> getItem({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    Item? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(Item),
      ) as Item;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Item>(
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

  /// Get artwork
  /// Artwork as image bytes: the original at full size, or a square-fit thumbnail when &#x60;size&#x60; is given. Besides item PIDs this endpoint also accepts album (&#x60;al-&#x60;), artist (&#x60;ar-&#x60;), podcast show (&#x60;pc-&#x60;), and playlist (&#x60;pl-&#x60;) PIDs, so search hits, subscription lists, and playlist grids can render artwork directly. A playlist answers its own cover, whether the owner uploaded one or the server built it from the members, and follows the same visibility rule as every other playlist read. Items without any artwork in their fallback chain return 404. Responses carry a content-addressed &#x60;ETag&#x60;; revalidate with &#x60;If-None-Match&#x60; instead of refetching.  Responses are cacheable for a day and reusable while revalidating for a week (&#x60;Cache-Control&#x60;), so a warm grid paints from the cache instead of spending a conditional GET per cover. The bytes are per-caller (artwork follows the item&#39;s visibility), so the directive is &#x60;private&#x60; and the response varies by the credential presented (&#x60;Cookie&#x60; or &#x60;Authorization&#x60;): a browser shared by two accounts must not answer one from the other&#39;s cache.  A URL names a PID and a size, not the bytes behind them, so a client that replaces an entity&#39;s artwork has to defeat its own caches: vary &#x60;v&#x60; to do it. 
  ///
  /// Parameters:
  /// * [pid] - Type-prefixed PID (e.g. `tr-01JZX5N8QW3F4V9T2B7KD3M9R6`).
  /// * [role] - Which artwork slot to read. Only `front` (the default) walks the album/artist fallback chain; `back`, `disc`, `booklet`, and `background` resolve at the requested entity's own level and 404 when that entity holds no image in the slot. 
  /// * [size] - Longest-edge bound in pixels for a thumbnail. Omit for the original image. 
  /// * [v] - Opaque cache-buster, ignored by the server. Artwork lives at one URL whatever it holds, and this response is cacheable for a day, so a client that has just replaced an entity's cover would otherwise keep painting the old bytes out of its own cache. Varying this asks for the same image under a name no cache has seen. 
  /// * [ifNoneMatch] - Previously returned `ETag`; a match answers 304 with no body.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [Uint8List] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Uint8List>> getItemArt({ 
    required String pid,
    ArtRole? role,
    int? size,
    String? v,
    String? ifNoneMatch,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/art'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
    final _options = Options(
      method: r'GET',
      responseType: ResponseType.bytes,
      headers: <String, dynamic>{
        if (ifNoneMatch != null) r'If-None-Match': ifNoneMatch,
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
      if (size != null) r'size': encodeQueryParameter(_serializers, size, const FullType(int)),
      if (v != null) r'v': encodeQueryParameter(_serializers, v, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    Uint8List? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as Uint8List;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Uint8List>(
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

  /// List the artwork slots an entity holds
  /// The artwork slots present at the entity&#39;s own level, not inherited from the album or artist chain, each with its stored format and pixel dimensions (0 when the image was not decodable). Besides item PIDs this accepts album (&#x60;al-&#x60;), artist (&#x60;ar-&#x60;), podcast show (&#x60;pc-&#x60;), and playlist (&#x60;pl-&#x60;) PIDs. It answers the own-versus-inherited question a front-cover read cannot: an item that lists a &#x60;front&#x60; slot here holds its own cover, while one that resolves art only through &#x60;/items/{pid}/art&#x60; inherits it from the chain. 
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
  /// Returns a [Future] containing a [Response] with a [ArtRoles] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ArtRoles>> getItemArtRoles({ 
    required String pid,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/items/{pid}/art-roles'.replaceAll('{' r'pid' '}', encodeQueryParameter(_serializers, pid, const FullType(String)).toString());
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

    ArtRoles? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ArtRoles),
      ) as ArtRoles;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ArtRoles>(
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

  /// Get an item&#39;s lyrics
  /// Lyrics for the item: synced lines when available, an unsynced text block otherwise. 404 when the item has no lyrics at all. 
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
  /// Returns a [Future] containing a [Response] with a [Lyrics] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<Lyrics>> getItemLyrics({ 
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

    Lyrics? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(Lyrics),
      ) as Lyrics;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<Lyrics>(
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

  /// Enumerate a browse dimension
  /// Keyset-paginated buckets of one browse dimension, each with the number of matching items: the \&quot;all genres\&quot; and \&quot;all artists\&quot; lists a browse index is built from. Buckets come biggest first by default, ties broken by label, so the list leads with what is worth opening and paging stays stable; &#x60;sort&#x3D;label&#x60; orders them A to Z instead, for an index with an alphabet rail. Drill a bucket by passing its &#x60;key&#x60; back as &#x60;listItems&#x60;&#39; &#x60;facetKey&#x60; together with the same &#x60;facet&#x60;. A cursor is only valid for the &#x60;sort&#x60; and the scope it was issued under: the two orders interleave differently, so resuming one from the other&#39;s boundary would skip or repeat buckets, and a scope change is a different bucket list entirely. Sending a mismatched pair is &#x60;invalid-request&#x60; rather than a silently wrong page. The &#x60;genre&#x60;, &#x60;artist&#x60;, &#x60;credit-artist&#x60;, &#x60;album-artist&#x60;, &#x60;album&#x60;, &#x60;release-group&#x60;, and &#x60;year&#x60; dimensions each carry a bucket for the items the dimension is absent from (&#x60;[No Genre]&#x60;, &#x60;[Unknown Artist]&#x60;, &#x60;[Non-Album]&#x60;, &#x60;[No Release Group]&#x60;, &#x60;[Unknown Year]&#x60;), with an empty &#x60;key&#x60; and &#x60;unknown&#x60; true. &#x60;[No Release Group]&#x60; is not &#x60;[Non-Album]&#x60;: a track on an album whose release group is unresolved is in the first and not the second. &#x60;genre&#x60; and &#x60;credit-artist&#x60; are the two many-per-item dimensions: an item contributes a count to every bucket it belongs to, so their bucket counts sum to more than the number of items. Every other dimension buckets an item exactly once. &#x60;kind&#x60; has none, because an item&#39;s kind is never absent, and a custom tag dimension has none, because only items carrying the key contribute at all; on those two, drilling an empty &#x60;facetKey&#x60; is &#x60;invalid-request&#x60; rather than an empty page. Podcast episodes are excluded from the music dimensions, which they have no artist, album, genre, or year for; the &#x60;kind&#x60; dimension counts them. Counts are scoped to the libraries the caller may see. The per-item rules the drill list also applies (podcast subscriptions, content rules) are per-item decisions no aggregation can express, so a bucket can read higher than the list it opens, the same way any restricted listing can return a short page. 
  ///
  /// Parameters:
  /// * [dimension] - Which browse dimension to enumerate.
  /// * [facet] - Restrict the enumeration to one bucket of a *second* browse dimension, taking the same dimension names this endpoint enumerates. The albums an artist is credited on are `dimension=album` scoped by `facet=credit-artist`: album buckets, counted over that artist's items only.  The pair is keyed on `facet` alone: an absent or empty `facetKey` selects the scope dimension's unknown bucket, exactly as it does on `/library/items`. Scoping by the dimension being enumerated is `invalid-request` - it would answer the one bucket it was given.  A scoped enumeration is computed per request rather than served from the enumeration cache, since the scopes are per-entity and unbounded; it is bounded instead by the scope, which is what makes it cheap. 
  /// * [facetKey] - The scope bucket, as returned in that dimension's `key`. Send it empty to scope to the dimension's unknown bucket; `kind` and custom tag dimensions have no unknown bucket and reject an empty key. Ignored without `facet`. 
  /// * [sort] - Bucket order. `count` (the default) is biggest first, ties broken by label then key. `label` is A to Z by the bucket's display label, ties broken by key; the unknown bucket sorts last under it, since a sentinel has no place in an alphabet. 
  /// * [cursor] - Opaque cursor from a previous page's `nextCursor`. Omit for the first page. Valid only with the `sort` it was issued under. 
  /// * [startsAt] - Start the page at the first bucket whose display label sorts at or after this prefix, folded the same way `sort=label` folds (case, and leading whitespace ignored). This is what an alphabet rail taps: `startsAt=m` on a library that jumps from L to N answers the first N bucket rather than nothing, since the comparison is at-or-after and not equality. Requires `sort=label`; with the default `count` order it is `invalid-request`, because a prefix names no position in a biggest-first list. Sending it together with `cursor` is `invalid-request` too: a cursor already names a position. A prefix past the last bucket is an empty page with no `nextCursor`, not an error. The unknown bucket is not seekable, since it sorts last whatever its sentinel spells; paging to the end still reaches it. 
  /// * [limit] - Maximum buckets per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [FacetPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<FacetPage>> listFacets({ 
    required String dimension,
    String? facet,
    String? facetKey,
    FacetSort? sort,
    String? cursor,
    String? startsAt,
    int? limit = 100,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/facets';
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
      r'dimension': encodeQueryParameter(_serializers, dimension, const FullType(String)),
      if (facet != null) r'facet': encodeQueryParameter(_serializers, facet, const FullType(String)),
      if (facetKey != null) r'facetKey': encodeQueryParameter(_serializers, facetKey, const FullType(String)),
      if (sort != null) r'sort': encodeQueryParameter(_serializers, sort, const FullType(FacetSort)),
      if (cursor != null) r'cursor': encodeQueryParameter(_serializers, cursor, const FullType(String)),
      if (startsAt != null) r'startsAt': encodeQueryParameter(_serializers, startsAt, const FullType(String)),
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

    FacetPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(FacetPage),
      ) as FacetPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<FacetPage>(
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

  /// Browse library items
  /// Keyset-paginated list of library items, optionally filtered by media type and by one bucket of a browse dimension. Ordering is stable (title, then pid) so cursors never skip or duplicate. 
  ///
  /// Parameters:
  /// * [mediaType] - Restrict results to one media type.
  /// * [facet] - Restrict results to one bucket of a browse dimension, taking the same dimension names `/library/facets` enumerates. Composes with `mediaType`. The pair is keyed on `facet` alone: an absent or empty `facetKey` selects the dimension's unknown bucket, which is a real bucket the enumeration returns, so it is a drill rather than a missing argument. 
  /// * [facetKey] - The bucket to drill, as returned in the enumeration's `key`. Send it empty to select the dimension's unknown bucket (the items the dimension is absent from, such as `[Non-Album]`); `kind` and custom tag dimensions have no unknown bucket and reject an empty key. Ignored without `facet`. 
  /// * [cursor] - Opaque keyset cursor from a previous page's `nextCursor`. Omit for the first page. A cursor carries the scope it was issued under, so reusing one with a changed `mediaType` or `facet` is `invalid-request` rather than a quietly wrong window. 
  /// * [limit] - Maximum items per page.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ItemPage] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ItemPage>> listItems({ 
    MediaType? mediaType,
    String? facet,
    String? facetKey,
    String? cursor,
    int? limit = 100,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/items';
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
      if (mediaType != null) r'mediaType': encodeQueryParameter(_serializers, mediaType, const FullType(MediaType)),
      if (facet != null) r'facet': encodeQueryParameter(_serializers, facet, const FullType(String)),
      if (facetKey != null) r'facetKey': encodeQueryParameter(_serializers, facetKey, const FullType(String)),
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

    ItemPage? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ItemPage),
      ) as ItemPage;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ItemPage>(
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

  /// Resolve a list of entity PIDs to cards
  /// Batch read of the display facts behind a list of entity PIDs: what a shelf needs to draw a card for something a client holds only a handle for. A POST because the PID list rides the body (as &#x60;/play-states&#x60;); nothing changes server-side.  Albums (&#x60;al-&#x60;), artists (&#x60;ar-&#x60;), release groups (&#x60;rg-&#x60;), playlists (&#x60;pl-&#x60;), podcast shows (&#x60;pc-&#x60;), and books (&#x60;bk-&#x60;) may be asked for, in any mix. A book is an item and the rest are entities; the response flattens that difference, because a card does not have one.  Answers are in request order, and that is the contract rather than an implementation detail: the caller&#39;s list is already ordered (a pinned shelf), so preserving it here is what keeps the shelf from reshuffling under a thumb.  PIDs the caller cannot be answered for are silently omitted rather than erroring: unknown, deleted, merged away, or in a library outside the caller&#39;s grant all leave the list one card shorter, which is what &#x60;Prefs.pinned&#x60; describes for a departed entity. A response shorter than the request is normal, and an empty request is an empty response.  Of the omissions, &#x60;departed&#x60; names the subset that is gone for everyone - deleted, merged away, or never real - as opposed to merely out of this caller&#39;s sight today (a grant, a lapsed subscription, the trash), which stays an unnamed omission. A client holding a pinned list may prune exactly the departed pids; pruning an unnamed omission would turn a state that can end into a loss that cannot. 
  ///
  /// Parameters:
  /// * [entityCardQuery] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [EntityCardList] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<EntityCardList>> resolveEntities({ 
    required EntityCardQuery entityCardQuery,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/entities';
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
      const _type = FullType(EntityCardQuery);
      _bodyData = _serializers.serialize(entityCardQuery, specifiedType: _type);

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

    EntityCardList? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(EntityCardList),
      ) as EntityCardList;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<EntityCardList>(
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

  /// Search the library
  /// Full-text search across artists, albums, tracks, books, and episodes. Results are grouped by kind and ranked within each group; each group is capped at &#x60;limit&#x60; hits. 
  ///
  /// Parameters:
  /// * [q] - Search query. Must contain at least one non-whitespace character.
  /// * [limit] - Maximum hits per result group.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SearchResults] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SearchResults>> search({ 
    required String q,
    int? limit = 20,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/library/search';
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
      r'q': encodeQueryParameter(_serializers, q, const FullType(String)),
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

    SearchResults? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SearchResults),
      ) as SearchResults;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SearchResults>(
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
