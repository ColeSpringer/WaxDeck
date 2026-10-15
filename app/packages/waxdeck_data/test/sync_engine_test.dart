import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

/// A scripted server: serves canned sync pages, records replayed
/// mutations, and can fail transiently to exercise crash-safe flushing.
class ScriptedRepository implements WaxDeckRepository {
  @override
  String? authToken;

  final catalogPages = <CatalogSyncPage>[];
  final serverPages = <ServerSyncPage>[];
  int catalogCalls = 0;
  bool resetCatalogOnce = false;

  final replayed = <String>[];
  final reportedSessions = <String>{};

  /// What each reported session claimed it saved, so a replay from the
  /// outbox can be checked for carrying the field at all.
  final reportedSkippedMs = <String, int?>{};
  int duplicateListens = 0;
  int failNextMutations = 0;

  ItemSummary item(
    String pid,
    String title, {
    MediaType mediaType = MediaType.music,
  }) => ItemSummary(
    pid: pid,
    mediaType: mediaType,
    title: title,
    durationMs: 1000,
  );

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    if (since != null && resetCatalogOnce) {
      resetCatalogOnce = false;
      throw const WaxDeckApiException(
        code: 'sync-reset',
        message: 'reset',
        statusCode: 410,
      );
    }
    catalogCalls++;
    if (catalogPages.isEmpty) {
      return const CatalogSyncPage(nextSince: 'cur-0');
    }
    return catalogPages.removeAt(0);
  }

  /// The cursor each server walk was asked from; null mints a fresh one.
  final serverSinces = <String?>[];

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
    serverSinces.add(since);
    if (serverPages.isEmpty) {
      return const ServerSyncPage(nextSince: 'scur-0');
    }
    return serverPages.removeAt(0);
  }

  @override
  Future<void> putPlayState(
    String pid,
    int positionMs, {
    DateTime? recordedAt,
  }) async {
    _maybeFail();
    replayed.add('position:$pid:$positionMs:${recordedAt != null}');
  }

  @override
  Future<PlayState> setStar(
    String pid,
    bool starred, {
    DateTime? recordedAt,
  }) async {
    _maybeFail();
    replayed.add('star:$pid:$starred:${recordedAt != null}');
    return PlayState(
      pid: pid,
      positionMs: 0,
      played: false,
      finished: false,
      playCount: 0,
      starred: starred,
    );
  }

  @override
  Future<PlayState> setRating(
    String pid,
    int? rating, {
    DateTime? recordedAt,
  }) async {
    _maybeFail();
    if (pid == 'tr-GONE') {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'gone',
        statusCode: 404,
      );
    }
    replayed.add('rating:$pid:$rating:${recordedAt != null}');
    return PlayState(
      pid: pid,
      positionMs: 0,
      played: false,
      finished: false,
      playCount: 0,
      starred: false,
      rating: rating,
    );
  }

  @override
  Future<ListenOutcome> reportListens(List<ListenSession> sessions) async {
    var accepted = 0;
    for (final s in sessions) {
      reportedSkippedMs[s.sessionId] = s.skippedMs;
      if (!reportedSessions.add(s.sessionId)) {
        duplicateListens++;
      } else {
        accepted++;
      }
    }
    return ListenOutcome(accepted: accepted, duplicates: 0);
  }

  @override
  Future<List<PlayState>> listPlayStates(List<String> pids) async => const [];

  /// The account's preference document as the server holds it.
  Prefs prefs = const Prefs();

  /// Every preference document written, in order.
  final prefsWrites = <Prefs>[];

  /// Thrown by every preference write while set.
  WaxDeckApiException? prefsWriteError;

  /// Holds every preference read until completed, when set.
  Completer<void>? prefsReadGate;

  @override
  Future<Prefs> getPrefs() async {
    await prefsReadGate?.future;
    return prefs;
  }

  @override
  Future<Prefs> putPrefs(Prefs next) async {
    final error = prefsWriteError;
    if (error != null) throw error;
    prefsWrites.add(next);
    return prefs = next;
  }

  /// Bookmarks the server holds, per book, as creates and deletes left
  /// them; and every create and delete sent, in order.
  final bookmarks = <String, List<Bookmark>>{};
  final bookmarkCalls = <String>[];

  /// Thrown by the next bookmark write while set.
  WaxDeckApiException? bookmarkError;

  /// Holds every bookmark create until completed, when set.
  Completer<void>? bookmarkGate;

  /// What reading one book's marks throws, per book.
  final listBookmarksErrors = <String, WaxDeckApiException>{};

  @override
  Future<List<Bookmark>> listBookmarks(String pid) async {
    bookmarkCalls.add('list:$pid');
    if (listBookmarksErrors[pid] case final error?) throw error;
    return [...?bookmarks[pid]];
  }

  @override
  Future<Bookmark> createBookmark(
    String pid,
    int positionMs, {
    String? note,
    String? id,
  }) async {
    bookmarkCalls.add('create:$pid:$id:$positionMs');
    await bookmarkGate?.future;
    final error = bookmarkError;
    if (error != null) throw error;
    final mark = Bookmark(
      id: id ?? 'bm-SERVER',
      positionMs: positionMs,
      note: note,
      createdAt: DateTime.utc(2026, 9, 27),
    );
    (bookmarks[pid] ??= []).add(mark);
    return mark;
  }

  @override
  Future<void> deleteBookmark(String pid, String bookmarkId) async {
    bookmarkCalls.add('delete:$pid:$bookmarkId');
    final error = bookmarkError;
    if (error != null) throw error;
    bookmarks[pid]?.removeWhere((m) => m.id == bookmarkId);
  }

  void _maybeFail() {
    if (failNextMutations > 0) {
      failNextMutations--;
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'transient',
        statusCode: 500,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A channel factory whose connections never come up: the engine under
/// test is driven directly, not over a socket.
EventsChannelFactory neverConnects() {
  return ({required onFrame, required onDone, required subscribe}) {
    return EventsChannel(
      url: 'ws://unused',
      authToken: null,
      onFrame: onFrame,
      onDone: onDone,
      subscribe: subscribe,
    );
  };
}

/// Same, but hands the frame sink back so a test can deliver one: the
/// engine's frame routing is otherwise reachable only over a socket.
EventsChannelFactory capturingFrames(
  void Function(void Function(String)) sink,
) {
  return ({required onFrame, required onDone, required subscribe}) {
    sink(onFrame);
    return EventsChannel(
      url: 'ws://unused',
      authToken: null,
      onFrame: onFrame,
      onDone: onDone,
      subscribe: subscribe,
    );
  };
}

/// The account the preference tests queue for.
const _owner = 'us-1';

/// A channel factory whose connections come up at once and carry
/// nothing: the engine is online, with no server frames to drive it.
EventsChannelFactory _connects() {
  return ({required onFrame, required onDone, required subscribe}) =>
      _QuietChannel(onFrame: onFrame, onDone: onDone, subscribe: subscribe);
}

class _QuietChannel extends EventsChannel {
  _QuietChannel({
    required super.onFrame,
    required super.onDone,
    required super.subscribe,
  }) : super(url: 'ws://unused', authToken: null);

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {}
}

/// Counts what reaches the database, for what a sync costs rather than
/// what it leaves.
class _Counter extends QueryInterceptor {
  final selects = <String>[];
  final deletes = <String>[];
  var transactions = 0;

  void reset() {
    selects.clear();
    deletes.clear();
    transactions = 0;
  }

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    deletes.add(statement);
    return super.runDelete(executor, statement, args);
  }
}

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
    )..account = _owner;
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  Future<List<MirrorItem>> mirror() => (db.select(
    db.mirrorItems,
  )..orderBy([(t) => OrderingTerm.asc(t.sortKey)])).get();

  test('snapshot pages fill the mirror and store the FIRST cursor', () async {
    // The server repeats the frozen cursor on every page, but a server
    // racing its own feed could differ; the client must keep the first
    // page's cursor, the one captured before anything was read, or a
    // mid-snapshot change falls between the two cursors and is lost.
    repo.catalogPages.addAll([
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-A',
            item: repo.item('tr-A', 'Alpha'),
          ),
        ],
        nextCursor: 'page2',
        nextSince: 'cur-1',
      ),
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-B',
            item: repo.item('tr-B', 'Bravo'),
          ),
        ],
        nextSince: 'cur-2-later',
      ),
    ]);
    await engine.pullCatalog();
    final rows = await mirror();
    expect(rows.map((r) => r.title), ['Alpha', 'Bravo']);
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.catalogSince, 'cur-1');
  });

  test(
    'deltas upsert, tombstones match on the ULID, unknown ops drop',
    () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-AAA',
              item: repo.item('tr-AAA', 'Alpha'),
            ),
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'bk-BBB',
              item: repo.item('bk-BBB', 'Book'),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();

      repo.catalogPages.add(
        const CatalogSyncPage(
          entries: [
            // The tombstone carries the track prefix although the item
            // was mirrored as a book: the ULID is what matters.
            CatalogSyncEntry(op: 'delete', pid: 'tr-BBB'),
            CatalogSyncEntry(op: 'sideways', pid: 'tr-AAA'),
          ],
          nextSince: 'cur-2',
        ),
      );
      await engine.pullCatalog();

      final rows = await mirror();
      expect(rows.map((r) => r.pid), ['tr-AAA']);
    },
  );

  test('an item whose kind changed replaces its old row', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Chapter One'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();

    // Treat as audiobook: the same ULID comes back under the book's
    // prefix, with no tombstone for the old one.
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-CCC',
            item: repo.item(
              'bk-CCC',
              'The Loose Chapters',
              mediaType: MediaType.audiobook,
            ),
          ),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();

    final rows = await mirror();
    expect(rows.map((r) => (r.pid, r.title)), [
      ('bk-CCC', 'The Loose Chapters'),
    ]);
    expect(
      (await db.select(db.syncCursors).getSingle()).catalogSince,
      'cur-2',
      reason: 'the page applied and the cursor moved past it',
    );
  });

  test('a kind change moves what the device keeps for the item', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-CCC',
            item: repo.item(
              'bk-CCC',
              'Chapter One',
              mediaType: MediaType.audiobook,
            ),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();
    final at = DateTime.utc(2026, 10, 1);
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'bk-CCC',
            fileIndex: 0,
            essenceHash: 'e1',
            etag: 'x',
            fileName: 'chapter-one.mp3',
            localPath: '/downloads/chapter-one.mp3',
            sizeBytes: 1024,
            state: 'complete',
          ),
        );
    await db
        .into(db.mirrorPlayStates)
        .insert(
          const MirrorPlayStatesCompanion(
            pid: Value('bk-CCC'),
            positionMs: Value(61000),
          ),
        );
    await db
        .into(db.queueEntries)
        .insert(
          QueueEntriesCompanion.insert(
            queueId: 'q1',
            pid: 'bk-CCC',
            position: 0,
            sourceRank: 0,
          ),
        );
    await db
        .into(db.artworkPins)
        .insert(
          ArtworkPinsCompanion.insert(
            pid: 'bk-CCC',
            sizePx: 300,
            artUrl: '/media/art?pid=bk-CCC',
            etag: 'a',
            localPath: '/art/ccc.jpg',
            sizeBytes: 2048,
            pinnedAt: at,
          ),
        );

    // Treat as music: the same ULID, under the track's prefix. A track
    // is one file, so the one the device holds is all of it.
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Chapter One'),
          ),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();

    expect((await db.select(db.downloadRecords).get()).map((r) => r.pid), [
      'tr-CCC',
    ], reason: 'the download plays offline under the new pid');
    final state = await db.select(db.mirrorPlayStates).getSingle();
    expect((state.pid, state.positionMs), ('tr-CCC', 61000));
    expect((await db.select(db.queueEntries).get()).map((r) => r.pid), [
      'tr-CCC',
    ]);
    expect((await db.select(db.artworkPins).get()).map((r) => r.pid), [
      'tr-CCC',
    ]);
  });

  /// What a device keeps for one item: a download of [files] files in
  /// [state] with its pinned cover, a play state, and a queue entry.
  Future<void> keepFor(
    String pid, {
    int files = 1,
    String state = 'complete',
  }) async {
    for (var i = 0; i < files; i++) {
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: i,
              essenceHash: '$pid-e$i',
              etag: 'x',
              fileName: '$pid-$i.mp3',
              localPath: state == 'complete' ? '/downloads/$pid-$i.mp3' : '',
              sizeBytes: 1024,
              state: state,
            ),
          );
    }
    await db
        .into(db.mirrorPlayStates)
        .insert(
          MirrorPlayStatesCompanion(
            pid: Value(pid),
            positionMs: const Value(61000),
          ),
        );
    await db
        .into(db.queueEntries)
        .insert(
          QueueEntriesCompanion.insert(
            queueId: 'q-$pid',
            pid: pid,
            position: 0,
            sourceRank: 0,
          ),
        );
    await db
        .into(db.artworkPins)
        .insert(
          ArtworkPinsCompanion.insert(
            pid: pid,
            sizePx: 300,
            artUrl: '/media/art?pid=$pid',
            etag: 'a',
            localPath: '/art/$pid.jpg',
            sizeBytes: 2048,
            pinnedAt: DateTime.utc(2026, 10, 1),
          ),
        );
  }

  Future<List<String>> pidsIn(TableInfo<Table, dynamic> table) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT pid FROM ${table.actualTableName} ORDER BY pid',
              readsFrom: {table},
            )
            .get())
      row.read<String>('pid'),
  ];

  test('a re-mirror moves what the device keeps for an item whose kind '
      'changed', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Chapter One'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-DDD',
            item: repo.item('bk-DDD', 'Delta', mediaType: MediaType.audiobook),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-EEE',
            item: repo.item('bk-EEE', 'Echo', mediaType: MediaType.audiobook),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();
    await keepFor('tr-CCC');
    await keepFor('bk-DDD', files: 3);
    await keepFor('bk-EEE');
    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    // Away while a track became a book and both books became tracks,
    // long enough that the server answers the cursor with a reset: the
    // mirror comes back whole, with no delta naming any change.
    repo.resetCatalogOnce = true;
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-CCC',
            item: repo.item(
              'bk-CCC',
              'The Loose Chapters',
              mediaType: MediaType.audiobook,
            ),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-DDD',
            item: repo.item('tr-DDD', 'Delta, Part One'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-EEE',
            item: repo.item('tr-EEE', 'Echo'),
          ),
        ],
        nextSince: 'cur-9',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    expect(
      (await mirror()).map((r) => r.pid),
      unorderedEquals(['bk-CCC', 'tr-DDD', 'tr-EEE']),
    );
    // The one-file book's download plays offline as the track; the
    // track's one file may be any part of its book, and the book's three
    // files any part of its track, so both stay put to be reclaimed.
    expect(await pidsIn(db.downloadRecords), [
      'bk-DDD',
      'bk-DDD',
      'bk-DDD',
      'tr-CCC',
      'tr-EEE',
    ]);
    expect(reclaimed, ['tr-CCC', 'bk-DDD']);
    expect(await pidsIn(db.artworkPins), ['bk-DDD', 'tr-CCC', 'tr-EEE']);
    expect(await pidsIn(db.mirrorPlayStates), ['bk-CCC', 'tr-DDD', 'tr-EEE']);
    expect(await pidsIn(db.queueEntries), ['bk-CCC', 'tr-DDD', 'tr-EEE']);
  });

  test(
    'a book download of several files is not moved onto one track',
    () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'bk-DDD',
              item: repo.item(
                'bk-DDD',
                'Delta',
                mediaType: MediaType.audiobook,
              ),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();
      await keepFor('bk-DDD', files: 3);
      final reclaimed = <String>[];
      final sub = engine.itemsRemoved.listen(reclaimed.add);

      // Treat as music: the book's primary part keeps the ULID as a track,
      // and nothing on this device says which of the three files that is.
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-DDD',
              item: repo.item('tr-DDD', 'Delta, Part Two'),
            ),
          ],
          nextSince: 'cur-2',
        ),
      );
      await engine.pullCatalog();
      await pumpEventQueue();
      await sub.cancel();

      expect((await mirror()).map((r) => r.pid), ['tr-DDD']);
      expect(await pidsIn(db.downloadRecords), ['bk-DDD', 'bk-DDD', 'bk-DDD']);
      // Published for the downloads store, which frees the files and the
      // cover pinned with them.
      expect(reclaimed, ['bk-DDD']);
      expect(await pidsIn(db.artworkPins), ['bk-DDD']);
      expect(await pidsIn(db.mirrorPlayStates), ['tr-DDD']);
      expect(await pidsIn(db.queueEntries), ['tr-DDD']);
    },
  );

  test('a one-file download is not moved onto a book, which may hold '
      'more', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          for (final (pid, title) in [
            ('tr-AAA', 'Chapter One'),
            ('tr-BBB', 'Chapter Two'),
            ('tr-CCC', 'Chapter Three'),
          ])
            CatalogSyncEntry(
              op: 'upsert',
              pid: pid,
              item: repo.item(pid, title),
            ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();
    await keepFor('tr-AAA');
    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    // Treat album as one audiobook: the first track's ULID comes back as
    // the book, and the other two are folded into it.
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-AAA',
            item: repo.item(
              'bk-AAA',
              'The Album',
              mediaType: MediaType.audiobook,
            ),
          ),
          const CatalogSyncEntry(
            op: 'delete',
            pid: 'tr-BBB',
            reason: 'removed',
          ),
          const CatalogSyncEntry(
            op: 'delete',
            pid: 'tr-CCC',
            reason: 'removed',
          ),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    expect((await mirror()).map((r) => r.pid), ['bk-AAA']);
    // The book's first part is not the book: left to be reclaimed, so it
    // shows as not downloaded rather than downloaded and one part long.
    expect(await pidsIn(db.downloadRecords), ['tr-AAA']);
    expect(reclaimed, ['tr-AAA', 'tr-BBB', 'tr-CCC']);
    expect(await pidsIn(db.artworkPins), ['tr-AAA']);
    expect(await pidsIn(db.mirrorPlayStates), ['bk-AAA']);
    expect(await pidsIn(db.queueEntries), ['bk-AAA']);
  });

  for (final state in ['pending', 'paused']) {
    test('a $state download stays with the pid its transfer runs under, '
        'to be reclaimed', () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'bk-DDD',
              item: repo.item(
                'bk-DDD',
                'Delta',
                mediaType: MediaType.audiobook,
              ),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();
      await keepFor('bk-DDD', state: state);
      final reclaimed = <String>[];
      final sub = engine.itemsRemoved.listen(reclaimed.add);

      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-DDD',
              item: repo.item('tr-DDD', 'Delta'),
            ),
          ],
          nextSince: 'cur-2',
        ),
      );
      await engine.pullCatalog();
      await pumpEventQueue();
      await sub.cancel();

      // The download manager holds the transfer under the old pid, so
      // that is where it is stopped and its rows dropped.
      expect(await pidsIn(db.downloadRecords), ['bk-DDD']);
      expect(reclaimed, ['bk-DDD']);
      expect(await pidsIn(db.artworkPins), ['bk-DDD']);
      expect(await pidsIn(db.mirrorPlayStates), ['tr-DDD']);
    });
  }

  test('a download moves only onto a pid that holds none', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-DDD',
            item: repo.item('bk-DDD', 'Delta', mediaType: MediaType.audiobook),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();
    await keepFor('bk-DDD');
    // Fetched again under its new pid before the delta said it moved.
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'tr-DDD',
            fileIndex: 0,
            essenceHash: 'bk-DDD-e0',
            etag: 'x',
            fileName: 'tr-DDD-0.mp3',
            localPath: '/downloads/tr-DDD-0.mp3',
            sizeBytes: 1024,
            state: 'complete',
          ),
        );
    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-DDD',
            item: repo.item('tr-DDD', 'Delta'),
          ),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    expect(await pidsIn(db.downloadRecords), ['bk-DDD', 'tr-DDD']);
    expect(reclaimed, ['bk-DDD'], reason: 'nothing else frees the old one');
  });

  test(
    "a snapshot that meets one item under two pids keeps the later page's",
    () async {
      // The item changed kind between the two page reads, and its new
      // title sorts it past the cursor, so it is read twice.
      repo.catalogPages.addAll([
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-AAA',
              item: repo.item('tr-AAA', 'Alpha'),
            ),
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-XXX',
              item: repo.item('tr-XXX', 'Chapter One'),
            ),
          ],
          nextCursor: 'page2',
          nextSince: 'cur-1',
        ),
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'bk-XXX',
              item: repo.item(
                'bk-XXX',
                'The Loose Chapters',
                mediaType: MediaType.audiobook,
              ),
            ),
          ],
          nextSince: 'cur-1',
        ),
      ]);
      await engine.pullCatalog();

      expect((await mirror()).map((r) => (r.pid, r.title)), [
        ('tr-AAA', 'Alpha'),
        ('bk-XXX', 'The Loose Chapters'),
      ]);
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-1',
      );
    },
  );

  test(
    'a play state moved by a kind change still answers to the old pid',
    () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'bk-CCC',
              item: repo.item(
                'bk-CCC',
                'Chapter',
                mediaType: MediaType.audiobook,
              ),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();
      await keepFor('bk-CCC');
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-CCC',
              item: repo.item('tr-CCC', 'Chapter'),
            ),
          ],
          nextSince: 'cur-2',
        ),
      );
      await engine.pullCatalog();

      // A queue entry saved before the delta still names the book.
      expect((await engine.localPlayState('bk-CCC'))?.positionMs, 61000);
      expect((await engine.localPlayState('tr-CCC'))?.positionMs, 61000);
      expect(await engine.localPlayState('tr-ZZZ'), isNull);
    },
  );

  test('ordinary upserts read the mirror once a page, and land', () async {
    final counter = _Counter();
    final counted = MirrorDatabase(
      DatabaseConnection(NativeDatabase.memory().interceptWith(counter)),
    );
    final quiet = SyncEngine(
      db: counted,
      repository: repo,
      channelFactory: neverConnects(),
    );
    addTearDown(() async {
      quiet.dispose();
      await counted.close();
    });
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-AAA',
            item: repo.item('tr-AAA', 'Alpha'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-BBB',
            item: repo.item('tr-BBB', 'Bravo'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await quiet.pullCatalog();
    counter.reset();

    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-AAA',
            item: repo.item('tr-AAA', 'Alpha (Remastered)'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Charlie'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-DDD',
            item: repo.item('tr-DDD', 'Delta'),
          ),
        ],
        nextSince: 'cur-2',
      ),
    );
    await quiet.pullCatalog();

    // The rare kind change is looked for once for the page, not paid
    // for per item in a transaction of its own.
    expect(
      counter.selects.where((s) => s.contains('"mirror_items"')),
      hasLength(1),
    );
    expect(counter.transactions, 0);
    expect(counter.deletes, isEmpty);
    final rows = await (counted.select(
      counted.mirrorItems,
    )..orderBy([(t) => OrderingTerm.asc(t.sortKey)])).get();
    expect(rows.map((r) => (r.pid, r.title)), [
      ('tr-AAA', 'Alpha (Remastered)'),
      ('tr-BBB', 'Bravo'),
      ('tr-CCC', 'Charlie'),
      ('tr-DDD', 'Delta'),
    ]);
  });

  test('only an unrecoverable delete publishes a pid to reclaim', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-AAA',
            item: repo.item('tr-AAA', 'Alpha'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-BBB',
            item: repo.item('tr-BBB', 'Bravo'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Charlie'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();

    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    repo.catalogPages.add(
      const CatalogSyncPage(
        entries: [
          // Trashed: the row goes, the bytes stay, because a restore
          // would otherwise cost the whole download again.
          CatalogSyncEntry(op: 'delete', pid: 'tr-AAA', reason: 'hidden'),
          // Deleted outright: nothing on the server can put it back.
          CatalogSyncEntry(op: 'delete', pid: 'tr-BBB', reason: 'removed'),
          // A server too old to say, or a value this build does not
          // know, is treated as the half that reclaims nothing.
          CatalogSyncEntry(op: 'delete', pid: 'tr-CCC'),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    // Every one of them left the mirror; only one freed anything.
    expect(await mirror(), isEmpty);
    expect(reclaimed, ['tr-BBB']);
  });

  test('reclaim names the pid the mirror stored, not the wire pid', () async {
    // A tombstone for an item that is genuinely gone cannot know its
    // kind, so it carries the track prefix whatever the item was. A
    // download and an artwork pin for an audiobook were written under
    // `bk-`, so publishing the wire pid reclaims nothing at all.
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'bk-DDD',
            item: repo.item('bk-DDD', 'Delta', mediaType: MediaType.audiobook),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();

    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);
    repo.catalogPages.add(
      const CatalogSyncPage(
        entries: [
          CatalogSyncEntry(op: 'delete', pid: 'tr-DDD', reason: 'removed'),
        ],
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    expect(await mirror(), isEmpty, reason: 'the ULID still matches');
    expect(reclaimed, ['bk-DDD']);
  });

  test(
    'upsert-show entries are dropped without corrupting the mirror',
    () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-AAA',
              item: repo.item('tr-AAA', 'Alpha'),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();

      // Podcast milestone servers emit upsert-show entries carrying a show
      // payload and no item; mirrors that do not track shows drop them.
      repo.catalogPages.add(
        const CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert-show',
              pid: 'pc-SHOW',
              show: PodcastShow(
                pid: 'pc-SHOW',
                title: 'The Prancing Pony Hour',
                sourceType: 'rss',
              ),
            ),
          ],
          nextSince: 'cur-2',
        ),
      );
      await engine.pullCatalog();

      final rows = await mirror();
      expect(rows.map((r) => r.pid), ['tr-AAA']);
      final cursors = await db.select(db.syncCursors).getSingle();
      expect(cursors.catalogSince, 'cur-2');
    },
  );

  test('a sync-reset drops the mirror and re-snapshots', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-OLD',
            item: repo.item('tr-OLD', 'Old'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();

    repo.resetCatalogOnce = true;
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-NEW',
            item: repo.item('tr-NEW', 'New'),
          ),
        ],
        nextSince: 'cur-9',
      ),
    );
    await engine.pullCatalog();

    final rows = await mirror();
    expect(rows.map((r) => r.pid), ['tr-NEW']);
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.catalogSince, 'cur-9');
  });

  test('the outbox replays in order with recorded times', () async {
    await engine.queueCheckpoint('tr-A', 5000);
    await engine.queueStar('tr-A', true);
    await engine.queueRating('tr-B', 80);
    await engine.flushOutbox();
    expect(repo.replayed, [
      'position:tr-A:5000:true',
      'star:tr-A:true:true',
      'rating:tr-B:80:true',
    ]);
    final left = await db.select(db.outboxMutations).get();
    expect(left, isEmpty);
  });

  test('offline mutations land in the local mirror immediately', () async {
    await engine.queueCheckpoint('tr-A', 5000);
    await engine.queueStar('tr-A', true);
    final st = await db.select(db.mirrorPlayStates).getSingle();
    expect(st.positionMs, 5000);
    expect(st.starred, isTrue);
  });

  test('a transient failure keeps the entry; the retry replays it', () async {
    await engine.queueCheckpoint('tr-A', 1000);
    await engine.queueStar('tr-B', true);
    repo.failNextMutations = 1;
    await expectLater(engine.flushOutbox(), throwsA(isA<Object>()));
    // The first entry failed transiently and stayed queued.
    expect(await db.select(db.outboxMutations).get(), hasLength(2));
    await engine.flushOutbox();
    expect(repo.replayed, ['position:tr-A:1000:true', 'star:tr-B:true:true']);
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test('a permanently rejected entry is dropped, not wedged', () async {
    await engine.queueRating('tr-GONE', 50);
    await engine.queueStar('tr-A', true);
    await engine.flushOutbox();
    expect(repo.replayed, ['star:tr-A:true:true']);
    expect(await db.select(db.outboxMutations).get(), isEmpty);
  });

  test('queued listens flush once even when the flush repeats', () async {
    final session = ListenSession(
      sessionId: 'S1',
      pid: 'tr-A',
      startedAt: DateTime.utc(2026, 7, 18),
      msPlayed: 4000,
      finished: true,
    );
    await engine.queueListen(session);
    await engine.queueListen(session); // duplicate queue attempt
    await engine.flushOutbox();
    await engine.queueListen(session); // replay after a crash
    await engine.flushOutbox();
    expect(repo.reportedSessions, {'S1'});
    expect(repo.duplicateListens, 1); // absorbed by idempotency server-side
    expect(await db.select(db.outboxListens).get(), isEmpty);
  });

  group('a preference patch', () {
    test('lands over the document as it stands', () async {
      // Another device moved the timezone and the pins while this one
      // was offline; the patch carries only what this one changed.
      repo.prefs = const Prefs(timezone: 'Europe/Madrid', pinned: ['AL-1']);
      final flushed = engine.prefsFlushed.first;
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);

      await engine.flushOutbox();
      await flushed;

      expect(repo.prefsWrites, hasLength(1));
      expect(repo.prefs.timezone, 'Europe/Madrid');
      expect(repo.prefs.pinned, ['AL-1']);
      expect(repo.prefs.locale, 'es');
      expect(await engine.pendingPrefsPatch(_owner), isNull);
    });

    test('the server refuses is dropped and reported', () async {
      repo.prefsWriteError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'unknown timezone',
        statusCode: 400,
      );
      final refused = engine.prefsRefused.first;
      await engine.queuePrefsPatch({'timezone': 'Mars/Olympus'}, owner: _owner);

      await engine.flushOutbox();
      await refused;

      expect(await engine.pendingPrefsPatch(_owner), isNull);
    });

    test('that fails in passing waits for the next flush', () async {
      repo.prefsWriteError = const WaxDeckApiException(
        code: 'internal',
        message: 'transient',
        statusCode: 500,
      );
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);

      await expectLater(
        engine.flushOutbox(),
        throwsA(isA<WaxDeckApiException>()),
      );
      expect(await engine.pendingPrefsPatch(_owner), {'locale': 'es'});

      repo.prefsWriteError = null;
      await engine.flushOutbox();
      expect(repo.prefs.locale, 'es');
    });

    test('that no longer reads is dropped, not wedged', () async {
      // Written by a build that spelled a field some other way. Nothing
      // will ever read it, and a flush that threw on it would never get
      // past it to the rest of the queue.
      await db
          .into(db.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              kind: 'prefs',
              pid: _owner,
              recordedAt: DateTime.utc(2026, 9, 27),
              payload: const Value('{"crossfadeSeconds": "loud"}'),
            ),
          );
      await engine.queueCheckpoint('tr-A', 1000);
      final refused = engine.prefsRefused.first;

      await engine.flushOutbox();
      await refused;

      expect(repo.prefsWrites, isEmpty);
      expect(repo.replayed, ['position:tr-A:1000:true']);
      expect(await db.select(db.outboxMutations).get(), isEmpty);
    });

    test('queued while connected is sent without a reconnect', () async {
      // A patch queued with the socket up would otherwise wait for the
      // next reconnect, and every write after it would queue behind it.
      final live = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: _connects(),
      )..account = _owner;
      addTearDown(live.dispose);
      await live.start();
      await pumpEventQueue();
      expect(live.current.online, isTrue);

      final flushed = live.prefsFlushed.first;
      await live.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      await flushed;

      expect(repo.prefs.locale, 'es');
    });

    test('a change queued while one is out waits for the next flush', () async {
      // The flush sends what it read; a change made while it was out is
      // merged into the waiting entry and is not answered by it.
      await engine.queuePrefsPatch({
        'pinned': ['AL-1'],
      }, owner: _owner);
      final gate = repo.prefsReadGate = Completer<void>();
      final flushing = engine.flushOutbox();
      await pumpEventQueue();

      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      gate.complete();
      await flushing;

      expect(repo.prefs.pinned, ['AL-1']);
      expect(await engine.pendingPrefsPatch(_owner), {'locale': 'es'});
    });

    test('a refusal keeps what was queued while it was out', () async {
      await engine.queuePrefsPatch({'timezone': 'Mars/Olympus'}, owner: _owner);
      repo.prefsWriteError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'unknown timezone',
        statusCode: 400,
      );
      final gate = repo.prefsReadGate = Completer<void>();
      final flushing = engine.flushOutbox();
      await pumpEventQueue();

      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      gate.complete();
      await flushing;

      expect(await engine.pendingPrefsPatch(_owner), {'locale': 'es'});
    });

    test('that is not an object reads as nothing waiting', () async {
      await db
          .into(db.outboxMutations)
          .insert(
            OutboxMutationsCompanion.insert(
              kind: 'prefs',
              pid: _owner,
              recordedAt: DateTime.utc(2026, 9, 27),
              payload: const Value('not json'),
            ),
          );

      expect(await engine.pendingPrefsPatch(_owner), isNull);
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      expect(await engine.pendingPrefsPatch(_owner), {'locale': 'es'});
    });

    test('sent after the mirror closed raises nothing', () async {
      // Teardown can close the mirror under a flush a write scheduled;
      // an error escaping that unawaited flush has no handler.
      final mirror = MirrorDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      final live = SyncEngine(
        db: mirror,
        repository: repo,
        channelFactory: _connects(),
      )..account = _owner;
      addTearDown(live.dispose);
      await live.start();
      await pumpEventQueue();
      final gate = repo.prefsReadGate = Completer<void>();
      await live.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      await pumpEventQueue();

      await mirror.close();
      gate.complete();
      await pumpEventQueue();
    });

    test('waits for its own account', () async {
      // The outbox outlives a session, so a patch one account left behind
      // is not the next account's to send: it goes out when its own
      // account is back.
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      engine.account = 'us-2';

      await engine.flushOutbox();
      expect(repo.prefsWrites, isEmpty);
      expect(await engine.pendingPrefsPatch('us-2'), isNull);

      engine.account = _owner;
      await engine.flushOutbox();
      expect(repo.prefs.locale, 'es');
    });

    test('a flush hands over what the server stored', () async {
      repo.prefs = const Prefs(timezone: 'Europe/Madrid');
      final flushed = engine.prefsFlushed.first;
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);

      await engine.flushOutbox();
      final flush = await flushed;

      expect(flush.owner, _owner);
      expect(flush.stored.timezone, 'Europe/Madrid');
      expect(flush.stored.locale, 'es');
      expect(flush.waiting, isNull);
    });

    test('sent now, does not wait for the socket', () async {
      // The server can answer while the socket is down: a caller with a
      // reason to think so sends the waiting patch itself.
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);

      await engine.sendPrefs(_owner);

      expect(repo.prefs.locale, 'es');
      expect(await engine.pendingPrefsPatch(_owner), isNull);
    });

    test('sent now and failing in passing, still waits', () async {
      await engine.queuePrefsPatch({'locale': 'es'}, owner: _owner);
      repo.prefsWriteError = const WaxDeckApiException(
        code: 'transport',
        message: 'no route to host',
      );

      await expectLater(
        engine.sendPrefs(_owner),
        throwsA(isA<WaxDeckApiException>()),
      );

      expect(await engine.pendingPrefsPatch(_owner), {'locale': 'es'});
    });

    test('two sort changes queued keep both', () async {
      await engine.queuePrefsPatch({
        'browseSorts': {'year': 'name'},
      }, owner: _owner);
      await engine.queuePrefsPatch({
        'browseSorts': {'genre': 'count'},
      }, owner: _owner);

      expect(await engine.pendingPrefsPatch(_owner), {
        'browseSorts': {'year': 'name', 'genre': 'count'},
      });
    });
  });

  test('server deltas hydrate mirrored play states', () async {
    repo.serverPages.addAll([const ServerSyncPage(nextSince: 'scur-1')]);
    await engine.pullServer(); // mints
    repo.serverPages.add(
      const ServerSyncPage(
        events: [
          ServerSyncEvent(
            kind: 'play-state',
            pid: 'tr-A',
            playState: PlayState(
              pid: 'tr-A',
              positionMs: 7000,
              played: false,
              finished: false,
              playCount: 0,
              starred: true,
            ),
          ),
          ServerSyncEvent(kind: 'mystery'),
        ],
        nextSince: 'scur-2',
      ),
    );
    await engine.pullServer();
    final st = await db.select(db.mirrorPlayStates).getSingle();
    expect(st.positionMs, 7000);
    expect(st.starred, isTrue);
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.serverSince, 'scur-2');
  });

  test('entity-state markers announce their pid without mirroring', () async {
    repo.serverPages.addAll([const ServerSyncPage(nextSince: 'scur-1')]);
    await engine.pullServer(); // mints
    final announced = <String>[];
    final sub = engine.playStateChanged.listen(announced.add);
    repo.serverPages.add(
      const ServerSyncPage(
        events: [
          ServerSyncEvent(kind: 'entity-state', pid: 'al-A'),
          ServerSyncEvent(kind: 'entity-state', pid: 'ar-B'),
        ],
        nextSince: 'scur-2',
      ),
    );
    await engine.pullServer();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // The marker is the whole payload: it invalidates the entity views
    // and writes nothing to the item mirror.
    expect(announced, ['al-A', 'ar-B']);
    expect(await db.select(db.mirrorPlayStates).get(), isEmpty);
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.serverSince, 'scur-2');
  });

  test('subscription and book-settings events are skipped cleanly', () async {
    repo.serverPages.addAll([const ServerSyncPage(nextSince: 'scur-1')]);
    await engine.pullServer(); // mints
    repo.serverPages.add(
      ServerSyncPage(
        events: [
          ServerSyncEvent(
            kind: 'subscription',
            pid: 'pc-SHOW',
            subscription: Subscription(
              show: const PodcastShow(
                pid: 'pc-SHOW',
                title: 'The Prancing Pony Hour',
                sourceType: 'rss',
              ),
              settings: const SubscriptionSettings(),
              subscribedAt: DateTime.utc(2026, 7, 1),
            ),
          ),
          const ServerSyncEvent(
            kind: 'book-settings',
            pid: 'bk-BOOK',
            bookSettings: BookSettings(speed: 1.5),
          ),
        ],
        nextSince: 'scur-2',
      ),
    );
    await engine.pullServer();
    // Neither event touches the play-state mirror; the cursor advances.
    expect(await db.select(db.mirrorPlayStates).get(), isEmpty);
    final cursors = await db.select(db.syncCursors).getSingle();
    expect(cursors.serverSince, 'scur-2');
  });

  test('a radio frame nudges the radio listener and nothing else', () async {
    late void Function(String) deliver;
    final radioEngine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: capturingFrames((sink) => deliver = sink),
    );
    addTearDown(radioEngine.dispose);
    var radio = 0, player = 0;
    radioEngine.onRadioInvalidate = () => radio++;
    radioEngine.onPlayerInvalidate = () => player++;
    radioEngine.start();

    deliver(jsonEncode({'type': 'invalidate', 'topic': 'radio'}));
    await pumpEventQueue();

    expect(radio, 1);
    expect(player, 0, reason: 'a radio frame is not a player frame');
    // No cursor and no mirror half: the frame says a cover landed, and
    // the listener re-reads play-info rather than pulling a stream.
    expect(repo.catalogCalls, 0);
  });

  test('a failed call drops the link it was made over', () async {
    // Closing the channel cancels its own done callback, so nothing else
    // would ever say the link went: connected, and never reconnecting.
    final live = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: _connects(),
    )..account = _owner;
    addTearDown(live.dispose);
    await live.queueCheckpoint('tr-A', 1000);
    repo.failNextMutations = 1;

    await live.start();
    await pumpEventQueue();

    expect(live.current.connection, isNot(SyncConnection.connected));
  });

  test('what one account left waiting is sent only for it', () async {
    await engine.queueCheckpoint('tr-A', 1000);
    await engine.queueListen(
      ListenSession(
        sessionId: 's-1',
        pid: 'tr-A',
        startedAt: DateTime.utc(2026, 9, 1),
        msPlayed: 1000,
      ),
    );
    engine.account = 'us-2';

    await engine.flushOutbox();
    expect(repo.replayed, isEmpty);
    expect(repo.reportedSessions, isEmpty);

    engine.account = _owner;
    await engine.flushOutbox();
    expect(repo.replayed, ['position:tr-A:1000:true']);
    expect(repo.reportedSessions, {'s-1'});
  });
}
