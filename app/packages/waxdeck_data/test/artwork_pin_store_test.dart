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

  test('removing answers what it dropped, so the files can go too', () async {
    await store.put(_pin('tr-A', 1024));
    await store.put(_pin('tr-A', 256));
    await store.put(_pin('tr-B', 1024));

    final dropped = await store.remove('tr-A');
    expect(dropped.map((p) => p.localPath), <String>[
      '/art/tr-A-1024.img',
      '/art/tr-A-256.img',
    ]);
    expect(await store.pinsFor('tr-A'), isEmpty);
    expect(await store.pinsFor('tr-B'), hasLength(1));
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
    expect(await none.remove('tr-A'), isEmpty);
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
    expect(await store.remove('tr-$ulid'), isEmpty);
    expect(await store.pinsFor('bk-$ulid'), hasLength(1));
    expect(await store.pinsToDraw('tr-01JZX5N8QW3F4V9T2B7KDOTHER1'), isEmpty);
  });
}
