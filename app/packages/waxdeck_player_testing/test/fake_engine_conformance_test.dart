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

    // Replay after completion is not a FakeEngine specific: it is the
    // port's contract, and it lives in the shared suite so the real
    // engines are held to it too. It was here, and only here, which is
    // how just_audio came to diverge from it unnoticed.

    test('advance scales media time by the playback speed', () async {
      final engine = FakeEngine(mediaDuration: const Duration(minutes: 10));
      await engine.load('/stream');
      await engine.setSpeed(2.0);
      await engine.play();
      engine.advance(const Duration(seconds: 30));
      expect(engine.position, const Duration(minutes: 1));
      await engine.setSpeed(0.5);
      engine.advance(const Duration(seconds: 60));
      expect(engine.position, const Duration(seconds: 90));
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

    test('records what was preloaded until the boundary takes it', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      await engine.preloadNext(
        '/stream/two',
        mimeType: 'audio/flac',
        clipStart: const Duration(seconds: 1),
        clipEnd: const Duration(seconds: 4),
      );
      expect(engine.preloadedUrl, '/stream/two');
      expect(engine.preloadedMimeType, 'audio/flac');
      expect(engine.preloadedClipStart, const Duration(seconds: 1));
      expect(engine.preloadedClipEnd, const Duration(seconds: 4));
      expect(engine.loadedUrl, '/stream/one');

      await engine.play();
      engine.advance(const Duration(seconds: 10));
      expect(engine.loadedUrl, '/stream/two');
      expect(engine.loadedMimeType, 'audio/flac');
      expect(engine.loadedClipStart, const Duration(seconds: 1));
      expect(engine.loadedClipEnd, const Duration(seconds: 4));
      expect(engine.duration, const Duration(seconds: 3));
      expect(engine.preloadedUrl, isNull, reason: 'the preload was consumed');
      await engine.dispose();
    });

    test('the boundary is sample-adjacent', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      await engine.preloadNext('/stream/two');
      var crossings = 0;
      final sub = engine.itemBoundary.listen((_) => crossings++);
      await engine.play();
      // Two seconds past the end of a ten second item: the media time
      // that ran over plays at the head of the next one, not lost and
      // not counted twice.
      engine.advance(const Duration(seconds: 12));
      await Future<void>.delayed(Duration.zero);
      expect(crossings, 1);
      expect(engine.position, const Duration(seconds: 2));
      expect(engine.playing, isTrue);
      expect(engine.processingState, EngineProcessingState.ready);
      await sub.cancel();
      await engine.dispose();
    });

    test('the overshoot carries at the playback speed', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      await engine.preloadNext('/stream/two');
      await engine.setSpeed(2.0);
      await engine.play();
      // Six seconds of wall time covers twelve of media at 2.0x.
      engine.advance(const Duration(seconds: 6));
      expect(engine.position, const Duration(seconds: 2));
      await engine.dispose();
    });

    test('running past both items completes the queue', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      await engine.preloadNext('/stream/two');
      var crossings = 0;
      var queueEnded = 0;
      final b = engine.itemBoundary.listen((_) => crossings++);
      final c = engine.completed.listen((_) => queueEnded++);
      await engine.play();
      engine.advance(const Duration(seconds: 25));
      await Future<void>.delayed(Duration.zero);
      expect(crossings, 1);
      expect(queueEnded, 1);
      expect(engine.position, const Duration(seconds: 10));
      expect(engine.processingState, EngineProcessingState.completed);
      expect(engine.playing, isFalse);
      await b.cancel();
      await c.cancel();
      await engine.dispose();
    });

    test('stopping drops the preload', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      await engine.preloadNext('/stream/two');
      await engine.stop();
      expect(engine.preloadedUrl, isNull);
      await engine.dispose();
    });

    test('a window that names no start runs from the head', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one', clipEnd: const Duration(seconds: 4));
      expect(engine.duration, const Duration(seconds: 4));
      await engine.preloadNext(
        '/stream/two',
        clipEnd: const Duration(seconds: 6),
      );
      await engine.play();
      engine.advance(const Duration(seconds: 4));
      expect(engine.duration, const Duration(seconds: 6));
      await engine.dispose();
    });

    test('the preloaded item takes the duration set for it', () async {
      final engine = FakeEngine(mediaDuration: const Duration(seconds: 10));
      await engine.load('/stream/one');
      engine.mediaDuration = const Duration(seconds: 30);
      await engine.preloadNext('/stream/two');
      await engine.play();
      engine.advance(const Duration(seconds: 10));
      expect(engine.duration, const Duration(seconds: 30));
      await engine.dispose();
    });
  });
}
