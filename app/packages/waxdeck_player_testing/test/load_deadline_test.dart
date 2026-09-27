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
/// released, and the fault decided by the stream probe, which is the
/// only evidence available when the platform reports none.
///
/// Here rather than in waxdeck_player, which carries no test directory
/// of its own.

/// A player whose calls can be made to never settle, the shape of the
/// reported bug.
///
/// Only the members the engine touches are real; anything else reaching
/// `noSuchMethod` is this fake being asked something the test did not
/// mean to exercise.
///
/// Playlist calls run the way just_audio 0.10.6 runs them: one at a
/// time under one lock, in the order they were made, each changing
/// [sequence] when its turn comes and then waiting on the platform. So a
/// call held on the platform holds every playlist call behind it, a
/// load's own reset of the list included, until [land] lets it finish.
class _HangingPlayer implements AudioPlayer {
  _HangingPlayer({
    this.stopHangs = false,
    this.state = ProcessingState.idle,
    this.loadHangs = true,
  });

  /// Whether `stop()` hangs too, which is the honest worst case: a
  /// player that would not finish a load may not finish a stop.
  final bool stopHangs;

  /// What the player reports it is doing. Anything but idle sends
  /// `load` through the stop that precedes a replacement, and completed
  /// sends `play` through the replay.
  ProcessingState state;

  /// Whether a load, once its list is in place, never finishes loading.
  bool loadHangs;

  /// Whether the next add or removal is held on the platform, read as
  /// the call is made.
  bool addHangs = false;
  bool removeHangs = false;

  /// Whether `pause()` or `seek()` never answers.
  bool pauseHangs = false;
  bool seekHangs = false;

  /// How long a `seek()` that does answer takes.
  Duration seekTakes = Duration.zero;

  int stops = 0;
  int loads = 0;
  int plays = 0;

  /// Runs as `stop()` is called, and how long a stop that answers takes.
  void Function()? onStop;
  Duration stopTakes = Duration.zero;

  bool _playing = false;
  final _sequence = <IndexedAudioSource>[];

  /// The tail of the playlist lock, and the calls held on the platform,
  /// oldest first.
  Future<void> _turn = Future<void>.value();
  final _held = <Completer<void>>[];

  final _index = StreamController<int?>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _states = StreamController<ProcessingState>.broadcast();

  /// The window, as the URLs the engine put in it.
  List<String> get urls => [
    for (final source in _sequence) (source as UriAudioSource).uri.toString(),
  ];

  /// Lets the oldest held playlist call finish on the platform.
  void land() => _held.removeAt(0).complete();

  /// Crosses into the item at [index], as the platform walking into it
  /// reports it.
  void cross(int index) => _index.add(index);

  /// Every playlist call made, answered or not.
  int playlistCalls = 0;

  Future<void> _playlist(void Function() change, {required bool hang}) {
    playlistCalls++;
    final done = _turn.then((_) async {
      change();
      if (!hang) return;
      final held = Completer<void>();
      _held.add(held);
      await held.future;
    });
    _turn = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  @override
  Stream<int?> get currentIndexStream => _index.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  ProcessingState get processingState => state;

  @override
  Stream<ProcessingState> get processingStateStream => _states.stream;

  @override
  bool get playing => _playing;

  @override
  List<IndexedAudioSource> get sequence => List.unmodifiable(_sequence);

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loads++;
    final hang = loadHangs;
    await _playlist(
      () => _sequence
        ..clear()
        ..addAll(sources.cast<IndexedAudioSource>()),
      hang: false,
    );
    if (hang) await Completer<void>().future;
    return const Duration(seconds: 3);
  }

  @override
  Future<void> addAudioSource(AudioSource audioSource) => _playlist(
    () => _sequence.add(audioSource as IndexedAudioSource),
    hang: addHangs,
  );

  @override
  Future<void> removeAudioSourceRange(int start, int end) =>
      _playlist(() => _sequence.removeRange(start, end), hang: removeHangs);

  @override
  Future<void> pause() {
    if (pauseHangs) return Completer<void>().future;
    _playing = false;
    return Future<void>.value();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) =>
      seekHangs ? Completer<void>().future : Future<void>.delayed(seekTakes);

  @override
  Future<void> play() {
    plays++;
    _playing = true;
    return Future<void>.value();
  }

  @override
  Future<void> stop() {
    stops++;
    onStop?.call();
    return stopHangs
        ? Completer<void>().future
        : Future<void>.delayed(stopTakes);
  }

  @override
  Future<void> dispose() async {
    await _index.close();
    await _duration.close();
    await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Long enough for any deadline here and the replay's own grace to run
/// out, short enough that a call left hanging fails the test rather than
/// the run.
const _patience = Duration(seconds: 3);

/// An engine over [player] with a deadline short enough to wait out.
JustAudioEngine _engine(
  _HangingPlayer player, {
  required StreamProbe found,
  Duration deadline = const Duration(milliseconds: 40),
}) => JustAudioEngine.withPlayer(
  player,
  loadDeadline: deadline,
  stopGrace: const Duration(milliseconds: 40),
  probe: (_) async => found,
);

void main() {
  test('a load that never settles becomes a fault', () async {
    final player = _HangingPlayer();
    final engine = _engine(player, found: StreamProbe.unreachable);
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
    final engine = _engine(player, found: StreamProbe.answered);
    addTearDown(engine.dispose);

    final fault = await engine
        .load('http://x/a.mp3')
        .then<MediaFault?>((_) => null)
        .onError<MediaLoadException>((e, _) => e.fault);
    expect(fault, MediaFault.source);
  });

  test('a URL that refuses the file is the media too', () async {
    // The case the desktop had no answer for: a file the server will
    // not serve as audio answers 415, mpv sits on it until the
    // deadline, and reading that as the transport left the queue
    // standing on a retry that cannot work. It is the file, so the
    // queue may step past it - the same verdict Android gives the same
    // bytes.
    final player = _HangingPlayer();
    final engine = _engine(player, found: StreamProbe.unplayable);
    addTearDown(engine.dispose);

    final fault = await engine
        .load('http://x/garbage.flac')
        .then<MediaFault?>((_) => null)
        .onError<MediaLoadException>((e, _) => e.fault);
    expect(fault, MediaFault.source);
  });

  test('a URL that reaches nothing is the transport', () async {
    final player = _HangingPlayer();
    final engine = _engine(player, found: StreamProbe.unreachable);
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
    final engine = _engine(player, found: StreamProbe.unreachable);
    addTearDown(engine.dispose);

    await expectLater(
      engine.load('http://x/a.mp3'),
      throwsA(isA<MediaLoadException>()),
    );
    expect(player.stops, 1);
  });

  test('a stop that hangs does not bury the fault', () async {
    final player = _HangingPlayer(stopHangs: true);
    final engine = _engine(player, found: StreamProbe.unreachable);
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
    final engine = _engine(player, found: StreamProbe.unreachable);
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
      probe: (_) async => StreamProbe.unreachable,
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
    // One stop before the replacement, one abandoning it.
    expect(
      player.stops,
      2,
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
    final player = _HangingPlayer(loadHangs: false);
    var probed = false;
    final engine = JustAudioEngine.withPlayer(
      player,
      loadDeadline: const Duration(seconds: 5),
      probe: (_) async {
        probed = true;
        return StreamProbe.answered;
      },
    );
    addTearDown(engine.dispose);

    await engine.load('http://x/a.mp3');
    expect(probed, isFalse);
    expect(player.stops, 0);
  });

  // The window edits run in turn on one future, so a platform call that
  // never answers used to hold up every edit queued behind it - the
  // trim a load's own failure path queues, and the preload drop a stop
  // waits for.
  group('window edits', () {
    test('a preload that never answers is let go at the deadline', () async {
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');

      player.addHangs = true;
      await engine.preloadNext('http://x/b.mp3').timeout(_patience);
      // Nothing behind it is held up either, the stop included.
      await engine.clearPreload().timeout(_patience);
      await engine.stop().timeout(_patience);
    });

    test('a preload that lands after its deadline is still the one', () async {
      // Not cancelled, only no longer waited for, and the caller has
      // recorded it as prepared. Landing while nothing replaced it, it is
      // the preload it was meant to be, and the crossing stays gapless.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.addHangs = true;
      await engine.preloadNext('http://x/b.mp3').timeout(_patience);

      player.land();
      await pumpEventQueue();
      final crossed = engine.itemBoundary.first;
      player.cross(1);

      await crossed.timeout(_patience);
      await pumpEventQueue();
      expect(player.urls, ['http://x/b.mp3']);
    });

    test('a late preload the caller let go is taken out', () async {
      // Landing behind the item playing, where nothing would announce a
      // crossing into it: left there, it plays after this item as a
      // track the queue no longer wants.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.addHangs = true;
      await engine.preloadNext('http://x/b.mp3').timeout(_patience);
      await engine.clearPreload().timeout(_patience);

      player.land();
      await pumpEventQueue();

      expect(player.urls, ['http://x/a.mp3']);
      // And the engine carries on as before.
      await engine.load('http://x/c.mp3');
      expect(player.urls, ['http://x/c.mp3']);
    });

    test('a removal that never answers holds nothing up behind it', () async {
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      await engine.preloadNext('http://x/b.mp3');

      player.removeHangs = true;
      // Said to the caller, who keeps its record of the item as the
      // engine keeps its own: the item is still in the platform's list.
      await expectLater(
        engine.clearPreload().timeout(_patience),
        throwsA(isA<TimeoutException>()),
      );
      // just_audio takes the item out of its own list as the removal's
      // turn starts, so the next preload finds it gone and is let go
      // itself: best effort, behind a call the platform holds.
      await engine.preloadNext('http://x/c.mp3').timeout(_patience);
      await engine.stop().timeout(_patience);

      // Once the platform catches up the drop has landed, and nothing is
      // left over.
      player.land();
      await pumpEventQueue();
      expect(player.urls, ['http://x/a.mp3']);
    });

    test('a preload the platform will not let go stays on record', () async {
      // Cleared from the record while still in the platform's list, the
      // item would play after this one under this one's face, with no
      // session behind it. On record, the crossing into it is announced.
      // The drop is not asked for behind a call the platform holds, a
      // replay's pause here, so the item is still in the list.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      await engine.preloadNext('http://x/b.mp3');
      player
        ..state = ProcessingState.completed
        ..pauseHangs = true;
      await expectLater(
        engine.play().timeout(_patience),
        throwsA(isA<MediaLoadException>()),
      );
      await expectLater(
        engine.clearPreload().timeout(_patience),
        throwsA(isA<TimeoutException>()),
      );
      final crossed = engine.itemBoundary.first;

      player.cross(1);

      await crossed.timeout(_patience);
    });

    test(
      'a load behind a replay that never answered is not the media',
      () async {
        // The replay's reload is a load like any other: one the platform
        // never answers holds the next load behind it.
        final player = _HangingPlayer(loadHangs: false);
        final engine = _engine(player, found: StreamProbe.answered);
        addTearDown(engine.dispose);
        await engine.load('http://x/a.mp3');
        player
          ..state = ProcessingState.completed
          ..loadHangs = true;
        await expectLater(
          engine.play().timeout(_patience),
          throwsA(isA<MediaLoadException>()),
        );

        final fault = await engine
            .load('http://x/b.mp3')
            .then<MediaFault?>((_) => null)
            .onError<MediaLoadException>((e, _) => e.fault);

        expect(fault, MediaFault.transport);
      },
    );

    test(
      'the stop that abandons a load does not decide what it was behind',
      () async {
        // Stopping can shake the held call loose. What the load was held
        // behind is read before that, or a load that never reached the
        // platform is blamed on its file.
        final player = _HangingPlayer(loadHangs: false);
        final engine = _engine(player, found: StreamProbe.answered);
        addTearDown(engine.dispose);
        await engine.load('http://x/a.mp3');
        player.addHangs = true;
        await engine.preloadNext('http://x/b.mp3').timeout(_patience);
        player
          ..onStop = player.land
          ..stopTakes = const Duration(milliseconds: 20);

        final fault = await engine
            .load('http://x/c.mp3')
            .then<MediaFault?>((_) => null)
            .onError<MediaLoadException>((e, _) => e.fault);

        expect(fault, MediaFault.transport);
      },
    );

    test('a stop behind a held call does not wait out a removal', () async {
      // Ending a session stops the engine, and the stop drops the
      // preload. Behind a call the platform holds, that removal would
      // only wait a deadline in turn; it is not asked for.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      await engine.preloadNext('http://x/b.mp3');
      player
        ..state = ProcessingState.completed
        ..pauseHangs = true;
      await expectLater(
        engine.play().timeout(_patience),
        throwsA(isA<MediaLoadException>()),
      );
      final calls = player.playlistCalls;

      await engine.stop().timeout(_patience);

      expect(player.playlistCalls, calls);
    });

    test('a trim waits for the list a load is still building', () async {
      // A load made while an add is held leaves the old list standing
      // until the add lands, because the reset waits its turn behind
      // it. Trimmed then, the removals would reach the platform after
      // the reset and take the new item out of the list it had built.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.addHangs = true;
      await engine.preloadNext('http://x/b.mp3').timeout(_patience);

      await expectLater(
        engine.load('http://x/c.mp3'),
        throwsA(isA<MediaLoadException>()),
      );
      // Held past every deadline the trim could run into, so whatever it
      // asks for is queued behind the reset rather than refused early.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      player.land();
      await pumpEventQueue();

      expect(player.urls, ['http://x/c.mp3']);
    });

    test('a load behind a call the platform holds is not the media', () async {
      // The load never reached the platform: its reset waits in turn
      // behind the held add. Nothing is known about the file, and a
      // probe that answers would blame it and walk the queue one good
      // track at a time.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.addHangs = true;
      await engine.preloadNext('http://x/b.mp3').timeout(_patience);

      final fault = await engine
          .load('http://x/c.mp3')
          .then<MediaFault?>((_) => null)
          .onError<MediaLoadException>((e, _) => e.fault);

      expect(fault, MediaFault.transport);
    });

    test('a held call costs the edits behind it nothing', () async {
      // Everything after a held call waits in turn behind it, so a call
      // made now only spends a deadline. The preload is best effort: it
      // is let go, and the item loads on advance instead.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      await engine.preloadNext('http://x/b.mp3');
      player.removeHangs = true;
      await expectLater(
        engine.clearPreload().timeout(_patience),
        throwsA(isA<TimeoutException>()),
      );
      final calls = player.playlistCalls;

      await engine.preloadNext('http://x/c.mp3');
      await engine.stop();

      expect(player.playlistCalls, calls);
    });

    test('the crossing trims the item it walked out of', () async {
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      await engine.preloadNext('http://x/b.mp3');
      final crossed = engine.itemBoundary.first;

      player.cross(1);
      await crossed;
      await pumpEventQueue();

      expect(player.urls, ['http://x/b.mp3']);
    });
  });

  group('the replay', () {
    // A play after the item ended starts it again, and on the platform
    // that never leaves the completed state by itself - the mpv bridge -
    // that is a reload of the held source: the same platform that
    // declines to finish loads.
    test('a replay that cannot load is a fault, and nothing plays', () async {
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player
        ..state = ProcessingState.completed
        ..loadHangs = true;

      final fault = await engine
          .play()
          .timeout(_patience)
          .then<MediaFault?>((_) => null)
          .onError<MediaLoadException>((e, _) => e.fault);

      // A deadline is the only report there is, and the engine no
      // longer holds a URL to probe: the transport, which offers a
      // retry rather than walking the queue.
      expect(fault, MediaFault.transport);
      expect(player.plays, 0);
      expect(engine.playing, isFalse);
    });

    test('a replay whose seek waits on buffering still plays', () async {
      // Android answers a seek only once the player is ready again, so
      // a replay over a slow link spends its buffering inside the seek:
      // a load's wait, not a stop's.
      final player = _HangingPlayer(loadHangs: false)
        ..seekTakes = const Duration(milliseconds: 200);
      final engine = JustAudioEngine.withPlayer(
        player,
        loadDeadline: const Duration(seconds: 2),
        stopGrace: const Duration(milliseconds: 40),
        probe: (_) async => StreamProbe.answered,
      );
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.state = ProcessingState.completed;

      await engine.play().timeout(_patience);

      expect(player.plays, 1);
    });

    test('a load during a replay takes the player over from it', () async {
      // The listener tapped something else while the finished item was
      // being started again. The replay must neither reload over the new
      // item - interrupting its load - nor start it.
      final player = _HangingPlayer(loadHangs: false);
      final engine = _engine(player, found: StreamProbe.answered);
      addTearDown(engine.dispose);
      await engine.load('http://x/a.mp3');
      player.state = ProcessingState.completed;
      final replay = engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await engine.load('http://x/b.mp3');
      await replay.timeout(_patience);

      expect(player.loads, 2);
      expect(player.plays, 0);
    });

    for (final stall in ['pause', 'seek']) {
      test('a replay whose $stall never answers is a fault too', () async {
        final player = _HangingPlayer(loadHangs: false);
        final engine = _engine(player, found: StreamProbe.answered);
        addTearDown(engine.dispose);
        await engine.load('http://x/a.mp3');
        player
          ..state = ProcessingState.completed
          ..pauseHangs = stall == 'pause'
          ..seekHangs = stall == 'seek';

        await expectLater(
          engine.play().timeout(_patience),
          throwsA(isA<MediaLoadException>()),
        );
        expect(player.plays, 0);
      });
    }
  });
}
