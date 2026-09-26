import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auto/auto_browse.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// A container whose off-tree copy follows [system] alone.
ProviderContainer _copy([List<Locale> system = const [Locale('en')]]) {
  final container = ProviderContainer(
    overrides: [localeOverrideProvider.overrideWithValue(null)],
  );
  addTearDown(container.dispose);
  container.read(systemLocalesProvider.notifier).locales = system;
  return container;
}

MirrorBrowseSource _source(MirrorDatabase db, ProviderContainer copy) =>
    MirrorBrowseSource(db, l10n: () => copy.read(offTreeL10nProvider));

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
    final source = _source(db, _copy());

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
    final source = _source(db, _copy());

    final cont = await source.children('continue');
    expect(cont.map((e) => e.id), ['bk-CCC']);
    final downloads = await source.children('downloads');
    expect(downloads.map((e) => e.id), ['tr-DDD']);
  });
  group('the downloads folder', () {
    Future<MirrorDatabase> mirror(List<String> pids) async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      for (final pid in pids) {
        await db
            .into(db.mirrorItems)
            .insert(
              MirrorItemsCompanion.insert(
                pid: pid,
                ulid: pid.substring(3),
                mediaType: 'audiobook',
                title: pid,
                durationMs: 1000,
                sortKey: pid,
              ),
            );
      }
      return db;
    }

    Future<void> file(
      MirrorDatabase db,
      String pid,
      int index, {
      String state = 'complete',
    }) => db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: pid,
            fileIndex: index,
            essenceHash: '$pid/$index',
            etag: 'etag',
            fileName: '$index.m4b',
            sizeBytes: 1,
            localPath: '/tmp/$pid/$index',
            state: state,
          ),
        );

    test('leaves out an item still on its way', () async {
      final db = await mirror(['bk-EEE', 'bk-FFF']);
      await file(db, 'bk-EEE', 0);
      await file(db, 'bk-EEE', 1, state: 'pending');
      await file(db, 'bk-FFF', 0);
      await file(db, 'bk-FFF', 1);

      final downloads = await _source(db, _copy()).children('downloads');

      expect(downloads.map((e) => e.id), ['bk-FFF']);
    });

    test('lists the newest first', () async {
      final db = await mirror(['bk-EEE', 'bk-FFF']);
      await file(db, 'bk-EEE', 0);
      await file(db, 'bk-FFF', 0);

      final downloads = await _source(db, _copy()).children('downloads');

      expect(downloads.map((e) => e.id), ['bk-FFF', 'bk-EEE']);
    });
  });

  test('the folders follow the app language', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final copy = _copy();
    final source = _source(db, copy);
    expect((await source.children(browseRootId)).first.title, 'Continue');

    copy.read(systemLocalesProvider.notifier).locales = const [Locale('es')];

    final root = await source.children(browseRootId);
    expect(root.map((e) => e.title), [
      'Continuar',
      'Música',
      'Pódcast',
      'Audiolibros',
      'Descargas',
    ]);
  });
}
