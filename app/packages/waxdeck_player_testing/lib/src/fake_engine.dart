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

  /// Last MIME hint passed to [load], for assertions.
  String? loadedMimeType;

  /// Whether [dispose] has run.
  bool disposed = false;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _playings = StreamController<bool>.broadcast();
  final _states = StreamController<EngineProcessingState>.broadcast();
  final _completions = StreamController<void>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
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
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
  }) async {
    loadedUrl = url;
    loadedMimeType = mimeType;
    _setState(EngineProcessingState.loading);
    _duration = mediaDuration;
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
  }

  /// Advances the manual clock by [amount] of media time.
  ///
  /// Does nothing while paused, exactly like a real clock. Reaching the end
  /// of the media fires [completed] and leaves the engine in the completed
  /// state with playback stopped.
  void advance(Duration amount) {
    if (!_playing || _state != EngineProcessingState.ready) return;
    final end = _duration;
    final target = _position + amount;
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
