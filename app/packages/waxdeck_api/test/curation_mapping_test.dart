import 'package:test/test.dart';
import 'package:waxdeck_api/src/mapping.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

void main() {
  group('review mapping', () {
    gen.CandidateSummary best() => gen.CandidateSummary(
      (b) => b
        ..mbid = 'mb-best'
        ..title = 'Inn Sessions'
        ..artist = 'The Bree Trio'
        ..year = 2019
        ..similarityPct = 97.5,
    );

    test('detail carries candidates, pairings, and tracks through', () {
      final detail = reviewEntryDetailFromGen(
        gen.ReviewEntryDetail(
          (b) => b
            ..id = 're-01JZX5N8QW3F4V9T2B7KDREVIEW'
            ..kind = 'import'
            ..status = 'pending'
            ..mediaType = gen.MediaType.music
            ..origin = 'upload'
            ..title = 'Inn Sessions'
            ..artist = 'The Bree Trio'
            ..trackCount = 2
            ..uploadedBy = 'barliman'
            ..identifying = false
            ..best = best().toBuilder()
            ..createdAt = DateTime.utc(2026, 7, 1)
            ..candidates.add(
              gen.ReviewCandidate(
                (c) => c
                  ..mbid = 'mb-best'
                  ..releaseGroupMbid = 'mb-group'
                  ..title = 'Inn Sessions'
                  ..artist = 'The Bree Trio'
                  ..year = 2019
                  ..trackCount = 2
                  ..country = 'NL'
                  ..similarityPct = 97.5
                  ..components.add(
                    gen.CandidateComponent(
                      (cc) => cc
                        ..name = 'tracks'
                        ..distance = 0.02
                        ..weight = 0.5,
                    ),
                  )
                  ..pairings.add(
                    gen.CandidatePairing(
                      (p) => p
                        ..trackIndex = 0
                        ..position = 1
                        ..disc = 1
                        ..title = 'Prancing Pony Blues'
                        ..durationMs = 214000
                        ..recordingMbid = 'mb-rec'
                        ..distance = 0.01,
                    ),
                  )
                  ..missingTitles.add('Hidden Track')
                  ..extraTrackIndexes.add(1),
              ),
            )
            ..tracks.add(
              gen.ReviewTrack(
                (t) => t
                  ..path = 'inbox/pony.flac'
                  ..title = 'Prancing Pony Blues'
                  ..trackNo = 1
                  ..durationMs = 214000,
              ),
            ),
        ),
      );

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

    test('absent candidate breakdowns map to empty lists', () {
      final candidate = reviewCandidateFromGen(
        gen.ReviewCandidate(
          (c) => c
            ..mbid = 'mb-min'
            ..title = 'Inn Sessions'
            ..artist = 'The Bree Trio'
            ..similarityPct = 80,
        ),
      );
      expect(candidate.components, isEmpty);
      expect(candidate.pairings, isEmpty);
      expect(candidate.missingTitles, isEmpty);
      expect(candidate.extraTrackIndexes, isEmpty);
    });

    test('decision actions bridge by wire name, including as-is', () {
      expect(reviewActionToGen('approve').name, 'approve');
      expect(reviewActionToGen('as-is').name, 'asIs');
      expect(reviewBulkActionToGen('as-is').name, 'asIs');
      expect(reviewBulkActionToGen('discard').name, 'discard');
    });

    test('matching modes roundtrip, including off', () {
      for (final mode in ['auto', 'review', 'off']) {
        expect(
          libraryMatchingModeFromGen(libraryMatchingModeToGen(mode)),
          mode,
        );
      }
    });

    test('stats default their optional counters to zero', () {
      final stats = reviewStatsFromGen(
        gen.ReviewStats(
          (b) => b
            ..pending = 3
            ..applied = 2
            ..autoApplied = 5
            ..reverted = 1
            ..revertedAutoApplied = 0,
        ),
      );
      expect(stats.pending, 3);
      expect(stats.identifying, 0);
      expect(stats.asIs, 0);
      expect(stats.skipped, 0);
    });
  });

  group('upload mapping', () {
    test('session with a duplicate warning carries through', () {
      final page = uploadPageFromGen(
        gen.UploadPage(
          (b) => b
            ..uploads.add(
              gen.Upload(
                (u) => u
                  ..id = 'up-01JZX5N8QW3F4V9T2B7KDUPLOAD'
                  ..fileName = 'pony.flac'
                  ..sizeBytes = 4096
                  ..receivedBytes = 4096
                  ..mediaType = gen.MediaType.music
                  ..libraryPid = 'li-01JZX5N8QW3F4V9T2B7KDLIB'
                  ..state = 'staged'
                  ..reviewEntryId = 're-01JZX5N8QW3F4V9T2B7KDREVIEW'
                  ..duplicate = gen.DuplicateWarning(
                    (d) => d
                      ..itemPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXIST'
                      ..kind = 'fingerprint'
                      ..title = 'Prancing Pony Blues'
                      ..artist = 'The Bree Trio',
                  ).toBuilder()
                  ..uploadedBy = 'barliman'
                  ..createdAt = DateTime.utc(2026, 7, 1)
                  ..expiresAt = DateTime.utc(2026, 7, 2),
              ),
            )
            ..nextCursor = 'cursor-1',
        ),
      );

      expect(page.nextCursor, 'cursor-1');
      expect(page.hasMore, isTrue);
      final upload = page.uploads.single;
      expect(upload.id, 'up-01JZX5N8QW3F4V9T2B7KDUPLOAD');
      expect(upload.state, 'staged');
      expect(upload.receivedBytes, 4096);
      expect(upload.reviewEntryId, 're-01JZX5N8QW3F4V9T2B7KDREVIEW');
      expect(upload.duplicate?.itemPid, 'tr-01JZX5N8QW3F4V9T2B7KDEXIST');
      expect(upload.duplicate?.kind, 'fingerprint');
      expect(upload.expiresAt, DateTime.utc(2026, 7, 2));
    });

    test('a fresh session has no duplicate and no review entry', () {
      final upload = uploadSessionFromGen(
        gen.Upload(
          (u) => u
            ..id = 'up-min'
            ..fileName = 'pony.flac'
            ..sizeBytes = 4096
            ..receivedBytes = 0
            ..mediaType = gen.MediaType.audiobook
            ..state = 'receiving'
            ..createdAt = DateTime.utc(2026, 7, 1),
        ),
      );
      expect(upload.mediaType, MediaType.audiobook);
      expect(upload.duplicate, isNull);
      expect(upload.reviewEntryId, isNull);
      expect(upload.expiresAt, isNull);
    });
  });

  group('item metadata mapping', () {
    test('the full editor payload carries through', () {
      final meta = itemMetadataFromGen(
        gen.ItemMetadata(
          (b) => b
            ..pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE'
            ..mediaType = gen.MediaType.music
            ..fields.addAll({
              'title': 'Prancing Pony Blues',
              'artist': 'The Bree Trio',
            })
            ..lockedFields.add('title')
            ..provenance.add(
              gen.FieldProvenance(
                (p) => p
                  ..field = 'title'
                  ..source_ = 'user'
                  ..locked = true
                  ..updatedAt = DateTime.utc(2026, 7, 1),
              ),
            )
            ..credits.add(
              gen.Credit(
                (c) => c
                  ..role = 'composer'
                  ..names.addAll(['B. Butterbur']),
              ),
            )
            ..lyrics = gen.LyricsState(
              (l) => l
                ..synced = true
                ..source_ = 'provider'
                ..lrc = '[00:01.00]At the sign of the pony',
            ).toBuilder()
            ..chapters.add(
              gen.ChapterMark(
                (c) => c
                  ..index = 0
                  ..title = 'Opening'
                  ..startMs = 0
                  ..endMs = 60000,
              ),
            )
            ..customTags.add(
              gen.CustomTag(
                (t) => t
                  ..key = 'MOOD'
                  ..values.addAll(['cozy']),
              ),
            )
            ..unofficial = false
            ..virtualTrack = true
            ..hasArtwork = true
            ..albumPid = 'al-01JZX5N8QW3F4V9T2B7KDALBUM'
            ..artistPid = 'ar-01JZX5N8QW3F4V9T2B7KDARTIST'
            ..writeBackIssues.add(
              gen.WriteBackIssue(
                (i) => i
                  ..filePid = 'fi-01JZX5N8QW3F4V9T2B7KDFILE'
                  ..code = 'synced-lyrics-unsupported'
                  ..tagKey = 'LYRICS'
                  ..detail = 'MP4 refuses embedded synced lyrics',
              ),
            ),
        ),
      );

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

    test('a bare item maps to empty collections', () {
      final meta = itemMetadataFromGen(
        gen.ItemMetadata(
          (b) => b
            ..pid = 'tr-min'
            ..mediaType = gen.MediaType.music
            ..unofficial = false
            ..virtualTrack = false
            ..hasArtwork = false,
        ),
      );
      expect(meta.fields, isEmpty);
      expect(meta.lockedFields, isEmpty);
      expect(meta.credits, isEmpty);
      expect(meta.lyrics, isNull);
      expect(meta.chapters, isEmpty);
      expect(meta.customTags, isEmpty);
      expect(meta.writeBackIssues, isEmpty);
    });

    test('chapter edits map onto the generated chapter mark', () {
      final mark = chapterEditToGen(
        const ChapterEdit(index: 2, title: 'Trollshaws', startMs: 120000),
      );
      expect(mark.index, 2);
      expect(mark.title, 'Trollshaws');
      expect(mark.startMs, 120000);
      expect(mark.endMs, isNull);
    });

    test('edit results default absent failure lists to empty', () {
      final result = metadataEditResultFromGen(
        gen.MetadataEditResult((b) => b..applied = true),
      );
      expect(result.applied, isTrue);
      expect(result.writeBackFailures, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('merge entity types bridge by wire name', () {
      expect(mergeEntityTypeToGen('album').name, 'album');
      expect(mergeEntityTypeToGen('release-group').name, 'releaseGroup');
    });
  });

  group('user account mapping', () {
    test('upload permissions carry through', () {
      final account = userAccountFromGen(
        gen.UserAccount(
          (b) => b
            ..id = 'us-01JZX5N8QW3F4V9T2B7KDUSER'
            ..username = 'barliman'
            ..displayName = 'Barliman Butterbur'
            ..roles.add('user')
            ..createdAt = DateTime.utc(2026, 7, 1)
            ..libraryAccess = gen.LibraryAccess(
              (a) => a
                ..mode = gen.LibraryAccessModeEnum.granted
                ..libraryPids.add('li-01JZX5N8QW3F4V9T2B7KDLIB'),
            ).toBuilder()
            ..uploadEnabled = true
            ..uploadQuotaBytes = 1073741824
            ..disabled = false
            ..pending = false
            ..permissions = gen.Permissions(
              (p) => p
                ..download = true
                ..delete = false
                ..explicitContent = false
                ..sharedOutputs = true
                ..managePodcasts = false
                ..maxTranscodeKbps = 192
                ..tagDeny.add(
                  gen.TagRule(
                    (t) => t
                      ..key = 'genre'
                      ..value = 'grindcore',
                  ),
                ),
            ).toBuilder(),
        ),
      );

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
