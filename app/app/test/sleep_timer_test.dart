import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/player/sleep_timer.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player/waxdeck_player.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'localized_host.dart';
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
      wallClockProvider.overrideWithValue(() => clock.now),
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

  testWidgets('a timer firing over a station lets the station go', (
    tester,
  ) async {
    // Pausing the engine alone left the face and the deck bar naming a
    // station nothing was playing.
    const stationPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1';
    final station = RadioStation(
      pid: stationPid,
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    final repo = FakeRepository()..radioStationsByPid[stationPid] = station;
    final engine = FakeEngine();
    final clock = _FakeClock();
    final container = _container(repo, engine, clock);
    await container.read(radioPlaybackProvider.notifier).play(station);
    expect(engine.playing, isTrue);

    container.read(sleepTimerProvider.notifier).startMinutes(15);
    clock.advance(const Duration(minutes: 16));
    await tester.pump(const Duration(minutes: 16));
    await tester.pump(
      SleepTimerController.fadeDuration + SleepTimerController.fadeStep,
    );
    await tester.pumpAndSettle();

    expect(engine.playing, isFalse);
    expect(container.read(radioPlaybackProvider).station, isNull);
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
  test('the extend button follows the app language', () async {
    final container = ProviderContainer(
      overrides: [localeOverrideProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    container.read(systemLocalesProvider.notifier).locales = const [
      Locale('en'),
    ];
    final session = _FakeMediaSession();
    container.read(mediaSessionProvider).bind(session);
    final timer = container.read(sleepTimerProvider.notifier)..startMinutes(5);
    addTearDown(timer.cancel);
    expect(session.extra?.label, 'Extend 10 min');

    container.read(systemLocalesProvider.notifier).locales = const [
      Locale('es'),
    ];
    await pumpEventQueue();

    expect(session.extra?.label, 'Ampliar 10 min');
  });

  testWidgets('a running timer says what is left in words', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: _container(repo, engine, _FakeClock()),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Sleep timer, 5 min left'), findsOneWidget);
    expect(find.text('5m'), findsOneWidget);
    harness.container.read(sleepTimerProvider.notifier).cancel();
    await harness.endPlayback(tester);
  });

  testWidgets('a timer waiting on the chapter says so', (tester) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(
        bookPid,
        durationMs: 3600000,
        chapters: const [
          ChapterMark(index: 0, title: 'One', startMs: 0),
          ChapterMark(index: 1, title: 'Two', startMs: 60000),
        ],
      );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: FakeEngine(mediaDuration: const Duration(hours: 1)),
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
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerChapter),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Sleep timer, until the chapter ends'),
      findsOneWidget,
    );
    expect(find.text('ch'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    expect(find.text('Stops when the chapter ends'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerCancel));
    await tester.pumpAndSettle();
    await harness.endPlayback(tester);
  });

  testWidgets('end of chapter picked on a sheet left open across a chapter '
      'end stops at the chapter playing then', (tester) async {
    final repo = FakeRepository()
      ..books[bookPid] = testBook(
        bookPid,
        durationMs: 3600000,
        chapters: const [
          ChapterMark(index: 0, title: 'One', startMs: 0),
          ChapterMark(index: 1, title: 'Two', startMs: 60000),
          ChapterMark(index: 2, title: 'Three', startMs: 120000),
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
      positionMs: 50000,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    // Chapter One ends while the sheet stands open.
    engine.advance(const Duration(seconds: 20));
    await tester.pump();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sleepTimerChapter),
    );
    await tester.pumpAndSettle();

    final armed = harness.container.read(sleepTimerProvider);
    expect(armed.endOfChapterEndMs, 120000);
    expect(armed.endOfChapterPid, bookPid);
    await harness.endPlayback(tester);
  });

  testWidgets('the badge speaks the reader\'s language', (tester) async {
    const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
      container: _container(repo, engine, _FakeClock()),
      host: (player) => localizedHost(player, locale: const Locale('es')),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimerOpen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sleepTimer(5)));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Temporizador de apagado, queda 5 min'),
      findsOneWidget,
    );
    expect(find.text("5'"), findsOneWidget);
    harness.container.read(sleepTimerProvider.notifier).cancel();
    await harness.endPlayback(tester);
  });

  group('end of chapter in a book of several files', () {
    // A folder-of-files book: each file is a chapter, so the end of a
    // chapter is the end of a file, which is exactly where the media's
    // own end races the position crossing it.
    const partMs = 60000;
    const other = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
    late FakeRepository repo;
    late FakeEngine engine;
    late ProviderContainer container;

    const book = ItemSummary(
      pid: bookPid,
      mediaType: MediaType.audiobook,
      title: 'There And Back Again',
      durationMs: 3 * partMs,
    );

    setUp(() {
      repo = FakeRepository(items: [testItem(other)])
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 3 * partMs,
          partCount: 3,
          chapters: const [
            ChapterMark(index: 0, title: 'One', startMs: 0),
            ChapterMark(index: 1, title: 'Two', startMs: partMs),
            ChapterMark(index: 2, title: 'Three', startMs: 2 * partMs),
          ],
        );
      engine = FakeEngine(mediaDuration: const Duration(milliseconds: partMs));
      container = _container(repo, engine, _FakeClock());
    });

    NowPlayingController playback() =>
        container.read(nowPlayingProvider.notifier);
    SleepTimerController timer() => container.read(sleepTimerProvider.notifier);

    Future<void> start({
      int positionMs = 0,
      List<ItemSummary> then = const [],
    }) async {
      container.read(sleepTimerProvider);
      playback().play(
        [book, ...then],
        source: const QueueSource(kind: QueueSourceKind.book, label: 'Book'),
        positionMs: positionMs,
      );
      await pumpEventQueue();
      await playback().settled;
      await pumpEventQueue();
    }

    /// Plays in steps small enough to count as listening.
    Future<void> play(Duration amount) async {
      const step = Duration(seconds: 1);
      for (var played = Duration.zero; played < amount; played += step) {
        engine.advance(step);
        await pumpEventQueue();
      }
    }

    /// Plays started on the engine before the run-out, so a test can
    /// tell whether anything started the next part, however briefly.
    var playsBefore = 0;

    Future<void> runOut({required bool coarse}) async {
      playsBefore = engine.playCalls;
      engine.advance(const Duration(seconds: 2), coarse: coarse);
      await pumpEventQueue();
      await pumpEventQueue();
      await pumpEventQueue();
    }

    void expectStoppedAtPartTwo() {
      expect(engine.loadedUrl, contains('part=1'));
      expect(
        engine.playCalls,
        playsBefore,
        reason: 'nothing starts the next part, not even for an instant',
      );
      expect(engine.playing, isFalse, reason: 'the next part waits');
      expect(engine.position, Duration.zero);
      expect(container.read(sleepTimerProvider).active, isFalse);
      expect(repo.putPlayStateCalls.last.positionMs, partMs);
    }

    test('stops the book before the next part plays', () async {
      await start();
      timer().startEndOfChapter(partMs);
      await play(const Duration(seconds: 58));
      await runOut(coarse: true);
      expectStoppedAtPartTwo();
      await pumpEventQueue();
      expect(engine.playing, isFalse, reason: 'nothing starts it afterwards');
    });

    test('stops it at 1.5x as well', () async {
      await start();
      await engine.setSpeed(1.5);
      timer().startEndOfChapter(partMs);
      await play(const Duration(seconds: 38));
      await runOut(coarse: true);
      expectStoppedAtPartTwo();
    });

    test('stops it when the position crossed before the end arrived', () async {
      await start();
      timer().startEndOfChapter(partMs);
      await play(const Duration(seconds: 58));
      await runOut(coarse: false);
      expectStoppedAtPartTwo();
    });

    test('stops it after a jump back across files', () async {
      await start(positionMs: 150000);
      expect(engine.loadedUrl, contains('part=2'));
      await playback().liveSession!.seek(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(engine.loadedUrl, contains('part=0'));
      timer().startEndOfChapter(partMs);
      await play(const Duration(seconds: 28));
      await runOut(coarse: true);
      expectStoppedAtPartTwo();
    });

    test('the last chapter stops without starting the next entry', () async {
      await start(positionMs: 150000, then: [testItem(other)]);
      timer().startEndOfChapter(3 * partMs);
      await play(const Duration(seconds: 28));
      await runOut(coarse: true);
      await pumpEventQueue();

      expect(container.read(queueControllerProvider).currentPid, bookPid);
      expect(engine.playing, isFalse);
      expect(engine.loadedUrl, contains('part=2'));
      expect(container.read(sleepTimerProvider).active, isFalse);
      expect(repo.reportedSessions.last.finished, isTrue);
    });

    for (final coarse in [true, false]) {
      test('a play after the last chapter stopped moves on '
          '(${coarse ? 'end first' : 'tick first'})', () async {
        await start(positionMs: 150000, then: [testItem(other)]);
        timer().startEndOfChapter(3 * partMs);
        await play(const Duration(seconds: 28));
        await runOut(coarse: coarse);
        await pumpEventQueue();
        expect(container.read(queueControllerProvider).currentPid, bookPid);

        await playback().liveSession!.play();
        await pumpEventQueue();
        await pumpEventQueue();
        expect(
          container.read(queueControllerProvider).currentPid,
          other,
          reason: 'the book is over either way the end arrived',
        );
      });
    }

    test('a seek past the boundary disarms it without pausing', () async {
      await start();
      timer().startEndOfChapter(partMs);
      await play(const Duration(seconds: 10));
      await playback().liveSession!.seek(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(engine.playing, isTrue);
      await playback().liveSession!.seek(const Duration(seconds: 90));
      await pumpEventQueue();
      await play(const Duration(seconds: 2));

      expect(engine.loadedUrl, contains('part=1'));
      expect(engine.playing, isTrue, reason: 'jumping past is not sleeping');
      expect(container.read(sleepTimerProvider).active, isFalse);
    });

    test('an item change clears the armed boundary', () async {
      await start(then: [testItem(other)]);
      timer().startEndOfChapter(partMs);
      // Longer than the boundary, so a boundary left armed would land.
      engine.mediaDuration = const Duration(minutes: 3);
      await playback().next();
      await pumpEventQueue();
      expect(container.read(queueControllerProvider).currentPid, other);
      await play(const Duration(seconds: 62));
      expect(engine.playing, isTrue);
    });
  });

  test('a jump back across files keeps the boundary armed', () async {
    // Parts of unequal length, so the first position the earlier part
    // reports, read against the later part's start while that part is
    // still the one on record, lands past the boundary.
    const twoMinutes = 120000;
    final repo = FakeRepository()
      ..books[bookPid] = const BookDetail(
        pid: bookPid,
        title: 'There And Back Again',
        authors: ['B. Baggins'],
        narrators: ['Frodo'],
        durationMs: 300000,
        chapters: [
          ChapterMark(index: 0, title: 'One', startMs: 0),
          ChapterMark(index: 1, title: 'Two', startMs: 60000),
          ChapterMark(index: 2, title: 'Three', startMs: 240000),
        ],
        parts: [
          BookPart(index: 0, startMs: 0, durationMs: 60000),
          BookPart(index: 1, startMs: 60000, durationMs: twoMinutes),
          BookPart(index: 2, startMs: 180000, durationMs: twoMinutes),
        ],
      );
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: twoMinutes),
    );
    final container = _container(repo, engine, _FakeClock());
    container.read(sleepTimerProvider);
    final playback = container.read(nowPlayingProvider.notifier);
    playback.play(
      const [
        ItemSummary(
          pid: bookPid,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
          durationMs: 300000,
        ),
      ],
      source: const QueueSource(kind: QueueSourceKind.book, label: 'Book'),
      positionMs: 200000,
    );
    await pumpEventQueue();
    await playback.settled;
    container.read(sleepTimerProvider.notifier).startEndOfChapter(240000);

    // Held open the way a real load is: the new media reports where it
    // stands before the load has answered.
    final gate = Completer<void>();
    engine.loadGate = gate;
    final seeking = playback.liveSession!.seek(
      const Duration(milliseconds: 175000),
    );
    await pumpEventQueue();
    gate.complete();
    await seeking;
    await pumpEventQueue();

    expect(engine.loadedUrl, contains('part=1'));
    expect(container.read(sleepTimerProvider).active, isTrue);
  });

  group('a boundary crossed by more than an ordinary step', () {
    // Inside one file, so the stop parks on the boundary rather than
    // loading another part.
    Future<({FakeEngine engine, ProviderContainer container})> armed({
      SkipMap? skips,
      double speed = 1,
    }) async {
      final repo = FakeRepository()
        ..books[bookPid] = testBook(
          bookPid,
          durationMs: 3600000,
          settings: BookSettings(trimSilence: skips != null),
          chapters: const [
            ChapterMark(index: 0, title: 'One', startMs: 0),
            ChapterMark(index: 1, title: 'Two', startMs: 60000),
          ],
        );
      if (skips != null) repo.skipMaps[bookPid] = skips;
      final engine = FakeEngine(mediaDuration: const Duration(hours: 1));
      final container = _container(repo, engine, _FakeClock());
      container.read(sleepTimerProvider);
      final playback = container.read(nowPlayingProvider.notifier);
      playback.play(
        const [
          ItemSummary(
            pid: bookPid,
            mediaType: MediaType.audiobook,
            title: 'There And Back Again',
            durationMs: 3600000,
          ),
        ],
        source: const QueueSource(kind: QueueSourceKind.book, label: 'Book'),
        positionMs: 50000,
      );
      await pumpEventQueue();
      await playback.settled;
      await pumpEventQueue();
      await engine.setSpeed(speed);
      container.read(sleepTimerProvider.notifier).startEndOfChapter(60000);
      return (engine: engine, container: container);
    }

    test('a silence the trim jumps over still stops at the boundary', () async {
      // The gap between chapters is silence, and trimming lands past it.
      final h = await armed(
        skips: const SkipMap(
          state: 'ready',
          spans: [SkipSpan(startMs: 59000, endMs: 62500)],
        ),
      );
      for (var i = 0; i < 12; i++) {
        h.engine.advance(const Duration(seconds: 1));
        await pumpEventQueue();
      }
      expect(h.engine.playing, isFalse);
      expect(h.engine.position, const Duration(seconds: 60));
      expect(h.container.read(sleepTimerProvider).active, isFalse);
    });

    test(
      'a fast speed with coarse ticks still stops at the boundary',
      () async {
        final h = await armed(speed: 2.5);
        for (var i = 0; i < 6; i++) {
          h.engine.advance(const Duration(seconds: 1));
          await pumpEventQueue();
        }
        expect(h.engine.playing, isFalse);
        expect(h.engine.position, const Duration(seconds: 60));
        expect(h.container.read(sleepTimerProvider).active, isFalse);
      },
    );
  });

  test('a short seek just past the boundary disarms it too', () async {
    // A step of a second or two is also what playing looks like, so the
    // seek has to say it was a seek: only the session knows that.
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
    final container = _container(repo, engine, _FakeClock());
    container.read(sleepTimerProvider);
    final playback = container.read(nowPlayingProvider.notifier);
    playback.play(
      const [
        ItemSummary(
          pid: bookPid,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
          durationMs: 3600000,
        ),
      ],
      source: const QueueSource(kind: QueueSourceKind.book, label: 'Book'),
      positionMs: 0,
    );
    await pumpEventQueue();
    await playback.settled;
    container.read(sleepTimerProvider.notifier).startEndOfChapter(60000);
    for (var i = 0; i < 59; i++) {
      engine.advance(const Duration(seconds: 1));
      await pumpEventQueue();
    }
    await playback.liveSession!.seek(const Duration(milliseconds: 60500));
    await pumpEventQueue();
    engine.advance(const Duration(seconds: 1));
    await pumpEventQueue();

    expect(engine.playing, isTrue);
    expect(container.read(sleepTimerProvider).active, isFalse);
  });

  test('a chapter end inside a file pauses within one tick and rests on '
      'the boundary', () async {
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
    final container = _container(repo, engine, _FakeClock());
    container.read(sleepTimerProvider);
    final playback = container.read(nowPlayingProvider.notifier);
    playback.play(
      const [
        ItemSummary(
          pid: bookPid,
          mediaType: MediaType.audiobook,
          title: 'There And Back Again',
          durationMs: 3600000,
        ),
      ],
      source: const QueueSource(kind: QueueSourceKind.book, label: 'Book'),
      positionMs: 0,
    );
    await pumpEventQueue();
    await playback.settled;
    container.read(sleepTimerProvider.notifier).startEndOfChapter(60000);
    for (var i = 0; i < 59; i++) {
      engine.advance(const Duration(seconds: 1));
      await pumpEventQueue();
    }
    engine.advance(const Duration(milliseconds: 1500));
    await pumpEventQueue();
    await pumpEventQueue();

    expect(engine.playing, isFalse);
    expect(engine.position, const Duration(seconds: 60));
    expect(repo.putPlayStateCalls.last.positionMs, 60000);
    expect(container.read(sleepTimerProvider).active, isFalse);
  });
}

/// A media session that records the one extra control the app raises.
/// What it publishes is the feed's business, and has its own test.
class _FakeMediaSession implements MediaSessionPort {
  MediaSessionExtra? extra;

  @override
  void showExtra(MediaSessionExtra? value) => extra = value;

  @override
  void publish(MediaSessionItem? item) {}

  @override
  void publishQueue(List<MediaSessionItem> items, {int index = 0}) {}

  @override
  void publishQueueIndex(int index) {}

  @override
  void publishOpening(bool opening) {}
}
