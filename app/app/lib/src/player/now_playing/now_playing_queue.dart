part of '../now_playing_controller.dart';

/// The play verbs that build the queue, and playback following it.
mixin _NowPlayingQueue
    on
        _NowPlayingCore,
        _NowPlayingPark,
        _NowPlayingFailure,
        _NowPlayingPreload,
        _NowPlayingInstall {
  /// The one "play this" verb: builds the queue this gesture defines and
  /// starts the entry it lands on.
  ///
  /// [items] is the list the gesture came from, in its own order, and
  /// [startIndex] the row that was chosen. [positionMs] overrides the
  /// saved resume position of that first entry (a book resume, a chapter
  /// start). [shuffle] is the "Shuffle" entry point, which draws from
  /// anywhere in [items].
  void play(
    List<ItemSummary> items, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
  }) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    _parkFollowsKnown();
    unawaited(
      playPids(
        [for (final item in items) item.pid],
        source: source,
        startIndex: startIndex,
        shuffle: shuffle,
        positionMs: positionMs,
      ),
    );
  }

  /// Adds [items] to the end of the queue without disturbing what is
  /// playing.
  ///
  /// Records the summaries first, the same reason [play] does: an entry
  /// added by hand is drawn from what the caller knew about it long
  /// before its own start resolves one, and a queue row reading "Loading"
  /// for something the screen was showing a title for is the seam
  /// showing.
  ///
  /// An empty queue takes them as its whole contents, which is what the
  /// queue layer already does with an insert into nothing, and playback
  /// follows the queue's current entry, so adding to nothing starts it.
  /// That is the design rather than a surprise: there is one queue and
  /// playback is a view of it. Except under a station, which nothing
  /// loads over: the entry waits, parked fresh, and is offered as queued
  /// once it stops.
  void enqueue(List<ItemSummary> items) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    _parkFollowsKnown();
    _addingUnderStation(
      () => ref.read(queueControllerProvider.notifier).addToEnd([
        for (final item in items) item.pid,
      ]),
    );
  }

  /// The same verb, landing at a chosen slot: what a row dropped onto
  /// the queue panel does. The summaries are seeded the same way, so
  /// the rows have titles before anything plays them.
  void enqueueAt(List<ItemSummary> items, int at) {
    if (items.isEmpty) return;
    for (final item in items) {
      _known[item.pid] = item;
    }
    _parkFollowsKnown();
    _addingUnderStation(
      () => ref.read(queueControllerProvider.notifier).insertAt([
        for (final item in items) item.pid,
      ], at),
    );
  }

  /// Runs [add], parking what it makes current while a station plays.
  void _addingUnderStation(void Function() add) {
    _parkLanding = _radioOwnsEngine;
    try {
      add();
    } finally {
      _parkLanding = false;
    }
  }

  /// The same verb for a queue named by pid alone, which is what
  /// arrives from outside the widget tree: a queue handed to this
  /// endpoint by another device, or a browse leaf tapped on a head
  /// unit. Summaries resolve as each entry starts.
  ///
  /// [autoplay] false loads the entry and stops there, for a queue put
  /// back at its checkpoint. Resolves once the entry it lands on has
  /// started or failed, so a caller that answers for the load can.
  ///
  /// This announces nothing. Replacing the queue is what every play verb
  /// in the app does, and the audio changing says so louder than a toast
  /// could; the displaced queue is still kept, and session history is
  /// where it is offered back.
  Future<void> playPids(
    List<String> pids, {
    required QueueSource source,
    int startIndex = 0,
    bool shuffle = false,
    int? positionMs,
    bool autoplay = true,
  }) {
    if (pids.isEmpty) return Future<void>.value();
    // A deliberate play is a fresh start, so a run of skipped files
    // left over from the last queue does not spend this one's budget:
    // three bad rips yesterday must not make the first bad file today
    // the one that stops everything.
    _skipRun = 0;
    _pendingPositionMs = positionMs;
    _pendingPaused = !autoplay;
    ref
        .read(queueControllerProvider.notifier)
        .playNow(
          pids,
          source: source,
          startIndex: startIndex,
          shuffle: shuffle,
          // Where the displaced queue stood, which the queue layer has
          // no way to know and this one does: it is what an Undo of the
          // replacement resumes at.
          replacedPositionMs: _session?.displayPosition.inMilliseconds ?? 0,
        );
    // The queue notifies its listeners as it is assigned, so the start
    // this landed on is already the one in flight.
    return settled;
  }

  void _onQueueChanged(QueueState? previous, QueueState next) {
    // Summaries accumulate as entries come and go, and a session can run
    // for days; what a sweep keeps (the queue, the one an undo would bring
    // back, and the item playing) is the bound worth holding them to.
    // Guarded rather than swept every time, because a drag emits a queue
    // state per frame.
    if (_known.length > 2 * kQueueCap + 1) _prune(next);
    final entry = next.currentEntry;
    if (entry == null) {
      _stop();
      return;
    }
    if (entry.queueId != _sessionEntryId) {
      if (_parkLanding) {
        _parkLanding = false;
        _sessionEntryId = entry.queueId;
        _sessionEntryLoaded = false;
        // Displaced from nothing: it never played.
        _setPark(entry.queueId, fresh: true);
        return;
      }
      final adopting = _adopting;
      _adopting = null;
      if (adopting != null && adopting.entry.queueId == entry.queueId) {
        _inFlight = _adopt(entry, adopting.info);
      } else {
        _inFlight = _start(entry);
      }
      return;
    }
    final unplayable = _unplayable;
    if (unplayable != null &&
        unplayable.entryId == entry.queueId &&
        _canMoveOn(next)) {
      _unplayable = null;
      _skipPast(entry, state.item, play: unplayable.play);
      return;
    }
    // The entry playing did not move, but what follows it may have
    // (a reorder, a removal, a repeat toggle).
    unawaited(_syncPreload());
  }
}
