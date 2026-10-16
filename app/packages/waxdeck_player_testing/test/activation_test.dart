import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'scripted_platform.dart';

JustAudioEngine _engine() => JustAudioEngine.withPlayer(
  AudioPlayer(handleAudioSessionActivation: false),
  loadDeadline: const Duration(seconds: 5),
  ask: answering(const ProbeAnswer(StreamProbe.answered)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedPlatform platform;
  setUp(() => JustAudioPlatform.instance = platform = ScriptedPlatform());

  test('a load that lands while the platform starts takes it over', () async {
    // A skip during a slow native start: the new load must not wait on
    // the start it interrupted.
    final start = platform.initGate = Completer<void>();
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
    platform.refuseNextInit = true;
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
