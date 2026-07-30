import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

/// Tuning races, which all turn on the same thing: a tune suspends
/// several times before it owns the engine, and everything that can take
/// the engine from it happens during those gaps.
///
/// The generation counter is what settles them, and where it is claimed
/// is the whole design. Claimed after the first await it is handed out in
/// completion order rather than tap order, so the tap that came first can
/// wake last and outrank the station the listener actually asked for -
/// and until it is claimed, a tune is invisible to the stop and the item
/// session that are supposed to be able to cancel it.
RadioStation _station(String pid, String name) => RadioStation(
  pid: pid,
  name: name,
  streamUrl: 'https://stream.example/$pid',
  createdAt: DateTime.utc(2026, 7, 1),
);

void main() {
  testWidgets('the last tap owns the engine, whichever tune wakes first', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final coastal = _station('ra-1', 'Coastal FM');
    final deck = _station('ra-2', 'Deck Radio');
    for (final station in [coastal, deck]) {
      repo.radioStationsByPid[station.pid] = station;
    }
    final engine = FakeEngine();
    final container = playbackContainer(repo: repo, engine: engine);
    final harness = PlayerHarness(container);
    harness.play([testItem('tr-A')]);
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    // Both taps land before either tune has the engine. The first parks
    // inside the item's pause, and because the engine drops its playing
    // flag on the way in, the second reads it as stopped, skips the pause
    // entirely, and runs on: the tune that started first is the one that
    // resumes last. Claimed after that await, the counter would hand the
    // higher generation to the earlier tap and let it win.
    final radio = container.read(radioPlaybackProvider.notifier);
    final gate = Completer<void>();
    engine.pauseGate = gate;
    final first = radio.play(coastal);
    final second = radio.play(deck);
    engine.pauseGate = null;
    gate.complete();
    await first;
    await second;
    await tester.pumpAndSettle();

    expect(
      container.read(radioPlaybackProvider).station?.pid,
      deck.pid,
      reason: 'the station named is the one tapped last',
    );
    expect(
      engine.loadedUrl,
      contains(deck.pid),
      reason: 'and it is the one the engine is actually playing',
    );

    await radio.stop();
    await harness.endPlayback(tester);
  });

  testWidgets('an item taking the engine cancels a tune still in its pause', (
    tester,
  ) async {
    // The window the state check missed: until a tune has published its
    // station, `state.station` is null, so a guard reading it decided
    // there was no tune to cancel - and the tune woke up, loaded its
    // stream over the item that had just started, and left a title poll
    // running against it.
    final repo = FakeRepository(items: [testItem('tr-A'), testItem('tr-B')]);
    final station = _station('ra-1', 'Coastal FM');
    repo.radioStationsByPid[station.pid] = station;
    final engine = FakeEngine();
    final container = playbackContainer(repo: repo, engine: engine);
    final harness = PlayerHarness(container);
    harness.play([testItem('tr-A')]);
    await tester.pumpAndSettle();

    // Held open so the tune is provably still inside its first await when
    // the item takes the engine.
    final gate = Completer<void>();
    engine.pauseGate = gate;
    final tune = container.read(radioPlaybackProvider.notifier).play(station);
    container.read(nowPlayingProvider.notifier).play([
      testItem('tr-B'),
    ], source: playedAlone(testItem('tr-B')));
    engine.pauseGate = null;
    gate.complete();
    await tune;
    await tester.pumpAndSettle();

    expect(
      container.read(radioPlaybackProvider).station,
      isNull,
      reason: 'the item owns the engine, so the tune is off',
    );
    expect(
      engine.loadedUrl,
      contains('tr-B'),
      reason: 'the station must not load over the item that just started',
    );

    await harness.endPlayback(tester);
  });

  testWidgets('a stop lands on a tune that has not named its station yet', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final station = _station('ra-1', 'Coastal FM');
    repo.radioStationsByPid[station.pid] = station;
    final engine = FakeEngine();
    final container = playbackContainer(repo: repo, engine: engine);
    final harness = PlayerHarness(container);
    harness.play([testItem('tr-A')]);
    await tester.pumpAndSettle();

    final radio = container.read(radioPlaybackProvider.notifier);
    final gate = Completer<void>();
    engine.pauseGate = gate;
    final tune = radio.play(station);
    await radio.stop();
    engine.pauseGate = null;
    gate.complete();
    await tune;
    await tester.pumpAndSettle();

    expect(container.read(radioPlaybackProvider).station, isNull);
    expect(
      engine.loadedUrl,
      contains('tr-A'),
      reason: 'a stopped tune never opens its stream',
    );

    await harness.endPlayback(tester);
  });

  testWidgets('a tune leaves the item paused, however many are in flight', (
    tester,
  ) async {
    // The item is paused so it stops writing checkpoints, and nothing in
    // a second tune may put it back: `pause` is idempotent where the
    // session's `toggle` is not, so this holds whatever order the two
    // tunes reach the engine in.
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final coastal = _station('ra-1', 'Coastal FM');
    final deck = _station('ra-2', 'Deck Radio');
    for (final station in [coastal, deck]) {
      repo.radioStationsByPid[station.pid] = station;
    }
    final engine = FakeEngine();
    final container = playbackContainer(repo: repo, engine: engine);
    final harness = PlayerHarness(container);
    harness.play([testItem('tr-A')]);
    await tester.pumpAndSettle();

    final radio = container.read(radioPlaybackProvider.notifier);
    final gate = Completer<void>();
    engine.pauseGate = gate;
    final first = radio.play(coastal);
    final second = radio.play(deck);
    engine.pauseGate = null;
    gate.complete();
    // The station that wins does not open its stream, or the engine plays
    // either way and the item's own state cannot be read off it.
    engine.failNextLoad = true;
    await first;
    await expectLater(second, throwsA(isA<MediaWillNotOpen>()));
    await tester.pumpAndSettle();

    expect(
      engine.playing,
      isFalse,
      reason: 'the item was paused for the tune and nothing resumed it',
    );

    await harness.endPlayback(tester);
  });
}
