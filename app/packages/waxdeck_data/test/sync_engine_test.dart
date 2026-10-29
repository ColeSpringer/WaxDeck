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

  @override
  String baseUrl = 'http://server.test';

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
    String? sortKey,
  }) => ItemSummary(
    pid: pid,
    mediaType: mediaType,
    title: title,
    durationMs: 1000,
    sortKey: sortKey,
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

  /// The pids the server can never put back, of those it is asked about,
  /// and every question it has had. [removedError] answers instead while
  /// set.
  final removedForGood = <String>{};
  final removedAsked = <List<String>>[];
  WaxDeckApiException? removedError;

  /// With [removedError] set, the only question (counting from 1) it
  /// fails; every question when null.
  int? removedErrorOnCall;

  /// Pids named whether or not they were asked about: a server gone wrong.
  final removedUnasked = <String>[];

  @override
  Future<List<String>> syncCatalogRemoved(List<String> pids) async {
    removedAsked.add([...pids]);
    final failing = removedErrorOnCall;
    if (removedError case final error?
        when failing == null || failing == removedAsked.length) {
      throw error;
    }
    return [
      for (final pid in pids)
        if (removedForGood.contains(pid)) pid,
      ...removedUnasked,
    ];
  }

  /// Each pid's download-info, which a pid without one answers not-found;
  /// every pid it was asked for. [downloadInfoError] answers instead while
  /// set.
  final downloadInfos = <String, DownloadInfo>{};
  final downloadInfoAsked = <String>[];
  WaxDeckApiException? downloadInfoError;

  /// Serves [pid] as one file per entry of [essences], in order.
  void serveFiles(String pid, List<String> essences) =>
      downloadInfos[pid] = DownloadInfo(
        pid: pid,
        files: [
          for (final (i, essence) in essences.indexed)
            DownloadFileInfo(
              url: '/media/download?pid=$pid&f=$i',
              mimeType: 'audio/mpeg',
              sizeBytes: 1024,
              fileName: '$pid-$i.mp3',
              essenceHash: essence,
              etag: 'x',
            ),
        ],
        expiresAt: DateTime.utc(2030),
      );

  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    downloadInfoAsked.add(pid);
    if (downloadInfoError case final error?) throw error;
    final info = downloadInfos[pid];
    if (info == null) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no item',
        statusCode: 404,
      );
    }
    return info;
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

/// Refuses the write of a pending free once armed, as a full disk does.
class _FailsFreeWrites extends QueryInterceptor {
  bool armed = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed &&
        args.any((a) => a is String && a.startsWith('waxdeck.sync.free.'))) {
      throw StateError('the disk is full');
    }
    return super.runInsert(executor, statement, args);
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

  test('the mirror files items under the key the server sorts by', () async {
    // A bare lowercase would file "The Zebra Song" under T and "Track 10"
    // before "Track 2"; the server's key is what keeps offline browsing in
    // the order the online listing has.
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-Z',
            item: repo.item('tr-Z', 'The Zebra Song', sortKey: 'zebra song'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-10',
            item: repo.item('tr-10', 'Track 10', sortKey: 'track 0000000010'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-2',
            item: repo.item('tr-2', 'Track 2', sortKey: 'track 0000000002'),
          ),
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-A',
            item: repo.item('tr-A', 'apple tune', sortKey: 'apple tune'),
          ),
          // From a server that sent no key: the lowercase title stands in.
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-M',
            item: repo.item('tr-M', 'Mango'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();

    final page = await mirrorItemsPage(db);
    expect(page.items.map((i) => i.title), [
      'apple tune',
      'Mango',
      'Track 2',
      'Track 10',
      'The Zebra Song',
    ]);
    expect(page.items.map((i) => i.sortKey), [
      'apple tune',
      'mango',
      'track 0000000002',
      'track 0000000010',
      'zebra song',
    ]);
    expect((await mirrorItemByPid(db, 'tr-Z'))!.sortKey, 'zebra song');
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
              server: Value(repo.baseUrl),
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

  /// What the downloads store does with a pid published to reclaim: takes
  /// its files and covers, then says the free is done.
  Future<void> freed(String pid) async {
    await (db.delete(db.downloadRecords)..where((t) => t.pid.equals(pid))).go();
    await (db.delete(db.artworkPins)..where((t) => t.pid.equals(pid))).go();
    expect(await engine.settleFree(pid), isTrue);
  }

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

    // Away while a track became a book of two files and both books became
    // tracks, long enough that the server answers the cursor with a reset:
    // the mirror comes back whole, with no delta naming any change.
    repo.serveFiles('bk-CCC', ['tr-CCC-e0', 'other-e1']);
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
    // track's one file is a part of its book, and the book's three files
    // any part of its track, so both stay put to be reclaimed.
    expect(await pidsIn(db.downloadRecords), [
      'bk-DDD',
      'bk-DDD',
      'bk-DDD',
      'tr-CCC',
      'tr-EEE',
    ]);
    expect(reclaimed, ['tr-CCC', 'bk-DDD']);
    expect(await pidsIn(db.artworkPins), ['bk-DDD', 'tr-CCC', 'tr-EEE']);
    // What was queued and how far it got stay with a download that is to
    // be reclaimed, whose bytes still play, and follow the item once the
    // free is done.
    expect(await pidsIn(db.mirrorPlayStates), ['bk-DDD', 'tr-CCC', 'tr-EEE']);
    expect(await pidsIn(db.queueEntries), ['bk-DDD', 'tr-CCC', 'tr-EEE']);
    for (final pid in reclaimed) {
      await freed(pid);
    }
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
      expect(await pidsIn(db.mirrorPlayStates), ['bk-DDD']);
      expect(await pidsIn(db.queueEntries), ['bk-DDD']);
      await freed('bk-DDD');
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
    // the book, and the other two are folded into it, as its three files.
    repo.serveFiles('bk-AAA', ['tr-AAA-e0', 'tr-BBB-e0', 'tr-CCC-e0']);
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
    expect(await pidsIn(db.mirrorPlayStates), ['tr-AAA']);
    expect(await pidsIn(db.queueEntries), ['tr-AAA']);
    await freed('tr-AAA');
    expect(await pidsIn(db.mirrorPlayStates), ['bk-AAA']);
    expect(await pidsIn(db.queueEntries), ['bk-AAA']);
  });

  test('a one-file download moves onto a book that is that file and no '
      'other', () async {
    repo.catalogPages.add(
      CatalogSyncPage(
        entries: [
          CatalogSyncEntry(
            op: 'upsert',
            pid: 'tr-CCC',
            item: repo.item('tr-CCC', 'Chapter'),
          ),
        ],
        nextSince: 'cur-1',
      ),
    );
    await engine.pullCatalog();
    await keepFor('tr-CCC');
    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    // Treat as audiobook: the book's download-info is the track's one file.
    repo.serveFiles('bk-CCC', ['tr-CCC-e0']);
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
        nextSince: 'cur-2',
      ),
    );
    await engine.pullCatalog();
    await pumpEventQueue();
    await sub.cancel();

    expect(repo.downloadInfoAsked, ['bk-CCC']);
    expect(reclaimed, isEmpty);
    expect(await pidsIn(db.downloadRecords), ['bk-CCC']);
    expect(await pidsIn(db.artworkPins), ['bk-CCC']);
    expect(await pidsIn(db.mirrorPlayStates), ['bk-CCC']);
    expect(await pidsIn(db.queueEntries), ['bk-CCC']);
  });

  for (final onePage in [false, true]) {
    test('a download outliving its mirror row moves with an item back under '
        'another kind${onePage ? ', in one page' : ''}', () async {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(
              op: 'upsert',
              pid: 'tr-HHH',
              item: repo.item('tr-HHH', 'Hotel'),
            ),
          ],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();
      await keepFor('tr-HHH');
      repo.serveFiles('bk-HHH', ['tr-HHH-e0']);
      // Out of this account's sight for a while, its bytes kept for its
      // return, which is under the book's prefix.
      const hidden = CatalogSyncEntry(
        op: 'delete',
        pid: 'tr-HHH',
        reason: 'hidden',
      );
      final back = CatalogSyncEntry(
        op: 'upsert',
        pid: 'bk-HHH',
        item: repo.item('bk-HHH', 'Hotel', mediaType: MediaType.audiobook),
      );
      repo.catalogPages.addAll([
        if (onePage)
          CatalogSyncPage(entries: [hidden, back], nextSince: 'cur-2')
        else ...[
          const CatalogSyncPage(
            entries: [hidden],
            nextSince: 'cur-2',
            more: true,
          ),
          CatalogSyncPage(entries: [back], nextSince: 'cur-3'),
        ],
      ]);
      await engine.pullCatalog();

      expect((await mirror()).map((r) => r.pid), ['bk-HHH']);
      expect(await pidsIn(db.downloadRecords), ['bk-HHH']);
      expect(await pidsIn(db.artworkPins), ['bk-HHH']);
      expect(await pidsIn(db.mirrorPlayStates), ['bk-HHH']);
      expect(await pidsIn(db.queueEntries), ['bk-HHH']);
      expect(await engine.pendingFrees(), isEmpty);
    });
  }

  group('a delta page with a book its server cannot answer for', () {
    CatalogSyncEntry upsert(
      String pid,
      String title, {
      MediaType type = MediaType.music,
    }) => CatalogSyncEntry(
      op: 'upsert',
      pid: pid,
      item: repo.item(pid, title, mediaType: type),
    );

    /// A downloaded track the next page lists as a book, ahead of another
    /// item, with [failure] answering every look at the book's files.
    Future<void> holding(WaxDeckApiException failure) async {
      repo.catalogPages.add(
        CatalogSyncPage(entries: [upsert('tr-XXX', 'Ex')], nextSince: 'cur-1'),
      );
      await engine.pullCatalog();
      await keepFor('tr-XXX');
      repo
        ..downloadInfoError = failure
        ..catalogPages.add(
          CatalogSyncPage(
            entries: [
              upsert('bk-XXX', 'Ex', type: MediaType.audiobook),
              upsert('tr-AAA', 'Alpha'),
            ],
            nextSince: 'cur-2',
          ),
        );
      await engine.pullCatalog();
    }

    test('goes past it, the book asked about again at each connect', () async {
      await holding(
        const WaxDeckApiException(
          code: 'internal',
          message: 'no',
          statusCode: 500,
        ),
      );

      expect(
        (await mirror()).map((r) => r.pid),
        unorderedEquals(['bk-XXX', 'tr-AAA']),
      );
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-2',
      );
      expect(await pidsIn(db.downloadRecords), ['tr-XXX']);
      expect(await pidsIn(db.queueEntries), ['tr-XXX']);
      expect(await engine.pendingFrees(), isEmpty);

      await engine.reconcile();
      expect(repo.downloadInfoAsked, ['bk-XXX', 'bk-XXX']);
      expect(await pidsIn(db.downloadRecords), ['tr-XXX']);

      repo
        ..downloadInfoError = null
        ..serveFiles('bk-XXX', ['tr-XXX-e0']);
      await engine.reconcile();
      expect(await pidsIn(db.downloadRecords), ['bk-XXX']);
      expect(await pidsIn(db.queueEntries), ['bk-XXX']);
    });

    test('stops at a lapsed session, writing nothing for it', () async {
      await holding(
        const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'no',
          statusCode: 401,
        ),
      );

      expect((await mirror()).map((r) => r.pid), ['tr-XXX']);
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-1',
      );
      expect(await pidsIn(db.downloadRecords), ['tr-XXX']);
      expect(await pidsIn(db.queueEntries), ['tr-XXX']);
    });
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
      expect(await pidsIn(db.mirrorPlayStates), ['bk-DDD']);
      await freed('bk-DDD');
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

  test('a book its mirror row had already left is freed by the pid its '
      'download is under', () async {
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
    await keepFor('bk-DDD', files: 2);
    final reclaimed = <String>[];
    final sub = engine.itemsRemoved.listen(reclaimed.add);

    // Trashed, which drops the row and keeps the bytes, then purged: the
    // tombstone carries the track prefix, and the mirror has no row left
    // to name the book.
    for (final (reason, since) in [('hidden', 'cur-2'), ('removed', 'cur-3')]) {
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [
            CatalogSyncEntry(op: 'delete', pid: 'tr-DDD', reason: reason),
          ],
          nextSince: since,
        ),
      );
      await engine.pullCatalog();
    }
    await pumpEventQueue();
    await sub.cancel();

    expect(reclaimed, ['bk-DDD']);
    expect(await engine.pendingFrees(), ['bk-DDD']);
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

  group('a snapshot, which carries no tombstones,', () {
    CatalogSyncEntry up(
      String pid,
      String title, {
      MediaType type = MediaType.music,
    }) => CatalogSyncEntry(
      op: 'upsert',
      pid: pid,
      item: repo.item(pid, title, mediaType: type),
    );

    Future<void> pinOnly(String pid) => db
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

    /// Mirrors [first], then answers the next pull with a sync-reset and
    /// [again] as the snapshot, and returns the pids published to reclaim.
    Future<List<String>> remirror(
      List<CatalogSyncEntry> first,
      List<CatalogSyncEntry> again, {
      required Future<void> Function() away,
    }) async {
      repo.catalogPages.add(
        CatalogSyncPage(entries: first, nextSince: 'cur-1'),
      );
      await engine.pullCatalog();
      await away();
      final reclaimed = <String>[];
      final sub = engine.itemsRemoved.listen(reclaimed.add);
      repo.resetCatalogOnce = true;
      repo.catalogPages.add(
        CatalogSyncPage(entries: again, nextSince: 'cur-9'),
      );
      await engine.pullCatalog();
      await pumpEventQueue();
      await sub.cancel();
      return reclaimed;
    }

    test('frees what the server can never put back', () async {
      final reclaimed = await remirror(
        [
          up('tr-AAA', 'Alpha'),
          up('tr-BBB', 'Bravo'),
          up('bk-EEE', 'Echo', type: MediaType.audiobook),
          up('tr-FFF', 'Foxtrot'),
        ],
        [up('tr-AAA', 'Alpha'), up('tr-FFF', 'Foxtrot')],
        away: () async {
          await keepFor('tr-AAA');
          await keepFor('tr-BBB');
          await keepFor('bk-EEE', files: 3);
          await keepFor('tr-FFF');
          // A cover pinned for an item whose download is already gone.
          await pinOnly('tr-DDD');
          // Deleted outright while the device was away: Bravo, the book,
          // and the one with only its cover left.
          repo.removedForGood.addAll(['tr-BBB', 'bk-EEE', 'tr-DDD']);
        },
      );

      // The delta's outcome for a `removed` tombstone: the pid is
      // published, once, for the downloads store to free the files and the
      // cover together. Alpha and Foxtrot are in the snapshot, and stay. A
      // cover with no download beside it names no server, so it is not
      // asked about; a sign-out takes it.
      expect(repo.removedAsked.single, ['bk-EEE', 'tr-BBB']);
      expect(reclaimed, ['bk-EEE', 'tr-BBB']);
      expect(await pidsIn(db.artworkPins), contains('tr-DDD'));
      expect((await mirror()).map((r) => r.pid), ['tr-AAA', 'tr-FFF']);
      expect(
        (await db.select(db.syncCursors).getSingle()).catalogSince,
        'cur-9',
      );
    });

    test('keeps what the server could put back', () async {
      final reclaimed = await remirror(
        [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo'), up('tr-CCC', 'Charlie')],
        [up('tr-AAA', 'Alpha')],
        away: () async {
          await keepFor('tr-AAA');
          // Trashed with its undo journal, or out of this caller's sight:
          // the delta calls both hidden, and so does the server's answer,
          // which does not name them.
          await keepFor('tr-BBB');
          await keepFor('tr-CCC', files: 2);
          repo.removedForGood.clear();
        },
      );

      expect(repo.removedAsked.single, ['tr-BBB', 'tr-CCC']);
      expect(reclaimed, isEmpty);
      // The rows left the mirror either way; the bytes and the cover are
      // where they were, for a restore to find.
      expect((await mirror()).map((r) => r.pid), ['tr-AAA']);
      expect(await pidsIn(db.downloadRecords), [
        'tr-AAA',
        'tr-BBB',
        'tr-CCC',
        'tr-CCC',
      ]);
      expect(await pidsIn(db.artworkPins), ['tr-AAA', 'tr-BBB', 'tr-CCC']);
    });

    test(
      'asks only about what it holds and the snapshot does not list',
      () async {
        await remirror(
          [
            up('tr-AAA', 'Alpha'),
            up('bk-BBB', 'Bravo', type: MediaType.audiobook),
            up('tr-CCC', 'Charlie'),
          ],
          // Alpha is listed; Bravo is listed under its new prefix (the kind
          // changed while the device was away); Charlie is not.
          [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo'), up('tr-DDD', 'Delta')],
          away: () async {
            await keepFor('tr-AAA');
            await keepFor('bk-BBB');
            await keepFor('tr-CCC');
            // Held and listed: asking would only invite a wrong answer. Not
            // held at all (Delta is new): nothing to free.
          },
        );

        expect(repo.removedAsked, [
          ['tr-CCC'],
        ]);
      },
    );

    /// Says [pid]'s download came from [server] (null: from before the
    /// device kept where a download came from).
    Future<void> fetchedFrom(String pid, String? server) =>
        (db.update(db.downloadRecords)..where((t) => t.pid.equals(pid))).write(
          DownloadRecordsCompanion(server: Value(server)),
        );

    test('asks a server only about the downloads that came from it', () async {
      final reclaimed = await remirror(
        [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
        [up('tr-CCC', 'Charlie')],
        away: () async {
          await keepFor('tr-AAA');
          // From a server this device was pointed at before, whose items
          // this one never held, and from before the device kept where a
          // download came from.
          await keepFor('tr-BBB');
          await fetchedFrom('tr-BBB', 'http://elsewhere.test');
          await keepFor('tr-DDD');
          await fetchedFrom('tr-DDD', null);
          // A server that would call every one of them gone.
          repo.removedForGood.addAll(['tr-AAA', 'tr-BBB', 'tr-DDD']);
        },
      );

      expect(repo.removedAsked, [
        ['tr-AAA'],
      ]);
      expect(reclaimed, ['tr-AAA']);
      expect(await pidsIn(db.artworkPins), ['tr-AAA', 'tr-BBB', 'tr-DDD']);
    });

    test('adopts a download it lists, whatever address fetched it', () async {
      // The same catalog reached at another address, and a download from
      // before the device kept where one came from: listed, so this
      // server's to answer for from now on.
      await keepFor('tr-AAA');
      await fetchedFrom('tr-AAA', 'http://old-address.test');
      await keepFor('tr-BBB');
      await fetchedFrom('tr-BBB', null);
      await keepFor('tr-CCC');
      await fetchedFrom('tr-CCC', 'http://elsewhere.test');
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
          nextSince: 'cur-1',
        ),
      );
      await engine.pullCatalog();

      final stamps = {
        for (final r in await db.select(db.downloadRecords).get())
          r.pid: r.server,
      };
      expect(stamps, {
        'tr-AAA': repo.baseUrl,
        'tr-BBB': repo.baseUrl,
        'tr-CCC': 'http://elsewhere.test',
      });

      // Gone for good by the next re-mirror, which asks about both.
      repo.removedForGood.addAll(['tr-AAA', 'tr-BBB', 'tr-CCC']);
      final reclaimed = <String>[];
      final sub = engine.itemsRemoved.listen(reclaimed.add);
      repo.resetCatalogOnce = true;
      repo.catalogPages.add(const CatalogSyncPage(nextSince: 'cur-9'));
      await engine.pullCatalog();
      await pumpEventQueue();
      await sub.cancel();
      expect(repo.removedAsked, [
        ['tr-AAA', 'tr-BBB'],
      ]);
      expect(reclaimed, ['tr-AAA', 'tr-BBB']);
    });

    for (final (server, rows) in [
      (null, 'name no server'),
      ('http://old-address.test', 'name another address of it'),
    ]) {
      test('moves a one-file download whose rows $rows with its item into a '
          'book, where it plays offline', () async {
        final reclaimed = await remirror(
          [up('tr-XXX', 'Ex')],
          [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
          away: () async {
            await keepFor('tr-XXX');
            await fetchedFrom('tr-XXX', server);
            // The book is the track's one file, as its download-info says.
            repo.serveFiles('bk-XXX', ['tr-XXX-e0']);
          },
        );

        expect(reclaimed, isEmpty);
        expect(await engine.pendingFrees(), isEmpty);
        final file = await db.select(db.downloadRecords).getSingle();
        expect(
          (file.pid, file.server, file.state, file.localPath),
          ('bk-XXX', repo.baseUrl, 'complete', '/downloads/tr-XXX-0.mp3'),
        );
        expect(await mirrorDownloadedPids(db), ['bk-XXX']);
        expect(await pidsIn(db.artworkPins), ['bk-XXX']);
        expect(await pidsIn(db.queueEntries), ['bk-XXX']);
        expect(await pidsIn(db.mirrorPlayStates), ['bk-XXX']);
      });
    }

    for (final (book, carved) in [
      ('one part of several', false),
      ('other audio', false),
      ('the whole file a carved track was cut from', true),
    ]) {
      test('reclaims whole a one-file download the book holds as $book, '
          'what was queued staying with it until it is freed', () async {
        final reclaimed = await remirror(
          [up('tr-XXX', 'Ex')],
          [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
          away: () async {
            await keepFor('tr-XXX');
            await db
                .update(db.downloadRecords)
                .write(
                  DownloadRecordsCompanion(
                    server: const Value(null),
                    spanStartMs: Value(carved ? 0 : null),
                    spanEndMs: Value(carved ? 60000 : null),
                  ),
                );
            repo.serveFiles('bk-XXX', switch (book) {
              'one part of several' => ['tr-XXX-e0', 'other-e1'],
              'other audio' => ['other-e0'],
              _ => ['tr-XXX-e0'],
            });
          },
        );

        expect(reclaimed, ['tr-XXX']);
        expect(await engine.pendingFrees(), ['tr-XXX']);
        expect(await pidsIn(db.downloadRecords), ['tr-XXX']);
        expect(await pidsIn(db.artworkPins), ['tr-XXX']);
        // The queue and the position stay with the bytes they play until
        // the free takes those; online the server answers either prefix.
        expect(await pidsIn(db.queueEntries), ['tr-XXX']);
        expect(await pidsIn(db.mirrorPlayStates), ['tr-XXX']);

        await freed('tr-XXX');

        expect(await pidsIn(db.queueEntries), ['bk-XXX']);
        expect(await pidsIn(db.mirrorPlayStates), ['bk-XXX']);
      });
    }

    test('what stayed with a reclaimed download stays while the device '
        'holds bytes under its pid again', () async {
      await remirror(
        [up('tr-XXX', 'Ex')],
        [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
        away: () async {
          await keepFor('tr-XXX');
          repo.serveFiles('bk-XXX', ['tr-XXX-e0', 'other-e1']);
        },
      );
      // The free takes what it was owed; a file taken up since is the
      // device's own.
      await (db.delete(
        db.downloadRecords,
      )..where((t) => t.pid.equals('tr-XXX'))).go();
      await (db.delete(
        db.artworkPins,
      )..where((t) => t.pid.equals('tr-XXX'))).go();
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: 'tr-XXX',
              fileIndex: 1,
              essenceHash: 'again',
              etag: 'x',
              fileName: 'again.mp3',
              localPath: '/downloads/again.mp3',
              sizeBytes: 1024,
              state: 'complete',
            ),
          );

      expect(await engine.settleFree('tr-XXX'), isTrue);

      expect(await pidsIn(db.queueEntries), ['tr-XXX']);
      expect(await pidsIn(db.mirrorPlayStates), ['tr-XXX']);
    });

    test('stops at a lapsed session, writing nothing', () async {
      repo.catalogPages.add(
        CatalogSyncPage(entries: [up('tr-XXX', 'Ex')], nextSince: 'cur-1'),
      );
      await engine.pullCatalog();
      await keepFor('tr-XXX');
      await fetchedFrom('tr-XXX', null);
      repo
        ..downloadInfoError = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'no',
          statusCode: 401,
        )
        ..resetCatalogOnce = true
        ..catalogPages.add(
          CatalogSyncPage(
            entries: [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
            nextSince: 'cur-9',
          ),
        );

      await expectLater(
        engine.pullCatalog(),
        throwsA(isA<WaxDeckApiException>()),
      );

      expect((await mirror()).map((r) => r.pid), ['tr-XXX']);
      final file = await db.select(db.downloadRecords).getSingle();
      expect((file.pid, file.server), ('tr-XXX', null));
      expect(await pidsIn(db.queueEntries), ['tr-XXX']);
      expect(await engine.pendingFrees(), isEmpty);

      // The next sync snapshots again, and is answered.
      repo
        ..downloadInfoError = null
        ..serveFiles('bk-XXX', ['tr-XXX-e0'])
        ..catalogPages.add(
          CatalogSyncPage(
            entries: [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
            nextSince: 'cur-10',
          ),
        );
      await engine.pullCatalog();
      expect(await pidsIn(db.downloadRecords), ['bk-XXX']);
      expect(await pidsIn(db.queueEntries), ['bk-XXX']);
    });

    for (final (book, files) in [
      ('that file alone', ['tr-XXX-e0']),
      ('more than that file', ['tr-XXX-e0', 'other-e1']),
    ]) {
      test('commits past a book its server cannot answer for, asking again at '
          'each connect until it says the book is $book', () async {
        repo.catalogPages.add(
          CatalogSyncPage(entries: [up('tr-XXX', 'Ex')], nextSince: 'cur-1'),
        );
        await engine.pullCatalog();
        await keepFor('tr-XXX');
        await fetchedFrom('tr-XXX', null);
        final reclaimed = <String>[];
        final sub = engine.itemsRemoved.listen(reclaimed.add);
        addTearDown(sub.cancel);
        // The book's details fail on the server, every time.
        repo
          ..downloadInfoError = const WaxDeckApiException(
            code: 'internal',
            message: 'no',
            statusCode: 500,
          )
          ..resetCatalogOnce = true
          ..catalogPages.add(
            CatalogSyncPage(
              entries: [
                up('bk-XXX', 'Ex', type: MediaType.audiobook),
                up('tr-AAA', 'Alpha'),
              ],
              nextSince: 'cur-9',
            ),
          );

        await engine.pullCatalog();

        Future<void> untouched() async {
          await pumpEventQueue();
          final file = await db.select(db.downloadRecords).getSingle();
          expect((file.pid, file.server), ('tr-XXX', repo.baseUrl));
          expect(await pidsIn(db.artworkPins), ['tr-XXX']);
          expect(await pidsIn(db.queueEntries), ['tr-XXX']);
          expect(await pidsIn(db.mirrorPlayStates), ['tr-XXX']);
          expect(await engine.pendingFrees(), isEmpty);
          expect(reclaimed, isEmpty);
        }

        expect(
          (await mirror()).map((r) => r.pid),
          unorderedEquals(['bk-XXX', 'tr-AAA']),
        );
        expect(
          (await db.select(db.syncCursors).getSingle()).catalogSince,
          'cur-9',
        );
        await untouched();
        expect(repo.downloadInfoAsked, ['bk-XXX']);

        // The next connect asks again, and gets no further.
        await engine.reconcile();
        expect(repo.downloadInfoAsked, ['bk-XXX', 'bk-XXX']);
        await untouched();

        // A connect that mirrors afresh asks in the snapshot, and only there.
        repo
          ..resetCatalogOnce = true
          ..catalogPages.add(
            CatalogSyncPage(
              entries: [
                up('bk-XXX', 'Ex', type: MediaType.audiobook),
                up('tr-AAA', 'Alpha'),
              ],
              nextSince: 'cur-10',
            ),
          );
        await engine.reconcile();
        expect(repo.downloadInfoAsked, hasLength(3));
        await untouched();

        // The one after is answered, and the kind change goes as it would
        // have gone.
        repo
          ..downloadInfoError = null
          ..serveFiles('bk-XXX', files);
        await engine.reconcile();
        await pumpEventQueue();
        expect(repo.downloadInfoAsked, hasLength(4));
        if (files.length == 1) {
          expect(await pidsIn(db.downloadRecords), ['bk-XXX']);
          expect(await pidsIn(db.queueEntries), ['bk-XXX']);
          expect(reclaimed, isEmpty);
        } else {
          expect(await pidsIn(db.downloadRecords), ['tr-XXX']);
          expect(reclaimed, ['tr-XXX']);
          expect(await engine.pendingFrees(), ['tr-XXX']);
        }

        // Decided, it is not asked about again.
        await engine.reconcile();
        expect(repo.downloadInfoAsked, hasLength(4));
      });
    }

    test('moves a download outliving its mirror row with an item back under '
        'another kind', () async {
      final reclaimed = await remirror(
        [up('tr-HHH', 'Hotel')],
        [up('bk-HHH', 'Hotel', type: MediaType.audiobook)],
        away: () async {
          await keepFor('tr-HHH');
          // Out of this account's sight, its bytes kept for its return.
          repo.catalogPages.add(
            const CatalogSyncPage(
              entries: [
                CatalogSyncEntry(op: 'delete', pid: 'tr-HHH', reason: 'hidden'),
              ],
              nextSince: 'cur-2',
            ),
          );
          await engine.pullCatalog();
          repo.serveFiles('bk-HHH', ['tr-HHH-e0']);
        },
      );

      expect(repo.removedAsked, isEmpty, reason: 'its item is listed');
      expect(reclaimed, isEmpty);
      expect(await pidsIn(db.downloadRecords), ['bk-HHH']);
      expect(await pidsIn(db.artworkPins), ['bk-HHH']);
      expect(await pidsIn(db.queueEntries), ['bk-HHH']);
      expect(await pidsIn(db.mirrorPlayStates), ['bk-HHH']);
    });

    test('leaves a download whose ULID it does not list where it is, '
        'untouched', () async {
      final reclaimed = await remirror(
        [up('tr-AAA', 'Alpha'), up('tr-YYY', 'Yankee'), up('tr-ZZZ', 'Zulu')],
        [up('tr-AAA', 'Alpha')],
        away: () async {
          await keepFor('tr-YYY');
          await fetchedFrom('tr-YYY', 'http://elsewhere.test');
          await keepFor('tr-ZZZ');
          await fetchedFrom('tr-ZZZ', null);
          // A server that would call both gone.
          repo.removedForGood.addAll(['tr-YYY', 'tr-ZZZ']);
        },
      );

      expect(repo.removedAsked, isEmpty);
      expect(reclaimed, isEmpty);
      expect(await engine.pendingFrees(), isEmpty);
      expect(
        {
          for (final r in await db.select(db.downloadRecords).get())
            r.pid: r.server,
        },
        {'tr-YYY': 'http://elsewhere.test', 'tr-ZZZ': null},
      );
      expect(await pidsIn(db.artworkPins), ['tr-YYY', 'tr-ZZZ']);
      expect(await pidsIn(db.queueEntries), ['tr-YYY', 'tr-ZZZ']);
      expect(await pidsIn(db.mirrorPlayStates), ['tr-YYY', 'tr-ZZZ']);
    });

    test('hands a download it lists under another kind to itself, whichever '
        'address fetched it, and then the kind change decides', () async {
      // A book fetched at another address, and this server's catalog (a
      // restore of that one is the same catalog) listing it as a track: the
      // ULID makes it this catalog's item, and three files are not a track.
      final reclaimed = await remirror(
        [up('bk-XXX', 'Ex', type: MediaType.audiobook)],
        [up('tr-XXX', 'Ex')],
        away: () async {
          await keepFor('bk-XXX', files: 3);
          await fetchedFrom('bk-XXX', 'http://elsewhere.test');
        },
      );

      expect(reclaimed, ['bk-XXX']);
      expect(await engine.pendingFrees(), ['bk-XXX']);
      expect(
        {for (final r in await db.select(db.downloadRecords).get()) r.server},
        {repo.baseUrl},
      );
    });

    test('a round trip between two addresses of one catalog keeps a one-file '
        'download, under whichever kind it has', () async {
      final reclaimed = await remirror(
        [up('bk-YYY', 'Why', type: MediaType.audiobook)],
        [up('tr-YYY', 'Why')],
        away: () async {
          await keepFor('bk-YYY');
          await fetchedFrom('bk-YYY', 'http://elsewhere.test');
        },
      );
      expect(reclaimed, isEmpty);
      expect(await pidsIn(db.downloadRecords), [
        'tr-YYY',
      ], reason: 'a track is one file');

      // At the other address, which lists the book again: its one file, as
      // its download-info says.
      repo.baseUrl = 'http://elsewhere.test';
      repo.serveFiles('bk-YYY', ['bk-YYY-e0']);
      final again = <String>[];
      final sub = engine.itemsRemoved.listen(again.add);
      repo.resetCatalogOnce = true;
      repo.catalogPages.add(
        CatalogSyncPage(
          entries: [up('bk-YYY', 'Why', type: MediaType.audiobook)],
          nextSince: 'cur-20',
        ),
      );
      await engine.pullCatalog();
      await pumpEventQueue();
      await sub.cancel();

      expect(again, isEmpty);
      expect(await engine.pendingFrees(), isEmpty);
      expect(await pidsIn(db.downloadRecords), ['bk-YYY']);
      expect(await pidsIn(db.artworkPins), ['bk-YYY']);
      expect(await pidsIn(db.queueEntries), ['bk-YYY']);
    });

    test('ask nothing when every pid it holds is listed', () async {
      await remirror(
        [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
        [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
        away: () async {
          await keepFor('tr-AAA');
          await pinOnly('tr-BBB');
        },
      );
      expect(repo.removedAsked, isEmpty);

      // And a device with nothing downloaded has nothing to ask.
      final fresh = ScriptedRepository();
      final other = SyncEngine(
        db: MirrorDatabase(DatabaseConnection(NativeDatabase.memory())),
        repository: fresh,
        channelFactory: neverConnects(),
      );
      addTearDown(() async {
        other.dispose();
        await other.db.close();
      });
      fresh.catalogPages.add(
        CatalogSyncPage(entries: [up('tr-AAA', 'Alpha')], nextSince: 'cur-1'),
      );
      await other.pullCatalog();
      expect(fresh.removedAsked, isEmpty);
    });

    test('asks in pages of 500', () async {
      final reclaimed = await remirror(
        [up('tr-AAA', 'Alpha')],
        [up('tr-AAA', 'Alpha')],
        away: () async {
          await db.batch(
            (b) => b.insertAll(db.downloadRecords, [
              for (var i = 0; i < 1001; i++)
                DownloadRecordsCompanion.insert(
                  pid: 'tr-X${i.toString().padLeft(4, '0')}',
                  fileIndex: 0,
                  essenceHash: 'e$i',
                  etag: 'x',
                  fileName: 'x$i.mp3',
                  localPath: '/downloads/x$i.mp3',
                  sizeBytes: 1,
                  state: 'complete',
                  server: Value(repo.baseUrl),
                ),
            ]),
          );
          repo.removedForGood.addAll([
            for (var i = 0; i < 1001; i++)
              'tr-X${i.toString().padLeft(4, '0')}',
          ]);
        },
      );

      expect(repo.removedAsked.map((a) => a.length), [500, 500, 1]);
      expect(reclaimed, hasLength(1001));
      expect(reclaimed.toSet(), hasLength(1001));
    });

    test('believes only the answer to what it asked', () async {
      final reclaimed = await remirror(
        [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
        [up('tr-AAA', 'Alpha')],
        away: () async {
          await keepFor('tr-AAA');
          await keepFor('tr-BBB');
          // A server naming a pid that is in the snapshot, and one never
          // asked about, must not free either.
          repo.removedUnasked.addAll(['tr-AAA', 'tr-ZZZ']);
        },
      );

      expect(reclaimed, isEmpty);
    });

    for (final (name, error) in [
      (
        'a server that does not know the question',
        const WaxDeckApiException(
          code: 'not-found',
          message: 'no such route',
          statusCode: 404,
        ),
      ),
      (
        'a catalog in maintenance',
        const WaxDeckApiException(
          code: 'catalog-maintenance',
          message: 'busy',
          statusCode: 503,
        ),
      ),
      (
        'a dropped connection',
        const WaxDeckApiException(code: 'transport', message: 'reset'),
      ),
    ]) {
      test('keeps every byte against $name, and still mirrors', () async {
        final reclaimed = await remirror(
          [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
          [up('tr-AAA', 'Alpha')],
          away: () async {
            await keepFor('tr-BBB');
            repo.removedForGood.add('tr-BBB');
            repo.removedError = error;
          },
        );

        expect(reclaimed, isEmpty);
        expect((await mirror()).map((r) => r.pid), ['tr-AAA']);
        expect(
          (await db.select(db.syncCursors).getSingle()).catalogSince,
          'cur-9',
        );
        expect(await pidsIn(db.downloadRecords), ['tr-BBB']);
      });
    }

    test('stops where the session ended, like any other request', () async {
      var expired = 0;
      final other = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: neverConnects(),
        onAuthExpired: () => expired++,
      )..account = _owner;
      addTearDown(other.dispose);
      await keepFor('tr-BBB');
      repo.removedError = const WaxDeckApiException(
        code: 'unauthenticated',
        message: 'sign in',
        statusCode: 401,
      );
      repo.catalogPages.add(
        CatalogSyncPage(entries: [up('tr-AAA', 'Alpha')], nextSince: 'cur-1'),
      );

      await other.reconcile();

      expect(expired, 1);
      // Nothing was committed: the snapshot is taken again after sign-in.
      expect(await mirror(), isEmpty);
      expect(await db.select(db.syncCursors).get(), isEmpty);
      // Nor does a question wait to be asked again: it is asked afresh.
      expect(await db.select(db.clientSettings).get(), isEmpty);
    });

    group('that could not be answered', () {
      const unavailable = WaxDeckApiException(
        code: 'catalog-maintenance',
        message: 'busy',
        statusCode: 503,
      );

      /// A later launch of the app: a new engine over the same database,
      /// so whatever waits is in the database and not in the engine.
      SyncEngine relaunch({void Function()? onAuthExpired}) {
        final next = SyncEngine(
          db: db,
          repository: repo,
          channelFactory: neverConnects(),
          onAuthExpired: onAuthExpired,
        )..account = _owner;
        addTearDown(next.dispose);
        return next;
      }

      /// One sync after connecting, and the pids it published to free.
      Future<List<String>> syncAgain(SyncEngine on) async {
        final reclaimed = <String>[];
        final sub = on.itemsRemoved.listen(reclaimed.add);
        await on.reconcile();
        await pumpEventQueue();
        await sub.cancel();
        return reclaimed;
      }

      /// A re-mirror after Bravo was deleted outright and Charlie went to
      /// the trash, when the server cannot be asked which. Leaves the
      /// question as it was put and clears the record of it.
      Future<void> failedQuestion() async {
        final freed = await remirror(
          [
            up('tr-AAA', 'Alpha'),
            up('tr-BBB', 'Bravo'),
            up('tr-CCC', 'Charlie'),
          ],
          [up('tr-AAA', 'Alpha')],
          away: () async {
            await keepFor('tr-AAA');
            await keepFor('tr-BBB');
            await keepFor('tr-CCC');
            repo.removedForGood.add('tr-BBB');
            repo.removedError = unavailable;
          },
        );
        expect(freed, isEmpty);
        expect(repo.removedAsked, [
          ['tr-BBB', 'tr-CCC'],
        ]);
        repo.removedAsked.clear();
        repo.removedError = null;
      }

      test(
        'is asked again at a later sync, and what it names is freed',
        () async {
          await failedQuestion();

          final reclaimed = await syncAgain(relaunch());

          expect(repo.removedAsked, [
            ['tr-BBB', 'tr-CCC'],
          ]);
          expect(reclaimed, ['tr-BBB']);
          // Answered, so a sync after that has nothing left to ask.
          repo.removedAsked.clear();
          expect(await syncAgain(relaunch()), isEmpty);
          expect(repo.removedAsked, isEmpty);
        },
      );

      test('is asked again while the server still cannot answer', () async {
        await failedQuestion();
        repo.removedError = unavailable;

        expect(await syncAgain(relaunch()), isEmpty);
        expect(repo.removedAsked, [
          ['tr-BBB', 'tr-CCC'],
        ]);

        repo.removedAsked.clear();
        repo.removedError = null;
        expect(await syncAgain(relaunch()), ['tr-BBB']);
      });

      test('is not asked twice in one sync', () async {
        // The snapshot of a first sync puts the question, and it fails;
        // the end of the same sync does not put it again.
        await keepFor('tr-BBB');
        repo.removedForGood.add('tr-BBB');
        repo.removedError = unavailable;
        repo.catalogPages.add(
          CatalogSyncPage(entries: [up('tr-AAA', 'Alpha')], nextSince: 'cur-1'),
        );

        await engine.reconcile();
        expect(repo.removedAsked, hasLength(1));

        repo.removedError = null;
        expect(await syncAgain(engine), ['tr-BBB']);
        expect(repo.removedAsked, hasLength(2));
      });

      test('is replaced by a snapshot that answers it', () async {
        await failedQuestion();

        // Away again; this time the server answers the re-mirror's question.
        repo.resetCatalogOnce = true;
        repo.catalogPages.add(
          CatalogSyncPage(
            entries: [up('tr-AAA', 'Alpha')],
            nextSince: 'cur-20',
          ),
        );
        final freed = <String>[];
        final sub = engine.itemsRemoved.listen(freed.add);
        await engine.pullCatalog();
        await pumpEventQueue();
        await sub.cancel();
        expect(freed, ['tr-BBB']);

        repo.removedAsked.clear();
        expect(await syncAgain(relaunch()), isEmpty);
        expect(repo.removedAsked, isEmpty);
      });

      test('skips a pid the mirror lists again by then', () async {
        await failedQuestion();
        // Charlie came back from the trash, and were he asked about the
        // server would not call him gone; Bravo is still gone.
        repo.removedForGood.add('tr-CCC');
        repo.catalogPages.add(
          CatalogSyncPage(
            entries: [up('tr-CCC', 'Charlie')],
            nextSince: 'cur-10',
          ),
        );

        final reclaimed = await syncAgain(relaunch());

        expect(repo.removedAsked, [
          ['tr-BBB'],
        ]);
        expect(reclaimed, ['tr-BBB']);

        // And he is not remembered: trashed again, nothing asks after him.
        repo.removedAsked.clear();
        repo.catalogPages.add(
          const CatalogSyncPage(
            entries: [
              CatalogSyncEntry(op: 'delete', pid: 'tr-CCC', reason: 'hidden'),
            ],
            nextSince: 'cur-11',
          ),
        );
        expect(await syncAgain(relaunch()), isEmpty);
        expect(repo.removedAsked, isEmpty);
      });

      test('does not ask about what was only held later', () async {
        await failedQuestion();
        // Downloaded since, from an item the mirror does not list either.
        await keepFor('tr-NEW');
        repo.removedForGood.add('tr-NEW');

        final reclaimed = await syncAgain(relaunch());

        // It was no part of the question that failed, so it is not asked.
        expect(repo.removedAsked, [
          ['tr-BBB', 'tr-CCC'],
        ]);
        expect(reclaimed, ['tr-BBB']);
      });

      test('still asks about a pid that gained a pin meanwhile', () async {
        await failedQuestion();
        // Charlie's cover was pinned again at another size, after the
        // failure; the server's answer is still what decides.
        await db
            .into(db.artworkPins)
            .insert(
              ArtworkPinsCompanion.insert(
                pid: 'tr-CCC',
                sizePx: 600,
                artUrl: '/media/art?pid=tr-CCC&size=600',
                etag: 'b',
                localPath: '/art/tr-CCC-600.jpg',
                sizeBytes: 4096,
                pinnedAt: DateTime.utc(2026, 10, 2),
              ),
            );

        final reclaimed = await syncAgain(relaunch());

        expect(repo.removedAsked, [
          ['tr-BBB', 'tr-CCC'],
        ]);
        expect(reclaimed, ['tr-BBB']);
        expect(await pidsIn(db.artworkPins), [
          'tr-AAA',
          'tr-BBB',
          'tr-CCC',
          'tr-CCC',
        ]);
      });

      test('is not put to another server', () async {
        await failedQuestion();
        // "Change server": the engine of another address, over the same
        // database, and one that would call every pid gone.
        final other = ScriptedRepository()
          ..baseUrl = 'http://elsewhere.test'
          ..removedForGood.addAll(['tr-BBB', 'tr-CCC']);
        final elsewhere = SyncEngine(
          db: db,
          repository: other,
          channelFactory: neverConnects(),
        )..account = _owner;
        addTearDown(elsewhere.dispose);

        expect(await syncAgain(elsewhere), isEmpty);
        expect(other.removedAsked, isEmpty);
        expect(await elsewhere.pendingFrees(), isEmpty);
      });

      test('forgets a pid the device no longer holds', () async {
        await failedQuestion();
        // The listener removed Bravo's download themselves.
        await (db.delete(
          db.downloadRecords,
        )..where((t) => t.pid.equals('tr-BBB'))).go();
        await (db.delete(
          db.artworkPins,
        )..where((t) => t.pid.equals('tr-BBB'))).go();

        final reclaimed = await syncAgain(relaunch());

        expect(repo.removedAsked, [
          ['tr-CCC'],
        ]);
        expect(reclaimed, isEmpty);
      });

      test('survives a lapsed session, which writes nothing', () async {
        await failedQuestion();
        var expired = 0;
        repo.removedError = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'sign in',
          statusCode: 401,
        );

        await relaunch(onAuthExpired: () => expired++).reconcile();

        expect(expired, 1);
        repo.removedError = null;
        repo.removedAsked.clear();
        expect(await syncAgain(relaunch()), ['tr-BBB']);
        expect(repo.removedAsked, [
          ['tr-BBB', 'tr-CCC'],
        ]);
      });

      List<String> manyPids() => [
        for (var i = 0; i < 1001; i++) 'tr-X${i.toString().padLeft(4, '0')}',
      ];

      Future<void> holdMany() => db.batch(
        (b) => b.insertAll(db.downloadRecords, [
          for (final pid in manyPids())
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: pid,
              etag: 'x',
              fileName: '$pid.mp3',
              localPath: '/downloads/$pid.mp3',
              sizeBytes: 1,
              state: 'complete',
              server: Value(repo.baseUrl),
            ),
        ]),
      );

      test('stops asking pages once one fails', () async {
        await remirror(
          [up('tr-AAA', 'Alpha')],
          [up('tr-AAA', 'Alpha')],
          away: () async {
            await holdMany();
            repo.removedError = unavailable;
          },
        );

        // 1001 candidates are three pages; the first failed, so the others
        // are not tried.
        expect(repo.removedAsked.map((a) => a.length), [500]);

        // Every one of them still waits.
        repo.removedAsked.clear();
        repo.removedError = null;
        repo.removedForGood.addAll(manyPids());
        final reclaimed = await syncAgain(relaunch());
        expect(repo.removedAsked.map((a) => a.length), [500, 500, 1]);
        expect(reclaimed, manyPids());
      });

      test('keeps only the pages a failure part-way did not reach', () async {
        final freed = await remirror(
          [up('tr-AAA', 'Alpha')],
          [up('tr-AAA', 'Alpha')],
          away: () async {
            await holdMany();
            repo.removedForGood.addAll(manyPids());
            repo.removedError = unavailable;
            repo.removedErrorOnCall = 2;
          },
        );

        // The first page was answered and freed; the second failed and the
        // third was not tried.
        expect(repo.removedAsked.map((a) => a.length), [500, 500]);
        expect(freed, manyPids().sublist(0, 500));

        repo.removedAsked.clear();
        repo.removedError = null;
        final later = await syncAgain(relaunch());
        expect(repo.removedAsked.map((a) => a.length), [500, 1]);
        expect(later, manyPids().sublist(500));
      });
    });
  });

  group('what a drop from the mirror owes the device', () {
    CatalogSyncEntry up(
      String pid,
      String title, {
      MediaType type = MediaType.music,
    }) => CatalogSyncEntry(
      op: 'upsert',
      pid: pid,
      item: repo.item(pid, title, mediaType: type),
    );

    /// The run after a kill: a new engine over the same database.
    SyncEngine relaunch() {
      final next = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: neverConnects(),
      )..account = _owner;
      addTearDown(next.dispose);
      return next;
    }

    Future<void> mirrored(List<CatalogSyncEntry> entries) async {
      repo.catalogPages.add(
        CatalogSyncPage(entries: entries, nextSince: 'cur-1'),
      );
      await engine.pullCatalog();
    }

    Future<void> delta(
      List<CatalogSyncEntry> entries, {
      String since = 'cur-2',
    }) async {
      repo.catalogPages.add(
        CatalogSyncPage(entries: entries, nextSince: since),
      );
      await engine.pullCatalog();
    }

    CatalogSyncEntry tombstone(String pid, String reason) =>
        CatalogSyncEntry(op: 'delete', pid: pid, reason: reason);

    /// A download of one file and a pinned cover, in [target].
    Future<void> holdIn(MirrorDatabase target, String pid) async {
      await target
          .into(target.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: pid,
              fileIndex: 0,
              essenceHash: '$pid-e0',
              etag: 'x',
              fileName: '$pid-0.mp3',
              localPath: '/downloads/$pid-0.mp3',
              sizeBytes: 1024,
              state: 'complete',
              server: Value(repo.baseUrl),
            ),
          );
      await target
          .into(target.artworkPins)
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

    /// Bravo's book, downloaded in two files with a cover, then dropped
    /// from the mirror by a `removed` tombstone, and the run ends there.
    Future<void> owedBook() async {
      await mirrored([up('bk-DDD', 'Delta', type: MediaType.audiobook)]);
      await keepFor('bk-DDD', files: 2);
      await delta([tombstone('tr-DDD', 'removed')]);
    }

    test('a removed tombstone owes the free from its commit', () async {
      await owedBook();

      // Nothing freed it, nothing listened: the run was killed. The wire
      // pid said `tr-`; the promise is for the pid the bytes are under.
      expect(await relaunch().pendingFrees(), ['bk-DDD']);
    });

    test(
      'a hidden tombstone owes nothing, nor does one for no bytes',
      () async {
        await mirrored([up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')]);
        await keepFor('tr-AAA');
        await delta([
          tombstone('tr-AAA', 'hidden'),
          tombstone('tr-BBB', 'removed'),
        ]);

        expect(await relaunch().pendingFrees(), isEmpty);
      },
    );

    test('a re-mirror owes what the server named', () async {
      await mirrored([up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')]);
      await keepFor('tr-BBB');
      repo.removedForGood.add('tr-BBB');
      repo.resetCatalogOnce = true;
      await delta([up('tr-AAA', 'Alpha')], since: 'cur-9');

      expect(await relaunch().pendingFrees(), ['tr-BBB']);
    });

    test('a re-mirror owes what a kind change left, and a delta too', () async {
      await mirrored([
        up('bk-DDD', 'Delta', type: MediaType.audiobook),
        up('bk-EEE', 'Echo', type: MediaType.audiobook),
      ]);
      await keepFor('bk-DDD', files: 3);
      await keepFor('bk-EEE', files: 3);

      // Echo becomes a track in a delta, Delta in a snapshot.
      await delta([up('tr-EEE', 'Echo')]);
      expect(await relaunch().pendingFrees(), ['bk-EEE']);
      repo.resetCatalogOnce = true;
      await delta([
        up('tr-DDD', 'Delta'),
        up('tr-EEE', 'Echo'),
      ], since: 'cur-9');
      expect(await relaunch().pendingFrees(), ['bk-DDD', 'bk-EEE']);
    });

    test('a kind change that carries the download over owes nothing', () async {
      await mirrored([up('bk-FFF', 'Foxtrot', type: MediaType.audiobook)]);
      await keepFor('bk-FFF');

      await delta([up('tr-FFF', 'Foxtrot')]);

      expect(await relaunch().pendingFrees(), isEmpty);
    });

    test('what a retried question names is owed at once', () async {
      await mirrored([up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')]);
      await keepFor('tr-BBB');
      repo
        ..removedForGood.add('tr-BBB')
        ..removedError = const WaxDeckApiException(
          code: 'catalog-maintenance',
          message: 'busy',
          statusCode: 503,
        )
        ..resetCatalogOnce = true;
      await delta([up('tr-AAA', 'Alpha')], since: 'cur-9');
      expect(await relaunch().pendingFrees(), isEmpty);

      repo.removedError = null;
      await relaunch().reconcile();

      expect(await relaunch().pendingFrees(), ['tr-BBB']);
    });

    test('a pid the mirror lists again is no longer owed', () async {
      await owedBook();

      // The item came back, as a kind change flipping twice can bring one.
      await delta([
        up('bk-DDD', 'Delta', type: MediaType.audiobook),
      ], since: 'cur-3');

      expect(await relaunch().pendingFrees(), isEmpty);
      // Forgotten for good, not hidden: it is not owed if it goes again.
      await db.delete(db.mirrorItems).go();
      expect(await relaunch().pendingFrees(), isEmpty);
    });

    group('bytes taken up after the commit', () {
      test('a file at an index it did not hold takes the pid out', () async {
        await owedBook();
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: 'bk-DDD',
                fileIndex: 7,
                essenceHash: 'bk-DDD-e7',
                etag: 'x',
                fileName: 'bk-DDD-7.mp3',
                localPath: '/downloads/bk-DDD-7.mp3',
                sizeBytes: 1024,
                state: 'complete',
              ),
            );

        expect(await relaunch().pendingFrees(), isEmpty);
      });

      test('a file replaced by other audio takes the pid out', () async {
        await owedBook();
        await (db.update(db.downloadRecords)
              ..where((t) => t.pid.equals('bk-DDD') & t.fileIndex.equals(1)))
            .write(const DownloadRecordsCompanion(essenceHash: Value('new')));

        expect(await relaunch().pendingFrees(), isEmpty);
      });

      test('a cover pinned at another size is no take-up', () async {
        await owedBook();
        await db
            .into(db.artworkPins)
            .insert(
              ArtworkPinsCompanion.insert(
                pid: 'bk-DDD',
                sizePx: 600,
                artUrl: '/media/art?pid=bk-DDD&size=600',
                etag: 'b',
                localPath: '/art/bk-DDD-600.jpg',
                sizeBytes: 4096,
                pinnedAt: DateTime.utc(2026, 10, 2),
              ),
            );

        // The free still comes; what it takes is what the promise lists.
        expect(await relaunch().pendingFrees(), ['bk-DDD']);
      });

      test('a cover pinned again is no take-up either', () async {
        await owedBook();
        await (db.update(
          db.artworkPins,
        )..where((t) => t.pid.equals('bk-DDD'))).write(
          ArtworkPinsCompanion(pinnedAt: Value(DateTime.utc(2026, 10, 2))),
        );

        expect(await relaunch().pendingFrees(), ['bk-DDD']);
      });
    });

    test('bytes already gone are not owed, and half gone still are', () async {
      await owedBook();
      await (db.delete(
        db.downloadRecords,
      )..where((t) => t.pid.equals('bk-DDD'))).go();

      // The files went and the cover has not: what is left is owed.
      expect(await relaunch().pendingFrees(), ['bk-DDD']);

      await (db.delete(
        db.artworkPins,
      )..where((t) => t.pid.equals('bk-DDD'))).go();
      expect(await relaunch().pendingFrees(), isEmpty);
    });

    test(
      'a promise this build cannot read is forgotten, not trusted',
      () async {
        await db
            .into(db.clientSettings)
            .insert(
              ClientSettingsCompanion.insert(
                key: 'waxdeck.sync.free.tr-ODD',
                value: 'not json at all',
              ),
            );

        expect(await engine.pendingFrees(), isEmpty);
        expect(await db.select(db.clientSettings).get(), isEmpty);
      },
    );

    group('settling', () {
      test('waits for the recorded bytes to be gone', () async {
        await owedBook();

        expect(await engine.settleFree('bk-DDD'), isFalse);
        expect(await engine.pendingFrees(), ['bk-DDD']);

        await (db.delete(
          db.downloadRecords,
        )..where((t) => t.pid.equals('bk-DDD'))).go();
        await (db.delete(
          db.artworkPins,
        )..where((t) => t.pid.equals('bk-DDD'))).go();
        expect(await engine.settleFree('bk-DDD'), isTrue);
        expect(await engine.pendingFrees(), isEmpty);
      });

      test('is not held open by bytes taken up since', () async {
        await owedBook();
        await (db.delete(
          db.downloadRecords,
        )..where((t) => t.pid.equals('bk-DDD'))).go();
        await (db.delete(
          db.artworkPins,
        )..where((t) => t.pid.equals('bk-DDD'))).go();
        // The listener downloads it again after the free: theirs, not owed.
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: 'bk-DDD',
                fileIndex: 0,
                essenceHash: 'again',
                etag: 'x',
                fileName: 'again.mp3',
                localPath: '/downloads/again.mp3',
                sizeBytes: 1024,
                state: 'complete',
              ),
            );

        expect(await engine.settleFree('bk-DDD'), isTrue);
        expect(await engine.pendingFrees(), isEmpty);
        expect(await pidsIn(db.downloadRecords), ['bk-DDD']);
      });

      test('a pid nothing is owed for settles at once', () async {
        expect(await engine.settleFree('tr-NONE'), isTrue);
      });
    });

    group('is written with the commit', () {
      late _FailsFreeWrites fails;
      late MirrorDatabase flaky;
      late SyncEngine eng;

      setUp(() {
        fails = _FailsFreeWrites();
        flaky = MirrorDatabase(
          DatabaseConnection(NativeDatabase.memory().interceptWith(fails)),
        );
        eng = SyncEngine(
          db: flaky,
          repository: repo,
          channelFactory: neverConnects(),
        );
      });

      tearDown(() async {
        eng.dispose();
        await flaky.close();
      });

      test('a tombstone commits with its promise or not at all', () async {
        repo.catalogPages.add(
          CatalogSyncPage(entries: [up('tr-AAA', 'Alpha')], nextSince: 'cur-1'),
        );
        await eng.pullCatalog();
        await holdIn(flaky, 'tr-AAA');

        fails.armed = true;
        repo.catalogPages.add(
          CatalogSyncPage(
            entries: [tombstone('tr-AAA', 'removed')],
            nextSince: 'cur-2',
          ),
        );
        await expectLater(eng.pullCatalog(), throwsStateError);
        expect(
          (await flaky.select(flaky.mirrorItems).get()).map((r) => r.pid),
          ['tr-AAA'],
          reason: 'the drop went with the promise that could not be kept',
        );

        // The cursor did not move, so the tombstone comes again, and lands.
        fails.armed = false;
        repo.catalogPages.add(
          CatalogSyncPage(
            entries: [tombstone('tr-AAA', 'removed')],
            nextSince: 'cur-2',
          ),
        );
        await eng.pullCatalog();
        expect(await flaky.select(flaky.mirrorItems).get(), isEmpty);
        expect(await eng.pendingFrees(), ['tr-AAA']);
      });

      test('a snapshot commits with its promises or not at all', () async {
        repo.catalogPages.add(
          CatalogSyncPage(
            entries: [up('tr-AAA', 'Alpha'), up('tr-BBB', 'Bravo')],
            nextSince: 'cur-1',
          ),
        );
        await eng.pullCatalog();
        await holdIn(flaky, 'tr-BBB');
        repo.removedForGood.add('tr-BBB');

        fails.armed = true;
        repo
          ..resetCatalogOnce = true
          ..catalogPages.add(
            CatalogSyncPage(
              entries: [up('tr-AAA', 'Alpha')],
              nextSince: 'cur-9',
            ),
          );
        await expectLater(eng.pullCatalog(), throwsStateError);

        expect(
          (await flaky.select(flaky.mirrorItems).get()).map((r) => r.pid),
          unorderedEquals(['tr-AAA', 'tr-BBB']),
        );
        expect(
          (await flaky.select(flaky.syncCursors).getSingle()).catalogSince,
          isNull,
          reason: 'the snapshot is taken again',
        );
      });
    });

    test('work given to beforeSync finishes before a frame pulls', () async {
      late void Function(String) deliver;
      final framed = SyncEngine(
        db: db,
        repository: repo,
        channelFactory: capturingFrames((sink) => deliver = sink),
      );
      addTearDown(framed.dispose);
      framed.start();
      final gate = Completer<void>();
      var ran = false;
      unawaited(
        framed.beforeSync(() async {
          await gate.future;
          ran = true;
        }),
      );

      deliver(jsonEncode({'type': 'invalidate', 'topic': 'catalog'}));
      await pumpEventQueue();
      expect(ran, isFalse);
      expect(repo.catalogCalls, 0, reason: 'the pull waits behind it');

      gate.complete();
      await pumpEventQueue();
      expect(ran, isTrue);
      expect(repo.catalogCalls, greaterThan(0));
    });
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

  test('a mirrored play state is announced with the state it stored', () async {
    // What the announcement is for is reacting to the state, and a
    // listener that had to read the mirror back for it paid a read per
    // checkpoint, every few seconds a player runs.
    repo.serverPages.addAll([const ServerSyncPage(nextSince: 'scur-1')]);
    await engine.pullServer(); // mints
    final announced = <PlayStateChange>[];
    final sub = engine.playStateChanged.listen(announced.add);
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
        ],
        nextSince: 'scur-2',
      ),
    );
    await engine.pullServer();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(announced.single.pid, 'tr-A');
    expect(announced.single.state?.positionMs, 7000);
    expect(announced.single.state?.starred, isTrue);
  });

  test('entity-state markers announce their pid without mirroring', () async {
    repo.serverPages.addAll([const ServerSyncPage(nextSince: 'scur-1')]);
    await engine.pullServer(); // mints
    final announced = <PlayStateChange>[];
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
    expect(announced.map((change) => change.pid), ['al-A', 'ar-B']);
    expect(announced.map((change) => change.state), everyElement(isNull));
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
