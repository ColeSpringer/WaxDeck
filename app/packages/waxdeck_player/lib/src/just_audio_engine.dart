import 'package:just_audio/just_audio.dart';

import 'audio_engine_port.dart';

/// [AudioEnginePort] backed by just_audio.
///
/// One facade drives every platform: the bundled just_audio backends on
/// mobile and web, and mpv via the media_kit bridge on desktop (see the
/// bootstrap helper). This class is the only place just_audio types appear.
class JustAudioEngine implements AudioEnginePort {
  JustAudioEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> load(
    String url, {
    String? mimeType,
    Duration? initialPosition,
  }) async {
    // The MIME hint is unused: just_audio sniffs the container itself on
    // every backend this engine targets.
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url)),
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Duration get position => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  // just_audio keeps its playing flag raised after playback runs off the
  // end of the media; the port contract (and the fake) drop it. Normalize
  // here so every engine reports completion the same way.
  @override
  bool get playing =>
      _player.playing && _player.processingState != ProcessingState.completed;

  @override
  Stream<bool> get playingStream => _player.playerStateStream
      .map((s) => s.playing && s.processingState != ProcessingState.completed)
      .distinct();

  @override
  EngineProcessingState get processingState => _map(_player.processingState);

  @override
  Stream<EngineProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_map).distinct();

  @override
  Stream<void> get completed => _player.processingStateStream.where(
    (state) => state == ProcessingState.completed,
  );

  EngineProcessingState _map(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => EngineProcessingState.idle,
      ProcessingState.loading ||
      ProcessingState.buffering => EngineProcessingState.loading,
      ProcessingState.ready => EngineProcessingState.ready,
      ProcessingState.completed => EngineProcessingState.completed,
    };
  }
}
