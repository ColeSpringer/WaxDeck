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

  group('recording where a pinned picture is now', () {
    const now = 'https://deck.moved.example/api/v1/items/bk-A/art';

    test('moves the URL of that pin and nothing else of it', () async {
      await store.put(_pin('bk-A', 1024));
      await store.put(_pin('bk-A', 256));
      final [hero, cell] = await store.pinsFor('bk-A');

      await store.recordUrl(hero, now);

      final [after, other] = await store.pinsFor('bk-A');
      expect(after.artUrl, now);
      expect(after.etag, hero.etag);
      expect(after.localPath, hero.localPath);
      expect(after.pinnedAt, hero.pinnedAt);
      expect(other.artUrl, cell.artUrl);
    });

    test('leaves a size pinned again since, and makes no row for one that '
        'is gone', () async {
      await store.put(_pin('bk-A', 1024));
      final read = (await store.pinsFor('bk-A')).single;
      await store.put(
        ArtworkPinRecord(
          pid: read.pid,
          sizePx: read.sizePx,
          artUrl: read.artUrl,
          etag: 'W/"since"',
          localPath: read.localPath,
          sizeBytes: read.sizeBytes,
          pinnedAt: DateTime.utc(2030),
        ),
      );
      await store.recordUrl(read, now);
      expect((await store.pinsFor('bk-A')).single.artUrl, read.artUrl);

      await store.removeExactly('bk-A', [
        (sizePx: 1024, pinnedAt: DateTime.utc(2030)),
      ]);
      await store.recordUrl(read, now);
      expect(await store.pinsFor('bk-A'), isEmpty);
    });
  });

  group('a walk of every pin', () {
    List<String> names(List<ArtworkPinRecord> pins) => [
      for (final pin in pins) '${pin.pid}/${pin.sizePx}',
    ];

    setUp(() async {
      // Put in no order, as downloads land.
      await store.put(_pin('tr-B', 1024));
      await store.put(_pin('al-C', 256));
      await store.put(_pin('tr-A', 1024));
      await store.put(_pin('tr-B', 256));
      await store.put(_pin('tr-A', 256));
    });

    test('reads them a page at a time, each once', () async {
      final seen = <String>[];
      PinCursor? after;
      while (true) {
        final page = await store.pinsAfter(after, limit: 2);
        if (page.isEmpty) break;
        expect(page.length, lessThanOrEqualTo(2));
        seen.addAll(names(page));
        after = (pid: page.last.pid, sizePx: page.last.sizePx);
      }
      expect(seen, [
        'al-C/256',
        'tr-A/256',
        'tr-A/1024',
        'tr-B/256',
        'tr-B/1024',
      ]);
    });

    test('picks up past its last pin when that pin has gone, and reads one '
        'pinned ahead of it since', () async {
      final first = await store.pinsAfter(null, limit: 2);
      expect(names(first), ['al-C/256', 'tr-A/256']);
      await store.removeExactly('tr-A', [
        (sizePx: 256, pinnedAt: first.last.pinnedAt),
      ]);
      await store.put(_pin('tr-AA', 256));

      final rest = await store.pinsAfter((pid: 'tr-A', sizePx: 256), limit: 10);
      expect(names(rest), ['tr-A/1024', 'tr-AA/256', 'tr-B/256', 'tr-B/1024']);
    });

    test('carries what a conditional request needs', () async {
      final pin = (await store.pinsAfter(null, limit: 1)).single;
      expect(pin.etag, 'W/"a"');
      expect(pin.artUrl, 'https://deck.example/api/v1/items/al-C/art');
      expect(pin.localPath, '/art/al-C-256.img');
    });
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
