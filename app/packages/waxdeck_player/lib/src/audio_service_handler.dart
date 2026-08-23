import 'dart:ui' show Color;

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
    required this.onPlayFromMediaId,
    this.browse,
    this.onPlay,
    this.onStop,
    this.onGoingAway,
    this.onSkipNext,
    this.onSkipPrevious,
    this.onSkipToQueueItem,
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

  /// The browse tree, where the platform has one to serve and this build
  /// has a mirror to serve it from. Null on web, whose media session is
  /// the browser's own transport and has no drawer to appear in.
  final BrowseSourcePort? browse;

  /// Starts playback of a browse-tree leaf (the media id is the item
  /// pid). The app decides how: online play-info or the downloaded
  /// original.
  final Future<void> Function(String pid) onPlayFromMediaId;

  /// How the app starts playback, for the play raised on a lock screen,
  /// a headset button, a head unit, or a Bluetooth remote.
  ///
  /// The one transport verb that is not the engine's to answer alone. A
  /// play arriving after the item ended is a replay, and what has to be
  /// reset for a replay - the finished flag, the skip cursor, which part
  /// of a book to go back to - lives in the app's playback session, not
  /// here. Absent, this falls through to the engine, which is the right
  /// answer for a build with no session layer at all.
  ///
  /// Pause is deliberately not paired with this: the session reads a
  /// pause off the engine's own transition, so that one from the lock
  /// screen and one from an interruption count alike.
  final Future<void> Function()? onPlay;

  /// How the app stops. A stop is an end rather than a gap, and the app
  /// holds state the engine does not - live radio keeps a tuned station
  /// beside it. Absent, this falls through to the engine.
  final Future<void> Function()? onStop;

  /// How the app finalizes when it is being thrown away rather than
  /// stopped: the checkpoint, the listen report, the session Connect is
  /// advertising, the queue the next launch offers to resume.
  ///
  /// Apart from [onStop] because they are different events with
  /// different endings. A stop silences what is playing and leaves the
  /// queue standing, which is what a lock-screen stop means; this is
  /// the app going, and everything a stop leaves standing has to be
  /// written down first. Absent, [onTaskRemoved] falls back to the
  /// stop, which is the old behaviour rather than a broken one.
  final Future<void> Function()? onGoingAway;

  /// Queue steps, when the app runs a queue (a Connect load, a
  /// browse-tree folder played through). Absent callbacks hide the
  /// skip controls.
  final Future<void> Function()? onSkipNext;
  final Future<void> Function()? onSkipPrevious;

  /// A row of the published queue, chosen on a head unit's up-next list.
  /// By index rather than by media id: the same item queued twice is
  /// ordinary, and an id would step to the wrong one of the pair.
  final Future<void> Function(int index)? onSkipToQueueItem;

  /// The one extra control the app has raised, when it has.
  MediaSessionExtra? _extra;

  /// Whether what is playing is a live stream, which decides what the
  /// transport may honestly offer.
  bool _live = false;

  /// Which row of the published queue is playing, so a head unit can
  /// highlight it.
  int? _queueIndex;

  @override
  void publish(MediaSessionItem? item) {
    _live = item?.live ?? false;
    mediaItem.add(item == null ? null : _asMediaItem(item));
    // The controls follow what is playing - a station has nothing to
    // seek and nothing to step to - so the state is republished with it.
    _publishState(engine.playing);
  }

  @override
  void publishQueue(List<MediaSessionItem> items, {int index = 0}) {
    queue.add(<MediaItem>[for (final item in items) _asMediaItem(item)]);
    _queueIndex = items.isEmpty ? null : index;
    _publishState(engine.playing);
  }

  @override
  void publishQueueIndex(int index) {
    if (queue.value.isEmpty) return;
    // The state carries the index; the list itself did not change.
    _queueIndex = index;
    _publishState(engine.playing);
  }

  @override
  void showExtra(MediaSessionExtra? extra) {
    if (_extra?.action == extra?.action) return;
    _extra = extra;
    // Republished immediately: the control is raised for a window that
    // is measured in seconds, and waiting for the next state change
    // would be waiting for the pause it exists to prevent.
    _publishState(engine.playing);
  }

  MediaItem _asMediaItem(MediaSessionItem item) => MediaItem(
    id: item.id,
    title: item.title,
    artist: item.artist,
    album: item.album,
    duration: item.duration,
    artUri: item.artUri,
    isLive: item.live,
    playable: true,
  );

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
    // A station has no position to move and no queue to step through, so
    // it offers exactly one verb. Drawing the rest would be four controls
    // on a lock screen that do nothing when they are pressed - and on a
    // steering wheel, four buttons that appear to have broken.
    final stepping = !_live;
    playbackState.add(
      PlaybackState(
        controls: [
          if (stepping && onSkipPrevious != null) MediaControl.skipToPrevious,
          if (stepping) MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          if (stepping) MediaControl.fastForward,
          if (stepping && onSkipNext != null) MediaControl.skipToNext,
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
        queueIndex: _queueIndex,
        // What the desktop surfaces read to decide whether their seek bar
        // and their skip buttons are live at all. MPRIS spells it
        // CanSeek and CanGoNext; the notification spells it by which
        // controls it drew.
        systemActions: <MediaAction>{
          if (stepping) MediaAction.seek,
          if (stepping) MediaAction.seekForward,
          if (stepping) MediaAction.seekBackward,
          if (stepping && onSkipToQueueItem != null)
            MediaAction.skipToQueueItem,
          MediaAction.setSpeed,
        },
      ),
    );
  }

  @override
  Future<void> play() => onPlay?.call() ?? engine.play();

  @override
  Future<void> pause() => engine.pause();

  @override
  Future<void> stop() => onStop?.call() ?? engine.stop();

  /// The app was swiped out of the recents list.
  ///
  /// Android keeps the foreground service alive after that, which is
  /// what makes a queue survive an app switch - and what left music
  /// playing out of a window the listener had just thrown away. The
  /// base handler's default is to do nothing, so this is where "closing
  /// it stops the music" is said on this platform.
  ///
  /// Routed to the app's finalize rather than to a stop: the state a
  /// departure has to write down - the checkpoint, the listen report,
  /// the session Connect is advertising, the queue the next launch
  /// offers - lives above the engine, and a stop is defined as the verb
  /// that leaves all of it standing. Silencing the audio alone would
  /// have left the listener where they were two sessions ago.
  ///
  /// Only the task being removed does this. `androidStopForegroundOnPause`
  /// stays false so backgrounding the app keeps playing, which is the
  /// half of the behaviour nobody complained about.
  @override
  Future<void> onTaskRemoved() async {
    final goingAway = onGoingAway;
    if (goingAway == null) {
      await stop();
      return;
    }
    await goingAway();
    // The engine goes with the process, but not necessarily at once:
    // the foreground service outlives the task, which is what left
    // music playing out of a window somebody had thrown away.
    await engine.stop();
  }

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
  Future<void> skipToQueueItem(int index) async {
    await onSkipToQueueItem?.call(index);
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
    final source = browse;
    if (source == null) return const <MediaItem>[];
    final entries = await source.children(parentMediaId);
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
/// startup on every platform that has one: the notification and Android
/// Auto's drawer on Android, MediaSession in the browser, MPRIS on
/// Linux, and the transport controls on Windows. The browse tree is
/// what makes the app appear in a head
/// unit's media drawer, where the platform renders one.
/// [notificationColor] tints the Android notification. It is a parameter
/// rather than a constant because the value is a design token this
/// package cannot see: waxdeck_ui is the app's dependency, not the
/// player's, so the app passes its accent down instead of
/// this file keeping a second copy of the amber that would drift.
Future<WaxDeckAudioHandler> initWaxDeckAudioService({
  required AudioEnginePort engine,
  required Future<void> Function(String pid) onPlayFromMediaId,
  BrowseSourcePort? browse,
  Future<void> Function()? onPlay,
  Future<void> Function()? onStop,
  Future<void> Function()? onGoingAway,
  Future<void> Function()? onSkipNext,
  Future<void> Function()? onSkipPrevious,
  Future<void> Function(int index)? onSkipToQueueItem,
  Color? notificationColor,
}) {
  return AudioService.init(
    builder: () => WaxDeckAudioHandler(
      engine: engine,
      browse: browse,
      onPlayFromMediaId: onPlayFromMediaId,
      onPlay: onPlay,
      onStop: onStop,
      onGoingAway: onGoingAway,
      onSkipNext: onSkipNext,
      onSkipPrevious: onSkipPrevious,
      onSkipToQueueItem: onSkipToQueueItem,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.colespringer.waxdeck.playback',
      androidNotificationChannelName: 'WaxDeck playback',
      // Keep the foreground service alive while paused so the OS does
      // not reap mid-listen state (the documented hardening posture).
      androidStopForegroundOnPause: false,
      // The mark as a silhouette. Without it Android falls back to the
      // launcher icon, which the status bar flattens to a white blob;
      // and audio_service only draws the notification's seek bar when
      // the icon is a real status-bar drawable and the colour is
      // opaque, so these two travel together.
      androidNotificationIcon: 'drawable/ic_stat_waxdeck',
      notificationColor: notificationColor,
    ),
  );
}
