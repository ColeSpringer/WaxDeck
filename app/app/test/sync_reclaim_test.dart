import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'offline_home_test.dart' show deadChannelFactory;

/// What a delete tombstone costs an offline client.
///
/// The catalog archives an item on every delete mode, so "the row is
/// gone" cannot say whether the audio can come back; the server answers
/// that with the entry's `reason`, and this is the client half of the
/// bargain: `removed` frees the download and the artwork pinned beside
/// it, `hidden` frees neither, because undoing a trash would otherwise
/// cost the whole transfer again.
void main() {
  Future<(ProviderContainer, FakeDownloads, FakeArtworkStore)> bind(
    List<CatalogSyncEntry> tombstones,
  ) async {
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    final artwork = FakeArtworkStore();
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final repo = FakeRepository()
      ..catalogPages.addAll(<CatalogSyncPage>[
        // The first pull mints the cursor a delta needs; the tombstones
        // ride the second, which is the shape the engine drives.
        const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        CatalogSyncPage(entries: tombstones, nextSince: 'cur-2'),
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
        artworkStoreProvider.overrideWithValue(artwork),
        syncEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    // Listened, not read: the binder is autoDispose, and the signed-in
    // shell is what holds it open in the app. A bare read would let it
    // dispose between one reclaim and the next.
    final alive = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(alive.close);

    await engine.pullCatalog();
    await engine.pullCatalog();
    // Generously, because the binder chains its reclaims rather than
    // firing them at once: draining the queue is several turns per pid.
    await pumpEventQueue(times: 50);
    return (container, downloads, artwork);
  }

  test(
    'a delete that cannot be undone frees the bytes and the artwork',
    () async {
      final (_, downloads, artwork) = await bind(const <CatalogSyncEntry>[
        CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
      ]);

      expect(downloads.removed, contains('tr-GONE'));
      // Both halves: the artwork pin lives in a table the downloads port
      // knows nothing about, so removing the audio alone leaves image
      // files nothing short of a sign-out reclaims.
      expect(artwork.unpinned, contains('tr-GONE'));
    },
  );

  test('reclaims one at a time, so a shared file is never orphaned', () async {
    // `remove` decides whether to unlink by asking whether any *other*
    // row still holds the same essence, so two items sharing one (CUE
    // siblings share an image) reclaimed at once each see the other's
    // row, each conclude the file is shared, and leave it on disk. A
    // delta page that retires a pair delivers both tombstones together,
    // which makes this the ordinary case rather than a race.
    final (_, downloads, _) = await bind(const <CatalogSyncEntry>[
      CatalogSyncEntry(op: 'delete', pid: 'tr-ONE', reason: 'removed'),
      CatalogSyncEntry(op: 'delete', pid: 'tr-TWO', reason: 'removed'),
      CatalogSyncEntry(op: 'delete', pid: 'tr-THREE', reason: 'removed'),
    ]);

    expect(downloads.removed, hasLength(3));
    expect(downloads.peakConcurrentRemovals, 1);
  });

  test(
    'a trashed item keeps its download, so a restore costs no transfer',
    () async {
      final (_, downloads, artwork) = await bind(const <CatalogSyncEntry>[
        CatalogSyncEntry(op: 'delete', pid: 'tr-TRASH', reason: 'hidden'),
        // A server too old to send a reason lands on the same half.
        CatalogSyncEntry(op: 'delete', pid: 'tr-OLD'),
      ]);

      expect(downloads.removed, isEmpty);
      expect(artwork.unpinned, isEmpty);
    },
  );
}
