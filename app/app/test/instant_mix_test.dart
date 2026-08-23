import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/discovery/discovery_actions.dart';
import 'package:waxdeck/src/queue/queue_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _seedPid = 'tr-01JZX5N8QW3F4V9T2B7KDSEED01';
const _mixPid1 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX001';
const _mixPid2 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX002';

/// A screen with nothing playing that can raise the sheet, for the one
/// case the player cannot host: the empty queue.
class _MixLauncher extends StatelessWidget {
  const _MixLauncher({required this.seed});

  final ItemSummary seed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showInstantMixSheet(context, seed),
        child: const Text('Mix from here'),
      ),
    ),
  );
}

Future<void> _runSheet(WidgetTester tester, {bool adventurous = false}) async {
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerDiscover));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMix));
  await tester.pumpAndSettle();
  if (adventurous) {
    // Slide fully right for maximum adventurousness.
    await tester.drag(
      find.bySemanticsIdentifier(SemanticsIds.mixAdventurousness),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMixRun));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a mix asked for mid-track lands behind what is playing', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..instantMixResult = InstantMix(
        basis: MixBasis.sonic,
        items: [
          testItem(_mixPid1, title: 'Mix Opener'),
          testItem(_mixPid2, title: 'Mix Follower'),
        ],
      );
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_seedPid),
      host: routedHost,
    );

    await _runSheet(tester, adventurous: true);

    expect(repo.instantMixCalls, hasLength(1));
    final call = repo.instantMixCalls.single;
    expect(call.seedPid, _seedPid);
    expect(call.size, 50);
    expect(call.adventurousness, closeTo(1.0, 0.001));
    // What is queued is what the mix must not hand back.
    expect(call.excludePids, <String>[_seedPid]);

    // The song keeps playing and the mix is behind it, in order.
    expect(engine.loadedUrl, contains(_seedPid));
    expect(engine.playing, isTrue);
    expect(harness.container.read(queueControllerProvider).pids, <String>[
      _seedPid,
      _mixPid1,
      _mixPid2,
    ]);
    // No track list and no player push: nothing on screen was asked to
    // change, so the count and a way to the queue is the whole answer.
    // Raised through the shell's channel, which is where the button
    // beside it can carry a semantics identifier - so the message is
    // read off that rather than found on a screen this host has none of.
    final message = harness.container.read(shellMessengerProvider);
    expect(shellMessageText(message), 'Added 2 tracks to the queue');
    expect(message?.actionLabel, 'Open');
    expect(message?.actionSemanticsId, SemanticsIds.queueOpen);
    expect(find.text('Instant mix'), findsNothing);
    await harness.endPlayback(tester);
  });

  testWidgets('with nothing queued the mix plays and opens its list', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..instantMixResult = InstantMix(
        basis: MixBasis.sonic,
        items: [
          testItem(_mixPid1, title: 'Mix Opener'),
          testItem(_mixPid2, title: 'Mix Follower'),
        ],
      );
    final engine = FakeEngine();
    final harness = PlayerHarness(
      playbackContainer(repo: repo, engine: engine),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: routedHost(_MixLauncher(seed: testItem(_seedPid))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mix from here'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMixRun));
    await tester.pumpAndSettle();

    expect(repo.instantMixCalls.single.excludePids, isEmpty);
    // The mix starts playing: the first mix track is loaded into the
    // engine and its player is on top of the mix list.
    expect(engine.loadedUrl, contains(_mixPid1));
    expect(engine.playing, isTrue);
    expect(find.text('Mix Opener'), findsWidgets);

    // Popping the player lands on the mix list for the rest of the mix.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pumpAndSettle();
    expect(find.text('Instant mix'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.scopedItem('mix', 1)),
      findsOneWidget,
    );
    await harness.endPlayback(tester);
  });

  testWidgets('the chosen adventurousness is remembered for the next mix', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..instantMixResult = InstantMix(
        basis: MixBasis.metadata,
        items: [testItem(_mixPid1)],
      );
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_seedPid),
      host: routedHost,
    );

    await _runSheet(tester, adventurous: true);
    // The player is still the surface, so the sheet opens again from it.
    await _runSheet(tester);

    expect(repo.instantMixCalls, hasLength(2));
    expect(repo.instantMixCalls.last.adventurousness, closeTo(1.0, 0.001));
    await harness.endPlayback(tester);
  });

  testWidgets('an empty mix answers with a snackbar instead of a screen', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)]);
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_seedPid),
      host: routedHost,
    );

    await _runSheet(tester);

    expect(find.text('No mix available for this track'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.mixBasis('mix')),
      findsNothing,
    );
    await harness.endPlayback(tester);
  });
}
