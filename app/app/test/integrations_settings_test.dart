import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  displayName: 'The Admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo, Widget child) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  ),
);

FakeRepository _adminRepo() => FakeRepository(
  sessionState: const SessionState(authenticated: true, user: _admin),
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

  testWidgets('non-admins never see the Last.fm setup affordance', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scrobbler-setup-lastfm')), findsNothing);
    final connect = tester.widget<TextButton>(
      find.byKey(const ValueKey('scrobbler-connect-lastfm')),
    );
    expect(connect.onPressed, isNull);
  });

  testWidgets('an admin sets Last.fm credentials and the slot goes live', (
    tester,
  ) async {
    final repo = _adminRepo();
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    // No credentials yet: the dead Connect gives way to the setup entry.
    expect(find.text('Needs server API credentials'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('scrobbler-connect-lastfm')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('scrobbler-setup-lastfm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lastfm-api-key-field')),
      'key-123',
    );
    await tester.enterText(
      find.byKey(const Key('lastfm-secret-field')),
      'secret-456',
    );
    await tester.tap(find.byKey(const Key('lastfm-credentials-save')));
    await tester.pumpAndSettle();

    expect(repo.scrobblingConfig.lastfmConfigured, isTrue);
    expect(repo.scrobblingConfig.lastfmApiKey, 'key-123');
    expect(repo.scrobblingConfig.lastfmSource, 'settings');

    // The section reloads live: the row is connectable and the setup
    // moved into the small trailing gear.
    expect(find.text('Needs server API credentials'), findsNothing);
    final connect = tester.widget<TextButton>(
      find.byKey(const ValueKey('scrobbler-connect-lastfm')),
    );
    expect(connect.onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey('scrobbler-setup-lastfm')),
      findsOneWidget,
    );
  });

  testWidgets('a half-set credential pair surfaces the server message', (
    tester,
  ) async {
    final repo = _adminRepo();
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scrobbler-setup-lastfm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lastfm-api-key-field')),
      'key-123',
    );
    await tester.tap(find.byKey(const Key('lastfm-credentials-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('set both the API key and the secret, or neither'),
      findsOneWidget,
    );
    // The dialog stays up for the correction.
    expect(find.byKey(const Key('lastfm-credentials-save')), findsOneWidget);
    expect(repo.scrobblingConfig.lastfmConfigured, isFalse);
  });

  testWidgets('stored credentials prefill the key and can be cleared', (
    tester,
  ) async {
    final repo = _adminRepo()
      ..scrobblingConfig = const ScrobblingAdminConfig(
        lastfmConfigured: true,
        lastfmSource: 'settings',
        lastfmApiKey: 'key-abc',
        lastfmSecretSet: true,
      )
      ..scrobblers = [
        const Scrobbler(service: 'lastfm', available: true, connected: false),
        const Scrobbler(
          service: 'listenbrainz',
          available: true,
          connected: false,
        ),
      ];
    await tester.pumpWidget(_host(repo, const ScrobblingSection()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scrobbler-setup-lastfm')));
    await tester.pumpAndSettle();

    final keyField = tester.widget<TextField>(
      find.byKey(const Key('lastfm-api-key-field')),
    );
    expect(keyField.controller!.text, 'key-abc');
    expect(find.text('Stored sealed; never shown again'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lastfm-credentials-clear')));
    await tester.pumpAndSettle();

    expect(repo.scrobblingConfig.lastfmConfigured, isFalse);
    expect(find.text('Needs server API credentials'), findsOneWidget);
    expect(find.text('Set up…'), findsOneWidget);
  });
}
