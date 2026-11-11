import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';

import 'support/last_run.dart';

const _ctx = WireContext(baseUrl: '');

Map<String, Object?> _lastRun() => <String, Object?>{
  ...lastRun(['lyrics', 'identity']),
  'artistsEnriched': 12,
  'lyricsMatched': 7,
  'groupArtEnriched': 9,
  'deferred': 4,
  'tagsSkipped': 3,
  'tagsReadOnly': 2,
  'finishedAt': '2026-09-27T03:45:00Z',
};

void main() {
  test('the status carries the switches, the phases and the last run', () {
    final status = decodeEnrichmentStatus(<String, Object?>{
      'providers': <Object?>[
        <String, Object?>{
          'name': 'fanarttv',
          'capabilities': <Object?>['aux-art'],
          'configured': true,
          'builtin': false,
          'enabled': false,
        },
        <String, Object?>{
          'name': 'lrclib',
          'capabilities': <Object?>['lyrics'],
          'configured': true,
          'builtin': true,
        },
      ],
      'coverage': <String, Object?>{
        for (final k in const ['artists', 'releaseGroups', 'books', 'lyrics'])
          k: <String, Object?>{'enriched': 1, 'total': 2},
        'lyricsAsked': 5,
      },
      'running': true,
      'runningJob': 'jb-01JZX5N8QW3F4V9T2B7KD3M9R6',
      'configured': true,
      'musicbrainzConfigured': false,
      'phases': <Object?>['group-art', 'track-fields'],
      'lastRun': _lastRun(),
    }, _ctx);

    final fanart = status.providers.first;
    expect(fanart.enabled, isFalse);
    // Absent reads as the contract's default: switched on.
    expect(status.providers.last.enabled, isTrue);
    expect(status.runningJob, 'jb-01JZX5N8QW3F4V9T2B7KD3M9R6');
    expect(status.configured, isTrue);
    expect(status.musicbrainzConfigured, isFalse);
    expect(status.phases, ['group-art', 'track-fields']);
    expect(status.coverage.lyrics.enriched, 1);
    expect(status.coverage.lyricsAsked, 5);
    final run = status.lastRun!;
    expect(run.artistsEnriched, 12);
    expect(run.lyricsMatched, 7);
    expect(run.groupArtEnriched, 9);
    expect(run.deferred, 4);
    expect(run.tagsSkipped, 3);
    expect(run.tagsReadOnly, 2);
    expect(run.stalled, ['lyrics', 'identity']);
    expect(run.finishedAt, DateTime.utc(2026, 9, 27, 3, 45));
  });

  test('a status with no finished pass carries no last run', () {
    final status = decodeEnrichmentStatus(<String, Object?>{
      'providers': <Object?>[],
      'coverage': <String, Object?>{
        for (final k in const ['artists', 'releaseGroups', 'books', 'lyrics'])
          k: <String, Object?>{'enriched': 0, 'total': 0},
        'lyricsAsked': 0,
      },
      'running': true,
      'configured': false,
      'musicbrainzConfigured': false,
      'phases': <Object?>[],
    }, _ctx);
    expect(status.lastRun, isNull);
    expect(status.phases, isEmpty);
  });

  test('a phase goes back to the wire as the wire spells it', () {
    for (final wire in const ['identity', 'group-art', 'album-fields']) {
      expect(
        encodeEnrichmentRunRequest(
          EnrichmentRunRequest(phases: [wire]),
        )['phases'],
        [wire],
      );
    }
  });

  test('the cache report keeps every kind and the exempt share', () {
    final report = decodeEnrichmentCacheReport(<String, Object?>{
      'rows': 3,
      'bytes': 700,
      'oldestAt': '2026-09-01T00:00:00Z',
      'kinds': <Object?>[
        <String, Object?>{
          'kind': 'mb:artist',
          'rows': 2,
          'bytes': 600,
          'exempt': false,
        },
        <String, Object?>{
          'kind': 'caa:rg-front',
          'rows': 1,
          'bytes': 100,
          'exempt': true,
        },
      ],
      'exemptRows': 1,
      'exemptBytes': 100,
    }, _ctx);
    expect(report.rows, 3);
    expect(report.oldestAt, DateTime.utc(2026, 9));
    expect(report.newestAt, isNull);
    expect(report.kinds.last.exempt, isTrue);
    expect(report.exemptBytes, 100);
  });
}
