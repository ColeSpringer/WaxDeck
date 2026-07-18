import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

/// Runs the shared engine conformance suite against [FakeEngine], and pins
/// the fake-specific behaviors the app's widget tests rely on.
class FakeEngineHarness extends AudioEngineHarness {
  @override
  Future<AudioEnginePort> createEngine() async =>
      FakeEngine(mediaDuration: mediaDuration);

  @override
  String get mediaUrl => '/media/stream?pid=tr-test&mt=token';

  @override
  Duration get mediaDuration => const Duration(minutes: 2);

  @override
  Future<void> advance(AudioEnginePort engine, Duration amount) async {
    (engine as FakeEngine).advance(amount);
    // Let broadcast stream events reach their listeners.
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  runAudioEngineConformance('FakeEngine', FakeEngineHarness());

  group('FakeEngine specifics', () {
    test('records what was loaded', () async {
      final engine = FakeEngine();
      await engine.load('/stream', mimeType: 'audio/flac');
      expect(engine.loadedUrl, '/stream');
      expect(engine.loadedMimeType, 'audio/flac');
      await engine.dispose();
      expect(engine.disposed, isTrue);
    });

    test('advance does nothing while paused', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream');
      engine.advance(const Duration(seconds: 5));
      expect(engine.position, Duration.zero);
      await engine.dispose();
    });

    test('play after completion restarts from the top', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream');
      await engine.play();
      engine.advance(const Duration(seconds: 11));
      expect(engine.processingState, EngineProcessingState.completed);
      await engine.play();
      expect(engine.position, Duration.zero);
      expect(engine.playing, isTrue);
      expect(engine.processingState, EngineProcessingState.ready);
      await engine.dispose();
    });

    test('seek clamps to the media bounds', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream');
      await engine.seek(const Duration(seconds: 99));
      expect(engine.position, const Duration(seconds: 10));
      await engine.seek(const Duration(seconds: -5));
      expect(engine.position, Duration.zero);
      await engine.dispose();
    });
  });
}
