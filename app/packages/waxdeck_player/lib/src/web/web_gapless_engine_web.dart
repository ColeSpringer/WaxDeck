import 'dart:async';

import '../audio_engine_port.dart';
import '../timeline/timeline_media.dart';
import 'hls_timeline_player_web.dart';

/// The browser's audio engine: the standard one for a single item, the
/// timeline one for a whole queue rendered as one stream.
///
/// Two halves rather than one, because they are two different browser
/// mechanisms. A podcast, a book, a station, and every fallback is an
/// `<audio>` element with a URL, which is what just_audio's web platform
/// already is. A music queue with gapless switched on is Media Source
/// Extensions fed by hls.js, which is the only arrangement in a browser
/// where a track boundary is a position rather than a load.
///
/// Exactly one half is active. Activating one silences the other, so a
/// listener never has two elements making sound and the media session
/// never names the wrong one. Volume and speed are written to both, so
/// they survive the switch.
class WebGaplessEngine implements TimelineAudioEngine {
  WebGaplessEngine(this._standard, {HlsTimelinePlayer? timeline})
    : _timeline = timeline ?? HlsTimelinePlayer();

  final AudioEnginePort _standard;
  final HlsTimelinePlayer _timeline;

  /// Which half owns the sound. The standard one at rest: a browser
  /// that never plays a queue gaplessly never touches the other.
  bool _onTimeline = false;

  AudioEnginePort get _active => _onTimeline ? _timeline : _standard;

  /// The two halves' streams, merged and filtered to the active one.
  ///
  /// Filtered rather than switched: every surface that draws playback
  /// subscribes once, at build, and a stream that was replaced under it
  /// would leave it listening to a half that has gone quiet.
  ///
  /// Built once each, into the fields below. A getter that merged afresh
  /// on every read handed a new stream - and two new upstream
  /// subscriptions - to every `StreamBuilder` rebuild on every surface
  /// that draws playback, and the merge replays nothing, so each of
  /// those started blank.
  Stream<T> _merged<T>(Stream<T> Function(AudioEnginePort) pick) {
    final standard = pick(_standard).where((_) => !_onTimeline);
    final timeline = pick(_timeline).where((_) => _onTimeline);
    return StreamGroup.merge<T>(<Stream<T>>[standard, timeline]);
  }

  late final Stream<Duration> _positions = _merged<Duration>(
    (e) => e.positionStream,
  );
  late final Stream<Duration?> _durations = _merged<Duration?>(
    (e) => e.durationStream,
  );
  late final Stream<bool> _playings = _merged<bool>((e) => e.playingStream);
  late final Stream<EngineProcessingState> _processingStates =
      _merged<EngineProcessingState>((e) => e.processingStateStream);
  late final Stream<void> _completions = _merged<void>((e) => e.completed);
  late final Stream<Object> _refusals = _merged<Object>(
    (e) => e.playbackRefused,
  );
  late final Stream<void> _boundaries = _merged<void>((e) => e.itemBoundary);
  late final Stream<double> _speeds = _merged<double>((e) => e.speedStream);
  late final Stream<double> _volumes = _merged<double>((e) => e.volumeStream);

  /// The timeline half's own two, filtered the same way the merged ones
  /// are. Both are broadcast and deliver a frame late, so a loss queued
  /// as the standard half took over would otherwise arrive after the
  /// switch and re-mint over whatever that half had since loaded.
  late final Stream<bool> _losses = _timeline.timelineLost.where(
    (_) => _onTimeline,
  );
  late final Stream<String> _timelineRefusals = _timeline.timelineRefused.where(
    (_) => _onTimeline,
  );

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
    Duration? clipStart,
    Duration? clipEnd,
  }) async {
    if (_onTimeline) {
      // Silenced and released before the other half opens anything:
      // two elements playing at once is the failure this ordering
      // exists to prevent.
      await _timeline.stop();
      _onTimeline = false;
    }
    await _standard.load(
      url,
      mimeType: mimeType,
      initialPosition: initialPosition,
      clipStart: clipStart,
      clipEnd: clipEnd,
    );
  }

  @override
  Future<void> loadTimeline(
    TimelineMedia media, {
    int member = 0,
    Duration? position,
    bool play = false,
  }) async {
    if (!_onTimeline) {
      await _standard.stop();
    }
    // Carried across rather than reset: a listener who set the level
    // before the queue went gapless does not expect it to change.
    await _timeline.setVolume(_standard.volume);
    await _timeline.setSpeed(_standard.speed);
    _onTimeline = true;
    try {
      await _timeline.loadTimeline(
        media,
        member: member,
        position: position,
        play: play,
      );
    } on Object {
      _onTimeline = false;
      rethrow;
    }
  }

  /// Refused rather than forwarded while the standard half has the
  /// sound: a seek into a member of a timeline that is not playing would
  /// move a silent element and report a position for media nobody is
  /// hearing.
  @override
  Future<void> seekToMember(int member, Duration position) async {
    if (!_onTimeline) return;
    await _timeline.seekToMember(member, position);
  }

  @override
  Future<bool> prepareTimelines() => _timeline.prepareTimelines();

  /// What this browser's media source will decode, asked before hls.js
  /// has been fetched: the answer is the browser's, not the library's,
  /// and it is needed at the mint - which is what causes the fetch.
  /// Gating it on the script being present made every mint arrive with
  /// an empty list, and the server then rendered its own ladder's
  /// choice - AAC, the one format a Chromium built without the
  /// proprietary codecs cannot play.
  @override
  List<String> get supportedTimelineFormats =>
      _timeline.supportedTimelineFormats;

  @override
  TimelineMedia? get loadedTimeline =>
      _onTimeline ? _timeline.loadedTimeline : null;

  /// Zero while the standard half holds the sound, so this and
  /// [loadedTimeline] answer as the pair the port describes them as: a
  /// stale member beside a null timeline is a member of nothing.
  @override
  int get currentMember => _onTimeline ? _timeline.currentMember : 0;

  @override
  Stream<bool> get timelineLost => _losses;

  @override
  Stream<String> get timelineRefused => _timelineRefusals;

  /// No window on either half. just_audio's web platform re-points one
  /// element's `src` at a boundary, which is a load and a gap; the
  /// timeline half needs no window because the next member is already
  /// in the stream.
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
  Future<void> play() => _active.play();

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> seek(Duration position) => _active.seek(position);

  @override
  Future<void> stop() async {
    await _timeline.stop();
    await _standard.stop();
    _onTimeline = false;
  }

  @override
  Future<void> dispose() async {
    await _timeline.dispose();
    await _standard.dispose();
  }

  @override
  Duration get position => _active.position;

  @override
  Stream<Duration> get positionStream => _positions;

  @override
  Duration? get duration => _active.duration;

  @override
  Stream<Duration?> get durationStream => _durations;

  @override
  bool get playing => _active.playing;

  @override
  Stream<bool> get playingStream => _playings;

  @override
  EngineProcessingState get processingState => _active.processingState;

  @override
  Stream<EngineProcessingState> get processingStateStream => _processingStates;

  @override
  Stream<void> get completed => _completions;

  @override
  Stream<Object> get playbackRefused => _refusals;

  @override
  Stream<void> get itemBoundary => _boundaries;

  @override
  Future<void> setSpeed(double speed) async {
    // Both halves, so the setting survives the switch.
    await _standard.setSpeed(speed);
    await _timeline.setSpeed(speed);
  }

  @override
  double get speed => _active.speed;

  @override
  Stream<double> get speedStream => _speeds;

  @override
  Future<void> setVolume(double volume) async {
    await _standard.setVolume(volume);
    await _timeline.setVolume(volume);
  }

  @override
  double get volume => _active.volume;

  /// Replays the current level, which the port requires of every
  /// implementation: a surface built after the level moved would
  /// otherwise draw full until somebody changed it.
  @override
  Stream<double> get volumeStream async* {
    yield volume;
    yield* _volumes;
  }
}

/// A local merge rather than `package:async`, which this package does
/// not depend on and would not gain anything else from.
class StreamGroup {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    late StreamController<T> controller;
    final subs = <StreamSubscription<T>>[];
    controller = StreamController<T>.broadcast(
      onListen: () {
        for (final stream in streams) {
          subs.add(stream.listen(controller.add, onError: controller.addError));
        }
      },
      onCancel: () async {
        // Taken and emptied before the first await: a listener arriving
        // during the cancels re-runs `onListen` and appends to the same
        // list, and iterating it across the awaits would either throw on
        // the concurrent modification or cancel the subscriptions that
        // new listener is waiting on.
        final closing = List<StreamSubscription<T>>.of(subs);
        subs.clear();
        for (final sub in closing) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }
}
