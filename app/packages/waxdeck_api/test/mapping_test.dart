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
            ..starred = true
            ..rating = 80,
        ),
      );
      expect(state.positionMs, 61500);
      expect(state.played, isTrue);
      expect(state.finished, isFalse);
      expect(state.playCount, 3);
      expect(state.starred, isTrue);
      expect(state.rating, 80);
      expect(state.updatedAt, isNull);
    });

    test('an unrated play-state keeps a null rating', () {
      final state = playStateFromGen(
        gen.PlayState(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..positionMs = 0
            ..played = false
            ..finished = false
            ..playCount = 0
            ..starred = false,
        ),
      );
      expect(state.rating, isNull);
    });
  });

  group('session mapping', () {
    test('device sessions carry over including the kind', () {
      final created = DateTime.utc(2026, 7, 1, 8);
      final seen = DateTime.utc(2026, 7, 18, 9);
      final session = deviceSessionFromGen(
        gen.DeviceSession(
          (b) => b
            ..id = 'se-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..kind = gen.DeviceSessionKindEnum.device
            ..deviceName = 'Pixel 9'
            ..client = 'waxdeck-flutter-android'
            ..createdAt = created
            ..lastSeenAt = seen
            ..current = true,
        ),
      );
      expect(session.id, 'se-01JZX5N8QW3F4V9T2B7KDEXAMPLE');
      expect(session.kind, SessionKind.device);
      expect(session.deviceName, 'Pixel 9');
      expect(session.client, 'waxdeck-flutter-android');
      expect(session.createdAt, created);
      expect(session.lastSeenAt, seen);
      expect(session.current, isTrue);
      expect(session.label, 'Pixel 9');
    });

    test('web sessions without labels fall back for display', () {
      final session = deviceSessionFromGen(
        gen.DeviceSession(
          (b) => b
            ..id = 'se-01JZX5N8QW3F4V9T2B7KDEXAMPL2'
            ..kind = gen.DeviceSessionKindEnum.web
            ..createdAt = DateTime.utc(2026, 7, 1)
            ..current = false,
        ),
      );
      expect(session.kind, SessionKind.web);
      expect(session.deviceName, isNull);
      expect(session.label, 'web');
    });
  });

  group('oidc mapping', () {
    test('start URLs resolve against the base for native clients', () {
      final provider = oidcProviderFromGen(
        gen.OidcProvider(
          (b) => b
            ..id = 'corp'
            ..displayName = 'Corp SSO'
            ..startUrl = '/api/v1/auth/oidc/start?provider=corp',
        ),
        baseUrl: 'http://host:4420',
      );
      expect(provider.id, 'corp');
      expect(provider.displayName, 'Corp SSO');
      expect(
        provider.startUrl,
        'http://host:4420/api/v1/auth/oidc/start?provider=corp',
      );
    });

    test('start URLs stay origin-relative with an empty base', () {
      final provider = oidcProviderFromGen(
        gen.OidcProvider(
          (b) => b
            ..id = 'corp'
            ..displayName = 'Corp SSO'
            ..startUrl = '/api/v1/auth/oidc/start?provider=corp',
        ),
      );
      expect(provider.startUrl, '/api/v1/auth/oidc/start?provider=corp');
    });
  });

  group('prefs mapping', () {
    test('themes round trip through the wire names', () {
      for (final theme in ThemePref.values) {
        expect(themePrefFromGen(themePrefToGen(theme)), theme);
      }
      expect(themePrefToGen(ThemePref.oled).name, 'oled');
    });

    test('fields carry over in both directions', () {
      final mapped = prefsFromGen(
        gen.Prefs(
          (b) => b
            ..timezone = 'Europe/Amsterdam'
            ..locale = 'en-US'
            ..theme = gen.PrefsThemeEnum.dark,
        ),
      );
      expect(mapped.timezone, 'Europe/Amsterdam');
      expect(mapped.locale, 'en-US');
      expect(mapped.theme, ThemePref.dark);

      final wire = prefsToGen(mapped.copyWith(theme: ThemePref.oled));
      expect(wire.timezone, 'Europe/Amsterdam');
      expect(wire.theme, gen.PrefsThemeEnum.oled);
    });

    test('empty prefs stay empty', () {
      final mapped = prefsFromGen(gen.Prefs((b) => b));
      expect(mapped.timezone, isNull);
      expect(mapped.locale, isNull);
      expect(mapped.theme, isNull);
      final wire = prefsToGen(mapped);
      expect(wire.theme, isNull);
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
