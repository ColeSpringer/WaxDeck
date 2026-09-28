import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
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

/// Counts preference reads, which is what a user fan-out costs here.
class _CountingRepository extends FakeRepository {
  int prefsReads = 0;

  @override
  Future<Prefs> getPrefs() {
    prefsReads++;
    return super.getPrefs();
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
}
