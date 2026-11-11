import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _noBase = WireContext(baseUrl: '');
const _host = WireContext(baseUrl: 'http://host:4420');

void main() {
  group('enum values', () {
    test('media types map one to one', () {
      MediaType decoded(String wire) => decodeItemSummary({
        'pid': 'tr-1',
        'mediaType': wire,
        'title': 'One',
        'durationMs': 1,
      }, _noBase).mediaType;
      expect(decoded('music'), MediaType.music);
      expect(decoded('podcast'), MediaType.podcast);
      expect(decoded('audiobook'), MediaType.audiobook);
      for (final type in MediaType.values) {
        final summary = ItemSummary(
          pid: 'tr-1',
          mediaType: type,
          title: 'One',
          durationMs: 1,
        );
        expect(
          decodeItemSummary(encodeItemSummary(summary), _noBase).mediaType,
          type,
        );
      }
    });

    test('discovery lists map to the wire names', () {
      for (final list in DiscoveryList.values) {
        expect(list.wireName, isNotEmpty);
      }
      expect(DiscoveryList.recentlyPlayed.wireName, 'recently-played');
      expect(DiscoveryList.alphabetical.wireName, 'alphabetical');
      expect(DiscoveryList.inProgress.wireName, 'in-progress');
    });
  });

  group('an item', () {
    Map<String, Object?> summary({String? artUrl}) => {
      'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      'mediaType': 'music',
      'title': 'Prancing Pony Blues',
      'artist': 'The Bree Trio',
      'album': 'Inn Sessions',
      'durationMs': 214000,
      'artUrl': ?artUrl,
    };

    test('summary fields carry over', () {
      final mapped = decodeItemSummary(
        summary(artUrl: '/api/v1/items/tr-x/art'),
        _host,
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
      expect(decodeItemSummary(summary(), _noBase).artUrl, isNull);
    });

    test('pages keep order and cursor', () {
      final mapped = decodeItemPage({
        'items': [summary()],
        'nextCursor': 'cursor-1',
      }, _noBase);
      expect(mapped.items, hasLength(1));
      expect(mapped.nextCursor, 'cursor-1');
      expect(mapped.hasMore, isTrue);
      expect(mapped.seed, isNull);

      final last = decodeItemPage({
        'items': [summary()],
      }, _noBase);
      expect(last.hasMore, isFalse);
    });

    test('random pages carry the effective seed through', () {
      final page = decodeItemPage({
        'items': [summary()],
        'seed': 42,
      }, _noBase);
      expect(page.seed, 42);
    });

    test('detail extends the summary with extra fields', () {
      final detail = decodeItemDetail({
        'pid': 'bk-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'mediaType': 'audiobook',
        'title': 'There And Back Again',
        'durationMs': 3600000,
        'year': 2024,
        'codec': 'flac',
        'genres': ['memoir'],
      }, _noBase);
      expect(detail.mediaType, MediaType.audiobook);
      expect(detail.year, 2024);
      expect(detail.codec, 'flac');
      expect(detail.genres, ['memoir']);
      expect(detail.trackNumber, isNull);
    });
  });

  group('playback', () {
    test('play-info resolves the stream URL against the base', () {
      final expires = DateTime.utc(2026, 7, 18, 12);
      final info = decodePlayInfo({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'url': '/media/stream?pid=tr-x&mt=abc',
        'mimeType': 'audio/flac',
        'durationMs': 214000,
        'seekable': true,
        'expiresAt': '2026-07-18T12:00:00Z',
      }, _host);
      expect(info.url, 'http://host:4420/media/stream?pid=tr-x&mt=abc');
      expect(info.mimeType, 'audio/flac');
      expect(info.durationMs, 214000);
      expect(info.seekable, isTrue);
      expect(info.expiresAt, expires);
      expect(info.appliedBitrateKbps, isNull);
    });

    test('play-info carries an applied bitrate cap through', () {
      final info = decodePlayInfo({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'url': '/media/stream?pid=tr-x&mt=abc&fmt=opus&br=192',
        'mimeType': 'audio/ogg',
        'durationMs': 214000,
        'seekable': false,
        'expiresAt': '2026-07-18T12:00:00Z',
        'appliedBitrateKbps': 192,
      }, _noBase);
      expect(info.appliedBitrateKbps, 192);
      expect(info.seekable, isFalse);
    });

    test('play-state fields carry over', () {
      final state = decodePlayState({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'positionMs': 61500,
        'played': true,
        'finished': false,
        'playCount': 3,
        'starred': true,
        'rating': 80,
      }, _noBase);
      expect(state.positionMs, 61500);
      expect(state.played, isTrue);
      expect(state.finished, isFalse);
      expect(state.playCount, 3);
      expect(state.starred, isTrue);
      expect(state.rating, 80);
      expect(state.updatedAt, isNull);
    });

    test('an unrated play-state keeps a null rating', () {
      final state = decodePlayState({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'positionMs': 0,
        'played': false,
        'finished': false,
        'playCount': 0,
        'starred': false,
      }, _noBase);
      expect(state.rating, isNull);
    });
  });

  group('a session', () {
    test('device sessions carry over including the kind', () {
      final created = DateTime.utc(2026, 7, 1, 8);
      final seen = DateTime.utc(2026, 7, 18, 9);
      final session = decodeDeviceSession({
        'id': 'se-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'kind': 'device',
        'deviceName': 'Pixel 9',
        'client': 'waxdeck-flutter-android',
        'createdAt': '2026-07-01T08:00:00Z',
        'lastSeenAt': '2026-07-18T09:00:00Z',
        'current': true,
      }, _noBase);
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
      final session = decodeDeviceSession({
        'id': 'se-01JZX5N8QW3F4V9T2B7KDEXAMPL2',
        'kind': 'web',
        'createdAt': '2026-07-01T00:00:00Z',
        'current': false,
      }, _noBase);
      expect(session.kind, SessionKind.web);
      expect(session.deviceName, isNull);
      expect(session.label, 'web');
    });
  });

  group('oidc', () {
    const provider = <String, Object?>{
      'id': 'corp',
      'displayName': 'Corp SSO',
      'startUrl': '/api/v1/auth/oidc/start?provider=corp',
    };

    test('start URLs resolve against the base for native clients', () {
      final decoded = decodeOidcProvider(provider, _host);
      expect(decoded.id, 'corp');
      expect(decoded.displayName, 'Corp SSO');
      expect(
        decoded.startUrl,
        'http://host:4420/api/v1/auth/oidc/start?provider=corp',
      );
    });

    test('start URLs stay origin-relative with an empty base', () {
      final decoded = decodeOidcProvider(provider, _noBase);
      expect(decoded.startUrl, '/api/v1/auth/oidc/start?provider=corp');
    });
  });

  group('prefs', () {
    test('fields carry over in both directions', () {
      final mapped = decodePrefs({
        'timezone': 'Europe/Amsterdam',
        'locale': 'en-US',
        'theme': 'dark',
      }, _noBase);
      expect(mapped.timezone, 'Europe/Amsterdam');
      expect(mapped.locale, 'en-US');
      expect(mapped.theme, ThemePref.dark);

      final wire = encodePrefs(mapped.copyWith(theme: ThemePref.oled));
      expect(wire['timezone'], 'Europe/Amsterdam');
      // Deprecated on the wire, still mapped: the one-time adoption
      // reads it and third-party clients may still write it.
      expect(wire['theme'], 'oled');
    });

    test('empty prefs stay empty', () {
      final mapped = decodePrefs(const {}, _noBase);
      expect(mapped.timezone, isNull);
      expect(mapped.locale, isNull);
      expect(mapped.theme, isNull);
      final wire = encodePrefs(mapped);
      expect(wire['theme'], isNull);
    });
  });

  group('a listen session', () {
    test('sessions serialize with UTC timestamps', () {
      final startedLocal = DateTime(2026, 7, 18, 9, 30);
      final mapped = encodeListenSession(
        ListenSession(
          sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ012345'.substring(0, 26),
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          startedAt: startedLocal,
          msPlayed: 90500,
          finished: true,
          client: 'waxdeck-flutter-test',
        ),
      );
      final startedAt = DateTime.parse(mapped['startedAt']! as String);
      expect(mapped['sessionId'], hasLength(26));
      expect(startedAt.isUtc, isTrue);
      expect(startedAt, startedLocal.toUtc());
      expect(mapped['msPlayed'], 90500);
      expect(mapped['finished'], isTrue);
      expect(mapped['client'], 'waxdeck-flutter-test');
    });

    test('a session goes out with a live source', () {
      final mapped = encodeListenSession(
        ListenSession(
          sessionId: 'ABCDEFGHJKMNPQRSTVWXYZ012345'.substring(0, 26),
          pid: 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
          startedAt: DateTime.utc(2026, 7, 18, 9, 30),
          msPlayed: 90500,
        ),
      );
      expect(mapped['source'], 'live');
    });

    test('ingest outcomes carry over including rejections', () {
      final outcome = decodeListenOutcome({
        'accepted': 2,
        'duplicates': 1,
        'rejected': [
          {'sessionId': 'S1', 'code': 'not-found', 'message': 'unknown item'},
        ],
      }, _noBase);
      expect(outcome.accepted, 2);
      expect(outcome.duplicates, 1);
      expect(outcome.rejected, hasLength(1));
      expect(outcome.rejected.single.code, 'not-found');
    });
  });

  group('search', () {
    test('groups carry over', () {
      final results = decodeSearchResults({
        'query': 'pony',
        'artists': <Object?>[],
        'albums': <Object?>[],
        'tracks': [
          {
            'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
            'kind': 'track',
            'title': 'Prancing Pony Blues',
            'subtitle': 'The Bree Trio',
          },
        ],
        'books': <Object?>[],
        'episodes': <Object?>[],
        'truncated': true,
      }, _noBase);
      expect(results.query, 'pony');
      expect(results.tracks.single.subtitle, 'The Bree Trio');
      expect(results.artists, isEmpty);
      expect(results.truncated, isTrue);
    });
  });

  group('podcasts and books', () {
    test('play-info carries part fields and defaults voiceBoost off', () {
      PlayInfo base(Map<String, Object?> extra) => decodePlayInfo({
        'pid': 'bk-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'url': '/media/stream?pid=bk-x&mt=abc',
        'mimeType': 'audio/mp4',
        'durationMs': 60000,
        'seekable': true,
        'expiresAt': '2026-07-18T12:00:00Z',
        ...extra,
      }, _noBase);

      final single = base(const {});
      expect(single.partIndex, isNull);
      expect(single.partCount, isNull);
      expect(single.partStartMs, isNull);
      expect(single.voiceBoost, isFalse);

      final part = base(const {
        'partIndex': 1,
        'partCount': 3,
        'partStartMs': 60000,
        'voiceBoost': true,
      });
      expect(part.partIndex, 1);
      expect(part.partCount, 3);
      expect(part.partStartMs, 60000);
      expect(part.voiceBoost, isTrue);
    });

    test('play-info carries where a cut stream begins, zero when uncut', () {
      PlayInfo info(Map<String, Object?> extra) => decodePlayInfo({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'url': '/media/stream?pid=tr-x&mt=abc&t=90',
        'mimeType': 'audio/ogg',
        'durationMs': 214000,
        'seekable': false,
        'expiresAt': '2026-10-15T12:00:00Z',
        ...extra,
      }, _noBase);
      expect(info(const {}).startOffsetMs, 0);
      expect(info(const {'startOffsetMs': 90000}).startOffsetMs, 90000);
    });

    test('episode summaries carry over with resolved art and defaults', () {
      final episode = decodeEpisodeSummary({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        'mediaType': 'podcast',
        'title': 'Pipeweed Economics',
        'durationMs': 214000,
        'artUrl': '/media/art?pid=tr-x',
        'showPid': 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
        'publishedAt': '2026-07-10T00:00:00Z',
        'downloaded': false,
        'fetchState': 'queued',
      }, _host);
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
        final episode = decodeEpisodeSummary({
          'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEP0002',
          'mediaType': 'podcast',
          'title': 'Second Breakfast',
          'durationMs': 180000,
          'showPid': 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
          'publishedAt': '2026-07-11T00:00:00Z',
          'downloaded': false,
          'hasEnclosure': true,
        }, _noBase);
        expect(episode.downloaded, isFalse);
        expect(episode.hasEnclosure, isTrue);
      },
    );

    test('show detail carries funding, medium, and person credits', () {
      final show = decodePodcastShow({
        'pid': 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
        'title': 'Second Breakfast',
        'sourceType': 'rss',
        'medium': 'podcast',
        'funding': {'url': 'https://example.com/support', 'message': 'Chip in'},
        'persons': [
          {
            'name': 'Merry',
            'role': 'host',
            'href': 'https://example.com/merry',
          },
        ],
      }, _noBase);
      expect(show.medium, 'podcast');
      expect(show.funding?.url, 'https://example.com/support');
      expect(show.funding?.message, 'Chip in');
      expect(show.persons.single.name, 'Merry');
      expect(show.persons.single.role, 'host');
      expect(show.persons.single.href, 'https://example.com/merry');
    });

    test('a show without 2.0 extras keeps funding null and credits empty', () {
      final show = decodePodcastShow({
        'pid': 'pc-01JZX5N8QW3F4V9T2B7KDSHOW02',
        'title': 'Bare Feed',
        'sourceType': 'rss',
      }, _noBase);
      expect(show.funding, isNull);
      expect(show.medium, isNull);
      expect(show.persons, isEmpty);
    });

    test('episode detail carries person credits and soundbites', () {
      final episode = decodeEpisodeDetail({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEP0001',
        'mediaType': 'podcast',
        'title': 'Pipeweed Economics',
        'durationMs': 214000,
        'showPid': 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01',
        'publishedAt': '2026-07-10T00:00:00Z',
        'downloaded': true,
        'persons': [
          {'name': 'Pippin', 'role': 'guest'},
        ],
        'soundbites': [
          {'startMs': 5000, 'durationMs': 30000, 'title': 'Best bit'},
        ],
      }, _noBase);
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
      final round = decodeSubscriptionSettings(
        encodeSubscriptionSettings(settings),
        _noBase,
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
      final round = decodeSubscriptionSettings(
        encodeSubscriptionSettings(settings),
        _noBase,
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
      final wire = encodeSubscriptionSettings(settings);
      final filter = wire['autoDownloadFilter']! as Map<String, Object?>;
      // The empty side is absent rather than an empty array, matching
      // what the server puts on the wire.
      expect(filter, isNot(contains('include')));
      expect(filter['exclude'], ['bonus']);
      final round = decodeSubscriptionSettings(wire, _noBase);
      expect(round.autoDownloadFilter!.exclude, ['bonus']);
      expect(round.autoDownloadFilter!.include, isEmpty);
    });

    test('no filter stays absent rather than becoming an empty one', () {
      const settings = SubscriptionSettings(autoDownload: true);
      final wire = encodeSubscriptionSettings(settings);
      expect(wire, isNot(contains('autoDownloadFilter')));
      expect(
        decodeSubscriptionSettings(wire, _noBase).autoDownloadFilter,
        isNull,
      );
    });

    test('skip maps expose spans only when ready', () {
      final ready = decodeSkipMap({
        'state': 'ready',
        'spans': [
          {'startMs': 5000, 'endMs': 15000},
        ],
      }, _noBase);
      expect(ready.ready, isTrue);
      expect(ready.spans.single.endMs, 15000);

      final pending = decodeSkipMap({'state': 'pending'}, _noBase);
      expect(pending.ready, isFalse);
      expect(pending.spans, isEmpty);
    });

    test('book detail maps chapters, parts, settings, and the author', () {
      final book = decodeBookDetail({
        'pid': 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01',
        'title': 'There And Back Again',
        'authors': ['B. Baggins'],
        'authorPid': 'ar-01JZX5N8QW3F4V9T2B7KDAUTHOR',
        'narrators': ['Frodo'],
        'durationMs': 120000,
        'artUrl': '/media/art?pid=bk-x',
        'chapters': [
          {'index': 0, 'title': 'One', 'startMs': 0},
        ],
        'parts': [
          {'index': 0, 'startMs': 0, 'durationMs': 60000},
          {'index': 1, 'startMs': 60000, 'durationMs': 60000},
        ],
        'settings': {'speed': 1.25},
      }, _host);
      expect(book.artUrl, 'http://host:4420/media/art?pid=bk-x');
      expect(book.chapters.single.title, 'One');
      expect(book.parts, hasLength(2));
      expect(book.parts[1].startMs, 60000);
      expect(book.settings?.speed, 1.25);
      expect(book.authorPid, 'ar-01JZX5N8QW3F4V9T2B7KDAUTHOR');
    });

    test('sync payloads carry shows and the new event kinds', () {
      final page = decodeCatalogSyncPage({
        'entries': [
          {
            'op': 'upsert-show',
            'pid': 'pc-SHOW',
            'show': {
              'pid': 'pc-SHOW',
              'title': 'The Prancing Pony Hour',
              'sourceType': 'rss',
            },
          },
        ],
        'nextSince': 'cur-1',
      }, _noBase);
      final entry = page.entries.single;
      expect(entry.op, 'upsert-show');
      expect(entry.item, isNull);
      expect(entry.show?.title, 'The Prancing Pony Hour');

      final events = decodeServerSyncPage({
        'events': [
          {
            'kind': 'book-settings',
            'pid': 'bk-BOOK',
            'bookSettings': {'speed': 2.0},
          },
        ],
        'nextSince': 'scur-1',
      }, _noBase);
      expect(events.events.single.kind, 'book-settings');
      expect(events.events.single.bookSettings?.speed, 2.0);
    });

    test('a bookmarks event carries the book\'s list, empty included', () {
      final page = decodeServerSyncPage(<String, Object?>{
        'nextSince': 'scur-2',
        'events': <Object?>[
          <String, Object?>{
            'kind': 'bookmarks',
            'pid': 'bk-BOOK',
            'bookmarks': <Object?>[
              <String, Object?>{
                'id': 'bm-01JZX5N8QW3F4V9T2B7KD3M9R6',
                'positionMs': 1500,
                'note': 'the turn',
                'createdAt': '2026-09-27T12:00:00Z',
              },
            ],
          },
          <String, Object?>{
            'kind': 'bookmarks',
            'pid': 'bk-EMPTY',
            'bookmarks': <Object?>[],
          },
          <String, Object?>{'kind': 'prefs'},
        ],
      }, _noBase);
      final marks = page.events[0].bookmarks!;
      expect(marks.single.id, 'bm-01JZX5N8QW3F4V9T2B7KD3M9R6');
      expect(marks.single.positionMs, 1500);
      expect(marks.single.note, 'the turn');
      expect(page.events[1].bookmarks, isEmpty);
      expect(page.events[2].bookmarks, isNull);
    });
  });

  group('a portable ref', () {
    test('a ref keeps where its fingerprint was stored, both ways', () {
      final ref = decodePortableRef({
        'kind': 'track',
        'title': 'One',
        'fingerprintBucket': 4,
      }, _noBase);
      expect(ref.fingerprintBucket, 4);
      expect(encodePortableRef(ref)['fingerprintBucket'], 4);
    });
  });

  group('health', () {
    test('an issue carries the lengths a rule measured', () {
      final issue = decodeHealthIssue({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'title': 'Half Song',
        'mediaType': 'music',
        'rules': ['duration-mismatch'],
        'detail': {
          'headerMs': 4000,
          'decodedMs': 8000,
          'partIndex': 2,
          'wholeFile': true,
        },
      }, _noBase);
      expect(issue.detail?.headerMs, 4000);
      expect(issue.detail?.decodedMs, 8000);
      expect(issue.detail?.partIndex, 2);
      expect(issue.detail?.wholeFile, isTrue);
    });

    test('a rule says what blocks its fix or that one runs, and a summary '
        'its sweep', () {
      final summary = decodeHealthSummary({
        'score': 80,
        'totalItems': 4,
        'evaluatedItems': 4,
        'warmingUp': false,
        'sweeping': true,
        'sweepFailed': true,
        'rules': [
          {
            'rule': 'missing-lyrics',
            'failing': 4,
            'fixable': false,
            'fixing': false,
            'fixBlocked': 'needs-contact',
          },
          {
            'rule': 'write-unsynced',
            'failing': 1,
            'fixable': true,
            'fixing': true,
          },
        ],
      }, _noBase);
      expect(summary.sweeping, isTrue);
      expect(summary.sweepFailed, isTrue);
      expect(summary.rules.first.fixBlocked, 'needs-contact');
      expect(summary.rules.first.fixing, isFalse);
      expect(summary.rules.last.fixBlocked, isNull);
      expect(summary.rules.last.fixing, isTrue);
    });

    test('a started fix names where it runs', () {
      final job = decodeHealthFixStart({
        'queued': 4,
        'jobPid': 'jb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
      }, _noBase);
      expect(job.queued, 4);
      expect(job.jobPid, 'jb-01JZX5N8QW3F4V9T2B7KDEXAMPL');
      expect(job.taskId, isNull);
    });

    test('an issue that measured nothing carries no detail', () {
      final issue = decodeHealthIssue({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'title': 'Plain Song',
        'mediaType': 'music',
        'rules': ['missing-art'],
      }, _noBase);
      expect(issue.detail, isNull);
    });
  });

  group('a job', () {
    test('a running job says how far it is, and nothing when it cannot', () {
      Job running(double? progress) => decodeJob({
        'pid': 'jb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'kind': 'scan',
        'state': 'running',
        'progress': ?progress,
      }, _noBase);
      expect(running(0.42).progress, 0.42);
      expect(running(null).progress, isNull);
    });

    test('a finished job carries when it ran and what it did', () {
      final job = decodeJob({
        'pid': 'jb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'kind': 'scan',
        'state': 'done',
        'startedAt': '2026-09-29T10:00:00Z',
        'finishedAt': '2026-09-29T10:02:00Z',
        'result': {'created': 3, 'errored': 0},
      }, _noBase);
      expect(job.startedAt, DateTime.utc(2026, 9, 29, 10));
      expect(job.finishedAt, DateTime.utc(2026, 9, 29, 10, 2));
      expect(job.result, {'created': 3, 'errored': 0});
    });

    test('a created library says whether its scan started', () {
      final lib = decodeLibraryInfo({
        'pid': 'lb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'name': 'extra',
        'readOnly': false,
        'managed': true,
        'profile': 'waxbin-native',
        'scanStarted': false,
      }, _noBase);
      expect(lib.scanStarted, isFalse);
      expect(lib.managed, isTrue);
      expect(lib.profile, 'waxbin-native');
    });

    test('a targeted job names its target', () {
      final job = decodeJob({
        'pid': 'jb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'kind': 'enrich',
        'state': 'running',
        'target': {
          'type': 'item',
          'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPL',
          'name': 'Amber Waves',
        },
      }, _noBase);
      expect(job.target?.type, 'item');
      expect(job.target?.pid, 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPL');
      expect(job.target?.name, 'Amber Waves');
    });
  });

  group('organize and trash', () {
    test('a profile carries its templates and samples', () {
      final profile = decodeOrganizeProfile({
        'name': 'flat',
        'musicTemplate': '{title}.{ext}',
        'audiobookTemplate': '{title}/{title}.{ext}',
        'podcastTemplate': '{podcast}/{episode}.{ext}',
        'tagWrite': true,
        'builtIn': false,
        'sample': {
          'music': 'Amber Waves.flac',
          'audiobook': 'The Long Harbor/The Long Harbor.m4b',
          'podcast': 'Night Shift Radio/The Lighthouse Keeper.mp3',
          'compilation':
              'Various Artists/Coastal Nights (2023)/1-04 - Night Drive.flac',
        },
      }, _noBase);
      expect(profile.musicTemplate, '{title}.{ext}');
      expect(profile.tagWrite, isTrue);
      expect(profile.builtIn, isFalse);
      expect(
        profile.sample.podcast,
        'Night Shift Radio/The Lighthouse Keeper.mp3',
      );
    });

    test('a trash entry names its library', () {
      final entry = decodeTrashEntry({
        'id': 'th-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'name': 'Album/01 Track.flac',
        'reason': 'user',
        'sizeBytes': 10,
        'trashedAt': '2026-09-30T00:00:00Z',
        'libraryPid': 'lb-01JZX5N8QW3F4V9T2B7KDEXAMPL',
        'libraryName': 'music',
      }, _noBase);
      expect(entry.libraryPid, 'lb-01JZX5N8QW3F4V9T2B7KDEXAMPL');
      expect(entry.libraryName, 'music');
    });
  });

  group('facet pages', () {
    FacetPage page(Map<String, Object?> bucket) => decodeFacetPage({
      'dimension': 'artist',
      'buckets': [bucket],
    }, _noBase);

    test('carry the rail letter the server computed', () {
      final decoded = page({
        'key': 'ar-1',
        'label': 'Edith Piaf',
        'count': 3,
        'letter': 'E',
      });
      expect(decoded.buckets.single.letter, 'E');
    });

    test('leave it null when the server does not send one', () {
      final decoded = page({'key': 'ar-1', 'label': 'Edith Piaf', 'count': 3});
      expect(decoded.buckets.single.letter, isNull);
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
