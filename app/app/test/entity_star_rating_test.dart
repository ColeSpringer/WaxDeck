import 'package:flutter/material.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/entity_star_rating_row.dart';
import 'package:waxdeck/src/providers.dart';

import 'fakes.dart';

// The entity star and rating row: the artist and album twin of the item
// controls on the player screen. Its own state, never a rollup of its
// members', which is what the last case here pins.

Widget _host(FakeRepository repo, Widget home) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(home: Scaffold(body: home)),
);

void main() {
  const albumPid = 'al-01JZX5N8QW3F4V9T2B7KDEXAMPLE';
  const trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

  testWidgets('the star button toggles the entity through the repository', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const EntityStarRatingRow(pid: albumPid, label: 'album')),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);

    await tester.tap(find.byKey(const Key('entity-star-button')));
    await tester.pumpAndSettle();
    expect(repo.entityStarredByPid[albumPid], isTrue);
    expect(find.byIcon(WaxIcons.heart.fill), findsOneWidget);

    await tester.tap(find.byKey(const Key('entity-star-button')));
    await tester.pumpAndSettle();
    expect(repo.entityStarredByPid[albumPid], isFalse);
    expect(find.byIcon(WaxIcons.heart.regular), findsOneWidget);
  });

  testWidgets('entity ratings map to the 0 to 100 scale and clear on repeat', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const EntityStarRatingRow(pid: albumPid, label: 'album')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('entity-rating-3')));
    await tester.pumpAndSettle();
    expect(repo.entityRatingByPid[albumPid], 60);
    expect(find.byIcon(WaxIcons.star.fill), findsNWidgets(3));

    // Tapping the current rating again clears it.
    await tester.tap(find.byKey(const Key('entity-rating-3')));
    await tester.pumpAndSettle();
    expect(repo.entityRatingByPid[albumPid], isNull);
    expect(find.byIcon(WaxIcons.star.regular), findsNWidgets(5));
  });

  testWidgets('a stored entity star and rating render on open', (tester) async {
    final repo = FakeRepository()
      ..entityStarredByPid[albumPid] = true
      ..entityRatingByPid[albumPid] = 40;
    await tester.pumpWidget(
      _host(repo, const EntityStarRatingRow(pid: albumPid, label: 'album')),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(WaxIcons.heart.fill), findsOneWidget);
    expect(find.byIcon(WaxIcons.star.fill), findsNWidgets(2));
  });

  testWidgets('starring an entity leaves its members alone', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const EntityStarRatingRow(pid: albumPid, label: 'album')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('entity-star-button')));
    await tester.pumpAndSettle();

    expect(repo.entityStarredByPid[albumPid], isTrue);
    expect(repo.starredByPid[albumPid], isNull);
    expect(repo.starredByPid[trackPid], isNull);
  });
}
