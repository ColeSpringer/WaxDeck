import 'dart:async';
import 'dart:io';

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

/// A server with a catalog of its own. A cursor it did not mint answers
/// `sync-reset`, as one from another server's generation does, and with
/// [namesEverything] it calls every pid it is asked about gone for good:
/// the wrong answer that must never cost another server's downloads.
class _Server extends FakeRepository {
  _Server(String address, this.catalog) {
    baseUrl = address;
  }

  final List<ItemSummary> catalog;
  final asked = <String>[];
  bool namesEverything = false;

  @override
  Future<CatalogSyncPage> syncCatalog({
    String? since,
    String? cursor,
    int? limit,
  }) async {
    if (since != null && !since.startsWith(baseUrl)) {
      throw const WaxDeckApiException(
        code: 'sync-reset',
        message: 'another catalog generation',
        statusCode: 410,
      );
    }
    if (since != null) return CatalogSyncPage(nextSince: since);
    return CatalogSyncPage(
      entries: [
        for (final item in catalog)
          CatalogSyncEntry(op: 'upsert', pid: item.pid, item: item),
      ],
      nextSince: '$baseUrl#1',
    );
  }

  @override
  Future<List<String>> syncCatalogRemoved(List<String> pids) async {
    asked.addAll(pids);
    return namesEverything ? pids : const <String>[];
  }

  /// For an item of its own catalog, whose one file is its ULID's whatever
  /// kind the item has; any other is not found.
  @override
  Future<DownloadInfo> getDownloadInfo(String pid) async {
    if (!catalog.any((item) => item.pid == pid)) {
      throw const WaxDeckApiException(
        code: 'not-found',
        message: 'no item',
        statusCode: 404,
      );
    }
    final ulid = pid.substring(pid.indexOf('-') + 1);
    return DownloadInfo(
      pid: pid,
      files: [
        DownloadFileInfo(
          url: '/media/download?pid=$pid&mt=test-token',
          mimeType: 'audio/flac',
          sizeBytes: 1024,
          fileName: '$ulid.flac',
          essenceHash: 'essence-$ulid',
          etag: '1024-1',
        ),
      ],
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }
}

/// Lands every transfer at once, as a file in [dir] under the name it was
/// started for.
class _Landing implements TransferEnginePort {
  _Landing(this.dir);

  final Directory dir;
  final _events = StreamController<TransferEvent>.broadcast();
  var _tasks = 0;

  @override
  Stream<TransferEvent> get events => _events.stream;

  @override
  Future<String> start(TransferRequest request) async {
    final id = 'task-${_tasks++}';
    final file = File('${dir.path}/${request.fileName}')
      ..writeAsBytesSync(const [1, 2, 3]);
    scheduleMicrotask(
      () => _events.add(
        TransferEvent(
          taskId: id,
          state: TransferState.complete,
          path: file.path,
          pid: request.pid,
          fileName: request.fileName,
        ),
      ),
    );
    return id;
  }

  @override
  Future<List<TrackedTransfer>> trackedTransfers() async => const [];

  @override
  Future<String?> mediaDirectory() async => dir.path;

  @override
  Future<void> recover() async {}

  @override
  Future<void> describe(TransferGroup group) async {}

  @override
  Future<bool> pause(String taskId) async => false;

  @override
  Future<void> resume(String taskId, {String? url, DateTime? staleAt}) async {}

  @override
  Future<void> cancel(List<String> taskIds) async {}

  @override
  Future<NotificationPermission> notificationPermission() async =>
      NotificationPermission.granted;

  @override
  Future<NotificationPermission> requestNotificationPermission() async =>
      NotificationPermission.granted;

  @override
  void dispose() => _events.close();
}

/// "Change server" keeps the mirror and the downloads, and a different
/// server answers the old cursor with a sync-reset, so the device takes a
/// snapshot that lists none of the old server's items. What it asks about
/// those is up to the server they came from: the new one is never asked,
/// so even a wrong answer could not free them, and back on the old server
/// they play.
void main() {
  /// The app's sync and downloads over a database of their own, reaching
  /// [a] until `ServerAddressController.adopt` points them at [b], as
  /// "Change server" does. The manager is the app's, told of a server
  /// change as the app tells it, over an engine that lands every transfer.
  ({
    ProviderContainer container,
    BackgroundDownloadManager manager,
    MirrorDatabase db,
  })
  switching(_Server a, _Server b) {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    final media = Directory.systemTemp.createTempSync('waxdeck-switch-');
    addTearDown(() => media.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        bootServerAddressProvider.overrideWithValue(a.baseUrl),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        repositoryProvider.overrideWith(
          (ref) => ref.watch(serverBaseUrlProvider) == a.baseUrl ? a : b,
        ),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        mirrorDatabaseProvider.overrideWithValue(db),
        artworkStoreProvider.overrideWithValue(FakeArtworkStore()),
        // As the app builds both, bar the socket: the engine follows the
        // repository, and the downloads manager outlives a server change.
        syncEngineProvider.overrideWith((ref) {
          final engine = SyncEngine(
            db: db,
            repository: ref.watch(repositoryProvider),
            channelFactory: deadChannelFactory(),
          );
          ref.onDispose(engine.dispose);
          return engine;
        }),
        downloadManagerProvider.overrideWith((ref) {
          final manager = BackgroundDownloadManager(
            db: db,
            repository: () => ref.read(repositoryProvider),
            engine: _Landing(media),
            copy: () => DownloadCopy(
              downloading: (progress) => progress,
              downloaded: 'Downloaded',
              failed: 'Failed',
              part: (title, number, total) => title,
            ),
          );
          ref.onDispose(manager.dispose);
          tellOfServerChanges(ref, manager);
          return manager;
        }),
      ],
    );
    addTearDown(container.dispose);
    // The signed-in shell holds the binder open in the app.
    final alive = container.listen(syncBinderProvider, (_, _) {});
    addTearDown(alive.close);
    return (
      container: container,
      manager:
          container.read(downloadManagerProvider)! as BackgroundDownloadManager,
      db: db,
    );
  }

  test('a visit to another server frees none of the downloads, which play '
      'again back on their own', () async {
    final a = _Server('http://a.test', [
      testItem('tr-A1', title: 'Alpha'),
      testItem('tr-A2', title: 'Bravo'),
    ]);
    final b = _Server('http://b.test', [testItem('tr-B1', title: 'Charlie')])
      ..namesEverything = true;
    final (:container, :manager, :db) = switching(a, b);

    Future<void> sync() async {
      await container.read(syncEngineProvider)!.pullCatalog();
      await pumpEventQueue(times: 50);
    }

    Future<void> playsOffline() async {
      for (final pid in ['tr-A1', 'tr-A2']) {
        final local = await manager.localFor(pid);
        expect(local, isNotNull, reason: '$pid plays from disk');
        expect(File(local!.parts.single.path).existsSync(), isTrue);
      }
    }

    // On the first server: its catalog mirrored, two items downloaded.
    await sync();
    await manager.download('tr-A1');
    await manager.download('tr-A2');
    await manager.settled;
    await playsOffline();

    await container.read(serverAddressProvider.notifier).adopt('http://b.test');
    await sync();

    expect((await mirrorItemsPage(db)).items.map((i) => i.pid), [
      'tr-B1',
    ], reason: 'the other server mirrored in their place');
    await playsOffline();
    expect(b.asked, isEmpty, reason: 'the downloads are not its to judge');
    expect(await container.read(syncEngineProvider)!.pendingFrees(), isEmpty);

    await container.read(serverAddressProvider.notifier).adopt('http://a.test');
    await sync();

    expect((await mirrorItemsPage(db)).items.map((i) => i.pid), [
      'tr-A1',
      'tr-A2',
    ]);
    await playsOffline();
  });

  test('a download the server does not know waits for the next, and goes '
      'on there', () async {
    final a = _Server('http://a.test', [testItem('tr-A1', title: 'Alpha')]);
    final b = _Server('http://b.test', [testItem('tr-OLD', title: 'Older')]);
    final (:container, :manager, :db) = switching(a, b);
    // B's item, left part-way by a run from before rows named the server
    // a download came from, on a device pointed at A.
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'tr-OLD',
            fileIndex: 0,
            essenceHash: 'essence-OLD',
            etag: '1024-1',
            fileName: 'essence-OLD.flac',
            localPath: '',
            sizeBytes: 1024,
            state: 'pending',
          ),
        );

    await manager.recover();
    await manager.settled;

    expect(a.asked, ['tr-OLD'], reason: 'A says whether it is gone for good');
    expect((await db.select(db.downloadRecords).getSingle()).state, 'pending');

    await container.read(serverAddressProvider.notifier).adopt('http://b.test');
    await pumpEventQueue(times: 50);
    await manager.settled;

    expect(await manager.isComplete('tr-OLD'), isTrue);
    expect(
      (await db.select(db.downloadRecords).getSingle()).server,
      'http://b.test',
    );
    expect(b.asked, isEmpty);
  });

  test('a one-file download whose item became a book while the device was '
      'away plays offline as the book', () async {
    final a = _Server('http://a.test', [testItem('tr-K1', title: 'Kilo')]);
    final b = _Server('http://b.test', const []);
    final (:container, :manager, :db) = switching(a, b);
    final engine = container.read(syncEngineProvider)!;
    await engine.pullCatalog();
    await manager.download('tr-K1');
    await manager.settled;
    // Written before rows named the server a download came from.
    await db
        .update(db.downloadRecords)
        .write(const DownloadRecordsCompanion(server: Value(null)));

    // Treated as an audiobook on the server, and mirrored afresh.
    a.catalog[0] = testItem(
      'bk-K1',
      title: 'Kilo',
      mediaType: MediaType.audiobook,
    );
    await engine.resyncCatalog();
    await pumpEventQueue(times: 50);

    final local = await manager.localFor('bk-K1');
    expect(local, isNotNull, reason: 'bk-K1 plays from disk');
    expect(File(local!.parts.single.path).existsSync(), isTrue);
    final file = await db.select(db.downloadRecords).getSingle();
    expect((file.pid, file.server), ('bk-K1', a.baseUrl));
    expect(await engine.pendingFrees(), isEmpty);
  });
}
