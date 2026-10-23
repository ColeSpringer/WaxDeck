import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;
import 'package:waxdeck_api/src/mapping.dart';

/// Answers every request with 204 and records it.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(null), 204);
  }

  @override
  void close({bool force = false}) {}
}

/// Answers every request with [body] and records it.
class _AnsweringAdapter implements HttpClientAdapter {
  _AnsweringAdapter(this.body);

  final Object body;
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
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a profile name reaches the path whole', () async {
    final adapter = _RecordingAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await client.deleteOrganizeProfile('C# layout?');
    final uri = adapter.requests.single.uri;
    expect(uri.pathSegments.last, 'C# layout?');
    expect(uri.hasFragment, isFalse);
    expect(uri.hasQuery, isFalse);
  });

  test('a playlist removal sends the item the caller saw', () async {
    final adapter = _RecordingAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await client.removePlaylistItemAt('pl-1', 2, itemPid: 'tr-9');
    final uri = adapter.requests.single.uri;
    expect(adapter.requests.single.method, 'DELETE');
    expect(uri.path, endsWith('/playlists/pl-1/items/2'));
    expect(uri.queryParameters['itemPid'], 'tr-9');
  });

  test('a preview counts its held moves by code', () {
    final plan = organizePlanFromGen(
      gen.OrganizePlan(
        (b) => b
          ..profile = 'default'
          ..totalActions = 0
          ..held = 3
          ..readOnlyLibraries = 0
          ..heldByCode.addAll({'read-only': 2, 'occupied': 1}),
      ),
    );
    expect(plan.heldByCode, {'read-only': 2, 'occupied': 1});
  });

  test('a preview lists its holds by their wire codes', () {
    final plan = organizePlanFromGen(
      gen.OrganizePlan(
        (b) => b
          ..profile = 'default'
          ..totalActions = 0
          ..held = 2
          ..readOnlyLibraries = 0
          ..holds.addAll([
            gen.OrganizeHold(
              (h) => h
                ..itemPid = 'tr-1'
                ..from = 'twin-b.flac'
                ..to = 'Pair/Doubles/01 Twin.flac'
                ..code = gen.OrganizeHoldCodeEnum.occupiedCase
                ..reason = 'a file named apart only by case stands there',
            ),
            gen.OrganizeHold(
              (h) => h
                ..from = 'nameless.flac'
                ..code = gen.OrganizeHoldCodeEnum.unknownDefaultOpenApi
                ..reason = 'a reason this build predates',
            ),
          ]),
      ),
    );
    expect(plan.holds.map((h) => h.code), ['occupied-case', '']);
    expect(plan.holds.first.itemPid, 'tr-1');
    expect(plan.holds.first.to, 'Pair/Doubles/01 Twin.flac');
    expect(plan.holds.last.itemPid, isNull);
  });

  test('a report names the job it ran as and the folders it emptied', () {
    final report = organizeReportFromGen(
      gen.OrganizeReport(
        (b) => b
          ..jobPid = 'jb-1'
          ..moved = 3
          ..skipped = 1
          ..held = 0
          ..readOnlyLibraries = 0
          ..failed = 0
          ..dirsPruned = 2,
      ),
    );
    expect(report.jobPid, 'jb-1');
    expect(report.dirsPruned, 2);
    expect(report.holds, isEmpty);
  });

  test('a history row says what ran and whether it undoes', () {
    final batch = organizeBatchFromGen(
      gen.OrganizeBatch(
        (b) => b
          ..jobPid = 'jb-2'
          ..kind = gen.OrganizeBatchKindEnum.organizeUndo
          ..state = 'done'
          ..startedAt = DateTime.utc(2026, 10, 1)
          ..committed = 4
          ..rolledBack = 0
          ..planned = 0
          ..undoable = true,
      ),
    );
    expect(batch.kind, 'organize-undo');
    expect(batch.isUndo, isTrue);
    expect(batch.committed, 4);
    expect(batch.profile, isNull);
    expect(batch.undoable, isTrue);
  });

  test('a history page is asked from its cursor and names the next', () async {
    final adapter = _AnsweringAdapter({
      'batches': [
        {
          'jobPid': 'jb-1',
          'kind': 'organize',
          'state': 'done',
          'startedAt': '2026-10-01T00:00:00Z',
          'committed': 2,
          'rolledBack': 0,
          'planned': 0,
          'undoable': true,
        },
      ],
      'nextCursor': 'c2',
    });
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    final page = await client.listOrganizeHistory(cursor: 'c1', limit: 2);
    final query = adapter.requests.single.uri.queryParameters;
    expect(query['cursor'], 'c1');
    expect(query['limit'], '2');
    expect(page.runs.single.jobPid, 'jb-1');
    expect(page.nextCursor, 'c2');
    expect(page.hasMore, isTrue);
  });

  test(
    'a preview, an apply and an undo wait as long as their run takes',
    () async {
      final adapter = _RecordingAdapter();
      final client = WaxDeckClient(
        baseUrl: 'http://host:4420',
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(client.previewOrganize(), throwsA(anything));
      await expectLater(client.applyOrganize(), throwsA(anything));
      await expectLater(client.undoOrganize('jb-3'), throwsA(anything));
      expect(adapter.requests, hasLength(3));
      for (final request in adapter.requests) {
        expect(
          request.receiveTimeout,
          const Duration(minutes: 30),
          reason: '${request.path} answers once its whole run has ended',
        );
      }
    },
  );

  test('a preview of a few items keeps the ordinary budget', () async {
    final adapter = _RecordingAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      client.previewOrganize(itemPids: const ['tr-1']),
      throwsA(anything),
    );
    expect(
      adapter.requests.single.receiveTimeout,
      const Duration(seconds: 30),
      reason: 'a scoped plan looks at its items alone',
    );
  });

  test('an undo posts the run it takes back', () async {
    final adapter = _RecordingAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(client.undoOrganize('jb-3'), throwsA(anything));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/organize/undo'));
    expect(jsonEncode(request.data), contains('"jobPid":"jb-3"'));
  });

  test('a saved profile carries what it sets itself', () {
    final profile = organizeProfileFromGen(
      gen.OrganizeProfile(
        (b) => b
          ..name = 'flat'
          ..musicTemplate = '{title}.{ext}'
          ..audiobookTemplate = '{author}/{title}.{ext}'
          ..podcastTemplate = '{podcast}/{episode}.{ext}'
          ..tagWrite = false
          ..builtIn = false
          ..sample.music = 'a'
          ..sample.audiobook = 'b'
          ..sample.podcast = 'c'
          ..saved.musicTemplate = '{title}.{ext}'
          ..saved.audiobookTemplate = ''
          ..saved.podcastTemplate = '',
      ),
    );
    expect(profile.saved?.music, '{title}.{ext}');
    expect(profile.saved?.audiobook, '');
  });
}
