import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _seedPid = 'tr-01JZX5N8QW3F4V9T2B7KDSEED01';
const _mixPid1 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX001';
const _mixPid2 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX002';

void main() {
  testWidgets('the mix flow calls createInstantMix and plays the result', (
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerDiscover));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMix));
    await tester.pumpAndSettle();

    // The sheet: slide fully right for maximum adventurousness, then mix.
    await tester.drag(
      find.byKey(const Key('mix-adventurousness')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    expect(repo.instantMixCalls, hasLength(1));
    final call = repo.instantMixCalls.single;
    expect(call.seedPid, _seedPid);
    expect(call.size, 50);
    expect(call.adventurousness, closeTo(1.0, 0.001));

    // The mix starts playing: the first mix track is loaded into the
    // engine and its player is on top of the mix list.
    expect(engine.loadedUrl, contains(_mixPid1));
    expect(engine.playing, isTrue);
    expect(find.text('Mix Opener'), findsWidgets);

    // Popping the player lands on the mix list for the rest of the mix.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pumpAndSettle();
    expect(find.text('Instant mix'), findsOneWidget);
    expect(find.byKey(const Key('mix-item-1')), findsOneWidget);
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerDiscover));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMix));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('mix-adventurousness')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    // Back out of the mix player and list, then open the sheet again.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerBack));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerDiscover));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMix));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerDiscover));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.instantMix));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    expect(find.text('No mix available for this track'), findsOneWidget);
    expect(find.byKey(const Key('discovery-basis')), findsNothing);
    await harness.endPlayback(tester);
  });
}
