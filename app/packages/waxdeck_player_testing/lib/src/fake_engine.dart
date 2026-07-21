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

  /// Whether [dispose] has run.
  bool disposed = false;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _playings = StreamController<bool>.broadcast();
  final _states = StreamController<EngineProcessingState>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _speeds = StreamController<double>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration;
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
    loadedUrl = url;
    loadedMimeType = mimeType;
    loadedClipStart = clipStart;
    loadedClipEnd = clipEnd;
    _setState(EngineProcessingState.loading);
    if (clipStart != null || clipEnd != null) {
      final start = clipStart ?? Duration.zero;
      final end = clipEnd ?? mediaDuration;
      // Floor at zero: a window past the media's end plays nothing,
      // never a negative duration.
      _duration = end > start ? end - start : Duration.zero;
    } else {
      _duration = mediaDuration;
    }
    if (!_durations.isClosed) _durations.add(_duration);
    _setPosition(initialPosition ?? Duration.zero);
    _setState(EngineProcessingState.ready);
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
    unawaited(_speeds.close());
  }

  /// Advances the manual clock by [amount] of wall time.
  ///
  /// Media time advances proportionally to the playback speed: at 2.0x,
  /// one second of wall time covers two seconds of media, exactly like a
  /// real engine. Does nothing while paused. Reaching the end of the media
  /// fires [completed] and leaves the engine in the completed state with
  /// playback stopped.
  void advance(Duration amount) {
    if (!_playing || _state != EngineProcessingState.ready) return;
    final end = _duration;
    final target = _position + amount * _speed;
    if (end != null && target >= end) {
      _setPosition(end);
      _setPlaying(false);
      _setState(EngineProcessingState.completed);
      if (!_completions.isClosed) _completions.add(null);
    } else {
      _setPosition(target);
    }
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
