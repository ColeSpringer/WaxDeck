part of '../playback_session.dart';

/// Opening the item, watching the engine and letting go of it.
extension _SessionLifecycle on PlaybackSession {
  /// [start]'s reads and its load, which [_underway] lands as asked.
  Future<void> _open({required bool autoplay}) async {
    // Asked on every road, before anything else: a setting the listener
    // changes meanwhile waits for it (see [_storeChoices]).
    _configLoad = _loadConfig();
    // The download is looked up beside the server's reads, and only the
    // mint waits on it: a copy that plays asks for no stream (see [start]
    // for what plays). Known out of reach, a start that will sound waits
    // on it first instead and plays a copy at once, at the mirror's
    // position, only the config asked behind it: a server whose connect
    // hangs would hold a downloaded item silent for the whole connect
    // deadline. Not known either way, the server has a short while to
    // answer first. A paused load is heard by nobody and waits for the
    // server as always, until a press, whenever it came.
    final reach = _reach;
    final mayWait = reach == _Reach.out || reach == _Reach.unknown;
    final lookedUp = downloads != null && timeline == null;
    final lookup = lookedUp ? downloads!.localFor(item.pid) : null;
    LocalPlayback? local;
    MediaLoadException? copyFailed;
    if (lookup != null && reach == _Reach.out && _resumeWanted) {
      local = await lookup;
      if (_disposed) return;
      final found = local;
      if (found != null) {
        if (_fits(found)) _copy = found;
        copyFailed = await _openFromDevice(found, autoplay: autoplay);
        if (copyFailed == null) return;
      }
    }
    // The three reads are independent and go out together. Config feeds
    // the rate, trim, and intro/outro, all applied after the load; play
    // state feeds only the resume point; play-info needs neither. Run in
    // turn they were three round trips of silence before the first byte
    // of an episode was even asked for, which is what made a
    // not-yet-fetched podcast slow to start.
    //
    // What that costs is the dispose gates that used to sit between
    // them: a session let go while the first read was in flight now
    // spends all three, so skipping fast through a queue mints a
    // play-info per tap. Bounded on the server rather than here - the
    // background chain resolve those mint has a ceiling of its own -
    // because a gate here would have to be a gate before the reads,
    // which is the serialization this removes.
    PlayState? saved;
    PlayInfo? playInfo;
    Object? stateFailure;
    Object? infoFailure;
    // The copy the lookup found, held where it can stand in for the stream.
    Future<void> settleCopy() async {
      if (lookup == null || copyFailed != null) return;
      final found = local = await lookup;
      if (!_disposed && found != null && _fits(found)) _copy = found;
    }

    try {
      // Joined rather than awaited one after another: a failure has to
      // leave no sibling read unwaited, or its own failure arrives as
      // an unhandled async error rather than in the catch below.
      //
      // Each read holds its own failure instead of letting the join
      // report one. `Future.wait` answers with whichever error landed
      // first, and the offline fallback below branches on the status
      // code it is handed - so a server mid-restart, answering 503 to
      // one read and 404 to the other, would decide between playing a
      // downloaded copy and rethrowing by whichever socket won the
      // race. Re-raised in a fixed order instead, which is the order
      // the serialized version had.
      final copyKnown = settleCopy();
      final reads = Future.wait<void>(<Future<void>>[
        _configLoad!,
        if (initialPositionMs == null)
          repository
              .getPlayState(item.pid)
              .then<void>((v) {
                saved = v;
              })
              .catchError((Object e) {
                stateFailure = e;
              }),
        // A copy that fits asks for no stream here: it plays unless the
        // boost is on, and the stream is asked for once that is known.
        if (!_isBook && timeline == null)
          copyKnown.then((_) async {
            if (_copy != null || _disposed) return;
            try {
              playInfo = await _mint(0);
            } on Object catch (e) {
              infoFailure = e;
            }
          }),
      ])..ignore();
      await copyKnown;
      if (_disposed) return;
      if (local != null &&
          mayWait &&
          copyFailed == null &&
          !await _answeredInTime(reads, reach!)) {
        if (_disposed) return;
        copyFailed = await _openFromDevice(local!, autoplay: autoplay);
        if (copyFailed == null) return;
      }
      await reads;
      if (stateFailure != null) throw stateFailure!;
      if (infoFailure != null) throw infoFailure!;
      // Let go while those were resolving: a tap on something else, or
      // the queue emptying. Loading here would put this item's media
      // over whatever took the engine, under a session nothing can
      // reach. One check for all three; every await after it is followed
      // by its own.
      if (_disposed) return;
      var resumeMs = initialPositionMs;
      if (resumeMs == null) {
        final state = saved!;
        // A finished item has no resume point: its checkpoint sits at
        // its own end, and playing it again means playing it. Loading
        // media at the position it ends at also fails outright on web,
        // where the element answers "no supported source" for a source
        // it is asked to begin past, so this is the difference between
        // starting over and an error pane.
        resumeMs = state.finished ? 0 : state.positionMs;
        if (autoplay) {
          // Applied to the load rather than as a seek after it, so the
          // ordinary case has no stutter at the seam.
          resumeMs = _rewound(resumeMs, since: state.updatedAt);
        } else {
          // A queue put back at launch stands at its checkpoint and may
          // never be played at all. Rewinding it here would move the
          // position this session goes on to write back, so ten cold
          // starts nobody listened to would walk a book backwards; the
          // step is owed to the first play and spent there.
          _restedSince = state.updatedAt;
        }
      }
      // The server's positions and chapters are placed on its own parts:
      // a book whose download no longer matches them streams.
      final held = _copy;
      if (held != null && !_matchesBook(held)) _copy = null;
      final copy = _copy;
      if (copy != null && !_boostOn) {
        copyFailed = await _openCopy(copy, resumeMs);
        if (copyFailed == null) return;
      }
      // Still held here, the copy was passed over for the boost: where
      // the boosted stream cannot be had, it plays without it.
      final boosted = _copy;
      if (boosted == null) {
        await _openStream(resumeMs, playInfo);
      } else {
        try {
          await _openStream(resumeMs, playInfo);
        } on Object catch (e) {
          if (_disposed ||
              e is! WaxDeckApiException && e is! MediaLoadException) {
            rethrow;
          }
          if (e is WaxDeckApiException && !e.unreachable) _boostRefused = true;
          copyFailed = await _openCopy(boosted, resumeMs);
          if (copyFailed != null) rethrow;
          return;
        }
      }
    } on WaxDeckApiException catch (e) {
      // The copy looked up above is not looked up again, and one that
      // would not load is how this ends, as it would have from here.
      LocalPlayback? copy;
      if (e.unreachable && copyFailed == null) {
        copy = lookedUp ? local : await _localFallback(e);
      }
      if (copy == null) {
        if (copyFailed != null && e.unreachable) throw copyFailed;
        rethrow;
      }
      await _openLocal(copy, autoplay: autoplay);
    }
    await _opened();
  }

  /// [_open]'s stream road: [playInfo], or one minted now, loaded at
  /// [resumeMs], the part holding it for a book.
  Future<void> _openStream(int resumeMs, PlayInfo? playInfo) async {
    if (_isBook) {
      final at = _startAt(resumeMs);
      _loadTarget = at;
      await _loadPartFor(at);
    } else {
      // A timeline member needs nothing resolved: the URL is minted,
      // the duration is the member's own, and the stream is
      // passthrough by construction. Synthesized into the same
      // PlayInfo the ordinary path builds so everything below - the
      // end-of-media guard, the outro cutoff, the reported duration -
      // reads one shape.
      final slot = timeline;
      // Minted here where the join asked for none: a copy was held, and
      // passed over for the boost.
      final info =
          playInfo ??
          (slot == null
              ? null
              : PlayInfo(
                  pid: item.pid,
                  url: slot.media.url,
                  mimeType: slot.media.mimeType,
                  durationMs: slot.durationMs,
                  seekable: true,
                  expiresAt: slot.media.expiresAt,
                )) ??
          await _mint(0);
      if (_disposed) return;
      // The same guard against a checkpoint the media outgrew: a
      // position at or past the end is not a place to start, however
      // it got there (a re-imported file, a listen that rounded up,
      // a finished flag that never landed). An episode the server
      // streams from its feed carries the feed's length here, which can
      // fall short of the audio or be missing: a checkpoint strictly past
      // it, or any checkpoint where the feed gave none, is held until the
      // audio's own length says whether it is clearly inside. One at the
      // declared length itself is the end a finish records when
      // play-info's length is all it has, so it replays from the top
      // like any end.
      final streamed =
          slot == null &&
          _lengthMayBeDeclared &&
          info.seekable &&
          info.partIndex == null;
      int? heldMs;
      var heldWithoutLength = false;
      if (info.durationMs > 0 && resumeMs >= info.durationMs) {
        if (streamed && resumeMs > info.durationMs) heldMs = resumeMs;
        resumeMs = 0;
      } else if (info.durationMs <= 0 && streamed && resumeMs > 0) {
        heldMs = resumeMs;
        heldWithoutLength = true;
        resumeMs = 0;
      }
      resumeMs = _applyIntroSkip(resumeMs);
      _loadTarget = resumeMs;
      if (slot != null) {
        await _loadTimelineMedia(
          slot,
          resumeMs > 0 ? Duration(milliseconds: resumeMs) : null,
        );
        if (_disposed) return;
        _moveTimeline(durationMs: slot.durationMs);
      } else {
        final at = resumeMs;
        // The mint above could not know the resume point (it went out
        // beside the play-state read), and a stream that answers no
        // ranges cannot be seeked to it: minted again, cut there.
        final minted = !info.seekable && at > 0 ? await _mint(at) : info;
        if (_disposed) return;
        await _loadStream(minted, at);
        if (_disposed) return;
        // Only clearly inside: a checkpoint in the last seconds is a
        // listen that reached the end, give or take another engine's
        // reading of the same audio, and replays from the top. Where no
        // length is known anywhere, nothing says it is not a place to
        // resume, and it is gone to as it stands.
        final held = heldMs;
        final length = engine.duration?.inMilliseconds;
        if (held != null &&
            (length == null
                ? heldWithoutLength
                : held + PlaybackSession._resumeSlackMs < length)) {
          await engine.seek(_inMedia(held));
        }
      }
      if (trimEnabled.value) unawaited(_loadSkipMap());
    }
  }

  /// Whether a start beside a download had the server's reads answer
  /// before it should take the copy instead. While nothing is to sound (a
  /// paused load, or a press taken back before anything sounded) that is
  /// whenever they answer; once something is, at once known out of reach,
  /// within [PlaybackSession.unansweredStartWait] not known either way.
  Future<bool> _answeredInTime(Future<void> reads, _Reach reach) async {
    final answered = reads.then((_) => true)..ignore();
    while (!_disposed) {
      if (!_resumeWanted && await _answeredOrPressed(answered)) return true;
      if (reach == _Reach.out) return false;
      if (await answered.timeout(
        PlaybackSession.unansweredStartWait,
        onTimeout: () => false,
      )) {
        return true;
      }
      if (_resumeWanted) return false;
    }
    return false;
  }

  /// Whether [answered] lands before play is pressed.
  Future<bool> _answeredOrPressed(Future<bool> answered) async {
    final pressed = Completer<bool>();
    void heard() {
      if (_resumeWanted && !pressed.isCompleted) pressed.complete(false);
    }

    reopening.addListener(heard);
    try {
      return await Future.any([answered, pressed.future]);
    } finally {
      reopening.removeListener(heard);
    }
  }

  /// The device road: [local] loaded at the mirrored position with what is
  /// known of the config, the rest taken up in place as it lands. Answers
  /// the failure of a copy that would not load, for the caller to ask the
  /// server instead.
  Future<MediaLoadException?> _openFromDevice(
    LocalPlayback local, {
    required bool autoplay,
  }) async {
    _applyConfig();
    try {
      await _openLocal(local, autoplay: autoplay);
    } on MediaLoadException catch (failure) {
      if (_disposed) rethrow;
      _copy = null;
      _localParts = null;
      return failure;
    }
    await _opened();
    if (!_disposed) _configLoad!.then((_) => _adoptLateConfig()).ignore();
    return null;
  }

  /// The device copy [copy] loaded at [resumeMs], the position the server
  /// answered, with its config applied. Answers the failure of a copy that
  /// would not load, for the caller to load the server's stream instead.
  Future<MediaLoadException?> _openCopy(
    LocalPlayback copy,
    int resumeMs,
  ) async {
    // The guards the stream's road applies: a position at or past the end
    // is not a place to start, and an episode starts past its intro.
    var at = resumeMs;
    if (_isBook) {
      at = _startAt(at);
    } else {
      final length = _fileLengthMs(copy);
      if (length > 0 && at >= length) at = 0;
      at = _applyIntroSkip(at);
    }
    _loadTarget = at;
    try {
      await _loadCopy(copy, at);
    } on MediaLoadException catch (failure) {
      if (_disposed) rethrow;
      _copy = null;
      _localParts = null;
      return failure;
    }
    if (_disposed) return null;
    // Parts ask for their own maps as they load.
    if (trimEnabled.value && _localParts == null) unawaited(_loadSkipMap());
    await _opened();
    return null;
  }

  /// [_open]'s offline branch: [local] loaded at the mirrored resume
  /// position.
  Future<void> _openLocal(LocalPlayback local, {required bool autoplay}) async {
    final saved = await sync?.localPlayState(item.pid);
    // The offline branch loads below; this is what keeps a session
    // already let go from doing so.
    if (_disposed) return;
    // A finished item starts over here too: the mirror keeps the same
    // checkpoint the server does, so a downloaded track listened to
    // the end would load at its own end with no network to correct
    // it.
    var resumeMs = initialPositionMs ?? 0;
    if (initialPositionMs == null && saved != null && !saved.finished) {
      resumeMs = saved.positionMs;
      if (autoplay) {
        resumeMs = _rewound(resumeMs, since: saved.updatedAt);
      } else {
        _restedSince = saved.updatedAt;
      }
    }
    // A downloaded book whose parts can be placed on its own timeline
    // resolves the part the resume position falls in, exactly as
    // play-info would have. Anything else - a track, a single-file
    // book, a book whose stored parts carry no durations - is the one
    // file this always loaded.
    if (_isBook && local.sequenced) {
      _localParts = local;
      final at = _startAt(resumeMs);
      _loadTarget = at;
      await _loadPartFor(at);
    } else {
      if (!_isBook) resumeMs = _applyIntroSkip(resumeMs);
      _loadTarget = resumeMs;
      await _loadLocalFile(local, resumeMs);
    }
  }

  /// What every road through [_open] ends in, once its media is loaded.
  Future<void> _opened() async {
    if (_disposed) return;
    // After whichever load branch ran, never before: the engine's rate
    // is player-level state that outlives sources, so a write up where
    // the config landed sat two round trips ahead of the load and
    // audibly re-rated the outgoing media - a 1.5x podcast dropping to
    // 1x while a tapped track resolved, and the reverse. Here the rate
    // only ever lands on media this session owns, loaded but not yet
    // audible. A rate the listener set meanwhile is the engine's already.
    if (!_speedChosen) await engine.setSpeed(_configuredSpeed());
    if (_disposed) return;
    _lastPosition = engine.position;
    _loaded = true;
    _watchEngine();
  }

  void _watchEngine() {
    _positionSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(_onPlayingChanged);
    _completedSub = engine.completed.listen((_) => _onCompleted());
    _failureSub = engine.mediaFailed.listen(_onMediaFailed);
  }

  /// Records what the listener wants stored, at once, so taps made while a
  /// store waits are carried by one write. Answers what becomes of them.
  Future<bool> _choose({double? speed, bool? boost}) {
    if (speed != null) _speedToStore = speed;
    if (boost != null) _boostToStore = boost;
    return (_choicesMade ??= Completer<bool>()).future;
  }

  /// The choices waiting stored in their turn, and the stream reopened for a
  /// boost stored, which only a fresh mint carries. A reopen that fails
  /// leaves the old media playing, or says that a load failed, as a seek's
  /// does.
  Future<void> _store({bool atReturn = false}) async {
    final boost = await _inTurn(() => _storeChoices(atReturn: atReturn));
    if (!boost || _disposed) return;
    _boostServed = true;
    await _reopenForEffects();
  }

  /// The one writer of this item's stored settings. It reads them now and
  /// writes that read back with only what the listener chose laid over it,
  /// so a setting saved elsewhere meanwhile is never reverted and a read
  /// that failed never lets defaults through.
  ///
  /// A tap's turn stores the choices made since the server was last found
  /// out of reach ([_choicesMade]); an ask again ([atReturn]) every choice
  /// still waiting, and a config never answered. Out of reach, the choices
  /// are kept, the chips standing, and asked about again at the sync
  /// engine's return and on a growing wait ([_keepWaiting]); answered
  /// with a refusal they go, the boost chip back on what is stored, and a
  /// refused rate stands, as it always has. A store under way when the
  /// session is let go finishes for its item; choices left waiting go with
  /// the session. Answers whether a boost was stored.
  Future<bool> _storeChoices({bool atReturn = false}) async {
    await _configLoad;
    // The start's read may have found the server out of reach meanwhile.
    if (atReturn ? _disposed : _choicesMade == null) return false;
    if (!_waiting && !_configFailed) return false;
    final first = !_configAnswered;
    try {
      await _readConfig();
    } on WaxDeckApiException catch (e) {
      if (!e.unreachable) _refuseWaiting();
      return false;
    }
    if (first && !_disposed && _ownsEngine) {
      _applyConfig();
      await _adoptLateConfig();
    }
    if (!_waiting) {
      _nothingWaits();
      return false;
    }
    final speed = _speedToStore;
    final boost = _boostToStore;
    final made = _choicesMade;
    _speedToStore = null;
    _boostToStore = null;
    _choicesMade = null;
    try {
      await _writeChoices(speed: speed, boost: boost);
    } on WaxDeckApiException catch (e) {
      if (e.unreachable) {
        // Under any made meanwhile.
        _speedToStore ??= speed;
        _boostToStore ??= boost;
        made?.complete(true);
        _keepWaiting();
        return false;
      }
      made?.complete(false);
      if (boost != null && _boostToStore == null) _showStoredBoost();
      _nothingWaits();
      return false;
    }
    made?.complete(true);
    _nothingWaits();
    return boost != null;
  }

  bool get _waiting => _speedToStore != null || _boostToStore != null;

  /// One write of [speed] and [boost] over the settings just read.
  Future<void> _writeChoices({double? speed, bool? boost}) async {
    final it = item;
    final newSpeed = speed == null ? null : () => speed;
    final newBoost = boost == null ? null : () => boost;
    if (it is EpisodeSummary && item.mediaType == MediaType.podcast) {
      // None stored is a show nobody here follows, which refuses the write.
      final read = _showSettings ?? const SubscriptionSettings();
      final updated = read.copyWith(speed: newSpeed, voiceBoost: newBoost);
      await repository.putSubscriptionSettings(it.showPid, updated);
      _showSettings = updated;
    } else if (_isBook) {
      final read = _bookSettings ?? const BookSettings();
      final updated = read.copyWith(speed: newSpeed, voiceBoost: newBoost);
      await repository.putBookSettings(item.pid, updated);
      _bookSettings = updated;
    }
  }

  /// The server found out of reach: the choices made so far wait for its
  /// return, and whoever made them is told they took. While one waits, or
  /// the config was never answered, the server is asked again after a wait
  /// that doubles from a second to a minute, as well as at the sync
  /// engine's return.
  void _keepWaiting() {
    _choicesMade?.complete(true);
    _choicesMade = null;
    if (_disposed || !_ownsEngine) return;
    _watchForServer();
    if (_waiting || _configFailed) {
      _askAgain ??= Timer(_askPace.take(), () {
        _askAgain = null;
        _serverReturned();
      });
    }
  }

  /// Nothing waits any more, no choice and no config: no ask is due, and
  /// the next wait is the first.
  void _nothingWaits() {
    if (_waiting || _configFailed) return;
    _askAgain?.cancel();
    _askAgain = null;
    _askPace.reset();
  }

  /// A read the server answered with an error: the choices waiting go, as a
  /// refused write's do.
  void _refuseWaiting() {
    final boost = _boostToStore;
    _speedToStore = null;
    _boostToStore = null;
    _choicesMade?.complete(false);
    _choicesMade = null;
    _nothingWaits();
    if (boost != null) _showStoredBoost();
  }

  /// The boost chip back on what is stored, the listener's choice gone.
  void _showStoredBoost() {
    _boostChosen = false;
    if (!_disposed) _applyBoost();
  }

  /// Runs [work] once the settings work ahead of it is done.
  Future<T> _inTurn<T>(Future<T> Function() work) {
    final turn = _settingsTurn.then((_) => work());
    _settingsTurn = turn.then<void>((_) {}, onError: (Object _) {});
    return turn;
  }

  /// Watches the sync engine for the server's return, each one: a config
  /// never answered is asked again, and the choices waiting are stored. An
  /// engine already back when the watch starts (it reconnected while a read
  /// hung on the old route) is a return now.
  void _watchForServer() {
    final engine = sync;
    if (engine == null || _serverBack != null) return;
    var online = engine.started && engine.current.online;
    _serverBack = engine.status.listen((status) {
      final back = status.online && !online;
      online = status.online;
      if (back) _serverReturned();
    });
    if (online) _serverReturned();
  }

  void _serverReturned() {
    if (_configFailed || _waiting) unawaited(_store(atReturn: true));
  }

  /// Where this item stands for a final checkpoint, read synchronously:
  /// where it stood when it said it failed, else the target of a load
  /// under way (the engine reads the media being replaced, or the new
  /// media against the old timeline), else [_standingMs].
  int _exitMs() {
    final failed = _failedAtMs;
    if (failed != null) return failed;
    final target = _pendingSeekMs ?? _loadTarget;
    if (_busy && target != null) return target;
    return _standingMs();
  }

  /// Where the item stands with no load under way: where it stood before
  /// a load that failed (the engine reads the incoming media's start
  /// then), else the end an outro recorded, else the engine.
  int _standingMs() =>
      _stoodBeforeFailedLoad ??
      _display(_endedAt ?? engine.position).inMilliseconds;

  Future<void> _shutdown({
    required int atMs,
    required bool finished,
    required bool stopEngine,
  }) async {
    if (_disposed) return;
    _disposed = true;
    _checkpointTimer?.cancel();
    _skipMapRetry?.cancel();
    // Cancellations are not awaited: an idle subscription's cancel future is
    // the root-zone null future, which never resumes inside the fake-async
    // zone widget tests run in. Cancelling takes effect synchronously.
    unawaited(_positionSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_failureSub?.cancel());
    unawaited(_serverBack?.cancel());
    _askAgain?.cancel();
    unawaited(_stopReached.close());
    unawaited(_timelineMoved.close());
    unawaited(_mediaLoaded.close());
    unawaited(_sessionCompleted.close());
    unawaited(_sessionFailed.close());
    unawaited(_moveFailed.close());
    // Silenced before the writes below, which can wait out a dead
    // network: a cleared queue or an app swiped away goes quiet now, not
    // once the server answers. Ownership is read before any await, for
    // the reason [dispose] gives.
    final owned = identical(PlaybackSession._engineOwners[engine], this);
    if (owned) PlaybackSession._engineOwners[engine] = null;
    Object? stopFailure;
    StackTrace? stopStack;
    if (owned && stopEngine) {
      try {
        await engine.stop();
      } on Object catch (error, stack) {
        stopFailure = error;
        stopStack = stack;
      }
    }
    // A start that never got as far as loading has nothing to record,
    // and the engine's position belongs to whatever played before it:
    // writing that as this item's resume point would lose the
    // listener's place on a failure they can retry.
    if (_loaded) await _checkpointMs(atMs);
    await _reportSession(finished: finished);
    trimEnabled.dispose();
    voiceBoost.dispose();
    hoursSavedMs.dispose();
    reopening.dispose();
    // The writes still landed; the stop that failed is the caller's to hear.
    if (stopFailure != null) Error.throwWithStackTrace(stopFailure, stopStack!);
  }
}
