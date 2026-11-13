part of '../now_playing_controller.dart';

/// The transport verbs: play, pause, seek, stop, skip, resume, restore.
mixin _NowPlayingTransport on _NowPlayingCore, _NowPlayingPark {
  /// Plays or pauses whatever this device is playing: a station stops
  /// and starts, a live session toggles, and an entry left standing by a
  /// failed start is taken back by starting it again.
  ///
  /// Here rather than beside the command that runs it, because the
  /// surfaces that need it are no longer all in the widget tree: the
  /// keyboard and the deck bar hold a `WidgetRef`, the tray menu holds a
  /// container's `Ref`, and neither is the other. The verb belongs to
  /// whatever owns playback, which is this.
  void togglePlayback() {
    if (_radioOwnsEngine) {
      unawaited(ref.read(radioPlaybackProvider.notifier).toggle());
      return;
    }
    final session = state.session;
    if (session != null) {
      unawaited(session.toggle());
      return;
    }
    // A start in flight: the press reverses what the transport shows of
    // it, which is whether it lands playing.
    if (_startPlays != null) {
      unawaited(meansToPlay ? transportPause() : transportPlay());
      return;
    }
    // Nothing is showing a parked entry as playing, so a press here does
    // not start it.
    if (_parkedEntryId != null) return;
    resume();
  }

  /// Plays, for a play raised anywhere but a session's own controls (a
  /// lock screen, a headset, a head unit, a routed command): a start in
  /// flight lands playing, a live session plays, and an entry a failed
  /// start left standing starts again. False when there is nothing to
  /// play at all, a parked entry included.
  Future<bool> transportPlay() async {
    final session = _session;
    if (_startPlays != null) {
      _startPlays = true;
      _republishOpening();
      // Installed, the start's own session folds the press into its load.
      if (_startInstalled && session != null) await session.play();
      return true;
    }
    if (session != null) {
      await session.play();
      return true;
    }
    if (ref.read(queueControllerProvider).isEmpty) return false;
    if (_parkedEntryId != null) return false;
    resume();
    return true;
  }

  /// Plays the queue entry at [index]: a row tapped, an offer accepted.
  /// The current entry starts again where it stood when nothing is
  /// driving it, a parked one included, and a fresh park starts as any
  /// entry does. The park goes with the start, so a press [resume]
  /// declines (a start radio overtook still unwinding) leaves the offer
  /// standing.
  Future<void> playEntryAt(int index) {
    final queue = ref.read(queueControllerProvider);
    if (queue.isEmpty) return settled;
    if (index != queue.currentIndex) {
      ref.read(queueControllerProvider.notifier).jumpTo(index);
      return settled;
    }
    resume();
    return settled;
  }

  /// Pauses, for a pause raised anywhere but a session's own controls (the
  /// sleep countdown, a lock screen, a routed command): a start in flight
  /// lands paused, a live session pauses, folding into a load under way,
  /// and a failed start that the server's return would have started waits
  /// for a press instead.
  Future<void> transportPause() async {
    _holdForPress();
    final session = _session;
    if (session != null) {
      await session.pause();
    } else {
      await _engine.pause();
    }
  }

  /// Seeks, for a seek raised outside the app (a lock screen, a routed
  /// command), on the timeline the screens show. A seek before the start
  /// in flight has a session is held for it: the session still live is the
  /// item being replaced, and moving it would write the target as that
  /// item's place. Answers whether the seek landed.
  Future<bool> transportSeek(Duration position) async {
    if (_startPlays != null && !_startInstalled) {
      _startSeek = position;
      return (_startSeekLanded ??= Completer<bool>()).future;
    }
    final session = _session;
    if (session != null) return session.seek(position);
    await _engine.seek(position);
    return true;
  }

  /// Hands a seek held for the start in flight to its session, or answers
  /// that it did not land when no session will take it.
  void _settleStartSeek(PlaybackSession? session) {
    final held = _startSeek;
    final landed = _startSeekLanded;
    _startSeek = null;
    _startSeekLanded = null;
    if (landed == null) return;
    if (held == null || session == null) {
      landed.complete(false);
      return;
    }
    unawaited(session.seek(held).then(landed.complete));
  }

  /// Stops, for a stop raised outside the app: as [transportPause], with
  /// the live session letting its media go.
  Future<void> transportStop() async {
    _holdForPress();
    final session = _session;
    if (session != null) {
      await session.stop();
    } else {
      await _engine.stop();
    }
  }

  /// A start in flight superseded by something that is no start of an
  /// entry (the queue emptied, radio, a crossing, the app going): it lands
  /// nowhere, so from here nothing reads as opening.
  void _dropStartIntent() {
    _startPlays = null;
    _startInstalled = false;
    _settleStartSeek(null);
    _republishOpening();
  }

  /// A press that silenced playback: nothing starts again until another
  /// press says so, neither a start in flight nor the server coming back.
  void _holdForPress() {
    _resumeOnReconnect = false;
    _armedOnline = null;
    if (_startPlays != null) {
      _startPlays = false;
      _republishOpening();
    }
  }

  /// Steps to the next entry at someone's request. False when the queue
  /// has nowhere to go, so the caller can say so rather than pretend.
  ///
  /// A skip while live radio has the engine does nothing. Radio never
  /// queues, so there is nothing to step; stepping would take the
  /// engine back from the station the listener chose, which no skip
  /// button means.
  Future<bool> next() async {
    if (_radioOwnsEngine) return false;
    switch (ref.read(queueControllerProvider.notifier).skipNext()) {
      case QueueAdvance.advanced:
        await settled;
        return true;
      // A lone entry wrapping onto itself under repeat all: nothing to
      // load, so this is where it plays again.
      case QueueAdvance.repeatedCurrent:
        return _replayCurrent();
      case QueueAdvance.ended:
      case QueueAdvance.empty:
        return false;
    }
  }

  /// Steps back an entry, or starts the current one over when already
  /// at the front, which is what a second press of previous means
  /// everywhere else. False when nothing is queued, or when live radio
  /// has the engine (see [next]).
  Future<bool> previous() async {
    if (_radioOwnsEngine) return false;
    switch (ref.read(queueControllerProvider.notifier).retreat()) {
      case QueueRetreat.moved:
        await settled;
        return true;
      case QueueRetreat.atStart:
        return _replayCurrent();
      case QueueRetreat.empty:
        return false;
    }
  }

  Future<bool> _replayCurrent() async {
    final session = _session;
    if (session == null) return false;
    // A skip is not a play command: pressing previous at the front of a
    // paused queue puts it back at the start, it does not start it.
    await session.replay(play: session.meansToPlay);
    return true;
  }

  /// Starts the current entry again when nothing is driving it.
  ///
  /// Two states reach this, and the queue never moved in either, so
  /// nothing else would ever try. A start that failed leaves the entry
  /// sitting there: a stream that expired under a sleeping phone, or a
  /// server that was down for a moment, is one tap from playing rather
  /// than a queue that has to be rebuilt. And an entry a station parked
  /// is taken back this way through [playEntryAt].
  ///
  /// Does nothing while a session is live: that session's own toggle is
  /// the verb for playing and pausing. Nor while one is still starting,
  /// which looks the same from the outside - the state carries an entry
  /// and no session for the whole resolve-and-load window - but is
  /// already on its way, and starting it again would supersede a load
  /// in flight, re-mint its stream token and its listen session, and
  /// drop the position it was asked to start at.
  void resume() {
    if (state.session != null || _starting != null) return;
    final entry = ref.read(queueControllerProvider).currentEntry;
    if (entry == null) return;
    // Both states this answers are resumes: a start that failed asks
    // again for where it was going, and an item that let go of the
    // engine to radio comes back to the checkpoint it wrote on its way
    // out. A park that never loaded comes back from the place its start
    // asked for, if it asked for one; a fresh one is no resume, so its
    // item's own start rules apply.
    final park = _park;
    final parked = park != null && park.id == entry.queueId;
    _pendingPositionMs = parked
        ? park.positionMs
        : state.error != null
        ? _entryPositionMs
        : null;
    _inFlight = _start(entry, useSavedPosition: !(parked && park.fresh));
  }

  /// Puts a queue back in play at its checkpoint, paused unless
  /// [autoplay] says to play it: a queue restored at launch waits, and
  /// the launch offer's Resume is a press of play.
  /// [offerUndo] keeps what this displaced, for the surfaces that offer
  /// to put it back. Without it the offer is a button that cannot work.
  void restore(
    QueueState queue, {
    bool offerUndo = false,
    bool autoplay = false,
  }) {
    _pendingPositionMs = null;
    _pendingPaused = !autoplay;
    // The one music case that legitimately comes back mid-track: this is
    // the listen the app was closed in the middle of. Armed only across
    // the call below, which notifies as it assigns and so may start from
    // inside it; disarmed the moment it returns, so no unrelated start
    // can pick it up.
    _pendingUseSaved = true;
    final began = _startToken;
    try {
      ref
          .read(queueControllerProvider.notifier)
          .restore(
            queue,
            displacedPositionMs: offerUndo
                ? _session?.displayPosition.inMilliseconds ?? 0
                : null,
          );
    } finally {
      _pendingUseSaved = false;
    }
    // The queue notified its listeners as it was assigned, so when the
    // restored current entry's id differs from the playing one's, the
    // entry change above already started it. When it does not - restored
    // sessions mint entry ids from zero and so does a live queue's first
    // playNow, so a collision is ordinary - nothing started: the engine
    // would keep playing the old audio under the restored queue's UI
    // forever, and the pending-paused flag would sit armed until some
    // later advance consumed it and stood silent. The start is forced,
    // not playback: it loads the restored source over the old one and
    // honors the paused contract at the checkpoint.
    if (_startToken != began) return;
    final entry = ref.read(queueControllerProvider).currentEntry;
    if (entry == null) return;
    _inFlight = _start(entry, useSavedPosition: true);
  }

  /// Takes back the replacement a tap made: the queue that was
  /// displaced, at the position it stood at, playing.
  ///
  /// The queue layer keeps what was displaced and answers where it was;
  /// resuming it there is this layer's half. Set before the queue moves,
  /// because the queue notifies its listeners as it is assigned and the
  /// start this lands on is already reading these.
  ///
  /// Playing rather than paused, unlike a restore: an undo answers an
  /// accident that happened mid-listen, and silence would be the second
  /// surprise rather than the end of the first.
  ///
  /// [only] is the replacement an offer was made for; once another has
  /// replaced the queue since, that offer takes nothing back.
  void undoReplace([QueueUndo? only]) {
    // Read before the queue moves, not from what the undo returns: the
    // queue notifies its listeners as it is assigned, so the start this
    // lands on has already read these by the time the call comes back.
    final pending = ref.read(queueControllerProvider).undo;
    if (pending == null || only != null && !identical(pending, only)) return;
    _pendingPositionMs = pending.positionMs;
    _pendingPaused = false;
    ref.read(queueControllerProvider.notifier).undoReplace();
    // The displaced queue was standing on the entry that is playing
    // (a replacement that only changed what follows), so no start is
    // coming to consume the position: seek to it here instead.
    if (ref.read(queueControllerProvider).currentEntry?.queueId ==
        _sessionEntryId) {
      _pendingPositionMs = null;
      _pendingPaused = false;
      unawaited(_session?.seek(Duration(milliseconds: pending.positionMs)));
    }
  }

  /// Takes the entry playing out of the queue, for an item that stopped
  /// existing under the listener (a kind change folded it into a book).
  /// What lands in its place waits, paused, rather than starting: the
  /// listener was just told playback stopped. A parked entry is not
  /// playing, so nothing loads at all: what lands in its place takes over
  /// the park, fresh, having never played. The last entry going empties
  /// the queue.
  ///
  /// Armed across the one synchronous call that can consume it, as
  /// [restore] arms its flags: the queue notifies as it is assigned.
  void dropCurrent() {
    final queue = ref.read(queueControllerProvider);
    if (queue.isEmpty) return;
    _pendingPositionMs = null;
    _pendingPaused = true;
    _parkLanding = parked != null;
    try {
      ref.read(queueControllerProvider.notifier).removeAt(queue.currentIndex);
    } finally {
      _pendingPaused = false;
      _parkLanding = false;
    }
  }
}
