import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  group('resolveMediaUrl', () {
    test('keeps relative URLs relative with an empty base', () {
      expect(resolveMediaUrl('', '/media/stream?pid=x'), '/media/stream?pid=x');
    });

    test('joins relative URLs onto a base origin', () {
      expect(
        resolveMediaUrl('http://localhost:4420', '/media/stream?pid=x'),
        'http://localhost:4420/media/stream?pid=x',
      );
    });

    test('trims trailing slashes off the base', () {
      expect(
        resolveMediaUrl('http://localhost:4420/', '/a/b'),
        'http://localhost:4420/a/b',
      );
    });

    test('passes absolute URLs through untouched', () {
      expect(
        resolveMediaUrl('http://localhost:4420', 'https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
    });
  });

  group('enum mapping', () {
    test('media types map one to one', () {
      expect(mediaTypeFromGen(gen.MediaType.music), MediaType.music);
      expect(mediaTypeFromGen(gen.MediaType.podcast), MediaType.podcast);
      expect(mediaTypeFromGen(gen.MediaType.audiobook), MediaType.audiobook);
      for (final type in MediaType.values) {
        expect(mediaTypeFromGen(mediaTypeToGen(type)), type);
      }
    });

    test('discovery lists map to the wire names', () {
      for (final list in DiscoveryList.values) {
        expect(discoveryListToGen(list).name, isNotEmpty);
      }
      expect(
        discoveryListToGen(DiscoveryList.recentlyPlayed),
        gen.DiscoveryList.recentlyPlayed,
      );
      expect(
        discoveryListToGen(DiscoveryList.alphabetical),
        gen.DiscoveryList.alphabetical,
      );
    });
  });

  group('item mapping', () {
    gen.$ItemSummary summary({String? artUrl}) => gen.$ItemSummary(
      (b) => b
        ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
        ..mediaType = gen.MediaType.music
        ..title = 'Prancing Pony Blues'
        ..artist = 'The Bree Trio'
        ..album = 'Inn Sessions'
        ..durationMs = 214000
        ..artUrl = artUrl,
    );

    test('summary fields carry over', () {
      final mapped = itemSummaryFromGen(
        summary(artUrl: '/api/v1/items/tr-x/art'),
        baseUrl: 'http://host:4420',
      );
      expect(mapped.pid, 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE');
      expect(mapped.mediaType, MediaType.music);
      expect(mapped.title, 'Prancing Pony Blues');
      expect(mapped.artist, 'The Bree Trio');
      expect(mapped.album, 'Inn Sessions');
      expect(mapped.durationMs, 214000);
      expect(mapped.artUrl, 'http://host:4420/api/v1/items/tr-x/art');
    });

    test('missing art stays null', () {
      expect(itemSummaryFromGen(summary()).artUrl, isNull);
    });

    test('pages keep order and cursor', () {
      final page = gen.ItemPage(
        (b) => b
          ..items.add(summary())
          ..nextCursor = 'cursor-1',
      );
      final mapped = itemPageFromGen(page);
      expect(mapped.items, hasLength(1));
      expect(mapped.nextCursor, 'cursor-1');
      expect(mapped.hasMore, isTrue);
      expect(mapped.seed, isNull);

      final last = itemPageFromGen(gen.ItemPage((b) => b.items.add(summary())));
      expect(last.hasMore, isFalse);
    });

    test('random pages carry the effective seed through', () {
      final page = gen.ItemPage(
        (b) => b
          ..items.add(summary())
          ..seed = 42,
      );
      expect(itemPageFromGen(page).seed, 42);
    });

    test('detail extends the summary with extra fields', () {
      final detail = itemDetailFromGen(
        gen.Item(
          (b) => b
            ..pid = 'bk-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..mediaType = gen.MediaType.audiobook
            ..title = 'There And Back Again'
            ..durationMs = 3600000
            ..year = 2024
            ..codec = 'flac'
            ..genres.addAll(['memoir']),
        ),
      );
      expect(detail.mediaType, MediaType.audiobook);
      expect(detail.year, 2024);
      expect(detail.codec, 'flac');
      expect(detail.genres, ['memoir']);
      expect(detail.trackNumber, isNull);
    });
  });

  group('playback mapping', () {
    test('play-info resolves the stream URL against the base', () {
      final expires = DateTime.utc(2026, 7, 18, 12);
      final info = playInfoFromGen(
        gen.PlayInfo(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..url = '/media/stream?pid=tr-x&mt=abc'
            ..mimeType = 'audio/flac'
            ..durationMs = 214000
            ..seekable = true
            ..expiresAt = expires,
        ),
        baseUrl: 'http://host:4420',
      );
      expect(info.url, 'http://host:4420/media/stream?pid=tr-x&mt=abc');
      expect(info.mimeType, 'audio/flac');
      expect(info.durationMs, 214000);
      expect(info.seekable, isTrue);
      expect(info.expiresAt, expires);
    });

    test('play-state fields carry over', () {
      final state = playStateFromGen(
        gen.PlayState(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..positionMs = 61500
            ..played = true
            ..finished = false
            ..playCount = 3
            ..starred = true,
        ),
      );
      expect(state.positionMs, 61500);
      expect(state.played, isTrue);
      expect(state.finished, isFalse);
      expect(state.playCount, 3);
      expect(state.starred, isTrue);
      expect(state.updatedAt, isNull);
    });
  });

  group('listen mapping', () {
    test('sessions serialize with UTC timestamps and a live source', () {
      final startedLocal = DateTime(2026, 7, 18, 9, 30);
      final mapped = listenSessionToGen(
        ListenSession(
          sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ012345'.substring(0, 26),
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          startedAt: startedLocal,
          msPlayed: 90500,
          finished: true,
          client: 'waxdeck-flutter-test',
        ),
      );
      expect(mapped.sessionId, hasLength(26));
      expect(mapped.startedAt.isUtc, isTrue);
      expect(mapped.startedAt, startedLocal.toUtc());
      expect(mapped.msPlayed, 90500);
      expect(mapped.finished, isTrue);
      expect(mapped.client, 'waxdeck-flutter-test');
      expect(mapped.source_, gen.ListenSessionSource_Enum.live);
    });

    test('ingest outcomes carry over including rejections', () {
      final outcome = listenOutcomeFromGen(
        gen.ListenIngestResult(
          (b) => b
            ..accepted = 2
            ..duplicates = 1
            ..rejected.add(
              gen.RejectedListen(
                (r) => r
                  ..sessionId = 'S1'
                  ..code = 'not-found'
                  ..message = 'unknown item',
              ),
            ),
        ),
      );
      expect(outcome.accepted, 2);
      expect(outcome.duplicates, 1);
      expect(outcome.rejected, hasLength(1));
      expect(outcome.rejected.single.code, 'not-found');
    });
  });

  group('search mapping', () {
    test('groups carry over', () {
      final results = searchResultsFromGen(
        gen.SearchResults(
          (b) => b
            ..query = 'pony'
            ..tracks.add(
              gen.SearchHit(
                (h) => h
                  ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
                  ..kind = 'track'
                  ..title = 'Prancing Pony Blues'
                  ..subtitle = 'The Bree Trio',
              ),
            )
            ..truncated = true,
        ),
      );
      expect(results.query, 'pony');
      expect(results.tracks.single.subtitle, 'The Bree Trio');
      expect(results.artists, isEmpty);
      expect(results.truncated, isTrue);
    });
  });

  group('session ids', () {
    test('are 26 Crockford base32 characters and collision free', () {
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        final id = newListenSessionId();
        expect(id, hasLength(26));
        expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(id), isTrue);
        expect(seen.add(id), isTrue);
      }
    });
  });
}
