import 'package:flutter/material.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

void main() {
  const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

  testWidgets('the star button toggles through the repository', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    expect(find.byKey(const Key('star-button')), findsOneWidget);
    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);

    await tester.tap(find.byKey(const Key('star-button')));
    await tester.pumpAndSettle();
    expect(repo.starredByPid[pid], isTrue);
    expect(find.byIcon(WaxIcons.heart.fill), findsOneWidget);

    await tester.tap(find.byKey(const Key('star-button')));
    await tester.pumpAndSettle();
    expect(repo.starredByPid[pid], isFalse);
    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('rating stars map to the 0 to 100 scale and clear on repeat', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    await tester.tap(find.byKey(const Key('rating-3')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], 60);
    expect(find.byIcon(WaxIcons.star.fill), findsNWidgets(3));

    await tester.tap(find.byKey(const Key('rating-5')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], 100);
    expect(find.byIcon(WaxIcons.star.fill), findsNWidgets(5));

    // Tapping the current rating again clears it.
    await tester.tap(find.byKey(const Key('rating-5')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], isNull);
    expect(find.byIcon(WaxIcons.star.regular), findsNWidgets(5));
    await harness.endPlayback(tester);
  });

  testWidgets('a stored rating renders on open', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..ratingByPid[pid] = 40
      ..starredByPid[pid] = true;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );

    expect(find.byIcon(WaxIcons.heart.fill), findsOneWidget);
    expect(find.byIcon(WaxIcons.star.fill), findsNWidgets(2));
    await harness.endPlayback(tester);
  });

  testWidgets('a failed star rolls back and tells the user', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(pid),
    );
    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);

    // Arm the failure after load, so only the mutation trips it.
    repo.playStateError = const WaxDeckApiException(
      code: 'internal',
      message: 'boom',
      statusCode: 500,
    );

    await tester.tap(find.byKey(const Key('star-button')));
    // The optimistic flip lands before the request settles.
    await tester.pump();
    expect(find.byIcon(WaxIcons.heart.fill), findsOneWidget);

    // The failure rolls it back and surfaces a snack bar; the fake was
    // never mutated.
    await tester.pumpAndSettle();
    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);
    expect(repo.starredByPid[pid], isNull);
    expect(find.text('Could not save that change'), findsOneWidget);
    await harness.endPlayback(tester);
  });
}
