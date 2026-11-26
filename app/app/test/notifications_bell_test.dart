import 'package:flutter/semantics.dart' show debugSemanticsDisableAnimations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/notifications/notifications_bell.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

Finder _byId(String id) => find.bySemanticsIdentifier(id);

/// Pass [generation] to remount the bell, as a new element, on each bump.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ValueNotifier<int>? generation,
  FakeRepository? repo,
}) async {
  return pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: generation == null
            ? const NotificationsBell()
            : ValueListenableBuilder<int>(
                valueListenable: generation,
                builder: (context, value, _) =>
                    NotificationsBell(key: ValueKey(value)),
              ),
      ),
    ),
    container: appContainer(
      repo:
          repo ??
          FakeRepository(
            sessionState: const SessionState(
              authenticated: true,
              user: WaxDeckUser(id: 'us-1', username: 'sam', roles: <String>[]),
            ),
          ),
    ),
  );
}

ServerNotification _row(
  String event, {
  required String id,
  String body = '',
  int count = 1,
  DateTime? resolvedAt,
  required int minutesAgo,
  String? target,
}) {
  final at = DateTime.now().subtract(Duration(minutes: minutesAgo));
  return ServerNotification(
    id: id,
    event: event,
    title: 'Server title',
    body: body,
    targetPid: target,
    createdAt: at,
    updatedAt: at,
    count: count,
    resolvedAt: resolvedAt,
  );
}

FakeRepository _inboxRepo(List<ServerNotification> rows) => FakeRepository(
  sessionState: const SessionState(
    authenticated: true,
    user: WaxDeckUser(id: 'us-1', username: 'sam', roles: <String>[]),
  ),
)..inbox = rows;

/// Reads the inbox the fake holds, as the bell does once signed in.
Future<void> _loadInbox(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await container.read(authControllerProvider.future);
  container.invalidate(notificationsProvider);
  await tester.pumpAndSettle();
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('a chosen row opens its own surface, not whatever took its '
      'place', (tester) async {
    final container = await _pump(
      tester,
      repo: _inboxRepo(<ServerNotification>[
        _row('feed-disabled', id: 'nf-feed', minutesAgo: 60),
      ]),
    );
    await _loadInbox(tester, container);
    final notifications = container.read(localNotificationsProvider.notifier);
    final router = GoRouter.of(tester.element(find.byType(NotificationsBell)));
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    // Newer news arrives behind the open menu, which holds the rows it
    // opened with. The handle names the row, so it goes on meaning the
    // podcast row however the list reorders underneath.
    notifications.recordDownloadCompleted(at: DateTime.now());
    await tester.pumpAndSettle();

    await tester.tap(
      _byId(SemanticsIds.notificationRow('feed-disabled', 'nf-feed')),
    );
    await tester.pumpAndSettle();

    expect(_location(router), WaxRoute.podcasts);
  });

  // Two rows of one event have to read differently in a menu that draws
  // a line a row: the count where the row folded, the body where not.
  testWidgets('a folded row says its count and a plain one what happened', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      repo: _inboxRepo(<ServerNotification>[
        _row(
          'review-ready',
          id: 'nf-a',
          count: 3,
          body: 'Newest',
          minutesAgo: 1,
        ),
        _row(
          'feed-disabled',
          id: 'nf-b',
          target: 'pc-A',
          body: 'Alpha stopped refreshing',
          minutesAgo: 2,
        ),
        _row(
          'feed-disabled',
          id: 'nf-c',
          target: 'pc-B',
          body: 'Beta stopped refreshing',
          minutesAgo: 3,
        ),
      ]),
    );
    await _loadInbox(tester, container);
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();

    expect(find.text('Review queue: 3 waiting for review'), findsOneWidget);
    expect(find.text('Podcasts: Alpha stopped refreshing'), findsOneWidget);
    expect(find.text('Podcasts: Beta stopped refreshing'), findsOneWidget);
  });

  testWidgets('a resolved row is listed but opens nothing', (tester) async {
    final container = await _pump(
      tester,
      repo: _inboxRepo(<ServerNotification>[
        _row(
          'review-ready',
          id: 'nf-done',
          resolvedAt: DateTime.now(),
          minutesAgo: 1,
        ),
        _row(
          'feed-disabled',
          id: 'nf-open',
          target: 'pc-A',
          body: 'Alpha stopped refreshing',
          minutesAgo: 2,
        ),
      ]),
    );
    await _loadInbox(tester, container);
    final router = GoRouter.of(tester.element(find.byType(NotificationsBell)));
    final before = _location(router);
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    expect(find.text('Review queue: Review queue cleared'), findsOneWidget);

    await tester.tap(
      _byId(SemanticsIds.notificationRow('review-ready', 'nf-done')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      _location(router),
      before,
      reason: 'a resolved row has nowhere to go',
    );

    // The menu is still up, and an unresolved row beside it does open.
    await tester.tap(
      _byId(SemanticsIds.notificationRow('feed-disabled', 'nf-open')),
    );
    await tester.pumpAndSettle();
    expect(_location(router), WaxRoute.show('pc-A'));
  });

  testWidgets('the last row reads the bell rather than opening a surface', (
    tester,
  ) async {
    final container = await _pump(tester);
    final router = GoRouter.of(tester.element(find.byType(NotificationsBell)));
    final before = _location(router);

    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));
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
        .recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));
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

  testWidgets('a menu dismissed before it finished appearing reads nothing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = await _pump(tester);

    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));
    await tester.pumpAndSettle();

    // Dismissed halfway through appearing: the first frame after the press
    // only starts the entrance.
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_byId(SemanticsIds.notificationsBell)).label,
      'Notifications, 1 unread',
    );
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    expect(
      _byId(SemanticsIds.notificationRowPlain(NotificationKind.download.token)),
      findsOneWidget,
    );
    handle.dispose();
  });

  // Reduced motion, as every e2e run but one has it, cuts the entrance to
  // one frame; the soak's two clicks landed 25 ms apart.
  testWidgets('with animations off, a menu is read only once it has stood '
      'as long as its entrance would take', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await _pump(tester);
    String label() =>
        tester.getSemantics(_byId(SemanticsIds.notificationsBell)).label;

    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));
    await tester.pumpAndSettle();

    debugSemanticsDisableAnimations = true;
    try {
      await tester.tap(_byId(SemanticsIds.notificationsBell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(label(), 'Notifications, 1 unread');

      await tester.tap(_byId(SemanticsIds.notificationsBell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(label(), 'Notifications');
    } finally {
      debugSemanticsDisableAnimations = null;
    }
    handle.dispose();
  });

  testWidgets('a bell rebuilt while its menu is up still reads it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final generation = ValueNotifier<int>(0);
    addTearDown(generation.dispose);
    final container = await _pump(tester, generation: generation);

    container
        .read(localNotificationsProvider.notifier)
        .recordDownloadCompleted(at: DateTime(2026, 8, 12, 9));
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pump();
    generation.value++;
    await tester.pumpAndSettle();
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
      SemanticsIds.notificationRowPlain(NotificationKind.download.token),
    );
    // The same row again, newer: a finished transfer replaces the last.
    final missed = drawn;

    // A bell carrying a stamp, which is an open that drew something and
    // nothing else: the press below has to be shown not to move a stamp
    // that is already there, and an unstamped list would draw the row
    // whatever the press did.
    local.recordDownloadCompleted(at: DateTime.now());
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.notificationsBell));
    await tester.pumpAndSettle();
    expect(drawn, findsOneWidget, reason: 'the open this stamps has to draw');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // News lands, and the press comes before the frame that would draw
    // it: no pump between the two.
    local.recordDownloadCompleted(
      at: DateTime.now().add(const Duration(seconds: 1)),
    );
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
