import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/player/sleep_timer.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const bookPid = 'bk-01JZX5N8QW3F4V9T2B7KDBOOK01';

/// The countdown diffs a wall-clock deadline (fake timers do not move
/// DateTime.now), so tests advance this clock in step with pump.
class _FakeClock {
  DateTime now = DateTime(2026, 7, 18, 22);
  void advance(Duration d) => now = now.add(d);
}

/// The player over a container whose sleep-timer clock the test drives.
ProviderContainer _container(
  FakeRepository repo,
  FakeEngine engine,
  _FakeClock clock,
) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      sleepClockProvider.overrideWithValue(() => clock.now),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('a preset timer pauses playback when it fires', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: _container(repo, engine, clock),
    );
    expect(engine.playing, isTrue);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(15)));
    await tester.pumpAndSettle();

    // Not yet: one minute short.
    clock.advance(const Duration(minutes: 14));
    await tester.pump(const Duration(minutes: 14));
    expect(engine.playing, isTrue);

    // The pump carries the ramp as well as the last minute.
    clock.advance(const Duration(minutes: 1, seconds: 1));
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(engine.playing, isFalse);
    await harness.endPlayback(tester);
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
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: _container(repo, engine, clock),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(15)));
    await tester.pumpAndSettle();

    // The device sleeps past the deadline: wall time races ahead while
    // the throttled timer delivers only a single late tick. That one
    // tick must fire the timer immediately.
    clock.advance(const Duration(minutes: 20));
    await tester.pump(const Duration(seconds: 1));
    // Firing starts the fade, not the pause.
    expect(engine.playing, isTrue);
    await tester.pump(
      SleepTimerController.fadeDuration + SleepTimerController.fadeStep,
    );
    expect(engine.playing, isFalse);
    await harness.endPlayback(tester);
  });

  testWidgets('cancel stops the countdown', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: _container(repo, engine, clock),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerCancel));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    expect(engine.playing, isTrue);
    await harness.endPlayback(tester);
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
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: const ItemSummary(
        pid: bookPid,
        mediaType: MediaType.audiobook,
        title: 'There And Back Again',
        durationMs: 3600000,
      ),
      positionMs: 0,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerChapter),
      findsOneWidget,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerChapter),
    );
    await tester.pumpAndSettle();

    engine.advance(const Duration(seconds: 59));
    await tester.pump();
    expect(engine.playing, isTrue);

    engine.advance(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(engine.playing, isFalse);
    // Never ramps: onPosition fires past the boundary, so a ramp would
    // fade the next chapter.
    expect(engine.volume, closeTo(1, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('the countdown ramps down, pauses, and puts the level back', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );
    await container.read(outputVolumeProvider.notifier).set(0.8);
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Mid-ramp: quieter, still playing, still reading active.
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);
    expect(engine.playing, isTrue);
    expect(engine.volume, lessThan(0.8));
    expect(
      container.read(sleepTimerProvider).active,
      isTrue,
      reason: 'a timer that reads inactive over fading audio is lying',
    );

    await tester.pump(SleepTimerController.fadeDuration);
    expect(engine.playing, isFalse);
    // Back once the audio stopped, or the next play starts silent.
    expect(engine.volume, closeTo(0.8, 0.001));
    expect(container.read(outputVolumeProvider), closeTo(0.8, 0.001));
    expect(container.read(sleepTimerProvider).active, isFalse);
    await harness.endPlayback(tester);
  });

  testWidgets('a level moved mid-fade ends the ramp and is left alone', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);

    // A drag, or a routed set-volume: either way it is theirs now.
    await container.read(outputVolumeProvider.notifier).set(0.35);
    await tester.pump(SleepTimerController.fadeDuration);

    // Still pauses; only the ramp was abandoned, and the level it would
    // have restored was not its own.
    expect(engine.playing, isFalse);
    expect(engine.volume, closeTo(0.35, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('a platform refusal ends the ramp without restoring', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    // The first write is refused, so the ramp owns nothing to put back.
    engine.failNextSetVolume = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(
      SleepTimerController.fadeDuration + SleepTimerController.fadeStep,
    );

    expect(engine.playing, isFalse);
    expect(engine.volume, closeTo(1, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('a refusal part way down still puts the level back', (
    tester,
  ) async {
    // The ramp had already lowered the level and still owns it, so the
    // refusal ends the fade but must not leave the listener quiet.
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );
    await container.read(outputVolumeProvider.notifier).set(0.8);
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);
    expect(engine.volume, lessThan(0.8));

    engine.failNextSetVolume = true;
    await tester.pump(SleepTimerController.fadeDuration);

    expect(engine.playing, isFalse);
    expect(engine.volume, closeTo(0.8, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('cancelling mid-fade stops the ramp and the pause', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);

    // Awake after all: the ramp stops and nothing pauses.
    container.read(sleepTimerProvider.notifier).cancel();
    await tester.pump(SleepTimerController.fadeDuration);

    expect(engine.playing, isTrue);
    // And at the level they were listening at, not the fade's residue.
    expect(engine.volume, closeTo(1, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('re-arming mid-fade puts the level back too', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );
    await container.read(outputVolumeProvider.notifier).set(0.6);
    await tester.pump();

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);
    expect(engine.volume, lessThan(0.6));

    container.read(sleepTimerProvider.notifier).startMinutes(30);
    await tester.pump(SleepTimerController.fadeDuration);

    expect(engine.playing, isTrue);
    expect(engine.volume, closeTo(0.6, 0.001));
    expect(container.read(sleepTimerProvider).active, isTrue);
    container.read(sleepTimerProvider.notifier).cancel();
    await harness.endPlayback(tester);
  });

  testWidgets('a cancel after a drag leaves the dragged level alone', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(SleepTimerController.fadeDuration ~/ 2);

    // The ramp stops owning the level here, so the cancel has nothing to
    // put back and must not overwrite what the listener chose.
    await container.read(outputVolumeProvider.notifier).set(0.25);
    container.read(sleepTimerProvider.notifier).cancel();
    await tester.pump(SleepTimerController.fadeDuration);

    expect(engine.playing, isTrue);
    expect(engine.volume, closeTo(0.25, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('extending buys ten more minutes from where it stood', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    clock.advance(const Duration(minutes: 4));
    await tester.pump(const Duration(minutes: 4));
    expect(container.read(sleepTimerProvider).remaining!.inSeconds, 60);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerExtend));
    await tester.pumpAndSettle();

    // From where it stood, not from now: one minute left plus ten is
    // eleven, which is what "not yet" means at that point.
    expect(container.read(sleepTimerProvider).remaining!.inSeconds, 11 * 60);

    clock.advance(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 10));
    expect(engine.playing, isTrue);
    container.read(sleepTimerProvider.notifier).cancel();
    await harness.endPlayback(tester);
  });

  testWidgets('the notification carries the extension while a timer runs', (
    tester,
  ) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    final session = _FakeMediaSession();
    container.read(mediaSessionProvider).bind(session);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: container,
    );
    expect(session.extra, isNull);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    // The whole time a timer runs rather than only during the fade: a
    // listener who wants another ten minutes usually knows before the
    // sound starts going.
    expect(session.extra?.label, 'Extend 10 min');

    // And it is a real control, not a label: pressing it extends.
    session.extra!.onPressed();
    await tester.pump();
    expect(container.read(sleepTimerProvider).remaining!.inSeconds, 15 * 60);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerCancel));
    await tester.pumpAndSettle();
    expect(session.extra, isNull);
    await harness.endPlayback(tester);
  });
}

/// A media session that records the one extra control the app raises.
class _FakeMediaSession implements MediaSessionPort {
  MediaSessionExtra? extra;

  @override
  void showExtra(MediaSessionExtra? value) => extra = value;
}
