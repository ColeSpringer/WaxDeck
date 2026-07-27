import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../player/session_registry.dart';
import '../providers.dart';

/// The shared internet radio station library.
class RadioStationsController extends AsyncNotifier<List<RadioStation>> {
  @override
  Future<List<RadioStation>> build() =>
      ref.watch(repositoryProvider).listRadioStations();

  /// Adds a station and reloads. Errors propagate so dialogs surface the
  /// server's message (duplicate stream URLs, refused private hosts).
  Future<RadioStation> add({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  }) async {
    final created = await ref
        .read(repositoryProvider)
        .createRadioStation(
          name: name,
          streamUrl: streamUrl,
          homepageUrl: homepageUrl,
          logoUrl: logoUrl,
        );
    ref.invalidateSelf();
    await future;
    return created;
  }

  Future<void> remove(String pid) async {
    await ref.read(repositoryProvider).deleteRadioStation(pid);
    ref.invalidateSelf();
    await future;
  }
}

final radioStationsProvider =
    AsyncNotifierProvider<RadioStationsController, List<RadioStation>>(
      RadioStationsController.new,
    );

/// What the radio player is doing right now.
class RadioPlayback {
  const RadioPlayback({this.station, this.starting = false, this.nowPlaying});

  /// The station currently loaded through the engine, if any.
  final RadioStation? station;

  /// True while play-info resolves and the stream buffers.
  final bool starting;

  /// The station's current in-stream title, when it announces one.
  final String? nowPlaying;
}

/// Drives live radio through the shared audio engine. Radio has no
/// positions, checkpoints, or listen accounting, so it deliberately
/// bypasses PlaybackSession: it pauses any active session first, then
/// owns the engine until a session (or another station) takes it back.
class RadioPlaybackController extends Notifier<RadioPlayback> {
  Timer? _titlePoll;
  Timer? _firstTitleTick;

  @override
  RadioPlayback build() {
    ref.onDispose(_stopTitlePoll);
    return const RadioPlayback();
  }

  Future<void> play(RadioStation station) async {
    // A paused session stops writing checkpoints, so taking the engine
    // from it cannot corrupt the item's saved position. The session
    // surface exposes a toggle, so pause only when actually playing.
    final session = ref.read(currentSessionRegistryProvider).current;
    if (session != null && ref.read(audioEngineProvider).playing) {
      await session.toggle();
    }
    _stopTitlePoll();
    state = RadioPlayback(station: station, starting: true);
    try {
      final info = await ref
          .read(repositoryProvider)
          .getRadioPlayInfo(station.pid);
      final engine = ref.read(audioEngineProvider);
      await engine.load(info.url);
      await engine.play();
      state = RadioPlayback(station: station, nowPlaying: info.nowPlaying);
      _startTitlePoll(station.pid);
    } on WaxDeckApiException {
      state = const RadioPlayback();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (state.station == null) return;
    _stopTitlePoll();
    state = const RadioPlayback();
    await ref.read(audioEngineProvider).stop();
  }

  /// Starts the loaded station's stream again after the platform turned
  /// a programmatic start down.
  ///
  /// The station is still tuned and its media still loaded: only the
  /// start was refused, so this is a play and not a re-tune, and the tap
  /// that reaches it is the gesture the browser was waiting for.
  Future<void> resume() async {
    if (state.station == null) return;
    await ref.read(audioEngineProvider).play();
  }

  /// Clears radio state without touching the engine; the player screen
  /// calls this as it hands the engine to a new item session.
  void markInterrupted() {
    if (state.station != null) {
      _stopTitlePoll();
      state = const RadioPlayback();
    }
  }

  /// The in-stream title lives in play-info and only exists while the
  /// proxy sees the stream, so it is polled during playback. The poll
  /// reads metadata only; the open stream is never re-tuned.
  void _startTitlePoll(String pid) {
    _titlePoll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshTitle(pid),
    );
    // The first metadata block lands moments after the stream opens;
    // one early refresh beats waiting out a full period. (The station
    // guard in _refreshTitle already makes a stale firing a no-op;
    // tracking the handle just cancels it cleanly.)
    _firstTitleTick = Timer(
      const Duration(seconds: 4),
      () => _refreshTitle(pid),
    );
  }

  void _stopTitlePoll() {
    _titlePoll?.cancel();
    _titlePoll = null;
    _firstTitleTick?.cancel();
    _firstTitleTick = null;
  }

  Future<void> _refreshTitle(String pid) async {
    if (state.station?.pid != pid) return;
    try {
      final info = await ref.read(repositoryProvider).getRadioPlayInfo(pid);
      if (state.station?.pid == pid) {
        state = RadioPlayback(
          station: state.station,
          nowPlaying: info.nowPlaying,
        );
      }
    } on WaxDeckApiException {
      // Metadata is decoration; playback carries on without it.
    }
  }
}

final radioPlaybackProvider =
    NotifierProvider<RadioPlaybackController, RadioPlayback>(
      RadioPlaybackController.new,
    );
