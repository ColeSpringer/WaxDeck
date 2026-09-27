import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// A platform whose players load, and whose first start can wait on
/// [firstStart] or fail outright.
class _StartingPlatform extends JustAudioPlatform {
  _StartingPlatform({this.firstStart, this.failFirstStart = false});

  final Future<void>? firstStart;
  final bool failFirstStart;
  int starts = 0;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (starts++ == 0) {
      await firstStart;
      if (failFirstStart) throw PlatformException(code: 'init');
    }
    return _LoadingPlayer(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

class _LoadingPlayer extends AudioPlayerPlatform {
  _LoadingPlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    const length = Duration(minutes: 3);
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: length,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: length);
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    return DisposeResponse();
  }
}

JustAudioEngine _engine() => JustAudioEngine.withPlayer(
  AudioPlayer(handleAudioSessionActivation: false),
  loadDeadline: const Duration(seconds: 5),
  probe: (_) async => StreamProbe.answered,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a load that lands while the platform starts takes it over', () async {
    // A skip during a slow native start: the new load must not wait on
    // the start it interrupted.
    final start = Completer<void>();
    JustAudioPlatform.instance = _StartingPlatform(firstStart: start.future);
    final engine = _engine();
    addTearDown(engine.dispose);

    final first = engine
        .load('http://x/one.mp3')
        .then<Object?>((_) => null, onError: (Object e) => e);
    await pumpEventQueue();
    final second = engine.load('http://x/two.mp3');
    await pumpEventQueue();
    start.complete();

    await expectLater(second.timeout(const Duration(seconds: 1)), completes);
    expect(await first, isA<MediaLoadException>());
    expect(engine.processingState, EngineProcessingState.ready);
  });

  test('a start that failed answers every call waiting on it', () async {
    JustAudioPlatform.instance = _StartingPlatform(failFirstStart: true);
    final engine = _engine();
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/one.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    for (final call in <Future<void> Function()>[
      () => engine.setVolume(0.5),
      () => engine.setSpeed(1.5),
      () => engine.seek(const Duration(seconds: 3)),
    ]) {
      await expectLater(
        call().timeout(const Duration(seconds: 1)),
        throwsA(isA<PlatformException>()),
      );
    }
    // And the next load takes the player back.
    await engine.load('http://x/two.mp3').timeout(const Duration(seconds: 1));
    expect(engine.processingState, EngineProcessingState.ready);
  });
}
