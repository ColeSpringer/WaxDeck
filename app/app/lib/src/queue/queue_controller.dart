import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'queue_state.dart';

/// What an [QueueController.advance] did, so the caller knows whether to
/// load an item, restart the current one, or stop.
enum QueueAdvance {
  /// The current entry moved on; load it.
  advanced,

  /// Repeat-one: nothing moved, seek to zero and play again.
  repeatedCurrent,

  /// The queue ran out. The current entry stays where it is, so the
  /// deck bar keeps showing what just finished.
  ended,

  /// Nothing was queued.
  empty,
}

/// What a [QueueController.retreat] did.
enum QueueRetreat {
  /// The current entry moved back; load it.
  moved,

  /// Already at the front with nowhere to wrap to: restart the current
  /// entry instead.
  atStart,

  /// Nothing was queued.
  empty,
}

/// The randomness shuffle draws on. Overridden with a seeded [Random] in
/// tests, so a shuffled queue is an assertable order rather than a
/// property test.
final queueRandomProvider = Provider<Random>((ref) => Random());

/// The local play queue: an ordered list of items, where the listener is
/// in it, and what it was built from.
///
/// A pure state machine. It owns no engine, mints no network calls, and
/// answers no questions about what is playing: it says what the queue
/// is, and the playback layer above it reacts to the current entry
/// changing. Persistence rides alongside (see `queue_persistence.dart`)
/// rather than living here, so the operations stay synchronous and the
/// tests stay about queue semantics.
class QueueController extends Notifier<QueueState> {
  late final Random _random = ref.read(queueRandomProvider);

  @override
  QueueState build() => QueueState.empty;

  /// Replaces the queue with [pids], starting at [startIndex], and
  /// remembers what it displaced so [undoReplace] can put it back.
  /// [replacedPositionMs] is where the displaced queue stood, which the
  /// caller knows and this layer does not.
  ///
  /// [shuffle] is the "Shuffle" entry point: it turns the standing
  /// preference on and draws from anywhere in [pids], so [startIndex] no
  /// longer means anything. Without it the standing preference still
  /// applies, the way a shuffle toggle does everywhere: the entry at
  /// [startIndex] plays, and what follows it is shuffled.
  ///
  /// Either way the queue remembers the order it arrived in, so turning
  /// shuffle off puts the album back in album order.
  ///
  /// Lists longer than [kQueueCap] are windowed rather than refused: in
  /// order the window starts at [startIndex] so everything asked for
  /// plays in sequence (backing up only when the tail is shorter than
  /// the cap); shuffled it is a random draw from the whole list.
  void playNow(
    List<String> pids, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int replacedPositionMs = 0,
  }) {
    if (pids.isEmpty) {
      clear();
      return;
    }
    final displaced = state.isNotEmpty
        ? QueueUndo(
            queue: state.copyWith(clearUndo: true),
            positionMs: replacedPositionMs,
          )
        : null;
    final shuffled = shuffle || state.shuffled;

    // Play order is built as positions in [pids], so the entries can be
    // minted in the order they arrived in no matter how they are played.
    var order = [for (var i = 0; i < pids.length; i++) i];
    var index = startIndex.clamp(0, pids.length - 1);
    if (shuffle) {
      _shuffleRange(order, 0, order.length);
      index = 0;
    } else if (order.length > kQueueCap) {
      final start = min(index, order.length - kQueueCap);
      order = order.sublist(start, start + kQueueCap);
      index -= start;
    }
    if (order.length > kQueueCap) {
      order = order.sublist(0, kQueueCap);
    }
    if (shuffled && !shuffle) {
      _shuffleRange(order, index + 1, order.length);
    }

    var nextId = state.nextQueueId;
    final minted = <int, QueueEntry>{};
    for (final at in [...order]..sort()) {
      minted[at] = QueueEntry(
        queueId: '$kQueueIdPrefix${nextId++}',
        pid: pids[at],
      );
    }
    state = QueueState(
      entries: [for (final at in order) minted[at]!],
      sourceOrder: [for (final at in minted.keys) minted[at]!.queueId],
      currentIndex: index,
      shuffled: shuffled,
      repeat: state.repeat,
      source: source,
      nextQueueId: nextId,
      undo: displaced,
    );
  }

  /// Inserts [pids] right after the current entry.
  void playNext(List<String> pids) =>
      _insert(pids, state.isEmpty ? 0 : state.currentIndex + 1);

  /// Appends [pids] to the end of the queue.
  void addToEnd(List<String> pids) => _insert(pids, state.length);

  void _insert(List<String> pids, int at) {
    if (pids.isEmpty) return;
    var nextId = state.nextQueueId;
    final added = [
      for (final pid in pids.take(kQueueCap))
        QueueEntry(queueId: '$kQueueIdPrefix${nextId++}', pid: pid),
    ];
    if (state.isEmpty) {
      // Nothing to insert into: the additions become the queue, with no
      // provenance to claim beyond having been added by hand. Shuffle
      // and repeat are standing preferences and stay as they were, so a
      // queue started under shuffle is shuffled rather than leaving the
      // toggle claiming something the order does not show.
      final entries = [...added];
      if (state.shuffled) _shuffleRange(entries, 1, entries.length);
      state = state.copyWith(
        entries: entries,
        sourceOrder: [for (final e in added) e.queueId],
        currentIndex: 0,
        source: QueueSource.none,
        nextQueueId: nextId,
        clearUndo: true,
      );
      return;
    }
    final currentId = state.currentEntry!.queueId;
    final entries = [...state.entries]..insertAll(at, added);
    // The source order follows the play order: an entry added after the
    // one at [at - 1] sits after it when shuffle is turned off too.
    final sourceOrder = [...state.sourceOrder];
    final anchor = at == 0
        ? -1
        : sourceOrder.indexOf(state.entries[at - 1].queueId);
    sourceOrder.insertAll(anchor + 1, [for (final e in added) e.queueId]);

    state = _capped(
      state.copyWith(
        entries: entries,
        sourceOrder: sourceOrder,
        nextQueueId: nextId,
      ),
      currentId,
      {for (final e in added) e.queueId},
    );
  }

  /// Drops the entry at [index]. Dropping the current entry moves the
  /// one after it into the slot; dropping the last entry moves back.
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    if (state.length == 1) {
      clear();
      return;
    }
    final removed = state.entries[index];
    final currentId = state.currentEntry!.queueId;
    final entries = [...state.entries]..removeAt(index);
    final sourceOrder = [...state.sourceOrder]..remove(removed.queueId);
    // Dropping what is playing has no entry to follow: the slot's new
    // occupant becomes current, or the new last entry when the queue
    // ran out under it.
    final landing = removed.queueId == currentId
        ? min(index, entries.length - 1)
        : entries.indexWhere((e) => e.queueId == currentId);
    state = state.copyWith(
      entries: entries,
      sourceOrder: sourceOrder,
      currentIndex: landing,
    );
  }

  /// Moves the entry at [from] so it lands at [to] in play order.
  ///
  /// Plain list semantics: the entry is removed and re-inserted, so [to]
  /// is an index into the queue without it. `ReorderableListView` hands
  /// out a `newIndex` that assumes the entry is still there, so callers
  /// subtract one when moving an entry down.
  void reorder(int from, int to) {
    if (from < 0 || from >= state.length) return;
    final target = to.clamp(0, state.length - 1);
    // Guarding the clamped target, not the raw one: a drag that lands
    // out of range moves nothing, and rewriting the source order for it
    // would silently change what un-shuffling restores.
    if (target == from) return;
    final currentId = state.currentEntry!.queueId;
    final entries = [...state.entries];
    final moved = entries.removeAt(from);
    entries.insert(target, moved);
    // A hand-placed entry keeps its new neighbour when shuffle goes
    // off: the listener's placement outranks the source's order.
    final sourceOrder = [...state.sourceOrder]..remove(moved.queueId);
    final anchor = target == 0
        ? -1
        : sourceOrder.indexOf(entries[target - 1].queueId);
    sourceOrder.insert(anchor + 1, moved.queueId);
    state = state.copyWith(
      entries: entries,
      sourceOrder: sourceOrder,
      currentIndex: entries.indexWhere((e) => e.queueId == currentId),
    );
  }

  /// Makes the entry at [index] the current one (a tap in the queue).
  void jumpTo(int index) {
    if (state.isEmpty) return;
    final target = index.clamp(0, state.length - 1);
    if (target == state.currentIndex) return;
    state = state.copyWith(currentIndex: target);
  }

  /// Steps to the next entry, applying repeat.
  QueueAdvance advance() {
    if (state.isEmpty) return QueueAdvance.empty;
    if (state.repeat == QueueRepeat.one) return QueueAdvance.repeatedCurrent;
    if (state.currentIndex + 1 < state.length) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
      return QueueAdvance.advanced;
    }
    if (state.repeat == QueueRepeat.all) {
      // A lone entry wraps onto itself. Calling that an advance would
      // have the caller load what is already loaded; calling it a repeat
      // re-mints the listen session, which is what a second play of the
      // same item is.
      if (state.length == 1) return QueueAdvance.repeatedCurrent;
      state = state.copyWith(currentIndex: 0);
      return QueueAdvance.advanced;
    }
    return QueueAdvance.ended;
  }

  /// Steps back one entry. Repeat-all wraps to the end from the front;
  /// otherwise the front answers [QueueRetreat.atStart] and the caller
  /// restarts the current entry, which is what a second press of
  /// previous means everywhere else.
  QueueRetreat retreat() {
    if (state.isEmpty) return QueueRetreat.empty;
    if (state.currentIndex > 0) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
      return QueueRetreat.moved;
    }
    if (state.repeat == QueueRepeat.all && state.length > 1) {
      state = state.copyWith(currentIndex: state.length - 1);
      return QueueRetreat.moved;
    }
    return QueueRetreat.atStart;
  }

  /// Shuffles or un-shuffles the part of the queue that has not played.
  ///
  /// Turning it on reorders everything after the current entry, leaving
  /// the current entry playing and the history it sits on intact.
  /// Turning it off puts that remainder back in the order the queue was
  /// built in. The server's own `set-shuffle` cannot restore an order it
  /// never kept; a local queue keeps one, so it does.
  void setShuffle(bool on) {
    if (on == state.shuffled) return;
    if (state.isEmpty) {
      state = state.copyWith(shuffled: on);
      return;
    }
    final entries = [...state.entries];
    final from = state.currentIndex + 1;
    if (on) {
      _shuffleRange(entries, from, entries.length);
    } else {
      final ranks = {
        for (var i = 0; i < state.sourceOrder.length; i++)
          state.sourceOrder[i]: i,
      };
      final tail = entries.sublist(from)
        ..sort(
          (a, b) => (ranks[a.queueId] ?? 0).compareTo(ranks[b.queueId] ?? 0),
        );
      entries.replaceRange(from, entries.length, tail);
    }
    state = state.copyWith(entries: entries, shuffled: on);
  }

  void setRepeat(QueueRepeat repeat) {
    if (repeat == state.repeat) return;
    state = state.copyWith(repeat: repeat);
  }

  /// Puts back the queue a replacement displaced, and answers where it
  /// stood so the caller can resume it there. Null when there is
  /// nothing to take back.
  int? undoReplace() {
    final undo = state.undo;
    if (undo == null) return null;
    state = undo.queue;
    return undo.positionMs;
  }

  /// Adopts a restored (or otherwise externally built) queue wholesale.
  void restore(QueueState restored) {
    state = restored.copyWith(clearUndo: true);
  }

  /// Empties the queue. Repeat and shuffle are the listener's standing
  /// preferences, not the queue's, so they survive: this is the "Clear
  /// queue" verb, not the end of a session.
  void clear() {
    state = QueueState.empty.copyWith(
      repeat: state.repeat,
      shuffled: state.shuffled,
      nextQueueId: state.nextQueueId,
    );
  }

  /// Drops the queue and the standing preferences with it, for a sign
  /// out: the listener whose preferences they were is gone, and the
  /// next one to sign in did not ask for repeat-all.
  void reset() {
    state = QueueState.empty;
  }

  /// Trims a queue back to [kQueueCap], evicting history first (the
  /// oldest played entries), then the far end. The entry playing is
  /// never evicted, and neither is anything in [added] while something
  /// else can go.
  ///
  /// The set is chosen in one pass and applied in one rebuild: evicting
  /// one at a time cost a scan and two linear removals per entry, and a
  /// 500-item add onto a full queue is a gesture someone is waiting
  /// through.
  QueueState _capped(QueueState next, String currentId, Set<String> added) {
    final currentAt = next.entries.indexWhere((e) => e.queueId == currentId);
    if (next.length <= kQueueCap) {
      return next.copyWith(currentIndex: currentAt);
    }
    var over = next.length - kQueueCap;
    final evicted = <String>{};

    // History first, oldest to newest.
    final fromHistory = min(over, currentAt);
    for (var i = 0; i < fromHistory; i++) {
      evicted.add(next.entries[i].queueId);
    }
    over -= fromHistory;

    // Then the far end, sparing what just arrived: an add onto a full
    // queue that evicted itself would quietly do nothing.
    for (var i = next.length - 1; over > 0 && i > currentAt; i--) {
      final id = next.entries[i].queueId;
      if (added.contains(id) || !evicted.add(id)) continue;
      over--;
    }
    // More arrived than the queue can hold: the overflow is the tail of
    // what arrived.
    for (var i = next.length - 1; over > 0 && i > currentAt; i--) {
      if (evicted.add(next.entries[i].queueId)) over--;
    }

    final entries = [
      for (final e in next.entries)
        if (!evicted.contains(e.queueId)) e,
    ];
    return next.copyWith(
      entries: entries,
      sourceOrder: [
        for (final id in next.sourceOrder)
          if (!evicted.contains(id)) id,
      ],
      currentIndex: entries.indexWhere((e) => e.queueId == currentId),
    );
  }

  void _shuffleRange<T>(List<T> items, int from, int to) {
    for (var i = to - 1; i > from; i--) {
      final j = from + _random.nextInt(i - from + 1);
      final swap = items[i];
      items[i] = items[j];
      items[j] = swap;
    }
  }
}

/// The one local queue.
final queueControllerProvider = NotifierProvider<QueueController, QueueState>(
  QueueController.new,
);
