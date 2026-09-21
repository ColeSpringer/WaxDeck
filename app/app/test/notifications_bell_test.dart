import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/notifications/notifications_bell.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(
        FakeRepository(
          sessionState: const SessionState(
            authenticated: true,
            user: WaxDeckUser(id: 'us-1', username: 'sam', roles: <String>[]),
          ),
        ),
      ),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      // A chosen row lands in the shell, and the shell hosts the deck bar.
      audioEngineProvider.overrideWithValue(FakeEngine()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: routedHost(
        const Scaffold(body: Center(child: NotificationsBell())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('a chosen row opens its own surface, not whatever took its '
      'place', (tester) async {
    final container = await _pump(tester);
    final notifications = container.read(localNotificationsProvider.notifier);
    final router = GoRouter.of(tester.element(find.byType(NotificationsBell)));

    notifications.record(
      NotificationKind.feedDisabled,
      at: DateTime(2026, 8, 12, 9),
    );
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    // Newer news arrives behind the open menu, which holds the rows it
    // opened with. The handle names what the row is about, so it goes on
    // meaning the podcast row however the list reorders underneath.
    notifications.record(
      NotificationKind.review,
      at: DateTime(2026, 8, 12, 10),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      _byId(
        SemanticsIds.notificationRowPlain(NotificationKind.feedDisabled.token),
      ),
    );
    await tester.pumpAndSettle();

    expect(_location(router), WaxRoute.podcasts);
  });

  testWidgets('the last row reads the bell rather than opening a surface', (
    tester,
  ) async {
    final container = await _pump(tester);
    final router = GoRouter.of(tester.element(find.byType(NotificationsBell)));
    final before = _location(router);

    container
        .read(localNotificationsProvider.notifier)
        .record(NotificationKind.download, at: DateTime(2026, 8, 12, 9));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.notificationsPeekRead));
    await tester.pumpAndSettle();

    // Read, not deleted. The peek holds what has not been dealt with,
    // so the row leaves it - but the screen still lists what happened,
    // because a dropdown is no place to throw away ninety days of
    // history on every device at once.
    expect(container.read(notificationRowsProvider), isEmpty);
    expect(container.read(notificationsViewProvider).rows, hasLength(1));
    // Its value is empty; every row's is a location.
    expect(_location(router), before);
  });

  testWidgets('a bell with nothing in it still opens and says so', (
    tester,
  ) async {
    await _pump(tester);

    // The state a visit leaves behind once it has dealt with the only
    // row there was, and the one a reader is most likely to open into.
    // Empty is not a broken bell: the trigger stays live and the menu
    // draws a line of its own, which is the handle the e2e reads to
    // tell an opened bell from a click that never landed.
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.notificationsEmpty), findsOneWidget);
    expect(_byId(SemanticsIds.notificationsClear), findsNothing);
  });

  testWidgets('the count is in the name, and opening is what reads it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = await _pump(tester);

    container
        .read(localNotificationsProvider.notifier)
        .record(NotificationKind.upload, at: DateTime(2026, 8, 12, 9));
    await tester.pumpAndSettle();

    // The name, not the drawn badge: it is what the e2e waits on.
    expect(
      tester.getSemantics(_byId(SemanticsIds.notificationsBell)).label,
      'Notifications, 1 unread',
    );

    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    // Dismissed, because the menu's barrier is over the trigger.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_byId(SemanticsIds.notificationsBell)).label,
      'Notifications',
    );
    handle.dispose();
  });

  // The bell draws what is unseen, and opening it is the whole of what
  // reading a hint can mean - so a press that reads one the menu never
  // drew loses it for good. The press and the list it opens with are
  // taken at two different instants, and this is the gap between them.
  testWidgets('news landing in the frame of a press is not read on its '
      'reader\'s behalf', (tester) async {
    final container = await _pump(tester);
    final local = container.read(localNotificationsProvider.notifier);
    final drawn = _byId(
      SemanticsIds.notificationRowPlain(NotificationKind.review.token),
    );
    final missed = _byId(
      SemanticsIds.notificationRowPlain(NotificationKind.upload.token),
    );

    // A bell carrying a stamp, which is an open that drew something and
    // nothing else: the press below has to be shown not to move a stamp
    // that is already there, and an unstamped list would draw the row
    // whatever the press did.
    local.record(NotificationKind.review, at: DateTime.now());
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    expect(drawn, findsOneWidget, reason: 'the open this stamps has to draw');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // News lands, and the press comes before the frame that would draw
    // it: no pump between the two.
    local.record(NotificationKind.upload, at: DateTime.now());
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    expect(missed, findsNothing, reason: 'this press cannot have drawn it');

    // Which leaves the next open holding it, the way the e2e driver
    // waits for its own news: closed, opened again, and there.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    expect(
      missed,
      findsOneWidget,
      reason: 'news nobody was shown is still news',
    );
  });
}
