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
        .read(localNotificationsProvider.notifier)
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
        .read(localNotificationsProvider.notifier)
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

  testWidgets('reading the list is something the reader says', (tester) async {
    final container = await _pump(tester);
    final notifications = container.read(localNotificationsProvider.notifier);

    // Arriving no longer reads everything for you. It did when the list
    // was this session's alone: nothing outlived the page, so the only
    // thing a badge over an open list could mean was noise. An inbox
    // outlives it, and rows on it are work; the affordance is what says
    // the work is done.
    notifications.record(NotificationKind.task, at: DateTime.now());
    await tester.pumpAndSettle();
    expect(container.read(unseenNotificationsProvider), 1);

    await tester.tap(_byId(SemanticsIds.notificationsMarkAllRead));
    await tester.pumpAndSettle();
    expect(container.read(unseenNotificationsProvider), 0);
    // And the control goes with the badge it clears.
    expect(_byId(SemanticsIds.notificationsMarkAllRead), findsNothing);
  });

  testWidgets('an inbox row says whether it has been dealt with, and can '
      'be thrown away', (tester) async {
    final container = await _pump(tester);
    final repo = container.read(repositoryProvider) as FakeRepository;
    repo.inbox = <ServerNotification>[
      ServerNotification(
        id: 'nf-1',
        event: 'backup-completed',
        title: 'A backup completed',
        body: 'All of it',
        createdAt: DateTime.now(),
      ),
    ];
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();

    expect(find.textContaining('Unread'), findsOneWidget);
    expect(
      find.text('A backup completed'),
      findsNothing,
      reason: "a known event is worded in this app's own words",
    );
    expect(find.text('Backup finished'), findsOneWidget);

    await tester.tap(_byId(SemanticsIds.notificationDelete('nf-1')));
    await tester.pumpAndSettle();

    expect(repo.inboxDeleted, <String>['nf-1']);
    expect(find.text('Backup finished'), findsNothing);
  });

  testWidgets('Clear asks first, and empties the list when answered', (
    tester,
  ) async {
    final container = await _pump(tester);
    container
        .read(localNotificationsProvider.notifier)
        .record(NotificationKind.task, at: DateTime.now());
    await tester.pumpAndSettle();

    // Cancelled, the list stands: this deletes durable history on every
    // device, so the first tap is not the decision.
    await tester.tap(_byId(SemanticsIds.notificationsClear));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(notificationsViewProvider).rows, hasLength(1));

    await tester.tap(_byId(SemanticsIds.notificationsClear));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsClearConfirm));
    await tester.pumpAndSettle();

    expect(container.read(notificationRowsProvider), isEmpty);
    // The control goes with the rows: an empty list has nothing to clear.
    expect(_byId(SemanticsIds.notificationsClear), findsNothing);
    expect(find.text('Nothing to report'), findsOneWidget);
  });

  testWidgets('an empty session is a legitimate state, not a broken page', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Nothing to report'), findsOneWidget);
    // Said out loud, because the two halves keep different promises: the
    // inbox survives a relaunch and reaches the other device, and this
    // device's own transfers do not.
    expect(find.textContaining('only while the app is open'), findsOneWidget);
  });
}
