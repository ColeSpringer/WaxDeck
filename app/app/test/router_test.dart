import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';

const _user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

ProviderContainer _container(FakeRepository repo) => ProviderContainer(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
);

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const WaxDeckApp());

FakeRepository _signedIn() => FakeRepository(
  sessionState: const SessionState(authenticated: true, user: _user),
  items: [testItem('tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE')],
);

String _location(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

void main() {
  testWidgets('a signed-out visitor is sent to login', (tester) async {
    final container = _container(FakeRepository());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.login);
  });

  testWidgets('a server with no accounts sends every location to setup', (
    tester,
  ) async {
    final container = _container(FakeRepository(bootstrapNeeded: true));
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(WaxRoute.settings);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.setup);
  });

  testWidgets('the auth screens are unreachable while signed in', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(WaxRoute.login);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.home);
  });

  testWidgets('a deep link survives the trip through the login form', (
    tester,
  ) async {
    final repo = FakeRepository();
    final container = _container(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(WaxRoute.settings);
    await tester.pumpAndSettle();
    expect(
      _location(container),
      '${WaxRoute.login}?${WaxRoute.fromParam}=%2Fsettings',
    );
    expect(find.byKey(const Key('login-username')), findsOneWidget);

    await container
        .read(authControllerProvider.notifier)
        .login(username: 'admin', password: 'wax-setup-pass');
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.settings);
  });

  testWidgets('a from parameter pointing off the app is refused', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // Each of these reads as an authority once a browser is done with
    // it: the second slash outright, the backslash because http(s)
    // treats it as one, and the tab because URL parsing strips it.
    for (final hostile in [
      '//example.com/',
      r'/\example.com/',
      '/%09/example.com/',
      'https://example.com/',
    ]) {
      container
          .read(routerProvider)
          .go('${WaxRoute.login}?${WaxRoute.fromParam}=$hostile');
      await tester.pumpAndSettle();

      expect(_location(container), WaxRoute.home, reason: hostile);
    }
  });

  testWidgets('signing out replaces the signed-in stack with login', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).push(WaxRoute.settings);
    await tester.pumpAndSettle();

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.login);
    expect(find.byKey(const Key('login-username')), findsOneWidget);
  });

  testWidgets('the editing prototype opens without a session', (tester) async {
    final container = _container(FakeRepository());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(WaxRoute.editingPrototype);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.editingPrototype);
  });

  testWidgets('a player route with no item in hand lands on the library', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // What a reload of /now-playing looks like: the location survives,
    // the in-memory item does not.
    container.read(routerProvider).go(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.home);
  });

  testWidgets('an unknown location renders the not-found screen', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/no-such-place');
    await tester.pumpAndSettle();

    expect(find.text('That page does not exist.'), findsOneWidget);

    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(_location(container), WaxRoute.home);
  });

  testWidgets('a screen opened directly can still leave', (tester) async {
    final container = _container(FakeRepository());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // Straight to the signup link with no login screen underneath, the
    // way a shared invite arrives.
    container.read(routerProvider).go(WaxRoute.signup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signup-username')), 'pippin');
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'second-breakfast',
    );
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to sign-in'));
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.login);
  });

  testWidgets('the preserved metadata deep link still resolves', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(WaxRoute.metadata('tr-1'));
    await tester.pumpAndSettle();

    expect(_location(container), '/metadata/tr-1');
  });
}
