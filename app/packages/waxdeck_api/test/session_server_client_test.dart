import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers each request with the next canned body.
class _CannedAdapter implements HttpClientAdapter {
  final List<Object> _bodies = [];

  void enqueue(Object body) => _bodies.add(body);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(_bodies.removeAt(0)),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

const _user = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'listener',
  'roles': ['user'],
  'uploadEnabled': false,
};

void main() {
  late _CannedAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = _CannedAdapter();
    client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
  });

  test('a session carries the server\'s read-only state', () async {
    adapter.enqueue({
      'authenticated': true,
      'user': _user,
      'csrfToken': 'csrf-1',
      'server': {'readOnly': true},
    });
    expect((await client.getSession()).serverReadOnly, isTrue);

    adapter.enqueue({
      'authenticated': true,
      'user': _user,
      'csrfToken': 'csrf-1',
      'server': {'readOnly': false},
    });
    expect((await client.getSession()).serverReadOnly, isFalse);
  });

  test('a server that says nothing is not read-only', () async {
    // The `server` object is optional and a signed-out probe carries none.
    adapter.enqueue({'authenticated': true, 'user': _user});
    expect((await client.getSession()).serverReadOnly, isFalse);

    adapter.enqueue({'authenticated': false});
    expect((await client.getSession()).serverReadOnly, isFalse);
  });
}
