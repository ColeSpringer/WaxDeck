import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/entity_play_state_controller.dart';
import 'package:waxdeck/src/player/entity_star_rating_row.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';

// The entity star and rating row: the artist and album twin of the item
// controls on the player screen. Its own state, never a rollup of its
// members', which is what the last case here pins.

Widget _host(FakeRepository repo, Widget home) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  // The row reaches for the copy table, so a bare host would throw
  // the moment a save failed: `nullable-getter: false` is the design.
  child: localizedHost(Scaffold(body: home)),
);

/// The message the row raised, if it raised one.
ShellMessage? _raised(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(EntityStarRatingRow)),
).read(shellMessengerProvider);

/// A server that holds no artist or album by any pid it is asked about.
class _NoEntities extends FakeRepository {
  @override
  Future<EntityPlayState> getEntityPlayState(String pid) async =>
      throw WaxDeckApiException(
        code: 'not-found',
        message: 'no entity $pid',
        statusCode: 404,
      );
}

void main() {
  const albumPid = 'al-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

  test('an entity that is gone settles at once', () async {
    // A missing artist's star row used to be five reads and a backoff
    // ladder long, for an answer that never changes.
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(_NoEntities())],
    );
    addTearDown(container.dispose);
    final state = entityPlayStateControllerProvider('ar-gone');
    final sub = container.listen(state, (_, _) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(state.future).timeout(const Duration(seconds: 2)),
      throwsA(isA<WaxDeckApiException>()),
    );
  });
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

  testWidgets('a star the server refuses says the change did not stick', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..playStateError = const WaxDeckApiException(
        code: 'forbidden',
        message: 'not yours to star',
        statusCode: 403,
      );
    await tester.pumpWidget(
      _host(repo, const EntityStarRatingRow(pid: albumPid, label: 'album')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('entity-star-button')));
    await tester.pumpAndSettle();

    expect(_raised(tester), isNotNull);
  });

  testWidgets('an entity that is gone is no change that did not stick', (
    tester,
  ) async {
    // The read is refused, which nobody tapped: the row stays disabled
    // and the screen says the entity is gone where it says anything.
    await tester.pumpWidget(
      _host(
        _NoEntities(),
        const EntityStarRatingRow(pid: 'ar-gone', label: 'artist'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_raised(tester), isNull);
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
