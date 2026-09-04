import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../audio_engine_port.dart';
import '../timeline/timeline_media.dart';

/// Plays a minted timeline in a browser, through hls.js over Media
/// Source Extensions.
///
/// The reason this exists at all: a browser's `<audio>` element takes
/// one source, and changing it is a load and a gap however the change is
/// arranged. A timeline is one source that already contains the whole
/// queue, so the crossing is a position passing a number rather than a
/// media swap - which is the only way a browser crosses a track boundary
/// without a hole in the music.
///
/// hls.js is vendored and served from this origin (`web/vendor/`), and
/// the script is injected the first time a timeline is loaded: a
/// listener who never switches gapless playback on never fetches it.
class HlsTimelinePlayer implements TimelineAudioEngine {
  HlsTimelinePlayer({web.HTMLAudioElement? element, Duration? loadDeadline})
    : _audio =
          element ??
          (web.document.createElement('audio') as web.HTMLAudioElement),
      _loadDeadline = loadDeadline ?? const Duration(seconds: 15) {
    _audio.preload = 'auto';
    _listen('timeupdate', (_) => _tick());
    _listen('seeked', (_) => _tick());
    _listen('ended', (_) => _onEnded());
    _listen('play', (_) => _setPlaying(true));
    _listen('pause', (_) => _setPlaying(false));
  }

  /// Where the vendored script is served from, relative to the app's
  /// base href, so it works under a sub-path deployment too.
  static const String scriptPath = 'vendor/hls.min.js';

  /// The formats a timeline can be rendered in, in the order a browser
  /// should prefer them, paired with the codec strings MSE is asked
  /// about. Lossless first: bandwidth on a LAN is not the scarce thing,
  /// and a lossy re-encode of a lossless library is a loss the listener
  /// did not ask for. AAC last of the four because it is the one every
  /// browser has, so it is the fallback rather than the choice.
  static const Map<String, String> _codecs = <String, String>{
    'flac': 'audio/mp4; codecs="flac"',
    'alac': 'audio/mp4; codecs="alac"',
    'opus': 'audio/mp4; codecs="opus"',
    'aac': 'audio/mp4; codecs="mp4a.40.2"',
  };

  final web.HTMLAudioElement _audio;
  final Duration _loadDeadline;

  JSObject? _hls;
  TimelineMedia? _media;
  int _member = 0;
  bool _disposed = false;
  Timer? _ticker;

  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _playings = StreamController<bool>.broadcast();
  final _states = StreamController<EngineProcessingState>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _boundaries = StreamController<void>.broadcast();
  final _refusals = StreamController<Object>.broadcast();
  final _speeds = StreamController<double>.broadcast();
  final _volumes = StreamController<double>.broadcast();
  final _losses = StreamController<bool>.broadcast();
  final _timelineRefusals = StreamController<String>.broadcast();

  bool _playingFlag = false;
  EngineProcessingState _state = EngineProcessingState.idle;

  /// The level and the speed this engine was told to hold. Kept beside
  /// the element rather than read off it: attaching media resets an
  /// element's `playbackRate` to its default, so an engine that trusted
  /// the element would quietly hand a listener 1.0x on the next track
  /// after they chose 1.5x.
  double _speedValue = 1.0;
  double _volumeValue = 1.0;

  /// The element this player drives, so a composite engine can silence
  /// it without going through the port.
  web.HTMLAudioElement get element => _audio;

  /// Whether this browser can play a timeline at all: MSE, plus at
  /// least one format the mint can produce.
  bool get supported =>
      _hlsGlobal != null &&
      _isMSESupported() &&
      supportedTimelineFormats.isNotEmpty;

  @override
  List<String> get supportedTimelineFormats => <String>[
    for (final entry in _codecs.entries)
      if (web.MediaSource.isTypeSupported(entry.value)) entry.key,
  ];

  @override
  TimelineMedia? get loadedTimeline => _media;

  @override
  int get currentMember => _member;

  @override
  Stream<bool> get timelineLost => _losses.stream;

  @override
  Future<bool> prepareTimelines() async {
    await _ensureScript();
    return supported;
  }

  @override
  Stream<String> get timelineRefused => _timelineRefusals.stream;

  @override
  Future<void> loadTimeline(
    TimelineMedia media, {
    int member = 0,
    Duration? position,
    bool play = false,
  }) async {
    if (_disposed) return;
    final at = member.clamp(0, media.members.length - 1);
    if (_media?.url == media.url && _hls != null) {
      // The same stream: a move inside it is a seek, and there is
      // nothing to fetch. The swap at a seam is the one case that must
      // not pause on the way through.
      if (!play) _audio.pause();
      _media = media;
      await seekToMember(at, position ?? Duration.zero);
      return;
    }
    await _ensureScript();
    if (!supported) {
      throw MediaLoadException(
        MediaFault.source,
        StateError('this browser cannot play a timeline'),
      );
    }
    _teardownHls();
    _media = media;
    _member = at;
    _setState(EngineProcessingState.loading);
    final ready = Completer<void>();
    final hls = _newHls();
    _hls = hls;
    hls.callMethod<JSAny?>(
      'on'.toJS,
      'hlsError'.toJS,
      ((JSAny? _, JSObject data) => _onHlsError(data, ready)).toJS,
    );
    void onCanPlay(web.Event _) {
      if (!ready.isCompleted) ready.complete();
    }

    final canPlay = onCanPlay.toJS;
    _audio.addEventListener('canplay', canPlay);
    try {
      hls.callMethod<JSAny?>('attachMedia'.toJS, _audio);
      hls.callMethod<JSAny?>('loadSource'.toJS, media.url.toJS);
      _audio.currentTime = media.absolute(at, _msOf(position)) / 1000;
      await ready.future.timeout(_loadDeadline);
    } on TimeoutException catch (error) {
      _teardownHls();
      _media = null;
      _setState(EngineProcessingState.idle);
      throw MediaLoadException(MediaFault.transport, error);
    } on MediaLoadException {
      _teardownHls();
      _media = null;
      _setState(EngineProcessingState.idle);
      rethrow;
    } finally {
      _audio.removeEventListener('canplay', canPlay);
    }
    if (_disposed) return;
    // Set again after the manifest parsed: an element with no duration
    // yet clamps a seek to zero, and the position asked for is where
    // this member begins. The level and the speed go back on for the
    // same reason - attaching media reset them.
    _audio.currentTime = media.absolute(at, _msOf(position)) / 1000;
    _audio.playbackRate = _speedValue;
    _audio.volume = _volumeValue;
    _publishMember(at, emitBoundary: false);
    _setState(EngineProcessingState.ready);
    if (play) await this.play();
  }

  @override
  Future<void> seekToMember(int member, Duration position) async {
    final media = _media;
    if (media == null) return;
    final at = member.clamp(0, media.members.length - 1);
    _audio.currentTime = media.absolute(at, position.inMilliseconds) / 1000;
    _publishMember(at, emitBoundary: false, position: position);
  }

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    // A single item is not this engine's job: the composite routes it to
    // the standard one. Declared so the port is whole, and refused
    // rather than half-played.
    throw MediaLoadException(
      MediaFault.source,
      StateError('the timeline engine plays timelines, not single items'),
    );
  }

  @override
  bool get canPreload => false;

  @override
  Future<void> preloadNext(
    String url, {
    String? mimeType,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {}

  @override
  Future<void> clearPreload() async {}

  @override
  Future<void> play() async {
    if (_media == null) return;
    // A stream that ran off its end restarts the member playing, the
    // way the port says a play after completion does.
    if (_state == EngineProcessingState.completed) {
      final media = _media!;
      _audio.currentTime = media.offsetMs(_member) / 1000;
      _setState(EngineProcessingState.ready);
    }
    try {
      await _audio.play().toDart;
      _startTicker();
    } on Object catch (error) {
      // A browser refusing a resume no gesture led to. The media stays
      // where it is; only the start was turned down.
      if (!_refusals.isClosed) _refusals.add(error);
    }
  }

  @override
  Future<void> pause() async {
    _pauseNow();
  }

  /// Pauses and says so at once, rather than waiting for the element's
  /// own event. Every caller of this is a moment where `playing` has to
  /// read false by the time whatever caused it is announced - a pause,
  /// a lost stream, a refusal - and the event is a frame later.
  void _pauseNow() {
    _audio.pause();
    _stopTicker();
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    final media = _media;
    if (media == null) return;
    _audio.currentTime =
        media.absolute(_member, position.inMilliseconds) / 1000;
    _emitPosition(position);
  }

  @override
  Future<void> stop() async {
    _pauseNow();
    _teardownHls();
    _media = null;
    _member = 0;
    _setState(EngineProcessingState.idle);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    for (final c in <StreamController<Object?>>[
      _positions,
      _durations,
      _playings,
      _states,
      _completions,
      _boundaries,
      _refusals,
      _speeds,
      _volumes,
      _losses,
      _timelineRefusals,
    ]) {
      unawaited(c.close());
    }
  }

  @override
  Duration get position {
    final media = _media;
    if (media == null) return Duration.zero;
    return Duration(milliseconds: media.memberPosition(_member, _absoluteMs));
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Duration? get duration {
    final media = _media;
    if (media == null) return null;
    return Duration(milliseconds: media.memberDurationMs(_member));
  }

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  bool get playing => _playingFlag;

  @override
  Stream<bool> get playingStream => _playings.stream;

  @override
  EngineProcessingState get processingState => _state;

  @override
  Stream<EngineProcessingState> get processingStateStream => _states.stream;

  @override
  Stream<void> get completed => _completions.stream;

  @override
  Stream<Object> get playbackRefused => _refusals.stream;

  @override
  Stream<void> get itemBoundary => _boundaries.stream;

  @override
  Future<void> setSpeed(double speed) async {
    _speedValue = speed;
    _audio.playbackRate = speed;
    if (!_speeds.isClosed) _speeds.add(speed);
  }

  @override
  double get speed => _speedValue;

  @override
  Stream<double> get speedStream => _speeds.stream;

  @override
  Future<void> setVolume(double volume) async {
    _volumeValue = volume;
    _audio.volume = volume;
    if (!_volumes.isClosed) _volumes.add(volume);
  }

  @override
  double get volume => _volumeValue;

  @override
  Stream<double> get volumeStream async* {
    yield _volumeValue;
    yield* _volumes.stream;
  }

  // ---- internals ----

  int get _absoluteMs => (_audio.currentTime * 1000).round();

  int _msOf(Duration? position) => position?.inMilliseconds ?? 0;

  /// The `Hls` constructor, when the vendored script has run. Read off
  /// the window every time rather than cached: the browser suite plants
  /// a stub there, and a cache would pin whichever ran first.
  JSFunction? get _hlsGlobal => web.window.getProperty<JSFunction?>('Hls'.toJS);

  bool _isMSESupported() {
    final hls = _hlsGlobal;
    if (hls == null) return false;
    // Deliberately not `isSupported()`, which tests a video codec
    // string and answers false on a Chromium built without proprietary
    // codecs - a browser that plays every format this ever mints.
    final answer = hls.callMethod<JSBoolean?>('isMSESupported'.toJS);
    return answer?.toDart ?? false;
  }

  JSObject _newHls() {
    final config = JSObject();
    // fMP4 passthrough has nothing to transmux, so a worker buys
    // nothing and costs a blob URL the page's own policy would have to
    // permit.
    config['enableWorker'] = false.toJS;
    config['maxBufferLength'] = 60.toJS;
    // hls.js ignores Retry-After, so the two seconds the streaming
    // engine asks for is written here instead. Eight attempts covers a
    // sidecar restart without giving up on a listen.
    final policy = JSObject();
    final retry = JSObject();
    retry['maxNumRetry'] = 8.toJS;
    retry['retryDelayMs'] = 2000.toJS;
    retry['maxRetryDelayMs'] = 8000.toJS;
    retry['backoff'] = 'linear'.toJS;
    policy['default'] = _withRetry(retry);
    config['fragLoadPolicy'] = policy;
    config['manifestLoadPolicy'] = policy;
    config['playlistLoadPolicy'] = policy;
    final ctor = _hlsGlobal!;
    return ctor.callAsConstructor<JSObject>(config);
  }

  JSObject _withRetry(JSObject retry) {
    final out = JSObject();
    out['maxTimeToFirstByteMs'] = 10000.toJS;
    out['maxLoadTimeMs'] = 60000.toJS;
    out['timeoutRetry'] = retry;
    out['errorRetry'] = retry;
    return out;
  }

  Future<void> _ensureScript() async {
    if (_hlsGlobal != null) return;
    final existing = web.document.querySelector('script[data-waxdeck-hls]');
    if (existing == null) {
      final script =
          web.document.createElement('script') as web.HTMLScriptElement;
      script.src = scriptPath;
      script.setAttribute('data-waxdeck-hls', '');
      final loaded = Completer<void>();
      void done(web.Event _) {
        if (!loaded.isCompleted) loaded.complete();
      }

      script.addEventListener('load', done.toJS);
      script.addEventListener('error', done.toJS);
      web.document.head!.appendChild(script);
      await loaded.future.timeout(_loadDeadline, onTimeout: () {});
    } else {
      // Another load is already fetching it; wait for the global to
      // appear rather than injecting a second copy.
      for (var i = 0; i < 150 && _hlsGlobal == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  void _teardownHls() {
    final hls = _hls;
    _hls = null;
    if (hls == null) return;
    hls.callMethod<JSAny?>('stopLoad'.toJS);
    hls.callMethod<JSAny?>('detachMedia'.toJS);
    hls.callMethod<JSAny?>('destroy'.toJS);
  }

  void _onHlsError(JSObject data, Completer<void> ready) {
    final fatal = data.getProperty<JSBoolean?>('fatal'.toJS)?.toDart ?? false;
    final status = data
        .getProperty<JSObject?>('response'.toJS)
        ?.getProperty<JSNumber?>('code'.toJS)
        ?.toDartInt;
    final type = data.getProperty<JSString?>('type'.toJS)?.toDart ?? '';
    // The server's session cap, met on a fetch. Re-minting does not
    // help - the ordinary path sits under the same limit.
    final refused = status == 429;
    // The token aged out, the render was let go, or the files moved
    // underneath it. All three want the same answer: mint again.
    final gone = status == 401 || status == 404 || status == 410;
    if (!ready.isCompleted) {
      // Still loading. Nothing has played, hls.js has nothing buffered
      // to keep playing while it retries, and each of these answers is
      // final for this attempt - so the load fails now rather than
      // spinning until the deadline over a refusal known at the first
      // fetch.
      if (!fatal && !refused && !gone) return;
      _pauseNow();
      if (refused) _refuse();
      ready.completeError(
        MediaLoadException(
          gone || (!refused && type == 'mediaError')
              ? MediaFault.source
              : MediaFault.transport,
          StateError(
            status == null
                ? (type.isEmpty ? 'hls error' : type)
                : 'http $status',
          ),
        ),
      );
      return;
    }
    // Mid-stream, where there is a buffer to play out of. A non-fatal
    // error is one hls.js is still working on, and it is configured to
    // work on it for sixteen seconds - well inside the sixty it holds
    // buffered. Tearing the stream down over a fetch that would have
    // been made good is a re-mint, a slot and an audible reload the
    // listener never needed.
    if (!fatal) return;
    if (refused) {
      _pauseNow();
      _refuse();
      return;
    }
    // Fatal mid-stream: the stream is gone as far as this listener is
    // concerned, and a fresh mint is the recovery.
    final wasPlaying = _playingFlag;
    _pauseNow();
    if (!_losses.isClosed) _losses.add(wasPlaying);
  }

  void _refuse() {
    if (!_timelineRefusals.isClosed) _timelineRefusals.add('transcode-limited');
  }

  void _listen(String event, void Function(web.Event) handler) {
    _audio.addEventListener(event, handler.toJS);
  }

  void _startTicker() {
    _ticker?.cancel();
    // Between `timeupdate` events, which browsers fire about four times
    // a second: a seam landing a quarter second late is a quarter
    // second of the next track credited to this one.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    final media = _media;
    if (media == null) return;
    final abs = _absoluteMs;
    final located = media.locate(abs);
    if (located > _member) {
      // Crossed one or more seams. One boundary per tick even when a
      // member was shorter than the tick: the caller resyncs from
      // [currentMember], which is what it is for.
      _publishMember(located, emitBoundary: true);
      return;
    }
    if (located < _member) {
      // MSE snaps a seek back to the previous keyframe, which can land
      // just before the member asked for. Reported as the head of the
      // member the caller asked for rather than as a jump backwards
      // into the one before it.
      if (media.offsetMs(_member) - abs <= 300) {
        _emitPosition(Duration.zero);
        return;
      }
      _publishMember(located, emitBoundary: false);
      return;
    }
    _emitPosition(Duration(milliseconds: media.memberPosition(_member, abs)));
  }

  void _publishMember(
    int member, {
    required bool emitBoundary,
    Duration? position,
  }) {
    final media = _media;
    if (media == null) return;
    _member = member;
    final at =
        position ??
        Duration(milliseconds: media.memberPosition(member, _absoluteMs));
    // Port order: the new item's duration and position read true before
    // anything is told that the crossing happened.
    if (!_durations.isClosed) {
      _durations.add(Duration(milliseconds: media.memberDurationMs(member)));
    }
    _emitPosition(at);
    if (emitBoundary && !_boundaries.isClosed) _boundaries.add(null);
  }

  void _emitPosition(Duration at) {
    if (!_positions.isClosed) _positions.add(at);
  }

  void _onEnded() {
    _stopTicker();
    _setPlaying(false);
    _setState(EngineProcessingState.completed);
    if (!_completions.isClosed) _completions.add(null);
  }

  void _setPlaying(bool playing) {
    if (_playingFlag == playing) return;
    _playingFlag = playing;
    // Stopped as well as started, because most pauses do not come
    // through this engine at all: an OS media key, a hardware button, a
    // call taking audio focus, another tab claiming the output. Those
    // arrive only as the element's own `pause` event, and a ticker left
    // running past one polls the element ten times a second, for the
    // life of the page, over media that is not moving.
    if (playing) {
      _startTicker();
    } else {
      _stopTicker();
    }
    if (!_playings.isClosed) _playings.add(playing);
  }

  void _setState(EngineProcessingState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
