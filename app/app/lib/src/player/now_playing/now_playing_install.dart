part of '../now_playing_controller.dart';

/// Starting an entry, adopting a crossing, and letting a session go.
mixin _NowPlayingInstall
    on
        _NowPlayingCore,
        _NowPlayingPark,
        _NowPlayingTransport,
        _NowPlayingFailure,
        _NowPlayingPreload {
  /// Starts [entry].
  ///
  /// [useSavedPosition] is where the "music never resumes mid-track"
  /// policy lives, and it lives here rather than in [PlaybackSession]:
  /// the session's job is to honour the position it is handed, and six
  /// other callers rely on it reading the checkpoint when it is handed
  /// none. A parameter rather than a pending flag, deliberately -
  /// `build` defers its first start to a microtask, and a flag set
  /// before that microtask would be consumed by whatever started in
  /// between and resume the wrong item mid-track.
  ///
  /// Spoken word is untouched whatever the flag says: a book and a
  /// podcast come back to their checkpoints, which is what a checkpoint
  /// is for. Only music starts at the head.
  ///
  /// Precedence: `_pendingPositionMs` still wins over both.
  /// `undoReplace`, `playPids(positionMs:)` and resume-after-error all
  /// set it and all mean it.
  @override
  Future<void> _start(
    QueueEntry entry, {
    bool useSavedPosition = false,
    bool ordinary = false,
  }) async {
    final token = ++_startToken;
    _starting = token;
    _resumeOnReconnect = false;
    _armedOnline = null;
    _unplayable = null;
    _setPark(null);
    if (entry.queueId != _sessionEntryId) _sessionEntryLoaded = false;
    _sessionEntryId = entry.queueId;
    var positionMs = _pendingPositionMs;
    final useSaved = useSavedPosition || _pendingUseSaved;
    _entryUseSaved = useSaved;
    // A seek held for a start this one replaces did not land there.
    _settleStartSeek(null);
    _startPlays = !_pendingPaused;
    _startInstalled = false;
    _republishOpening();
    _entryPositionMs = positionMs;
    _pendingPositionMs = null;
    _pendingPaused = false;
    state = NowPlaying(entry: entry, item: _known[entry.pid], loading: true);
    TimelineSlot? slot;
    try {
      // Live radio bypasses sessions; loading an item takes the engine
      // back, so the radio surface must stop claiming it - and stop its
      // sound. Awaited, and inside the try, because the interrupt is the
      // start's first act on the engine: a station audibly playing
      // through the round trips below is the seam showing, and a start
      // that dies before its session exists has no other teardown that
      // would ever silence it. The ordering is total from here: engine
      // idle, then resolve, then session start, then load.
      await ref.read(radioPlaybackProvider.notifier).interrupt();
      if (_superseded(token)) return;
      // A load starts a fresh window, so whatever was prepared behind
      // the outgoing item is gone at the engine and gone here. Above the
      // resolve, so a resolve that throws cannot leave a stale record
      // suppressing the next legitimate arm.
      _preload = null;
      final item = await _resolve(entry.pid);
      if (_superseded(token)) return;
      // Named as soon as it resolves rather than once it loads.
      if (state.item == null) {
        state = NowPlaying(entry: entry, item: item, loading: true);
      }
      // Music starts at the head. Skipping away from a track and back is
      // a fresh play rather than a resume, and so is tapping a track in
      // a listing you had heard half of; the exceptions all say so
      // through [useSavedPosition]. Told to the session as an explicit
      // zero rather than by leaving it null, which is what asks the
      // session to go and read the checkpoint. Spoken word passes null
      // and keeps resuming.
      if (positionMs == null &&
          !useSaved &&
          item.mediaType == MediaType.music) {
        positionMs = 0;
      }
      // The head, not "unspecified": a retry after a failed start would
      // otherwise read the checkpoint and resume music mid-track.
      _entryPositionMs = positionMs;
      // Minted here rather than inside the session: the queue is what
      // gets rendered, and the queue is this layer's. Null everywhere
      // the ordinary per-item path applies, which is everywhere but a
      // browser playing music with the switch on.
      slot = ordinary
          ? null
          : await _feeder.slotFor(
              entry,
              item,
              ref.read(queueControllerProvider),
            );
      if (_superseded(token)) return;
      final session = _build(
        item,
        initialPositionMs: positionMs,
        timeline: slot,
      );
      // The engine's owner changes as start() begins, so the outgoing
      // session flushes its final checkpoint and listen report without
      // stopping media it no longer owns. A press from outside before
      // this point changed how the start lands; one after it reaches the
      // session, which folds it into its own load.
      final starting = session.start(autoplay: _startPlays ?? true);
      _install(session, entry);
      _startInstalled = true;
      _settleStartSeek(session);
      await starting;
      if (_superseded(token)) return;
      // The stream this start asked for is loaded and fetching, which
      // is when a rendering the feeder handed off to make room for it
      // is safe to let go of.
      _feeder.started();
      _skipRun = 0;
      state = NowPlaying(entry: entry, item: item, session: session);
      _sessionEntryLoaded = true;
      await _syncPreload();
    } on Object catch (error) {
      if (_superseded(token)) return;
      // The pane stays terse; the console carries the real failure so
      // field reports and browser tests can see it.
      debugPrint('playback start failed: $error');
      // Installed before it was known to work, so that the outgoing
      // session could let go while this one loaded: it has to let go
      // too, or Connect keeps reporting an endpoint playing an item that
      // never loaded, and anything reaching for the live session finds
      // one that cannot drive the engine.
      unawaited(_release(_session, _Farewell.stop));
      _setSession(null);
      _settleStartSeek(null);
      if (slot != null) {
        // The rendering is what would not load, a stream every member of
        // the queue shares, not this item: it is let go of and the item
        // starts the ordinary way, where a skip would spend the queue and
        // a retry would be handed the same rendering back.
        _feeder.clear();
        if (error case MediaTrouble(:final refusal?)) {
          _feeder.onLoadRefused(refusal);
        }
        _pendingPositionMs = _entryPositionMs;
        _pendingPaused = !(_startPlays ?? true);
        await (_inFlight = _start(
          entry,
          useSavedPosition: useSaved,
          ordinary: true,
        ));
        return;
      }
      _startFailed(
        entry,
        _known[entry.pid],
        error,
        meantToPlay: _startPlays ?? true,
      );
    } finally {
      // Only if it is still this start's window: a newer one that
      // superseded this has its own to close.
      if (_starting == token) {
        _starting = null;
        _startPlays = null;
        _republishOpening();
      }
    }
  }

  /// Takes over a stream the engine is already playing, after it crossed
  /// out of the previous item and into this one.
  @override
  Future<void> _adopt(QueueEntry entry, PlayInfo info) async {
    // The same bail every other start-class entry point has: radio took
    // the engine between the crossing and the queue catching up, so the
    // stream is the station's and there is nothing of this item's to
    // adopt. A session built here would run its checkpoint timer
    // against the radio stream and write this item's pid at the
    // station's position.
    if (_radioOwnsEngine) return;
    final token = ++_startToken;
    _starting = token;
    _dropStartIntent();
    _setPark(null);
    if (entry.queueId != _sessionEntryId) _sessionEntryLoaded = false;
    _sessionEntryId = entry.queueId;
    _entryPositionMs = null;
    _entryUseSaved = false;
    try {
      var item = _known[entry.pid];
      if (item == null) {
        // Normally the summary is in hand, because arming the preload
        // resolved it. Without it there is a fetch between the crossing
        // and the session that owns what is playing, and the outgoing
        // session has already let go: say so rather than leave a
        // finalized session on the state for surfaces to read.
        state = NowPlaying(entry: entry, loading: true);
        item = await _resolve(entry.pid);
        if (_superseded(token)) return;
      }
      // A replacement timeline minted while the outgoing one played is
      // swapped in here, at the seam that is happening now, before the
      // session that will own the stream exists. Nothing to do in the
      // ordinary case, where the crossing was inside the timeline
      // already loaded.
      final swapped = await _feeder.settleSwap(entry);
      if (_superseded(token)) return;
      if (!swapped) {
        // A replacement always carries a new URL, so the swap tore the
        // outgoing stream down before it failed. There is nothing left
        // to adopt: this is a start.
        await _start(entry);
        return;
      }
      final session = _build(item, timeline: _feeder.slotAt(entry));
      final adopting = session.adopt(info);
      _install(session, entry);
      // Published as soon as the session exists rather than once it
      // settles: the item is already playing and this session speaks
      // for it from here, so a crossing with the summary in hand
      // publishes exactly once, whole, with no frame in between where
      // the transport has nothing to bind to.
      _skipRun = 0;
      state = NowPlaying(entry: entry, item: item, session: session);
      _sessionEntryLoaded = true;
      await adopting;
      if (_superseded(token)) return;
      await _syncPreload();
    } on Object catch (error) {
      if (_superseded(token)) return;
      debugPrint('playback rollover failed: $error');
      unawaited(_release(_session, _Farewell.stop));
      _setSession(null);
      // A roll-over is playback already running.
      _startFailed(entry, _known[entry.pid], error, meantToPlay: true);
    } finally {
      if (_starting == token) _starting = null;
    }
  }

  /// Radio has taken the engine. The item playing lets go now, while
  /// the position is still its own: leaving it subscribed would count
  /// the station's stream as time listened to the item, checkpoint the
  /// item's pid at the station's position, and report it finished when
  /// the stream dropped. The queue keeps its entry, parked: no surface
  /// names it as playing, and nothing restarts it, because that would
  /// load over the radio the listener just chose.
  ///
  /// The token bump is unconditional, session or none: a start still
  /// resolving has no session installed yet, and guarding the bump on
  /// one let exactly that start wake up unsuperseded and load its item
  /// over the station that had just won the engine. Only the farewell
  /// is session-shaped, so only it stays behind the guard.
  void _handOverToRadio() {
    _startToken++;
    _dropStartIntent();
    // A failed start waiting for the server must not take the engine back
    // from the station when it returns.
    _resumeOnReconnect = false;
    _armedOnline = null;
    _adopting = null;
    // The park is the entry's state now: a queue edit under the station
    // skips nothing past it, and the press that takes it back plays.
    _unplayable = null;
    _pendingPaused = false;
    _feeder.clear();
    unawaited(_dropPreload());
    // [_sessionEntryId] is kept, so a queue edit under radio does not
    // restart the entry. One that had loaded was in playback and comes
    // back where it let go. One whose start never loaded, or failed,
    // keeps the place that start asked for, and comes back as that start
    // meant: to its checkpoint, to a place it was given (an undo, a
    // handoff, a bookmark), or from its own beginning with neither. A park
    // an earlier station left stays as it was made.
    if (_parkedEntryId != _sessionEntryId) {
      final loaded = _sessionEntryLoaded;
      final place = loaded ? null : _entryPositionMs;
      // Fresh is a park with nowhere to come back to. A position the start
      // was given decides it (the head is none); with none given, the
      // checkpoint it meant to resume does.
      final fresh = !loaded && (place == null ? !_entryUseSaved : place <= 0);
      _setPark(_sessionEntryId, fresh: fresh, positionMs: place);
    }
    final session = _session;
    if (session != null) {
      unawaited(_release(session, _Farewell.handOver));
      _setSession(null);
    }
    // Session or none: a start radio overtook is retired too.
    state = NowPlaying.nothing;
  }

  /// The queue ran out from under playback: let the item go and say so.
  void _stop() {
    _startToken++;
    _dropStartIntent();
    _adopting = null;
    _sessionEntryId = null;
    _setPark(null);
    _feeder.clear();
    unawaited(_dropPreload());
    unawaited(_release(_session, _Farewell.stop));
    _setSession(null);
    state = NowPlaying.nothing;
  }

  /// This client is going away: stop, and wait for the state a stop
  /// finalizes to actually land.
  ///
  /// The one verb here that is worth awaiting. Everywhere else a
  /// release is fired and forgotten, because the app is still running
  /// and the writes it makes will land in their own time; here the
  /// process is about to end, and a checkpoint still in flight when it
  /// does is a listener who comes back to a book at the position it
  /// stood at the last time they closed it properly.
  ///
  /// Deliberately not what backgrounding does. Closing the window is
  /// the gesture that means "stop"; minimizing, switching apps, and
  /// losing focus all keep playing, which is what a music player is
  /// for. A remote session is left alone for the same reason - the
  /// speaker in the other room is not this window.
  Future<void> goingAway() async {
    if (_radioOwnsEngine) {
      await ref.read(radioPlaybackProvider.notifier).interrupt();
      return;
    }
    final session = _session;
    _startToken++;
    _dropStartIntent();
    _adopting = null;
    _sessionEntryId = null;
    _feeder.clear();
    unawaited(_dropPreload());
    if (session == null) return;
    // The one release that is awaited, and awaited through the release
    // itself: a second `handOver` beside it would meet the disposed
    // guard and return on the next microtask having waited for neither
    // the checkpoint nor the listen report, which is the whole of what
    // this call is for. `handOver` rather than `dispose` because it
    // finalizes without touching the engine, and the engine is going
    // with the process anyway.
    final farewell = _release(session, _Farewell.handOver);
    _setSession(null);
    state = NowPlaying(entry: state.entry, item: state.item);
    await farewell;
  }

  PlaybackSession _build(
    ItemSummary item, {
    int? initialPositionMs,
    TimelineSlot? timeline,
  }) => PlaybackSession(
    repository: ref.read(repositoryProvider),
    engine: _engine,
    item: item,
    clientId: listenClientId,
    sync: ref.read(syncEngineProvider),
    downloads: ref.read(downloadManagerProvider),
    initialPositionMs: initialPositionMs,
    // Read at build, so a default changed mid-book does not re-rate
    // what is playing. The two domains keep separate defaults
    // because they are listened to differently: 1.5x is ordinary for
    // a podcast and unusual for a novel.
    defaultSpeed: item.mediaType == MediaType.audiobook
        ? ref.read(bookSpeedProvider)
        : ref.read(podcastSpeedProvider),
    defaultTrimSilence: ref.read(trimSilenceDefaultProvider),
    defaultVoiceBoost: ref.read(voiceBoostDefaultProvider),
    smartRewind: ref.read(smartRewindProvider),
    maxBitrateKbps: ref.read(streamMaxBitrateKbpsProvider),
    timeline: timeline,
    // Only where nothing durable queues a listen that could not be sent.
    listenOutbox: ref.read(syncEngineProvider) == null
        ? ref.read(listenOutboxProvider)
        : null,
  );

  /// Makes [session] the live one: the previous session lets go, Connect
  /// and the session registry are pointed here, and the feeds this layer
  /// runs on hang off it.
  void _install(PlaybackSession session, QueueEntry entry) {
    unawaited(_release(_session, _Farewell.stop));
    _sessionEntryId = entry.queueId;
    _registry.register(session);
    _setSession(session);
    _completedSub = session.sessionCompleted.listen(_onCompleted);
    _failedSub = session.sessionFailed.listen(_onSessionFailed);
    _moveFailedSub = session.moveFailed.listen(_onMoveFailed);
    // A load of the session's own drops whatever the engine had prepared
    // behind the item: forgotten here too, and prepared again when it is
    // time to.
    _loadedSub = session.mediaLoaded.listen((_) {
      _preload = null;
      unawaited(_syncPreload());
    });
    session.reopening.addListener(_republishOpening);
    final sleepTimer = ref.read(sleepTimerProvider.notifier)
      // The chapter boundary belonged to the item that armed it: another
      // item drops it, and the same item starting again (a retry, the
      // resume when the server comes back) keeps it. A countdown is the
      // listener's and stays.
      ..clearEndOfChapter(keepFor: session.item.pid);
    // End-of-chapter sleep is the session's to carry out. On the
    // container, because nothing need be watching the timer: the player
    // that armed it can be closed long before the chapter ends.
    _chapterEnd = ref.container.listen<int?>(
      sleepTimerProvider.select((s) => s.endOfChapterEndMs),
      (_, endMs) => session.stopAt(endMs),
      fireImmediately: true,
    );
    _stopReachedSub = session.stopReached.listen(
      (_) => sleepTimer.chapterReached(),
    );
    // When to prepare the next item is a question about how much of this
    // one is left, so the preload rides the position ticks.
    _positionFeed = session.displayPositionStream.listen(
      (_) => unawaited(_syncPreload()),
    );
  }

  /// Lets go of [session]: the feeds stop, the registry forgets it, and
  /// it finalizes out of band so the last checkpoint and listen report
  /// still ride while the next item loads.
  ///
  /// The caller names the session that replaces it (or none) through
  /// [_setSession], which is the one place Connect hears about it: what
  /// the endpoint mirrors is whichever session owns the engine, and
  /// between these two calls that is nothing.
  ///
  /// Returns the farewell rather than swallowing it. Three of the four
  /// callers ignore it, which is the design; [goingAway] is the one
  /// that has to know the checkpoint and the listen report landed
  /// before the process goes, and a session finalizes once - a second
  /// `handOver` beside this one returns on the disposed guard without
  /// waiting for anything.
  ///
  /// Everything before the farewell runs synchronously, so a caller
  /// that drops the future still has the feeds cancelled and the
  /// registry cleared by the time it returns.
  @override
  Future<void> _release(PlaybackSession? session, _Farewell farewell) {
    unawaited(_completedSub?.cancel());
    unawaited(_failedSub?.cancel());
    unawaited(_moveFailedSub?.cancel());
    unawaited(_loadedSub?.cancel());
    unawaited(_positionFeed?.cancel());
    unawaited(_stopReachedSub?.cancel());
    _chapterEnd?.close();
    _completedSub = null;
    _failedSub = null;
    _moveFailedSub = null;
    _loadedSub = null;
    _positionFeed = null;
    _stopReachedSub = null;
    _chapterEnd = null;
    if (session == null) return Future<void>.value();
    session.reopening.removeListener(_republishOpening);
    _registry.unregister(session);
    return switch (farewell) {
      _Farewell.stop => session.dispose(),
      _Farewell.boundary => session.finishAtBoundary(),
      _Farewell.handOver => session.handOver(),
    };
  }
}
