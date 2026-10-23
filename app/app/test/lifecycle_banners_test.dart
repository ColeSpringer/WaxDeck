import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/server_settings_screen.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/lifecycle_banners.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'routed_host.dart';

/// The banners on their own, the way the shell frame hosts them.
class _BannerHost extends ConsumerWidget {
  const _BannerHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: lifecycleBanners(context, ref),
    ),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeRepository repo,
}) async {
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: localizedHost(const _BannerHost(), theme: buildWaxTheme()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a dropped connection says it is reconnecting, and stops', (
    tester,
  ) async {
    final container = await _pump(tester, repo: FakeRepository());
    // Nothing has answered yet, which is not the same as a broken
    // connection: a client that has not tried is not reconnecting.
    expect(find.byType(WaxBanner), findsNothing);

    container.read(liveLinkProvider.notifier).report(connected: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnecting'), findsOneWidget);

    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();
    expect(
      find.byType(WaxBanner),
      findsNothing,
      reason: 'it clears itself, silently',
    );
  });

  testWidgets('a server that came back as another build says so', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    // The first connect is the baseline, never a report of change.
    link.report(connected: true);
    await tester.pumpAndSettle();
    expect(find.byType(WaxBanner), findsNothing);

    // A restart, which is exactly what a reconnect means here.
    repo.serverVersion = '1.1.0';
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsOneWidget);
  });

  testWidgets('an API version bump counts as a new build', (tester) async {
    // The case the banner exists for: a bundle from before a contract
    // change, still running against the server that changed it.
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    link.report(connected: true);
    await tester.pumpAndSettle();

    repo.apiVersion = 2;
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsOneWidget);
  });

  testWidgets('a probe that fails off-contract says nothing, and survives', (
    tester,
  ) async {
    // The probe runs unawaited, so anything escaping it reaches the zone
    // with no handler. The client maps only transport failures into the
    // structured API error, and a response the generated deserializer
    // cannot build throws something else - which is exactly the shape
    // the one event this watches for can produce.
    final repo = FakeRepository()
      ..serverHealthError = const FormatException('not the health you knew');
    final container = await _pump(tester, repo: repo);

    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(WaxBanner), findsNothing);

    // And the baseline was never taken, so the next probe that answers
    // is the one that establishes it rather than a false alarm.
    repo.serverHealthError = null;
    repo.serverVersion = '1.1.0';
    container.read(liveLinkProvider.notifier).report(connected: false);
    await tester.pumpAndSettle();
    container.read(liveLinkProvider.notifier).report(connected: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('updated'), findsNothing);
  });

  testWidgets('a reconnect onto the same build says nothing', (tester) async {
    final repo = FakeRepository();
    final container = await _pump(tester, repo: repo);
    final link = container.read(liveLinkProvider.notifier);

    link.report(connected: true);
    await tester.pumpAndSettle();
    link.report(connected: false);
    await tester.pumpAndSettle();
    link.report(connected: true);
    await tester.pumpAndSettle();

    expect(find.textContaining('updated'), findsNothing);
  });

  group('the read-only banner', () {
    const listener = WaxDeckUser(
      id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      username: 'listener',
      roles: ['user'],
    );
    SessionState session({required bool readOnly}) => SessionState(
      authenticated: true,
      user: listener,
      serverReadOnly: readOnly,
    );

    testWidgets('stays up while the session says read-only, and clears', (
      tester,
    ) async {
      final repo = FakeRepository(sessionState: session(readOnly: true));
      final container = await _pump(tester, repo: repo);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.readOnlyBanner),
        findsOneWidget,
      );
      expect(
        find.textContaining('This server is read-only right now'),
        findsOneWidget,
      );

      // The account marker is what makes an open client read it again.
      repo.sessionState = session(readOnly: false);
      await container.read(authControllerProvider.notifier).refreshSession();
      await tester.pumpAndSettle();
      expect(find.byType(WaxBanner), findsNothing);

      repo.sessionState = session(readOnly: true);
      await container.read(authControllerProvider.notifier).refreshSession();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.readOnlyBanner),
        findsOneWidget,
      );
    });

    testWidgets('leads an administrator to the switch, and no one else', (
      tester,
    ) async {
      final admin = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(
            id: 'us-01JZX5N8QW3F4V9T2B7KDADMIN01',
            username: 'admin',
            roles: ['admin'],
          ),
          serverReadOnly: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(admin),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: routedHost(const _BannerHost()),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.bySemanticsIdentifier(
        SemanticsIds.readOnlyBannerSettings,
      );
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(ServerSettingsScreen), findsOneWidget);

      await _pump(
        tester,
        repo: FakeRepository(sessionState: session(readOnly: true)),
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.readOnlyBanner),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.readOnlyBannerSettings),
        findsNothing,
      );
    });

    testWidgets('says nothing on a writable server or when signed out', (
      tester,
    ) async {
      await _pump(
        tester,
        repo: FakeRepository(sessionState: session(readOnly: false)),
      );
      expect(find.byType(WaxBanner), findsNothing);

      await _pump(tester, repo: FakeRepository());
      expect(find.byType(WaxBanner), findsNothing);
    });
  });
}
