import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_persistence.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _album = QueueSource(
  kind: QueueSourceKind.album,
  label: 'Kind of Blue',
  pid: 'al-1',
);

/// A store that records what it was asked to do, so a test can tell one
/// coalesced write from three, and can refuse to write at all.
class RecordingQueueStore implements QueueStore {
  StoredQueue? saved;
  int saves = 0;
  int clears = 0;

  /// Stands in for a locked database or a full disk.
  bool failClears = false;

  @override
  Future<StoredQueue?> load() async => saved;

  @override
  Future<void> save(StoredQueue queue) async {
    saved = queue;
    saves++;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (failClears) throw StateError('database is locked');
    saved = null;
  }
}

StoredQueue _storedTrack() => StoredQueue(
  entries: const [StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0)],
  currentIndex: 0,
  shuffled: false,
  repeat: 'off',
  sourceKind: 'album',
  sourceLabel: 'Kind of Blue',
  nextQueueId: 1,
  updatedAt: DateTime.utc(2026, 7, 25),
);

const _tick = Duration(milliseconds: 5);

Future<void> _settle() => Future<void>.delayed(_tick * 4);

ProviderContainer _container(RecordingQueueStore store, {MirrorDatabase? db}) {
  final container = ProviderContainer(
    overrides: [
      queueStoreProvider.overrideWithValue(store),
      queueSaveDebounceProvider.overrideWithValue(_tick),
      repositoryProvider.overrideWithValue(
        FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]),
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      // Accepting a restore offer hands the queue to playback, which
      // reaches for the engine: without this the real one is built and
      // asks for a platform binding no unit test has.
      audioEngineProvider.overrideWithValue(FakeEngine()),
      if (db != null) mirrorDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Mounts the persister the way the signed-in scope does: watched, so
/// it lives as long as the session rather than as long as one read.
QueuePersister _bind(ProviderContainer container) {
  final keepAlive = container.listen(queuePersistenceProvider, (_, _) {});
  addTearDown(keepAlive.close);
  return container.read(queuePersistenceProvider);
}

void main() {
  group('persisting', () {
    test('a run of edits settles into one write', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      _bind(container);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(['tr-A', 'tr-B', 'tr-C'], source: _album);
      queue.reorder(2, 0);
      queue.reorder(2, 1);
      expect(store.saves, 0);

      await _settle();
      expect(store.saves, 1);
      expect(
        [for (final e in store.saved!.entries) e.pid],
        ['tr-C', 'tr-B', 'tr-A'],
      );
      expect(store.saved!.sourceKind, 'album');
      expect(store.saved!.sourceLabel, 'Kind of Blue');
    });

    test('the empty queue a launch starts on is not written', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      _bind(container);
      final queue = container.read(queueControllerProvider.notifier);

      // Standing preferences can change before anything is queued; none
      // of that may erase the queue the launch is about to offer.
      queue.setRepeat(QueueRepeat.all);
      queue.setShuffle(true);
      await _settle();

      expect(store.saves, 0);
      expect(store.clears, 0);
    });

    test('emptying a queue that held something forgets it', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      _bind(container);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(['tr-A'], source: _album);
      await _settle();
      expect(store.saves, 1);

      queue.clear();
      await _settle();
      expect(store.clears, 1);
      expect(store.saved, isNull);
    });

    test('a pending write lands when the session ends', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      final persister = _bind(container);
      final queue = container.read(queueControllerProvider.notifier);

      queue.playNow(['tr-A'], source: _album);
      await persister.flush();

      expect(store.saves, 1);
      expect(store.saved!.entries.single.pid, 'tr-A');
    });

    test('signing out leaves nothing for the next account', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      _bind(container);
      final queue = container.read(queueControllerProvider.notifier);
      queue.playNow(['tr-A'], source: _album);
      queue.setRepeat(QueueRepeat.all);
      queue.setShuffle(true);
      await _settle();
      expect(store.saved, isNotNull);

      await container.read(authControllerProvider.notifier).signOutLocally();

      expect(container.read(queueControllerProvider).isEmpty, isTrue);
      expect(await store.load(), isNull);
      // Repeat and shuffle were the departing listener's preferences,
      // not the install's.
      expect(container.read(queueControllerProvider).repeat, QueueRepeat.off);
      expect(container.read(queueControllerProvider).shuffled, isFalse);
      // The queue is empty again, so an offer is free to build: it has
      // to find nothing, or the next account is asked whether to resume
      // an album it has never heard.
      expect(await container.read(queueRestoreProvider.future), isNull);
    });

    test('a store that will not clear cannot strand the sign-out', () async {
      final store = RecordingQueueStore()..failClears = true;
      final container = _container(store);
      _bind(container);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-A',
      ], source: _album);
      await _settle();

      await container.read(authControllerProvider.notifier).signOutLocally();

      // The session is what matters: a queue left on disk is a stale
      // offer, a session left signed in is a dead credential the UI
      // keeps using.
      expect(
        container.read(authControllerProvider).value!.authenticated,
        isFalse,
      );
      expect(container.read(queueControllerProvider).isEmpty, isTrue);
    });

    test('a queue already playing when the binder mounts is written', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      // Queued before anything binds persistence: a Connect load, a
      // deep link, a restore accepted while the shell was mounting.
      container.read(queueControllerProvider.notifier).playNow([
        'tr-A',
      ], source: _album);

      _bind(container);
      await _settle();

      expect(store.saved!.entries.single.pid, 'tr-A');
    });

    test('a flush with nothing pending writes nothing', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      final persister = _bind(container);

      await persister.flush();
      expect(store.saves, 0);
      expect(store.clears, 0);
    });
  });

  group('restoring', () {
    test('nothing saved offers nothing', () async {
      final container = _container(RecordingQueueStore());

      expect(await container.read(queueRestoreProvider.future), isNull);
    });

    test('a saved queue comes back as an offer', () async {
      final store = RecordingQueueStore();
      final container = _container(store);
      _bind(container);
      final queue = container.read(queueControllerProvider.notifier);
      queue.playNow(['tr-A', 'tr-B', 'tr-C'], source: _album, startIndex: 1);
      queue.setRepeat(QueueRepeat.all);
      await _settle();

      // A fresh launch over the same store.
      final relaunch = _container(store);
      final offer = await relaunch.read(queueRestoreProvider.future);

      expect(offer, isNotNull);
      expect(offer!.length, 3);
      expect(offer.queue.currentPid, 'tr-B');
      expect(offer.queue.repeat, QueueRepeat.all);
      expect(offer.queue.source.label, 'Kind of Blue');
      expect(offer.currentItem, isNull);
    });

    test('the offer names the item when the mirror knows it', () async {
      final db = inMemoryMirrorDatabase();
      addTearDown(db.close);
      await db
          .into(db.mirrorItems)
          .insert(
            MirrorItemsCompanion.insert(
              pid: 'tr-A',
              ulid: 'A',
              mediaType: 'music',
              title: 'So What',
              durationMs: 545000,
              sortKey: 'so what',
            ),
          );
      final store = RecordingQueueStore()
        ..saved = StoredQueue(
          entries: const [
            StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
          ],
          currentIndex: 0,
          shuffled: false,
          repeat: 'off',
          sourceKind: 'album',
          sourceLabel: 'Kind of Blue',
          nextQueueId: 1,
          updatedAt: DateTime.utc(2026, 7, 25),
        );

      final offer = await _container(
        store,
        db: db,
      ).read(queueRestoreProvider.future);

      expect(offer!.currentItem!.title, 'So What');
      expect(offer.savedAt, DateTime.utc(2026, 7, 25));
    });

    test('accepting puts the queue back and retires the offer', () async {
      final store = RecordingQueueStore()
        ..saved = StoredQueue(
          entries: const [
            StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 1),
            StoredQueueEntry(queueId: 'q1', pid: 'tr-B', sourceRank: 0),
          ],
          currentIndex: 1,
          shuffled: true,
          repeat: 'one',
          sourceKind: 'playlist',
          sourceLabel: 'Roadtrip',
          nextQueueId: 2,
          updatedAt: DateTime.utc(2026, 7, 25),
        );
      final container = _container(store);
      await container.read(queueRestoreProvider.future);

      container.read(queueRestoreProvider.notifier).accept();

      final queue = container.read(queueControllerProvider);
      expect(queue.pids, ['tr-A', 'tr-B']);
      expect(queue.currentPid, 'tr-B');
      expect(queue.shuffled, isTrue);
      expect(queue.repeat, QueueRepeat.one);
      expect(queue.source.kind, QueueSourceKind.playlist);
      expect(container.read(queueRestoreProvider).value, isNull);
    });

    test('starting to play retires the offer', () async {
      final store = RecordingQueueStore()..saved = _storedTrack();
      final container = _container(store);
      _bind(container);
      expect(await container.read(queueRestoreProvider.future), isNotNull);

      // The listener ignores the offer and taps something else.
      container.read(queueControllerProvider.notifier).playNow([
        'tr-B',
      ], source: _album);
      await _settle();

      // Accepting now would replace live playback with a snapshot of
      // what came before it, so there is nothing left to accept.
      expect(container.read(queueRestoreProvider).value, isNull);
      container.read(queueRestoreProvider.notifier).accept();
      expect(container.read(queueControllerProvider).pids, ['tr-B']);
    });

    test('a queue already playing is never offered one', () async {
      final store = RecordingQueueStore()..saved = _storedTrack();
      final container = _container(store);
      container.read(queueControllerProvider.notifier).playNow([
        'tr-B',
      ], source: _album);

      expect(await container.read(queueRestoreProvider.future), isNull);
    });

    test('an offer that cannot be forgotten is still turned down', () async {
      final store = RecordingQueueStore()
        ..saved = _storedTrack()
        ..failClears = true;
      final container = _container(store);
      await container.read(queueRestoreProvider.future);

      await container.read(queueRestoreProvider.notifier).dismiss();

      expect(container.read(queueRestoreProvider).value, isNull);
    });

    test('turning the offer down forgets the queue for good', () async {
      final store = RecordingQueueStore()
        ..saved = StoredQueue(
          entries: const [
            StoredQueueEntry(queueId: 'q0', pid: 'tr-A', sourceRank: 0),
          ],
          currentIndex: 0,
          shuffled: false,
          repeat: 'off',
          sourceKind: 'album',
          sourceLabel: 'Kind of Blue',
          nextQueueId: 1,
          updatedAt: DateTime.utc(2026, 7, 25),
        );
      final container = _container(store);
      await container.read(queueRestoreProvider.future);

      await container.read(queueRestoreProvider.notifier).dismiss();

      expect(store.clears, 1);
      expect(await store.load(), isNull);
      expect(container.read(queueControllerProvider).isEmpty, isTrue);
    });
  });
}
