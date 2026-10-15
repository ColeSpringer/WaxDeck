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

const _flacItem = 'tr-01JZX5N8QW3F4V9T2B7KDUPFLAC';
const _mp3Item = 'tr-01JZX5N8QW3F4V9T2B7KDUPMP3X';
const _oggItem = 'tr-01JZX5N8QW3F4V9T2B7KDUPOGGX';
const _twoFiles = 'tr-01JZX5N8QW3F4V9T2B7KDUPBOTH';

/// Shaped by the listing's schema: a recording two items hold, then an
/// item holding two encodings of its own, alike enough that their paths
/// are what tell them apart.
const _listing = <String, Object?>{
  'groups': <Object?>[
    <String, Object?>{
      'members': <Object?>[
        <String, Object?>{
          'itemPid': _flacItem,
          'filePid': 'fi-01JZX5N8QW3F4V9T2B7KDUPFLAC',
          'title': 'Harbour Lights',
          'artist': 'Nightjar',
          'codec': 'flac',
          'bitrate': 1011,
          'sampleRate': 96000,
          'bitDepth': 24,
          'lossless': true,
          'best': true,
        },
        <String, Object?>{
          'itemPid': _mp3Item,
          'filePid': 'fi-01JZX5N8QW3F4V9T2B7KDUPMP3X',
          'title': 'Harbour Lights (Radio)',
          'codec': 'mp3',
          'bitrate': 320,
          'sampleRate': 44100,
          'lossless': false,
          'best': false,
        },
      ],
    },
    <String, Object?>{
      'members': <Object?>[
        <String, Object?>{
          'itemPid': _twoFiles,
          'filePid': 'fi-01JZX5N8QW3F4V9T2B7KDUPKEEP',
          'path': '/srv/music/Nightjar/01 Gullwing.m4a',
          'title': 'Gullwing',
          'artist': 'Nightjar',
          'codec': 'aac',
          'bitrate': 256,
          'lossless': false,
          'best': true,
        },
        <String, Object?>{
          'itemPid': _twoFiles,
          'filePid': 'fi-01JZX5N8QW3F4V9T2B7KDUPDROP',
          'path': '/srv/music/Nightjar/01 Gullwing (1).m4a',
          'title': 'Gullwing',
          'artist': 'Nightjar',
          'codec': 'aac',
          'bitrate': 256,
          'lossless': false,
          'best': false,
        },
      ],
    },
  ],
};

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

  test('an upgrade listing reads every field of every member', () async {
    adapter.enqueue(200, _listing);

    final groups = await client.listUpgrades();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.uri.path, endsWith('/library/upgrades'));
    expect(
      [
        for (final group in groups)
          [
            for (final m in group.members)
              (
                m.itemPid,
                m.filePid,
                m.path,
                m.title,
                m.artist,
                m.codec,
                m.bitrate,
                m.sampleRate,
                m.bitDepth,
                m.lossless,
                m.best,
              ),
          ],
      ],
      [
        [
          (
            _flacItem,
            'fi-01JZX5N8QW3F4V9T2B7KDUPFLAC',
            null,
            'Harbour Lights',
            'Nightjar',
            'flac',
            1011,
            96000,
            24,
            true,
            true,
          ),
          (
            _mp3Item,
            'fi-01JZX5N8QW3F4V9T2B7KDUPMP3X',
            null,
            'Harbour Lights (Radio)',
            null,
            'mp3',
            320,
            44100,
            null,
            false,
            false,
          ),
        ],
        [
          (
            _twoFiles,
            'fi-01JZX5N8QW3F4V9T2B7KDUPKEEP',
            '/srv/music/Nightjar/01 Gullwing.m4a',
            'Gullwing',
            'Nightjar',
            'aac',
            256,
            null,
            null,
            false,
            true,
          ),
          (
            _twoFiles,
            'fi-01JZX5N8QW3F4V9T2B7KDUPDROP',
            '/srv/music/Nightjar/01 Gullwing (1).m4a',
            'Gullwing',
            'Nightjar',
            'aac',
            256,
            null,
            null,
            false,
            false,
          ),
        ],
      ],
    );
  });

  test('a resolve names files within one item, and whole items across '
      'them', () async {
    adapter
      ..enqueue(200, {'trashed': 1})
      ..enqueue(200, {'trashed': 2});

    final withinOne = await client.resolveUpgrade(
      keepItemPid: _twoFiles,
      keepFilePid: 'fi-01JZX5N8QW3F4V9T2B7KDUPKEEP',
      removeFilePids: ['fi-01JZX5N8QW3F4V9T2B7KDUPDROP'],
    );
    final across = await client.resolveUpgrade(
      keepItemPid: _flacItem,
      removeItemPids: [_mp3Item, _oggItem],
    );

    expect((withinOne, across), (1, 2));
    for (final sent in adapter.requests) {
      expect(sent.method, 'POST');
      expect(sent.uri.path, endsWith('/library/upgrades/resolve'));
    }
    // Exactly one removal list each, and nothing of the other shape.
    expect(
      [for (final sent in adapter.requests) jsonDecode(jsonEncode(sent.data))],
      [
        {
          'keepItemPid': _twoFiles,
          'keepFilePid': 'fi-01JZX5N8QW3F4V9T2B7KDUPKEEP',
          'removeFilePids': ['fi-01JZX5N8QW3F4V9T2B7KDUPDROP'],
        },
        {
          'keepItemPid': _flacItem,
          'removeItemPids': [_mp3Item, _oggItem],
        },
      ],
    );
  });
}
