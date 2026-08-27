import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/discovery/discovery_actions.dart';
import 'package:waxdeck/src/discovery/track_list_screen.dart';
import 'package:waxdeck/src/player/deck_bar_host.dart';
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
const _playedPid = 'tr-01JZX5N8QW3F4V9T2B7KDPLAYED';
const _upcomingPid = 'tr-01JZX5N8QW3F4V9T2B7KDNEXT01';

/// A screen with nothing playing that can raise the sheet, for the one
/// case the player cannot host: the empty queue.
class _MixLauncher extends StatelessWidget {
  const _MixLauncher({required this.seed});

  final ItemSummary seed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () =>
            showInstantMixSheet(context, (pid: seed.pid, title: seed.title)),
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
    // The mix starts in the dock: the first mix track is loaded into
    // the engine while the mix list is the screen on top. The full
    // player is a choice the deck bar offers, not a landing. The list
    // is a shell route now, so the real tree carries the deck bar.
    expect(engine.loadedUrl, contains(_mixPid1));
    expect(engine.playing, isTrue);
    expect(find.text('Instant mix'), findsOneWidget);
    expect(find.text('Mix Opener'), findsWidgets);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.scopedItem('mix', 1)),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.playerBack), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.deckBar), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('playing from the mix list stays put and raises the dock', (
    tester,
  ) async {
    final repo = FakeRepository(
      items: [testItem(_mixPid1), testItem(_mixPid2)],
    );
    final engine = FakeEngine();
    final harness = PlayerHarness(
      playbackContainer(repo: repo, engine: engine),
    );
    // The dock in the screen's own slot, the way the shell mounts it,
    // so the play tap's whole answer is visible in one tree. Animations
    // off: a playing bar never settles.
    final screen = Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Stack(
          children: [
            TrackListScreen(
              title: 'Instant mix',
              basis: MixBasis.sonic,
              items: [
                testItem(_mixPid1, title: 'Mix Opener'),
                testItem(_mixPid2, title: 'Mix Follower'),
              ],
              idPrefix: 'mix',
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: DeckBarHost(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: routedHost(screen),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.deckBar), findsNothing);

    // warnIfMissed: a row's identifier sits on its content region
    // rather than on the whole row (MediaListRow says why), so the tap
    // lands on the row's own handler and not on the node the finder
    // matched.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scopedItem('mix', 1)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Playback starts from the tapped row, the route does not change,
    // and the dock is where it shows.
    expect(engine.loadedUrl, contains(_mixPid2));
    expect(engine.playing, isTrue);
    expect(find.text('Instant mix'), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.playerBack), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.deckBar), findsOneWidget);
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

  testWidgets('a mix excludes what is coming, not what has played', (
    tester,
  ) async {
    final repo =
        FakeRepository(
            items: [
              testItem(_playedPid),
              testItem(_seedPid),
              testItem(_upcomingPid),
            ],
          )
          ..instantMixResult = InstantMix(
            basis: MixBasis.sonic,
            items: [testItem(_mixPid1)],
          );
    final engine = FakeEngine();
    final harness = PlayerHarness(
      playbackContainer(repo: repo, engine: engine),
    );
    // A queue mid-listen: one entry behind the current track, one ahead.
    harness.play([
      testItem(_playedPid),
      testItem(_seedPid),
      testItem(_upcomingPid),
    ], startIndex: 1);
    await pumpPlayerInto(tester, harness, host: routedHost);

    await _runSheet(tester);

    // The played entry stays mixable: on a small library excluding the
    // whole queue was the whole catalog, and every mix came back empty.
    expect(repo.instantMixCalls.single.excludePids, <String>[
      _seedPid,
      _upcomingPid,
    ]);
    await harness.endPlayback(tester);
  });

  testWidgets('an all-excluded empty mix says the queue already has it', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..instantMixResult = const InstantMix(
        basis: MixBasis.metadata,
        excluded: 12,
      );
    final engine = FakeEngine();
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_seedPid),
      host: routedHost,
    );

    await _runSheet(tester);

    expect(
      find.text('Everything similar is already in your queue'),
      findsOneWidget,
    );
    expect(find.text('No mix available for this track'), findsNothing);
    await harness.endPlayback(tester);
  });
}
