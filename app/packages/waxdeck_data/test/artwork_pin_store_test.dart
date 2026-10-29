import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

ArtworkPinRecord _pin(String pid, int sizePx, {String etag = 'W/"a"'}) {
  return ArtworkPinRecord(
    pid: pid,
    sizePx: sizePx,
    artUrl: 'https://deck.example/api/v1/items/$pid/art',
    etag: etag,
    localPath: '/art/$pid-$sizePx.img',
    sizeBytes: sizePx * 100,
    pinnedAt: DateTime.utc(2026, 7, 27, 9),
  );
}

void main() {
  late MirrorDatabase db;
  late DriftArtworkPinStore store;

  setUp(() {
    db = inMemoryMirrorDatabase();
    store = DriftArtworkPinStore(db);
  });
  tearDown(() => db.close());

  test('an unpinned item has no pins', () async {
    expect(await store.pinsFor('tr-A'), isEmpty);
  });

  test('pins come back largest first, so a draw takes the first one big '
      'enough', () async {
    await store.put(_pin('tr-A', 256));
    await store.put(_pin('tr-A', 1024));
    expect((await store.pinsFor('tr-A')).map((p) => p.sizePx), <int>[
      1024,
      256,
    ]);
  });

  test('re-pinning a rung replaces it rather than doubling it', () async {
    await store.put(_pin('tr-A', 1024, etag: 'W/"old"'));
    await store.put(_pin('tr-A', 1024, etag: 'W/"new"'));
    final pins = await store.pinsFor('tr-A');
    expect(pins, hasLength(1));
    expect(pins.single.etag, 'W/"new"');
  });

  group('removing exactly', () {
    ArtworkPinRecord at(String pid, int sizePx, DateTime when) =>
        ArtworkPinRecord(
          pid: pid,
          sizePx: sizePx,
          artUrl: 'https://deck.example/api/v1/items/$pid/art',
          etag: 'W/"a"',
          localPath: '/art/$pid-$sizePx.img',
          sizeBytes: sizePx * 100,
          pinnedAt: when,
        );

    final first = DateTime.utc(2026, 10, 1);
    final later = DateTime.utc(2026, 10, 2);

    test('takes the pins listed and leaves every other', () async {
      await store.put(at('tr-A', 1024, first));
      await store.put(at('tr-A', 256, first));
      await store.put(at('tr-B', 1024, first));
      // A cover the device pinned after the list was made.
      await store.put(at('tr-A', 512, later));

      await store.removeExactly('tr-A', [
        (sizePx: 1024, pinnedAt: first),
        (sizePx: 256, pinnedAt: first),
      ]);

      expect((await store.pinsFor('tr-A')).map((p) => p.sizePx), [512]);
      expect(await store.pinsFor('tr-B'), hasLength(1));
    });

    test('leaves a size pinned again since, which is not the cover that '
        'was listed', () async {
      await store.put(at('tr-A', 1024, first));
      await store.put(at('tr-A', 1024, later));

      await store.removeExactly('tr-A', [(sizePx: 1024, pinnedAt: first)]);

      final held = await store.pinsFor('tr-A');
      expect(held, hasLength(1));
      expect(held.single.pinnedAt.toUtc(), later);
    });
  });

  group('whether a cover may be pinned', () {
    Future<void> download(String pid) => db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: pid,
            fileIndex: 0,
            essenceHash: 'e-$pid',
            etag: 'x',
            fileName: 'e.mp3',
            localPath: '/downloads/e.mp3',
            sizeBytes: 1,
            state: 'complete',
          ),
        );

    test('not for an item the device holds no download of', () async {
      expect(await store.mayPin('tr-A'), isFalse);
    });

    test('for one it holds, when no free is owed for it', () async {
      await download('tr-A');

      expect(await store.mayPin('tr-A'), isTrue);
    });

    test('not for one a commit has promised to free', () async {
      await download('tr-A');
      await db.transaction(() => PendingFrees(db).condemn('tr-A'));

      expect(await store.mayPin('tr-A'), isFalse);
    });

    test('for one whose promise is no longer owed', () async {
      await download('tr-A');
      await db.transaction(() => PendingFrees(db).condemn('tr-A'));
      await db
          .into(db.mirrorItems)
          .insert(
            MirrorItemsCompanion.insert(
              pid: 'tr-A',
              ulid: 'A',
              mediaType: 'music',
              title: 'Back',
              durationMs: 1,
              sortKey: 'back',
            ),
          );

      expect(await store.mayPin('tr-A'), isTrue);
    });

    test('the no-op store never pins', () async {
      expect(await const NoArtworkPinStore().mayPin('tr-A'), isFalse);
    });
  });

  test('clearing drops every account-held pin', () async {
    await store.put(_pin('tr-A', 1024));
    await store.put(_pin('tr-B', 256));
    expect(await store.clear(), hasLength(2));
    expect(await store.pinsFor('tr-A'), isEmpty);
    expect(await store.pinsFor('tr-B'), isEmpty);
  });

  test('the no-op store is safe to call and pins nothing', () async {
    const none = NoArtworkPinStore();
    await none.put(_pin('tr-A', 1024));
    expect(await none.pinsFor('tr-A'), isEmpty);
    await none.removeExactly('tr-A', [
      (sizePx: 1024, pinnedAt: DateTime.utc(2026, 7, 27, 9)),
    ]);
    expect(await none.clear(), isEmpty);
  });

  test('a draw under a pid a kind change retired finds the pins it moved '
      'to, and nothing else does', () async {
    const ulid = '01JZX5N8QW3F4V9T2B7KDKIND01';
    await db
        .into(db.mirrorItems)
        .insert(
          MirrorItemsCompanion.insert(
            pid: 'bk-$ulid',
            ulid: ulid,
            mediaType: 'audiobook',
            title: 'Kind',
            durationMs: 60000,
            sortKey: 'kind',
          ),
        );
    await store.put(_pin('bk-$ulid', 1024));

    // A queue entry saved before the change still names the track.
    expect((await store.pinsToDraw('tr-$ulid')).map((p) => p.pid), [
      'bk-$ulid',
    ]);
    expect(await store.pinsFor('tr-$ulid'), isEmpty);
    await store.removeExactly('tr-$ulid', [
      (sizePx: 1024, pinnedAt: DateTime.utc(2026, 7, 27, 9)),
    ]);
    expect(await store.pinsFor('bk-$ulid'), hasLength(1));
    expect(await store.pinsToDraw('tr-01JZX5N8QW3F4V9T2B7KDOTHER1'), isEmpty);
  });
}
