import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
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
    this.sync,
    this.downloads,
    this.checkpointInterval = const Duration(seconds: 5),
  });

  final WaxDeckRepository repository;
  final AudioEnginePort engine;
  final ItemSummary item;
  final String clientId;

  /// The sync engine, when this platform runs one: offline mutations
  /// queue through it instead of being dropped.
  final SyncEngine? sync;

  /// Downloaded originals, for playback when the server is unreachable.
  final DownloadManagerPort? downloads;
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
  /// position when there is one, and starts playing. When the server is
  /// unreachable and the item's original is downloaded, playback runs
  /// from the local file with the mirrored resume position instead.
  Future<void> start() async {
    _engineOwners[engine] = this;
    String url;
    String? mimeType;
    int savedMs;
    try {
      final info = await repository.getPlayInfo(item.pid);
      final saved = await repository.getPlayState(item.pid);
      _playInfo = info;
      url = info.url;
      mimeType = info.mimeType;
      savedMs = saved.positionMs;
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (local == null) rethrow;
      url = Uri.file(local.paths.first).toString();
      final saved = await sync?.localPlayState(item.pid);
      savedMs = saved?.positionMs ?? 0;
    }
    final resumeAt = savedMs > 0 ? Duration(milliseconds: savedMs) : null;
    await engine.load(url, mimeType: mimeType, initialPosition: resumeAt);
    _lastPosition = engine.position;
    _positionSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(_onPlayingChanged);
    _completedSub = engine.completed.listen((_) => _onCompleted());
    await engine.play();
  }

  /// The downloaded original, but only for failures that smell like
  /// unreachability; a real API rejection (404, 401) propagates.
  Future<LocalPlayback?> _localFallback(WaxDeckApiException e) async {
    final port = downloads;
    if (port == null) return null;
    if (e.statusCode != null && e.statusCode != 503) return null;
    return port.localFor(item.pid);
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
    final position = at ?? engine.position;
    try {
      await repository.putPlayState(item.pid, position.inMilliseconds);
    } on WaxDeckApiException {
      // ANY failure queues, deliberately broader than the reachability
      // gate elsewhere: queued checkpoints replay with recordedAt and
      // reconcile server-side, flushOutbox drops permanent rejections,
      // and a transient auth failure would otherwise silently lose the
      // position. Without an engine (web), best effort stands and the
      // next checkpoint catches up.
      await sync?.queueCheckpoint(item.pid, position.inMilliseconds);
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
      final engine = sync;
      if (engine != null) {
        await engine.queueListen(session);
      } else {
        _pendingRetry = session;
      }
    }
  }

  Future<void> _flushRetry() async {
    final retry = _pendingRetry;
    if (retry == null) return;
    _pendingRetry = null;
    try {
      await repository.reportListens([retry]);
    } on WaxDeckApiException {
      // Web only (native queues instead of retrying): gone for good
      // once the session ends.
    }
  }
}
