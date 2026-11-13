part of '../playback_session.dart';

/// A load under way, reloads, recovery from a media failure and the skip map.
extension _SessionRecovery on PlaybackSession {
  /// Runs [load] as this session's load under way (see [_busy]), meaning
  /// to land at display position [atMs] and to end playing when [resume]
  /// says so. A press made meanwhile changes what it ends with, and a seek
  /// made meanwhile lands as soon as it does. Throws what [load] threw,
  /// leaving nothing folded into it behind.
  Future<void> _underway(
    int atMs, {
    required bool resume,
    required Future<void> Function() load,
  }) async {
    final landed = Completer<bool>();
    _landed = landed;
    _busy = true;
    _resumeWanted = resume;
    _loadTarget = atMs;
    _markReopening();
    try {
      await load();
    } on Object {
      // A seek folded into a load that failed did not land, and the next
      // load must not carry it.
      _pendingSeekMs = null;
      _remint = false;
      landed.complete(false);
      rethrow;
    } finally {
      _busy = false;
      _loadTarget = null;
      _markReopening();
    }
    var arrived = false;
    try {
      if (_disposed) return;
      _lastPosition = engine.position;
      if (_resumeWanted) {
        await play();
      } else if (engine.playing) {
        // Landed over live playback that was asked to stay paused (a
        // queue put back while something plays): the source swap alone
        // does not stop the transport.
        await engine.pause();
      }
      // A seek that arrived after the last mint lands now; effects
      // changed meanwhile reopen it once more (a seek that reloads has
      // minted them already).
      final pending = _pendingSeekMs;
      _pendingSeekMs = null;
      arrived = pending == null || await seek(Duration(milliseconds: pending));
    } finally {
      landed.complete(arrived);
    }
    if (_remint && !_disposed) await _reopenForEffects();
  }

  /// Mints this item again and loads it at display position [atMs], as a
  /// load under way. Keeps the listen session and its accounting: the
  /// item never changed, only the stream it plays from.
  ///
  /// Throws what the load threw, the server's refusals as API errors.
  Future<void> _reload({required int atMs, required bool resume}) => _underway(
    atMs,
    resume: resume,
    load: () async {
      var at = atMs;
      do {
        _remint = false;
        await _loadAt(at);
        if (_disposed) return;
        // Effects changed while the media loaded: minted again where
        // it now stands.
        at = _display(engine.position).inMilliseconds;
        _loadTarget = at;
      } while (_remint);
    },
  );

  /// One mint and load inside a load under way, at display position
  /// [atMs] or the newest target a seek made meanwhile: the part holding
  /// it for a book; the item otherwise, or the copy downloaded to this
  /// device when the server is out of reach.
  Future<void> _loadAt(int atMs) async {
    if (_isBook) {
      await _loadPartFor(atMs, newest: true);
      return;
    }
    final (PlayInfo, int) minted;
    try {
      minted = await _mintNewest(atMs);
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (_disposed) return;
      if (local == null) rethrow;
      final target = _pendingSeekMs ?? _loadTarget ?? atMs;
      _pendingSeekMs = null;
      await _loadLocalFile(local, target);
      return;
    }
    if (_disposed) return;
    await _loadStream(minted.$1, minted.$2);
  }

  /// A load of its own the listener asked for (a move, an effect). One
  /// whose mint failed before any load began left the media it was
  /// replacing as it was, so that is kept, set as the presses made
  /// meanwhile ask, and it answers false, said on [moveFailed] when [say]
  /// asks; one that failed after a load began has nothing left to keep
  /// and is said on [sessionFailed].
  Future<bool> _reloadKeeping({
    required int atMs,
    required bool resume,
    bool say = false,
  }) async {
    final loadsBefore = _loadsBegun;
    try {
      await _reload(atMs: atMs, resume: resume);
      return !_disposed;
    } on Object catch (error) {
      if (_disposed) return false;
      if (_loadsBegun != loadsBefore) {
        _announceFailed(error, meantToPlay: _resumeWanted);
        return false;
      }
      if (_resumeWanted &&
          !engine.playing &&
          engine.processingState != EngineProcessingState.completed) {
        await engine.play();
      } else if (!_resumeWanted && engine.playing) {
        await engine.pause();
      }
      if (say && !_moveFailed.isClosed) _moveFailed.add(error);
      return false;
    }
  }

  /// Media that had loaded failed afterwards (a token that lapsed before
  /// the next range request, a dropped connection, the engine away).
  ///
  /// Recovered by minting again and reloading where the listener stood,
  /// when another mint can help: a stale or engine-down refusal, or a
  /// failure nobody explained. The server's other refusals (the transcode
  /// cap) and the file itself failing are said instead, never retried.
  /// A timeline member and a downloaded file have nothing to mint.
  void _onMediaFailed(MediaFailure failure) {
    if (_disposed || !_loaded || _busy) return;
    if (!identical(PlaybackSession._engineOwners[engine], this)) return;
    // The engine may have dropped its position with the media; the last
    // one it reported is the floor, for a reload and for a failure said.
    final now = _display(engine.position).inMilliseconds;
    final last = _display(_lastPosition).inMilliseconds;
    final at = now > last ? now : last;
    final refusal = failure.refusal;
    final curable = refusal != null
        ? _curedByMint(refusal)
        : failure.fault == MediaFault.transport || _streamStale;
    if (_info == null ||
        !curable ||
        _recoveries >= PlaybackSession._recoveryBudget) {
      _announceFailed(
        _surfaced(failure),
        meantToPlay: failure.wasPlaying,
        atMs: at,
      );
      return;
    }
    _recoveries++;
    _recoveredAtMs = at;
    unawaited(_recover(at, resume: failure.wasPlaying));
  }

  /// Reloads at [atMs], where the listener stood, for a failure or a
  /// token that lapsed, and says the failure from there when that does
  /// not work. Answers whether it landed.
  Future<bool> _recover(int atMs, {required bool resume}) async {
    try {
      await _reload(atMs: atMs, resume: resume);
      return !_disposed;
    } on Object catch (error) {
      _announceFailed(error, meantToPlay: _resumeWanted, atMs: atMs);
      return false;
    }
  }

  /// Fetches the skip map for the loaded file. Pending maps, and the
  /// refusal of a server whose streaming engine is away (its analysis
  /// waits for the engine), get exactly one retry after
  /// [skipMapRetryDelay]; anything else leaves trimming inert for this
  /// load.
  Future<void> _loadSkipMap() async {
    _skipMapRetry?.cancel();
    final requestedPart = _partIndex;
    bool pending;
    try {
      final map = await repository.getSkipMap(
        item.pid,
        partIndex: requestedPart,
      );
      if (_disposed || requestedPart != _partIndex) return;
      if (map.ready) {
        _skipSpans = map.spans;
        _lastJumpedSpan = -1;
        return;
      }
      pending = map.state == 'pending';
    } on WaxDeckApiException catch (error) {
      if (_disposed || requestedPart != _partIndex) return;
      pending =
          error.code == 'feature-unavailable' &&
          error.params?['feature'] == 'streaming-engine';
    }
    if (pending && !_skipMapRetried) {
      _skipMapRetried = true;
      _skipMapRetry = Timer(skipMapRetryDelay, () {
        unawaited(_loadSkipMap());
      });
    }
  }
}
