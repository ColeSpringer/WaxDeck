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

  group('podcast and book mapping', () {
    test('play-info carries part fields and defaults voiceBoost off', () {
      final expires = DateTime.utc(2026, 7, 18, 12);
      gen.PlayInfo base(void Function(gen.PlayInfoBuilder) extra) =>
          gen.PlayInfo((b) {
            b
              ..pid = 'bk-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
              ..url = '/media/stream?pid=bk-x&mt=abc'
              ..mimeType = 'audio/mp4'
              ..durationMs = 60000
              ..seekable = true
              ..expiresAt = expires;
            extra(b);
          });

      final single = playInfoFromGen(base((_) {}));
      expect(single.partIndex, isNull);
      expect(single.partCount, isNull);
      expect(single.partStartMs, isNull);
      expect(single.voiceBoost, isFalse);

      final part = playInfoFromGen(
        base(
          (b) => b
            ..partIndex = 1
            ..partCount = 3
            ..partStartMs = 60000
            ..voiceBoost = true,
        ),
      );
      expect(part.partIndex, 1);
      expect(part.partCount, 3);
      expect(part.partStartMs, 60000);
      expect(part.voiceBoost, isTrue);
    });

    test('episode summaries carry over with resolved art and defaults', () {
      final episode = episodeSummaryFromGen(
        gen.$EpisodeSummary(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001'
            ..mediaType = gen.MediaType.podcast
            ..title = 'Pipeweed Economics'
            ..durationMs = 214000
            ..artUrl = '/media/art?pid=tr-x'
            ..showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01'
            ..publishedAt = DateTime.utc(2026, 7, 10)
            ..downloaded = false
            ..fetchState = 'queued',
        ),
        baseUrl: 'http://host:4420',
      );
      expect(episode.mediaType, MediaType.podcast);
      expect(episode.artUrl, 'http://host:4420/media/art?pid=tr-x');
      expect(episode.showPid, 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01');
      expect(episode.downloaded, isFalse);
      expect(episode.fetchState, 'queued');
      expect(episode.explicit, isFalse);
      expect(episode.hasTranscript, isFalse);
      // Absent means false rather than null: an episode the server did
      // not mark playable must not read as playable.
      expect(episode.hasEnclosure, isFalse);
    });

    test(
      'an undownloaded episode still reports hasEnclosure when it plays',
      () {
        // The passthrough pair: not on the server, still playable, which
        // is what a client reads before offering play rather than fetch.
        final episode = episodeSummaryFromGen(
          gen.$EpisodeSummary(
            (b) => b
              ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0002'
              ..mediaType = gen.MediaType.podcast
              ..title = 'Second Breakfast'
              ..durationMs = 180000
              ..showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01'
              ..publishedAt = DateTime.utc(2026, 7, 11)
              ..downloaded = false
              ..hasEnclosure = true,
          ),
        );
        expect(episode.downloaded, isFalse);
        expect(episode.hasEnclosure, isTrue);
      },
    );

    test('show detail carries funding, medium, and person credits', () {
      final show = podcastShowFromGen(
        gen.PodcastShow(
          (b) => b
            ..pid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01'
            ..title = 'Second Breakfast'
            ..sourceType = 'rss'
            ..medium = 'podcast'
            ..funding.replace(
              gen.PodcastFunding(
                (f) => f
                  ..url = 'https://example.com/support'
                  ..message = 'Chip in',
              ),
            )
            ..persons.add(
              gen.FeedPerson(
                (p) => p
                  ..name = 'Merry'
                  ..role = 'host'
                  ..href = 'https://example.com/merry',
              ),
            ),
        ),
      );
      expect(show.medium, 'podcast');
      expect(show.funding?.url, 'https://example.com/support');
      expect(show.funding?.message, 'Chip in');
      expect(show.persons.single.name, 'Merry');
      expect(show.persons.single.role, 'host');
      expect(show.persons.single.href, 'https://example.com/merry');
    });

    test('a show without 2.0 extras keeps funding null and credits empty', () {
      final show = podcastShowFromGen(
        gen.PodcastShow(
          (b) => b
            ..pid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW02'
            ..title = 'Bare Feed'
            ..sourceType = 'rss',
        ),
      );
      expect(show.funding, isNull);
      expect(show.medium, isNull);
      expect(show.persons, isEmpty);
    });

    test('episode detail carries person credits and soundbites', () {
      final episode = episodeDetailFromGen(
        gen.Episode(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001'
            ..mediaType = gen.MediaType.podcast
            ..title = 'Pipeweed Economics'
            ..durationMs = 214000
            ..showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01'
            ..publishedAt = DateTime.utc(2026, 7, 10)
            ..downloaded = true
            ..persons.add(
              gen.FeedPerson(
                (p) => p
                  ..name = 'Pippin'
                  ..role = 'guest',
              ),
            )
            ..soundbites.add(
              gen.Soundbite(
                (s) => s
                  ..startMs = 5000
                  ..durationMs = 30000
                  ..title = 'Best bit',
              ),
            ),
        ),
      );
      expect(episode.persons.single.name, 'Pippin');
      expect(episode.persons.single.role, 'guest');
      expect(episode.soundbites.single.startMs, 5000);
      expect(episode.soundbites.single.durationMs, 30000);
      expect(episode.soundbites.single.title, 'Best bit');
    });

    test('subscription settings round trip through the wire shape', () {
      const settings = SubscriptionSettings(
        retentionKeep: 5,
        autoDownload: true,
        folder: 'News',
        speed: 1.5,
        trimSilence: true,
        skipIntroSeconds: 30,
      );
      final round = subscriptionSettingsFromGen(
        subscriptionSettingsToGen(settings),
      );
      expect(round.retentionKeep, 5);
      expect(round.autoDownload, isTrue);
      expect(round.folder, 'News');
      expect(round.private, isFalse);
      expect(round.speed, 1.5);
      expect(round.trimSilence, isTrue);
      expect(round.voiceBoost, isNull);
      expect(round.skipIntroSeconds, 30);
      expect(round.skipOutroSeconds, isNull);
    });

    test('the auto-download filter survives a settings round trip', () {
      // The PUT replaces the whole document, so a sender that dropped
      // this field would erase a filter the next time anyone saved a
      // speed or a trim toggle.
      const settings = SubscriptionSettings(
        autoDownload: true,
        autoDownloadFilter: EpisodeFilter(
          include: ['mailbag'],
          exclude: ['bonus', 'trailer'],
        ),
      );
      final round = subscriptionSettingsFromGen(
        subscriptionSettingsToGen(settings),
      );
      expect(round.autoDownloadFilter, isNotNull);
      expect(round.autoDownloadFilter!.include, ['mailbag']);
      expect(round.autoDownloadFilter!.exclude, ['bonus', 'trailer']);
    });

    test('a one-sided filter keeps the side it names and sends no other', () {
      const settings = SubscriptionSettings(
        autoDownload: true,
        autoDownloadFilter: EpisodeFilter(exclude: ['bonus']),
      );
      final wire = subscriptionSettingsToGen(settings);
      // The empty side is absent rather than an empty array, matching
      // what the server puts on the wire.
      expect(wire.autoDownloadFilter!.include, isNull);
      expect(wire.autoDownloadFilter!.exclude!.toList(), ['bonus']);
      final round = subscriptionSettingsFromGen(wire);
      expect(round.autoDownloadFilter!.exclude, ['bonus']);
      expect(round.autoDownloadFilter!.include, isEmpty);
    });

    test('no filter stays absent rather than becoming an empty one', () {
      const settings = SubscriptionSettings(autoDownload: true);
      final wire = subscriptionSettingsToGen(settings);
      expect(wire.autoDownloadFilter, isNull);
      expect(subscriptionSettingsFromGen(wire).autoDownloadFilter, isNull);
    });

    test('skip maps expose spans only when ready', () {
      final ready = skipMapFromGen(
        gen.SkipMap(
          (b) => b
            ..state = 'ready'
            ..spans.addAll([
              gen.SkipSpan(
                (s) => s
                  ..startMs = 5000
                  ..endMs = 15000,
              ),
            ]),
        ),
      );
      expect(ready.ready, isTrue);
      expect(ready.spans.single.endMs, 15000);

      final pending = skipMapFromGen(gen.SkipMap((b) => b..state = 'pending'));
      expect(pending.ready, isFalse);
      expect(pending.spans, isEmpty);
    });

    test('book detail maps chapters, parts, and settings', () {
      final book = bookDetailFromGen(
        gen.BookDetail(
          (b) => b
            ..pid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01'
            ..title = 'There And Back Again'
            ..authors.add('B. Baggins')
            ..narrators.add('Frodo')
            ..durationMs = 120000
            ..artUrl = '/media/art?pid=bk-x'
            ..chapters.add(
              gen.ChapterMark(
                (c) => c
                  ..index = 0
                  ..title = 'One'
                  ..startMs = 0,
              ),
            )
            ..parts.addAll([
              gen.BookPart(
                (p) => p
                  ..index = 0
                  ..startMs = 0
                  ..durationMs = 60000,
              ),
              gen.BookPart(
                (p) => p
                  ..index = 1
                  ..startMs = 60000
                  ..durationMs = 60000,
              ),
            ])
            ..settings.replace(gen.BookSettings((s) => s..speed = 1.25)),
        ),
        baseUrl: 'http://host:4420',
      );
      expect(book.artUrl, 'http://host:4420/media/art?pid=bk-x');
      expect(book.chapters.single.title, 'One');
      expect(book.parts, hasLength(2));
      expect(book.parts[1].startMs, 60000);
      expect(book.settings?.speed, 1.25);
    });

    test('sync payloads carry shows and the new event kinds', () {
      final page = catalogSyncPageFromGen(
        gen.CatalogSyncPage(
          (b) => b
            ..entries.add(
              gen.CatalogSyncEntry(
                (e) => e
                  ..op = 'upsert-show'
                  ..pid = 'pc-SHOW'
                  ..show_.replace(
                    gen.PodcastShow(
                      (s) => s
                        ..pid = 'pc-SHOW'
                        ..title = 'The Prancing Pony Hour'
                        ..sourceType = 'rss',
                    ),
                  ),
              ),
            )
            ..nextSince = 'cur-1',
        ),
      );
      final entry = page.entries.single;
      expect(entry.op, 'upsert-show');
      expect(entry.item, isNull);
      expect(entry.show?.title, 'The Prancing Pony Hour');

      final events = serverSyncPageFromGen(
        gen.ServerSyncPage(
          (b) => b
            ..events.add(
              gen.ServerSyncEvent(
                (e) => e
                  ..kind = 'book-settings'
                  ..pid = 'bk-BOOK'
                  ..bookSettings.replace(
                    gen.BookSettings((s) => s..speed = 2.0),
                  ),
              ),
            )
            ..nextSince = 'scur-1',
        ),
      );
      expect(events.events.single.kind, 'book-settings');
      expect(events.events.single.bookSettings?.speed, 2.0);
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
