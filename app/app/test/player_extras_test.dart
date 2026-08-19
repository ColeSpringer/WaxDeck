import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/metadata/metadata_controller.dart';
import 'package:waxdeck/src/metadata/metadata_screen.dart';
import 'package:waxdeck/src/player/car_mode_screen.dart';
import 'package:waxdeck/src/player/visualizer_screen.dart';
import 'package:waxdeck/src/player/wake_port.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _pid = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';

/// A measured file, which is what the visualizer needs to draw anything.
Waveform _measured() => Waveform(
  state: 'ready',
  peaks: <int>[for (var i = 0; i < 1000; i++) (i % 200) + 20],
  resolution: 1000,
);

/// Records what the platform was asked to do with the screen.
class RecordingWake implements WakePort {
  final List<bool> calls = <bool>[];

  @override
  Future<void> keepAwake(bool on) async => calls.add(on);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the visualizer', () {
    testWidgets('draws the track once the analyze pass has measured it', (
      tester,
    ) async {
      _phone(tester);
      final repo = FakeRepository()..waveforms[_pid] = _measured();
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const VisualizerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VisualizerStage), findsOneWidget);
      await harness.endPlayback(tester);
    });

    testWidgets('says so rather than spinning when nothing was measured', (
      tester,
    ) async {
      _phone(tester);
      // Unseeded, which answers `pending`: what an unanalyzed library
      // says about every file it holds.
      final repo = FakeRepository();
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const VisualizerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VisualizerStage), findsNothing);
      expect(find.text('No shape to draw'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('the chrome goes away, and any touch brings it back', (
      tester,
    ) async {
      _phone(tester);
      final repo = FakeRepository()..waveforms[_pid] = _measured();
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const VisualizerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      AnimatedOpacity chrome() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);

      expect(chrome().opacity, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(chrome().opacity, 0);

      // A touch on the picture, which is also a scrub: using the surface
      // is what reveals the controls, not only reaching for them.
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      expect(chrome().opacity, 1);
      await harness.endPlayback(tester);
    });

    testWidgets('and stays put for a screen reader, which has no way to '
        'bring it back', (tester) async {
      _phone(tester);
      final repo = FakeRepository()..waveforms[_pid] = _measured();
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              accessibleNavigation: true,
            ),
            child: routedHost(const VisualizerScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 10));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      await harness.endPlayback(tester);
    });

    testWidgets('holds the screen awake, and lets it go on the way out', (
      tester,
    ) async {
      _phone(tester);
      final wake = RecordingWake();
      final repo = FakeRepository()..waveforms[_pid] = _measured();
      final container = playbackContainer(
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        extra: [wakePortProvider.overrideWithValue(wake)],
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const VisualizerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(wake.calls, <bool>[true]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      expect(wake.calls, <bool>[true, false]);
      await harness.endPlayback(tester);
    });
  });

  group('car mode', () {
    testWidgets('drives what is playing and holds the screen', (tester) async {
      _phone(tester);
      final wake = RecordingWake();
      final engine = FakeEngine(
        mediaDuration: const Duration(milliseconds: 214000),
      );
      final container = playbackContainer(
        repo: FakeRepository(),
        engine: engine,
        extra: [wakePortProvider.overrideWithValue(wake)],
      );
      final harness = PlayerHarness(container);
      harness.play([testItem(_pid)]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const CarModeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(wake.calls, <bool>[true]);
      expect(find.text('Prancing Pony Blues'), findsOneWidget);

      expect(engine.playing, isTrue);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.carToggle));
      await tester.pumpAndSettle();
      expect(engine.playing, isFalse);
      await harness.endPlayback(tester);
    });

    testWidgets('opened in silence, it offers the way out rather than a '
        'dead screen', (tester) async {
      _phone(tester);
      final container = playbackContainer(
        repo: FakeRepository(),
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const CarModeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing is playing'), findsOneWidget);
      expect(find.bySemanticsIdentifier(SemanticsIds.carExit), findsOneWidget);
    });
  });

  group('the player', () {
    testWidgets('offers car mode in its menu, and on the row once asked', (
      tester,
    ) async {
      _phone(tester);
      final repo = FakeRepository();
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testItem(_pid),
        host: (player) => routedHost(player),
      );

      // In the menu by default, and nowhere else.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerCarMode),
        findsNothing,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerCarMode),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerVisualizer),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Asked for, it moves onto the row and leaves the menu, so one
      // verb never stands twice under one handle.
      harness.container.read(carModeButtonProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerCarMode),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerCarMode),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await harness.endPlayback(tester);
    });

    testWidgets('a spoken-word face is offered no visualizer', (tester) async {
      _phone(tester);
      final harness = await pumpPlayer(
        tester,
        repo: FakeRepository(),
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testItem(
          'bk-01JZX5N8QW3F4V9T2B7KD3M9R6',
          mediaType: MediaType.audiobook,
        ),
        host: (player) => routedHost(player),
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.playerVisualizer),
        findsNothing,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await harness.endPlayback(tester);
    });

    testWidgets('the menu row opens the visualizer over the player', (
      tester,
    ) async {
      _phone(tester);
      final repo = FakeRepository()..waveforms[_pid] = _measured();
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testItem(_pid),
        host: (player) => routedHost(player),
      );

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.playerVisualizer),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VisualizerScreen), findsOneWidget);
      // Over it, not instead of it: leaving lands back on the face the
      // menu was opened from.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.visualizerClose),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VisualizerScreen), findsNothing);
      await harness.endPlayback(tester);
    });

    testWidgets('the metadata door follows the server, not a role', (
      tester,
    ) async {
      _phone(tester);
      final repo = FakeRepository()..mayCurateItems = false;
      final harness = await pumpPlayer(
        tester,
        repo: repo,
        engine: FakeEngine(mediaDuration: const Duration(milliseconds: 214000)),
        item: testItem(_pid),
        host: (player) => routedHost(player),
      );

      final door = find.bySemanticsIdentifier(SemanticsIds.editMetadata(_pid));
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      expect(door, findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // The same listener on an item their own upload brought in: the
      // permission is a fact about this item, so the row appears for
      // the item and not for the account.
      repo.mayCurateItems = true;
      harness.container.invalidate(mayCurateItemProvider(_pid));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
      await tester.pumpAndSettle();
      expect(door, findsOneWidget);
      await tester.tap(door);
      await tester.pumpAndSettle();

      // The location, not the widget: this host mounts the player with
      // no shell standing, so a `push` into the shell would build one
      // here and look like it worked. What the app has underneath is an
      // already-mounted shell, which is why the row uses `go` - and a
      // `go` is visible in the address the router reports either way.
      expect(
        GoRouter.of(
          tester.element(find.byType(MetadataScreen)),
        ).state.uri.toString(),
        WaxRoute.metadata(_pid),
      );
      await harness.endPlayback(tester);
    });
  });

  group('the wake lock', () {
    test('two holders, one lock', () {
      final wake = RecordingWake();
      final container = ProviderContainer(
        overrides: [wakePortProvider.overrideWithValue(wake)],
      );
      addTearDown(container.dispose);
      final lock = container.read(wakeLockProvider);

      lock.hold();
      lock.hold();
      expect(wake.calls, <bool>[true]);
      expect(lock.held.value, isTrue);

      // The first one out must not turn the screen off under the other.
      lock.letGo();
      expect(wake.calls, <bool>[true]);
      expect(lock.held.value, isTrue);

      lock.letGo();
      expect(wake.calls, <bool>[true, false]);
      expect(lock.held.value, isFalse);

      // A release nothing took changes nothing.
      lock.letGo();
      expect(wake.calls, <bool>[true, false]);
    });

    test('a container torn down while held lets the screen go', () {
      final wake = RecordingWake();
      final container = ProviderContainer(
        overrides: [wakePortProvider.overrideWithValue(wake)],
      );
      container.read(wakeLockProvider).hold();
      container.dispose();
      expect(wake.calls, <bool>[true, false]);
    });
  });

  test('the route table names both surfaces', () {
    expect(WaxRoute.visualizer, '/visualizer');
    expect(WaxRoute.carMode, '/car');
  });
}
