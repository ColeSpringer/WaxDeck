import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  group('instant mix request mapping', () {
    test('carries every field onto the wire model', () {
      final request = instantMixRequestToGen(
        seedPid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        genre: null,
        adventurousness: 0.7,
        size: 25,
        excludePids: ['tr-PLAYED1', 'tr-PLAYED2'],
      );
      expect(request.seedPid, 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE');
      expect(request.genre, isNull);
      expect(request.adventurousness, 0.7);
      expect(request.size, 25);
      expect(request.excludePids?.toList(), ['tr-PLAYED1', 'tr-PLAYED2']);
    });

    test('an empty exclusion list rides as an absent field', () {
      final request = instantMixRequestToGen(genre: 'blues');
      expect(request.genre, 'blues');
      expect(request.seedPid, isNull);
      expect(request.adventurousness, isNull);
      expect(request.size, isNull);
      expect(request.excludePids, isNull);
    });
  });

  group('share mapping', () {
    gen.Share share({DateTime? expiresAt}) => gen.Share(
      (b) => b
        ..pid = 'sh-01JZX5N8QW3F4V9T2B7KDSHARE1'
        ..url = '/s/01JZX5N8QW3F4V9T2B7KSECRET'
        ..targetPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
        ..targetKind = 'track'
        ..targetTitle = 'Prancing Pony Blues'
        ..allowDownload = true
        ..createdAt = DateTime.utc(2026, 7, 20, 12)
        ..expiresAt = expiresAt
        ..plays = 3,
    );

    test('resolves the capability URL and keeps the expiry', () {
      final mapped = shareFromGen(
        share(expiresAt: DateTime.utc(2026, 7, 27, 12)),
        baseUrl: 'http://host:4420',
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
      final mapped = shareFromGen(share());
      expect(mapped.expiresAt, isNull);
      // With an empty base the URL stays origin-relative for web builds.
      expect(mapped.url, '/s/01JZX5N8QW3F4V9T2B7KSECRET');
    });
  });

  group('playlist import result mapping', () {
    test('missing entries and rung counts carry through in order', () {
      final mapped = playlistImportResultFromGen(
        gen.PlaylistImportResult(
          (b) => b
            ..playlistPid = 'pl-01JZX5N8QW3F4V9T2B7KDIMPORT'
            ..name = 'Road Trip'
            ..requested = 4
            ..resolved = 2
            ..missing.addAll([
              gen.PlaylistImportMiss(
                (m) => m
                  ..artist = 'The Bree Trio'
                  ..title = 'Lost B-Side'
                  ..album = 'Inn Sessions'
                  ..durationMs = 187000,
              ),
              gen.PlaylistImportMiss((m) => m..title = 'Untagged Bootleg'),
            ])
            ..rungs.replace(
              gen.ResolveRungCounts(
                (r) => r
                  ..essence = 1
                  ..strongId = 0
                  ..fingerprint = 0
                  ..descriptive = 1,
              ),
            ),
        ),
      );
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
      final mapped = playlistImportResultFromGen(
        gen.PlaylistImportResult(
          (b) => b
            ..name = 'Imported playlist'
            ..requested = 1
            ..resolved = 0
            ..missing.add(gen.PlaylistImportMiss((m) => m..title = 'Nowhere'))
            ..rungs.replace(
              gen.ResolveRungCounts(
                (r) => r
                  ..essence = 0
                  ..strongId = 0
                  ..fingerprint = 0
                  ..descriptive = 0,
              ),
            ),
        ),
      );
      expect(mapped.playlistPid, isNull);
    });
  });

  group('year in review mapping', () {
    test('recap fields, months, and top lists carry through', () {
      final mapped = yearInReviewFromGen(
        gen.YearInReview(
          (b) => b
            ..year = 2026
            ..timezone = 'America/Denver'
            ..totalMs = 7200000
            ..sessions = 40
            ..distinctItems = 30
            ..newInLibrary = 12
            ..timeSavedMs = 60000
            ..longestStreakDays = 9
            ..byMonth.addAll([
              for (var month = 1; month <= 12; month++)
                gen.MonthListening(
                  (m) => m
                    ..month = month
                    ..ms = month == 7 ? 7200000 : 0
                    ..sessions = month == 7 ? 40 : 0,
                ),
            ])
            ..byMediaType.add(
              gen.MediaTypeListening(
                (m) => m
                  ..mediaType = gen.MediaType.music
                  ..ms = 7200000
                  ..sessions = 40,
              ),
            )
            ..topArtists.add(
              gen.TopEntry(
                (t) => t
                  ..name = 'Muddy Waters'
                  ..pid = 'ar-01JZX5N8QW3F4V9T2B7KDARTIST'
                  ..artUrl = '/api/v1/items/tr-x/art'
                  ..plays = 18
                  ..ms = 3600000,
              ),
            )
            ..topGenres.add(
              gen.TopEntry(
                (t) => t
                  ..name = 'blues'
                  ..plays = 22
                  ..ms = 4000000,
              ),
            ),
        ),
        baseUrl: 'http://host:4420',
      );
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
      expect(mapped.byMediaType.single.mediaType, MediaType.music);
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

    test('top lists unmangle the generated range names', () {
      final mapped = topListFromGen(
        gen.TopList(
          (b) => b
            ..kind = gen.TopListKindEnum.artists
            ..range = gen.TopListRangeEnum.n7d,
        ),
      );
      // The generator prefixes enum names that start with a digit
      // (7d becomes n7d); the mapper bridges back to the wire form.
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
      expect(listenSessionToGen(session).skippedMs, 12000);

      final bare = ListenSession(
        sessionId: '01JZX5N8QW3F4V9T2B7KDSESSIO2',
        pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        startedAt: DateTime.utc(2026, 7, 20, 8),
        msPlayed: 214000,
      );
      expect(listenSessionToGen(bare).skippedMs, isNull);
    });

    test('sharedStatsOptOut round-trips through prefs', () {
      final stored = prefsFromGen(
        prefsToGen(const Prefs(timezone: 'America/Denver')),
      );
      expect(stored.sharedStatsOptOut, isNull);

      final optedOut = prefsFromGen(
        prefsToGen(const Prefs(sharedStatsOptOut: true)),
      );
      expect(optedOut.sharedStatsOptOut, isTrue);
    });
  });
}
