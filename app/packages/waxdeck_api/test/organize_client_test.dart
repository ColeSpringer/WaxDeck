import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _ctx = WireContext(baseUrl: '');

void main() {
  test('a profile name reaches the path whole', () async {
    final adapter = RecordingAdapter(status: 204);
    final client = clientOn(adapter);
    await client.deleteOrganizeProfile('C# layout?');
    final uri = adapter.requests.single.uri;
    expect(uri.pathSegments.last, 'C# layout?');
    expect(uri.hasFragment, isFalse);
    expect(uri.hasQuery, isFalse);
  });

  test('a playlist removal sends the item the caller saw', () async {
    final adapter = RecordingAdapter(status: 204);
    final client = clientOn(adapter);
    await client.removePlaylistItemAt('pl-1', 2, itemPid: 'tr-9');
    final uri = adapter.requests.single.uri;
    expect(adapter.requests.single.method, 'DELETE');
    expect(uri.path, endsWith('/playlists/pl-1/items/2'));
    expect(uri.queryParameters['itemPid'], 'tr-9');
  });

  test('a preview counts its held moves by code', () {
    final plan = decodeOrganizePlan({
      'profile': 'default',
      'totalActions': 0,
      'held': 3,
      'readOnlyLibraries': 0,
      'actions': <Object?>[],
      'heldByCode': {'read-only': 2, 'occupied': 1},
    }, _ctx);
    expect(plan.heldByCode, {'read-only': 2, 'occupied': 1});
  });

  test('a preview lists its holds by their wire codes', () {
    final plan = decodeOrganizePlan({
      'profile': 'default',
      'totalActions': 0,
      'held': 2,
      'readOnlyLibraries': 0,
      'actions': <Object?>[],
      'holds': [
        {
          'itemPid': 'tr-1',
          'from': 'twin-b.flac',
          'to': 'Pair/Doubles/01 Twin.flac',
          'code': 'occupied-case',
          'reason': 'a file named apart only by case stands there',
        },
        {
          'from': 'nameless.flac',
          'code': 'held-by-a-later-rule',
          'reason': 'a reason this build predates',
        },
      ],
    }, _ctx);
    expect(plan.holds.map((h) => h.code), ['occupied-case', '']);
    expect(plan.holds.first.itemPid, 'tr-1');
    expect(plan.holds.first.to, 'Pair/Doubles/01 Twin.flac');
    expect(plan.holds.last.itemPid, isNull);
  });

  test('a report names the job it ran as and the folders it emptied', () {
    final report = decodeOrganizeReport({
      'jobPid': 'jb-1',
      'moved': 3,
      'skipped': 1,
      'held': 0,
      'readOnlyLibraries': 0,
      'failed': 0,
      'dirsPruned': 2,
    }, _ctx);
    expect(report.jobPid, 'jb-1');
    expect(report.dirsPruned, 2);
    expect(report.holds, isEmpty);
  });

  test('a history row says what ran and whether it undoes', () {
    final batch = decodeOrganizeBatch({
      'jobPid': 'jb-2',
      'kind': 'organize-undo',
      'state': 'done',
      'startedAt': '2026-10-01T00:00:00Z',
      'committed': 4,
      'rolledBack': 0,
      'planned': 0,
      'undoable': true,
    }, _ctx);
    expect(batch.kind, 'organize-undo');
    expect(batch.isUndo, isTrue);
    expect(batch.committed, 4);
    expect(batch.profile, isNull);
    expect(batch.undoable, isTrue);
  });

  test('a history page is asked from its cursor and names the next', () async {
    final adapter = RecordingAdapter(
      body: {
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
      },
    );
    final client = clientOn(adapter);
    final page = await client.listOrganizeHistory(cursor: 'c1', limit: 2);
    final query = adapter.requests.single.uri.queryParameters;
    expect(query['cursor'], 'c1');
    expect(query['limit'], '2');
    expect(page.runs.single.jobPid, 'jb-1');
    expect(page.nextCursor, 'c2');
    expect(page.hasMore, isTrue);
  });

  test(
    'a preview of the whole library waits as long as its run takes',
    () async {
      final adapter = RecordingAdapter(status: 204);
      final client = clientOn(adapter);
      await expectLater(client.previewOrganize(), throwsA(anything));
      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(minutes: 30),
        reason:
            'a library-wide plan answers once every file has been looked at',
      );
    },
  );

  test('a preview of a few items keeps the ordinary budget', () async {
    final adapter = RecordingAdapter(status: 204);
    final client = clientOn(adapter);
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

  test('a saved profile carries what it sets itself', () {
    final profile = decodeOrganizeProfile({
      'name': 'flat',
      'musicTemplate': '{title}.{ext}',
      'audiobookTemplate': '{author}/{title}.{ext}',
      'podcastTemplate': '{podcast}/{episode}.{ext}',
      'tagWrite': false,
      'builtIn': false,
      'sample': {
        'music': 'a',
        'audiobook': 'b',
        'podcast': 'c',
        'compilation': 'd',
      },
      'saved': {
        'musicTemplate': '{title}.{ext}',
        'audiobookTemplate': '',
        'podcastTemplate': '',
      },
    }, _ctx);
    expect(profile.saved?.music, '{title}.{ext}');
    expect(profile.saved?.audiobook, '');
  });

  test('a compilation folder keeps its three states apart', () {
    OrganizeProfile decoded(String? folder) => decodeOrganizeProfile({
      'name': 'flat',
      'musicTemplate': 'm',
      'audiobookTemplate': 'a',
      'podcastTemplate': 'p',
      'tagWrite': false,
      'builtIn': false,
      'compilationFolder': ?folder,
      'sample': {
        'music': 'a',
        'audiobook': 'b',
        'podcast': 'c',
        'compilation': 'Mixes/Coastal Nights/04 - Night Drive.flac',
      },
    }, _ctx);
    expect(decoded(null).compilationFolder, isNull);
    expect(decoded('').compilationFolder, '');
    final named = decoded('Mixes');
    expect(named.compilationFolder, 'Mixes');
    expect(
      named.sample.compilation,
      'Mixes/Coastal Nights/04 - Night Drive.flac',
    );
  });

  test('a save and a preview send the folder only when there is one', () async {
    final profile = {
      'name': 'flat',
      'musicTemplate': 'm',
      'audiobookTemplate': 'a',
      'podcastTemplate': 'p',
      'tagWrite': false,
      'builtIn': false,
      'sample': {
        'music': '',
        'audiobook': '',
        'podcast': '',
        'compilation': '',
      },
    };
    final saves = RecordingAdapter(body: profile);
    final client = clientOn(saves);
    await client.putOrganizeProfile('unset');
    await client.putOrganizeProfile('own', compilationFolder: '');
    await client.putOrganizeProfile('named', compilationFolder: 'Mixes');
    final sent = [
      for (final r in saves.requests)
        jsonDecode(jsonEncode(r.data)) as Map<String, Object?>,
    ];
    expect(sent[0].containsKey('compilationFolder'), isFalse);
    expect(sent[1]['compilationFolder'], '');
    expect(sent[2]['compilationFolder'], 'Mixes');

    final previews = RecordingAdapter(body: profile['sample']!);
    final previewing = clientOn(previews);
    await previewing.previewOrganizeProfile();
    await previewing.previewOrganizeProfile(compilationFolder: '');
    expect(
      jsonEncode(previews.requests.first.data),
      isNot(contains('compilationFolder')),
    );
    expect(
      jsonEncode(previews.requests.last.data),
      contains('"compilationFolder":""'),
    );
  });
}
