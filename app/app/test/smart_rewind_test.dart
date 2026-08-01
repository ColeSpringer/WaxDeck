import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/player/smart_rewind.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

/// A clock a test can move without waiting.
class _Clock {
  DateTime now = DateTime.utc(2026, 8, 1, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

PlaybackSession _session({
  required FakeRepository repo,
  required FakeEngine engine,
  required ItemSummary item,
  required _Clock clock,
  SmartRewind rewind = SmartRewind.short,
  int? initialPositionMs,
}) => PlaybackSession(
  repository: repo,
  engine: engine,
  item: item,
  clientId: 'test',
  smartRewind: rewind,
  clock: clock.call,
  initialPositionMs: initialPositionMs,
);

void main() {
  group('the ladder', () {
    test('does nothing under the first threshold', () {
      expect(
        SmartRewind.short.rewindFor(const Duration(minutes: 4)),
        Duration.zero,
      );
      expect(
        SmartRewind.long.rewindFor(const Duration(minutes: 4)),
        Duration.zero,
      );
    });

    test('steps back further the longer the pause was', () {
      const ladder = SmartRewind.short;
      expect(
        ladder.rewindFor(const Duration(minutes: 5)),
        const Duration(seconds: 3),
      );
      expect(
        ladder.rewindFor(const Duration(hours: 2)),
        const Duration(seconds: 10),
      );
      expect(
        ladder.rewindFor(const Duration(days: 3)),
        const Duration(seconds: 30),
      );
    });

    test('off never moves, however long the pause', () {
      expect(
        SmartRewind.off.rewindFor(const Duration(days: 30)),
        Duration.zero,
      );
    });
  });

  group('resuming an item', () {
    test('starts behind the checkpoint when it is old enough', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
        ..playPositions[_episodePid] = 120000
        ..playStateUpdatedAt[_episodePid] = clock.now.subtract(
          const Duration(hours: 2),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start();

      // Two minutes in, paused two hours ago: the ladder's middle rung.
      expect(engine.position, const Duration(milliseconds: 110000));
      await session.dispose();
    });

    test('starts on the checkpoint when the break was short', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
        ..playPositions[_episodePid] = 120000
        ..playStateUpdatedAt[_episodePid] = clock.now.subtract(
          const Duration(minutes: 1),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start();

      expect(engine.position, const Duration(milliseconds: 120000));
      await session.dispose();
    });

    test('leaves music alone however long it stood', () async {
      final clock = _Clock();
      final repo = FakeRepository(items: [testItem(_trackPid)])
        ..playPositions[_trackPid] = 100000
        ..playStateUpdatedAt[_trackPid] = clock.now.subtract(
          const Duration(days: 4),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 214000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testItem(_trackPid),
        clock: clock,
      );
      await session.start();

      // A track resumed after a week starts where it stopped: rewinding
      // three seconds into a song is noise, not context.
      expect(engine.position, const Duration(milliseconds: 100000));
      await session.dispose();
    });

    test('honours an asked-for position exactly', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
        ..playPositions[_episodePid] = 120000
        ..playStateUpdatedAt[_episodePid] = clock.now.subtract(
          const Duration(days: 2),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
        // A chapter tap or a shared timestamp: a request for a place,
        // not a resume, so nothing moves it.
        initialPositionMs: 90000,
      );
      await session.start();

      expect(engine.position, const Duration(milliseconds: 90000));
      await session.dispose();
    });
  });

  group('a queue put back at launch', () {
    test('stands where the checkpoint says until it is played', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
        ..playPositions[_episodePid] = 120000
        ..playStateUpdatedAt[_episodePid] = clock.now.subtract(
          const Duration(days: 2),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start(autoplay: false);

      // Loaded, not played. The step is owed to the first play and has
      // not been taken yet.
      expect(engine.position, const Duration(milliseconds: 120000));

      // Closing without playing writes the checkpoint back, so a step
      // taken here would walk the book backwards once per launch: ten
      // cold starts nobody listened to would lose five minutes.
      await session.dispose();
      expect(repo.putPlayStateCalls.last.positionMs, 120000);
    });

    test('spends the step on the first play, however it arrives', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
        ..playPositions[_episodePid] = 120000
        ..playStateUpdatedAt[_episodePid] = clock.now.subtract(
          const Duration(days: 2),
        );
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start(autoplay: false);

      // Straight at the engine, which is what a lock-screen button, a
      // headset, a media key, and a routed Connect command all do.
      await engine.play();
      await Future<void>.delayed(Duration.zero);
      expect(engine.position, const Duration(milliseconds: 90000));
      await session.dispose();
    });
  });

  group('resuming after a pause', () {
    test('steps back from a play the session never saw', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start();
      engine.advance(const Duration(minutes: 3));

      // Paused and played through the engine rather than the session:
      // the overnight resume this feature is for is most often a
      // lock-screen press, which never reaches a WaxDeck control.
      await engine.pause();
      clock.advance(const Duration(hours: 3));
      await engine.play();
      await Future<void>.delayed(Duration.zero);

      expect(engine.position, const Duration(seconds: 170));
      await session.dispose();
    });

    test('steps back by how long the pause was', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start();
      engine.advance(const Duration(minutes: 3));

      await session.toggle();
      expect(engine.playing, isFalse);
      clock.advance(const Duration(hours: 3));
      await session.toggle();

      expect(engine.playing, isTrue);
      expect(engine.position, const Duration(seconds: 170));
      await session.dispose();
    });

    test('a pause the listener came right back from moves nothing', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
      );
      await session.start();
      engine.advance(const Duration(minutes: 3));

      await session.toggle();
      clock.advance(const Duration(seconds: 20));
      await session.toggle();

      expect(engine.position, const Duration(minutes: 3));
      await session.dispose();
    });

    test('never steps back past the start of the item', () async {
      final clock = _Clock();
      final repo = FakeRepository()
        ..addSubscription(testShow(_showPid))
        ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 900000),
      );
      final session = _session(
        repo: repo,
        engine: engine,
        item: testEpisode(_episodePid),
        clock: clock,
        rewind: SmartRewind.long,
      );
      await session.start();
      engine.advance(const Duration(seconds: 4));

      await session.toggle();
      clock.advance(const Duration(days: 2));
      await session.toggle();

      expect(engine.position, Duration.zero);
      await session.dispose();
    });
  });
}
