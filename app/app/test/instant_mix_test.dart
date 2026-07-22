import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

const _seedPid = 'tr-01JZX5N8QW3F4V9T2B7KDSEED01';
const _mixPid1 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX001';
const _mixPid2 = 'tr-01JZX5N8QW3F4V9T2B7KDMIX002';

Widget _host(FakeRepository repo, FakeEngine engine) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    audioEngineProvider.overrideWithValue(engine),
  ],
  child: MaterialApp(home: PlayerScreen(item: testItem(_seedPid))),
);

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
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix')));
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Instant mix'), findsOneWidget);
    expect(find.byKey(const Key('mix-item-1')), findsOneWidget);
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
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('mix-adventurousness')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    // Back out of the mix player and list, then open the sheet again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    expect(repo.instantMixCalls, hasLength(2));
    expect(repo.instantMixCalls.last.adventurousness, closeTo(1.0, 0.001));
  });

  testWidgets('an empty mix answers with a snackbar instead of a screen', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_seedPid)]);
    final engine = FakeEngine();
    await tester.pumpWidget(_host(repo, engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('player-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instant-mix-run')));
    await tester.pumpAndSettle();

    expect(find.text('No mix available for this track'), findsOneWidget);
    expect(find.byKey(const Key('discovery-basis')), findsNothing);
  });
}
