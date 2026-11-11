import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _ctx = WireContext(baseUrl: '');

/// The JSON bodies [adapter] was sent, in order.
List<Map<Object?, Object?>> _sent(RecordingAdapter adapter) => [
  for (final r in adapter.requests) r.data as Map<Object?, Object?>,
];

void main() {
  group('review', () {
    Map<String, Object?> best() => {
      'mbid': 'mb-best',
      'title': 'Inn Sessions',
      'artist': 'The Bree Trio',
      'year': 2019,
      'similarityPct': 97.5,
    };

    test('detail carries candidates, pairings, and tracks through', () {
      final detail = decodeReviewEntryDetail({
        'id': 're-01JZX5N8QW3F4V9T2B7KDREVIEW',
        'kind': 'import',
        'status': 'pending',
        'mediaType': 'music',
        'origin': 'upload',
        'title': 'Inn Sessions',
        'artist': 'The Bree Trio',
        'trackCount': 2,
        'uploadedBy': 'barliman',
        'identifying': false,
        'best': best(),
        'createdAt': '2026-07-01T00:00:00Z',
        'candidates': [
          {
            'mbid': 'mb-best',
            'releaseGroupMbid': 'mb-group',
            'title': 'Inn Sessions',
            'artist': 'The Bree Trio',
            'year': 2019,
            'trackCount': 2,
            'country': 'NL',
            'similarityPct': 97.5,
            'components': [
              {'name': 'tracks', 'distance': 0.02, 'weight': 0.5},
            ],
            'pairings': [
              {
                'trackIndex': 0,
                'position': 1,
                'disc': 1,
                'title': 'Prancing Pony Blues',
                'durationMs': 214000,
                'recordingMbid': 'mb-rec',
                'distance': 0.01,
              },
            ],
            'missingTitles': ['Hidden Track'],
            'extraTrackIndexes': [1],
          },
        ],
        'tracks': [
          {
            'path': 'inbox/pony.flac',
            'title': 'Prancing Pony Blues',
            'trackNo': 1,
            'durationMs': 214000,
          },
        ],
      }, _ctx);

      expect(detail.id, 're-01JZX5N8QW3F4V9T2B7KDREVIEW');
      expect(detail.kind, 'import');
      expect(detail.status, 'pending');
      expect(detail.mediaType, MediaType.music);
      expect(detail.origin, 'upload');
      expect(detail.best?.mbid, 'mb-best');
      expect(detail.best?.similarityPct, 97.5);
      expect(detail.decidedAt, isNull);

      final candidate = detail.candidates.single;
      expect(candidate.releaseGroupMbid, 'mb-group');
      expect(candidate.components.single.name, 'tracks');
      expect(candidate.components.single.weight, 0.5);
      final pairing = candidate.pairings.single;
      expect(pairing.trackIndex, 0);
      expect(pairing.position, 1);
      expect(pairing.recordingMbid, 'mb-rec');
      expect(candidate.missingTitles, ['Hidden Track']);
      expect(candidate.extraTrackIndexes, [1]);

      final track = detail.tracks.single;
      expect(track.pid, isNull);
      expect(track.path, 'inbox/pony.flac');
      expect(track.trackNo, 1);
    });

    test('absent breakdowns and empty pairings map to empty lists', () {
      final candidate = decodeReviewCandidate({
        'mbid': 'mb-min',
        'title': 'Inn Sessions',
        'artist': 'The Bree Trio',
        'similarityPct': 80,
        'pairings': <Object?>[],
      }, _ctx);
      expect(candidate.components, isEmpty);
      expect(candidate.pairings, isEmpty);
      expect(candidate.missingTitles, isEmpty);
      expect(candidate.extraTrackIndexes, isEmpty);
    });

    test('decision actions go out by wire name, including as-is', () async {
      final adapter = RecordingAdapter.refusing();
      final client = clientOn(adapter);
      for (final action in ['approve', 'as-is']) {
        await expectLater(
          client.decideReviewEntry('rv-1', action: action),
          throwsA(isA<WaxDeckApiException>()),
        );
      }
      for (final action in ['as-is', 'discard']) {
        await expectLater(
          client.decideReviewBulk(const ['rv-1'], action: action),
          throwsA(isA<WaxDeckApiException>()),
        );
      }
      expect(
        [for (final body in _sent(adapter)) body['action']],
        ['approve', 'as-is', 'as-is', 'discard'],
      );
    });

    test('matching modes roundtrip, including off', () {
      for (final mode in ['auto', 'review', 'off']) {
        for (final singles in [false, true]) {
          final matching = LibraryMatching(
            mode: mode,
            singlesAutoApply: singles,
          );
          final round = decodeLibraryMatching(
            encodeLibraryMatching(matching),
            _ctx,
          );
          expect(round.mode, mode);
          expect(round.singlesAutoApply, singles);
        }
      }
    });

    test('a bulk outcome carries its code and warnings', () {
      final refused = decodeReviewBulkOutcome({
        'entryId': 'rv-1',
        'ok': false,
        'code': 'catalog-busy',
        'error': 'busy',
      }, _ctx);
      expect(refused.code, 'catalog-busy');
      expect(refused.warnings, isEmpty);
      final stood = decodeReviewBulkOutcome({
        'entryId': 'rv-2',
        'ok': true,
        'warnings': ['one.flac: tags not written'],
      }, _ctx);
      expect(stood.warnings, ['one.flac: tags not written']);
    });

    test('stats default their optional counters to zero', () {
      final stats = decodeReviewStats({
        'pending': 3,
        'decided': 9,
        'applied': 2,
        'autoApplied': 5,
        'reverted': 1,
        'revertedAutoApplied': 0,
      }, _ctx);
      expect(stats.pending, 3);
      expect(stats.decided, 9);
      expect(stats.identifying, 0);
      expect(stats.asIs, 0);
      expect(stats.skipped, 0);
    });
  });

  group('uploads', () {
    test('session with a duplicate warning carries through', () {
      final page = decodeUploadPage({
        'uploads': [
          {
            'id': 'up-01JZX5N8QW3F4V9T2B7KDUPLOAD',
            'fileName': 'pony.flac',
            'sizeBytes': 4096,
            'receivedBytes': 4096,
            'idleMs': 4200,
            'mediaType': 'music',
            'libraryPid': 'li-01JZX5N8QW3F4V9T2B7KDLIB',
            'state': 'staged',
            'reviewEntryId': 're-01JZX5N8QW3F4V9T2B7KDREVIEW',
            'duplicate': {
              'itemPid': 'tr-01JZX5N8QW3F4V9T2B7KDEXIST',
              'kind': 'fingerprint',
              'title': 'Prancing Pony Blues',
              'artist': 'The Bree Trio',
            },
            'uploadedBy': 'barliman',
            'createdAt': '2026-07-01T00:00:00Z',
            'expiresAt': '2026-07-02T00:00:00Z',
          },
        ],
        'nextCursor': 'cursor-1',
      }, _ctx);

      expect(page.nextCursor, 'cursor-1');
      expect(page.hasMore, isTrue);
      final upload = page.uploads.single;
      expect(upload.id, 'up-01JZX5N8QW3F4V9T2B7KDUPLOAD');
      expect(upload.state, 'staged');
      expect(upload.receivedBytes, 4096);
      expect(upload.idle, const Duration(milliseconds: 4200));
      expect(upload.reviewEntryId, 're-01JZX5N8QW3F4V9T2B7KDREVIEW');
      expect(upload.duplicate?.itemPid, 'tr-01JZX5N8QW3F4V9T2B7KDEXIST');
      expect(upload.duplicate?.kind, 'fingerprint');
      expect(upload.expiresAt, DateTime.utc(2026, 7, 2));
    });

    test('a fresh session has no duplicate and no review entry', () {
      final upload = decodeUploadSession({
        'id': 'up-min',
        'fileName': 'pony.flac',
        'sizeBytes': 4096,
        'receivedBytes': 0,
        'idleMs': 0,
        'mediaType': 'audiobook',
        'state': 'receiving',
        'createdAt': '2026-07-01T00:00:00Z',
      }, _ctx);
      expect(upload.mediaType, MediaType.audiobook);
      expect(upload.duplicate, isNull);
      expect(upload.reviewEntryId, isNull);
      expect(upload.expiresAt, isNull);
    });
  });

  group('a library', () {
    Map<String, Object?> library({bool? declared}) => <String, Object?>{
      'pid': 'lb-1',
      'name': 'books',
      'media': 'audiobook',
      'mediaDeclared': ?declared,
      'readOnly': false,
      'managed': false,
    };

    test('a library the configuration declares says so', () {
      LibraryInfo listed(Map<String, Object?> json) =>
          decodeLibraryInfo(json, _ctx);
      expect(listed(library(declared: true)).mediaDeclared, isTrue);
      expect(listed(library(declared: false)).mediaDeclared, isFalse);
      expect(listed(library()).mediaDeclared, isFalse);
      final created = decodeLibraryInfo({
        ...library(declared: true),
        'scanStarted': true,
      }, _ctx);
      expect(created.mediaDeclared, isTrue);
    });
  });

  group('the genre vocabulary', () {
    test('the source reads in its wire spelling', () {
      GenreTree tree(String source) =>
          decodeGenreTree({'source': source, 'genres': <Object?>[]}, _ctx);
      expect(tree('default').source, 'default');
      expect(tree('default').isDefault, isTrue);
      expect(tree('custom').source, 'custom');
      expect(tree('custom').isDefault, isFalse);
    });
  });

  group('item files', () {
    test('a copy says why it is one, off the wire', () {
      final files = decodeItemFiles(<String, Object?>{
        'files': <Object?>[
          <String, Object?>{
            'filePid': 'fi-own',
            'role': 'primary',
            'name': 'Harbour Lights.flac',
          },
          <String, Object?>{
            'filePid': 'fi-copy',
            'role': 'alternate',
            'name': 'Harbour Lights (1).flac',
            'reason': 'same-audio',
          },
          <String, Object?>{
            'filePid': 'fi-mp3',
            'role': 'alternate',
            'name': 'Harbour Lights.mp3',
            'reason': 'other-encoding',
          },
        ],
      }, _ctx).files;
      expect(files.map((f) => (f.filePid, f.isCopy, f.reason)), [
        ('fi-own', false, null),
        ('fi-copy', true, 'same-audio'),
        ('fi-mp3', true, 'other-encoding'),
      ]);
    });
  });

  group('item metadata', () {
    test('the full editor payload carries through', () {
      final meta = decodeItemMetadata({
        'pid': 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
        'mediaType': 'music',
        'fields': {'title': 'Prancing Pony Blues', 'artist': 'The Bree Trio'},
        'lockedFields': ['title'],
        'provenance': [
          {
            'field': 'title',
            'source': 'user',
            'locked': true,
            'updatedAt': '2026-07-01T00:00:00Z',
          },
        ],
        'credits': [
          {
            'role': 'composer',
            'names': ['B. Butterbur'],
          },
        ],
        'lyrics': {
          'synced': true,
          'source': 'provider',
          'lrc': '[00:01.00]At the sign of the pony',
        },
        'chapters': [
          {'index': 0, 'title': 'Opening', 'startMs': 0, 'endMs': 60000},
        ],
        'customTags': [
          {
            'key': 'MOOD',
            'values': ['cozy'],
          },
        ],
        'unofficial': false,
        'virtualTrack': true,
        'hasArtwork': true,
        'hasOwnArtwork': true,
        'albumPid': 'al-01JZX5N8QW3F4V9T2B7KDALBUM',
        'artistPid': 'ar-01JZX5N8QW3F4V9T2B7KDARTIST',
        'writeBackIssues': [
          {
            'filePid': 'fi-01JZX5N8QW3F4V9T2B7KDFILE',
            'code': 'synced-lyrics-unsupported',
            'tagKey': 'LYRICS',
            'detail': 'MP4 refuses embedded synced lyrics',
          },
        ],
      }, _ctx);

      expect(meta.fields, {
        'title': 'Prancing Pony Blues',
        'artist': 'The Bree Trio',
      });
      expect(meta.lockedFields, ['title']);
      final provenance = meta.provenance.single;
      expect(provenance.field, 'title');
      expect(provenance.source, 'user');
      expect(provenance.locked, isTrue);
      expect(meta.credits.single.role, 'composer');
      expect(meta.credits.single.names, ['B. Butterbur']);
      expect(meta.lyrics?.synced, isTrue);
      expect(meta.lyrics?.source, 'provider');
      expect(meta.chapters.single.title, 'Opening');
      expect(meta.customTags.single.key, 'MOOD');
      expect(meta.virtualTrack, isTrue);
      expect(meta.hasArtwork, isTrue);
      expect(meta.albumPid, 'al-01JZX5N8QW3F4V9T2B7KDALBUM');
      final issue = meta.writeBackIssues.single;
      expect(issue.code, 'synced-lyrics-unsupported');
      expect(issue.tagKey, 'LYRICS');
    });

    test('empty collections stay empty, and absent chapters and lyrics read '
        'as none', () {
      final meta = decodeItemMetadata({
        'pid': 'tr-min',
        'mediaType': 'music',
        'fields': <String, Object?>{},
        'lockedFields': <Object?>[],
        'provenance': <Object?>[],
        'credits': <Object?>[],
        'customTags': <Object?>[],
        'unofficial': false,
        'virtualTrack': false,
        'hasArtwork': false,
        'hasOwnArtwork': false,
        'writeBackIssues': <Object?>[],
      }, _ctx);
      expect(meta.fields, isEmpty);
      expect(meta.lockedFields, isEmpty);
      expect(meta.credits, isEmpty);
      expect(meta.lyrics, isNull);
      expect(meta.chapters, isEmpty);
      expect(meta.customTags, isEmpty);
      expect(meta.writeBackIssues, isEmpty);
    });

    test('a chapter edit goes out as the chapter mark the wire takes', () {
      final mark = encodeChapterMark(
        const ChapterMark(index: 2, title: 'Trollshaws', startMs: 120000),
      );
      expect(mark['index'], 2);
      expect(mark['title'], 'Trollshaws');
      expect(mark['startMs'], 120000);
      expect(mark, isNot(contains('endMs')));
    });

    test('edit results default absent failure lists to empty', () {
      final result = decodeMetadataEditResult({'applied': true}, _ctx);
      expect(result.applied, isTrue);
      expect(result.writeBackFailures, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('a tag edit carries the files its write-back missed', () {
      final result = decodeTagEditResult({
        'key': 'MOOD',
        'stored': 1,
        'writeBackFailures': [
          {'filePid': 'fl-1', 'path': 'a.flac', 'reason': 'read-only file'},
        ],
      }, _ctx);
      expect(result.key, 'MOOD');
      expect(result.writeBackFailures.map((f) => (f.filePid, f.reason)), [
        ('fl-1', 'read-only file'),
      ]);
      expect(
        decodeTagEditResult({
          'key': 'MOOD',
          'stored': 1,
        }, _ctx).writeBackFailures,
        isEmpty,
      );
    });

    test('merge entity types go out by wire name', () async {
      final adapter = RecordingAdapter.refusing();
      final client = clientOn(adapter);
      for (final entityType in ['album', 'release-group']) {
        await expectLater(
          client.mergeDuplicates(
            entityType: entityType,
            survivorPid: 'al-1',
            loserPids: const ['al-2'],
          ),
          throwsA(isA<WaxDeckApiException>()),
        );
      }
      expect(
        [for (final body in _sent(adapter)) body['entityType']],
        ['album', 'release-group'],
      );
    });
  });

  group('a user account', () {
    test('upload permissions carry through', () {
      final account = decodeUserAccount({
        'id': 'us-01JZX5N8QW3F4V9T2B7KDUSER',
        'username': 'barliman',
        'displayName': 'Barliman Butterbur',
        'roles': ['user'],
        'createdAt': '2026-07-01T00:00:00Z',
        'libraryAccess': {
          'mode': 'granted',
          'libraryPids': ['li-01JZX5N8QW3F4V9T2B7KDLIB'],
        },
        'uploadEnabled': true,
        'uploadQuotaBytes': 1073741824,
        'disabled': false,
        'pending': false,
        'permissions': {
          'download': true,
          'delete': false,
          'explicitContent': false,
          'sharedOutputs': true,
          'managePodcasts': false,
          'maxTranscodeKbps': 192,
          'tagDeny': [
            {'key': 'genre', 'value': 'grindcore'},
          ],
        },
      }, _ctx);

      expect(account.username, 'barliman');
      expect(account.uploadEnabled, isTrue);
      expect(account.uploadQuotaBytes, 1073741824);
      expect(account.libraryAccess.mode, 'granted');
      expect(account.libraryAccess.libraryPids, [
        'li-01JZX5N8QW3F4V9T2B7KDLIB',
      ]);
      expect(account.disabled, isFalse);
      expect(account.hasPassword, isTrue);
      expect(account.pending, isFalse);
      expect(account.permissions.download, isTrue);
      expect(account.permissions.explicitContent, isFalse);
      expect(account.permissions.sharedOutputs, isTrue);
      expect(account.permissions.maxTranscodeKbps, 192);
      expect(account.permissions.tagAllow, isEmpty);
      expect(account.permissions.tagDeny.single.key, 'genre');
      expect(account.permissions.tagDeny.single.value, 'grindcore');
    });
  });
}
