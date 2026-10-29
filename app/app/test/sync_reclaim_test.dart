import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/artwork/artwork_providers.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/downloads/downloads_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sync/sync_binder.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// A downloads store that decides and frees as the real one does: whether
/// the free is still owed is asked of the promise when it runs, and what it
/// deletes is the rows the promise lists, with the records going with the
/// bytes. What the sync reads to know a free is done.
class _RecordedDownloads extends FakeDownloads {
  _RecordedDownloads(this.db);

  final MirrorDatabase db;

  /// Run once a free has decided it is owed and before it deletes, as a
  /// writer outside the manager's chain would land.
  Future<void> Function()? afterDecision;

  /// How many times the downloads list was read, which is once a build.
  var listed = 0;

  @override
  Future<List<DownloadedItem>> stored() {
    listed++;
    return super.stored();
  }

  @override
  Future<void> remove(String pid) async {
    await super.remove(pid);
    await (db.delete(db.downloadRecords)..where((t) => t.pid.equals(pid))).go();
  }

  @override
  Future<List<OwedPin>?> freeOwed(String pid) async {
    final owed = await PendingFrees(db).owed(pid);
    if (owed == null) return null;
    await afterDecision?.call();
    await super.remove(pid);
    for (final file in owed.files) {
      await (db.delete(db.downloadRecords)
            ..where((t) => t.pid.equals(pid))
            ..where((t) => t.fileIndex.equals(file.index))
            ..where((t) => t.essenceHash.equals(file.essence)))
          .go();
    }
    return owed.pins;
  }
}

/// The same for the pinned covers.
class _RecordedArtwork extends FakeArtworkStore {
  _RecordedArtwork(this.db);

  final MirrorDatabase db;

  @override
  Future<void> unpin(String pid) async {
    await super.unpin(pid);
    await (db.delete(db.artworkPins)..where((t) => t.pid.equals(pid))).go();
  }

  @override
  Future<void> unpinExact(String pid, List<OwedPin> owed) async {
    await super.unpinExact(pid, owed);
    for (final pin in owed) {
      await (db.delete(db.artworkPins)
            ..where((t) => t.pid.equals(pid))
            ..where((t) => t.sizePx.equals(pin.sizePx))
            ..where((t) => t.pinnedAt.equals(pin.pinnedAt)))
          .go();
    }
  }
}

/// One run of the app: an engine and a binder over a database, which a
/// later run can open again.
class _Run {
  _Run({
    required this.db,
    required this.engine,
    required this.downloads,
    required this.artwork,
    required this.container,
    required this.alive,
  });

  final MirrorDatabase db;
  final SyncEngine engine;
  final _RecordedDownloads downloads;
  final _RecordedArtwork artwork;
  final ProviderContainer container;
  final ProviderSubscription<void> alive;
  var _ended = false;

  /// The run ends where it stands: a free still going is never finished.
  void end() {
    if (_ended) return;
    _ended = true;
    alive.close();
    container.dispose();
    engine.dispose();
    downloads.dispose();
  }
}

/// What a device holds for an item it downloaded from the test server: a
/// file and a cover.
Future<void> _hold(
  MirrorDatabase db,
  String pid, {
  String state = 'complete',
}) async {
  await db
      .into(db.downloadRecords)
      .insertOnConflictUpdate(
        DownloadRecordsCompanion.insert(
          pid: pid,
          fileIndex: 0,
          essenceHash: pid,
          etag: '1-1',
          fileName: '$pid.flac',
          localPath: state == 'complete' ? '/downloads/$pid.flac' : '',
          sizeBytes: 1024,
          state: state,
          server: const Value(testServerAddress),
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

/// What a delete tombstone costs an offline client.
///
/// The catalog archives an item on every delete mode, so "the row is
/// gone" cannot say whether the audio can come back; the server answers
/// that with the entry's `reason`, and this is the client half of the
/// bargain: `removed` frees the download and the artwork pinned beside
/// it, `hidden` frees neither, because undoing a trash would otherwise
/// cost the whole transfer again.
///
/// A snapshot carries no tombstones, so a device that re-mirrors (the
/// first pull of an install, or after a sync-reset) is told the same by
/// asking the server about what it holds and the snapshot lacks: `held`
/// are the pids it holds a download for, and `gone` those the server says
/// it can never put back.
///
/// Either way the drop commits with a promise to free, and the promise
/// outlives the run: the free a kill cut short is finished at the next
/// start.
void main() {
  _Run launch(
    MirrorDatabase db, {
    FakeRepository? repo,
    _RecordedDownloads? downloads,
  }) {
    final repository = repo ?? FakeRepository();
    final store = downloads ?? _RecordedDownloads(db);
    final covers = _RecordedArtwork(db);
    final engine = SyncEngine(
      db: db,
      repository: repository,
      channelFactory: deadChannelFactory(),
    );
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        mirrorDatabaseProvider.overrideWithValue(db),
        downloadManagerProvider.overrideWithValue(store),
        artworkStoreProvider.overrideWithValue(covers),
        syncEngineProvider.overrideWithValue(engine),
      ],
    );
    // Listened, not read: the binder is autoDispose, and the signed-in
    // shell is what holds it open in the app. A bare read would let it
    // dispose between one reclaim and the next.
    final run = _Run(
      db: db,
      engine: engine,
      downloads: store,
      artwork: covers,
      container: container,
      alive: container.listen(syncBinderProvider, (_, _) {}),
    );
    addTearDown(run.end);
    return run;
  }

  Future<_Run> bind(
    List<CatalogSyncEntry> tombstones, {
    List<String> held = const [],
    Set<String> gone = const {},
  }) async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    for (final pid in held) {
      await _hold(db, pid);
    }
    final repo = FakeRepository()
      ..removedForGood.addAll(gone)
      ..catalogPages.addAll(<CatalogSyncPage>[
        // The first pull mints the cursor a delta needs; the tombstones
        // ride the second, which is the shape the engine drives.
        const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        CatalogSyncPage(entries: tombstones, nextSince: 'cur-2'),
      ]);
    final run = launch(db, repo: repo);
    await run.engine.pullCatalog();
    await run.engine.pullCatalog();
    // Generously, because the binder chains its reclaims rather than
    // firing them at once: draining the queue is several turns per pid.
    await pumpEventQueue(times: 50);
    return run;
  }

  test(
    'a delete that cannot be undone frees the bytes and the artwork',
    () async {
      final run = await bind(
        const <CatalogSyncEntry>[
          CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
        ],
        held: const ['tr-GONE'],
      );

      expect(run.downloads.removed, contains('tr-GONE'));
      // Both halves: the artwork pin lives in a table the downloads port
      // knows nothing about, so removing the audio alone leaves image
      // files nothing short of a sign-out reclaims.
      expect(run.artwork.unpinned, contains('tr-GONE'));
      // And the promise is kept, and cleared by the free itself: read off
      // the table, since asking what is owed would forget it on the way.
      expect(await run.db.select(run.db.clientSettings).get(), isEmpty);
    },
  );

  /// Two items dropped by one page, and the first held behind its gate, so
  /// the second waits its turn: the time in which a device can take it up.
  Future<(_Run, _RecordedDownloads, MirrorDatabase)> waiting() async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await _hold(db, 'tr-ONE');
    await _hold(db, 'tr-TWO');
    final repo = FakeRepository()
      ..catalogPages.addAll(<CatalogSyncPage>[
        const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        const CatalogSyncPage(
          entries: [
            CatalogSyncEntry(op: 'delete', pid: 'tr-ONE', reason: 'removed'),
            CatalogSyncEntry(op: 'delete', pid: 'tr-TWO', reason: 'removed'),
          ],
          nextSince: 'cur-2',
        ),
      ]);
    // One at a time, so the second waits behind the first's free.
    final slow = _RecordedDownloads(db)..removeGate = Completer<void>();
    final run = launch(db, repo: repo, downloads: slow);
    await run.engine.pullCatalog();
    await run.engine.pullCatalog();
    await pumpEventQueue(times: 50);
    expect(slow.removed, isEmpty, reason: 'the first free is under way');
    return (run, slow, db);
  }

  test('a file taken up while the pid waits its turn keeps the lot', () async {
    final (run, slow, db) = await waiting();

    // After the commit that owes both, the device takes a file up for the
    // second: the free decides when it runs, and finds it no longer owed.
    await db
        .into(db.downloadRecords)
        .insert(
          DownloadRecordsCompanion.insert(
            pid: 'tr-TWO',
            fileIndex: 4,
            essenceHash: 'again',
            etag: '1-2',
            fileName: 'again.flac',
            localPath: '/downloads/again.flac',
            sizeBytes: 1024,
            state: 'complete',
          ),
        );
    slow.removeGate!.complete();
    await pumpEventQueue(times: 50);

    expect(slow.removed, ['tr-ONE']);
    expect(
      (await db.select(db.downloadRecords).get()).map((r) => r.pid),
      unorderedEquals(['tr-TWO', 'tr-TWO']),
    );
    expect(await db.select(db.artworkPins).get(), hasLength(1));
    expect(await run.engine.pendingFrees(), isEmpty);
  });

  test('a cover pinned while the pid waits its turn is left alone, and the '
      'rest goes', () async {
    final (run, slow, db) = await waiting();

    await db
        .into(db.artworkPins)
        .insert(
          ArtworkPinsCompanion.insert(
            pid: 'tr-TWO',
            sizePx: 600,
            artUrl: '/media/art?pid=tr-TWO&size=600',
            etag: 'b',
            localPath: '/art/tr-TWO-600.jpg',
            sizeBytes: 4096,
            pinnedAt: DateTime.utc(2026, 10, 2),
          ),
        );
    slow.removeGate!.complete();
    await pumpEventQueue(times: 50);

    // The free takes what the promise listed, the audio and its cover, and
    // the cover that landed since is not among them.
    expect(slow.removed, ['tr-ONE', 'tr-TWO']);
    expect(await db.select(db.downloadRecords).get(), isEmpty);
    expect(
      (await db.select(db.artworkPins).get()).map((p) => (p.pid, p.sizePx)),
      [('tr-TWO', 600)],
    );
    expect(await run.engine.pendingFrees(), isEmpty);
  });

  test('a file that lands between the decision and the delete is not '
      'deleted with the rest', () async {
    final db = inMemoryMirrorDatabase();
    addTearDown(db.close);
    await _hold(db, 'tr-GONE');
    final repo = FakeRepository()
      ..catalogPages.addAll(<CatalogSyncPage>[
        const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        const CatalogSyncPage(
          entries: [
            CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
          ],
          nextSince: 'cur-2',
        ),
      ]);
    final downloads = _RecordedDownloads(db)
      ..afterDecision = () => db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              pid: 'tr-GONE',
              fileIndex: 5,
              essenceHash: 'late',
              etag: '1-3',
              fileName: 'late.flac',
              localPath: '/downloads/late.flac',
              sizeBytes: 1024,
              state: 'complete',
            ),
          );
    final run = launch(db, repo: repo, downloads: downloads);
    await run.engine.pullCatalog();
    await run.engine.pullCatalog();
    await pumpEventQueue(times: 50);

    // The listed file and cover go; the one that landed is the device's.
    expect(
      (await db.select(db.downloadRecords).get()).map((r) => r.fileIndex),
      [5],
    );
    expect(await db.select(db.artworkPins).get(), isEmpty);
    expect(await run.engine.pendingFrees(), isEmpty);
  });

  test(
    'a cover that lands between the decision and the unpin is kept',
    () async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      await _hold(db, 'tr-GONE');
      final repo = FakeRepository()
        ..catalogPages.addAll(<CatalogSyncPage>[
          const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
          const CatalogSyncPage(
            entries: [
              CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
            ],
            nextSince: 'cur-2',
          ),
        ]);
      final downloads = _RecordedDownloads(db)
        ..afterDecision = () => db
            .into(db.artworkPins)
            .insert(
              ArtworkPinsCompanion.insert(
                pid: 'tr-GONE',
                sizePx: 600,
                artUrl: '/media/art?pid=tr-GONE&size=600',
                etag: 'b',
                localPath: '/art/tr-GONE-600.jpg',
                sizeBytes: 4096,
                pinnedAt: DateTime.utc(2026, 10, 2),
              ),
            );
      final run = launch(db, repo: repo, downloads: downloads);
      await run.engine.pullCatalog();
      await run.engine.pullCatalog();
      await pumpEventQueue(times: 50);

      expect(await db.select(db.downloadRecords).get(), isEmpty);
      expect((await db.select(db.artworkPins).get()).map((p) => p.sizePx), [
        600,
      ], reason: 'the listed cover went, the one that landed stayed');
      expect(await run.engine.pendingFrees(), isEmpty);
    },
  );

  test(
    'a download that finishes after the commit is freed with the rest',
    () async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      await _hold(db, 'tr-GONE', state: 'pending');
      final repo = FakeRepository()
        ..catalogPages.addAll(<CatalogSyncPage>[
          const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
          const CatalogSyncPage(
            entries: [
              CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
            ],
            nextSince: 'cur-2',
          ),
        ]);
      final downloads = _RecordedDownloads(db)..removeGate = Completer<void>();
      final run = launch(db, repo: repo, downloads: downloads);
      await run.engine.pullCatalog();
      await run.engine.pullCatalog();
      await pumpEventQueue(times: 50);
      expect(downloads.removed, isEmpty, reason: 'its free is waiting');

      // The transfer lands before the free comes round, under the same key.
      await (db.update(
        db.downloadRecords,
      )..where((t) => t.pid.equals('tr-GONE'))).write(
        const DownloadRecordsCompanion(
          state: Value('complete'),
          localPath: Value('/downloads/tr-GONE.flac'),
        ),
      );
      downloads.removeGate!.complete();
      await pumpEventQueue(times: 50);

      expect(downloads.removed, ['tr-GONE']);
      expect(await db.select(db.downloadRecords).get(), isEmpty);
      expect(await run.engine.pendingFrees(), isEmpty);
    },
  );

  test('a re-mirror frees what the server removed while the device was '
      'away', () async {
    final run = await bind(
      const <CatalogSyncEntry>[],
      held: ['tr-GONE', 'tr-TRASH'],
      gone: {'tr-GONE'},
    );

    // The same two halves a `removed` tombstone frees, and only for the
    // item the server cannot give back: the other was trashed, or went
    // out of this account's sight, and a restore would cost the transfer.
    expect(run.downloads.removed, ['tr-GONE']);
    expect(run.artwork.unpinned, ['tr-GONE']);
  });

  test('a re-mirror frees nothing the server could put back', () async {
    final run = await bind(
      const <CatalogSyncEntry>[],
      held: ['tr-TRASH', 'tr-OTHER'],
    );

    expect(run.downloads.removed, isEmpty);
    expect(run.artwork.unpinned, isEmpty);
  });

  test('reclaims one at a time, so a shared file is never orphaned', () async {
    // `remove` decides whether to unlink by asking whether any *other*
    // row still holds the same essence, so two items sharing one (CUE
    // siblings share an image) reclaimed at once each see the other's
    // row, each conclude the file is shared, and leave it on disk. A
    // delta page that retires a pair delivers both tombstones together,
    // which makes this the ordinary case rather than a race.
    final run = await bind(
      const <CatalogSyncEntry>[
        CatalogSyncEntry(op: 'delete', pid: 'tr-ONE', reason: 'removed'),
        CatalogSyncEntry(op: 'delete', pid: 'tr-TWO', reason: 'removed'),
        CatalogSyncEntry(op: 'delete', pid: 'tr-THREE', reason: 'removed'),
      ],
      held: const ['tr-ONE', 'tr-TWO', 'tr-THREE'],
    );

    expect(run.downloads.removed, hasLength(3));
    expect(run.downloads.peakConcurrentRemovals, 1);
  });

  group('a burst of frees rebuilds the downloads list once', () {
    final gone = [
      for (var i = 0; i < 40; i++) 'tr-GONE${i.toString().padLeft(2, '0')}',
    ];

    /// A device holding every pid of [gone], its catalog cursor at
    /// [since] when set, with the Downloads screen open on them.
    Future<(_Run, _RecordedDownloads)> holding(
      FakeRepository repo, {
      String? since,
    }) async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      for (final pid in gone) {
        await _hold(db, pid);
      }
      if (since != null) {
        await db
            .into(db.syncCursors)
            .insert(SyncCursorsCompanion.insert(catalogSince: Value(since)));
      }
      final counted = _RecordedDownloads(db)
        ..setStored([
          for (final pid in gone)
            DownloadedItem(pid: pid, sizeBytes: 1024, files: 1, complete: true),
        ]);
      final run = launch(db, repo: repo, downloads: counted);
      final screen = run.container.listen(downloadsProvider, (_, _) {});
      addTearDown(screen.close);
      expect(
        (await run.container.read(downloadsProvider.future)).entries,
        hasLength(gone.length),
      );
      expect(counted.listed, 1, reason: "the screen's own build");
      return (run, counted);
    }

    Future<void> expectOneRebuildWithoutThem(
      _Run run,
      _RecordedDownloads counted,
    ) async {
      await pumpEventQueue(times: 400);
      expect(counted.removed, gone);
      expect(await run.engine.pendingFrees(), isEmpty);
      // The screen's own build, the catalog change's (the list draws the
      // mirror's titles), and one more for the frees.
      expect(counted.listed, 3);
      expect(
        (await run.container.read(downloadsProvider.future)).entries,
        isEmpty,
      );
    }

    test('when a re-mirror is told they are gone', () async {
      final repo = FakeRepository()
        ..removedForGood.addAll(gone)
        ..catalogPages.add(
          const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        );
      final (run, counted) = await holding(repo);

      await run.engine.pullCatalog();

      await expectOneRebuildWithoutThem(run, counted);
    });

    test('when one delta page tombstones them', () async {
      final repo = FakeRepository()
        ..catalogPages.add(
          CatalogSyncPage(
            entries: [
              for (final pid in gone)
                CatalogSyncEntry(op: 'delete', pid: pid, reason: 'removed'),
            ],
            nextSince: 'cur-2',
          ),
        );
      final (run, counted) = await holding(repo, since: 'cur-1');

      await run.engine.pullCatalog();

      await expectOneRebuildWithoutThem(run, counted);
    });
  });

  test(
    'a trashed item keeps its download, so a restore costs no transfer',
    () async {
      final run = await bind(
        const <CatalogSyncEntry>[
          CatalogSyncEntry(op: 'delete', pid: 'tr-TRASH', reason: 'hidden'),
          // A server too old to send a reason lands on the same half.
          CatalogSyncEntry(op: 'delete', pid: 'tr-OLD'),
        ],
        held: const ['tr-TRASH', 'tr-OLD'],
      );

      expect(run.downloads.removed, isEmpty);
      expect(run.artwork.unpinned, isEmpty);
    },
  );

  group('a run killed after the commit and before the free', () {
    /// The first run, over a database holding a download and a cover for
    /// `tr-GONE`, up to the commit that drops it and promises its free; the
    /// free is held open for good, which is a kill. [tombstone] says which
    /// commit: a delta's tombstone for an item the mirror had, or a
    /// re-mirror whose answer names a pid the snapshot never listed.
    Future<MirrorDatabase> killed({required bool tombstone}) async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      await _hold(db, 'tr-GONE');
      final repo = FakeRepository();
      if (tombstone) {
        repo.catalogPages.addAll(<CatalogSyncPage>[
          CatalogSyncPage(
            entries: [
              CatalogSyncEntry(
                op: 'upsert',
                pid: 'tr-GONE',
                item: testItem('tr-GONE'),
              ),
            ],
            nextSince: 'cur-1',
          ),
          const CatalogSyncPage(
            entries: [
              CatalogSyncEntry(op: 'delete', pid: 'tr-GONE', reason: 'removed'),
            ],
            nextSince: 'cur-2',
          ),
        ]);
      } else {
        repo
          ..removedForGood.add('tr-GONE')
          ..catalogPages.add(
            const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
          );
      }
      final stuck = _RecordedDownloads(db)..removeGate = Completer<void>();
      final first = launch(db, repo: repo, downloads: stuck);
      await first.engine.pullCatalog();
      if (tombstone) await first.engine.pullCatalog();
      await pumpEventQueue(times: 50);

      expect(stuck.removed, isEmpty, reason: 'the free never got going');
      expect(await first.engine.pendingFrees(), ['tr-GONE']);
      first.end();
      return db;
    }

    /// The next run, which finishes whatever the first left.
    Future<_Run> restart(MirrorDatabase db) async {
      final next = launch(db);
      await pumpEventQueue(times: 50);
      return next;
    }

    for (final (path, isTombstone) in [
      ('a tombstone', true),
      ('a re-mirror', false),
    ]) {
      test('$path: the next start frees the bytes and the cover', () async {
        final db = await killed(tombstone: isTombstone);

        final next = await restart(db);

        expect(next.downloads.removed, ['tr-GONE']);
        expect(next.artwork.unpinned, ['tr-GONE']);
        expect(await next.engine.pendingFrees(), isEmpty);
        expect(await db.select(db.downloadRecords).get(), isEmpty);
        expect(await db.select(db.artworkPins).get(), isEmpty);
      });

      test('$path: a pid the mirror lists again by then is kept', () async {
        final db = await killed(tombstone: isTombstone);
        // Back in the mirror before the restart.
        await db
            .into(db.mirrorItems)
            .insert(
              MirrorItemsCompanion.insert(
                pid: 'tr-GONE',
                ulid: 'GONE',
                mediaType: 'music',
                title: 'Back Again',
                durationMs: 1000,
                sortKey: 'back again',
              ),
            );

        final next = await restart(db);

        expect(next.downloads.removed, isEmpty);
        expect(next.artwork.unpinned, isEmpty);
        expect(await db.select(db.downloadRecords).get(), hasLength(1));
        expect(await db.select(db.artworkPins).get(), hasLength(1));
        expect(await next.engine.pendingFrees(), isEmpty);
      });

      test('$path: a cover pinned after the commit is kept, and the rest '
          'goes', () async {
        final db = await killed(tombstone: isTombstone);
        await db
            .into(db.artworkPins)
            .insert(
              ArtworkPinsCompanion.insert(
                pid: 'tr-GONE',
                sizePx: 600,
                artUrl: '/media/art?pid=tr-GONE&size=600',
                etag: 'b',
                localPath: '/art/tr-GONE-600.jpg',
                sizeBytes: 4096,
                pinnedAt: DateTime.utc(2026, 10, 2),
              ),
            );

        final next = await restart(db);

        expect(next.downloads.removed, ['tr-GONE']);
        expect(next.artwork.unpinnedExactly['tr-GONE']!.map((p) => p.sizePx), [
          300,
        ], reason: 'the free is told of the cover the commit found, no other');
        expect((await db.select(db.artworkPins).get()).map((p) => p.sizePx), [
          600,
        ]);
        expect(await db.select(db.downloadRecords).get(), isEmpty);
        expect(await next.engine.pendingFrees(), isEmpty);
      });

      test('$path: a file taken up after the commit is kept', () async {
        final db = await killed(tombstone: isTombstone);
        await db
            .into(db.downloadRecords)
            .insert(
              DownloadRecordsCompanion.insert(
                pid: 'tr-GONE',
                fileIndex: 3,
                essenceHash: 'again',
                etag: '1-2',
                fileName: 'again.flac',
                localPath: '/downloads/again.flac',
                sizeBytes: 1024,
                state: 'complete',
              ),
            );

        final next = await restart(db);

        expect(next.downloads.removed, isEmpty);
        expect(await db.select(db.downloadRecords).get(), hasLength(2));
        expect(await next.engine.pendingFrees(), isEmpty);
      });
    }

    test('frees owed at start rebuild the downloads list once, after the '
        'last of them', () async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      const owed = ['tr-ONE', 'tr-THREE', 'tr-TWO'];
      for (final pid in owed) {
        await _hold(db, pid);
      }
      final repo = FakeRepository()
        ..removedForGood.addAll(owed)
        ..catalogPages.add(
          const CatalogSyncPage(entries: [], nextSince: 'cur-1'),
        );
      final stuck = _RecordedDownloads(db)..removeGate = Completer<void>();
      final first = launch(db, repo: repo, downloads: stuck);
      await first.engine.pullCatalog();
      await pumpEventQueue(times: 50);
      expect(await first.engine.pendingFrees(), owed);
      first.end();

      final counted = _RecordedDownloads(db);
      final next = launch(db, downloads: counted);
      // Open, as the Downloads screen holds it.
      final screen = next.container.listen(downloadsProvider, (_, _) {});
      addTearDown(screen.close);
      int? freedBeforeSync;
      unawaited(
        next.engine.beforeSync(() async {
          freedBeforeSync = counted.removed.length;
        }),
      );
      await pumpEventQueue(times: 100);

      expect(counted.removed, owed);
      expect(freedBeforeSync, owed.length, reason: 'the drain goes first');
      expect(await next.engine.pendingFrees(), isEmpty);
      // The screen's own build, and one more for the three frees.
      expect(counted.listed, 2);
    });

    test('the free finishes ahead of whatever the engine does next', () async {
      final db = await killed(tombstone: true);
      final slow = _RecordedDownloads(db)..removeGate = Completer<void>();
      final next = launch(db, downloads: slow);
      var after = false;
      unawaited(next.engine.beforeSync(() async => after = true));

      await pumpEventQueue(times: 50);
      expect(after, isFalse, reason: 'the free is still going');

      slow.removeGate!.complete();
      await pumpEventQueue(times: 50);
      expect(slow.removed, ['tr-GONE']);
      expect(after, isTrue);
    });

    test(
      'a free that fails stays owed, and a later start finishes it',
      () async {
        final db = await killed(tombstone: true);
        final failing = _RecordedDownloads(db)
          ..removeError = StateError('the disk is gone');
        final second = launch(db, downloads: failing);
        await pumpEventQueue(times: 50);

        expect(failing.removed, isEmpty);
        expect(await second.engine.pendingFrees(), ['tr-GONE']);
        second.end();

        final third = await restart(db);

        expect(third.downloads.removed, ['tr-GONE']);
        expect(await third.engine.pendingFrees(), isEmpty);
      },
    );
  });
}
