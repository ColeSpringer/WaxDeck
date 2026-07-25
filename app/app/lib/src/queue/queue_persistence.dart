import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

import '../sync/sync_providers.dart';
import 'queue_controller.dart';
import 'queue_state.dart';

/// Where the queue persists. Native builds write it to the local
/// mirror; the web build has no mirror and offers the server's most
/// recent session at launch instead.
final queueStoreProvider = Provider<QueueStore>((ref) {
  final db = ref.watch(mirrorDatabaseProvider);
  return db == null ? const NoQueueStore() : DriftQueueStore(db);
});

/// How long a run of queue edits settles before it is written. A drag
/// reorder emits a state per frame; a write per frame would put the
/// queue tables in the way of the gesture.
const Duration kQueueSaveDebounce = Duration(milliseconds: 750);

/// Overridden in tests, which cannot wait out the real debounce.
final queueSaveDebounceProvider = Provider<Duration>(
  (ref) => kQueueSaveDebounce,
);

/// Writes the queue as it changes, coalescing a run of edits into one
/// write.
///
/// Emptiness is not written until the queue has held something in this
/// session: a launch starts on an empty queue, and saving that would
/// throw away the queue the launch is about to offer to restore.
class QueuePersister {
  QueuePersister({
    required this.store,
    required this.debounce,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final QueueStore store;
  final Duration debounce;
  final DateTime Function() _now;

  Timer? _timer;
  QueueState? _pending;
  bool _sawEntries = false;
  bool _disposed = false;

  /// Queues [state] to be written once the edits stop.
  void onChanged(QueueState state) {
    if (_disposed) return;
    if (state.isNotEmpty) _sawEntries = true;
    if (state.isEmpty && !_sawEntries) return;
    _pending = state;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush().catchError(_writeFailed));
    });
  }

  /// A queue that cannot be written is a queue that is not offered next
  /// launch, which is not worth taking the app down for: the snapshot is
  /// written whole every time, so the next edit carries whatever this
  /// write lost. It has no other symptom, though, so the console gets
  /// the reason (a locked database, a full disk) rather than nothing.
  static void _writeFailed(Object error) {
    debugPrint('queue write failed: $error');
  }

  /// Writes whatever is pending now. Called on the way out (app
  /// shutdown, sign-out) so a queue edited seconds before does not
  /// vanish with the process.
  ///
  /// Deliberately still writes after [dispose]: the provider flushes on
  /// its way out, and refusing there would drop the last edit of every
  /// session.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final state = _pending;
    if (state == null) return;
    _pending = null;
    if (state.isEmpty) {
      await store.clear();
      return;
    }
    await store.save(state.toStored(updatedAt: _now()));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Binds queue persistence to the session: watched by the signed-in
/// scope, so writes stop and the last edit lands when the session ends.
final queuePersistenceProvider = Provider.autoDispose<QueuePersister>((ref) {
  final persister = QueuePersister(
    store: ref.watch(queueStoreProvider),
    debounce: ref.watch(queueSaveDebounceProvider),
  );
  // Fired immediately as well as on change: this provider is scoped to
  // the session while the queue outlives it, so a queue already playing
  // when the binder mounts (or remounts, if the store or the debounce
  // changed under it) would otherwise go unwritten until its next edit.
  ref.listen(
    queueControllerProvider,
    (_, next) => persister.onChanged(next),
    fireImmediately: true,
  );
  ref.onDispose(() {
    // The pending write survives the provider: flush first, dispose
    // after, or the last edit before a sign-out is the one that is lost.
    unawaited(persister.flush().catchError(QueuePersister._writeFailed));
    persister.dispose();
  });
  return persister;
});

/// A queue found at launch, with enough about it to make the offer
/// concrete ("Resume Kind of Blue") rather than a bare prompt.
class RestorableQueue {
  const RestorableQueue({
    required this.queue,
    required this.savedAt,
    this.currentItem,
  });

  final QueueState queue;
  final DateTime savedAt;

  /// The entry that would resume, when the catalog mirror knows it.
  /// Absent offline for an item that never synced, which is a missing
  /// title on the offer, not a reason to withhold it.
  final ItemSummary? currentItem;

  int get length => queue.length;
}

/// What a launch found to resume, or null when there is nothing to
/// offer. Read by the deck bar's restore affordance.
///
/// The position is deliberately not part of this: the checkpointed play
/// state already knows where the item stands, and a second copy could
/// only disagree with it.
class QueueRestoreController extends AsyncNotifier<RestorableQueue?> {
  @override
  Future<RestorableQueue?> build() async {
    // Both reads happen before the first await: watching across one is
    // fragile, and the store and the database have to be the pair the
    // same launch resolved (in a native build the store is built over
    // this very database).
    final store = ref.watch(queueStoreProvider);
    final db = ref.watch(mirrorDatabaseProvider);

    // An offer is only ever about a queue that is not playing. Anything
    // that starts one retires it, or the affordance sits there waiting
    // to replace live playback with a snapshot of what came before it.
    if (ref.read(queueControllerProvider).isNotEmpty) return null;
    ref.listen(queueControllerProvider, (_, next) {
      if (next.isNotEmpty) state = const AsyncData(null);
    });

    final stored = await store.load();
    if (stored == null || stored.entries.isEmpty) return null;
    final queue = QueueState.fromStored(stored);
    final pid = queue.currentPid;
    final item = db == null || pid == null
        ? null
        : await mirrorItemByPid(db, pid);
    // Checked again on the way out: a queue that started while the disk
    // was being read would have its retirement overwritten by the offer
    // this build is about to return.
    if (ref.read(queueControllerProvider).isNotEmpty) return null;
    return RestorableQueue(
      queue: queue,
      savedAt: stored.updatedAt,
      currentItem: item,
    );
  }

  /// Puts the restored queue back in play. The playback layer picks the
  /// current entry up from there, paused at its checkpoint.
  void accept() {
    final offer = state.value;
    if (offer == null) return;
    ref.read(queueControllerProvider.notifier).restore(offer.queue);
    state = const AsyncData(null);
  }

  /// Turns the offer down, and forgets the queue so it is not offered
  /// again at every launch.
  ///
  /// The forgetting is attempted first, so a failure to write is a
  /// logged failure rather than an offer that looks declined and comes
  /// back next launch with no explanation. It never throws: this hangs
  /// off a button.
  Future<void> dismiss() async {
    await ref
        .read(queueStoreProvider)
        .clear()
        .catchError(QueuePersister._writeFailed);
    state = const AsyncData(null);
  }
}

final queueRestoreProvider =
    AsyncNotifierProvider<QueueRestoreController, RestorableQueue?>(
      QueueRestoreController.new,
    );

/// Everything the queue leaves behind when a session ends: the live
/// queue with the standing preferences that were the departing
/// listener's, what was written for the next launch, and the offer that
/// would have made it. The auth controller decides when a session ends;
/// what that costs the queue is the queue's own business.
///
/// Deliberately not hung off [queuePersistenceProvider]'s disposal: a
/// provider is disposed for reasons that are not a sign-out (a rebuild
/// when the store or the debounce changes), and forgetting a listener's
/// queue on one of those would be a data loss with no cause.
///
/// Never throws. A store that will not clear is a stale offer at the
/// next launch, which is not a reason to leave the session standing.
Future<void> forgetQueueOnSignOut(Ref ref) async {
  ref.read(queueControllerProvider.notifier).reset();
  await ref
      .read(queueStoreProvider)
      .clear()
      .catchError(QueuePersister._writeFailed);
  ref.invalidate(queueRestoreProvider);
}
