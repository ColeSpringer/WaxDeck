part of '../playback_session.dart';

/// Reactions to the engine, stops, and what this session announces.
extension _SessionEvents on PlaybackSession {
  void _onPosition(Duration position) {
    if (_disposed) return;
    final delta = position - _lastPosition;
    _lastPosition = position;
    if (_reachedStop(position, delta)) return;
    if (!engine.playing) return;
    if (delta > Duration.zero && delta <= PlaybackSession.maxCountedStep) {
      _ensureSession();
      _msPlayed += delta.inMilliseconds;
      _countSpeedSaving(delta.inMilliseconds);
    }
    final recoveredAt = _recoveredAtMs;
    if (recoveredAt != null &&
        _display(position).inMilliseconds - recoveredAt >=
            PlaybackSession._provenMs) {
      _recoveries = 0;
      _recoveredAtMs = null;
    }
    _maybeTrimJump(position);
    _maybeOutroStop(position);
  }

  /// Entering a mapped silence span jumps forward to its end. Jumps only
  /// ever go forward and each span fires at most once per load, so a
  /// stubborn backend that lands short of the target cannot loop.
  ///
  /// Spans are in the file's own time; a cut stream's clock starts at the
  /// cut, so both sides are read in file time.
  void _maybeTrimJump(Duration position) {
    if (!trimEnabled.value || _skipSpans.isEmpty) return;
    // A jump would restart such a stream at its head, and a cut per
    // silence is a fresh encode of the rest each time.
    if (_cantSeekHere) return;
    final ms = _cutMs + position.inMilliseconds;
    for (var i = _lastJumpedSpan + 1; i < _skipSpans.length; i++) {
      final span = _skipSpans[i];
      if (ms >= span.startMs - PlaybackSession.trimWindowMs &&
          ms < span.endMs) {
        _lastJumpedSpan = i;
        hoursSavedMs.value += span.endMs - ms;
        unawaited(engine.seek(Duration(milliseconds: span.endMs - _cutMs)));
        return;
      }
    }
  }

  /// Crossing the outro cutoff ends the episode as completed: the tail
  /// is credits the caller asked to skip.
  void _maybeOutroStop(Duration position) {
    final cutoff = _outroCutoffMs;
    if (cutoff == null || _outroFired) return;
    final fileMs = _cutMs + position.inMilliseconds;
    if (fileMs < cutoff) return;
    _outroFired = true;
    _finished = true;
    unawaited(engine.pause());
    // The checkpoint records the real end so resume lands past the outro.
    // Held as well as written: the engine is paused at the cutoff, so a
    // final checkpoint taken from it would put the resume point back
    // before the outro and fire this again on the next play.
    final endMs = _mediaEndMs ?? fileMs;
    // On the engine's clock, which [_display] reads back through the cut.
    _endedAt = Duration(milliseconds: endMs - _cutMs);
    unawaited(_checkpoint(at: _endedAt!));
    unawaited(_reportSession(finished: true));
    _announceCompleted(SessionEnd.played);
  }

  void _onPlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _rewindForBreak();
      _ensureSession();
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(checkpointInterval, (_) {
        if (_loading == 0) unawaited(_checkpoint());
      });
    } else {
      // Stamped from the engine's own transition rather than from the
      // control that caused it: a pause arrives from the lock screen,
      // a headset button, a routed Connect command, and an interruption
      // the platform made on its own, and all of them are a listener
      // who stopped listening.
      _pausedAt ??= _clock();
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      // Paused from outside while a load under way waits on its mint (an
      // interruption the platform made): it must not start it again. Only
      // media still standing ready stops that way. The stop that comes
      // with an end or a failure arrives after it, when the end has
      // already begun a load (the roll into a book's next part), and is
      // no listener stopping.
      if (_busy &&
          _loading == 0 &&
          engine.processingState == EngineProcessingState.ready) {
        _resumeWanted = false;
        _markReopening();
      }
      // The stop a load starts with is not the listener stopping: the
      // engine already reads the new media while the state is the old.
      // Nor is a boundary stop's own pause, which checkpoints where it parks.
      if (_loading == 0 && !_stopping) unawaited(_checkpoint());
    }
  }

  void _onCompleted() {
    if (_disposed) return;
    // About media no longer loaded: a newer load took the engine first.
    if (engine.processingState != EngineProcessingState.completed) return;
    // Already somebody's: a stop at the end under way, a load replacing
    // the media, an end held for the next play or rested on.
    if (_stopping || _busy || _atEnd != _AtEnd.none) return;
    final stop = _stopAtMs;
    if (stop != null &&
        (stop <=
                _partStartMs +
                    _loadedDurationMs +
                    PlaybackSession._stopSlackMs ||
            !_hasNextPart)) {
      // The boundary is this media's end, and the end arrived before any
      // position crossed it: the end is the boundary. On the last part a
      // boundary still armed is the end too, since a chapter can be
      // marked past where the audio stops.
      _stopAtMs = null;
      unawaited(_stopHere(stop, ended: true));
      return;
    }
    if (_hasNextPart) {
      // The book has more parts: roll into the next one seamlessly.
      unawaited(_advanceToNextPart());
      return;
    }
    _finished = true;
    unawaited(_checkpoint());
    unawaited(_reportSession(finished: true));
    _announceCompleted(SessionEnd.played);
  }

  Future<void> _advanceToNextPart() async {
    // Falls back to the downloaded parts itself where there are any: a
    // server that went away mid-book does not end a book somebody
    // downloaded, which is the whole point of downloading one. A part
    // that cannot be had lands on the error surface instead, from the
    // boundary this play actually reached, and the release that answers
    // it reports the listen unfinished, which is what it is.
    final partEnd = _partStartMs + _loadedDurationMs;
    if (await _recover(partEnd, resume: true)) {
      // The load's own pause wrote nothing; this is where the book is.
      unawaited(_checkpoint());
    }
  }

  /// Whether [position] reached the armed stop by moving forward into it:
  /// playing at any speed, or a trim jump over the silence a chapter ends
  /// in. A listener's jump past it never arrives here, since [seek]
  /// disarms it first; a move backwards across it only spends it.
  ///
  /// Read off the step, not off `playing`: the tick that crosses a
  /// boundary at the end of the media arrives as the media ends, when the
  /// engine already reads stopped.
  bool _reachedStop(Duration position, Duration delta) {
    final stop = _stopAtMs;
    // A load in flight reports the new media's position against the old
    // media's timeline, which can read as anywhere; and while a load of
    // the session's own is under way the media still playing is the one
    // being replaced, whose crossing says nothing of where the new one
    // lands.
    if (stop == null || _loading > 0 || _busy) return false;
    if (_display(position).inMilliseconds < stop) return false;
    _stopAtMs = null;
    // Reached only by a step that began short of it. One already behind
    // where the step began (a move backwards, a boundary armed after
    // playback passed it) is spent where it stands.
    final crossed = _display(position - delta).inMilliseconds < stop;
    if (crossed) {
      unawaited(_stopHere(stop));
    } else {
      _announceStopReached();
    }
    return crossed;
  }

  /// Where the loaded media ends on the display timeline: a book part's
  /// end; for anything else the audio's own length as the engine reports
  /// it, else play-info's where that is the audio's rather than a feed's
  /// word. Null when nothing says, and a stop there parks: only the
  /// media's own end finishes the listen.
  int? get _mediaEndMs {
    if (_isBook) return _partStartMs + _loadedDurationMs;
    // A cut stream's own clock covers only what is left of the item.
    final reported = _cutMs > 0 ? null : engine.duration;
    if (reported != null && reported > Duration.zero) {
      return reported.inMilliseconds;
    }
    if (_lengthMayBeDeclared || _loadedDurationMs <= 0) return null;
    return _loadedDurationMs;
  }

  /// Rests at [stopMs]: pauses and parks on the boundary, so a resume
  /// starts what follows at its head. A boundary at the end of the loaded
  /// media is that end: a book's next part is loaded paused, and the last
  /// part finishes without the queue moving on under a sleeper. A load
  /// under way while it does, so a press made meanwhile is how it ends.
  ///
  /// [ended] is the media's own end arriving with the boundary armed,
  /// which for media of no known length is where it stops.
  Future<void> _stopHere(int stopMs, {bool ended = false}) async {
    _stopping = true;
    final mediaEnd =
        _mediaEndMs ??
        (ended ? _display(engine.position).inMilliseconds : null);
    final atEnd =
        mediaEnd != null && stopMs >= mediaEnd - PlaybackSession._stopSlackMs;
    final at = mediaEnd != null && mediaEnd < stopMs ? mediaEnd : stopMs;
    try {
      await _underway(
        at,
        resume: false,
        load: () async {
          await engine.pause();
          if (_disposed) return;
          if (!atEnd) {
            // The pause lands up to a tick late; parked back where the
            // engine can seek, left there where it would restart the
            // stream.
            if (!_cantSeekHere) await engine.seek(_inMedia(stopMs));
          } else if (_hasNextPart) {
            await _loadAt(_partStartMs + _loadedDurationMs);
          } else {
            _finished = true;
            _atEnd = _AtEnd.held;
            unawaited(_reportSession(finished: true));
          }
        },
      );
      if (!_disposed) unawaited(_checkpoint());
    } on Object catch (error) {
      _announceFailed(error, meantToPlay: _resumeWanted, atMs: at);
    } finally {
      _stopping = false;
      _announceStopReached();
    }
  }

  void _announceStopReached() {
    if (!_stopReached.isClosed) _stopReached.add(null);
  }

  /// Tells the layer above that this item is over. Reported after the
  /// checkpoint and the listen report are on their way, so whatever
  /// advances the queue cannot outrun this item's own accounting.
  void _announceCompleted(SessionEnd end) {
    if (!_sessionCompleted.isClosed) _sessionCompleted.add(end);
  }

  /// Tells the layer above this session could not do what its item
  /// needed and should be let go, with [error] as the reason to show and
  /// whether playback [meantToPlay] when it struck.
  /// [atMs] is where the item stood, when the caller knows better than
  /// the engine does by now.
  void _announceFailed(Object error, {required bool meantToPlay, int? atMs}) {
    if (_sessionFailed.isClosed) return;
    final at = atMs ?? _exitMs();
    _failedAtMs = at;
    _sessionFailed.add((error: error, meantToPlay: meantToPlay, atMs: at));
  }
}
