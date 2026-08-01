import 'package:audio_service/audio_service.dart';

import 'audio_engine_port.dart';
import 'media_session_port.dart';

/// The audio_service handler: exposes the engine to the OS media
/// session (lock screen, Bluetooth, Android Auto) and serves the browse
/// tree. This is the only file that touches audio_service types, per
/// the wrap-don't-call policy.
class WaxDeckAudioHandler extends BaseAudioHandler implements MediaSessionPort {
  WaxDeckAudioHandler({
    required this.engine,
    required this.browse,
    required this.onPlayFromMediaId,
    this.onSkipNext,
    this.onSkipPrevious,
  }) {
    engine.playingStream.listen(_publishState);
    engine.processingStateStream.listen((_) => _publishState(engine.playing));
    engine.speedStream.listen((_) => _publishState(engine.playing));
    // A gapless crossing moves the position without changing any state
    // the listeners above watch, and the OS extrapolates its progress
    // from the last position published. Left alone, the lock screen
    // would run the previous item's clock through the whole next one.
    engine.itemBoundary.listen((_) => _publishState(engine.playing));
  }

  final AudioEnginePort engine;
  final BrowseSourcePort browse;

  /// Starts playback of a browse-tree leaf (the media id is the item
  /// pid). The app decides how: online play-info or the downloaded
  /// original.
  final Future<void> Function(String pid) onPlayFromMediaId;

  /// Queue steps, when the app runs a queue (a Connect load, a
  /// browse-tree folder played through). Absent callbacks hide the
  /// skip controls.
  final Future<void> Function()? onSkipNext;
  final Future<void> Function()? onSkipPrevious;

  /// The one extra control the app has raised, when it has.
  MediaSessionExtra? _extra;

  @override
  void showExtra(MediaSessionExtra? extra) {
    if (_extra?.action == extra?.action) return;
    _extra = extra;
    // Republished immediately: the control is raised for a window that
    // is measured in seconds, and waiting for the next state change
    // would be waiting for the pause it exists to prevent.
    _publishState(engine.playing);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    final extra = _extra;
    if (extra != null && extra.action == name) {
      extra.onPressed();
      return;
    }
    return super.customAction(name, extras);
  }

  void _publishState(bool playing) {
    final extra = _extra;
    playbackState.add(
      PlaybackState(
        controls: [
          if (onSkipPrevious != null) MediaControl.skipToPrevious,
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          if (onSkipNext != null) MediaControl.skipToNext,
          MediaControl.stop,
          if (extra != null)
            MediaControl.custom(
              // A bundled drawable: audio_service resolves the icon in
              // the Android resource table, so an app-supplied name
              // would need an asset in the host project. The extra is
              // an extension of playback and the forward glyph says
              // so; the label carries the meaning.
              androidIcon: 'drawable/audio_service_fast_forward',
              label: extra.label,
              name: extra.action,
            ),
        ],
        processingState: switch (engine.processingState) {
          EngineProcessingState.idle => AudioProcessingState.idle,
          EngineProcessingState.loading => AudioProcessingState.loading,
          EngineProcessingState.ready => AudioProcessingState.ready,
          EngineProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: engine.position,
        speed: engine.speed,
      ),
    );
  }

  @override
  Future<void> play() => engine.play();

  @override
  Future<void> pause() => engine.pause();

  @override
  Future<void> stop() => engine.stop();

  @override
  Future<void> seek(Duration position) => engine.seek(position);

  /// Spoken-word friendly jumps for cars and headsets: a short hop
  /// back to recover a missed sentence, a longer hop forward.
  @override
  Future<void> rewind() {
    final target = engine.position - const Duration(seconds: 10);
    return engine.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> fastForward() {
    return engine.seek(engine.position + const Duration(seconds: 30));
  }

  @override
  Future<void> skipToNext() async {
    await onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipPrevious?.call();
  }

  @override
  Future<void> setSpeed(double speed) => engine.setSpeed(speed);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) {
    return onPlayFromMediaId(mediaId);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final entries = await browse.children(parentMediaId);
    return [
      for (final e in entries)
        MediaItem(
          id: e.id,
          title: e.title,
          artist: e.subtitle,
          playable: e.playable,
        ),
    ];
  }
}

/// Initializes the OS media session around the engine. Called once at
/// startup on platforms with a media session (Android today); the
/// browse tree makes the app appear in Android Auto's media drawer.
Future<WaxDeckAudioHandler> initWaxDeckAudioService({
  required AudioEnginePort engine,
  required BrowseSourcePort browse,
  required Future<void> Function(String pid) onPlayFromMediaId,
  Future<void> Function()? onSkipNext,
  Future<void> Function()? onSkipPrevious,
}) {
  return AudioService.init(
    builder: () => WaxDeckAudioHandler(
      engine: engine,
      browse: browse,
      onPlayFromMediaId: onPlayFromMediaId,
      onSkipNext: onSkipNext,
      onSkipPrevious: onSkipPrevious,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.colespringer.waxdeck.playback',
      androidNotificationChannelName: 'WaxDeck playback',
      // Keep the foreground service alive while paused so the OS does
      // not reap mid-listen state (the documented hardening posture).
      androidStopForegroundOnPause: false,
    ),
  );
}
