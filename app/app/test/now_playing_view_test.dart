import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_view.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'player_host.dart';

void main() {
  testWidgets('a skip keeps what played until the next one loads', (
    tester,
  ) async {
    // Lyrics, car mode and the visualizer flashed "Nothing is playing"
    // on every skip.
    final a = testItem('tr-A', title: 'First');
    final b = testItem('tr-B', title: 'Second');
    final repo = FakeRepository(items: [a, b]);
    final harness = PlayerHarness(
      playbackContainer(repo: repo, engine: FakeEngine()),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: localizedHost(
          NowPlayingView(
            idle: (_) => const Text('idle'),
            builder: (_, _, item, _) => Text(item.title),
          ),
          theme: buildWaxTheme(),
        ),
      ),
    );
    harness.play([a, b], source: QueueSource.none);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    final gate = repo.playInfoGate = Completer<void>();
    unawaited(harness.playback.next());
    await tester.pumpAndSettle();
    expect(find.text('idle'), findsNothing);
    expect(find.text('First'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    await harness.endPlayback(tester);
  });
}
