import 'dart:async';

import 'package:flutter/foundation.dart';
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
///
/// Spoken-word items add item-scoped playback config on top: per-show and
/// per-book speed memory, silence trimming from server skip maps, episode
/// intro/outro skipping, and multi-part audiobooks. For books every
/// position this class reports to the server is a book-timeline
/// millisecond (part start plus the in-part engine position).
class PlaybackSession {
  PlaybackSession({
    required this.repository,
    required this.engine,
    required this.item,
    required this.clientId,
    this.sync,
    this.downloads,
    this.checkpointInterval = const Duration(seconds: 5),
    this.initialPositionMs,
    this.skipMapRetryDelay = const Duration(seconds: 30),
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

  /// Overrides the saved resume position (book resume, chapter start).
  /// For books this is a book-timeline millisecond.
  final int? initialPositionMs;

  /// How long to wait before the single retry of a pending skip map.
  final Duration skipMapRetryDelay;

  /// Position deltas above this are treated as seeks, not listening.
  static const maxCountedStep = Duration(seconds: 2);

  /// How early before a silence span the trim jump may fire, absorbing
  /// position-stream granularity.
  static const trimWindowMs = 250;

  /// Which session currently owns each (shared) engine. A disposed
  /// session must not stop an engine a newer session has taken over.
  static final Expando<PlaybackSession> _engineOwners = Expando('engine owner');

  PlayInfo? _playInfo;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<void>? _completedSub;
  Timer? _checkpointTimer;
  Timer? _skipMapRetry;

  Duration _lastPosition = Duration.zero;
  String? _sessionId;
  DateTime? _startedAt;
  int _msPlayed = 0;
  bool _finished = false;
  ListenSession? _pendingRetry;
  bool _disposed = false;

  // Item-scoped playback config, fetched on start and tolerated missing.
  SubscriptionSettings? _showSettings;
  BookDetail? _book;
  BookSettings? _bookSettings;

  // Multi-part book state. _partStartMs stays 0 for single-file items so
  // display arithmetic is uniform.
  int? _partIndex;
  int? _partCount;
  int _partStartMs = 0;

  // Silence trimming. Spans are in the loaded file's own timeline.
  List<SkipSpan> _skipSpans = const [];
  int _lastJumpedSpan = -1;
  bool _skipMapRetried = false;

  // Episode outro cutoff, in the file timeline; null when unset.
  int? _outroCutoffMs;
  bool _outroFired = false;

  /// Whether silence trimming is currently on, for the player chip.
  final ValueNotifier<bool> trimEnabled = ValueNotifier(false);

  /// Milliseconds of silence skipped so far, for the hours-saved badge.
  final ValueNotifier<int> hoursSavedMs = ValueNotifier(0);

  /// The book detail behind an audiobook session (chapters, parts), when
  /// it could be fetched.
  BookDetail? get book => _book;

  bool get _isBook => item.mediaType == MediaType.audiobook;

  /// Whether this item carries spoken-word playback affordances.
  bool get isSpokenWord => item.mediaType != MediaType.music;

  /// Current playback speed multiplier.
  double get speed => engine.speed;

  /// Duration to render the seek bar against: the whole book timeline
  /// for audiobooks, the loaded media otherwise.
  Duration get mediaDuration {
    if (_isBook) {
      final total = _book?.durationMs ?? item.durationMs;
      if (total > 0) return Duration(milliseconds: total);
    }
    return engine.duration ??
        Duration(milliseconds: _playInfo?.durationMs ?? 0);
  }

  /// Current position on the display timeline (book timeline for books).
  Duration get displayPosition => _display(engine.position);

  /// Position updates on the display timeline.
  Stream<Duration> get displayPositionStream =>
      engine.positionStream.map(_display);

  Duration _display(Duration enginePosition) =>
      Duration(milliseconds: _partStartMs + enginePosition.inMilliseconds);

  /// Fetches item config, play-info, and saved state, loads the stream at
  /// the resume position, and starts playing. When the server is
  /// unreachable and the item's original is downloaded, playback runs
  /// from the local file with the mirrored resume position instead.
  Future<void> start() async {
    _engineOwners[engine] = this;
    await _loadConfig();
    await engine.setSpeed(_configuredSpeed());
    try {
      var resumeMs = initialPositionMs;
      if (resumeMs == null) {
        final saved = await repository.getPlayState(item.pid);
        resumeMs = saved.positionMs;
      }
      if (_isBook) {
        await _loadPartFor(resumeMs, autoplay: false);
      } else {
        final info = await repository.getPlayInfo(item.pid);
        _playInfo = info;
        _applyOutroCutoff(info.durationMs);
        resumeMs = _applyIntroSkip(resumeMs);
        final resumeAt = resumeMs > 0 ? Duration(milliseconds: resumeMs) : null;
        // A span means the URL carries the whole backing file (direct
        // playback of a carved track); the engine clips to the window
        // and every position stays track-relative.
        await engine.load(
          info.url,
          mimeType: info.mimeType,
          initialPosition: resumeAt,
          clipStart: info.spanStartMs == null
              ? null
              : Duration(milliseconds: info.spanStartMs!),
          clipEnd: info.spanEndMs == null
              ? null
              : Duration(milliseconds: info.spanEndMs!),
        );
        if (trimEnabled.value) unawaited(_loadSkipMap());
      }
    } on WaxDeckApiException catch (e) {
      final local = await _localFallback(e);
      if (local == null) rethrow;
      final saved = await sync?.localPlayState(item.pid);
      var resumeMs = initialPositionMs ?? saved?.positionMs ?? 0;
      if (!_isBook) resumeMs = _applyIntroSkip(resumeMs);
      final resumeAt = resumeMs > 0 ? Duration(milliseconds: resumeMs) : null;
      // Downloaded originals carry the same window; clipping here is
      // what makes an offline carved track play as itself instead of
      // the whole rip.
      await engine.load(
        Uri.file(local.paths.first).toString(),
        initialPosition: resumeAt,
        clipStart: local.spanStartMs == null
            ? null
            : Duration(milliseconds: local.spanStartMs!),
        // The server closes open-ended windows now; the zero guard
        // covers download records stored before it did (an open clip
        // end plays to the file's end, which is what those meant).
        clipEnd: local.spanEndMs == null || local.spanEndMs! <= 0
            ? null
            : Duration(milliseconds: local.spanEndMs!),
      );
    }
    _lastPosition = engine.position;
    _positionSub = engine.positionStream.listen(_onPosition);
    _playingSub = engine.playingStream.listen(_onPlayingChanged);
    _completedSub = engine.completed.listen((_) => _onCompleted());
    await engine.play();
  }

  /// Fetches the per-show or per-book playback config; playback works
  /// without it, so any failure just leaves the defaults in place.
  Future<void> _loadConfig() async {
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final detail = await repository.getPodcast(it.showPid);
        _showSettings = detail.settings;
      } else if (_isBook) {
        final detail = await repository.getBook(item.pid);
        _book = detail;
        _bookSettings = detail.settings;
      }
    } on WaxDeckApiException {
      // Defaults apply; the player still plays.
    }
    trimEnabled.value = _isBook
        ? (_bookSettings?.trimSilence ?? false)
        : (_showSettings?.trimSilence ?? false);
  }

  double _configuredSpeed() {
    final configured = _isBook ? _bookSettings?.speed : _showSettings?.speed;
    return configured ?? 1.0;
  }

  /// Episodes with a skip-intro setting start at the intro end unless the
  /// resume point is already past it.
  int _applyIntroSkip(int resumeMs) {
    final intro = _showSettings?.skipIntroSeconds;
    if (intro == null || intro <= 0) return resumeMs;
    final introMs = intro * 1000;
    return resumeMs > introMs ? resumeMs : introMs;
  }

  void _applyOutroCutoff(int durationMs) {
    final outro = _showSettings?.skipOutroSeconds;
    if (outro == null || outro <= 0 || durationMs <= 0) return;
    final cutoff = durationMs - outro * 1000;
    if (cutoff > 0) _outroCutoffMs = cutoff;
  }

  /// Resolves and loads the part containing book-timeline [bookMs]
  /// (single-file items resolve to the whole file with partStartMs 0).
  Future<void> _loadPartFor(int bookMs, {required bool autoplay}) async {
    final info = await repository.getPlayInfo(item.pid, positionMs: bookMs);
    _playInfo = info;
    _partIndex = info.partIndex;
    _partCount = info.partCount;
    _partStartMs = info.partStartMs ?? 0;
    _skipSpans = const [];
    _lastJumpedSpan = -1;
    _skipMapRetried = false;
    final inPartMs = bookMs - _partStartMs;
    await engine.load(
      info.url,
      mimeType: info.mimeType,
      initialPosition: inPartMs > 0 ? Duration(milliseconds: inPartMs) : null,
    );
    _lastPosition = engine.position;
    if (trimEnabled.value) unawaited(_loadSkipMap());
    if (autoplay) await engine.play();
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

  /// Seeks to a display-timeline position: the book timeline for books
  /// (crossing into another part re-resolves play-info), the media
  /// timeline otherwise.
  Future<void> seek(Duration position) async {
    final targetMs = position.inMilliseconds;
    final partDurationMs = _playInfo?.durationMs ?? 0;
    final withinPart =
        _partIndex == null ||
        (targetMs >= _partStartMs && targetMs <= _partStartMs + partDurationMs);
    if (withinPart) {
      await engine.seek(Duration(milliseconds: targetMs - _partStartMs));
    } else {
      await _loadPartFor(targetMs, autoplay: engine.playing);
    }
  }

  /// Sets the playback speed now and, for episodes and books, persists it
  /// as the item's remembered speed. Music never persists.
  Future<void> setSpeed(double speed, {bool persist = true}) async {
    await engine.setSpeed(speed);
    if (!persist) return;
    try {
      final it = item;
      if (item.mediaType == MediaType.podcast && it is EpisodeSummary) {
        final current = _showSettings;
        if (current == null) return;
        final updated = SubscriptionSettings(
          retentionKeep: current.retentionKeep,
          autoDownload: current.autoDownload,
          folder: current.folder,
          private: current.private,
          speed: speed,
          trimSilence: current.trimSilence,
          voiceBoost: current.voiceBoost,
          skipIntroSeconds: current.skipIntroSeconds,
          skipOutroSeconds: current.skipOutroSeconds,
        );
        _showSettings = updated;
        await repository.putSubscriptionSettings(it.showPid, updated);
      } else if (_isBook) {
        final current = _bookSettings ?? const BookSettings();
        final updated = BookSettings(
          speed: speed,
          voiceBoost: current.voiceBoost,
          trimSilence: current.trimSilence,
        );
        _bookSettings = updated;
        await repository.putBookSettings(item.pid, updated);
      }
    } on WaxDeckApiException {
      // The runtime speed stands; remembering it is best effort.
    }
  }

  /// Turns silence trimming on or off for this session.
  void setTrimEnabled(bool on) {
    trimEnabled.value = on;
    if (on && _skipSpans.isEmpty) {
      unawaited(_loadSkipMap());
    }
  }

  /// Fetches the skip map for the loaded file. Pending maps get exactly
  /// one retry after [skipMapRetryDelay]; anything else leaves trimming
  /// inert for this load.
  Future<void> _loadSkipMap() async {
    _skipMapRetry?.cancel();
    final requestedPart = _partIndex;
    try {
      final map = await repository.getSkipMap(
        item.pid,
        partIndex: requestedPart,
      );
      if (_disposed || requestedPart != _partIndex) return;
      if (map.ready) {
        _skipSpans = map.spans;
        _lastJumpedSpan = -1;
      } else if (map.state == 'pending' && !_skipMapRetried) {
        _skipMapRetried = true;
        _skipMapRetry = Timer(skipMapRetryDelay, () {
          unawaited(_loadSkipMap());
        });
      }
    } on WaxDeckApiException {
      // Unavailable or unreachable: trimming stays off for this load.
    }
  }

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
    _skipMapRetry?.cancel();
    // Cancellations are not awaited: an idle subscription's cancel future is
    // the root-zone null future, which never resumes inside the fake-async
    // zone widget tests run in. Cancelling takes effect synchronously.
    unawaited(_positionSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_completedSub?.cancel());
    await _checkpoint(at: finalPosition);
    await _reportSession(finished: _finished);
    await _flushRetry();
    trimEnabled.dispose();
    hoursSavedMs.dispose();
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
    _maybeTrimJump(position);
    _maybeOutroStop(position);
  }

  /// Entering a mapped silence span jumps forward to its end. Jumps only
  /// ever go forward and each span fires at most once per load, so a
  /// stubborn backend that lands short of the target cannot loop.
  void _maybeTrimJump(Duration position) {
    if (!trimEnabled.value || _skipSpans.isEmpty) return;
    final ms = position.inMilliseconds;
    for (var i = _lastJumpedSpan + 1; i < _skipSpans.length; i++) {
      final span = _skipSpans[i];
      if (ms >= span.startMs - trimWindowMs && ms < span.endMs) {
        _lastJumpedSpan = i;
        hoursSavedMs.value += span.endMs - ms;
        unawaited(engine.seek(Duration(milliseconds: span.endMs)));
        return;
      }
    }
  }

  /// Crossing the outro cutoff ends the episode as completed: the tail
  /// is credits the caller asked to skip.
  void _maybeOutroStop(Duration position) {
    final cutoff = _outroCutoffMs;
    if (cutoff == null || _outroFired) return;
    if (position.inMilliseconds < cutoff) return;
    _outroFired = true;
    _finished = true;
    unawaited(engine.pause());
    // The checkpoint records the real end so resume lands past the outro.
    final endMs = _playInfo?.durationMs ?? position.inMilliseconds;
    unawaited(_checkpoint(at: Duration(milliseconds: endMs)));
    unawaited(_reportSession(finished: true));
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
    final index = _partIndex;
    final count = _partCount;
    if (index != null && count != null && index < count - 1) {
      // The book has more parts: roll into the next one seamlessly.
      unawaited(_advanceToNextPart());
      return;
    }
    _finished = true;
    unawaited(_checkpoint());
    unawaited(_reportSession(finished: true));
  }

  Future<void> _advanceToNextPart() async {
    final nextStartMs = _partStartMs + (_playInfo?.durationMs ?? 0);
    try {
      await _loadPartFor(nextStartMs, autoplay: true);
    } on WaxDeckApiException {
      // The next part cannot be resolved (server unreachable): end the
      // session honestly where it stopped.
      _finished = true;
      unawaited(_checkpoint());
      unawaited(_reportSession(finished: true));
    }
  }

  /// Mints the idempotency ID the first time playback makes progress and
  /// whenever a new run starts after the previous session was reported.
  void _ensureSession() {
    if (_sessionId != null) return;
    _sessionId = newListenSessionId();
    _startedAt = DateTime.now().toUtc();
    _msPlayed = 0;
  }

  /// Checkpoints [at] (engine timeline; defaults to the live position),
  /// reported to the server on the display timeline: books checkpoint
  /// book-timeline positions.
  Future<void> _checkpoint({Duration? at}) async {
    final position = _display(at ?? engine.position);
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
