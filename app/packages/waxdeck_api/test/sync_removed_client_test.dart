import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Records each request and answers every one with the same status and
/// JSON body.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Map<String, Object?> body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

WaxDeckClient _client(_Adapter adapter) => WaxDeckClient(
  baseUrl: 'http://host:4420',
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  test('the pids ride the body and the named ones come back', () async {
    final adapter = _Adapter(200, {
      'pids': ['bk-B'],
    });

    final removed = await _client(
      adapter,
    ).syncCatalogRemoved(['tr-A', 'bk-B', 'ep-C']);

    expect(removed, ['bk-B']);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/sync/catalog/removed'));
    expect(request.data, {
      'pids': ['tr-A', 'bk-B', 'ep-C'],
    });
  });

  test('nothing named is an empty list', () async {
    final removed = await _client(
      _Adapter(200, {'pids': <String>[]}),
    ).syncCatalogRemoved(['tr-A']);

    expect(removed, isEmpty);
  });

  test('a refusal is the structured error, whoever the server is', () async {
    final adapter = _Adapter(503, {
      'code': 'catalog-maintenance',
      'message': 'the catalog is busy',
    });

    await expectLater(
      _client(adapter).syncCatalogRemoved(['tr-A']),
      throwsA(
        isA<WaxDeckApiException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.code, 'code', 'catalog-maintenance'),
      ),
    );
  });
}
