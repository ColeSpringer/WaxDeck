import 'package:audio_service/audio_service.dart';

import 'audio_engine_port.dart';
import 'media_session_port.dart';

/// The audio_service handler: exposes the engine to the OS media
/// session (lock screen, Bluetooth, Android Auto) and serves the browse
/// tree. This is the only file that touches audio_service types, per
/// the wrap-don't-call policy.
class WaxDeckAudioHandler extends BaseAudioHandler {
  WaxDeckAudioHandler({
    required this.engine,
    required this.browse,
    required this.onPlayFromMediaId,
  }) {
    engine.playingStream.listen(_publishState);
    engine.processingStateStream.listen((_) => _publishState(engine.playing));
  }

  final AudioEnginePort engine;
  final BrowseSourcePort browse;

  /// Starts playback of a browse-tree leaf (the media id is the item
  /// pid). The app decides how: online play-info or the downloaded
  /// original.
  final Future<void> Function(String pid) onPlayFromMediaId;

  void _publishState(bool playing) {
    playbackState.add(
      PlaybackState(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        processingState: switch (engine.processingState) {
          EngineProcessingState.idle => AudioProcessingState.idle,
          EngineProcessingState.loading => AudioProcessingState.loading,
          EngineProcessingState.ready => AudioProcessingState.ready,
          EngineProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: engine.position,
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
}) {
  return AudioService.init(
    builder: () => WaxDeckAudioHandler(
      engine: engine,
      browse: browse,
      onPlayFromMediaId: onPlayFromMediaId,
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
