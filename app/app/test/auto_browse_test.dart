import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auto/auto_browse.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

void main() {
  test('the browse tree serves the mirror: root, library, leaves', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await db.batch(
      (b) => b.insertAll(db.mirrorItems, [
        MirrorItemsCompanion.insert(
          pid: 'tr-BBB',
          ulid: 'BBB',
          mediaType: 'music',
          title: 'Bravo',
          artist: const Value('Fixture Artist'),
          durationMs: 1000,
          sortKey: 'bravo',
        ),
        MirrorItemsCompanion.insert(
          pid: 'tr-AAA',
          ulid: 'AAA',
          mediaType: 'music',
          title: 'Alpha',
          artist: const Value('Fixture Artist'),
          durationMs: 1000,
          sortKey: 'alpha',
        ),
      ]),
    );
    final source = MirrorBrowseSource(db);

    final root = await source.children(browseRootId);
    expect(root.map((e) => e.title), [
      'Continue',
      'Music',
      'Podcasts',
      'Audiobooks',
      'Downloads',
    ]);
    expect(root.every((e) => !e.playable), isTrue);

    final music = await source.children('music');
    expect(music.map((e) => e.title), ['Alpha', 'Bravo']);
    expect(music.every((e) => e.playable), isTrue);
    expect(music.first.id, 'tr-AAA');

    // The other media folders are empty for a music-only mirror, and
    // so are Continue and Downloads with no progress or files.
    expect(await source.children('podcasts'), isEmpty);
    expect(await source.children('continue'), isEmpty);
    expect(await source.children('downloads'), isEmpty);

    expect(await source.children('nonsense'), isEmpty);
  });

  test('continue and downloads folders serve progress and files', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await db.batch(
      (b) => b.insertAll(db.mirrorItems, [
        MirrorItemsCompanion.insert(
          pid: 'bk-CCC',
          ulid: 'CCC',
          mediaType: 'audiobook',
          title: 'Charlie',
          durationMs: 1000,
          sortKey: 'charlie',
        ),
        MirrorItemsCompanion.insert(
          pid: 'tr-DDD',
          ulid: 'DDD',
          mediaType: 'music',
          title: 'Delta',
          durationMs: 1000,
          sortKey: 'delta',
        ),
      ]),
    );
    await db
        .into(db.mirrorPlayStates)
        .insert(
          MirrorPlayStatesCompanion.insert(
            pid: 'bk-CCC',
            positionMs: const Value(5000),
          ),
        );
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'tr-DDD',
            fileIndex: 0,
            essenceHash: 'hash',
            etag: 'etag',
            fileName: 'x.flac',
            sizeBytes: 1,
            localPath: '/tmp/x',
            state: 'complete',
          ),
        );
    final source = MirrorBrowseSource(db);

    final cont = await source.children('continue');
    expect(cont.map((e) => e.id), ['bk-CCC']);
    final downloads = await source.children('downloads');
    expect(downloads.map((e) => e.id), ['tr-DDD']);
  });
}
