import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxSwitch;

import 'fakes.dart';
import 'localized_host.dart';

/// The switch inside one event row. The key names the row; the control
/// is what a tap has to land on.
Finder _eventSwitch(String event) => find.descendant(
  of: find.byKey(ValueKey('notify-event-$event')),
  matching: find.byType(WaxSwitch),
);

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
  child: localizedHost(Scaffold(body: ListView(children: [child]))),
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

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.appPasswordAdd));
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

  testWidgets('creates a personal notification target through the editor', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notification targets yet'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();

    // The kind dropdown swaps the config field group: Pushover's
    // token and key give way to Gotify's server URL and token.
    expect(find.byKey(const ValueKey('notify-config-userKey')), findsOneWidget);
    expect(find.byKey(const ValueKey('notify-config-serverUrl')), findsNothing);
    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gotify').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notify-config-userKey')), findsNothing);
    expect(
      find.byKey(const ValueKey('notify-config-serverUrl')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('notify-target-label')),
      'My phone',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-serverUrl')),
      'https://gotify.example.net',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-token')),
      'app-token',
    );
    await tester.tap(_eventSwitch('episode-downloaded'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(repo.myNotificationTargets, hasLength(1));
    final saved = repo.myNotificationTargets.single;
    expect(saved.kind, 'gotify');
    expect(saved.label, 'My phone');
    expect(saved.config['serverUrl'], 'https://gotify.example.net');
    expect(saved.config['token'], 'app-token');
    expect(saved.enabledEvents, ['episode-downloaded']);
    expect(find.text('My phone'), findsOneWidget);
  });

  testWidgets('the editor refuses a missing required config field', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pump();
    expect(find.text('Application token is required'), findsOneWidget);
    expect(repo.myNotificationTargets, isEmpty);
  });

  testWidgets('a server rejection keeps the editor open with the message', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..notificationTargetError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'the destination resolves to a private address',
      );
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-token')),
      't',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-userKey')),
      'u',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('the destination resolves to a private address'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notify-target-save')), findsOneWidget);
  });

  testWidgets('the personal checklist offers server events to admins only', (
    tester,
  ) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-episode-downloaded')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final adminRepo = _adminRepo();
    await tester.pumpWidget(
      _host(adminRepo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsOneWidget,
    );
    expect(find.text('Server events'), findsOneWidget);
    expect(find.text('My events'), findsOneWidget);
  });

  testWidgets('the server section edits server-scope targets only', (
    tester,
  ) async {
    final repo = _adminRepo();
    await tester.pumpWidget(
      _host(repo, const ServerNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.notifyServerTargetAdd),
    );
    await tester.pumpAndSettle();

    // Server-scope editors list server events only, flat.
    expect(
      find.byKey(const ValueKey('notify-event-signup-requested')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('notify-event-episode-downloaded')),
      findsNothing,
    );
    expect(find.text('Server events'), findsNothing);

    await tester.tap(find.byKey(const Key('notify-target-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webhook').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-url')),
      'https://hooks.example.net/ops',
    );
    await tester.tap(_eventSwitch('signup-requested'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();

    expect(repo.serverNotificationTargets, hasLength(1));
    expect(repo.serverNotificationTargets.single.scope, 'server');
    expect(repo.serverNotificationTargets.single.kind, 'webhook');
  });

  testWidgets('tests a target and edits it back through the round trip', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..myNotificationTargets.add(
        NotificationTarget(
          pid: 'nt-SEED',
          kind: 'ntfy',
          scope: 'user',
          label: 'Tablet',
          config: const {'topic': 'waxdeck', 'accessToken': 'tk'},
          enabledEvents: const ['episode-downloaded'],
          createdAt: DateTime.utc(2026),
        ),
      );
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notify-target-test-nt-SEED')));
    await tester.pumpAndSettle();
    expect(repo.notificationTargetTests['nt-SEED'], 1);

    // Editing seeds the round-tripped config and replaces it whole.
    await tester.tap(find.byKey(const ValueKey('notify-target-nt-SEED')));
    await tester.pumpAndSettle();
    final topicField = tester.widget<TextField>(
      find.byKey(const ValueKey('notify-config-topic')),
    );
    expect(topicField.controller!.text, 'waxdeck');
    await tester.enterText(
      find.byKey(const ValueKey('notify-config-topic')),
      'waxdeck-2',
    );
    await tester.tap(find.byKey(const Key('notify-target-save')));
    await tester.pumpAndSettle();
    expect(repo.myNotificationTargets.single.config['topic'], 'waxdeck-2');
    expect(repo.myNotificationTargets.single.config['accessToken'], 'tk');
  });

  testWidgets('an unhealthy target shows its standing delivery error', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..myNotificationTargets.add(
        NotificationTarget(
          pid: 'nt-SICK',
          kind: 'pushover',
          scope: 'user',
          config: const {'token': 't', 'userKey': 'u'},
          enabledEvents: const [],
          createdAt: DateTime.utc(2026),
          lastError: 'delivery answered status 401',
          lastErrorAt: DateTime.utc(2026, 7, 22),
        ),
      );
    await tester.pumpWidget(
      _host(repo, const PersonalNotificationTargetsSection()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('delivery answered status 401'), findsOneWidget);
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
