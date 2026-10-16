import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'scripted_platform.dart';

/// Every load stops the outgoing media first, which takes the platform
/// through idle. audio_service reads a move into idle as the service
/// stopping (on the web it clears the browser's media session), so the
/// engine reports a load as loading from the stop to the end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedPlatform platform;
  setUp(() => JustAudioPlatform.instance = platform = ScriptedPlatform());

  test('a load that replaces ready media never reads idle', () async {
    final e = scriptedEngine();
    await e.load('http://x/a.flac');
    await e.play();
    await settle();
    final seen = <EngineProcessingState>[];
    final sub = e.processingStateStream.listen(seen.add);
    final read = <EngineProcessingState>[];
    final reader = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => read.add(e.processingState),
    );
    await e.load('http://x/b.flac');
    await settle();
    reader.cancel();
    await sub.cancel();

    expect(seen, isNot(contains(EngineProcessingState.idle)));
    expect(read, isNot(contains(EngineProcessingState.idle)));
    expect(e.processingState, EngineProcessingState.ready);
  });

  test('a load that fails still ends idle', () async {
    final e = scriptedEngine();
    await e.load('http://x/a.flac');
    await settle();
    final seen = <EngineProcessingState>[];
    final sub = e.processingStateStream.listen(seen.add);
    platform.refuseLoads = true;
    await expectLater(
      e.load('http://x/b.ape'),
      throwsA(isA<MediaLoadException>()),
    );
    await settle();
    await sub.cancel();

    expect(e.processingState, EngineProcessingState.idle);
    expect(seen.last, EngineProcessingState.idle);
  });

  test('one instance of the states can be listened to again', () async {
    // A composite keeps the stream it picked and listens anew each time
    // its own listeners come back.
    final e = scriptedEngine();
    await e.load('http://x/a.flac');
    await settle();
    final states = e.processingStateStream;
    final first = <EngineProcessingState>[];
    final sub = states.listen(first.add);
    await settle();
    await sub.cancel();

    final again = <EngineProcessingState>[];
    final next = states.listen(again.add);
    addTearDown(next.cancel);
    await settle();
    expect(first, <EngineProcessingState>[EngineProcessingState.ready]);
    expect(again, <EngineProcessingState>[EngineProcessingState.ready]);
  });

  test('the states end with the engine', () async {
    final e = JustAudioEngine.withPlayer(
      AudioPlayer(handleAudioSessionActivation: false),
      ask: answering(ProbeAnswer.unreachable),
    );
    await e.load('http://x/a.flac');
    final done = Completer<void>();
    e.processingStateStream.listen(null, onDone: done.complete);
    await e.dispose();
    await done.future.timeout(const Duration(seconds: 1));
  });

  test('a stop outside a load still reads idle', () async {
    final e = scriptedEngine();
    await e.load('http://x/a.flac');
    await settle();
    await e.stop();
    await settle();
    expect(e.processingState, EngineProcessingState.idle);
  });
}
