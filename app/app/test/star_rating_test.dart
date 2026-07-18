import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/player_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo, FakeEngine engine, Widget home) =>
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        audioEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

  testWidgets('the star button toggles through the repository', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('star-button')), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byKey(const Key('star-button')));
    await tester.pumpAndSettle();
    expect(repo.starredByPid[pid], isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byKey(const Key('star-button')));
    await tester.pumpAndSettle();
    expect(repo.starredByPid[pid], isFalse);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('rating stars map to the 0 to 100 scale and clear on repeat', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rating-3')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], 60);
    expect(find.byIcon(Icons.star), findsNWidgets(3));

    await tester.tap(find.byKey(const Key('rating-5')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], 100);
    expect(find.byIcon(Icons.star), findsNWidgets(5));

    // Tapping the current rating again clears it.
    await tester.tap(find.byKey(const Key('rating-5')));
    await tester.pumpAndSettle();
    expect(repo.ratingByPid[pid], isNull);
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
  });

  testWidgets('a stored rating renders on open', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)])
      ..ratingByPid[pid] = 40
      ..starredByPid[pid] = true;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(2));
  });

  testWidgets('a failed star rolls back and tells the user', (tester) async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );

    await tester.pumpWidget(
      _host(repo, engine, PlayerScreen(item: testItem(pid))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    // Arm the failure after load, so only the mutation trips it.
    repo.playStateError = const WaxDeckApiException(
      code: 'internal',
      message: 'boom',
      statusCode: 500,
    );

    await tester.tap(find.byKey(const Key('star-button')));
    // The optimistic flip lands before the request settles.
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    // The failure rolls it back and surfaces a snack bar; the fake was
    // never mutated.
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(repo.starredByPid[pid], isNull);
    expect(find.text('Could not save that change'), findsOneWidget);
  });
}
