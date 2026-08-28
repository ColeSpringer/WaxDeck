import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:waxdeck_player/waxdeck_player.dart';

/// The deadline that turns "never answers" into a fault.
///
/// mpv through media_kit does not report a failed load - it simply
/// never finishes one - so on desktop there was nothing to classify and
/// nothing for the session to give up on. These pin the engine's own
/// answer to that: past the deadline the load is abandoned, the source
/// released, and the fault decided by the reachability probe, which is
/// the only evidence available when the platform reports none.
///
/// Here rather than in waxdeck_player, which carries no test directory
/// of its own.

/// A player whose load never settles, the shape of the reported bug.
///
/// Only the members the engine's load path touches are real; anything
/// else reaching `noSuchMethod` is this fake being asked something the
/// test did not mean to exercise.
class _HangingPlayer implements AudioPlayer {
  _HangingPlayer({this.stopHangs = false, this.state = ProcessingState.idle});

  /// Whether `stop()` hangs too, which is the honest worst case: a
  /// player that would not finish a load may not finish a stop.
  final bool stopHangs;

  /// What the player reports it is doing. Anything but idle sends
  /// `load` through the stop that precedes a replacement.
  final ProcessingState state;

  int stops = 0;
  int loads = 0;

  final _index = StreamController<int?>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  @override
  Stream<int?> get currentIndexStream => _index.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  ProcessingState get processingState => state;

  @override
  List<IndexedAudioSource> get sequence => const <IndexedAudioSource>[];

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    loads++;
    return Completer<Duration?>().future;
  }

  @override
  Future<void> stop() {
    stops++;
    return stopHangs ? Completer<void>().future : Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    await _index.close();
    await _duration.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// An engine over [player] with a deadline short enough to wait out.
JustAudioEngine _engine(
  _HangingPlayer player, {
  required bool reachable,
  Duration deadline = const Duration(milliseconds: 40),
}) => JustAudioEngine.withPlayer(
  player,
  loadDeadline: deadline,
  stopGrace: const Duration(milliseconds: 40),
  probe: (_) async => reachable,
);

void main() {
  test('a load that never settles becomes a fault', () async {
    final player = _HangingPlayer();
    final engine = _engine(player, reachable: false);
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/a.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    expect(player.loads, 1);
  });

  test('a URL that answers while the player will not is the media', () async {
    // The desktop's whole classification: nothing came back from the
    // platform, so the only evidence is whether the bytes are there to
    // be had. They are, and the player still could not finish - which
    // is what garbage on disk looks like from out here, and what
    // Android reports directly.
    final player = _HangingPlayer();
    final engine = _engine(player, reachable: true);
    addTearDown(engine.dispose);

    final fault = await engine
        .load('http://x/a.mp3')
        .then<MediaFault?>((_) => null)
        .onError<MediaLoadException>((e, _) => e.fault);
    expect(fault, MediaFault.source);
  });

  test('a URL that does not answer is the transport', () async {
    final player = _HangingPlayer();
    final engine = _engine(player, reachable: false);
    addTearDown(engine.dispose);

    final fault = await engine
        .load('http://x/a.mp3')
        .then<MediaFault?>((_) => null)
        .onError<MediaLoadException>((e, _) => e.fault);
    expect(fault, MediaFault.transport);
  });

  test('the abandoned load releases its source', () async {
    // just_audio has no cancel, so the source stays attached until
    // something replaces it, and on the mpv bridge that keeps the file
    // open. The stop is what releases it.
    final player = _HangingPlayer();
    final engine = _engine(player, reachable: false);
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/a.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    expect(player.stops, 1);
  });

  test('a stop that hangs does not bury the fault', () async {
    final player = _HangingPlayer(stopHangs: true);
    final engine = _engine(player, reachable: false);
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/a.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    expect(player.stops, 1);
  });

  test('a stop that hangs before a load does not swallow the load', () async {
    // The hole the deadline would otherwise leave open: the stop that
    // precedes a replacement runs against a player already mid-hang, so
    // an unbounded wait there moves the hang one call along - no
    // deadline reached, no fault, no pane. Exactly the bug this whole
    // change exists to close, one line above where it was closed.
    final player = _HangingPlayer(
      stopHangs: true,
      state: ProcessingState.ready,
    );
    final engine = _engine(player, reachable: false);
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/a.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    // The pre-load stop gave up and the load was still attempted; the
    // abandonment stop is the second.
    expect(player.loads, 1);
    expect(player.stops, 2);
  });

  test('a load the listener replaced does not stop what took over', () async {
    // A load is deliberately interruptible, and fifteen seconds is long
    // enough for a listener to tap something else. The abandoned load's
    // stop would otherwise land on the item that took the player over,
    // silencing a track nothing reported a fault for.
    final player = _HangingPlayer();
    final engine = JustAudioEngine.withPlayer(
      player,
      loadDeadline: const Duration(milliseconds: 200),
      stopGrace: const Duration(milliseconds: 40),
      probe: (_) async => false,
    );
    addTearDown(engine.dispose);

    // Handled the moment it is made: the abandoned load fails while the
    // replacement is still in flight, and an unhandled rejection there
    // would fail this test for the wrong reason.
    final abandoned = engine
        .load('http://x/slow.mp3')
        .then<Object?>((_) => null)
        .onError<MediaLoadException>((e, _) => e);
    // The replacement bumps the generation the first load finds changed
    // when its own deadline fires. Both are refused; only the surviving
    // one may touch the player.
    await expectLater(
      engine.load('http://x/next.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    expect(await abandoned, isA<MediaLoadException>());
    expect(
      player.stops,
      1,
      reason: 'the abandoned load stopped the player that replaced it',
    );
  });

  test('a probe that breaks leaves the transport standing', () async {
    // The port promises MediaLoadException and nothing else.
    final player = _HangingPlayer();
    final engine = JustAudioEngine.withPlayer(
      player,
      loadDeadline: const Duration(milliseconds: 40),
      probe: (_) => throw StateError('probe broke'),
    );
    addTearDown(engine.dispose);

    final fault = await engine
        .load('http://x/a.mp3')
        .then<MediaFault?>((_) => null)
        .onError<MediaLoadException>((e, _) => e.fault);
    expect(fault, MediaFault.transport);
  });

  test('a load that answers inside the deadline is left alone', () async {
    // The deadline is an outer bound, not a budget every load is
    // measured against: nothing is stopped and nothing is probed.
    final player = _SettlingPlayer();
    var probed = false;
    final engine = JustAudioEngine.withPlayer(
      player,
      loadDeadline: const Duration(seconds: 5),
      probe: (_) async {
        probed = true;
        return true;
      },
    );
    addTearDown(engine.dispose);

    await engine.load('http://x/a.mp3');
    expect(probed, isFalse);
    expect(player.stops, 0);
  });
}

/// A player that loads, so the deadline has something to not fire on.
class _SettlingPlayer extends _HangingPlayer {
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loads++;
    return const Duration(seconds: 3);
  }
}
