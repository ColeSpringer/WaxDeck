import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/idle_visualizer.dart';
import 'package:waxdeck/src/player/visualizer_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'player_host.dart';

const _pid = 'tr-01JZX5N8QW3F4V9T2B7KD3M9R6';

Waveform _measured() => Waveform(
  state: 'ready',
  peaks: <int>[for (var i = 0; i < 1000; i++) (i % 200) + 20],
  resolution: 1000,
);

/// A desktop with music playing, wrapped in the watcher, at a size the
/// visualizer can draw itself at.
Future<void> _pump(
  WidgetTester tester, {
  required bool desktop,
  required bool setting,
  bool playing = true,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = FakeRepository()..waveforms[_pid] = _measured();
  final engine = FakeEngine(
    mediaDuration: const Duration(milliseconds: 214000),
  );
  final container = playbackContainer(
    repo: repo,
    engine: engine,
    extra: [desktopProvider.overrideWithValue(desktop)],
  );
  PlayerHarness(container).play([testItem(_pid)]);
  await pumpApp(
    tester,
    const IdleVisualizer(child: Scaffold(body: Text('the library'))),
    container: container,
  );
  container.read(visualizerWhenIdleProvider.notifier).set(setting);
  if (!playing) await engine.pause();
  await tester.pumpAndSettle();
}

/// Past the watcher's own patience, in steps rather than one jump, so a
/// timer that re-arms itself is still walked past its deadline.
Future<void> _waitOut(WidgetTester tester) async {
  await tester.pump(IdleVisualizer.after + const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a desktop left alone with music on fills its screen', (
    tester,
  ) async {
    await _pump(tester, desktop: true, setting: true);

    expect(find.byType(VisualizerScreen), findsNothing);
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsOneWidget);
  });

  testWidgets('and nothing happens unless somebody asked for it', (
    tester,
  ) async {
    await _pump(tester, desktop: true, setting: false);
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsNothing);
  });

  testWidgets('a phone is left alone', (tester) async {
    await _pump(tester, desktop: false, setting: true);
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsNothing);
  });

  testWidgets('a machine sitting paused is not a machine playing music', (
    tester,
  ) async {
    await _pump(tester, desktop: true, setting: true, playing: false);
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsNothing);
  });

  testWidgets('a hand on the machine puts the clock back to the start', (
    tester,
  ) async {
    await _pump(tester, desktop: true, setting: true);

    // Most of the way there, then a click: the countdown starts over
    // rather than firing on the tail of the first stretch.
    await tester.pump(IdleVisualizer.after - const Duration(seconds: 30));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(seconds: 40));
    expect(find.byType(VisualizerScreen), findsNothing);

    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsOneWidget);
  });

  testWidgets('it does not open a second one over the first', (tester) async {
    await _pump(tester, desktop: true, setting: true);
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsOneWidget);

    // Left alone again with the visualizer already up. The surface holds
    // the screen, which is what says there is nothing to open.
    await _waitOut(tester);
    expect(find.byType(VisualizerScreen), findsOneWidget);
  });
}
