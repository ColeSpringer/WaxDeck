import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/output_volume.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

/// The full player's own level.
///
/// The deck bar's three-zone layout is the only other place local output
/// can be set, and it needs a sidebar's worth of width to draw a right
/// cluster. Below that this screen is the level's one home, which is what
/// the report about the full player showing none was really about.
void main() {
  testWidgets('the player sets this device up and down, and back', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    // The gate is the platform, and flutter_test pins that to Android -
    // the half of the condition that deliberately gets no slider, because
    // hardware buttons own local volume there. Overridden through the
    // provider rather than the foundation global.
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
      container: playbackContainer(
        repo: repo,
        engine: engine,
        extra: [localVolumeAvailableProvider.overrideWithValue(true)],
      ),
    );

    final slider = find.bySemanticsIdentifier(SemanticsIds.playerVolume);
    expect(slider, findsOneWidget);

    await tester.tapAt(
      tester.getCenter(slider) - Offset(tester.getSize(slider).width / 4, 0),
    );
    await tester.pumpAndSettle();
    expect(engine.volume, lessThan(0.5));

    // Mute puts it back where it was rather than guessing, and the glyph
    // says which of the two the next tap will do.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMute));
    await tester.pumpAndSettle();
    expect(engine.volume, 0);
    expect(find.bySemanticsLabel('Unmute'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMute));
    await tester.pumpAndSettle();
    expect(engine.volume, greaterThan(0));
    expect(find.bySemanticsLabel('Mute'), findsOneWidget);

    await harness.endPlayback(tester);
  });

  testWidgets('the level moves under the finger, not on release', (
    tester,
  ) async {
    // The filed bug: volume only changed when the finger let go. The
    // slider now reports live, one value per step crossed, and the
    // optimistic controller writes each one straight to the engine.
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
      container: playbackContainer(
        repo: repo,
        engine: engine,
        extra: [localVolumeAvailableProvider.overrideWithValue(true)],
      ),
    );

    final before = engine.volume;
    final slider = find.bySemanticsIdentifier(SemanticsIds.playerVolume);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(Offset(-tester.getSize(slider).width / 4, 0));
    await tester.pump();
    expect(
      engine.volume,
      lessThan(before),
      reason: 'the gain must follow the drag, not wait for release',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.volume, closeTo(0.25, 0.1));

    await harness.endPlayback(tester);
  });

  testWidgets('the level follows a change nothing on screen made', (
    tester,
  ) async {
    // The sleep timer's fade and a routed set-volume both write the gain
    // without asking any widget, so the control reads the engine rather
    // than keeping a copy of what it last sent.
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
      container: playbackContainer(
        repo: repo,
        engine: engine,
        extra: [localVolumeAvailableProvider.overrideWithValue(true)],
      ),
    );

    await engine.setVolume(0);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Unmute'), findsOneWidget);

    await engine.setVolume(0.6);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Mute'), findsOneWidget);

    await harness.endPlayback(tester);
  });

  testWidgets('a level the platform refuses does not stay on the slider', (
    tester,
  ) async {
    // The optimism is what keeps a drag smooth, and it has to survive its
    // own failure: a write the platform turns down leaves the control
    // drawing a loudness the output never took, which is the one thing
    // this controller exists to prevent.
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    final container = playbackContainer(
      repo: repo,
      engine: engine,
      extra: [localVolumeAvailableProvider.overrideWithValue(true)],
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
      container: container,
    );

    await container.read(outputVolumeProvider.notifier).set(0.4);
    await tester.pumpAndSettle();
    expect(container.read(outputVolumeProvider), closeTo(0.4, 0.001));

    // Not raised: every call site is a slider or a glyph firing and
    // forgetting, so a raised failure is an unhandled zone error per drag
    // frame and nothing on screen. The level snapping back is the report.
    engine.failNextSetVolume = true;
    await container.read(outputVolumeProvider.notifier).set(0.9);
    await tester.pumpAndSettle();

    // Back to the engine's own gain, not the level nobody took.
    expect(engine.volume, closeTo(0.4, 0.001));
    expect(container.read(outputVolumeProvider), closeTo(0.4, 0.001));

    await harness.endPlayback(tester);
  });

  testWidgets('a refused unmute keeps the level it was putting back', (
    tester,
  ) async {
    // Mute's whole promise is the level it is holding. Spent before the
    // write, a refused unmute forgot it, and the retry - the obvious thing
    // to do next - had nothing to go back to but full volume, in a pair of
    // headphones, at whatever the engine's idea of 1.0 is.
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    final container = playbackContainer(
      repo: repo,
      engine: engine,
      extra: [localVolumeAvailableProvider.overrideWithValue(true)],
    );
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
      container: container,
    );

    final volume = container.read(outputVolumeProvider.notifier);
    await volume.set(0.6);
    await volume.toggleMute();
    expect(engine.volume, 0);

    engine.failNextSetVolume = true;
    await volume.toggleMute();
    await tester.pumpAndSettle();
    expect(engine.volume, 0, reason: 'the write was refused');
    expect(container.read(outputVolumeProvider), 0);

    await volume.toggleMute();
    expect(
      engine.volume,
      closeTo(0.6, 0.001),
      reason: 'the remembered level survived the refusal',
    );

    await harness.endPlayback(tester);
  });

  testWidgets('a phone gets none of it, where the buttons own the level', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem('tr-A')]);
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem('tr-A'),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.playerVolume),
      findsNothing,
      reason: 'a software slider there fights the OS volume stack',
    );

    await harness.endPlayback(tester);
  });
}
