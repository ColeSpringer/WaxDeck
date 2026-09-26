import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/discovery/track_list_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';
import 'routed_host.dart';
import 'secondary_click.dart';

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
        of: find.bySemanticsIdentifier(SemanticsIds.mixBasis('similar')),
        matching: find.text('sonic'),
      ),
      findsOneWidget,
    );
    expect(find.text('Kindred Groove'), findsOneWidget);

    // Rows play like library rows.
    // warnIfMissed: a row's identifier sits on its content region rather
    // than on the whole row (MediaListRow says why), so the tap lands on
    // the row's own handler and not on the node the finder matched.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.scopedItem('similar', 0)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(engine.loadedUrl, contains(_similarPid));
    expect(engine.playing, isTrue);
    await harness.endPlayback(tester);
  });

  testWidgets('a row of the answer opens the item menu', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(FakeRepository()),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
        child: routedHost(
          TrackListScreen(
            title: 'More like this',
            basis: MixBasis.sonic,
            items: <ItemSummary>[
              testItem(_similarPid, title: 'Kindred Groove'),
            ],
            idPrefix: 'similar',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await rightClick(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.scopedItem('similar', 0)),
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.itemMenuSheet(_similarPid)),
      findsOneWidget,
    );
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
        of: find.bySemanticsIdentifier(SemanticsIds.mixBasis('similar')),
        matching: find.text('metadata'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing found'), findsOneWidget);
    await harness.endPlayback(tester);
  });
}
