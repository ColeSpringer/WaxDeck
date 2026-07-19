import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo, Widget child) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  ),
);

void main() {
  testWidgets('connects ListenBrainz through the token dialog', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    expect(find.text('Needs server API credentials'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('scrobbler-connect-listenbrainz')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listenbrainz-token-field')),
      'token-123',
    );
    await tester.tap(find.byKey(const Key('listenbrainz-connect-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Connected as listener'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('scrobbler-disconnect-listenbrainz')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected as listener'), findsNothing);
  });

  testWidgets('surfaces an invalid ListenBrainz token', (tester) async {
    final repo = FakeRepository()
      ..connectError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the service did not accept this token',
      );
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('scrobbler-connect-listenbrainz')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('listenbrainz-token-field')),
      'bad',
    );
    await tester.tap(find.byKey(const Key('listenbrainz-connect-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('the service did not accept this token'), findsOneWidget);
  });

  testWidgets('creates an app password and shows the secret once', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo, const AppPasswordsSection()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app-password-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('app-password-label-field')),
      'Symfonium',
    );
    await tester.tap(find.byKey(const Key('app-password-create-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-password-secret')), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-password-secret-done')));
    await tester.pumpAndSettle();

    expect(find.text('Symfonium'), findsOneWidget);
  });

  testWidgets('saves the notification configuration', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo, const NotificationsSection()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('apprise-url-field')),
      'http://apprise:8000/notify',
    );
    await tester.tap(
      find.byKey(const ValueKey('notify-event-episode-downloaded')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('notifications-save')));
    await tester.pumpAndSettle();

    expect(repo.notificationConfig.appriseUrl, 'http://apprise:8000/notify');
    expect(
      repo.notificationConfig.enabledEvents,
      contains('episode-downloaded'),
    );

    await tester.tap(find.byKey(const Key('notifications-test')));
    await tester.pumpAndSettle();
    expect(repo.notificationTests, 1);
  });

  testWidgets('shows scrobbler delivery health on the slot row', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..scrobblers = [
        const Scrobbler(service: 'lastfm', available: false, connected: false),
        Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: true,
          username: 'listener',
          lastSuccessAt: DateTime.utc(2026, 7, 18),
          lastError: 'the service answered status 503',
          lastErrorAt: DateTime.utc(2026, 7, 19),
        ),
      ];
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    expect(
      find.text('Delivery failing: the service answered status 503'),
      findsOneWidget,
    );
  });

  testWidgets('a healthy delivering slot reads as such', (tester) async {
    final repo = FakeRepository()
      ..scrobblers = [
        Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: true,
          username: 'listener',
          lastSuccessAt: DateTime.utc(2026, 7, 19),
        ),
      ];
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();
    expect(find.text('Connected as listener, delivering'), findsOneWidget);
  });
}
