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

  /// Refuses the next [play] the way a browser refuses a programmatic
  /// resume: the request is dropped, nothing plays, and the reason
  /// arrives on [playbackRefused]. Cleared as it fires, so the tap that
  /// follows is allowed.
  bool refuseNextPlay = false;

  /// Fails the next [load] the way media that will not open fails: it
  /// throws, and nothing else about the engine moves. Cleared as it
  /// fires, so the load after it is allowed.
  ///
  /// A thrown load is what a dead stream or a deleted file looks like from
  /// here, and it is not a [WaxDeckApiException]: the server answered
  /// fine and the media is what did not. Callers that caught the API type
  /// alone are the ones this exists to catch out.
  bool failNextLoad = false;

  /// Fails the next [setVolume] the way a platform that will not take the
  /// write fails: it throws and the gain does not move. Cleared as it
  /// fires.
  bool failNextSetVolume = false;

  /// Holds the next [load] open until the test completes it, after its
  /// state has applied: a real platform swaps the source at dispatch and
  /// only its resolution takes time, so a caller parked in a load has
  /// already replaced what the engine holds. One-shot - consumed as it
  /// fires - so the load that takes over afterwards runs free.
  Completer<void>? loadGate;

  /// Fails the next [stop] the way a platform that will not release the
  /// media fails: it throws and nothing about the engine moves. Cleared
  /// as it fires.
  bool failNextStop = false;

  /// Holds [pause] open until the test completes it, so a caller can be
  /// caught still inside one.
  ///
  /// The flag drops before the gate, which is the order just_audio uses:
  /// it moves its playing flag and *then* asks the platform (see the note
  /// on the engine's refusal path). A caller suspended in a pause has
  /// therefore already published that it is not playing, which is what
  /// lets a second caller run straight past the pause and reach the code
  /// after it first. Null leaves [pause] as immediate as it has always
  /// been.
  Completer<void>? pauseGate;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _playings = StreamController<bool>.broadcast();
  final _states = StreamController<EngineProcessingState>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _boundaries = StreamController<void>.broadcast();
  final _refusals = StreamController<Object>.broadcast();
  final _speeds = StreamController<double>.broadcast();
  final _volumes = StreamController<double>.broadcast();

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
  Stream<Object> get playbackRefused => _refusals.stream;

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
    if (failNextSetVolume) {
      failNextSetVolume = false;
      throw const VolumeRefused();
    }
    _volume = volume;
    if (!_volumes.isClosed) _volumes.add(volume);
  }

  @override
  double get volume => _volume;

  /// Seeded, as the port requires and just_audio's behaviour subject is: a
  /// plain broadcast stream would draw full loudness in a test and the true
  /// level in the app.
  @override
  Stream<double> get volumeStream async* {
    yield _volume;
    yield* _volumes.stream;
  }

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw const MediaWillNotOpen();
    }
    // The real facade stops the transport before replacing sources (the
    // web platform's per-playlist player cache makes the stop
    // mandatory), so a session watching the engine hears playing go
    // false mid-load with the outgoing media's position still standing.
    // Announced before the first suspension so the event lands exactly
    // in that window, which is where a checkpoint fired off the pause
    // has to read the old timeline and not a half-updated one.
    _setPlaying(false);
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
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
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
    if (refuseNextPlay) {
      // The refusal is announced rather than thrown, which is the port's
      // contract: it lands after the request has been dispatched, so
      // nothing awaiting the start is waiting for it.
      refuseNextPlay = false;
      if (!_refusals.isClosed) _refusals.add(const _RefusedByPlatform());
      return;
    }
    if (_state == EngineProcessingState.completed) {
      // Match real engines: replay after completion restarts from the top.
      _setPosition(Duration.zero);
      _setState(EngineProcessingState.ready);
    }
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    _setPlaying(false);
    await pauseGate?.future;
  }

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
    if (failNextStop) {
      failNextStop = false;
      throw const MediaWillNotRelease();
    }
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
    unawaited(_refusals.close());
    unawaited(_speeds.close());
    unawaited(_volumes.close());
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

/// What [FakeEngine.refuseNextPlay] reports, standing in for the browser's
/// "play() failed because the user didn't interact with the document
/// first". Nothing reads its contents; the refusal itself is the signal.
class _RefusedByPlatform implements Exception {
  const _RefusedByPlatform();

  @override
  String toString() => 'the platform refused to start playback';
}

/// What [FakeEngine.failNextLoad] throws.
///
/// Public, so a test can name the failure it arranged rather than
/// asserting on whatever type happened to come out.
class MediaWillNotOpen implements Exception {
  const MediaWillNotOpen();

  @override
  String toString() => 'the media would not open';
}

/// What [FakeEngine.failNextSetVolume] throws. Public for the same
/// reason as [MediaWillNotOpen].
class VolumeRefused implements Exception {
  const VolumeRefused();

  @override
  String toString() => 'the platform would not take the level';
}

/// What [FakeEngine.failNextStop] throws. Public for the same reason as
/// [MediaWillNotOpen].
class MediaWillNotRelease implements Exception {
  const MediaWillNotRelease();

  @override
  String toString() => 'the media would not be released';
}
