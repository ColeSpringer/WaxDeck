import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _document = <String, Object?>{
  'name': 'Loved and long',
  'all': <Object?>[
    <String, Object?>{
      'is': <String, Object?>{'loved': true},
    },
    <String, Object?>{
      'gt': <String, Object?>{'duration': 180},
    },
  ],
};

const _playlistJson = <String, Object?>{
  'pid': 'pl-01JZX5N8QW3F4V9T2B7KDNSP001',
  'name': 'Loved and long',
  'kind': 'smart',
  'visibility': 'private',
  'ownerName': 'admin',
  'isOwner': true,
  'itemCount': 0,
  'createdAt': '2026-09-29T00:00:00Z',
  'updatedAt': '2026-09-29T00:00:00Z',
};

void main() {
  late RecordingAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = RecordingAdapter();
    client = clientOn(adapter);
  });

  test('a check sends the document and reads the report', () async {
    adapter.enqueue(200, <String, Object?>{
      'direction': 'import',
      'gaps': <Object?>[
        <String, Object?>{
          'kind': 'field',
          'code': 'unsupported_field',
          'field': 'starred',
          'path': '/all/0',
          'reason': 'nsp: unsupported field: starred',
        },
      ],
    });

    final report = await client.checkNspImport(_document);

    final sent = adapter.requests.single;
    expect(sent.method, 'POST');
    expect(sent.uri.path, '/api/v1/playlists/nsp/report');
    expect(jsonDecode(jsonEncode(sent.data)), _document);
    expect(report.direction, 'import');
    expect(report.gaps.single.code, 'unsupported_field');
    expect(report.gaps.single.field, 'starred');
  });

  test(
    'a strict import sends no parameters and answers the playlist',
    () async {
      adapter.enqueue(201, _playlistJson);

      final created = await client.importNsp(_document);

      final sent = adapter.requests.single;
      expect(sent.uri.path, '/api/v1/playlists/nsp');
      expect(sent.uri.queryParameters, isEmpty);
      expect(jsonDecode(jsonEncode(sent.data)), _document);
      expect(created.pid, 'pl-01JZX5N8QW3F4V9T2B7KDNSP001');
      expect(created.kind, 'smart');
    },
  );

  test('a top-level null goes as pasted', () async {
    adapter.enqueue(200, <String, Object?>{'direction': 'import'});

    await client.checkNspImport(<String, Object?>{
      'name': 'x',
      'all': <Object?>[],
      'any': null,
    });

    expect(jsonDecode(jsonEncode(adapter.requests.single.data)), {
      'name': 'x',
      'all': <Object?>[],
      'any': null,
    });
  });

  test('a report says when it stopped at the cap', () async {
    adapter.enqueue(200, <String, Object?>{
      'direction': 'import',
      'truncated': true,
    });

    expect((await client.checkNspImport(_document)).truncated, isTrue);
  });

  test('a partial import asks for it, and a name overrides', () async {
    adapter.enqueue(201, _playlistJson);

    await client.importNsp(_document, partial: true, name: 'Mine');

    expect(adapter.requests.single.uri.queryParameters, <String, String>{
      'partial': 'true',
      'name': 'Mine',
    });
  });
}
