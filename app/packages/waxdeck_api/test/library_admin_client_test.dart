import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

/// Answers every request with [status] and [body], and records it.
class _Recording implements HttpClientAdapter {
  _Recording(this.status, this.body);

  final int status;
  final Object? body;
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

WaxDeckClient _client(_Recording adapter) => WaxDeckClient(
  baseUrl: 'http://host:4420',
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  test('a library says whether it is configured, reachable and writable', () {
    LibraryInfo listed(Map<String, Object?> json) => libraryInfoFromGen(
      gen.standardSerializers.deserializeWith(gen.ModelLibrary.serializer, {
        'pid': 'lb-1',
        'name': 'music',
        'readOnly': false,
        'managed': true,
        ...json,
      })!,
    );
    final flagged = listed({
      'configured': true,
      'unreachable': true,
      'writable': false,
    });
    expect(flagged.configured, isTrue);
    expect(flagged.unreachable, isTrue);
    expect(flagged.writable, isFalse);
    final plain = listed({});
    expect(plain.configured, isFalse);
    expect(plain.unreachable, isFalse);
    expect(plain.writable, isNull);
  });

  test('a folder mounted later reaches the create', () async {
    final adapter = _Recording(201, <String, Object?>{
      'pid': 'lb-2',
      'name': 'later',
      'readOnly': false,
      'managed': false,
      'path': '/srv/later',
    });
    final created = await _client(
      adapter,
    ).createLibrary(name: 'later', path: '/srv/later', allowAbsent: true);
    expect(created.pid, 'lb-2');
    final sent = adapter.requests.single.data;
    expect((sent is String ? jsonDecode(sent) : sent)['allowAbsent'], isTrue);
  });

  test('a removal deletes the library and answers its job', () async {
    final adapter = _Recording(202, <String, Object?>{
      'pid': 'jb-1',
      'kind': 'remove-root',
      'state': 'running',
      'target': <String, Object?>{'type': 'library', 'pid': 'lb-2'},
    });
    final job = await _client(adapter).removeLibrary('lb-2');
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.uri.path, endsWith('/libraries/lb-2'));
    expect(job.kind, 'remove-root');
    expect(job.target?.pid, 'lb-2');
  });
}
