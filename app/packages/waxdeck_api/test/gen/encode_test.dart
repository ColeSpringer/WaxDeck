import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/hand_models.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const noBase = WireContext(baseUrl: '');

final at = DateTime.utc(2024, 5, 1, 10);

ItemSummary track({String? artUrl, String? artist}) => ItemSummary(
  pid: 'tr-1',
  mediaType: MediaType.music,
  title: 'One',
  durationMs: 1000,
  artist: artist,
  artUrl: artUrl,
);

void main() {
  group('a date-time', () {
    DeviceSession session({required DateTime createdAt, DateTime? seen}) =>
        DeviceSession(
          id: 's-1',
          kind: SessionKind.web,
          createdAt: createdAt,
          lastSeenAt: seen,
          current: true,
        );

    test('is written in UTC even when the value is not', () {
      final local = at.toLocal();
      expect(local.isUtc, isFalse);
      expect(
        encodeDeviceSession(session(createdAt: local))['createdAt'],
        '2024-05-01T10:00:00.000Z',
      );
    });

    test('read with an offset is written as the same instant in UTC', () {
      final read = decodeDeviceSession({
        'id': 's-1',
        'kind': 'web',
        'createdAt': '2024-05-01T12:00:00+02:00',
        'current': true,
      }, noBase);
      expect(
        encodeDeviceSession(read)['createdAt'],
        '2024-05-01T10:00:00.000Z',
      );
    });

    test('is left out when an optional one is null, written when it is '
        'not', () {
      expect(
        encodeDeviceSession(session(createdAt: at)),
        isNot(contains('lastSeenAt')),
      );
      expect(
        encodeDeviceSession(session(createdAt: at, seen: at)),
        containsPair('lastSeenAt', '2024-05-01T10:00:00.000Z'),
      );
    });
  });

  group('a date', () {
    test('is written as its calendar day', () {
      expect(
        encodeHeatmapDay(HeatmapDay(date: at, ms: 5, sessions: 1)),
        containsPair('date', '2024-05-01'),
      );
      expect(
        encodeListeningBucket(
          ListeningBucket(
            start: DateTime.utc(2024, 12, 31, 23, 59),
            ms: 5,
            sessions: 1,
          ),
        ),
        containsPair('start', '2024-12-31'),
      );
    });

    test('goes back out as it came in', () {
      const json = <String, Object?>{
        'date': '2024-05-01',
        'ms': 5,
        'sessions': 1,
      };
      expect(encodeHeatmapDay(decodeHeatmapDay(json, noBase)), json);
    });
  });

  group('a byte string', () {
    test('is written as base64 text', () {
      final proposal = EnrichCoverProposal(
        provider: 'mb',
        data: Uint8List.fromList([1, 2, 3, 255]),
      );
      expect(encodeEnrichCoverProposal(proposal), {
        'provider': 'mb',
        'data': 'AQID/w==',
      });
    });

    test('goes back out as it came in', () {
      const json = <String, Object?>{'provider': 'mb', 'data': 'AQID/w=='};
      expect(
        encodeEnrichCoverProposal(decodeEnrichCoverProposal(json, noBase)),
        json,
      );
    });
  });

  group('a property that has a default', () {
    test('is sent even when it holds the default', () {
      expect(
        encodeNotificationTargetCreate(
          const NotificationTargetCreate(
            kind: 'webhook',
            config: {'url': 'https://hooks.example/x'},
            enabledEvents: ['scan.finished'],
          ),
        ),
        {
          'kind': 'webhook',
          'config': {'url': 'https://hooks.example/x'},
          'enabledEvents': ['scan.finished'],
          'muted': false,
          'minIntervalSeconds': 0,
        },
      );
    });

    test('is sent for each default kind of a settings object', () {
      expect(
        encodeAdminSettings(
          const AdminSettings(
            signupEnabled: false,
            readOnly: false,
            backupKeepCount: 3,
            backupKeepBytes: 0,
          ),
        ),
        {
          'signupEnabled': false,
          'readOnly': false,
          'sonicAnalysis': true,
          'radioExternalArt': false,
          'backupKeepCount': 3,
          'backupKeepBytes': 0,
          'trashRetentionDays': 0,
          'taskRetentionDays': 30,
        },
      );
    });
  });

  group('a nullable property', () {
    test('that is required is sent as an explicit null', () {
      final json = encodeRatingUpdate(const RatingUpdate(rating: null));
      expect(json, containsPair('rating', null));
      expect(json, isNot(contains('recordedAt')));
    });

    test('that is required is sent as its value when it has one', () {
      expect(encodeRatingUpdate(RatingUpdate(rating: 80, recordedAt: at)), {
        'rating': 80,
        'recordedAt': '2024-05-01T10:00:00.000Z',
      });
    });

    test('that is optional is left out when null', () {
      expect(encodeItemSummary(track()), isNot(contains('artist')));
      expect(
        encodeItemSummary(track(artist: 'Ada')),
        containsPair('artist', 'Ada'),
      );
    });
  });

  group('a list that is left out when empty', () {
    void leftOutWhenEmpty(
      String field,
      Map<String, Object?> Function() empty,
      Map<String, Object?> Function() filled,
      Object? sent,
    ) {
      final key = field.split('.').last;
      test('$field is absent when empty and sent when not', () {
        expect(empty(), isNot(contains(key)));
        expect(filled(), containsPair(key, sent));
      });
    }

    const rule = RuleNode.all();
    leftOutWhenEmpty(
      'SmartRule.sorts',
      () => encodeSmartRule(const SmartRule(root: rule)),
      () => encodeSmartRule(
        const SmartRule(
          root: rule,
          sorts: [RuleSort(field: 'rating', desc: true)],
        ),
      ),
      [
        {'field': 'rating', 'desc': true},
      ],
    );
    leftOutWhenEmpty(
      'GenreNode.aliases',
      () => encodeGenreNode(const GenreNode(name: 'rock')),
      () => encodeGenreNode(const GenreNode(name: 'rock', aliases: ['rock n'])),
      ['rock n'],
    );
    leftOutWhenEmpty(
      'MetadataCommit.credits',
      () => encodeMetadataCommit(const MetadataCommit()),
      () => encodeMetadataCommit(
        const MetadataCommit(
          credits: [
            CommitCredits(role: 'producer', names: ['Ada']),
          ],
        ),
      ),
      [
        {
          'role': 'producer',
          'names': ['Ada'],
        },
      ],
    );
    leftOutWhenEmpty(
      'MetadataCommit.tagRemoves',
      () => encodeMetadataCommit(const MetadataCommit()),
      () => encodeMetadataCommit(const MetadataCommit(tagRemoves: ['mood'])),
      ['mood'],
    );
    leftOutWhenEmpty(
      'LibraryAccess.libraryPids',
      () => encodeLibraryAccess(const LibraryAccess(mode: 'all')),
      () => encodeLibraryAccess(
        const LibraryAccess(mode: 'only', libraryPids: ['lb-1']),
      ),
      ['lb-1'],
    );
    leftOutWhenEmpty(
      'Permissions.tagAllow',
      () => encodePermissions(const Permissions()),
      () => encodePermissions(
        const Permissions(
          tagAllow: [TagRule(key: 'mood', value: 'calm')],
        ),
      ),
      [
        {'key': 'mood', 'value': 'calm'},
      ],
    );
    leftOutWhenEmpty(
      'Permissions.tagDeny',
      () => encodePermissions(const Permissions()),
      () =>
          encodePermissions(const Permissions(tagDeny: [TagRule(key: 'mood')])),
      [
        {'key': 'mood'},
      ],
    );
    leftOutWhenEmpty(
      'InstantMixRequest.excludePids',
      () => encodeInstantMixRequest(const InstantMixRequest()),
      () => encodeInstantMixRequest(
        const InstantMixRequest(excludePids: ['tr-9']),
      ),
      ['tr-9'],
    );
    leftOutWhenEmpty(
      'EpisodeFilter.include',
      () => encodeEpisodeFilter(const EpisodeFilter()),
      () => encodeEpisodeFilter(const EpisodeFilter(include: ['ad'])),
      ['ad'],
    );
    leftOutWhenEmpty(
      'EpisodeFilter.exclude',
      () => encodeEpisodeFilter(const EpisodeFilter()),
      () => encodeEpisodeFilter(const EpisodeFilter(exclude: ['ad'])),
      ['ad'],
    );

    leftOutWhenEmpty(
      'EnrichmentRunRequest.forcePhases',
      () => encodeEnrichmentRunRequest(const EnrichmentRunRequest()),
      () => encodeEnrichmentRunRequest(
        const EnrichmentRunRequest(forcePhases: ['group-art']),
      ),
      ['group-art'],
    );
    leftOutWhenEmpty(
      'EnrichmentRunRequest.phases',
      () => encodeEnrichmentRunRequest(const EnrichmentRunRequest()),
      () => encodeEnrichmentRunRequest(
        const EnrichmentRunRequest(phases: ['identity', 'group-art']),
      ),
      ['identity', 'group-art'],
    );

    group('and may also be null', () {
      leftOutWhenEmpty(
        'PlaylistCreate.itemPids',
        () => encodePlaylistCreate(
          const PlaylistCreate(name: 'Mix', kind: 'static', itemPids: []),
        ),
        () => encodePlaylistCreate(
          const PlaylistCreate(name: 'Mix', kind: 'static', itemPids: ['tr-1']),
        ),
        ['tr-1'],
      );
      leftOutWhenEmpty(
        'UpgradeResolveRequest.removeItemPids',
        () => encodeUpgradeResolveRequest(
          const UpgradeResolveRequest(keepItemPid: 'tr-1', removeItemPids: []),
        ),
        () => encodeUpgradeResolveRequest(
          const UpgradeResolveRequest(
            keepItemPid: 'tr-1',
            removeItemPids: ['tr-2'],
          ),
        ),
        ['tr-2'],
      );
      leftOutWhenEmpty(
        'UpgradeResolveRequest.removeFilePids',
        () => encodeUpgradeResolveRequest(
          const UpgradeResolveRequest(keepItemPid: 'tr-1', removeFilePids: []),
        ),
        () => encodeUpgradeResolveRequest(
          const UpgradeResolveRequest(
            keepItemPid: 'tr-1',
            removeFilePids: ['fi-2'],
          ),
        ),
        ['fi-2'],
      );

      test('PlaylistCreate.itemPids is absent when null', () {
        expect(
          encodePlaylistCreate(
            const PlaylistCreate(name: 'Mix', kind: 'static'),
          ),
          isNot(contains('itemPids')),
        );
      });
    });
  });

  group('a property that is left out at its default', () {
    void leftOutAtDefault(
      String field,
      Map<String, Object?> Function() atDefault,
      Map<String, Object?> Function() other,
      Object? sent,
    ) {
      final key = field.split('.').last;
      test('$field is absent at its default and sent otherwise', () {
        expect(atDefault(), isNot(contains(key)));
        expect(other(), containsPair(key, sent));
      });
    }

    const rule = RuleNode.all();
    SmartRule smartRule({int limit = 0, String mode = '', int seed = 0}) =>
        SmartRule(root: rule, limit: limit, limitMode: mode, limitSeed: seed);

    leftOutAtDefault(
      'MetadataCommit.clearLyrics',
      () => encodeMetadataCommit(const MetadataCommit()),
      () => encodeMetadataCommit(const MetadataCommit(clearLyrics: true)),
      true,
    );
    leftOutAtDefault(
      'MetadataCommit.tagSets',
      () => encodeMetadataCommit(const MetadataCommit()),
      () => encodeMetadataCommit(
        const MetadataCommit(
          tagSets: {
            'mood': ['calm'],
          },
        ),
      ),
      {
        'mood': ['calm'],
      },
    );
    leftOutAtDefault(
      'SmartRule.limit',
      () => encodeSmartRule(smartRule()),
      () => encodeSmartRule(smartRule(limit: 25)),
      25,
    );
    leftOutAtDefault(
      'SmartRule.limitMode',
      () => encodeSmartRule(smartRule()),
      () => encodeSmartRule(smartRule(mode: 'random')),
      'random',
    );
    leftOutAtDefault(
      'SmartRule.limitSeed',
      () => encodeSmartRule(smartRule()),
      () => encodeSmartRule(smartRule(seed: 7)),
      7,
    );
    leftOutAtDefault(
      'RuleSort.desc',
      () => encodeRuleSort(const RuleSort(field: 'rating')),
      () => encodeRuleSort(const RuleSort(field: 'rating', desc: true)),
      true,
    );

    test('SmartRule.limit sends a negative value as it is given', () {
      expect(encodeSmartRule(smartRule(limit: -5)), containsPair('limit', -5));
    });

    group('SubscriptionSettings.autoDownloadFilter', () {
      test('is absent when null or when it has no terms', () {
        expect(
          encodeSubscriptionSettings(const SubscriptionSettings()),
          isNot(contains('autoDownloadFilter')),
        );
        expect(
          encodeSubscriptionSettings(
            const SubscriptionSettings(autoDownloadFilter: EpisodeFilter()),
          ),
          isNot(contains('autoDownloadFilter')),
        );
      });

      test('is sent when it has terms', () {
        expect(
          encodeSubscriptionSettings(
            const SubscriptionSettings(
              autoDownloadFilter: EpisodeFilter(include: ['ad']),
            ),
          ),
          containsPair('autoDownloadFilter', {
            'include': ['ad'],
          }),
        );
      });
    });
  });

  group('a field the server defaults', () {
    // Null is the server's to default; the default itself, named, is sent.
    void sentOnceNamed(
      String field,
      Map<String, Object?> Function() unset,
      Map<String, Object?> Function() atDefault,
      Object? sent,
    ) {
      final key = field.split('.').last;
      test('$field is absent when unset and sent at its default', () {
        expect(unset(), isNot(contains(key)));
        expect(atDefault(), containsPair(key, sent));
      });
    }

    sentOnceNamed(
      'DeleteItemsRequest.mode',
      () => encodeDeleteItemsRequest(const DeleteItemsRequest(pids: ['tr-1'])),
      () => encodeDeleteItemsRequest(
        const DeleteItemsRequest(pids: ['tr-1'], mode: 'trash'),
      ),
      'trash',
    );
    sentOnceNamed(
      'DeleteItemFilesRequest.mode',
      () => encodeDeleteItemFilesRequest(
        const DeleteItemFilesRequest(filePids: ['fi-1']),
      ),
      () => encodeDeleteItemFilesRequest(
        const DeleteItemFilesRequest(filePids: ['fi-1'], mode: 'trash'),
      ),
      'trash',
    );
    sentOnceNamed(
      'InviteCreate.maxUses',
      () => encodeInviteCreate(const InviteCreate()),
      () => encodeInviteCreate(const InviteCreate(maxUses: 1)),
      1,
    );
    sentOnceNamed(
      'InstantMixRequest.adventurousness',
      () => encodeInstantMixRequest(const InstantMixRequest()),
      () => encodeInstantMixRequest(
        const InstantMixRequest(adventurousness: 0.4),
      ),
      0.4,
    );
    sentOnceNamed(
      'InstantMixRequest.size',
      () => encodeInstantMixRequest(const InstantMixRequest()),
      () => encodeInstantMixRequest(const InstantMixRequest(size: 50)),
      50,
    );
  });

  test('a list that is not marked is sent even when empty', () {
    expect(encodeEntityResolution(const EntityResolution(cards: [])), {
      'entities': <Object?>[],
      'departed': <Object?>[],
    });
  });

  test('a notification target config is sent without its null entries', () {
    const config = <String, Object?>{
      'url': 'https://hooks.example/x',
      'secret': null,
    };
    expect(
      encodeNotificationTargetCreate(
        const NotificationTargetCreate(
          kind: 'webhook',
          config: config,
          enabledEvents: [],
        ),
      ),
      containsPair('config', {'url': 'https://hooks.example/x'}),
    );
    expect(
      encodeNotificationTargetUpdate(
        const NotificationTargetUpdate(config: config, enabledEvents: []),
      ),
      containsPair('config', {'url': 'https://hooks.example/x'}),
    );
  });

  group('a parent that is an empty string', () {
    test('is sent as the value holds it, and left out when null', () {
      expect(
        encodeGenreNode(const GenreNode(name: 'metal', parent: '')),
        containsPair('parent', ''),
      );
      expect(
        encodeGenreNode(const GenreNode(name: 'metal')),
        isNot(contains('parent')),
      );
    });
  });

  group('an enum', () {
    test('is written as its wire name', () {
      expect(
        encodeEntityCard(
          const EntityCard(
            pid: 'rg-1',
            kind: EntityCardKind.releaseGroup,
            title: 'LP',
          ),
        ),
        containsPair('kind', 'release-group'),
      );
      expect(
        encodePrefs(const Prefs(theme: ThemePref.oled)),
        containsPair('theme', 'oled'),
      );
      expect(
        encodeUploadBatchCreate(
          const UploadBatchCreate(
            grouping: UploadGrouping.tracks,
            mediaType: 'music',
          ),
        ),
        containsPair('grouping', 'tracks'),
      );
    });

    test('is left out of a patch that does not set it', () {
      expect(encodePrefs(const Prefs()), isEmpty);
    });

    test('keeps every theme under its wire spelling, both ways', () {
      const spelling = {
        ThemePref.system: 'system',
        ThemePref.dark: 'dark',
        ThemePref.light: 'light',
        ThemePref.oled: 'oled',
      };
      expect(spelling.keys, unorderedEquals(ThemePref.values));
      for (final theme in ThemePref.values) {
        final wire = spelling[theme];
        expect(encodePrefs(Prefs(theme: theme)), {'theme': wire});
        expect(decodePrefs({'theme': wire}, noBase).theme, theme);
      }
    });
  });

  group('a media URL', () {
    test('is written as the value holds it', () {
      expect(
        encodeItemSummary(track(artUrl: 'https://wax.example/art/tr-1')),
        containsPair('artUrl', 'https://wax.example/art/tr-1'),
      );
    });

    test('goes back out as it came in when the base URL is empty', () {
      final json = encodeItemSummary(track(artUrl: '/api/v1/items/tr-1/art'));
      expect(encodeItemSummary(decodeItemSummary(json, noBase)), json);
    });
  });

  group('a property the Dart class names differently', () {
    test('is written under its wire key', () {
      expect(
        encodeWaxDeckUser(
          const WaxDeckUser(id: 'u-1', username: 'ada', canDelete: true),
        ),
        containsPair('delete', true),
      );
      expect(
        encodeEntityResolution(
          const EntityResolution(cards: [], departed: ['al-9']),
        ),
        {
          'entities': <Object?>[],
          'departed': ['al-9'],
        },
      );
    });

    test('is written as milliseconds for a duration', () {
      final upload = UploadSession(
        id: 'up-1',
        fileName: 'a.flac',
        sizeBytes: 10,
        receivedBytes: 5,
        idle: const Duration(seconds: 1, milliseconds: 500),
        mediaType: MediaType.music,
        state: 'receiving',
        createdAt: at,
      );
      expect(encodeUploadSession(upload), containsPair('idleMs', 1500));
    });

    test('is written as an error object for an exception', () {
      final part = MetadataCommitPart(
        part: MetadataCommitPartKind.lyrics,
        status: MetadataCommitStatus.refused,
        refusal: const WaxDeckApiException(
          code: 'forbidden',
          message: 'no',
          statusCode: 403,
          params: {'field': 'lyrics'},
        ),
      );
      expect(encodeMetadataCommitPart(part), {
        'part': 'lyrics',
        'status': 'refused',
        'refusal': {
          'code': 'forbidden',
          'message': 'no',
          'params': {'field': 'lyrics'},
        },
      });
    });

    test('is written as the base64 text it holds', () {
      expect(
        encodePortableRef(
          const PortableRef(
            kind: 'track',
            title: 'One',
            fingerprint: 'AQID/w==',
          ),
        ),
        containsPair('fingerprint', 'AQID/w=='),
      );
    });
  });

  group('a hand class', () {
    test('is written inside the generated class that holds it', () {
      final json = encodePlaylistCreate(
        const PlaylistCreate(
          name: 'Calm',
          kind: 'smart',
          rule: SmartRule(
            root: RuleNode.all([
              RuleNode.condition(field: 'rating', op: 'gte', value: '80'),
              RuleNode.condition(
                field: 'year',
                op: 'inTheRange',
                values: ['1990', '1999'],
              ),
            ]),
          ),
        ),
      );
      expect(json, containsPair('name', 'Calm'));
      expect(
        json['rule'],
        isA<Map<String, Object?>>().having((rule) => rule['root'], 'root', {
          'type': 'all',
          'nodes': [
            {
              'type': 'condition',
              'field': 'rating',
              'op': 'gte',
              'value': '80',
            },
            {
              'type': 'condition',
              'field': 'year',
              'op': 'inTheRange',
              'values': ['1990', '1999'],
            },
          ],
        }),
      );
    });

    test('writes whether a playlist has art from its art URL', () {
      const json = <String, Object?>{
        'pid': 'pl-1',
        'name': 'Mix',
        'kind': 'static',
        'visibility': 'private',
        'ownerName': 'ada',
        'isOwner': true,
        'hasArt': true,
        'createdAt': '2024-05-01T10:00:00Z',
        'updatedAt': '2024-05-01T10:00:00Z',
      };
      expect(encodePlaylist(decodePlaylist(json, noBase))['hasArt'], isTrue);
      expect(
        encodePlaylist(
          decodePlaylist({...json, 'hasArt': false}, noBase),
        )['hasArt'],
        isFalse,
      );
    });

    test('writes a rule tree as it came, its empty lists left out', () {
      const json = <String, Object?>{
        'type': 'all',
        'nodes': [
          {
            'type': 'condition',
            'field': 'rating',
            'op': 'inTheRange',
            'values': ['60', '80'],
          },
          {
            'type': 'not',
            'node': {'type': 'any'},
          },
        ],
      };
      expect(encodeRuleNode(decodeRuleNode(json, noBase)), json);
    });

    test('keeps the outcome name of an M3U line in a preview', () {
      final json = encodeM3uPreview(
        M3uPreview(
          matched: 1,
          merged: 0,
          unmatched: 1,
          lines: [
            M3uPreviewLine(
              path: 'a.flac',
              outcome: M3uLineOutcome.matched,
              item: track(),
            ),
            const M3uPreviewLine(
              path: 'b.flac',
              outcome: M3uLineOutcome.unmatched,
            ),
          ],
        ),
      );
      final lines = json['entries']! as List<Object?>;
      expect((lines.first! as Map)['outcome'], 'matched');
      expect((lines.first! as Map)['item'], containsPair('pid', 'tr-1'));
      expect(lines.last, {'path': 'b.flac', 'outcome': 'unmatched'});
    });

    test('writes the session switch under server', () {
      expect(
        encodeSessionState(
          const SessionState(authenticated: true, serverReadOnly: true),
        ),
        {
          'authenticated': true,
          'server': {'readOnly': true},
        },
      );
    });

    test('writes a session position in UTC', () {
      final info = PlaybackSessionInfo(
        id: 's-1',
        endpointId: 'e-1',
        mine: true,
        authority: 'remote',
        playing: true,
        index: 0,
        positionMs: 5,
        positionAt: at.toLocal(),
        rate: 1,
        queueVersion: 2,
        entries: const [PlaybackSessionEntry(pid: 'tr-1', title: 'One')],
      );
      final json = encodePlaybackSessionList(
        PlaybackSessionList(sessions: [info]),
      );
      final session = (json['sessions']! as List<Object?>).single! as Map;
      expect(session['positionAt'], '2024-05-01T10:00:00.000Z');
      expect(session['entries'], [
        {'pid': 'tr-1', 'title': 'One'},
      ]);
    });

    test('writes a session its decode reads back', () {
      // A socket frame reads leniently, a missing stamp included; what it
      // gives must still encode to an answer the codec takes.
      final info = PlaybackSessionInfo.fromWire({
        'id': 's-1',
        'endpointId': 'e-1',
        'mine': true,
        'authority': 'remote',
        'playing': true,
        'index': 0,
        'positionMs': 5,
        'positionAt': '2024-05-01T10:00:00Z',
        'rate': 1,
        'queueVersion': 2,
      });
      final again = decodePlaybackSessionInfo(
        encodePlaybackSessionInfo(info),
        noBase,
      );
      // Without one, the last change is the position's own.
      expect(info.updatedAt, info.positionAt);
      expect(again.id, info.id);
      expect(again.positionAt, info.positionAt);
      expect(again.updatedAt, info.updatedAt);
    });
  });

  group('an object read from JSON', () {
    test('goes back out as the JSON it came from', () {
      const json = <String, Object?>{
        'pid': 'nt-1',
        'kind': 'webhook',
        'scope': 'user',
        'label': 'Hook',
        'config': {'url': 'https://hooks.example/x'},
        'enabledEvents': ['scan.finished'],
        'lastError': 'timeout',
        'lastErrorAt': '2024-05-01T10:00:00.000Z',
        'muted': true,
        'minIntervalSeconds': 60,
        'createdAt': '2024-05-01T09:00:00.000Z',
      };
      expect(
        encodeNotificationTarget(decodeNotificationTarget(json, noBase)),
        json,
      );
    });
  });
}
