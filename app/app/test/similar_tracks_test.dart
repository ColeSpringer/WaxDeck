import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';

const _seedPid = 'tr-01JZX5N8QW3F4V9T2B7KDSEED01';
const _similarPid = 'tr-01JZX5N8QW3F4V9T2B7KDSIM001';

void main() {
  testWidgets('shows the results with the answering basis as a chip', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..similarTracksResult = SimilarTracks(
        basis: MixBasis.sonic,
        items: [testItem(_similarPid, title: 'Kindred Groove')],
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
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.similarTracks));
    await tester.pumpAndSettle();

    expect(repo.similarTracksCalls.single.pid, _seedPid);
    expect(
      find.descendant(
        of: find.byKey(const Key('discovery-basis')),
        matching: find.text('sonic'),
      ),
      findsOneWidget,
    );
    expect(find.text('Kindred Groove'), findsOneWidget);

    // Rows play like library rows.
    await tester.tap(find.byKey(const Key('similar-item-0')));
    await tester.pumpAndSettle();
    expect(engine.loadedUrl, contains(_similarPid));
    expect(engine.playing, isTrue);
    await harness.endPlayback(tester);
  });

  testWidgets('the metadata fallback names itself on the chip', (tester) async {
    final repo = FakeRepository(items: [testItem(_seedPid)])
      ..similarTracksResult = const SimilarTracks(basis: MixBasis.metadata);
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
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.similarTracks));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('discovery-basis')),
        matching: find.text('metadata'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing found'), findsOneWidget);
    await harness.endPlayback(tester);
  });
}
