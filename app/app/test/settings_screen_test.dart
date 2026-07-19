import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _user = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  displayName: 'The Admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: const MaterialApp(home: SettingsScreen()),
);

FakeRepository _signedInRepo({List<DeviceSession> sessions = const []}) =>
    FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
      sessions: sessions,
    );

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

void main() {
  testWidgets('renders the account and every session', (tester) async {
    final repo = _signedInRepo(
      sessions: [
        testSession(
          'se-1',
          kind: SessionKind.web,
          deviceName: null,
          client: 'Firefox',
          current: true,
        ),
        testSession('se-2', deviceName: 'Pixel 9'),
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('The Admin'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
    expect(find.byKey(const Key('device-row-se-1')), findsOneWidget);
    expect(find.byKey(const Key('device-row-se-2')), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);
    // The integration sections sit above the sign-out button, which
    // starts off screen in the test viewport.
    await tester.scrollUntilVisible(
      find.byKey(const Key('logout-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
  });

  testWidgets('revoking another device calls through and keeps the session', (
    tester,
  ) async {
    final repo = _signedInRepo(
      sessions: [
        testSession('se-1', current: true, deviceName: 'This one'),
        testSession('se-2', deviceName: 'Pixel 9'),
      ],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('device-revoke-se-2')));
    await tester.pumpAndSettle();
    expect(find.text('"Pixel 9" will be signed out immediately.'), findsOne);

    await tester.tap(find.byKey(const Key('device-revoke-confirm')));
    await tester.pumpAndSettle();

    expect(repo.revokedSessionIds, ['se-2']);
    expect(find.byKey(const Key('device-row-se-2')), findsNothing);
    expect(find.byKey(const Key('device-row-se-1')), findsOneWidget);
  });

  testWidgets('cancelling the confirm dialog revokes nothing', (tester) async {
    final repo = _signedInRepo(sessions: [testSession('se-2')]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('device-revoke-se-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.revokedSessionIds, isEmpty);
    expect(find.byKey(const Key('device-row-se-2')), findsOneWidget);
  });

  testWidgets('revoking the current session signs out', (tester) async {
    final repo = _signedInRepo(
      sessions: [testSession('se-1', current: true, deviceName: 'This one')],
    );
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    final container = _container(tester);

    await tester.tap(find.byKey(const Key('device-revoke-se-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-revoke-confirm')));
    await tester.pumpAndSettle();

    expect(repo.revokedSessionIds, ['se-1']);
    final auth = container.read(authControllerProvider).value;
    expect(auth?.authenticated, isFalse);
  });

  testWidgets('sign out logs out and drops the session', (tester) async {
    final repo = _signedInRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    final container = _container(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('logout-button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();

    expect(repo.sessionState.authenticated, isFalse);
    final auth = container.read(authControllerProvider).value;
    expect(auth?.authenticated, isFalse);
  });

  testWidgets('the theme dropdown stores the preference', (tester) async {
    final repo = _signedInRepo();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();

    expect(repo.prefs.theme, ThemePref.light);
  });
}
