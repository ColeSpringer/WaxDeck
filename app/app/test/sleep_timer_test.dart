import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/player/sleep_timer.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

/// The countdown diffs a wall-clock deadline (fake timers do not move
/// DateTime.now), so tests advance this clock in step with pump.
class _FakeClock {
  DateTime now = DateTime(2026, 7, 18, 22);
  void advance(Duration d) => now = now.add(d);
}

Widget _host(
  FakeRepository repo,
  FakeEngine engine,
  Widget home, {
  _FakeClock? clock,
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(engine),
    if (clock != null) sleepClockProvider.overrideWithValue(() => clock.now),
  ],
  child: MaterialApp(home: home),
);

void main() {
  testWidgets('a preset timer pauses playback when it fires', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid)), clock: clock),
    );
    await tester.pumpAndSettle();
    expect(engine.playing, isTrue);

    await tester.tap(find.byKey(const Key('sleep-timer-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-timer-15')));
    await tester.pumpAndSettle();

    // Not yet: one minute short.
    clock.advance(const Duration(minutes: 14));
    await tester.pump(const Duration(minutes: 14));
    expect(engine.playing, isTrue);

    clock.advance(const Duration(minutes: 1, seconds: 1));
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(engine.playing, isFalse);
  });

  testWidgets('a throttled tick cadence never stretches the countdown', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid)), clock: clock),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sleep-timer-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-timer-15')));
    await tester.pumpAndSettle();

    // The device sleeps past the deadline: wall time races ahead while
    // the throttled timer delivers only a single late tick. That one
    // tick must fire the timer immediately.
    clock.advance(const Duration(minutes: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(engine.playing, isFalse);
  });

  testWidgets('cancel stops the countdown', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid)), clock: clock),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sleep-timer-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-timer-5')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sleep-timer-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sleep-timer-cancel')));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    expect(engine.playing, isTrue);
  });

  testWidgets('end-of-chapter mode pauses at the chapter boundary', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(
        bookPid,
        durationMs: 3600000,
        chapters: const [
          ChapterMark(index: 0, title: 'One', startMs: 0),
          ChapterMark(index: 1, title: 'Two', startMs: 60000),
        ],
      );
    final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
    await tester.pumpWidget(
      _host(
        repo,
        engine,
        PlayerScreen(
          item: ItemSummary(
            pid: bookPid,
            mediaType: MediaType.audiobook,
            title: 'There And Back Again',
            durationMs: 3600000,
          ),
          initialPositionMs: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sleep-timer-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sleep-timer-chapter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-timer-chapter')));
    await tester.pumpAndSettle();

    engine.advance(const Duration(seconds: 59));
    await tester.pump();
    expect(engine.playing, isTrue);

    engine.advance(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);
  });
}
