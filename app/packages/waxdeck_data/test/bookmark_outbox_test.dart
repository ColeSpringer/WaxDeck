import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import 'sync_engine_test.dart';

const _book = 'bk-BOOK';
const _me = 'us-1';

Bookmark _mark(String id, int positionMs, {String? note}) => Bookmark(
  id: id,
  positionMs: positionMs,
  note: note,
  createdAt: DateTime.utc(2026, 9, 27, 12),
);

void main() {
  late MirrorDatabase db;
  late ScriptedRepository repo;
  late SyncEngine engine;

  setUp(() {
    db = MirrorDatabase(DatabaseConnection(NativeDatabase.memory()));
    repo = ScriptedRepository();
    engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: neverConnects(),
    )..account = _me;
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  Future<Map<String, BookmarkSync>> local({String owner = _me}) async => {
    for (final m in await engine.localBookmarks(_book, owner: owner))
      m.mark.id: m.sync,
  };

  test('a mark made offline is mirrored as pending and queued', () async {
    final changed = <String>[];
    final sub = engine.bookmarksChanged.listen(changed.add);
    addTearDown(sub.cancel);

    await engine.queueBookmarkCreate(
      _book,
      _mark('bm-A', 1500, note: 'the turn'),
      owner: _me,
    );

    final held = await engine.localBookmarks(_book, owner: _me);
    expect(held.single.mark.note, 'the turn');
    expect(held.single.sync, BookmarkSync.pending);
    expect(await db.select(db.outboxMutations).get(), hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(changed, [_book]);
  });

  test('the flush sends the minted id and the mark is then synced', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);

    await engine.flushOutbox();

    expect(repo.bookmarkCalls, ['create:$_book:bm-A:1500']);
    expect(await local(), {'bm-A': BookmarkSync.synced});
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test('a refusal keeps what the listener wrote, with the reason', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 99), owner: _me);
    repo.bookmarkError = const WaxDeckApiException(
      code: 'invalid-request',
      message: 'positionMs is past the end of the book',
      statusCode: 400,
    );

    await engine.flushOutbox();

    final held = (await engine.localBookmarks(_book, owner: _me)).single;
    expect(held.sync, BookmarkSync.refused);
    expect(held.refusal?.code, 'invalid-request');
    expect(held.refusal?.message, 'positionMs is past the end of the book');
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test('a transient failure leaves the mark pending and queued', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkError = const WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 500,
    );

    await expectLater(
      engine.flushOutbox(),
      throwsA(isA<WaxDeckApiException>()),
    );

    expect(await local(), {'bm-A': BookmarkSync.pending});
    expect(await db.select(db.outboxMutations).get(), hasLength(1));
  });

  test('deleting a mark whose create never left sends no create', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);

    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);
    await engine.flushOutbox();

    expect(await local(), isEmpty);
    expect(await db.select(db.outboxMutations).get(), isEmpty);
    // The delete goes anyway, for a create that may already be out.
    expect(repo.bookmarkCalls, ['delete:$_book:bm-A']);
  });

  test('a read while a removed mark is out does not bring it back', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkGate = Completer<void>();
    final flush = engine.flushOutbox();
    await Future<void>.delayed(Duration.zero);

    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);
    // The server already holds it, so a read answers it.
    await engine.storeBookmarks(_book, [_mark('bm-A', 1500)], owner: _me);
    repo.bookmarkGate!.complete();
    await flush;
    await engine.flushOutbox();

    expect(await local(), isEmpty);
    expect(repo.bookmarkCalls.last, 'delete:$_book:bm-A');
  });

  test('a create landing after the mirror is wiped queues nothing', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkGate = Completer<void>();
    final flush = engine.flushOutbox();
    await Future<void>.delayed(Duration.zero);

    await db.wipe();
    repo.bookmarkGate!.complete();
    await flush;

    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test('a mark removed while its create was out is removed after', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkGate = Completer<void>();
    final flush = engine.flushOutbox();
    await Future<void>.delayed(Duration.zero);
    expect(repo.bookmarkCalls, ['create:$_book:bm-A:1500']);

    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);
    repo.bookmarkGate!.complete();
    await flush;
    await engine.flushOutbox();

    expect(repo.bookmarkCalls, [
      'create:$_book:bm-A:1500',
      'delete:$_book:bm-A',
    ]);
    expect(await local(), isEmpty);
  });

  test('deleting a synced mark offline queues the delete', () async {
    await engine.storeBookmarks(_book, [_mark('bm-A', 1500)], owner: _me);

    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);
    expect(await local(), isEmpty);
    await engine.flushOutbox();

    expect(repo.bookmarkCalls, ['delete:$_book:bm-A']);
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test(
    'a pull replaces synced marks and keeps unsent and refused ones',
    () async {
      await engine.storeBookmarks(_book, [
        _mark('bm-A', 1000),
        _mark('bm-B', 2000),
      ], owner: _me);
      await engine.queueBookmarkCreate(_book, _mark('bm-D', 4000), owner: _me);
      repo.bookmarkError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'refused',
        statusCode: 400,
      );
      await engine.flushOutbox();
      repo.bookmarkError = null;
      await engine.queueBookmarkCreate(_book, _mark('bm-C', 3000), owner: _me);

      await (db.into(db.syncCursors)).insertOnConflictUpdate(
        const SyncCursorsCompanion(
          id: Value(1),
          serverSince: Value('scur-1'),
          serverAccount: Value(_me),
        ),
      );
      repo.serverPages.add(
        ServerSyncPage(
          nextSince: 'scur-2',
          events: [
            ServerSyncEvent(
              kind: 'bookmarks',
              pid: _book,
              bookmarks: [_mark('bm-A', 1100), _mark('bm-E', 5000)],
            ),
          ],
        ),
      );
      await engine.pullServer();

      final held = {
        for (final m in await engine.localBookmarks(_book, owner: _me))
          m.mark.id: (m.sync, m.mark.positionMs),
      };
      expect(held, {
        'bm-A': (BookmarkSync.synced, 1100),
        'bm-C': (BookmarkSync.pending, 3000),
        'bm-D': (BookmarkSync.refused, 4000),
        'bm-E': (BookmarkSync.synced, 5000),
      });
    },
  );

  test('a pull does not bring back a mark whose delete waits', () async {
    await engine.storeBookmarks(_book, [_mark('bm-A', 1000)], owner: _me);
    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);

    await engine.storeBookmarks(_book, [_mark('bm-A', 1000)], owner: _me);

    expect(await local(), isEmpty);
  });

  test("another account's marks are neither shown nor sent", () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: 'us-2');

    expect(await local(), isEmpty);
    await engine.flushOutbox();
    expect(repo.bookmarkCalls, isEmpty);

    engine.account = 'us-2';
    await engine.flushOutbox();
    expect(repo.bookmarkCalls, ['create:$_book:bm-A:1500']);
    expect(await local(owner: 'us-2'), {'bm-A': BookmarkSync.synced});
  });

  test('a fresh cursor mirrors the marks of the books held offline', () async {
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: _book,
            fileIndex: 0,
            essenceHash: 'e',
            etag: 'x',
            fileName: 'b.m4b',
            localPath: '/tmp/b.m4b',
            sizeBytes: 1,
            state: 'complete',
          ),
        );
    repo.bookmarks[_book] = [_mark('bm-A', 1000)];

    await engine.pullServer();

    expect(await local(), {'bm-A': BookmarkSync.synced});
  });

  test('removing a mark whose create still waits takes the create', () async {
    // The create landed and a read answered it, but its answer was lost:
    // the mark shows synced while the create still waits to be replayed.
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    await engine.storeBookmarks(_book, [_mark('bm-A', 1500)], owner: _me);

    await engine.queueBookmarkDelete(_book, 'bm-A', owner: _me);

    expect(
      [for (final m in await db.select(db.outboxMutations).get()) m.kind],
      ['bookmark-delete'],
    );
  });

  test('a mark removed on another device is dropped, not refused', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkError = const WaxDeckApiException(
      code: 'conflict',
      message: 'that bookmark was removed',
      statusCode: 409,
      params: {'reason': 'removed'},
    );

    await engine.flushOutbox();

    expect(await local(), isEmpty);
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test("a book's marks are sent while the socket is down", () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    await engine.queueBookmarkCreate('bk-OTHER', _mark('bm-B', 1), owner: _me);

    await engine.sendBookmarks(_book);

    expect(repo.bookmarkCalls, ['create:$_book:bm-A:1500']);
    expect(await local(), {'bm-A': BookmarkSync.synced});
  });

  test('a send the server cannot take leaves the write waiting', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);
    repo.bookmarkError = const WaxDeckApiException(
      code: 'transport',
      message: 'network unreachable',
    );

    await expectLater(
      engine.sendBookmarks(_book),
      throwsA(isA<WaxDeckApiException>()),
    );

    expect(await local(), {'bm-A': BookmarkSync.pending});
    expect(await db.select(db.outboxMutations).get(), hasLength(1));
  });

  test('storing the list this device already holds says nothing', () async {
    await engine.storeBookmarks(_book, [_mark('bm-A', 1500)], owner: _me);
    final changed = <String>[];
    final sub = engine.bookmarksChanged.listen(changed.add);
    addTearDown(sub.cancel);

    await engine.storeBookmarks(_book, [_mark('bm-A', 1500)], owner: _me);
    await Future<void>.delayed(Duration.zero);

    expect(changed, isEmpty);
  });

  test('a book fetched for offline has its marks', () async {
    repo.bookmarks[_book] = [_mark('bm-A', 1000)];

    await engine.fillBookmarks(_book);

    expect(await local(), {'bm-A': BookmarkSync.synced});
  });

  test('a fresh cursor cut short by a failure is minted again', () async {
    for (final pid in [_book, 'bk-OTHER']) {
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: 'e-$pid',
              etag: 'x',
              fileName: 'b.m4b',
              localPath: '/tmp/$pid.m4b',
              sizeBytes: 1,
              state: 'complete',
            ),
          );
    }
    repo.bookmarks[_book] = [_mark('bm-A', 1000)];
    repo.listBookmarksErrors['bk-OTHER'] = const WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 500,
    );

    await expectLater(engine.pullServer(), throwsA(isA<WaxDeckApiException>()));
    repo.listBookmarksErrors.clear();
    repo.bookmarks['bk-OTHER'] = [_mark('bm-B', 1)];
    await engine.pullServer();

    expect(await local(), {'bm-A': BookmarkSync.synced});
    expect(await engine.localBookmarks('bk-OTHER', owner: _me), hasLength(1));
  });

  test(
    "a cursor another account walked is minted again for this one",
    () async {
      // Its walk moved past this account's own events, which it never saw.
      await (db.into(db.syncCursors)).insertOnConflictUpdate(
        const SyncCursorsCompanion(
          id: Value(1),
          serverSince: Value('scur-9'),
          serverAccount: Value('us-2'),
        ),
      );

      await engine.pullServer();

      expect(repo.serverSinces, [null]);
      final cursor = await db.select(db.syncCursors).getSingle();
      expect(cursor.serverAccount, _me);
    },
  );

  test('an install upgraded with a cursor mints one for its account', () async {
    // Bookmarks arrived with v7: the marks already on the server reach
    // this device only through a fresh cursor.
    await (db.into(db.syncCursors)).insertOnConflictUpdate(
      const SyncCursorsCompanion(id: Value(1), serverSince: Value('scur-9')),
    );

    await engine.pullServer();

    expect(repo.serverSinces, [null]);
  });

  test('forgetting the server forgets the marks', () async {
    await engine.queueBookmarkCreate(_book, _mark('bm-A', 1500), owner: _me);

    await db.wipe();

    expect(await local(), isEmpty);
  });
}
