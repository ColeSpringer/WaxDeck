import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

import 'scripted_platform.dart';

/// Media failing after its load succeeded: a dropped connection, a token
/// that lapsed before the next range request, a file that stops decoding
/// part way. The load had answered, so nothing was left to throw, and the
/// engine used to report it nowhere - the transport kept saying playing
/// over silence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedPlatform platform;
  setUp(() => JustAudioPlatform.instance = platform = ScriptedPlatform());

  test('a failure after a settled load reaches mediaFailed with the play '
      'intent', () async {
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    await settle();
    expect(engine.playing, isTrue);

    platform.player.fail(2, 'network');
    await settle();

    expect(failures, hasLength(1));
    expect(failures.single.wasPlaying, isTrue);
    expect(failures.single.fault, MediaFault.transport);
    expect(failures.single.cause, isA<PlayerException>());
    expect(
      engine.playing,
      isFalse,
      reason: 'a failed element must not keep reporting playing',
    );
  });

  test(
    'a release the platform never finishes holds no load behind it',
    () async {
      // just_audio lets its platform player go on the error's move to idle,
      // under the lock every later load waits on. just_audio_web's release
      // waits behind an `<audio>` play still waiting for data, and a network
      // error never settles that play.
      platform.releaseGate = Completer<void>();
      JustAudioPlatform.instance = ReleaseBoundedPlatform(
        platform,
        bound: const Duration(milliseconds: 50),
      );
      final engine = JustAudioEngine.withPlayer(
        AudioPlayer(handleAudioSessionActivation: false),
        loadDeadline: const Duration(seconds: 2),
        ask: answering(ProbeAnswer.unreachable),
      );
      addTearDown(engine.dispose);
      await engine.load('http://x/a.flac');
      await engine.play();
      await settle();
      platform.player.fail(2, 'network');
      await settle();

      await engine.load('http://x/b.flac?mt=fresh');
      expect(platform.player.loads, 1, reason: 'a fresh player took it');
      expect(
        platform.players.skip(1).expand((p) => p.loadedUris),
        everyElement(contains('mt=fresh')),
        reason: 'nothing reopens the stream that failed',
      );
    },
  );

  test('a failure while paused says it was not playing', () async {
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    platform.player.fail(2);
    await settle();
    expect(failures.single.wasPlaying, isFalse);
  });

  test('the server\'s refusal rides along with the failure', () async {
    final asked = <String>[];
    final engine = scriptedEngine(
      ask: (url, {segmentAt}) async {
        asked.add(url);
        return const ProbeAnswer(
          StreamProbe.unreachable,
          StreamRefusal(status: 401, code: 'unauthenticated'),
        );
      },
    );
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac?mt=old');
    await engine.play();
    platform.player.fail(2);
    await settle();
    expect(asked, <String>['http://x/a.flac?mt=old']);
    expect(failures.single.refusal?.stale, isTrue);
    expect(failures.single.fault, MediaFault.transport);
  });

  test('a load that fails is reported by its throw and not again', () async {
    platform.refuseLoads = true;
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await expectLater(
      engine.load('http://x/a.ape'),
      throwsA(isA<MediaLoadException>()),
    );
    await settle();
    expect(failures, isEmpty);
  });

  test('an error while a replacement load is in flight belongs to that '
      'load', () async {
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    await settle();
    final gate = Completer<void>();
    platform.loadGate = gate;
    final next = engine.load('http://x/b.flac');
    await settle();
    expect(platform.player.loads, 1, reason: 'the replacement is loading');
    platform.player.fail(2);
    await settle();
    gate.complete();
    await next;
    await settle();
    expect(failures, isEmpty);
  });

  test('a failure a new load overtakes is not announced', () async {
    final probe = Completer<ProbeAnswer>();
    final engine = scriptedEngine(ask: (_, {segmentAt}) => probe.future);
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    platform.player.fail(2);
    await settle();
    await engine.load('http://x/b.flac');
    probe.complete(const ProbeAnswer(StreamProbe.unreachable));
    await settle();
    expect(failures, isEmpty);
  });

  test('the same failure again after a successful reload is delivered '
      'again', () async {
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    platform.player.fail(2, 'network');
    await settle();
    await engine.load('http://x/a.flac');
    await engine.play();
    await settle();
    platform.player.fail(2, 'network');
    await settle();
    expect(failures, hasLength(2));
  });

  test(
    'a failure whose URL still answers is the connection, not the file',
    () async {
      // Mid-play, what fails is the way to the file far more often than a
      // file that decoded for minutes; a reload costs little, a skip costs
      // the track.
      final engine = scriptedEngine(
        ask: answering(const ProbeAnswer(StreamProbe.answered)),
      );
      final failures = <MediaFailure>[];
      engine.mediaFailed.listen(failures.add);
      await engine.load('http://x/a.flac');
      await engine.play();
      platform.player.fail(0, 'Source error');
      await settle();
      expect(failures.single.fault, MediaFault.transport);
    },
  );

  test('a file the server will not make audio of is still the file', () async {
    final engine = scriptedEngine(
      ask: answering(const ProbeAnswer(StreamProbe.unplayable)),
    );
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    platform.player.fail(0, 'Source error');
    await settle();
    expect(failures.single.fault, MediaFault.source);
  });

  group('a failure still being probed', () {
    // The announcement waits on the probe, up to its deadline for a host
    // that does not answer, and the listener can act meanwhile.
    late Completer<ProbeAnswer> probe;
    late JustAudioEngine engine;
    late List<MediaFailure> failures;

    setUp(() async {
      probe = Completer<ProbeAnswer>();
      engine = scriptedEngine(ask: (_, {segmentAt}) => probe.future);
      failures = <MediaFailure>[];
      engine.mediaFailed.listen(failures.add);
      await engine.load('http://x/a.flac');
    });

    Future<void> failPlaying() async {
      await engine.play();
      await settle();
      platform.player.fail(2, 'network');
      await settle();
    }

    test('is not announced about media that was stopped', () async {
      await failPlaying();
      await engine.stop();
      probe.complete(ProbeAnswer.unreachable);
      await settle();
      expect(failures, isEmpty);
    });

    test('carries a pause made while it waits', () async {
      await failPlaying();
      await engine.pause();
      probe.complete(ProbeAnswer.unreachable);
      await settle();
      expect(failures.single.wasPlaying, isFalse);
    });

    test('carries a play made while it waits, and starts nothing', () async {
      platform.player.fail(2, 'network');
      await settle();
      final players = platform.players.length;
      await engine.play();
      await settle();
      probe.complete(ProbeAnswer.unreachable);
      await settle();
      expect(failures.single.wasPlaying, isTrue);
      expect(engine.playing, isFalse);
      expect(platform.players, hasLength(players), reason: 'nothing reopened');
    });

    test('stands after a seek, which moves where it picks up', () async {
      await failPlaying();
      await engine.seek(const Duration(seconds: 30));
      probe.complete(ProbeAnswer.unreachable);
      await settle();
      expect(failures, hasLength(1));
      expect(engine.position, const Duration(seconds: 30));
    });

    test('reads loading, never idle, until it is announced', () async {
      await engine.play();
      await settle();
      final seen = <EngineProcessingState>[];
      final sub = engine.processingStateStream.listen(seen.add);
      final read = <EngineProcessingState>[];
      final reader = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => read.add(engine.processingState),
      );
      platform.player.fail(2, 'network');
      await settle();
      reader.cancel();
      expect(seen, isNot(contains(EngineProcessingState.idle)));
      expect(read, isNot(contains(EngineProcessingState.idle)));
      expect(engine.processingState, EngineProcessingState.loading);

      probe.complete(ProbeAnswer.unreachable);
      await settle();
      await sub.cancel();
      expect(failures, hasLength(1));
      expect(
        engine.processingState,
        EngineProcessingState.idle,
        reason: 'once it is said, nothing is loaded',
      );
    });
  });

  test('a replay that cannot reload is reported by its throw and not '
      'again', () async {
    final engine = scriptedEngine();
    final failures = <MediaFailure>[];
    engine.mediaFailed.listen(failures.add);
    await engine.load('http://x/a.flac');
    await engine.play();
    await settle();
    platform.player.emit(
      state: ProcessingStateMessage.completed,
      position: const Duration(minutes: 3),
    );
    await settle();
    platform.refuseLoads = true;
    await expectLater(engine.play(), throwsA(isA<MediaLoadException>()));
    await settle();
    expect(failures, isEmpty);
  });

  test('dispose closes the stream', () async {
    final engine = JustAudioEngine.withPlayer(
      AudioPlayer(handleAudioSessionActivation: false),
      ask: answering(ProbeAnswer.unreachable),
    );
    final done = Completer<void>();
    engine.mediaFailed.listen(null, onDone: done.complete);
    await engine.dispose();
    await done.future.timeout(const Duration(seconds: 1));
  });
}
