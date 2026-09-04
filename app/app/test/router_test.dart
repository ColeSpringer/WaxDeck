import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/radio/radio_controller.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
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

  testWidgets('the player route stands on its own with nothing playing', (
    tester,
  ) async {
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // What a reload of /now-playing looks like. The player is a view of
    // whatever is playing, so the location needs nothing in memory to
    // resolve, and with nothing playing it says so rather than bouncing
    // the visitor somewhere else.
    container.read(routerProvider).go(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.nowPlaying);
    expect(find.byKey(const Key('player-idle')), findsOneWidget);
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

  testWidgets('a screen that needs a payload stays out of the address bar', (
    tester,
  ) async {
    // The other half of the rule. These locations resolve to something
    // else on their own, so reporting them would hand out a link that
    // lands somewhere the sender did not mean.
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    container.read(routerProvider).push<void>(WaxRoute.nowPlaying);
    await tester.pumpAndSettle();

    expect(_location(container), WaxRoute.home);
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

  // The overlay routes sit on the root navigator while every domain
  // location lives inside the shell, so pushing a shell location from
  // one builds a second shell over the one already mounted and trips the
  // navigator's key reservation. The assertion loses the navigation and
  // the surface that asked for it: that is how the radio face's
  // find-in-library button came to look dead and blank the station's
  // title beside it.
  //
  // Driven through the whole app on purpose. `routedHost` puts a screen
  // at a route of its own rather than over the shell, and the push it
  // tolerates is exactly the one production refuses - so a face-level
  // test there passes either way and saw none of this.
  testWidgets('going where the news points is what clears it', (tester) async {
    // The bell used to hold a row until it was tapped or the list was
    // emptied, so dealing with the thing itself - opening the surface
    // from anywhere else - left a badge standing over work that was
    // done. The router is what sees an arrival, however it was reached.
    final container = _container(_signedIn());
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final notifications = container.read(notificationsProvider.notifier);
    notifications
      ..record(NotificationKind.upload, at: DateTime(2026, 8, 12, 9))
      ..record(NotificationKind.task, at: DateTime(2026, 8, 12, 10));
    await tester.pumpAndSettle();
    expect(container.read(notificationsProvider), hasLength(2));

    container.read(routerProvider).go(WaxRoute.uploads);
    await tester.pumpAndSettle();

    expect(
      container.read(notificationsProvider).map((n) => n.kind),
      <NotificationKind>[NotificationKind.task],
      reason: 'the visit answers its own row and leaves the other',
    );
  });

  testWidgets('find-in-library leaves the player for search', (tester) async {
    const stationPid = 'rs-01JZX5N8QW3F4V9T2B7KDSTATN1';
    final station = RadioStation(
      pid: stationPid,
      name: 'Coastal FM',
      streamUrl: 'https://stream.example/coastal',
      createdAt: DateTime.utc(2026, 7, 1),
    );
    final repo = _signedIn()
      ..radioStationsByPid[stationPid] = station
      ..radioNowPlaying[stationPid] = 'Ashley McBryde - What if We Don\'t';
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        audioEngineProvider.overrideWithValue(FakeEngine()),
        clientSettingsStoreProvider.overrideWithValue(
          MemoryClientSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await container.read(radioPlaybackProvider.notifier).play(station);
    container.read(routerProvider).push<void>(WaxRoute.nowPlaying);
    // Pumped rather than settled: the platter ring turns for as long as a
    // station plays, so there is no still frame to settle on.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.playerFindInLibrary),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(_location(container), startsWith(WaxRoute.search));
    // The station is still playing and still named; only the surface moved.
    expect(
      container.read(radioPlaybackProvider).nowPlaying,
      'Ashley McBryde - What if We Don\'t',
    );
    await container.read(radioPlaybackProvider.notifier).stop();
  });
}
