part of '../playback_session.dart';

/// Listen accounting: the open listen session, its checkpoints and its report.
extension _SessionListen on PlaybackSession {
  /// Mints the idempotency ID the first time playback makes progress and
  /// whenever a new run starts after the previous session was reported.
  void _ensureSession() {
    if (_sessionId != null) return;
    _sessionId = newListenSessionId();
    _startedAt = DateTime.now().toUtc();
    _msPlayed = 0;
    _skippedAtSessionStart = hoursSavedMs.value;
    _speedSavedAtSessionStart = _speedSavedMs;
  }

  /// Checkpoints [at] (engine timeline; defaults to the live position),
  /// reported to the server on the display timeline: books checkpoint
  /// book-timeline positions. The position is read now, the write waits
  /// its turn.
  Future<void> _checkpoint({Duration? at}) =>
      _checkpointMs(_display(at ?? engine.position).inMilliseconds);

  /// [_checkpoint] at a display-timeline position already read. Settles
  /// once that position, or a newer one queued behind it, is written.
  Future<void> _checkpointMs(int positionMs) {
    final waiting = _queuedCheckpoint ??= Completer<void>()..future.ignore();
    _queuedCheckpointMs = positionMs;
    if (!_writingCheckpoint) unawaited(_drainCheckpoints());
    return waiting.future;
  }

  Future<void> _drainCheckpoints() async {
    _writingCheckpoint = true;
    try {
      while (true) {
        final positionMs = _queuedCheckpointMs;
        final waiting = _queuedCheckpoint;
        if (positionMs == null || waiting == null) return;
        _queuedCheckpointMs = null;
        _queuedCheckpoint = null;
        try {
          await _writeCheckpoint(positionMs);
          waiting.complete();
        } on Object catch (error, stack) {
          debugPrint('checkpoint failed: $error');
          waiting.completeError(error, stack);
        }
      }
    } finally {
      _writingCheckpoint = false;
    }
  }

  Future<void> _writeCheckpoint(int positionMs) async {
    try {
      await repository.putPlayState(item.pid, positionMs);
    } on WaxDeckApiException {
      // ANY failure queues, deliberately broader than the reachability
      // gate elsewhere: queued checkpoints replay with recordedAt and
      // reconcile server-side, flushOutbox drops permanent rejections,
      // and a transient auth failure would otherwise silently lose the
      // position. Without an engine (web), best effort stands and the
      // next checkpoint catches up.
      await sync?.queueCheckpoint(item.pid, positionMs);
    }
  }

  /// Milliseconds of content this listen session did not sit through,
  /// for the server's time-saved counter.
  ///
  /// The two things the field is defined as, added: what trimming jumped
  /// over, and what playing faster than the recording gave back. Both
  /// are accumulated where they happen - the jump that skipped a span
  /// adds its own length, and every counted delta is priced at the rate
  /// it was heard at - so this is a sum rather than a measurement.
  ///
  /// It is deliberately *not* content minus wall clock, which is the
  /// obvious formulation and is wrong twice over. A trim jump and a hand
  /// on the seek bar look identical as a position delta, so content read
  /// off raw movement counts a scrub through an hour as an hour saved.
  /// And wall clock counts every second that passed, including the ones
  /// that saved nobody anything: a rebuffer, a phone that slept, a
  /// browser tab throttled in the background. Subtracting those would
  /// let a stalled stream eat a real saving and report zero beside a
  /// trim chip saying thirty seconds.
  int _timeSavedMs() {
    final trimmed = hoursSavedMs.value - _skippedAtSessionStart;
    final faster = _speedSavedMs - _speedSavedAtSessionStart;
    return (trimmed > 0 ? trimmed : 0) + (faster > 0 ? faster : 0);
  }

  /// Reports the open session once. One that does not reach the server
  /// waits in the sync engine's queue, or where there is none in the
  /// listen outbox, until it does; the server deduplicates on the session
  /// ID, so a report sent twice never counts twice.
  Future<void> _reportSession({required bool finished}) async {
    final sessionId = _sessionId;
    final startedAt = _startedAt;
    _sessionId = null;
    _startedAt = null;
    if (sessionId == null || startedAt == null || _msPlayed <= 0) return;
    final skipped = _timeSavedMs();
    final session = ListenSession(
      sessionId: sessionId,
      pid: item.pid,
      startedAt: startedAt,
      msPlayed: _msPlayed,
      skippedMs: skipped > 0 ? skipped : null,
      finished: finished,
      client: clientId,
    );
    _msPlayed = 0;
    _finished = false;
    try {
      await repository.reportListens([session]);
      // The server is answering: whatever an earlier report left behind
      // goes now.
      unawaited(listenOutbox?.flush(repository));
    } on WaxDeckApiException catch (error) {
      final engine = sync;
      if (engine != null) {
        await engine.queueListen(session);
      } else if (!error.isRefusal) {
        // A refusal is the server's answer (a session signed out mid-flight
        // answers 401), not a report waiting for the server to come back.
        listenOutbox?.keep(session);
      }
    }
  }
}
