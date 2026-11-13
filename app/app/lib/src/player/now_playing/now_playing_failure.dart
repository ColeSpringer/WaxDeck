part of '../now_playing_controller.dart';

/// Where failed starts land, and what the session and the engine report.
mixin _NowPlayingFailure on _NowPlayingCore, _NowPlayingTransport {
  /// Where a start that did not survive lands: skipped past when the
  /// media itself is the problem and there is somewhere to go, and left
  /// on the error pane otherwise.
  ///
  /// The split is what refused, which is why the engine types it
  /// ([MediaFault]) rather than leaving it to be guessed at from the
  /// wording. A file the platform will not decode is not going to
  /// decode on the next press, and the queue behind it has nothing
  /// wrong with it: one bad rip should cost the track rather than the
  /// listening. Everything else keeps the pane - a server that answered
  /// an error, a stream that could not be fetched, a bug in here - and
  /// the retry there is a real offer, because all three are states that
  /// change.
  ///
  /// [mayAdvance] is false for a book that failed after it was already
  /// playing. A part that will not load is still a bad file, but the
  /// queue entry it belongs to is the whole book: stepping past it
  /// leaves the book six hours in, and reports the listen ended at a
  /// part boundary. That one stops where it is.
  ///
  /// [meantToPlay] is a start, or playback, that was meant to be running:
  /// one that failed for want of the server starts when the server is
  /// back, and a skip past a bad file plays what it lands on. Anything put
  /// back to wait, or paused, waits for a press instead.
  void _startFailed(
    QueueEntry? entry,
    ItemSummary? item,
    Object error, {
    bool mayAdvance = true,
    bool meantToPlay = false,
    bool midPlay = false,
  }) {
    final unplayable =
        error is MediaTrouble && error.fault == MediaFault.source && mayAdvance;
    if (unplayable && _canMoveOn(ref.read(queueControllerProvider))) {
      if (_skipPast(entry, item, play: meantToPlay)) return;
      // The run hit its cap. Stopping is the honest answer - a queue
      // that is all bad files is a library problem, not a skip - and
      // the message says how far it got rather than repeating the last
      // filename.
      final skipped = _skipRun;
      _skipRun = 0;
      ref
          .read(shellMessengerProvider.notifier)
          .showLocalized(
            (l10n) => l10n.playerSkipsGaveUp(skipped),
            // The same channel the skips used: this is the last thing
            // that run has to say, and it belongs in place of the
            // count still standing rather than behind it.
            channel: _skipChannel,
          );
      state = NowPlaying(entry: entry, item: item, error: error);
      return;
    }
    final id = entry?.queueId;
    _unplayable = unplayable && id != null
        ? (entryId: id, play: meantToPlay)
        : null;
    _resumeOnReconnect = meantToPlay && _outOfReach(error);
    _armedOnline =
        _resumeOnReconnect && ref.read(liveConnectionProvider) != false
        ? ref.read(wallClockProvider)()
        : null;
    state = NowPlaying(entry: entry, item: item, error: error);
    _offerRetry(item, midPlay: midPlay);
  }

  /// Steps past [item], a file that will not play, and says so; what it
  /// lands on plays only when [play] says the start meant to. False once
  /// the run of skips has reached its cap.
  bool _skipPast(QueueEntry? entry, ItemSummary? item, {required bool play}) {
    if (_skipRun >= _maxConsecutiveSkips) return false;
    _skipRun++;
    _announceSkip(item);
    if (!play) _pendingPaused = true;
    // Not awaited: a failed start calls this from a catch inside the
    // start it is replacing, and the next start has to begin after that
    // one has finished unwinding.
    Future<void>.microtask(next);
    // No error on the state: the queue is moving, and a pane that
    // appeared for a frame between two tracks is the flash this exists
    // to avoid.
    state = NowPlaying(entry: entry, item: item);
    return true;
  }

  /// Says on the shell that [item] could not start, with the pane's retry
  /// beside it: the pane is drawn only by the full player, and a listener
  /// at the deck bar would otherwise see a stopped transport and no why.
  /// Offline, a start that will resume by itself says so (see
  /// [_onServerBack]).
  /// [midPlay] is an item that had been playing, which did not fail to
  /// start and is not said to.
  void _offerRetry(ItemSummary? item, {bool midPlay = false}) {
    final title = item?.title;
    final offline =
        _resumeOnReconnect && ref.read(liveConnectionProvider) == false;
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => offline
              ? l10n.playerOfflineStart
              : switch ((title, midPlay)) {
                  (null, false) => l10n.playerStartFailed,
                  (null, true) => l10n.playerStopped,
                  (final title?, false) => l10n.playerCouldNotStart(title),
                  (final title?, true) => l10n.playerCouldNotContinue(title),
                },
          actionLabelOf: (l10n) => l10n.commonRetry,
          onAction: resume,
          actionSemanticsId: SemanticsIds.playerStartRetry,
        );
  }

  /// The link went down. A resume a failure armed while it still read up
  /// stands when that failure was this outage's leading edge, and lapses
  /// when it was older.
  void _outageBegan() {
    final armed = _armedOnline;
    if (armed == null) return;
    _armedOnline = null;
    final since = ref.read(wallClockProvider)().difference(armed);
    if (since > _outageGrace) _resumeOnReconnect = false;
  }

  /// The live connection came back: a start that failed for want of the
  /// server starts, and listens held while it was away are sent.
  void _onServerBack() {
    unawaited(
      ref.read(listenOutboxProvider).flush(ref.read(repositoryProvider)),
    );
    if (_resumeOnReconnect && state.session == null && state.error != null) {
      _resumeOnReconnect = false;
      resume();
    }
  }

  /// Says what was skipped, as one line however many there have been.
  ///
  /// The first names the track, because that is the useful sentence
  /// when a single file in an album is bad. From the second on it is a
  /// count: three toasts naming three files nobody chose is noise, and
  /// the shell replaces the standing message rather than queueing it.
  void _announceSkip(ItemSummary? item) {
    final run = _skipRun;
    final title = item?.title;
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => run > 1 || title == null
              ? l10n.playerSkippedUnplayableMany(run)
              : l10n.playerSkippedUnplayable(title),
          channel: _skipChannel,
        );
  }

  /// Points [NowPlayingController.liveSession] at [session] and tells
  /// Connect, whose reports follow whatever owns the engine: a fresh
  /// session mirrors from here, and none at all stops the reports rather
  /// than leaving an endpoint claiming to play something it let go of.
  void _setSession(PlaybackSession? session) {
    _session = session;
    _republishOpening();
    _connect.onPlaybackChanged();
  }

  /// The live session could not do what its item needed mid-flight (a
  /// book part that would not load, a cross-part jump the server
  /// refused, media that stopped decoding): let it go the way a failed
  /// start is let go, so the same error pane and retry stand where the
  /// transport was. The release flushes the checkpoint at the position
  /// the failure left, which is where the retry resumes.
  ///
  /// A book never skips, however the failure classifies: a part is part
  /// of something already underway, and the entry a skip would step
  /// past is the whole book. A track or an episode whose file stopped
  /// decoding is the same bad file a failed start is, and skips the same.
  void _onSessionFailed(SessionFailure failure) {
    final session = _session;
    if (session == null) return;
    debugPrint('playback session failed: ${failure.error}');
    // A retry, by hand or on reconnect, picks up where this stood, not
    // where the entry first started.
    _entryPositionMs = failure.atMs;
    unawaited(_release(session, _Farewell.stop));
    _setSession(null);
    _startFailed(
      state.entry,
      state.item,
      failure.error,
      mayAdvance: session.item.mediaType != MediaType.audiobook,
      meantToPlay: failure.meantToPlay,
      midPlay: true,
    );
  }

  /// The item ended with nothing behind it in the engine: step the
  /// queue, which is what loads whatever comes next.
  void _onCompleted(SessionEnd end) {
    if (_radioOwnsEngine) return;
    final session = _session;
    switch (ref.read(queueControllerProvider.notifier).advance()) {
      // The queue moved; the entry change starts what it landed on.
      case QueueAdvance.advanced:
      case QueueAdvance.empty:
        break;
      // Nothing follows: what just finished stays on the deck bar, unless
      // a play released an end a sleep stop was holding - that press asked
      // for something, and with nothing after the item it is the item.
      case QueueAdvance.ended:
        if (end == SessionEnd.heldEndPlayed && session != null) {
          unawaited(session.replay());
        }
      case QueueAdvance.repeatedCurrent:
        if (session != null) unawaited(session.replay());
    }
  }

  /// A seek the live session could not have, with playback going on as
  /// it was: said, and nothing let go of.
  void _onMoveFailed(Object error) {
    ref
        .read(shellMessengerProvider.notifier)
        .showLocalized(
          (l10n) => l10n.playerMoveFailed(explainError(l10n, error)),
        );
  }

  /// The engine crossed out of the playing item and into the one it had
  /// prepared: the queue moves to that entry and a session for it takes
  /// over a stream that never stopped.
  void _onBoundary() {
    if (_radioOwnsEngine) return;
    final crossed = _preload;
    _preload = null;
    final notifier = ref.read(queueControllerProvider.notifier);
    if (crossed == null) {
      // The preload was dropped (the queue was edited) in the moment
      // between the engine committing to it and the crossing. The item
      // that played still reached its end, so it is finalized there
      // before the queue moves: leaving that to the next start would
      // checkpoint it at the stray item's position, which is zero.
      // Whatever the queue advances to then loads over the stray; if it
      // has nowhere to go, that item plays on and the log is the only
      // record of it.
      debugPrint('playback: crossed into an item the queue had let go');
      // Inside a timeline the stream did not stop, it ran on into the
      // member after this one - which on repeat one is the head of a
      // track the listener did not ask for, playing under the restart
      // that is about to happen.
      if (ref.read(queueControllerProvider).repeat == QueueRepeat.one) {
        _feeder.rewindMember();
      }
      unawaited(_release(_session, _Farewell.boundary));
      _setSession(null);
      _recoverFromStray();
      return;
    }
    // The outgoing item is finalized at its own end, not at the engine's
    // position, which already belongs to the item now playing.
    unawaited(_release(_session, _Farewell.boundary));
    _setSession(null);
    _adopting = crossed;
    final queue = ref.read(queueControllerProvider);
    // By identity, never by index: the queue may have been edited since
    // the preload was armed.
    final index = queue.entries.indexWhere(
      (e) => e.queueId == crossed.entry.queueId,
    );
    if (index < 0) {
      _adopting = null;
      _recoverFromStray();
    } else if (index == queue.currentIndex) {
      // Already current (the queue was edited under the crossing), so
      // no state change is coming to react to.
      _adopting = null;
      _inFlight = _adopt(crossed.entry, crossed.info);
    } else {
      notifier.jumpTo(index);
    }
  }

  /// The engine is playing an item the queue no longer points at, and the
  /// session that was playing has let go. Move the queue on, the way the
  /// end of an item does; when it has nowhere to go, nothing should be
  /// playing at all, so the stray is stopped rather than left running
  /// under a state that names a session which has already finalized.
  void _recoverFromStray() {
    _sessionEntryId = null;
    switch (ref.read(queueControllerProvider.notifier).advance()) {
      // The queue moved: the entry change loads over the stray.
      case QueueAdvance.advanced:
        return;
      // Repeat-one does not move the queue, so nothing else will load
      // over it; this does.
      case QueueAdvance.repeatedCurrent:
        final entry = ref.read(queueControllerProvider).currentEntry;
        if (entry != null) _inFlight = _start(entry);
      case QueueAdvance.ended:
      case QueueAdvance.empty:
        // The entry left standing is still the session's: a queue edit
        // must not start it, and a station taking the engine parks it.
        _sessionEntryId = ref
            .read(queueControllerProvider)
            .currentEntry
            ?.queueId;
        unawaited(_engine.stop());
        state = NowPlaying(entry: state.entry, item: state.item);
    }
  }
}

/// Whether [queue] has another entry to move on to: under repeat all a
/// lone entry can advance, but only onto itself.
bool _canMoveOn(QueueState queue) =>
    queue.canAdvance && queue.entries.length > 1;

/// Whether [error] is the server or the way to it being away, which the
/// connection coming back can cure. Never a file, never a refusal.
bool _outOfReach(Object error) => switch (error) {
  WaxDeckApiException(:final unreachable) => unreachable,
  MediaTrouble(:final fault, :final refusal) =>
    fault == MediaFault.transport && refusal == null,
  _ => false,
};

/// Shared by every message a skip run raises, so the shell supersedes
/// the standing one instead of stacking a second bar over it. Not a
/// semantics identifier: none of these has a button, and there is
/// nothing here for a test to press.
const _skipChannel = ShellChannel.skippedUnplayable;
