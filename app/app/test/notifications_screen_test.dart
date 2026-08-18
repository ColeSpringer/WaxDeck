import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/notifications/notifications_screen.dart';
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
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
      child: routedHost(const NotificationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The router the screen is mounted in. Held before a tap that
/// navigates: the screen goes with it, so asking afterwards finds no
/// element to ask.
GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(NotificationsScreen)));

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('says what happened and where it says it', (tester) async {
    final container = await _pump(tester);
    container
        .read(notificationsProvider.notifier)
        .record(NotificationKind.upload, at: DateTime.now());
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.notificationsScreen), findsOneWidget);
    expect(find.text('An upload changed.'), findsOneWidget);
    // The second half of the topic, and the reason this is a destination
    // rather than the bell drawn larger: the delivery targets were a row
    // inside a settings section nobody looking for "stop telling me
    // about this" would think to open.
    expect(_byId(SemanticsIds.notifyTargetAdd), findsOneWidget);
  });

  testWidgets('a row is a link to the surface it is about', (tester) async {
    final container = await _pump(tester);
    final router = _router(tester);
    container
        .read(notificationsProvider.notifier)
        .record(NotificationKind.feedDisabled, at: DateTime.now(), pid: 'pc-1');
    await tester.pumpAndSettle();

    await tester.tap(
      _byId(
        SemanticsIds.notificationRow(
          NotificationKind.feedDisabled.token,
          'pc-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The entity the marker named, not the kind's own surface.
    expect(_location(router), WaxRoute.show('pc-1'));
  });

  testWidgets('arriving reads the list, and so does news landing on it', (
    tester,
  ) async {
    final container = await _pump(tester);
    final router = _router(tester);
    final notifications = container.read(notificationsProvider.notifier);

    // Unlike the bell, this surface stays open. A row landing on it is
    // read where it lands: a badge climbing on the page somebody is
    // looking at is the bell's own promise broken.
    notifications.record(NotificationKind.task, at: DateTime.now());
    await tester.pumpAndSettle();
    expect(container.read(unseenNotificationsProvider), 0);

    // And a backlog gathered elsewhere is read on arrival, which is what
    // opening the bell does too.
    router.go(WaxRoute.settings);
    await tester.pumpAndSettle();
    notifications.record(NotificationKind.upload, at: DateTime.now());
    await tester.pumpAndSettle();
    expect(container.read(unseenNotificationsProvider), 1);

    router.go(WaxRoute.notifications);
    await tester.pumpAndSettle();

    expect(_byId(SemanticsIds.notificationsScreen), findsOneWidget);
    expect(container.read(unseenNotificationsProvider), 0);
  });

  testWidgets('Clear empties the list, and goes with it', (tester) async {
    final container = await _pump(tester);
    container
        .read(notificationsProvider.notifier)
        .record(NotificationKind.task, at: DateTime.now());
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.notificationsClear));
    await tester.pumpAndSettle();

    expect(container.read(notificationsProvider), isEmpty);
    // The control goes with the rows: an empty list has nothing to clear.
    expect(_byId(SemanticsIds.notificationsClear), findsNothing);
    expect(find.text('Nothing to report'), findsOneWidget);
  });

  testWidgets('an empty session is a legitimate state, not a broken page', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Nothing to report'), findsOneWidget);
    // Said out loud, because there is no server inbox behind this: the
    // list is what this client saw while it was running, and a launch
    // starts it empty.
    expect(find.textContaining('since the app opened'), findsOneWidget);
  });
}
