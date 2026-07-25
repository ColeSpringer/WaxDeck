import 'dart:async';

import 'package:waxdeck_player/waxdeck_player.dart';

/// Deterministic in-memory engine for tests.
///
/// Time never passes on its own: tests drive playback with [advance], so
/// every assertion about position, accounting, and completion is exact.
class FakeEngine implements AudioEnginePort {
  FakeEngine({this.mediaDuration = const Duration(minutes: 3)});

  /// Duration assigned to whatever gets loaded next.
  Duration mediaDuration;

  /// Last URL passed to [load], for assertions.
  String? loadedUrl;

  /// The clip window the last [load] carried, when any.
  Duration? loadedClipStart;
  Duration? loadedClipEnd;

  /// Last MIME hint passed to [load], for assertions.
  String? loadedMimeType;

  /// What [preloadNext] put behind the loaded item, or null when nothing
  /// is preloaded. Cleared when the boundary is crossed, so these read
  /// as the item waiting, never the one playing.
  String? preloadedUrl;
  String? preloadedMimeType;
  Duration? preloadedClipStart;
  Duration? preloadedClipEnd;

  /// Whether [dispose] has run.
  bool disposed = false;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _playings = StreamController<bool>.broadcast();
  final _states = StreamController<EngineProcessingState>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _boundaries = StreamController<void>.broadcast();
  final _speeds = StreamController<double>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration;

  /// Duration the preloaded item takes on when it is crossed into,
  /// resolved at [preloadNext] time from the [mediaDuration] then in
  /// force and the window it carried.
  Duration? _preloadedDuration;
  bool _playing = false;
  double _speed = 1.0;
  double _volume = 1.0;
  EngineProcessingState _state = EngineProcessingState.idle;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Duration? get duration => _duration;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  bool get playing => _playing;

  @override
  Stream<bool> get playingStream => _playings.stream;

  @override
  EngineProcessingState get processingState => _state;

  @override
  Stream<EngineProcessingState> get processingStateStream => _states.stream;

  @override
  Stream<void> get completed => _completions.stream;

  @override
  Stream<void> get itemBoundary => _boundaries.stream;

  @override
  double get speed => _speed;

  @override
  Stream<double> get speedStream => _speeds.stream;

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (!_speeds.isClosed) _speeds.add(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  double get volume => _volume;

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    // A fresh load starts a fresh window, preload included.
    await clearPreload();
    loadedUrl = url;
    loadedMimeType = mimeType;
    loadedClipStart = clipStart;
    loadedClipEnd = clipEnd;
    _setState(EngineProcessingState.loading);
    _duration = _windowDuration(clipStart, clipEnd);
    if (!_durations.isClosed) _durations.add(_duration);
    _setPosition(initialPosition ?? Duration.zero);
    _setState(EngineProcessingState.ready);
  }

  @override
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    // Nothing loaded means nothing to follow, exactly as the real engine
    // treats an empty source list.
    if (loadedUrl == null) return;
    preloadedUrl = url;
    preloadedMimeType = mimeType;
    preloadedClipStart = clipStart;
    preloadedClipEnd = clipEnd;
    _preloadedDuration = _windowDuration(clipStart, clipEnd);
  }

  @override
  Future<void> clearPreload() async {
    preloadedUrl = null;
    preloadedMimeType = null;
    preloadedClipStart = null;
    preloadedClipEnd = null;
    _preloadedDuration = null;
  }

  /// Duration an item plays for: its clip window, or the whole media.
  Duration _windowDuration(Duration? clipStart, Duration? clipEnd) {
    if (clipStart == null && clipEnd == null) return mediaDuration;
    final start = clipStart ?? Duration.zero;
    final end = clipEnd ?? mediaDuration;
    // Floor at zero: a window past the media's end plays nothing, never
    // a negative duration.
    return end > start ? end - start : Duration.zero;
  }

  @override
  Future<void> play() async {
    if (_state == EngineProcessingState.completed) {
      // Match real engines: replay after completion restarts from the top.
      _setPosition(Duration.zero);
      _setState(EngineProcessingState.ready);
    }
    _setPlaying(true);
  }

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> seek(Duration position) async {
    final max = _duration ?? position;
    _setPosition(
      position < Duration.zero
          ? Duration.zero
          : (position > max ? max : position),
    );
  }

  @override
  Future<void> stop() async {
    _setPlaying(false);
    _setState(EngineProcessingState.idle);
    // Stopping releases the media, and the window with it.
    await clearPreload();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _setPlaying(false);
    // Closes are not awaited: a listener-free broadcast controller hands
    // back the root-zone done future, which never resumes inside the
    // fake-async zone widget tests run in.
    unawaited(_positions.close());
    unawaited(_durations.close());
    unawaited(_playings.close());
    unawaited(_states.close());
    unawaited(_completions.close());
    unawaited(_boundaries.close());
    unawaited(_speeds.close());
  }

  /// Advances the manual clock by [amount] of wall time.
  ///
  /// Media time advances proportionally to the playback speed: at 2.0x,
  /// one second of wall time covers two seconds of media, exactly like a
  /// real engine. Does nothing while paused. Reaching the end of the
  /// media rolls into the preloaded item when there is one, firing
  /// [itemBoundary]; with nothing preloaded it fires [completed] and
  /// leaves the engine in the completed state with playback stopped.
  void advance(Duration amount) {
    if (!_playing || _state != EngineProcessingState.ready) return;
    var remaining = amount * _speed;
    while (true) {
      final end = _duration;
      final target = _position + remaining;
      if (end == null || target < end) {
        _setPosition(target);
        return;
      }
      if (preloadedUrl == null) {
        _setPosition(end);
        _setPlaying(false);
        _setState(EngineProcessingState.completed);
        if (!_completions.isClosed) _completions.add(null);
        return;
      }
      // Sample-adjacent: the media time that ran past the end of the
      // item plays out at the head of the preloaded one, with no pause
      // and no reload in between. Only one item is ever preloaded, so
      // this rolls at most once before the loop ends or completes.
      remaining = target - end;
      _crossBoundary();
    }
  }

  /// Makes the preloaded item the loaded one, as the engine walking into
  /// it does.
  void _crossBoundary() {
    loadedUrl = preloadedUrl;
    loadedMimeType = preloadedMimeType;
    loadedClipStart = preloadedClipStart;
    loadedClipEnd = preloadedClipEnd;
    _duration = _preloadedDuration;
    preloadedUrl = null;
    preloadedMimeType = null;
    preloadedClipStart = null;
    preloadedClipEnd = null;
    _preloadedDuration = null;
    if (!_durations.isClosed) _durations.add(_duration);
    _setPosition(Duration.zero);
    if (!_boundaries.isClosed) _boundaries.add(null);
  }

  void _setPosition(Duration position) {
    _position = position;
    if (!_positions.isClosed) _positions.add(position);
  }

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    if (!_playings.isClosed) _playings.add(playing);
  }

  void _setState(EngineProcessingState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
