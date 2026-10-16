import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/home/home_shelves.dart';
import 'package:waxdeck/src/player/entity_play_state_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck/src/sync/refresh_pacing.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// A native session with the binder mounted over [engine]'s mirror,
/// signed in as us-1 with [prefs], and the preference document watched.
Future<({ProviderContainer container, SyncEngine engine, FakeRepository repo})>
_bind({
  Prefs prefs = const Prefs(timezone: 'America/Denver'),
  List<ServerSyncPage> serverPages = const [],
  List<ProviderObserver> observers = const [],
}) async {
  final db = inMemoryMirrorDatabase();
  addTearDown(db.close);
  final downloads = FakeDownloads();
  addTearDown(downloads.dispose);
  final repo = _CountingRepository()
    ..sessionState = const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-1', username: 'admin'),
    )
    ..prefs = prefs
    ..serverPages.addAll(serverPages);
  final engine = SyncEngine(
    db: db,
    repository: repo,
    channelFactory: deadChannelFactory(),
  );
  addTearDown(engine.dispose);
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(FakeEngine()),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      mirrorDatabaseProvider.overrideWithValue(db),
      downloadManagerProvider.overrideWithValue(downloads),
      artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
      syncEngineProvider.overrideWithValue(engine),
    ],
    observers: observers,
  );
  addTearDown(container.dispose);
  final alive = container.listen(syncBinderProvider, (_, _) {});
  addTearDown(alive.close);
  container.listen(prefsControllerProvider, (_, _) {});
  await container.read(prefsControllerProvider.future);
  return (container: container, engine: engine, repo: repo);
}

/// One play state reported on the user stream, hydrated as the server
/// sends it.
ServerSyncPage _reported(
  String since, {
  String pid = 'tr-A',
  int positionMs = 0,
  bool finished = false,
  int minute = 0,
}) => ServerSyncPage(
  events: [
    ServerSyncEvent(
      kind: 'play-state',
      pid: pid,
      playState: PlayState(
        pid: pid,
        positionMs: positionMs,
        played: finished,
        finished: finished,
        playCount: finished ? 1 : 0,
        starred: false,
        updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
      ),
    ),
  ],
  nextSince: since,
);

/// Holds home's shelves open, as a mounted home does.
Future<void> _watchShelves(ProviderContainer container) async {
  for (final shelf in <FutureProvider<HomeShelfItems>>[
    continueListeningShelfProvider,
    recentlyAddedShelfProvider,
    mostPlayedShelfProvider,
  ]) {
    container.listen(shelf, (_, _) {});
    await container.read(shelf.future);
  }
}

/// Ends a session inside a fake-time test: the pacers' windows and the
/// engine's reconnect are timers, and one left pending fails the test.
Future<void> _signOut(WidgetTester tester, ProviderContainer container) async {
  container.dispose();
  await tester.pump();
}

/// Counts preference reads, which is what a user fan-out costs here,
/// health reads, which is what a health marker's costs, and task reads.
class _CountingRepository extends FakeRepository {
  int prefsReads = 0;
  int healthReads = 0;
  int taskReads = 0;

  @override
  Future<ToolTaskPage> listToolTasks({String? cursor, int? limit}) {
    taskReads++;
    return super.listToolTasks(cursor: cursor, limit: limit);
  }

  @override
  Future<Prefs> getPrefs() {
    prefsReads++;
    return super.getPrefs();
  }

  @override
  Future<HealthSummary> getLibraryHealth() {
    healthReads++;
    return super.getLibraryHealth();
  }

  int libraryReads = 0;

  @override
  Future<List<LibraryInfo>> listLibraries({bool counts = false}) {
    libraryReads++;
    return super.listLibraries(counts: counts);
  }

  int entityReads = 0;

  @override
  Future<EntityPlayState> getEntityPlayState(String pid) {
    entityReads++;
    return super.getEntityPlayState(pid);
  }
}

/// The user stream on native is walked by the sync engine, which mirrors
/// play states and publishes every event it walks. The surfaces that ride
/// the stream refresh through the user fan-out, which web runs on every
/// user invalidation - so native has to run it for every kind as well, not
/// only for the kinds its mirror stores.
void main() {
  test('a preference another device changed arrives', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final repo = FakeRepository()
      ..sessionState = const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-1', username: 'admin'),
      )
      ..prefs = const Prefs(timezone: 'America/Denver')
      ..serverPages.addAll(const <ServerSyncPage>[
        // The first walk mints the cursor; what follows it is news.
        ServerSyncPage(nextSince: 'scur-1'),
        ServerSyncPage(
          events: [
            ServerSyncEvent(
              kind: 'prefs',
              prefs: Prefs(timezone: 'Europe/Madrid'),
            ),
          ],
          nextSince: 'scur-2',
        ),
      ]);
    final engine = SyncEngine(
      db: db,
      repository: repo,
      channelFactory: deadChannelFactory(),
    );
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        mirrorDatabaseProvider.overrideWithValue(db),
        downloadManagerProvider.overrideWithValue(downloads),
        artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
        syncEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final alive = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(alive.close);
    container.listen(prefsControllerProvider, (_, _) {});
    await container.read(prefsControllerProvider.future);
    await engine.pullServer();

    repo.prefs = const Prefs(timezone: 'Europe/Madrid');
    await engine.pullServer();
    await pumpEventQueue();
    final loaded = await container.read(prefsControllerProvider.future);

    expect(loaded.timezone, 'Europe/Madrid');
  });

  test('the session names whose waiting patch goes out', () async {
    // Patches are kept per account; a session that named nobody would
    // leave its own account's waiting for good.
    final b = await _bind();
    await b.engine.queuePrefsPatch({'locale': 'es'}, owner: 'us-1');

    await b.engine.flushOutbox();

    expect(b.repo.prefs.locale, 'es');
  });

  testWidgets('a play-state change refreshes the user surfaces once', (
    tester,
  ) async {
    // Hinted by both the mirror's play-state signal and the event itself,
    // it would run the fan-out again at the end of the pacing window.
    final b = await _bind(
      serverPages: [
        const ServerSyncPage(nextSince: 'scur-1'),
        ServerSyncPage(
          events: [
            ServerSyncEvent(
              kind: 'play-state',
              pid: 'tr-A',
              playState: const PlayState(
                pid: 'tr-A',
                positionMs: 1000,
                played: false,
                finished: false,
                playCount: 0,
                starred: false,
              ),
            ),
          ],
          nextSince: 'scur-2',
        ),
      ],
    );
    await b.engine.pullServer();
    final reads = (b.repo as _CountingRepository).prefsReads;

    await b.engine.pullServer();
    await tester.pump(kUserRefreshWindow + const Duration(seconds: 1));

    expect((b.repo as _CountingRepository).prefsReads, reads + 1);
    await _signOut(tester, b.container);
  });

  test('a bookmarks event refreshes none of the user surfaces', () async {
    // The mirror stores the book's list and says so itself; nothing in
    // the user fan-out reads bookmarks.
    final b = await _bind(
      serverPages: [
        const ServerSyncPage(nextSince: 'scur-1'),
        ServerSyncPage(
          events: [
            ServerSyncEvent(
              kind: 'bookmarks',
              pid: 'bk-A',
              bookmarks: [
                Bookmark(
                  id: 'bm-01JZX5N8QW3F4V9T2B7KD3M9R6',
                  positionMs: 1000,
                  createdAt: DateTime.utc(2026, 9, 1),
                ),
              ],
            ),
          ],
          nextSince: 'scur-2',
        ),
      ],
    );
    await b.engine.pullServer();
    final reads = (b.repo as _CountingRepository).prefsReads;

    await b.engine.pullServer();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect((b.repo as _CountingRepository).prefsReads, reads);
  });

  test(
    'a task-progress marker refreshes the tasks and none of the user surfaces',
    () async {
      // A long task reports every five percent; the user fan-out on each
      // would refetch every open list for the length of it.
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'task-progress', pid: 'tk-1')],
            nextSince: 'scur-2',
          ),
        ],
      );
      b.container.listen(toolTasksProvider, (_, _) {});
      await b.container.read(toolTasksProvider.future);
      await b.engine.pullServer();
      final repo = b.repo as _CountingRepository;
      final (prefs, tasks) = (repo.prefsReads, repo.taskReads);

      await b.engine.pullServer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(repo.taskReads, tasks + 1);
      expect(repo.prefsReads, prefs);
    },
  );

  test(
    'a stream that lost its place refreshes every surface it feeds',
    () async {
      // What fell between the lost cursor and the fresh one is gone, so
      // nothing per-kind can say what to refresh.
      final b = await _bind();
      b.container
        ..listen(adminJobsProvider, (_, _) {})
        ..listen(healthProvider, (_, _) {});
      await b.container.read(adminJobsProvider.future);
      await b.container.read(healthProvider.future);
      final repo = b.repo as _CountingRepository;
      final (prefs, jobs, health) = (
        repo.prefsReads,
        repo.jobReads,
        repo.healthReads,
      );

      b.container.read(serverEventBusProvider).reset();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(repo.prefsReads, prefs + 1);
      expect(repo.jobReads, jobs + 1);
      expect(repo.healthReads, health + 1);
    },
  );

  test(
    'a job marker refreshes the jobs and none of the user surfaces',
    () async {
      // A running scan announces every five percent and its message
      // every fifteen seconds; running the user fan-out for each would
      // refetch every open list on every admin client for the length of
      // the scan.
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'job', pid: 'jb-1')],
            nextSince: 'scur-2',
          ),
        ],
      );
      b.container.listen(adminJobsProvider, (_, _) {});
      await b.container.read(adminJobsProvider.future);
      await b.engine.pullServer();
      final repo = b.repo as _CountingRepository;
      final prefs = repo.prefsReads;
      final jobs = repo.jobReads;

      await b.engine.pullServer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(repo.jobReads, jobs + 1);
      expect(repo.prefsReads, prefs);
    },
  );

  test(
    'a health marker refreshes health and none of the user surfaces',
    () async {
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'health')],
            nextSince: 'scur-2',
          ),
        ],
      );
      b.container.listen(healthProvider, (_, _) {});
      await b.container.read(healthProvider.future);
      await b.engine.pullServer();
      final repo = b.repo as _CountingRepository;
      final prefs = repo.prefsReads;
      final health = repo.healthReads;

      await b.engine.pullServer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(repo.healthReads, health + 1);
      expect(repo.prefsReads, prefs);
    },
  );

  test(
    'a libraries marker refreshes the libraries and none of the user surfaces',
    () async {
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'libraries')],
            nextSince: 'scur-2',
          ),
        ],
      );
      b.container.listen(libraryCountsProvider, (_, _) {});
      await b.container.read(libraryCountsProvider.future);
      await b.engine.pullServer();
      final repo = b.repo as _CountingRepository;
      final prefs = repo.prefsReads;
      final libraries = repo.libraryReads;

      await b.engine.pullServer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(repo.libraryReads, libraries + 1);
      expect(repo.prefsReads, prefs);
    },
  );

  group('home\'s library probe', () {
    const item = 'tr-01JZX5N8QW3F4V9T2B7KDHOME01';

    testWidgets('is asked once a run of catalog changes goes quiet, not '
        'on every pass', (tester) async {
      // A scan reports a change about once a second, and the probe was one
      // of the reads every pass cost an open home.
      final b = await _bind();
      b.repo.libraryItems.add(testItem(item));
      b.container.listen(libraryHasAnythingProvider, (_, _) {});
      expect(await b.container.read(libraryHasAnythingProvider.future), isTrue);
      final reads = b.repo.listItemsCalls.length;

      for (var hint = 0; hint < 10; hint++) {
        await b.engine.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(kCatalogRefreshWindow + const Duration(seconds: 1));

      expect(b.repo.listItemsCalls.length, reads + 1);
      await _signOut(tester, b.container);
    });

    testWidgets('a run that goes quiet over the probe\'s first read asks '
        'again once it lands', (tester) async {
      // A first read still out when the run goes quiet may have started
      // before the run's last change. The app's root container tracks
      // first builds; so does this one.
      final b = await _bind(observers: [FirstBuildObserver()]);
      b.repo.libraryItems.add(testItem(item));
      final gate = Completer<void>();
      b.repo.listItemsGate = gate;
      b.container.listen(libraryHasAnythingProvider, (_, _) {});
      await tester.pump();
      await b.engine.pullCatalog();
      await tester.pump(kCatalogRefreshWindow + const Duration(seconds: 1));
      final reads = b.repo.listItemsCalls.length;

      b.repo.listItemsGate = null;
      gate.complete();
      await tester.pump();
      await tester.pump(kCatalogRefreshWindow + const Duration(seconds: 1));

      expect(b.repo.listItemsCalls.length, greaterThan(reads));
      await _signOut(tester, b.container);
    });

    testWidgets('finds a library that emptied once its changes go quiet', (
      tester,
    ) async {
      // A scan that finds its files gone, or a delete made on another
      // device, arrives as catalog changes like any other: the library
      // can empty under a probe that said it held something.
      final b = await _bind();
      b.repo.libraryItems.add(testItem(item));
      b.container.listen(libraryHasAnythingProvider, (_, _) {});
      expect(await b.container.read(libraryHasAnythingProvider.future), isTrue);

      b.repo.libraryItems.clear();
      await b.engine.pullCatalog();
      await tester.pump(kCatalogRefreshWindow + const Duration(seconds: 1));

      expect(
        await b.container.read(libraryHasAnythingProvider.future),
        isFalse,
      );
      await _signOut(tester, b.container);
    });

    test(
      'is asked again by a catalog change while the library reads empty',
      () async {
        // The first-run state ends when a first scan or upload lands, and
        // that arrives as a catalog change.
        final b = await _bind();
        b.container.listen(libraryHasAnythingProvider, (_, _) {});
        expect(
          await b.container.read(libraryHasAnythingProvider.future),
          isFalse,
        );

        b.repo.libraryItems.add(testItem(item));
        await b.engine.pullCatalog();
        await Future<void>.delayed(const Duration(milliseconds: 1500));

        expect(
          await b.container.read(libraryHasAnythingProvider.future),
          isTrue,
        );
      },
    );

    test('is asked again when the libraries change', () async {
      // A library added, restored or taken away can change the answer
      // either way.
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'libraries')],
            nextSince: 'scur-2',
          ),
        ],
      );
      b.repo.libraryItems.add(testItem(item));
      b.container.listen(libraryHasAnythingProvider, (_, _) {});
      await b.container.read(libraryHasAnythingProvider.future);
      await b.engine.pullServer();
      final reads = b.repo.listItemsCalls.length;

      await b.engine.pullServer();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(b.repo.listItemsCalls.length, reads + 1);
    });
  });

  group('home under a busy stream', () {
    testWidgets('a play-state report that only moves the position refetches '
        'no shelf', (tester) async {
      // A player checkpoints every few seconds, and each one came back as
      // a report that refetched every shelf of an open home.
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          _reported('scur-2', positionMs: 1000, minute: 1),
          _reported('scur-3', positionMs: 6000, minute: 2),
        ],
      );
      final repo = b.repo as _CountingRepository;
      await _watchShelves(b.container);
      await b.engine.pullServer();
      // The first report of an item can put it on a shelf, so it hints.
      await b.engine.pullServer();
      await tester.pump(const Duration(seconds: 6));
      final (browses, prefs) = (repo.browseCalls.length, repo.prefsReads);

      await b.engine.pullServer();
      await tester.pump(const Duration(seconds: 6));

      expect(repo.browseCalls.length, browses);
      expect(repo.prefsReads, prefs, reason: 'no user pass at all');
      await _signOut(tester, b.container);
    });

    testWidgets('a report that finishes the item refetches the shelves', (
      tester,
    ) async {
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          _reported('scur-2', positionMs: 1000, minute: 1),
          _reported('scur-3', positionMs: 214000, finished: true, minute: 2),
        ],
      );
      final repo = b.repo as _CountingRepository;
      await _watchShelves(b.container);
      await b.engine.pullServer();
      await b.engine.pullServer();
      await tester.pump(const Duration(seconds: 6));
      final (browses, prefs) = (repo.browseCalls.length, repo.prefsReads);

      await b.engine.pullServer();
      await tester.pump(const Duration(seconds: 6));

      expect(repo.browseCalls.length, greaterThan(browses));
      expect(repo.prefsReads, prefs + 1);
      await _signOut(tester, b.container);
    });

    testWidgets('an artist starred elsewhere refreshes the entity rows and '
        'no shelf', (tester) async {
      final b = await _bind(
        serverPages: [
          const ServerSyncPage(nextSince: 'scur-1'),
          const ServerSyncPage(
            events: [ServerSyncEvent(kind: 'entity-state', pid: 'ar-1')],
            nextSince: 'scur-2',
          ),
        ],
      );
      final repo = b.repo as _CountingRepository;
      await _watchShelves(b.container);
      final star = entityPlayStateControllerProvider('ar-1');
      b.container.listen(star, (_, _) {});
      await b.container.read(star.future);
      await b.engine.pullServer();
      final (browses, prefs, entities) = (
        repo.browseCalls.length,
        repo.prefsReads,
        repo.entityReads,
      );

      await b.engine.pullServer();
      await tester.pump(const Duration(seconds: 6));

      expect(repo.entityReads, entities + 1);
      expect(repo.browseCalls.length, browses);
      expect(repo.prefsReads, prefs);
      await _signOut(tester, b.container);
    });

    testWidgets('a scan costs one pass per window, not one per hint', (
      tester,
    ) async {
      // A running scan reports a catalog change about once a second, and
      // home refetched every shelf for each one.
      final b = await _bind();
      b.repo.libraryItems.add(testItem('tr-01JZX5N8QW3F4V9T2B7KDSCAN01'));
      await _watchShelves(b.container);
      int passes() => b.repo.browseCalls
          .where((call) => call.list == DiscoveryList.recentlyAdded)
          .length;
      final before = passes();

      for (var hint = 0; hint < 10; hint++) {
        await b.engine.pullCatalog();
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(seconds: 6));

      // The leading pass, then at most one trailing pass per 5 s window
      // across the ten seconds the hints arrived over.
      expect(passes() - before, inInclusiveRange(2, 3));
      await _signOut(tester, b.container);
    });
  });
}
