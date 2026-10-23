import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers each request with the next canned body and records it.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<(int, Object)> _canned = [];

  void enqueue(int status, Object body) => _canned.add((status, body));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = _canned.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
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

  test('a clear-finished sweep names its own scope by default', () async {
    adapter.enqueue(200, {'deleted': 3, 'kept': 0});

    final cleared = await client.clearFinishedToolTasks();

    expect(cleared.deleted, 3);
    expect(cleared.kept, 0);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/tools/tasks/clear-finished'));
    expect(request.data, {'scope': 'mine'});
  });

  test('everyone\'s sweep names the wide scope, and what it kept', () async {
    adapter.enqueue(200, {'deleted': 7, 'kept': 1});

    final cleared = await client.clearFinishedToolTasks(all: true);

    expect(cleared.deleted, 7);
    expect(cleared.kept, 1);
    expect(adapter.requests.single.data, {'scope': 'all'});
  });

  test('a member\'s wide sweep is refused as forbidden', () async {
    adapter.enqueue(403, {
      'code': 'forbidden',
      'message': 'administrators only',
    });

    await expectLater(
      client.clearFinishedToolTasks(all: true),
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.code, 'code', 'forbidden'),
      ),
    );
  });
}
