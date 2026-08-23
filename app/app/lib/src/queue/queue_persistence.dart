import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
// The mirror's own generated `QueueEntry` row class collides with the
// queue's; this file speaks about both, and the queue's is the one it
// builds.
import 'package:waxdeck_data/waxdeck_data.dart' hide QueueEntry;

import '../player/now_playing_controller.dart';
import '../providers.dart';
import '../settings/client_settings_providers.dart';
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
    this.sessionId,
  });

  final QueueState queue;
  final DateTime savedAt;

  /// The entry that would resume, when the catalog mirror knows it.
  /// Absent offline for an item that never synced, which is a missing
  /// title on the offer, not a reason to withhold it.
  final ItemSummary? currentItem;

  /// The ended server session this came from, when it did not come off
  /// the disk. What declining it has to remember, since there is no
  /// local snapshot to clear.
  final String? sessionId;

  int get length => queue.length;
}

/// What kind of thing an API pid names, from its type prefix.
///
/// Music is the fallback rather than an error: an unknown prefix is a
/// newer server, and drawing a square cover for it is a better answer
/// than refusing to draw the row.
MediaType mediaTypeOfPid(String pid) => switch (pid.split('-').first) {
  'ep' => MediaType.podcast,
  'bk' => MediaType.audiobook,
  _ => MediaType.music,
};

/// Builds a local queue out of an ended server session.
///
/// The provenance stays unknown: the server records what was playing,
/// not what it was built from, and captioning a restored queue with an
/// endpoint name would answer a different question than "playing from".
QueueState queueFromSession(PlaybackSessionHistoryEntry session) {
  final entries = <QueueEntry>[
    for (var i = 0; i < session.entries.length; i++)
      QueueEntry(queueId: '$kQueueIdPrefix$i', pid: session.entries[i].pid),
  ];
  return QueueState(
    entries: entries,
    sourceOrder: [for (final e in entries) e.queueId],
    currentIndex: entries.isEmpty
        ? 0
        : session.index.clamp(0, entries.length - 1),
    shuffled: session.shuffle,
    repeat: QueueRepeat.fromWire(session.repeat ?? ''),
    source: QueueSource.none,
    nextQueueId: entries.length,
  );
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
    final offer = stored == null || stored.entries.isEmpty
        ? await _fromServer()
        : await _fromDisk(stored, db);
    // Checked again on the way out: a queue that started while the disk
    // and the server were being read would have its retirement
    // overwritten by the offer this build is about to return.
    if (ref.read(queueControllerProvider).isNotEmpty) return null;
    return offer;
  }

  Future<RestorableQueue> _fromDisk(
    StoredQueue stored,
    MirrorDatabase? db,
  ) async {
    final queue = QueueState.fromStored(stored);
    final pid = queue.currentPid;
    final item = db == null || pid == null
        ? null
        : await mirrorItemByPid(db, pid);
    return RestorableQueue(
      queue: queue,
      savedAt: stored.updatedAt,
      currentItem: item,
    );
  }

  /// What the account was last playing anywhere, for the launches with
  /// nothing on the disk: the web build, which keeps no mirror, and a
  /// fresh install of a native one. The server keeps a few ended
  /// sessions per user and this offers the newest.
  ///
  /// Never throws. A launch offline, or against a server that does not
  /// serve this yet, is a launch with nothing to offer - not a failed
  /// one, and certainly not a deck bar stuck on an error.
  Future<RestorableQueue?> _fromServer() async {
    // Together: what the server was playing and whether this device
    // already said no to it are independent facts, and the deck bar
    // waits on the whole of this. Asked in turn, a launch on the web
    // build spent a local read's worth of nothing before the round trip
    // it actually needed.
    final (sessions, declinedThrough) = await (
      _sessionHistory(),
      // The store promises never to throw and this does not rely on
      // being lucky about it: the whole cost of losing here is an offer
      // that comes back after it was declined, which is not worth
      // failing a launch for.
      ref
          .read(clientSettingsStoreProvider)
          .read(ClientSettingKeys.resumeDeclinedThrough)
          .catchError((Object _) => null),
    ).wait;
    if (sessions == null) return null;
    final declined = DateTime.tryParse(declinedThrough ?? '');
    for (final session in sessions) {
      if (session.entries.isEmpty) continue;
      if (declined != null && !session.positionAt.isAfter(declined)) continue;
      final current = session.currentEntry;
      return RestorableQueue(
        queue: queueFromSession(session),
        savedAt: session.positionAt,
        sessionId: session.id,
        currentItem: current == null ? null : await _offeredItem(current),
      );
    }
    return null;
  }

  /// The account's recent server-side sessions, or null where they
  /// could not be asked for. A launch offline, or against a server that
  /// does not serve this yet, is a launch with nothing to offer.
  Future<List<PlaybackSessionHistoryEntry>?> _sessionHistory() async {
    try {
      return await ref.read(repositoryProvider).listPlaybackSessionHistory();
    } on Object catch (error) {
      debugPrint('session history unavailable: $error');
      return null;
    }
  }

  /// The full summary for the entry a server-side session was left on.
  ///
  /// A session entry is the wire's own record of what played - a pid, a
  /// title, an artist - and it carries no artwork and no media type.
  /// Built from that alone, the offer drew a monogram where the cover
  /// belongs and guessed the shape from the pid, so coming back to a
  /// session looked nothing like leaving it. One read per launch fixes
  /// both, and it is the item already on screen when the offer is
  /// accepted, so the fetch is one the next frame would make anyway.
  ///
  /// Falls back to the entry's own fields rather than to nothing: the
  /// item may have been deleted while the account was away, and an
  /// offer that names what it was playing beats no offer at all.
  Future<ItemSummary> _offeredItem(PlaybackSessionEntry entry) async {
    final inline = ItemSummary(
      pid: entry.pid,
      // A session entry carries no media type; the pid says it, since
      // every API pid is a type prefix in front of a ULID. It decides
      // the offer's artwork shape and glyph, so a book offered as a
      // track would be the wrong shape on the bar.
      mediaType: mediaTypeOfPid(entry.pid),
      title: entry.title,
      artist: entry.artist,
      durationMs: entry.durationMs ?? 0,
    );
    try {
      return await ref.read(repositoryProvider).getItem(entry.pid);
    } on Object catch (error) {
      debugPrint('offered item ${entry.pid} unavailable: $error');
      return inline;
    }
  }

  /// Puts the restored queue back in play. Through the playback layer,
  /// which loads the current entry paused at its checkpoint: accepting
  /// the offer is "put it back", and the transport is right there for
  /// the rest.
  void accept() {
    final offer = state.value;
    if (offer == null) return;
    ref.read(nowPlayingProvider.notifier).restore(offer.queue);
    state = const AsyncData(null);
  }

  /// Turns the offer down, and forgets the queue so it is not offered
  /// again at every launch.
  ///
  /// Two things to forget, because the offer comes from two places. A
  /// queue off the disk is cleared. A session off the server is not
  /// this client's to delete - it is the account's history, and another
  /// device may still want it - so declining it is recorded here
  /// instead, per device, which is the scope the decision has.
  ///
  /// The forgetting is attempted first, so a failure to write is a
  /// logged failure rather than an offer that looks declined and comes
  /// back next launch with no explanation. It never throws: this hangs
  /// off a button.
  Future<void> dismiss() async {
    final offer = state.value;
    if (offer?.sessionId == null) {
      await ref
          .read(queueStoreProvider)
          .clear()
          .catchError(QueuePersister._writeFailed);
    } else {
      await ref
          .read(clientSettingsStoreProvider)
          .write(
            ClientSettingKeys.resumeDeclinedThrough,
            offer!.savedAt.toUtc().toIso8601String(),
          )
          // Guarded like the disk branch, and for the same reason: this
          // hangs off a button, and a write that threw would skip the
          // retirement below and leave the offer standing with an
          // uncaught error behind it.
          .catchError(QueuePersister._writeFailed);
    }
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
