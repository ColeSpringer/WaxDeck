import 'package:drift/drift.dart';

import 'database.dart';

/// One persisted queue entry. [sourceRank] is the entry's place in the
/// order the queue was built in; the list order is the play order.
class StoredQueueEntry {
  const StoredQueueEntry({
    required this.queueId,
    required this.pid,
    required this.sourceRank,
  });

  final String queueId;
  final String pid;
  final int sourceRank;
}

/// A queue as it survives a restart: ordered pids, where the listener
/// was in them, and what they were built from. Deliberately no titles
/// or artwork (the catalog mirror is the one catalog truth) and no
/// position (the checkpointed play state is the one position truth).
class StoredQueue {
  const StoredQueue({
    required this.entries,
    required this.currentIndex,
    required this.shuffled,
    required this.repeat,
    required this.sourceKind,
    required this.sourceLabel,
    required this.nextQueueId,
    required this.updatedAt,
    this.sourcePid,
    this.sourceRolling = false,
    this.sourceCursor = '',
  });

  final List<StoredQueueEntry> entries;
  final int currentIndex;
  final bool shuffled;
  final String repeat;
  final String sourceKind;
  final String sourceLabel;
  final String? sourcePid;
  final bool sourceRolling;

  /// Where the source's own listing stood when this window was cut, so a
  /// window that drains can ask for more instead of ending at the cap.
  /// Opaque - the server shapes its cursors and this only carries them.
  ///
  /// Round-tripped here but not yet filled: nothing on the queue side
  /// pages a source, so [QueueState] has no cursor to hand over and the
  /// empty string is the honest answer. The plumbing is what stops the
  /// column from being a trap for whoever builds the refill - a `save`
  /// that omitted it would quietly reset the stored cursor on every
  /// write, and no test would have said so.
  final String sourceCursor;

  final int nextQueueId;
  final DateTime updatedAt;
}

/// Where the local queue persists between launches.
abstract class QueueStore {
  /// The last saved queue, or null when nothing was saved (or the
  /// platform does not persist queues).
  Future<StoredQueue?> load();

  /// Replaces the saved queue wholesale. Callers debounce; this writes
  /// what it is given.
  Future<void> save(StoredQueue queue);

  /// Forgets the saved queue, so the next launch offers nothing.
  Future<void> clear();
}

/// The queue store over the local mirror database (native builds).
class DriftQueueStore implements QueueStore {
  DriftQueueStore(this.db);

  final MirrorDatabase db;

  @override
  Future<StoredQueue?> load() async {
    final meta = await db.select(db.queueMeta).getSingleOrNull();
    if (meta == null) return null;
    final rows = await (db.select(
      db.queueEntries,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    if (rows.isEmpty) return null;
    return StoredQueue(
      entries: [
        for (final r in rows)
          StoredQueueEntry(
            queueId: r.queueId,
            pid: r.pid,
            sourceRank: r.sourceRank,
          ),
      ],
      // A meta row that outlived its entries (a torn write, an older
      // build) must not restore an index past the end.
      currentIndex: meta.currentIndex.clamp(0, rows.length - 1),
      shuffled: meta.shuffled,
      repeat: meta.repeat,
      sourceKind: meta.sourceKind,
      sourceLabel: meta.sourceLabel,
      sourcePid: meta.sourcePid,
      sourceRolling: meta.sourceRolling,
      sourceCursor: meta.sourceCursor,
      nextQueueId: meta.nextQueueId,
      updatedAt: meta.updatedAt,
    );
  }

  /// One transaction: a crash mid-save leaves the previous queue whole
  /// rather than a half-rewritten one.
  @override
  Future<void> save(StoredQueue queue) {
    return db.transaction(() async {
      await db.delete(db.queueEntries).go();
      await db.batch((b) {
        b.insertAll(db.queueEntries, [
          for (var i = 0; i < queue.entries.length; i++)
            QueueEntriesCompanion.insert(
              queueId: queue.entries[i].queueId,
              pid: queue.entries[i].pid,
              position: i,
              sourceRank: queue.entries[i].sourceRank,
            ),
        ]);
      });
      await db
          .into(db.queueMeta)
          .insertOnConflictUpdate(
            QueueMetaCompanion.insert(
              id: const Value(1),
              currentIndex: Value(queue.currentIndex),
              shuffled: Value(queue.shuffled),
              repeat: Value(queue.repeat),
              sourceKind: Value(queue.sourceKind),
              sourceLabel: Value(queue.sourceLabel),
              sourcePid: Value(queue.sourcePid),
              sourceRolling: Value(queue.sourceRolling),
              sourceCursor: Value(queue.sourceCursor),
              nextQueueId: Value(queue.nextQueueId),
              updatedAt: queue.updatedAt,
            ),
          );
    });
  }

  @override
  Future<void> clear() {
    return db.transaction(() async {
      await db.delete(db.queueEntries).go();
      await db.delete(db.queueMeta).go();
    });
  }
}

/// The queue store where nothing persists: the web build, which has no
/// local mirror and offers the server's most recent session instead,
/// and tests that do not care.
class NoQueueStore implements QueueStore {
  const NoQueueStore();

  @override
  Future<StoredQueue?> load() async => null;

  @override
  Future<void> save(StoredQueue queue) async {}

  @override
  Future<void> clear() async {}
}
