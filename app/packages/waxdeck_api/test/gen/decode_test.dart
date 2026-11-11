import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/hand_models.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../support/last_run.dart';

const ctx = WireContext(baseUrl: 'https://wax.example');
const noBase = WireContext(baseUrl: '');

const track = <String, Object?>{
  'pid': 'tr-1',
  'mediaType': 'music',
  'title': 'One',
  'durationMs': 1000,
};

const session = <String, Object?>{
  'id': 's-1',
  'kind': 'web',
  'createdAt': '2024-05-01T10:00:00Z',
  'current': true,
};

const playbackSession = <String, Object?>{
  'id': 'ps-1',
  'endpointId': 'pe-1',
  'mine': true,
  'authority': 'remote',
  'playing': false,
  'index': 0,
  'positionMs': 0,
  'positionAt': '2024-05-01T10:00:00Z',
  'rate': 1,
  'queueVersion': 3,
  'updatedAt': '2024-05-01T10:00:00Z',
};

const admin = <String, Object?>{
  'signupEnabled': false,
  'readOnly': false,
  'backupKeepCount': 3,
  'backupKeepBytes': 0,
};

const target = <String, Object?>{
  'pid': 'nt-1',
  'kind': 'webhook',
  'scope': 'user',
  'config': <String, Object?>{},
  'enabledEvents': <String>[],
  'createdAt': '2024-05-01T10:00:00Z',
};

const coverageCount = <String, Object?>{'enriched': 0, 'total': 0};

const enrichmentStatus = <String, Object?>{
  'providers': <Object?>[],
  'coverage': {
    'artists': coverageCount,
    'releaseGroups': coverageCount,
    'books': coverageCount,
    'lyrics': coverageCount,
    'lyricsAsked': 0,
  },
  'running': false,
  'configured': true,
  'musicbrainzConfigured': false,
  'phases': <String>[],
};

const playlist = <String, Object?>{
  'pid': 'pl-1',
  'name': 'Mix',
  'kind': 'static',
  'visibility': 'private',
  'ownerName': 'ada',
  'isOwner': true,
  'createdAt': '2024-05-01T10:00:00Z',
  'updatedAt': '2024-05-01T10:00:00Z',
};

Map<String, Object?> card(String pid, String kind) => {
  'pid': pid,
  'kind': kind,
  'title': pid,
};

void main() {
  group('a wire value this build does not know', () {
    test('is kept as the free-form string a browse sort is, and written '
        'back', () {
      const wire = <String, Object?>{
        'browseSorts': <String, Object?>{
          'album': 'hologram-order',
          'genre': 'count',
        },
      };
      final prefs = decodePrefs(wire, noBase);
      expect(prefs.browseSorts, {'album': 'hologram-order', 'genre': 'count'});
      expect(encodePrefs(prefs)['browseSorts'], wire['browseSorts']);
    });

    test('reads as music for a media type; a known one is kept', () {
      MediaType read(String wire) =>
          decodeItemSummary({...track, 'mediaType': wire}, ctx).mediaType;
      expect(read('hologram'), MediaType.music);
      expect(read('audiobook'), MediaType.audiobook);
    });

    test('reads as music for a stats media type; radio is kept', () {
      StatsMediaType read(String wire) => decodeMediaTypeListening({
        'mediaType': wire,
        'ms': 5,
        'sessions': 1,
      }, ctx).mediaType;
      expect(read('tape'), StatsMediaType.music);
      expect(read('radio'), StatsMediaType.radio);
    });

    test('reads as a device for a session kind; web is kept', () {
      SessionKind read(String wire) =>
          decodeDeviceSession({...session, 'kind': wire}, ctx).kind;
      expect(read('toaster'), SessionKind.device);
      expect(read('web'), SessionKind.web);
    });

    test('reads as the system theme; oled is kept; absent stays null', () {
      ThemePref? read(Map<String, Object?> json) =>
          decodePrefs(json, ctx).theme;
      expect(read({'theme': 'sepia'}), ThemePref.system);
      expect(read({'theme': 'oled'}), ThemePref.oled);
      expect(read({}), isNull);
    });

    test('reads as auto for an upload grouping; tracks is kept', () {
      UploadGrouping read(String wire) => decodeUploadBatchCreate({
        'grouping': wire,
        'mediaType': 'music',
      }, ctx).grouping;
      expect(read('by-mood'), UploadGrouping.auto);
      expect(read('tracks'), UploadGrouping.tracks);
    });

    test('reads as a metadata basis for a mix; sonic is kept', () {
      MixBasis read(String wire) =>
          decodeInstantMix({'basis': wire, 'items': <Object?>[]}, ctx).basis;
      expect(read('vibes'), MixBasis.metadata);
      expect(read('sonic'), MixBasis.sonic);
    });

    test('drops the card of a kind this build does not know, keeps the '
        'rest in order', () {
      final resolution = decodeEntityResolution({
        'entities': [
          card('al-1', 'album'),
          card('mx-1', 'mixtape'),
          card('ar-1', 'artist'),
        ],
      }, ctx);
      expect([for (final c in resolution.cards) c.pid], ['al-1', 'ar-1']);
      expect(resolution.cards.last.kind, EntityCardKind.artist);
    });

    test('refuses a card that is not an object, rather than dropping it', () {
      expect(
        () => decodeEntityResolution({
          'entities': [card('al-1', 'album'), 7],
        }, ctx),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('EntityResolution.entities[1]'),
          ),
        ),
      );
    });

    test('reads as unmatched, without its item, in an M3U preview', () {
      final preview = decodeM3uPreview({
        'matched': 1,
        'merged': 1,
        'unmatched': 1,
        'entries': [
          {'path': 'a.flac', 'outcome': 'matched', 'item': track},
          {
            'path': 'b.flac',
            'outcome': 'teleported',
            'item': {...track, 'pid': 'tr-2'},
          },
          {
            'path': 'c.flac',
            'outcome': 'merged',
            'item': {...track, 'pid': 'tr-3'},
          },
        ],
      }, ctx);
      expect(
        [for (final line in preview.lines) line.outcome],
        [
          M3uLineOutcome.matched,
          M3uLineOutcome.unmatched,
          M3uLineOutcome.merged,
        ],
      );
      expect(
        [for (final line in preview.lines) line.item?.pid],
        ['tr-1', null, 'tr-3'],
      );
    });

    test('reads as renamed for a rename outcome; merged is kept', () {
      EntityRenameOutcome read(String wire) => decodeEntityRenameResult({
        'entityPid': 'ar-1',
        'outcome': wire,
        'members': 1,
        'credits': 0,
      }, ctx).outcome;
      expect(read('teleported'), EntityRenameOutcome.renamed);
      expect(read('merged'), EntityRenameOutcome.merged);
    });

    test('reads as unknown for a commit part kind; lyrics is kept', () {
      MetadataCommitPartKind read(String wire) => decodeMetadataCommitPart({
        'part': wire,
        'status': 'committed',
      }, ctx).part;
      expect(read('cuneiform'), MetadataCommitPartKind.unknown);
      expect(read('lyrics'), MetadataCommitPartKind.lyrics);
    });

    test('reads as unknown for a commit status; refused is kept', () {
      MetadataCommitStatus read(String wire) => decodeMetadataCommitPart({
        'part': 'fields',
        'status': wire,
      }, ctx).status;
      expect(read('maybe'), MetadataCommitStatus.unknown);
      expect(read('refused'), MetadataCommitStatus.refused);
    });

    test('reads as an empty code for an organize hold; a known one is '
        'kept', () {
      String read(String wire) => decodeOrganizeHold({
        'from': 'a.flac',
        'code': wire,
        'reason': 'why',
      }, ctx).code;
      expect(read('novel'), '');
      expect(read('read-only'), 'read-only');
    });

    test('reads as organize for an organize batch kind; undo is kept', () {
      String read(String wire) => decodeOrganizeBatch({
        'jobPid': 'jb-1',
        'kind': wire,
        'state': 'done',
        'startedAt': '2024-05-01T10:00:00Z',
        'committed': 1,
        'rolledBack': 0,
        'planned': 1,
        'undoable': true,
      }, ctx).kind;
      expect(read('novel'), 'organize');
      expect(read('organize-undo'), 'organize-undo');
    });

    test('is dropped from an enrichment status phase list', () {
      final status = decodeEnrichmentStatus({
        ...enrichmentStatus,
        'phases': ['identity', 'novel', 'lyrics'],
      }, ctx);
      expect(status.phases, ['identity', 'lyrics']);
    });

    test('is dropped from the phases a last run stalled on', () {
      final run = decodeEnrichmentLastRun(
        lastRun(['lyrics', 'novel', 'identity']),
        ctx,
      );
      expect(run.stalled, ['lyrics', 'identity']);
    });

    test('drops a schedule of a kind this build does not know from the '
        'list', () {
      Map<String, Object?> schedule(String kind) => {
        'kind': kind,
        'cron': '0 3 * * *',
        'enabled': true,
      };
      final list = decodeScheduleList({
        'schedules': [schedule('scan'), schedule('defrag'), schedule('backup')],
      }, ctx);
      expect([for (final s in list.schedules) s.kind], ['scan', 'backup']);
    });

    test('keeps a schedule kind as sent when the schedule is read on its '
        'own', () {
      final schedule = decodeSchedule({
        'kind': 'defrag',
        'cron': '0 3 * * *',
        'enabled': true,
      }, ctx);
      expect(schedule.kind, 'defrag');
    });
  });

  group('date-time', () {
    DeviceSession read(String createdAt) =>
        decodeDeviceSession({...session, 'createdAt': createdAt}, ctx);

    test('reads an offset as the same instant in UTC', () {
      final at = read('2024-05-01T12:00:00+02:00').createdAt;
      expect(at, DateTime.utc(2024, 5, 1, 10));
      expect(at.isUtc, isTrue);
    });

    test('reads a Z timestamp and its fraction in UTC', () {
      final at = read('2024-05-01T10:00:00.250Z').createdAt;
      expect(at, DateTime.utc(2024, 5, 1, 10, 0, 0, 250));
      expect(at.isUtc, isTrue);
    });

    test('is null when an optional one is absent', () {
      expect(read('2024-05-01T10:00:00Z').lastSeenAt, isNull);
    });

    test('fails the decode for text that is no timestamp, naming the '
        'field', () {
      expect(
        () => read('last tuesday'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('DeviceSession.createdAt'),
          ),
        ),
      );
    });
  });

  group('date', () {
    HeatmapDay read(String date) =>
        decodeHeatmapDay({'date': date, 'ms': 5, 'sessions': 1}, ctx);

    test('reads a full date as that day at midnight UTC', () {
      final date = read('2024-05-01').date;
      expect(date, DateTime.utc(2024, 5, 1));
      expect(date.isUtc, isTrue);
    });

    test('fails the decode for a day that does not exist', () {
      expect(() => read('2024-02-30'), throwsFormatException);
    });

    test('fails the decode for a timestamp where a date belongs', () {
      expect(() => read('2024-05-01T00:00:00Z'), throwsFormatException);
    });

    test('is read by another date field the same way', () {
      final bucket = decodeListeningBucket({
        'start': '2024-12-31',
        'ms': 5,
        'sessions': 1,
      }, ctx);
      expect(bucket.start, DateTime.utc(2024, 12, 31));
    });
  });

  group('byte', () {
    EnrichCoverProposal read(String data) =>
        decodeEnrichCoverProposal({'provider': 'mb', 'data': data}, ctx);

    test('reads base64 text as bytes', () {
      final data = read('AQID/w==').data;
      expect(data, isA<Uint8List>());
      expect(data, [1, 2, 3, 255]);
    });

    test('fails the decode for text that is not base64, naming the '
        'field', () {
      expect(
        () => read('not base64!'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('EnrichCoverProposal.data'),
          ),
        ),
      );
    });
  });

  group('a property with a default', () {
    test('is false when absent', () {
      final read = decodeNotificationTarget(target, ctx);
      expect(read.muted, isFalse);
    });

    test('is 0 when absent', () {
      final read = decodeNotificationTarget(target, ctx);
      expect(read.minIntervalSeconds, 0);
    });

    test('is an empty list that cannot be changed when absent', () {
      final read = decodeGenreNode({'name': 'rock'}, ctx);
      expect(read.aliases, isEmpty);
      expect(() => read.aliases.add('x'), throwsUnsupportedError);
    });

    test('is true when absent', () {
      expect(decodeAdminSettings(admin, ctx).sonicAnalysis, isTrue);
    });

    test('is an empty string when absent', () {
      final read = decodeEnrichFieldProposal({
        'name': 'title',
        'proposed': 'One',
        'provider': 'mb',
      }, ctx);
      expect(read.current, '');
    });

    test('is 30 when absent', () {
      expect(decodeAdminSettings(admin, ctx).taskRetentionDays, 30);
    });

    test('is an empty map when absent', () {
      expect(decodeMetadataCommit(<String, Object?>{}, ctx).tagSets, isEmpty);
    });

    test('is the value the JSON holds when it holds one', () {
      final read = decodeAdminSettings({
        ...admin,
        'sonicAnalysis': false,
        'taskRetentionDays': 7,
      }, ctx);
      expect(read.sonicAnalysis, isFalse);
      expect(read.taskRetentionDays, 7);
    });

    test('is the default when the JSON holds null', () {
      final read = decodeAdminSettings({
        ...admin,
        'sonicAnalysis': null,
        'taskRetentionDays': null,
      }, ctx);
      expect(read.sonicAnalysis, isTrue);
      expect(read.taskRetentionDays, 30);
    });

    test('is still required when the schema requires it: the decode fails '
        'without it', () {
      expect(
        () => decodeInstantMix({'basis': 'sonic'}, ctx),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'InstantMix.items: missing',
          ),
        ),
      );
    });
  });

  group('an empty string read as absent', () {
    String? read(Map<String, Object?> extra) =>
        decodeGenreNode({'name': 'metal', ...extra}, ctx).parent;

    test('is null for an empty parent', () {
      expect(read({'parent': ''}), isNull);
    });

    test('keeps a parent that holds text', () {
      expect(read({'parent': 'rock'}), 'rock');
    });

    test('is null for a parent that is absent or null', () {
      expect(read({}), isNull);
      expect(read({'parent': null}), isNull);
    });
  });

  group('a media URL', () {
    String? art(WireContext on, String? url) =>
        decodeItemSummary({...track, 'artUrl': ?url}, on).artUrl;

    test('resolves against the base URL', () {
      expect(
        art(ctx, '/api/v1/items/tr-1/art'),
        'https://wax.example/api/v1/items/tr-1/art',
      );
    });

    test('resolves against a base URL that ends in a slash', () {
      expect(
        art(
          const WireContext(baseUrl: 'https://wax.example/'),
          '/api/v1/items/tr-1/art',
        ),
        'https://wax.example/api/v1/items/tr-1/art',
      );
    });

    test('passes through unchanged when it is already absolute', () {
      expect(
        art(ctx, 'https://cdn.example/a.jpg'),
        'https://cdn.example/a.jpg',
      );
    });

    test('stays relative when the base URL is empty', () {
      expect(art(noBase, '/api/v1/items/tr-1/art'), '/api/v1/items/tr-1/art');
    });

    test('is null when absent', () {
      expect(art(ctx, null), isNull);
    });

    test('resolves a required URL field the same way', () {
      final provider = decodeOidcProvider({
        'id': 'corp',
        'displayName': 'Corp',
        'startUrl': '/auth/oidc/corp/start',
      }, ctx);
      expect(provider.startUrl, 'https://wax.example/auth/oidc/corp/start');
    });
  });

  group('a property the Dart class names differently', () {
    test('reads a renamed property from its wire key', () {
      final user = decodeWaxDeckUser({
        'id': 'u-1',
        'username': 'ada',
        'roles': <String>[],
        'uploadEnabled': false,
        'delete': true,
      }, ctx);
      expect(user.canDelete, isTrue);
    });

    test('reads milliseconds as a duration', () {
      final upload = decodeUploadSession({
        'id': 'up-1',
        'fileName': 'a.flac',
        'sizeBytes': 10,
        'receivedBytes': 5,
        'idleMs': 1500,
        'mediaType': 'music',
        'state': 'receiving',
        'createdAt': '2024-05-01T10:00:00Z',
      }, ctx);
      expect(upload.idle, const Duration(milliseconds: 1500));
    });

    test('reads an error object as the exception the client throws', () {
      final part = decodeMetadataCommitPart({
        'part': 'lyrics',
        'status': 'refused',
        'refusal': {
          'code': 'forbidden',
          'message': 'no',
          'params': {'field': 'lyrics'},
        },
      }, ctx);
      expect(part.refusal?.code, 'forbidden');
      expect(part.refusal?.message, 'no');
      expect(part.refusal?.params, {'field': 'lyrics'});
      expect(part.refusal?.statusCode, isNull);
    });

    test('reads an error object as an HTTP error body reads', () {
      MetadataCommitPart refused(Object? refusal) => decodeMetadataCommitPart({
        'part': 'lyrics',
        'status': 'refused',
        'refusal': refusal,
      }, ctx);
      // Params keep only their string entries, here as there.
      expect(
        refused({
          'code': 'forbidden',
          'message': 'no',
          'params': {'field': 'lyrics', 'count': 2},
        }).refusal?.params,
        {'field': 'lyrics'},
      );
      // Anything but a string code and message is no error object, and the
      // failure names the member.
      for (final (notOne, member) in <(Map<String, Object?>, String)>[
        ({'message': 'no'}, 'code: missing'),
        ({'code': 'forbidden'}, 'message: missing'),
        ({'code': 403, 'message': 'no'}, 'code: expected a string, got int'),
        ({'code': 'forbidden', 'message': null}, 'message: null'),
      ]) {
        expect(
          () => refused(notOne),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'MetadataCommitPart.refusal.$member',
            ),
          ),
          reason: '$notOne',
        );
      }
    });

    test('keeps a byte string as its base64 text', () {
      final ref = decodePortableRef({
        'kind': 'track',
        'title': 'One',
        'fingerprint': 'AQID/w==',
      }, ctx);
      expect(ref.fingerprint, 'AQID/w==');
    });
  });

  group('synced lyrics', () {
    test('decode in the order the server sent them', () {
      final lyrics = decodeLyrics({
        'pid': 'tr-1',
        'source': 'enrichment',
        'synced': [
          {'timeMs': 1000, 'text': 'a'},
          {'timeMs': 1000, 'text': 'b'},
          {'timeMs': 2000, 'text': 'c'},
        ],
      }, ctx);
      expect([for (final line in lyrics.synced) line.text], ['a', 'b', 'c']);
    });
  });

  test('two decodes of one object are two objects, not equal ones', () {
    final first = decodeItemSummary(track, ctx);
    final second = decodeItemSummary(track, ctx);
    expect(first == second, isFalse);
    expect(first.pid, second.pid);
  });

  group('a key this build does not know', () {
    test('is ignored, at the top of an object and inside a list in it', () {
      final read = decodeItemPage({
        'items': [
          {...track, 'addedByANewerServer': true},
        ],
        'nextCursor': 'c-2',
        'alsoNew': {'x': 1},
      }, ctx);
      expect(read.items.single.pid, 'tr-1');
      expect(read.nextCursor, 'c-2');
    });
  });

  group('a schema that extends another', () {
    test('decodes to the classes it extends, grandchildren included', () {
      final detail = decodeEpisodeDetail({
        ...track,
        'mediaType': 'podcast',
        'showPid': 'pc-1',
        'publishedAt': '2024-05-01T10:00:00Z',
        'downloaded': false,
      }, ctx);
      expect(detail, isA<EpisodeSummary>());
      expect(detail, isA<ItemSummary>());
    });
  });

  group('a hand class', () {
    test('reads a matched M3U line with its item', () {
      final line = decodeM3uPreviewLine({
        'path': 'a.flac',
        'outcome': 'matched',
        'item': track,
      }, ctx);
      expect(line.outcome, M3uLineOutcome.matched);
      expect(line.item?.pid, 'tr-1');
    });

    test('reads its art URL from hasArt when a playlist page holds it', () {
      final page = decodePlaylistPage({
        'playlists': [
          {...playlist, 'hasArt': true},
          {...playlist, 'pid': 'pl-2', 'hasArt': false},
          {...playlist, 'pid': 'pl-3'},
        ],
        'nextCursor': 'c-2',
      }, ctx);
      expect(page.playlists.map((p) => p.artUrl), [
        'https://wax.example/api/v1/items/pl-1/art',
        null,
        null,
      ]);
      expect(page.nextCursor, 'c-2');
    });

    test('leaves its art URL relative when the base URL is empty', () {
      final page = decodePlaylistPage({
        'playlists': [
          {...playlist, 'hasArt': true},
        ],
      }, noBase);
      expect(page.playlists.single.artUrl, '/api/v1/items/pl-1/art');
    });

    test('reads a rule tree when a smart playlist holds it', () {
      final page = decodePlaylistPage({
        'playlists': [
          {
            ...playlist,
            'kind': 'smart',
            'rule': {
              'root': {
                'type': 'all',
                'nodes': [
                  {
                    'type': 'condition',
                    'field': 'rating',
                    'op': 'gte',
                    'value': '80',
                  },
                  {
                    'type': 'not',
                    'node': {'type': 'any'},
                  },
                ],
              },
              'limit': 25,
            },
          },
        ],
      }, ctx);
      final rule = page.playlists.single.rule!;
      expect(rule.limit, 25);
      expect(rule.root.type, 'all');
      expect(rule.root.nodes.first.field, 'rating');
      expect(rule.root.nodes.first.value, '80');
      expect(rule.root.nodes.last.node?.type, 'any');
    });

    test('reads a playback session and its entries from a session list', () {
      final list = decodePlaybackSessionList({
        'sessions': [
          {
            ...playbackSession,
            'positionAt': '2024-05-01T12:00:00+02:00',
            'entries': [
              {'pid': 'tr-1', 'title': 'One', 'durationMs': 1000},
              {'pid': '', 'title': ''},
            ],
          },
        ],
      }, ctx);
      final info = list.sessions.single;
      expect(info.positionAt, DateTime.utc(2024, 5, 1, 10));
      expect(info.authority, 'remote');
      expect(info.rate, 1.0);
      expect(info.entries.map((e) => e.withheld), [false, true]);
      expect(info.currentEntry?.pid, 'tr-1');
    });

    group('a playback session read from a REST answer', () {
      // One field of each kind the contract requires: a string, a boolean,
      // an integer, a number and a date-time.
      for (final field in const [
        'id',
        'endpointId',
        'authority',
        'mine',
        'playing',
        'index',
        'positionMs',
        'queueVersion',
        'rate',
        'positionAt',
        'updatedAt',
      ]) {
        test('refuses an answer without its $field', () {
          expect(
            () => decodePlaybackSessionInfo({
              for (final MapEntry(:key, :value) in playbackSession.entries)
                if (key != field) key: value,
            }, ctx),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'PlaybackSessionInfo.$field: missing',
              ),
            ),
          );
        });
      }

      for (final field in const ['pid', 'title']) {
        test('refuses an entry without its $field', () {
          expect(
            () => decodePlaybackSessionEntry(
              {'pid': 'tr-1', 'title': 'One'}..remove(field),
              ctx,
            ),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                'PlaybackSessionEntry.$field: missing',
              ),
            ),
          );
        });
      }

      test('refuses an entry of the queue that lacks one', () {
        expect(
          () => decodePlaybackSessionInfo({
            ...playbackSession,
            'entries': [
              {'title': 'One'},
            ],
          }, ctx),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'PlaybackSessionEntry.pid: missing',
            ),
          ),
        );
      });

      test('does not need what the contract leaves optional', () {
        final info = decodePlaybackSessionInfo(playbackSession, ctx);
        expect(info.entries, isEmpty);
        expect(info.endpointName, isNull);
        expect(info.shuffle, isFalse);
        expect(info.ended, isFalse);
      });
    });

    test('is lenient in a WebSocket frame, which fromWire reads', () {
      final frame = PlaybackSessionInfo.fromWire(<String, dynamic>{});
      expect(frame.id, '');
      expect(frame.authority, 'remote');
      expect(frame.rate, 1.0);
      expect(frame.entries, isEmpty);
      expect(frame.updatedAt, frame.positionAt);
    });

    test('reads the entries of a session in the history', () {
      final history = decodePlaybackSessionHistoryEntry({
        'id': 's-1',
        'endpointId': 'e-1',
        'authority': 'mirror',
        'index': 1,
        'positionMs': 5,
        'positionAt': '2024-05-01T10:00:00Z',
        'rate': 1,
        'entries': [
          {'pid': 'tr-1', 'title': 'One'},
          {'pid': 'tr-2', 'title': 'Two', 'artist': 'Ada'},
        ],
      }, ctx);
      expect(history.rate, 1.0);
      expect(history.entries.map((e) => e.title), ['One', 'Two']);
      expect(history.entries.last.artist, 'Ada');
    });
  });
}
