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

  @override
  Future<ServerSyncPage> syncServer({String? since, int? limit}) async {
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
    );
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
}
