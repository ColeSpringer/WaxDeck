import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/health/health_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/server_event_bus.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
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
  );
  addTearDown(container.dispose);
  final alive = container.listen(syncBinderProvider, (_, _) {});
  addTearDown(alive.close);
  container.listen(prefsControllerProvider, (_, _) {});
  await container.read(prefsControllerProvider.future);
  return (container: container, engine: engine, repo: repo);
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

  test('a play-state change refreshes the user surfaces once', () async {
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
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect((b.repo as _CountingRepository).prefsReads, reads + 1);
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
}
