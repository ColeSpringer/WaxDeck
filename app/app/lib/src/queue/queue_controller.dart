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
      source: _windowed(source, pids.length, order, shuffle),
      nextQueueId: nextId,
      undo: displaced,
    );
  }

  /// What the source says about its own frontier once the cap has had
  /// its say.
  ///
  /// The caller's cursor names where its listing stands, which is the
  /// queue's frontier only when the queue took everything the caller
  /// had. Two windows leave it somewhere else:
  ///
  /// An ordered window is a contiguous run, and one cut short of the
  /// caller's last item ends inside the list rather than at its end.
  /// Resuming from the caller's cursor would step over everything
  /// between, so the cursor is dropped and the draw finds its place by
  /// the entry at the frontier instead - and it is rolling whatever the
  /// caller declared, because there demonstrably is more.
  ///
  /// A shuffled window is a sample of the whole list rather than a run,
  /// so it has no frontier inside the list at all: the caller's cursor
  /// is exactly the right place to draw from next, and whether the
  /// source can be drawn from is the pager's answer, not this layer's.
  QueueSource _windowed(
    QueueSource source,
    int available,
    List<int> order,
    bool shuffle,
  ) {
    if (shuffle || order.length == available) return source;
    return source.copyWith(rolling: true, cursor: '');
  }

  /// Appends more of the scope this queue is a window over, and records
  /// where the source stands after it.
  ///
  /// [more] false seals the window: the scope ran out, the caption goes,
  /// and nothing draws again. An empty [pids] with [more] true is a page
  /// that landed empty and says nothing either way - everything visible
  /// was filtered out of it, say - so the cursor moves on and the next
  /// drain tries again.
  ///
  void appendWindow(
    List<String> pids, {
    required String cursor,
    required bool more,
    int? seed,
  }) {
    // A window is over the queue that was cut from the scope; without
    // one there is nothing to append to and no provenance to keep.
    if (state.isEmpty) return;
    // A draw is machinery, not a gesture: it places itself in the source
    // by an entry or a cursor, and either can land it on ground the
    // queue already covers - a reorder that moved the frontier entry, a
    // cursor issued before an edit. Whatever it already holds is not
    // drawn again. A listener adding the same track twice by hand is a
    // different verb and still gets two of them.
    final held = state.pids.toSet();
    final arrivals = <String>[
      for (final pid in pids)
        if (held.add(pid)) pid,
    ];
    if (arrivals.isNotEmpty) {
      final currentId = state.currentEntry!.queueId;
      var nextId = state.nextQueueId;
      final added = [
        for (final pid in arrivals.take(kQueueCap))
          QueueEntry(queueId: '$kQueueIdPrefix${nextId++}', pid: pid),
      ];
      // Appended at the end of both orders, unlike a hand-placed
      // insert: these came after everything else in the scope, so that
      // is where turning shuffle off puts them back.
      final entries = [...state.entries, ...added];
      // A shuffled queue shuffles what arrives among itself rather than
      // through the tail already on screen: the window grows at its end,
      // which is what the queue surface shows and what a listener
      // watching it expects.
      if (state.shuffled) {
        _shuffleRange(entries, state.length, entries.length);
      }
      state = _capped(
        state.copyWith(
          entries: entries,
          sourceOrder: [...state.sourceOrder, for (final e in added) e.queueId],
          nextQueueId: nextId,
        ),
        currentId,
        {for (final e in added) e.queueId},
      );
    }
    state = state.copyWith(
      source: state.source.copyWith(
        rolling: more,
        cursor: cursor,
        seed: seed,
        clearSeed: seed == null,
      ),
    );
  }

  /// Stops the window drawing again: the scope ran out, or nothing here
  /// can say where in it the queue stands. The queue keeps playing what
  /// it holds; it just stops claiming there is more behind it.
  void sealWindow() {
    if (!state.source.rolling) return;
    state = state.copyWith(source: state.source.copyWith(rolling: false));
  }

  /// Inserts [pids] right after the current entry.
  void playNext(List<String> pids) =>
      _insert(pids, state.isEmpty ? 0 : state.currentIndex + 1);

  /// Appends [pids] to the end of the queue.
  void addToEnd(List<String> pids) => _insert(pids, state.length);

  /// Inserts [pids] at [at], which is where a drop that named a row
  /// lands. Clamped rather than refused: the caller resolves [at] from
  /// a hit test against rows that may have moved since.
  void insertAt(List<String> pids, int at) =>
      _insert(pids, at.clamp(0, state.length));

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

  /// Drops every entry in [queueIds] in one rebuild.
  ///
  /// One state write rather than a loop of [removeAt], because a loop
  /// invalidates its own indices after the first removal and rebuilds
  /// the whole surface per row. The current entry is dropped from the
  /// set defensively: multi-select is offered on the up-next rows only,
  /// and taking the queue out from under what is playing is not
  /// something a batch verb should be able to do by accident.
  void removeSet(Set<String> queueIds) {
    if (queueIds.isEmpty || state.isEmpty) return;
    final currentId = state.currentEntry!.queueId;
    final dropping = queueIds.where((id) => id != currentId).toSet();
    final entries = [
      for (final e in state.entries)
        if (!dropping.contains(e.queueId)) e,
    ];
    // Never empty by construction: the current entry is held back above,
    // so a set naming the whole queue leaves what is playing behind.
    // Emptying the queue is [clear]'s job and stays a deliberate verb.
    if (entries.length == state.length) return;
    state = state.copyWith(
      entries: entries,
      sourceOrder: [
        for (final id in state.sourceOrder)
          if (!dropping.contains(id)) id,
      ],
      // Re-derived rather than adjusted: the removals can straddle the
      // current entry, and counting them is one more thing to get wrong
      // than looking the entry back up.
      currentIndex: entries.indexWhere((e) => e.queueId == currentId),
    );
  }

  /// Gathers every entry in [queueIds] and lands the block at [to].
  ///
  /// The set arrives wherever it was and leaves contiguous, keeping its
  /// own play order: a selection of tracks 1, 4, and 7 moved to the top
  /// arrives as 1, 4, 7 rather than interleaved with what it passed.
  ///
  /// [to] is an index into the queue **without the moved entries**, the
  /// same convention [reorder] documents, and clamps - so the whole
  /// length means the end.
  ///
  /// A move that lands the set where it already sits writes nothing, for
  /// the reason [reorder] guards its own version: the source order is
  /// what un-shuffling restores, and rebuilding it for a move nobody can
  /// see changes where shuffle-off puts things back.
  ///
  /// Which entries a caller may move is the caller's to decide, as it is
  /// for [reorder] - the surface offers this on the up-next rows. Unlike
  /// [removeSet] there is no guard on the current entry, because moving
  /// what is playing is coherent where removing it is not: the index is
  /// re-derived from the entry rather than counted.
  void moveSetTo(Set<String> queueIds, int to) {
    if (queueIds.isEmpty || state.isEmpty) return;
    final moving = [
      for (final e in state.entries)
        if (queueIds.contains(e.queueId)) e,
    ];
    if (moving.isEmpty) return;
    final currentId = state.currentEntry!.queueId;
    final rest = [
      for (final e in state.entries)
        if (!queueIds.contains(e.queueId)) e,
    ];
    final at = to.clamp(0, rest.length);
    final entries = [...rest]..insertAll(at, moving);
    // Nothing moved, so nothing is written. Compared by play order
    // rather than by the target index: a set already contiguous at the
    // target arrives at the same arrangement whichever arithmetic got
    // it there.
    if (Iterable<int>.generate(
      entries.length,
    ).every((i) => entries[i].queueId == state.entries[i].queueId)) {
      return;
    }
    // The source order follows the play order, as it does for a single
    // hand-placed entry: the block sits after whatever now precedes it,
    // so turning shuffle off keeps the placement.
    final movedIds = <String>{for (final e in moving) e.queueId};
    final sourceOrder = [
      for (final id in state.sourceOrder)
        if (!movedIds.contains(id)) id,
    ];
    final anchor = at == 0 ? -1 : sourceOrder.indexOf(rest[at - 1].queueId);
    sourceOrder.insertAll(anchor + 1, [for (final e in moving) e.queueId]);
    state = state.copyWith(
      entries: entries,
      sourceOrder: sourceOrder,
      currentIndex: entries.indexWhere((e) => e.queueId == currentId),
    );
  }

  /// Moves the entry at [from] so it lands at [to] in play order.
  ///
  /// Plain list semantics: the entry is removed and re-inserted, so [to]
  /// is an index into the queue without it. That is what
  /// `SliverReorderableList.onReorderItem` hands out - it adjusts for
  /// the removal itself - so a surface using the older `onReorder`
  /// would have to subtract one when moving an entry down.
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

  /// Steps to the next entry because the current one ended, applying
  /// repeat.
  QueueAdvance advance() {
    if (state.isEmpty) return QueueAdvance.empty;
    if (state.repeat == QueueRepeat.one) return QueueAdvance.repeatedCurrent;
    return _step();
  }

  /// Steps to the next entry because someone asked for it: a transport
  /// button, a head unit, a controller on another device.
  ///
  /// Unlike [advance], repeat one does not hold the queue in place. It
  /// holds an item against its own end, not against a skip: whoever
  /// presses next means next.
  QueueAdvance skipNext() {
    if (state.isEmpty) return QueueAdvance.empty;
    return _step();
  }

  /// The step both forward verbs share: on to the next entry, wrapping
  /// under repeat all.
  QueueAdvance _step() {
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
  ///
  /// [displacedPositionMs] records what this replaced so it can be taken
  /// back, for the surfaces that offer an undo. The restored queue's own
  /// undo is always dropped: it belongs to a session that ended.
  void restore(QueueState restored, {int? displacedPositionMs}) {
    final displaced = displacedPositionMs != null && state.isNotEmpty
        ? QueueUndo(
            queue: state.copyWith(clearUndo: true),
            positionMs: displacedPositionMs,
          )
        : null;
    state = displaced == null
        ? restored.copyWith(clearUndo: true)
        : restored.copyWith(clearUndo: true).copyWith(undo: displaced);
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

/// Whether a next control leads anywhere, for the five surfaces that
/// offer one. Derived here rather than at each of them, so two
/// transports onto one queue cannot disagree about it, and selected so
/// they rebuild when the answer changes rather than on every edit.
final queueCanAdvanceProvider = Provider<bool>(
  (ref) => ref.watch(queueControllerProvider.select((q) => q.canAdvance)),
);
