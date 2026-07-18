import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// Drives one item's playback through the engine port and owns the server
/// bookkeeping around it: resume on open, position checkpoints, and listen
/// session accounting.
///
/// Listen accounting counts media time actually heard, not wall clock:
/// position deltas are accumulated only while playing and only when small
/// enough to be normal playback progress, so pauses contribute nothing and
/// a seek's jump is never counted as listening.
class PlaybackSession {
  PlaybackSession({
    required this.repository,
    required this.engine,
    required this.item,
    required this.clientId,
    this.checkpointInterval = const Duration(seconds: 5),
  });

  final WaxDeckRepository repository;
  final AudioEnginePort engine;
  final ItemSummary item;
  final String clientId;
  final Duration checkpointInterval;

  /// Position deltas above this are treated as seeks, not listening.
  static const maxCountedStep = Duration(seconds: 2);

  /// Which session currently owns each (shared) engine. A disposed
  /// session must not stop an engine a newer session has taken over.
  static final Expando<PlaybackSession> _engineOwners = Expando('engine owner');

  PlayInfo? _playInfo;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<void>? _completedSub;
  Timer? _checkpointTimer;

  Duration _lastPosition = Duration.zero;
  String? _sessionId;
  DateTime? _startedAt;
  int _msPlayed = 0;
  bool _finished = false;
  ListenSession? _pendingRetry;
  bool _disposed = false;

  /// Duration to render the seek bar against.
  Duration get mediaDuration =>
      engine.duration ?? Duration(milliseconds: _playInfo?.durationMs ?? 0);

  /// Fetches play-info and saved state, loads the stream at the saved resume
  /// position when there is one, and starts playing.
  Future<void> start() async {
    _engineOwners[engine] = this;
    final info = await repository.getPlayInfo(item.pid);
    final saved = await repository.getPlayState(item.pid);
    _playInfo = info;
    final resumeAt = saved.positionMs > 0
        ? Duration(milliseconds: saved.positionMs)
        : null;
    await engine.load(
      info.url,
      mimeType: info.mimeType,
      initialPosition: resumeAt,
    );
    _lastPosition = engine.position;
    _positionSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(_onPlayingChanged);
    _completedSub = engine.completed.listen((_) => _onCompleted());
    await engine.play();
  }

  Future<void> toggle() async {
    if (engine.playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Future<void> seek(Duration position) => engine.seek(position);

  /// Stops playback, flushing a final checkpoint and the listen report.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Snapshot the position now, synchronously: the engine is shared, and
    // by the time the awaits below run a newer session may have loaded
    // different media into it. The checkpoint must record where THIS
    // item was, and stop() must not cut off the newer session.
    final finalPosition = engine.position;
    _checkpointTimer?.cancel();
    // Cancellations are not awaited: an idle subscription's cancel future is
    // the root-zone null future, which never resumes inside the fake-async
    // zone widget tests run in. Cancelling takes effect synchronously.
    unawaited(_positionSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    await _checkpoint(at: finalPosition);
    await _reportSession(finished: _finished);
    await _flushRetry();
    if (identical(_engineOwners[engine], this)) {
      _engineOwners[engine] = null;
      await engine.stop();
    }
  }

  void _onPosition(Duration position) {
    final delta = position - _lastPosition;
    _lastPosition = position;
    if (!engine.playing) return;
    if (delta > Duration.zero && delta <= maxCountedStep) {
      _ensureSession();
      _msPlayed += delta.inMilliseconds;
    }
  }

  void _onPlayingChanged(bool playing) {
    if (_disposed) return;
    if (playing) {
      _ensureSession();
      _checkpointTimer?.cancel();
      _checkpointTimer = Timer.periodic(
        checkpointInterval,
        (_) => _checkpoint(),
      );
    } else {
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      unawaited(_checkpoint());
    }
  }

  void _onCompleted() {
    if (_disposed) return;
    _finished = true;
    unawaited(_checkpoint());
    unawaited(_reportSession(finished: true));
  }

  /// Mints the idempotency ID the first time playback makes progress and
  /// whenever a new run starts after the previous session was reported.
  void _ensureSession() {
    if (_sessionId != null) return;
    _sessionId = newListenSessionId();
    _startedAt = DateTime.now().toUtc();
    _msPlayed = 0;
  }

  Future<void> _checkpoint({Duration? at}) async {
    try {
      final position = at ?? engine.position;
      await repository.putPlayState(item.pid, position.inMilliseconds);
    } on WaxDeckApiException {
      // Checkpoints are best effort; the next one will catch up.
    }
  }

  /// Reports the open session once. On network failure the session is kept
  /// and retried on dispose; the server deduplicates on the session ID, so
  /// the retry can never double-count.
  Future<void> _reportSession({required bool finished}) async {
    final sessionId = _sessionId;
    final startedAt = _startedAt;
    _sessionId = null;
    _startedAt = null;
    if (sessionId == null || startedAt == null || _msPlayed <= 0) return;
    final session = ListenSession(
      sessionId: sessionId,
      pid: item.pid,
      startedAt: startedAt,
      msPlayed: _msPlayed,
      finished: finished,
      client: clientId,
    );
    _msPlayed = 0;
    _finished = false;
    try {
      await repository.reportListens([session]);
    } on WaxDeckApiException {
      _pendingRetry = session;
    }
  }

  Future<void> _flushRetry() async {
    final retry = _pendingRetry;
    if (retry == null) return;
    _pendingRetry = null;
    try {
      await repository.reportListens([retry]);
    } on WaxDeckApiException {
      // Gone for good once the session ends; offline queueing comes later.
    }
  }
}
