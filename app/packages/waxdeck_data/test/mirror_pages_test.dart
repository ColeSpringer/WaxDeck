import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

const _base = 'http://deck.local:4420/api/v1/items';

/// The art URL the app mints for [pid], at the server's address now.
String _artAt(String pid) => '$_base/$pid/art';
const _pinned = 'tr-01JZX5N8QW3F4V9T2B7KDPINNED';
const _bare = 'tr-01JZX5N8QW3F4V9T2B7KDBARE01';

Future<void> _item(
  MirrorDatabase db,
  String pid, {
  String mediaType = 'music',
  String? title,
}) => db
    .into(db.mirrorItems)
    .insert(
      MirrorItemsCompanion.insert(
        pid: pid,
        ulid: pid.substring(3),
        mediaType: mediaType,
        title: title ?? pid,
        durationMs: 60000,
        sortKey: (title ?? pid).toLowerCase(),
      ),
    );

Future<void> _pin(
  MirrorDatabase db,
  String pid,
  int sizePx, {
  required String artUrl,
}) => DriftArtworkPinStore(db).put(
  ArtworkPinRecord(
    pid: pid,
    sizePx: sizePx,
    artUrl: artUrl,
    etag: '"$sizePx"',
    localPath: '/art/$pid-$sizePx.img',
    sizeBytes: sizePx,
    pinnedAt: DateTime.utc(2026, 11, 18),
  ),
);

void main() {
  late MirrorDatabase db;

  setUp(() => db = inMemoryMirrorDatabase());
  tearDown(() => db.close());

  group('a hydrated summary carries the cover pinned for it', () {
    setUp(() async {
      await _item(db, _pinned, title: 'a');
      await _item(db, _bare, title: 'b');
      await _pin(db, _pinned, 1024, artUrl: '$_base/$_pinned/art');
      await _pin(db, _pinned, 256, artUrl: '$_base/$_pinned/art');
    });

    test('one by pid', () async {
      expect(
        (await mirrorItemByPid(db, _pinned, artUrlFor: _artAt))!.artUrl,
        '$_base/$_pinned/art',
      );
      expect(
        (await mirrorItemByPid(db, _bare, artUrlFor: _artAt))!.artUrl,
        isNull,
        reason: 'nothing on disk is a placeholder, not a request',
      );
    });

    test('one pinned while the server was at another address names this '
        'one', () async {
      await _pin(
        db,
        _bare,
        1024,
        artUrl: 'http://old.local:4420/api/v1/items/$_bare/art',
      );

      expect(
        (await mirrorItemByPid(db, _bare, artUrlFor: _artAt))!.artUrl,
        '$_base/$_bare/art',
      );
      expect(
        (await mirrorItemsPage(
          db,
          artUrlFor: _artAt,
        )).items.map((item) => item.artUrl),
        ['$_base/$_pinned/art', '$_base/$_bare/art'],
      );
    });

    test('a reader that draws nothing is handed none', () async {
      expect((await mirrorItemByPid(db, _pinned))!.artUrl, isNull);
      expect((await mirrorItemsPage(db)).items.map((item) => item.artUrl), [
        null,
        null,
      ]);
    });

    test('a page', () async {
      final page = await mirrorItemsPage(db, artUrlFor: _artAt);
      expect(
        {for (final item in page.items) item.pid: item.artUrl},
        {_pinned: '$_base/$_pinned/art', _bare: null},
      );
    });
  });

  group('after a kind change', () {
    const ulid = '01JZX5N8QW3F4V9T2B7KDKIND01';

    setUp(() => _item(db, 'bk-$ulid', mediaType: 'audiobook'));

    test('a pin that moved with its download names the pid the item has '
        'now', () async {
      // Moved by the sync under the new pid, with the URL it was fetched
      // from, which names the old one.
      await _pin(db, 'bk-$ulid', 1024, artUrl: '$_base/tr-$ulid/art');

      expect(
        (await mirrorItemByPid(db, 'bk-$ulid', artUrlFor: _artAt))!.artUrl,
        '$_base/bk-$ulid/art',
      );
      expect(
        (await mirrorItemsPage(db, artUrlFor: _artAt)).items.single.artUrl,
        '$_base/bk-$ulid/art',
      );
    });

    test('a pin left under the retired pid is not the new one\'s', () async {
      // There until the kind change is decided: moved with the download,
      // or freed with it.
      await _pin(db, 'tr-$ulid', 1024, artUrl: '$_base/tr-$ulid/art');

      expect(
        (await mirrorItemByPid(db, 'bk-$ulid', artUrlFor: _artAt))!.artUrl,
        isNull,
      );
      expect(
        (await mirrorItemsPage(db, artUrlFor: _artAt)).items.single.artUrl,
        isNull,
      );
    });
  });
}
