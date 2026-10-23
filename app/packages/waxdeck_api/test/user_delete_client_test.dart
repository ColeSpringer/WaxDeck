import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Records each request and answers it with an empty 204.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = _RecordingAdapter();
    client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
  });

  test(
    'a deletion hands the shared playlists over unless told otherwise',
    () async {
      await client.deleteUser('us-01JZX5N8QW3F4V9T2B7KDEXAMPLE');

      final request = adapter.requests.single;
      expect(request.method, 'DELETE');
      expect(
        request.uri.path,
        endsWith('/users/us-01JZX5N8QW3F4V9T2B7KDEXAMPLE'),
      );
      expect(request.uri.queryParameters['playlists'], 'transfer');
    },
  );

  test('a deletion can delete the playlists instead', () async {
    await client.deleteUser(
      'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      playlists: 'delete',
    );

    expect(adapter.requests.single.uri.queryParameters['playlists'], 'delete');
  });
}
