import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

const _pid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

void main() {
  late MirrorDatabase db;
  late PendingFrees frees;

  setUp(() {
    db = inMemoryMirrorDatabase();
    frees = PendingFrees(db);
  });
  tearDown(() => db.close());

  Future<void> file(int index, String essence, {String state = 'complete'}) =>
      db
          .into(db.downloadRecords)
          .insertOnConflictUpdate(
            DownloadRecordsCompanion.insert(
              pid: _pid,
              fileIndex: index,
              essenceHash: essence,
              etag: 'x',
              fileName: '$essence.m4b',
              localPath: state == 'complete' ? '/downloads/$essence.m4b' : '',
              sizeBytes: 1024,
              state: state,
            ),
          );

  Future<void> cover(int sizePx, DateTime at) => db
      .into(db.artworkPins)
      .insertOnConflictUpdate(
        ArtworkPinsCompanion.insert(
          pid: _pid,
          sizePx: sizePx,
          artUrl: '/media/art?pid=$_pid',
          etag: 'a',
          localPath: '/art/$_pid-$sizePx.img',
          sizeBytes: 2048,
          pinnedAt: at,
        ),
      );

  final first = DateTime.utc(2026, 10, 1);
  final later = DateTime.utc(2026, 10, 2);

  /// Two files and two covers held, and a promise to free them.
  Future<void> owedBook() async {
    await file(0, 'e0');
    await file(1, 'e1');
    await cover(300, first);
    await cover(600, first);
    await db.transaction(() => frees.condemn(_pid));
  }

  List<String> keys(Owed owed) => [
    for (final f in owed.files) '${f.index}/${f.essence}',
    for (final p in owed.pins)
      '${p.sizePx}@${p.pinnedAt.millisecondsSinceEpoch ~/ 1000}',
  ];

  test('owes exactly the rows held when the promise was written', () async {
    await owedBook();

    final owed = (await frees.owed(_pid))!;

    expect(keys(owed), [
      '0/e0',
      '1/e1',
      '300@${first.millisecondsSinceEpoch ~/ 1000}',
      '600@${first.millisecondsSinceEpoch ~/ 1000}',
    ]);
  });

  test('a pid nothing was promised for owes nothing', () async {
    expect(await frees.owed('tr-NONE'), isNull);
    await file(0, 'e0');
    expect(await frees.owed(_pid), isNull, reason: 'held is not promised');
  });

  test('owes only what is still held of it', () async {
    await owedBook();
    await (db.delete(
      db.downloadRecords,
    )..where((t) => t.fileIndex.equals(0))).go();
    await (db.delete(db.artworkPins)..where((t) => t.sizePx.equals(600))).go();

    final owed = (await frees.owed(_pid))!;

    expect(keys(owed), ['1/e1', '300@${first.millisecondsSinceEpoch ~/ 1000}']);
  });

  group(
    'a file taken up after the commit takes the pid out of the promise',
    () {
      test('at another index', () async {
        await owedBook();
        await file(7, 'e7');

        expect(await frees.owed(_pid), isNull);
        expect(await frees.due(), isEmpty, reason: 'and it is forgotten');
      });

      test('replaced by other audio', () async {
        await owedBook();
        await file(1, 'other');

        expect(await frees.owed(_pid), isNull);
      });
    },
  );

  group('a cover pinned after the commit is no take-up', () {
    test('at another size: the promise still owes what it listed', () async {
      await owedBook();
      await cover(1024, later);

      final owed = (await frees.owed(_pid))!;

      expect(keys(owed), [
        '0/e0',
        '1/e1',
        '300@${first.millisecondsSinceEpoch ~/ 1000}',
        '600@${first.millisecondsSinceEpoch ~/ 1000}',
      ], reason: 'the new cover is not listed, so not owed');
    });

    test('again at the size it held: that cover is no longer the listed '
        'one', () async {
      await owedBook();
      await cover(300, later);

      final owed = (await frees.owed(_pid))!;

      expect(keys(owed), [
        '0/e0',
        '1/e1',
        '600@${first.millisecondsSinceEpoch ~/ 1000}',
      ]);
    });
  });

  test(
    'the mirror listing the pid again takes it out of the promise',
    () async {
      await owedBook();
      await db
          .into(db.mirrorItems)
          .insert(
            MirrorItemsCompanion.insert(
              pid: _pid,
              ulid: _pid.substring(3),
              mediaType: 'audiobook',
              title: 'The Book',
              durationMs: 1,
              sortKey: 'book',
            ),
          );

      expect(await frees.owed(_pid), isNull);
      expect(await frees.due(), isEmpty);
    },
  );

  test(
    'nothing promised still held is nothing owed, whatever else is',
    () async {
      await owedBook();
      await db.delete(db.downloadRecords).go();
      await db.delete(db.artworkPins).go();
      await cover(1024, later);

      expect(await frees.owed(_pid), isNull);
      expect(await frees.due(), isEmpty);
      expect(
        (await db.select(db.clientSettings).get()).where(
          (r) => r.key.startsWith(PendingFrees.keyPrefix),
        ),
        isEmpty,
        reason: 'forgotten',
      );
    },
  );

  test('a download still going when the promise was written is owed once it '
      'lands', () async {
    await file(0, 'e0', state: 'pending');
    await db.transaction(() => frees.condemn(_pid));
    // It completes after the commit, under the same key.
    await file(0, 'e0');

    final owed = (await frees.owed(_pid))!;

    expect(keys(owed), ['0/e0']);
  });

  test(
    'due lists the pids still owed, in order, and settle clears one',
    () async {
      await owedBook();
      expect(await frees.due(), [_pid]);
      expect(await frees.due(only: 'tr-NONE'), isEmpty);

      expect(await frees.settle(_pid), isFalse, reason: 'the bytes are held');
      await db.delete(db.downloadRecords).go();
      await db.delete(db.artworkPins).go();
      expect(await frees.settle(_pid), isTrue);
      expect(await frees.due(), isEmpty);
    },
  );
}
