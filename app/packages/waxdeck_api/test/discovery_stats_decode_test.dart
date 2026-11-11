import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _noBase = WireContext(baseUrl: '');
const _host = WireContext(baseUrl: 'http://host:4420');

/// The body [WaxDeckClient.createInstantMix] sends for these arguments.
Future<Map<Object?, Object?>> _mixRequest({
  String? seedPid,
  String? genre,
  double? adventurousness,
  int? size,
  List<String> excludePids = const [],
}) async {
  final adapter = RecordingAdapter.refusing();
  final client = clientOn(adapter);
  await expectLater(
    client.createInstantMix(
      seedPid: seedPid,
      genre: genre,
      adventurousness: adventurousness,
      size: size,
      excludePids: excludePids,
    ),
    throwsA(isA<WaxDeckApiException>()),
  );
  return adapter.requests.single.data as Map<Object?, Object?>;
}

void main() {
  group('the instant mix request', () {
    test('carries every field onto the wire model', () async {
      final request = await _mixRequest(
        seedPid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        genre: null,
        adventurousness: 0.7,
        size: 25,
        excludePids: ['tr-PLAYED1', 'tr-PLAYED2'],
      );
      expect(request['seedPid'], 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE');
      expect(request['genre'], isNull);
      expect(request['adventurousness'], 0.7);
      expect(request['size'], 25);
      expect(request['excludePids'], ['tr-PLAYED1', 'tr-PLAYED2']);
    });

    test('an empty exclusion list rides as an absent field', () async {
      final request = await _mixRequest(genre: 'blues');
      expect(request['genre'], 'blues');
      expect(request['seedPid'], isNull);
      expect(request, isNot(contains('excludePids')));
    });

    test('an unset adventurousness and size ride as absent fields', () async {
      final request = await _mixRequest(genre: 'blues');
      expect(request, isNot(contains('adventurousness')));
      expect(request, isNot(contains('size')));
    });
  });

  group('the instant mix response', () {
    test('carries the exclusion count through', () {
      final mix = decodeInstantMix({
        'basis': 'metadata',
        'items': <Object?>[],
        'excluded': 7,
      }, _noBase);
      expect(mix.basis, MixBasis.metadata);
      expect(mix.items, isEmpty);
      expect(mix.excluded, 7);
    });

    test('a server without the field reads as zero', () {
      final mix = decodeInstantMix({
        'basis': 'sonic',
        'items': <Object?>[],
      }, _noBase);
      expect(mix.excluded, 0);
    });
  });

  group('a share', () {
    Map<String, Object?> share({String? expiresAt}) => {
      'pid': 'sh-01JZX5N8QW3F4V9T2B7KDSHARE1',
      'url': '/s/01JZX5N8QW3F4V9T2B7KSECRET',
      'targetPid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      'targetKind': 'track',
      'targetTitle': 'Prancing Pony Blues',
      'allowDownload': true,
      'createdAt': '2026-07-20T12:00:00Z',
      'expiresAt': ?expiresAt,
      'plays': 3,
    };

    test('resolves the capability URL and keeps the expiry', () {
      final mapped = decodeShare(
        share(expiresAt: '2026-07-27T12:00:00Z'),
        _host,
      );
      expect(mapped.pid, 'sh-01JZX5N8QW3F4V9T2B7KDSHARE1');
      expect(mapped.url, 'http://host:4420/s/01JZX5N8QW3F4V9T2B7KSECRET');
      expect(mapped.targetPid, 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE');
      expect(mapped.targetKind, 'track');
      expect(mapped.targetTitle, 'Prancing Pony Blues');
      expect(mapped.allowDownload, isTrue);
      expect(mapped.positionMs, isNull);
      expect(mapped.createdAt, DateTime.utc(2026, 7, 20, 12));
      expect(mapped.expiresAt, DateTime.utc(2026, 7, 27, 12));
      expect(mapped.plays, 3);
    });

    test('a link without expiry maps to a null expiresAt', () {
      final mapped = decodeShare(share(), _noBase);
      expect(mapped.expiresAt, isNull);
      // With an empty base the URL stays origin-relative for web builds.
      expect(mapped.url, '/s/01JZX5N8QW3F4V9T2B7KSECRET');
    });
  });

  group('a playlist import result', () {
    test('missing entries and rung counts carry through in order', () {
      final mapped = decodePlaylistImportResult({
        'playlistPid': 'pl-01JZX5N8QW3F4V9T2B7KDIMPORT',
        'name': 'Road Trip',
        'requested': 4,
        'resolved': 2,
        'missing': [
          {
            'artist': 'The Bree Trio',
            'title': 'Lost B-Side',
            'album': 'Inn Sessions',
            'durationMs': 187000,
          },
          {'title': 'Untagged Bootleg'},
        ],
        'rungs': {
          'essence': 1,
          'strongId': 0,
          'fingerprint': 0,
          'descriptive': 1,
        },
      }, _noBase);
      expect(mapped.playlistPid, 'pl-01JZX5N8QW3F4V9T2B7KDIMPORT');
      expect(mapped.name, 'Road Trip');
      expect(mapped.requested, 4);
      expect(mapped.resolved, 2);
      expect(mapped.missing, hasLength(2));
      expect(mapped.missing.first.artist, 'The Bree Trio');
      expect(mapped.missing.first.title, 'Lost B-Side');
      expect(mapped.missing.first.durationMs, 187000);
      expect(mapped.missing.last.title, 'Untagged Bootleg');
      expect(mapped.missing.last.artist, isNull);
      expect(mapped.rungs.essence, 1);
      expect(mapped.rungs.descriptive, 1);
    });

    test('nothing resolved leaves the playlist pid null', () {
      final mapped = decodePlaylistImportResult({
        'name': 'Imported playlist',
        'requested': 1,
        'resolved': 0,
        'missing': [
          {'title': 'Nowhere'},
        ],
        'rungs': {
          'essence': 0,
          'strongId': 0,
          'fingerprint': 0,
          'descriptive': 0,
        },
      }, _noBase);
      expect(mapped.playlistPid, isNull);
    });
  });

  group('the year in review', () {
    test('recap fields, months, and top lists carry through', () {
      final mapped = decodeYearInReview({
        'year': 2026,
        'timezone': 'America/Denver',
        'totalMs': 7200000,
        'sessions': 40,
        'distinctItems': 30,
        'newInLibrary': 12,
        'timeSavedMs': 60000,
        'longestStreakDays': 9,
        'byMonth': [
          for (var month = 1; month <= 12; month++)
            {
              'month': month,
              'ms': month == 7 ? 7200000 : 0,
              'sessions': month == 7 ? 40 : 0,
            },
        ],
        'byMediaType': [
          {'mediaType': 'music', 'ms': 7200000, 'sessions': 40},
        ],
        'topArtists': [
          {
            'name': 'Muddy Waters',
            'pid': 'ar-01JZX5N8QW3F4V9T2B7KDARTIST',
            'artUrl': '/api/v1/items/tr-x/art',
            'plays': 18,
            'ms': 3600000,
          },
        ],
        'topTracks': <Object?>[],
        'topGenres': [
          {'name': 'blues', 'plays': 22, 'ms': 4000000},
        ],
        'topShows': <Object?>[],
      }, _host);
      expect(mapped.year, 2026);
      expect(mapped.timezone, 'America/Denver');
      expect(mapped.totalMs, 7200000);
      expect(mapped.distinctItems, 30);
      expect(mapped.newInLibrary, 12);
      expect(mapped.timeSavedMs, 60000);
      expect(mapped.longestStreakDays, 9);
      expect(mapped.byMonth, hasLength(12));
      expect(mapped.byMonth[6].month, 7);
      expect(mapped.byMonth[6].ms, 7200000);
      expect(mapped.byMediaType.single.mediaType, StatsMediaType.music);
      final artist = mapped.topArtists.single;
      expect(artist.name, 'Muddy Waters');
      expect(artist.pid, 'ar-01JZX5N8QW3F4V9T2B7KDARTIST');
      // Origin-relative art resolves against the base URL, like item art.
      expect(artist.artUrl, 'http://host:4420/api/v1/items/tr-x/art');
      final genre = mapped.topGenres.single;
      expect(genre.pid, isNull);
      expect(genre.artUrl, isNull);
      expect(mapped.topTracks, isEmpty);
      expect(mapped.topShows, isEmpty);
    });

    test('a top list keeps its range in the wire spelling', () {
      final mapped = decodeTopList({
        'kind': 'artists',
        'range': '7d',
        'entries': <Object?>[],
      }, _noBase);
      expect(mapped.kind, 'artists');
      expect(mapped.range, '7d');
      expect(mapped.entries, isEmpty);
    });
  });

  group('listen session and prefs field additions', () {
    test('skippedMs rides onto the wire session when present', () {
      final session = ListenSession(
        sessionId: '01JZX5N8QW3F4V9T2B7KDSESSION',
        pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        startedAt: DateTime.utc(2026, 7, 20, 8),
        msPlayed: 214000,
        skippedMs: 12000,
      );
      expect(encodeListenSession(session)['skippedMs'], 12000);

      final bare = ListenSession(
        sessionId: '01JZX5N8QW3F4V9T2B7KDSESSIO2',
        pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        startedAt: DateTime.utc(2026, 7, 20, 8),
        msPlayed: 214000,
      );
      expect(encodeListenSession(bare)['skippedMs'], isNull);
    });

    test('sharedStatsOptOut round-trips through prefs', () {
      final stored = decodePrefs(
        encodePrefs(const Prefs(timezone: 'America/Denver')),
        _noBase,
      );
      expect(stored.sharedStatsOptOut, isNull);

      final optedOut = decodePrefs(
        encodePrefs(const Prefs(sharedStatsOptOut: true)),
        _noBase,
      );
      expect(optedOut.sharedStatsOptOut, isTrue);
    });
  });
}
