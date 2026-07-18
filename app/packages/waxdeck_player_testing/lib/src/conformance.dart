/// Behavioral conformance suite for [AudioEnginePort] implementations.
///
/// The same assertions run against any engine through an
/// [AudioEngineHarness]: the deterministic fake in this package's own
/// tests, and the real desktop engine in the app's integration tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// Adapts one engine implementation to the shared suite.
abstract class AudioEngineHarness {
  /// A fresh engine per test.
  Future<AudioEnginePort> createEngine();

  /// A URL the engine can load.
  String get mediaUrl;

  /// Duration of the media behind [mediaUrl].
  Duration get mediaDuration;

  /// Slack allowed when comparing positions and durations. Fakes are
  /// sample-exact and keep the default of zero; real engines interpolate
  /// positions between backend updates and need honest slack.
  Duration get tolerance => Duration.zero;

  /// Advances playback by [amount] of media time and lets events settle.
  /// Fakes step a manual clock; a real-engine harness waits in wall
  /// time, seeking ahead first when the amount is large.
  Future<void> advance(AudioEnginePort engine, Duration amount);

  Future<void> disposeEngine(AudioEnginePort engine) => engine.dispose();
}

void runAudioEngineConformance(String name, AudioEngineHarness harness) {
  // Seek targets scale with the media, so short real files and long fake
  // ones exercise the same shape: one quarter in, then three quarters.
  final quarter = harness.mediaDuration ~/ 4;
  final threeQuarters = harness.mediaDuration * 3 ~/ 4;

  void expectNear(Duration actual, Duration expected, String what) {
    expect(
      (actual - expected).abs(),
      lessThanOrEqualTo(harness.tolerance),
      reason:
          '$what should be within ${harness.tolerance} '
          'of $expected, was $actual',
    );
  }

  group('$name conformance', () {
    late AudioEnginePort engine;

    setUp(() async {
      engine = await harness.createEngine();
    });

    tearDown(() => harness.disposeEngine(engine));

    test('load prepares media and reports ready', () async {
      await engine.load(harness.mediaUrl);
      expect(engine.processingState, EngineProcessingState.ready);
      expect(engine.duration, isNotNull);
      expectNear(engine.duration!, harness.mediaDuration, 'duration');
      expect(engine.playing, isFalse);
      expectNear(engine.position, Duration.zero, 'position after load');
    });

    test('load honors an initial position', () async {
      await engine.load(harness.mediaUrl, initialPosition: quarter);
      expectNear(engine.position, quarter, 'initial position');
    });

    test('load then play reports playing', () async {
      await engine.load(harness.mediaUrl);
      final transitions = <bool>[];
      final sub = engine.playingStream.listen(transitions.add);
      await engine.play();
      await harness.advance(engine, const Duration(seconds: 1));
      expect(engine.playing, isTrue);
      expect(transitions, contains(true));
      await sub.cancel();
    });

    test('pause clears playing and keeps the position', () async {
      await engine.load(harness.mediaUrl);
      await engine.play();
      await harness.advance(engine, const Duration(seconds: 2));
      final before = engine.position;
      await engine.pause();
      expect(engine.playing, isFalse);
      expectNear(engine.position, before, 'position across pause');
    });

    test('seek updates the position', () async {
      await engine.load(harness.mediaUrl);
      final positions = <Duration>[];
      final sub = engine.positionStream.listen(positions.add);
      await engine.seek(threeQuarters);
      await harness.advance(engine, Duration.zero);
      expectNear(engine.position, threeQuarters, 'position after seek');
      expect(
        positions.any((p) => (p - threeQuarters).abs() <= harness.tolerance),
        isTrue,
        reason:
            'positionStream should report the seek target; '
            'saw $positions',
      );
      await sub.cancel();
    });

    test('completed fires when playback reaches the end', () async {
      await engine.load(harness.mediaUrl);
      await engine.play();
      final done = engine.completed.first;
      await harness.advance(
        engine,
        harness.mediaDuration + const Duration(seconds: 1),
      );
      await done.timeout(const Duration(seconds: 5));
      expect(engine.processingState, EngineProcessingState.completed);
      expect(engine.playing, isFalse);
    });

    test('stop clears playing and returns to idle', () async {
      await engine.load(harness.mediaUrl);
      await engine.play();
      await engine.stop();
      expect(engine.playing, isFalse);
      expect(engine.processingState, EngineProcessingState.idle);
    });
  });
}
