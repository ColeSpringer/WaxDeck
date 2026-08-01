import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Override lives here rather than in the root library.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/now_playing_controller.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/queue/queue_state.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// One item played the way a row tap plays it: on its own, with nothing
/// after it.
QueueSource playedAlone(ItemSummary item) =>
    QueueSource(kind: QueueSourceKind.single, label: item.title, pid: item.pid);

/// A container wired to the fakes, with nothing playing yet. Tests
/// needing more overrides build their own and hand it to [PlayerHarness].
ProviderContainer playbackContainer({
  required FakeRepository repo,
  required FakeEngine engine,
  List<Override> extra = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      audioEngineProvider.overrideWithValue(engine),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A test's grip on playback, which lives in the container rather than
/// in any screen: what is playing survives the player being mounted,
/// unmounted, or never mounted at all.
class PlayerHarness {
  PlayerHarness(this.container);

  final ProviderContainer container;

  NowPlayingController get playback =>
      container.read(nowPlayingProvider.notifier);

  /// Plays [items] from [startIndex], the way a tap on a row does.
  void play(
    List<ItemSummary> items, {
    QueueSource? source,
    int startIndex = 0,
    int? positionMs,
  }) => playback.play(
    items,
    source: source ?? playedAlone(items[startIndex]),
    startIndex: startIndex,
    positionMs: positionMs,
  );

  /// Ends playback the way "Clear queue" does: the queue empties, and
  /// the session lets go after flushing its last checkpoint and listen
  /// report.
  ///
  /// Every test that starts playback ends it, because playback no longer
  /// belongs to the widget tree: unmounting the player leaves the item
  /// playing, its checkpoint timer running, and Connect still reporting
  /// it, which is the whole point of the phase and a hung test otherwise.
  Future<void> endPlayback(WidgetTester tester) async {
    container.read(queueControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
  }
}

/// Starts [item] playing and mounts the player over it, which is what a
/// tap on a row does: the queue gets the item, playback follows it, and
/// the screen shows what came of that.
///
/// [host] wraps the player for tests that need more around it than a
/// bare app: the discovery journeys mount it over the real route table
/// so the pushes their menus make land somewhere.
Future<PlayerHarness> pumpPlayer(
  WidgetTester tester, {
  required FakeRepository repo,
  required FakeEngine engine,
  required ItemSummary item,
  int? positionMs,
  ProviderContainer? container,
  Widget Function(Widget player)? host,
}) async {
  final harness = PlayerHarness(
    container ?? playbackContainer(repo: repo, engine: engine),
  );
  harness.play([item], positionMs: positionMs);
  await pumpPlayerInto(tester, harness, host: host);
  return harness;
}

/// Mounts the player over a queue a test built itself.
///
/// For the cases where one item played on its own is the wrong setup: an
/// up-next peek needs something after the current entry, and a
/// provenance line needs a source that is not a single tap.
Future<void> pumpPlayerInto(
  WidgetTester tester,
  PlayerHarness harness, {
  Widget Function(Widget player)? host,
}) async {
  const player = PlayerScreen();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: host?.call(player) ?? const MaterialApp(home: player),
    ),
  );
  await tester.pumpAndSettle();
}
