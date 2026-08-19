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
  ///
  /// A real-engine harness is expected to silence what it returns here:
  /// the suite plays minutes of a test tone through the machine's real
  /// output, and whoever is at the keyboard should not have to hear it.
  Future<AudioEnginePort> createEngine();

  /// The engine exactly as its constructor leaves it, for the few cases
  /// whose subject is that initial state - a harness that silences in
  /// [createEngine] has already destroyed what they assert on.
  ///
  /// Only a test that never plays may use this, which is what keeps the
  /// suite quiet: loading and reading make no sound. Fakes silence
  /// nothing, so for them the two are the same engine.
  Future<AudioEnginePort> createUnsilencedEngine() => createEngine();

  /// A URL the engine can load.
  String get mediaUrl;

  /// Duration of the media behind [mediaUrl].
  Duration get mediaDuration;

  /// Slack allowed when comparing positions and durations. Fakes are
  /// sample-exact and keep the default of zero; real engines interpolate
  /// positions between backend updates and need honest slack.
  Duration get tolerance => Duration.zero;

  /// A second URL the engine can load, used as the preloaded item at a
  /// boundary. The same media twice is fine: what the boundary cases
  /// assert is the crossing, not which file is playing.
  String get nextMediaUrl => mediaUrl;

  /// Whether the engine actually preloads, which must be what its
  /// [AudioEnginePort.canPreload] answers. The port lets an engine that
  /// cannot degrade to load-on-advance, so a harness that says `false`
  /// gets the degraded contract asserted instead of the gapless one.
  ///
  /// Asked of the harness rather than of the engine because it selects
  /// which tests are declared, and the engine does not exist until
  /// `setUp` has built one.
  bool get preloads => true;

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

    test('play answers while the item is still playing', () async {
      // The port's promise is that play resolves once the request has
      // been taken, never when the item ends. Awaiting the end instead
      // is what one backend did for a whole phase: a caller waiting on
      // it published its transport only when the track finished, and a
      // live stream, which never finishes, published none at all. This
      // asks for the answer before the item can possibly be over.
      await engine.load(harness.mediaUrl);
      var answered = false;
      final request = engine.play().then((_) => answered = true);
      await harness.advance(engine, quarter);
      expect(
        answered,
        isTrue,
        reason:
            'play should answer when the request is taken, '
            'not when the item ends',
      );
      expect(engine.playing, isTrue);
      await engine.pause();
      await request;
    });

    test('a start that is taken reports no refusal', () async {
      // The other half of that contract: a platform that turns a start
      // down says so here rather than by throwing, so an engine that is
      // playing must stay silent on this stream. A refusal itself
      // cannot be provoked from a test - it takes a browser's autoplay
      // policy - so the surfaces that read it are exercised against the
      // fake instead.
      final refusals = <Object>[];
      final sub = engine.playbackRefused.listen(refusals.add);
      await engine.load(harness.mediaUrl);
      await engine.play();
      await harness.advance(engine, quarter);
      expect(refusals, isEmpty);
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

    test('a clip window plays as if it were the whole media', () async {
      await engine.load(
        harness.mediaUrl,
        clipStart: quarter,
        clipEnd: threeQuarters,
      );
      expect(engine.duration, isNotNull);
      expectNear(engine.duration!, threeQuarters - quarter, 'clipped duration');
      expectNear(engine.position, Duration.zero, 'position at the window head');
      // Window-relative to the caller: half way in is half way through
      // the window, not through the file it was carved from.
      final half = (threeQuarters - quarter) ~/ 2;
      await engine.seek(half);
      await harness.advance(engine, Duration.zero);
      expectNear(engine.position, half, 'position after seeking in a window');
    });

    test('a window that names no start runs from the head', () async {
      // The first track carved out of a rip: a window that ends early
      // and starts where the file does.
      await engine.load(harness.mediaUrl, clipEnd: threeQuarters);
      expect(engine.duration, isNotNull);
      expectNear(engine.duration!, threeQuarters, 'open-start clip duration');
    });

    test('a clipped item ends at the end of its window', () async {
      await engine.load(
        harness.mediaUrl,
        clipStart: quarter,
        clipEnd: threeQuarters,
      );
      await engine.play();
      final done = engine.completed.first;
      await harness.advance(
        engine,
        threeQuarters - quarter + const Duration(seconds: 1),
      );
      await done.timeout(const Duration(seconds: 5));
      expect(engine.processingState, EngineProcessingState.completed);
      expect(engine.playing, isFalse);
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

    // The pair to the assertion above. `playing` going false at the end
    // is what puts a play button back on every surface that has one -
    // the deck, the lock screen, a headset button, a head unit - so a
    // play from there has to be able to start the item again. An engine
    // whose underlying player treats "completed" as still-playing will
    // take the request and do nothing, which reads as a dead button.
    test('play after completion starts the item again', () async {
      await engine.load(harness.mediaUrl);
      await engine.play();
      final done = engine.completed.first;
      await harness.advance(
        engine,
        harness.mediaDuration + const Duration(seconds: 1),
      );
      await done.timeout(const Duration(seconds: 5));
      expect(engine.playing, isFalse, reason: 'precondition: it ended');

      await engine.play();
      expect(engine.playing, isTrue);
      expect(
        engine.processingState,
        isNot(EngineProcessingState.completed),
        reason: 'a replay leaves the completed state behind',
      );
      expectNear(engine.position, Duration.zero, 'a replay starts at the top');
      // The assertion with teeth. `playing` and the processing state
      // both turn on leaving `completed`, so a rewind that never
      // actually asked the platform to play would satisfy them both.
      // Only the clock moving says the sound is running again.
      await harness.advance(engine, quarter);
      expectNear(engine.position, quarter, 'the replay is really running');
    });

    test('stop clears playing and returns to idle', () async {
      await engine.load(harness.mediaUrl);
      await engine.play();
      await engine.stop();
      expect(engine.playing, isFalse);
      expect(engine.processingState, EngineProcessingState.idle);
    });

    test('speed defaults to 1.0 and setSpeed reads back', () async {
      await engine.load(harness.mediaUrl);
      expect(engine.speed, closeTo(1.0, 0.001));
      await engine.setSpeed(1.5);
      expect(engine.speed, closeTo(1.5, 0.001));
    });

    test('speedStream emits the new speed', () async {
      await engine.load(harness.mediaUrl);
      final emitted = <double>[];
      final sub = engine.speedStream.listen(emitted.add);
      await engine.setSpeed(1.5);
      await harness.advance(engine, Duration.zero);
      expect(emitted.any((s) => (s - 1.5).abs() < 0.001), isTrue);
      await sub.cancel();
    });

    // Volume had no cases at all until a surface drew it: the two callers
    // it started with were the endpoint controller's session report and
    // its routed `set-volume`, neither of which reads the level back, so
    // nothing here was ever verified against a real engine.
    //
    // The only case that builds its own engine, because a real harness
    // silences the shared one - so the default asserted below would be
    // the harness's 0 rather than the engine's. Nothing here plays; it
    // loads and reads, which is what makes an unsilenced engine safe.
    test('volume defaults to 1.0 and setVolume reads back', () async {
      final fresh = await harness.createUnsilencedEngine();
      try {
        await fresh.load(harness.mediaUrl);
        expect(fresh.volume, closeTo(1.0, 0.001));
        await fresh.setVolume(0.4);
        expect(fresh.volume, closeTo(0.4, 0.001));
      } finally {
        await harness.disposeEngine(fresh);
      }
    });

    test('volumeStream emits the new volume', () async {
      await engine.load(harness.mediaUrl);
      final emitted = <double>[];
      final sub = engine.volumeStream.listen(emitted.add);
      await engine.setVolume(0.25);
      await harness.advance(engine, Duration.zero);
      expect(emitted.any((v) => (v - 0.25).abs() < 0.001), isTrue);
      await sub.cancel();
    });

    // Every case above subscribes before the level moves, which is the one
    // arrangement that cannot tell a seeded stream from a plain broadcast
    // one.
    test('volumeStream replays the current volume on listen', () async {
      await engine.load(harness.mediaUrl);
      await engine.setVolume(0.35);
      await harness.advance(engine, Duration.zero);
      expect(
        await engine.volumeStream.first,
        closeTo(0.35, 0.001),
        reason: 'volumeStream must seed a new listener with the current level',
      );
    });

    // The level is the listener's, not the track's: a queue crossing must
    // not put the room back to full.
    test('volume survives loading new media', () async {
      await engine.load(harness.mediaUrl);
      await engine.setVolume(0.3);
      await engine.load(harness.mediaUrl);
      expect(engine.volume, closeTo(0.3, 0.001));
    });

    test('speed persists across pause and play', () async {
      await engine.load(harness.mediaUrl);
      await engine.setSpeed(2.0);
      await engine.play();
      await harness.advance(engine, const Duration(seconds: 1));
      await engine.pause();
      expect(engine.speed, closeTo(2.0, 0.001));
      await engine.play();
      expect(engine.speed, closeTo(2.0, 0.001));
    });
  });

  group('$name gapless', () {
    late AudioEnginePort engine;

    setUp(() async {
      engine = await harness.createEngine();
    });

    tearDown(() => harness.disposeEngine(engine));

    /// Plays from wherever the engine sits off the end of the loaded
    /// item, then lets the crossing (or the completion) reach its
    /// listeners.
    Future<void> playPastTheEnd() async {
      await engine.play();
      await harness.advance(
        engine,
        harness.mediaDuration + const Duration(seconds: 1),
      );
      await harness.advance(engine, Duration.zero);
    }

    if (!harness.preloads) {
      test('an engine that cannot preload still ends the queue', () async {
        await engine.load(harness.mediaUrl);
        await engine.preloadNext(harness.nextMediaUrl);
        var crossings = 0;
        var queueEnded = 0;
        final b = engine.itemBoundary.listen((_) => crossings++);
        final c = engine.completed.listen((_) => queueEnded++);
        await playPastTheEnd();
        expect(crossings, 0, reason: 'a no-op preload has nothing to cross');
        expect(
          queueEnded,
          1,
          reason:
              'the caller advances on completed, so degrading to '
              'load-on-advance has to reach it',
        );
        expect(engine.processingState, EngineProcessingState.completed);
        await b.cancel();
        await c.cancel();
      });
      return;
    }

    test('an item ending into a preloaded one fires the boundary', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(harness.nextMediaUrl);
      var crossings = 0;
      var queueEnded = 0;
      final b = engine.itemBoundary.listen((_) => crossings++);
      final c = engine.completed.listen((_) => queueEnded++);
      await playPastTheEnd();
      expect(
        crossings,
        1,
        reason: 'the engine crossed into the preloaded item',
      );
      expect(
        queueEnded,
        0,
        reason:
            'an item ending into a preloaded one is item-ended, '
            'never queue-ended',
      );
      expect(engine.processingState, EngineProcessingState.ready);
      expect(engine.playing, isTrue);
      await b.cancel();
      await c.cancel();
    });

    test('the boundary neither pauses nor reloads', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(harness.nextMediaUrl);
      await engine.play();
      // Subscribed after play, so what these collect is the crossing
      // and nothing else. Sample adjacency itself is asserted where a
      // manual clock makes it exact (the fake's own tests); across a
      // real backend the honest statement is that playback never
      // stopped and the media was never re-prepared.
      final playing = <bool>[];
      final states = <EngineProcessingState>[];
      final p = engine.playingStream.listen(playing.add);
      final s = engine.processingStateStream.listen(states.add);
      await harness.advance(
        engine,
        harness.mediaDuration + const Duration(seconds: 1),
      );
      await harness.advance(engine, Duration.zero);
      expect(
        playing,
        isNot(contains(false)),
        reason: 'playback should not stop across the boundary',
      );
      expect(
        states,
        isNot(contains(EngineProcessingState.idle)),
        reason: 'the media should not be released and re-prepared',
      );
      expect(states, isNot(contains(EngineProcessingState.completed)));
      await p.cancel();
      await s.cancel();
    });

    test('positions read against the item now playing', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(harness.nextMediaUrl);
      await playPastTheEnd();
      expect(
        engine.position,
        lessThan(harness.mediaDuration),
        reason:
            'the position should have restarted against the preloaded '
            'item, not carried the finished one',
      );
      final before = engine.position;
      await harness.advance(engine, const Duration(seconds: 1));
      expect(
        engine.position,
        greaterThan(before),
        reason: 'the new item should still be running',
      );
    });

    test('a clip window is honored across the boundary', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(
        harness.nextMediaUrl,
        clipStart: quarter,
        clipEnd: threeQuarters,
      );
      await playPastTheEnd();
      expect(engine.duration, isNotNull);
      expectNear(
        engine.duration!,
        threeQuarters - quarter,
        'preloaded clip duration',
      );
    });

    test('preloading again replaces what was waiting', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(
        harness.nextMediaUrl,
        clipStart: quarter,
        clipEnd: threeQuarters,
      );
      await engine.preloadNext(harness.nextMediaUrl);
      await playPastTheEnd();
      expect(engine.duration, isNotNull);
      expectNear(
        engine.duration!,
        harness.mediaDuration,
        'duration after the replacing preload',
      );
    });

    test('the item after a boundary ends the queue', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(harness.nextMediaUrl);
      var queueEnded = 0;
      final c = engine.completed.listen((_) => queueEnded++);
      await playPastTheEnd();
      expect(queueEnded, 0);
      await playPastTheEnd();
      expect(
        queueEnded,
        1,
        reason: 'nothing was preloaded behind the second item',
      );
      expect(engine.processingState, EngineProcessingState.completed);
      expect(engine.playing, isFalse);
      await c.cancel();
    });

    test(
      'clearPreload makes the end of the item the end of the queue',
      () async {
        await engine.load(harness.mediaUrl);
        await engine.preloadNext(harness.nextMediaUrl);
        await engine.clearPreload();
        var crossings = 0;
        var queueEnded = 0;
        final b = engine.itemBoundary.listen((_) => crossings++);
        final c = engine.completed.listen((_) => queueEnded++);
        await playPastTheEnd();
        expect(crossings, 0);
        expect(queueEnded, 1);
        await b.cancel();
        await c.cancel();
      },
    );

    test('loading clears a pending preload', () async {
      await engine.load(harness.mediaUrl);
      await engine.preloadNext(harness.nextMediaUrl);
      await engine.load(harness.mediaUrl);
      var crossings = 0;
      var queueEnded = 0;
      final b = engine.itemBoundary.listen((_) => crossings++);
      final c = engine.completed.listen((_) => queueEnded++);
      await playPastTheEnd();
      expect(
        crossings,
        0,
        reason: 'a fresh load starts a fresh window, preload included',
      );
      expect(queueEnded, 1);
      await b.cancel();
      await c.cancel();
    });

    test('a load that interrupts a preload owns the window', () async {
      await engine.load(harness.mediaUrl);
      // The shape of a real queue jump, and the one that actually races:
      // a preload that replaces a previous one has to drop the old
      // source before adding the new one, and the load lands in between.
      // What the load leaves behind has to be its own item and nothing
      // else. An engine that lets the interrupted preload settle into
      // the new window plays a track nobody queued, gaplessly.
      await engine.preloadNext(harness.nextMediaUrl);
      final preloading = engine.preloadNext(harness.nextMediaUrl);
      await Future<void>.delayed(Duration.zero);
      await engine.load(harness.mediaUrl);
      await preloading;
      var crossings = 0;
      var queueEnded = 0;
      final b = engine.itemBoundary.listen((_) => crossings++);
      final c = engine.completed.listen((_) => queueEnded++);
      await playPastTheEnd();
      expect(
        crossings,
        0,
        reason: 'the interrupted preload does not follow the loaded item',
      );
      expect(queueEnded, 1);
      await b.cancel();
      await c.cancel();
    });

    test('preloading before anything is loaded does nothing', () async {
      await engine.preloadNext(harness.nextMediaUrl);
      await engine.load(harness.mediaUrl);
      var crossings = 0;
      var queueEnded = 0;
      final b = engine.itemBoundary.listen((_) => crossings++);
      final c = engine.completed.listen((_) => queueEnded++);
      await playPastTheEnd();
      expect(
        crossings,
        0,
        reason: 'there was no item for the preload to follow',
      );
      expect(queueEnded, 1);
      await b.cancel();
      await c.cancel();
    });
  });
}
