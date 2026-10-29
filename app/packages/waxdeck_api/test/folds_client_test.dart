import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers every request with [body] under [status] and records it.
class _AnsweringAdapter implements HttpClientAdapter {
  _AnsweringAdapter(this.body, {this.status = 200});

  final Object? body;
  final int status;
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

WaxDeckClient _client(_AnsweringAdapter adapter) => WaxDeckClient(
  baseUrl: 'http://host:4420',
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  test('a merge names the keys it folded', () async {
    final adapter = _AnsweringAdapter({
      'merged': 1,
      'childrenMoved': 2,
      'folds': ['the beatles'],
    });
    final outcome = await _client(adapter).mergeDuplicates(
      entityType: 'artist',
      survivorPid: 'ar-1',
      loserPids: const ['ar-2'],
    );
    expect(outcome.merged, 1);
    expect(outcome.folds, ['the beatles']);
  });

  test('a folds page is asked from its cursor and maps each fold', () async {
    final adapter = _AnsweringAdapter({
      'folds': [
        {
          'entityType': 'release-group',
          'key': 'rg:joni\u001fblue',
          'spelling': 'joni - blue',
          'entityPid': 'rg-01JZX5N8QW3F4V9T2B7KDEXAMPL',
          'entityName': 'Blue',
          'createdAt': '2026-10-01T12:00:00Z',
        },
        {
          'entityType': 'album',
          'key': 'al:rg:joni\u001fblue\u001f\u001f\u001fsrv music blue again',
          'spelling': 'joni - blue',
          'folder': 'Joni/Blue Again',
          'library': 'Music',
          'entityPid': 'al-01JZX5N8QW3F4V9T2B7KDEXAMPL',
          'entityName': 'Blue',
          'createdAt': '2026-10-01T12:00:00Z',
        },
        {
          'entityType': 'genre',
          'key': 'mood:chill',
          'spelling': 'chill',
          'facet': 'mood',
          'entityPid': '01JZX5N8QW3F4V9T2B7KDEXAMPL',
          'entityName': 'Chill',
          'createdAt': '2026-10-01T12:00:00Z',
        },
      ],
      'nextCursor': 'c2',
    });
    final page = await _client(
      adapter,
    ).listEntityFolds(cursor: 'c1', limit: 50);
    final query = adapter.requests.single.uri.queryParameters;
    expect(adapter.requests.single.uri.path, endsWith('/library/folds'));
    expect(query['cursor'], 'c1');
    expect(query['limit'], '50');
    expect(page.folds, hasLength(3));
    final fold = page.folds.first;
    expect(fold.entityType, 'release-group');
    expect(fold.facet, isNull);
    expect(fold.folder, isNull);
    expect(fold.library, isNull);
    final album = page.folds[1];
    expect(album.folder, 'Joni/Blue Again');
    expect(album.library, 'Music');
    expect(page.folds[2].facet, 'mood');
    expect(fold.key, 'rg:joni\u001fblue');
    expect(fold.spelling, 'joni - blue');
    expect(fold.entityPid, 'rg-01JZX5N8QW3F4V9T2B7KDEXAMPL');
    expect(fold.entityName, 'Blue');
    expect(fold.createdAt, DateTime.utc(2026, 10, 1, 12));
    expect(page.nextCursor, 'c2');
    expect(page.hasMore, isTrue);
  });

  test('an unfold posts the type and the keys as listed', () async {
    final adapter = _AnsweringAdapter(null, status: 204);
    await _client(adapter).unfoldEntities(
      entityType: 'release-group',
      keys: const ['rg:joni\u001fblue'],
    );
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/library/folds/unfold'));
    final sent = jsonDecode(jsonEncode(request.data)) as Map<String, Object?>;
    expect(sent['entityType'], 'release-group');
    expect(sent['keys'], ['rg:joni\u001fblue']);
  });

  test('an unfold of a key no fold holds is a not-found', () async {
    final adapter = _AnsweringAdapter({
      'code': 'not-found',
      'message': 'no artist fold of "x"',
    }, status: 404);
    await expectLater(
      _client(adapter).unfoldEntities(entityType: 'artist', keys: const ['x']),
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.code, 'code', 'not-found'),
      ),
    );
  });
}
