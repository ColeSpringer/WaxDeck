import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/playback_session.dart';
import 'package:waxdeck/src/player/smart_rewind.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

/// A clock a test can move without waiting.
class _Clock {
  DateTime now = DateTime.utc(2026, 8, 2, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

FakeRepository _repo({SkipMap? skips, double? speed}) {
  final repo = FakeRepository()
    ..addSubscription(
      testShow(_showPid),
      settings: SubscriptionSettings(speed: speed, trimSilence: skips != null),
    )
    ..episodesByShow[_showPid] = [testEpisode(_episodePid)];
  if (skips != null) repo.skipMaps[_episodePid] = skips;
  return repo;
}

/// Everything the accounting needs, wired to a clock the test moves.
///
/// The two clocks travel together on purpose: [FakeEngine.advance] takes
/// wall time and moves the position by wall times rate, which is what a
/// real engine does, so stepping both by the same amount is what makes
/// the reported saving mean anything.
class _Harness {
  _Harness({SkipMap? skips, double? speed})
    : repo = _repo(skips: skips, speed: speed),
      engine = FakeEngine(mediaDuration: const Duration(minutes: 30));

  final FakeRepository repo;
  final FakeEngine engine;
  final _Clock clock = _Clock();
  late final PlaybackSession session = PlaybackSession(
    repository: repo,
    engine: engine,
    item: testEpisode(_episodePid),
    clientId: 'test',
    clock: clock.call,
    // Off, so nothing steps the position sideways behind the arithmetic
    // under test. Its own tests cover the ladder.
    smartRewind: SmartRewind.off,
  );

  Future<void> start() async {
    await session.start();
    await pumpEventQueue();
  }

  /// Spends [wall] seconds of somebody's life, a step at a time.
  ///
  /// Small steps because the listen accounting only counts position
  /// deltas that look like ordinary progress: at 2x a one-second step is
  /// already two seconds of content, which is the edge of what counts.
  Future<void> listen(int wallSeconds) async {
    for (var i = 0; i < wallSeconds * 2; i++) {
      clock.advance(const Duration(milliseconds: 500));
      engine.advance(const Duration(milliseconds: 500));
      await pumpEventQueue();
    }
  }

  Future<void> pauseFor(Duration idle) async {
    await engine.pause();
    await pumpEventQueue();
    clock.advance(idle);
  }

  Future<void> resume() async {
    await engine.play();
    await pumpEventQueue();
  }

  /// The session's own report, once it has let go.
  Future<ListenSession> report() async {
    await session.dispose();
    await pumpEventQueue();
    expect(repo.reportedSessions, hasLength(1));
    return repo.reportedSessions.single;
  }
}

void main() {
  test('at ordinary speed with nothing trimmed, nothing was saved', () async {
    final harness = _Harness();
    await harness.start();
    await harness.listen(20);

    final report = await harness.report();
    expect(report.msPlayed, closeTo(20000, 1000));
    // Null rather than zero: the field is omitted when neither thing
    // that saves time happened.
    expect(report.skippedMs, isNull);
  });

  test('playing at double speed saves the half nobody sat through', () async {
    final harness = _Harness(speed: 2);
    await harness.start();
    await harness.listen(20);

    final report = await harness.report();
    // Forty seconds of content out of twenty seconds of somebody's
    // evening.
    expect(report.msPlayed, closeTo(40000, 2000));
    expect(report.skippedMs, closeTo(20000, 2000));
  });

  test('a hand on the seek bar is not a saving', () async {
    final harness = _Harness();
    await harness.start();
    await harness.listen(5);
    // Ten minutes of position, no time at all: the thing a naive
    // content-minus-wall reading counts as ten minutes saved.
    await harness.session.seek(const Duration(minutes: 10));
    await pumpEventQueue();
    await harness.listen(5);

    final report = await harness.report();
    expect(report.msPlayed, closeTo(10000, 1000));
    expect(report.skippedMs, isNull);
  });

  test('silence trimmed is time saved, at ordinary speed', () async {
    final harness = _Harness(
      skips: const SkipMap(
        state: 'ready',
        spans: <SkipSpan>[SkipSpan(startMs: 10000, endMs: 40000)],
      ),
    );
    await harness.start();
    // Past the span, which jumps thirty seconds forward for free.
    await harness.listen(20);

    final report = await harness.report();
    expect(harness.engine.position.inSeconds, greaterThan(40));
    expect(report.skippedMs, closeTo(30000, 1500));
  });

  test('trimming and speed add up rather than replacing each other', () async {
    final harness = _Harness(
      speed: 2,
      skips: const SkipMap(
        state: 'ready',
        spans: <SkipSpan>[SkipSpan(startMs: 10000, endMs: 40000)],
      ),
    );
    await harness.start();
    await harness.listen(20);

    final report = await harness.report();
    // Twenty seconds spent. Forty seconds of content heard, plus thirty
    // jumped: seventy seconds of episode for twenty seconds of evening.
    expect(report.skippedMs, closeTo(50000, 3000));
  });

  test('a stall does not eat what was already saved', () async {
    final harness = _Harness(speed: 2);
    await harness.start();
    await harness.listen(10);

    // The engine still says playing and the clock still runs, but no
    // audio arrives: a rebuffer, a phone asleep in a pocket, a browser
    // tab throttled in the background. Content-minus-wall-clock reads
    // this as the listener sitting there and quietly deletes the saving.
    harness.clock.advance(const Duration(minutes: 4));
    await pumpEventQueue();

    final report = await harness.report();
    expect(report.skippedMs, closeTo(10000, 1000));
  });

  test('a rate raised mid-episode is priced from where it changed', () async {
    final harness = _Harness();
    await harness.start();
    await harness.listen(10);
    await harness.engine.setSpeed(2);
    await pumpEventQueue();
    await harness.listen(10);

    final report = await harness.report();
    // Ten seconds at 1x is ten seconds of content and nothing saved; ten
    // more at 2x is twenty seconds of content and ten saved.
    expect(report.msPlayed, closeTo(30000, 2000));
    expect(report.skippedMs, closeTo(10000, 1000));
  });

  test('a pause costs the listener nothing and saves them nothing', () async {
    final harness = _Harness(speed: 2);
    await harness.start();
    await harness.listen(10);
    await harness.pauseFor(const Duration(hours: 3));
    await harness.resume();
    await harness.listen(10);

    final report = await harness.report();
    // The three hours are not wall clock this listener spent listening,
    // so they neither dilute the saving nor add to it.
    expect(report.skippedMs, closeTo(20000, 2000));
  });
}
