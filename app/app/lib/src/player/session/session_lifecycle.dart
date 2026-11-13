part of '../playback_session.dart';

/// Opening the item, watching the engine and letting go of it.
extension _SessionLifecycle on PlaybackSession {
  /// [start]'s reads and its load, which [_underway] lands as asked.
  Future<void> _open({required bool autoplay}) async {
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
    _configLoad = _loadConfig();
    PlayState? saved;
    PlayInfo? playInfo;
    Object? stateFailure;
    Object? infoFailure;
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
      await Future.wait<void>(<Future<void>>[
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
        if (!_isBook && timeline == null)
          _mint(0)
              .then<void>((v) {
                playInfo = v;
              })
              .catchError((Object e) {
                infoFailure = e;
              }),
      ]);
      if (stateFailure != null) throw stateFailure!;
      if (infoFailure != null) throw infoFailure!;
      // Let go while those were resolving: a tap on something else, or
      // the queue emptying. Loading here would put this item's media
      // over whatever took the engine, under a session nothing can
      // reach. One check for all three, because nothing between here
      // and the load awaits again.
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
                  ))!;
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
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (local == null) rethrow;
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
    if (_disposed) return;
    // After whichever load branch ran, never before: the engine's rate
    // is player-level state that outlives sources, so a write up where
    // the config landed sat two round trips ahead of the load and
    // audibly re-rated the outgoing media - a 1.5x podcast dropping to
    // 1x while a tapped track resolved, and the reverse. Here the rate
    // only ever lands on media this session owns, loaded but not yet
    // audible.
    await engine.setSpeed(_configuredSpeed());
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

  /// The show's stored settings, waited for rather than given up on.
  ///
  /// A persist sends the whole object back, so it needs what is stored
  /// now. Reading the field alone meant a tap that beat the load - or
  /// one whose load had failed - dropped the choice with the engine
  /// already at the new rate and the sheet's own footer promising the
  /// show would remember it. Re-fetched here when the load left nothing
  /// behind, so the write either lands or throws to the caller's catch.
  Future<SubscriptionSettings> _storedShowSettings(String showPid) async {
    await _configLoad;
    final loaded = _showSettings;
    if (loaded != null) return loaded;
    final detail = await repository.getPodcast(showPid);
    // Defaults where the show carries none, the way the book branch
    // already reads its own: a show nobody is subscribed to refuses the
    // write server-side, which is the caller's catch to report.
    final fetched = detail.settings ?? const SubscriptionSettings();
    _showSettings = fetched;
    return fetched;
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
