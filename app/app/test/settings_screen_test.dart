import 'package:flutter/material.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart' show WaxTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _user = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  displayName: 'The Admin',
  roles: ['admin'],
);

Widget _host(FakeRepository repo, Widget screen) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(screen),
);

Widget _section(FakeRepository repo, SettingsSection section) =>
    _host(repo, SettingsSectionScreen(section: section));

FakeRepository _signedInRepo({List<DeviceSession> sessions = const []}) =>
    FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
      sessions: sessions,
    );

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

Future<void> _show(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);

/// A surface tall enough to hold a settings section.
///
/// The default 800x600 test window is shorter than any device this ships
/// on, and a section is a column of rows by design - so on the default
/// window most of these tests would be exercising `scrollUntilVisible`
/// rather than the settings. Restored after each test, so nothing leaks
/// into the next one.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the settings home', () {
    testWidgets('lists every section a member may open', (tester) async {
      _tallWindow(tester);
      final repo = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-2', username: 'sam'),
        ),
      );
      await tester.pumpWidget(_host(repo, const SettingsScreen()));
      await tester.pumpAndSettle();

      for (final section in SettingsSection.values) {
        final row = find.bySemanticsIdentifier(
          SemanticsIds.settingsSection(section.segment),
        );
        // Server is the administrator's alone, and absent rather than
        // present and refusing.
        expect(
          row,
          section.adminOnly ? findsNothing : findsOneWidget,
          reason: section.title,
        );
      }
    });

    testWidgets('an administrator also gets the server section', (
      tester,
    ) async {
      _tallWindow(tester);
      await tester.pumpWidget(_host(_signedInRepo(), const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSection('server')),
        findsOneWidget,
      );
    });

    testWidgets('search finds a setting by a word that is not in its name', (
      tester,
    ) async {
      _tallWindow(tester);
      await tester.pumpWidget(_host(_signedInRepo(), const SettingsScreen()));
      await tester.pumpAndSettle();

      // "Loudness" appears nowhere in "Level casting volume"; the
      // keyword is what makes arriving from another app's vocabulary
      // land.
      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        'loudness',
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsResult('replay-gain')),
        findsOneWidget,
      );
      // The section list is replaced by the results rather than sitting
      // under them.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSection('playback')),
        findsNothing,
      );
    });

    testWidgets('a query that matches nothing says so', (tester) async {
      _tallWindow(tester);
      await tester.pumpWidget(_host(_signedInRepo(), const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        'zzzz',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No setting matches'), findsOneWidget);
    });
  });

  group('the account section', () {
    testWidgets('renders the account and every session', (tester) async {
      _tallWindow(tester);
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
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();

      expect(find.text('The Admin'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deviceRow('se-1')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deviceRow('se-2')),
        findsOneWidget,
      );
      expect(find.textContaining('this device'), findsOneWidget);
      expect(find.text('Firefox (this device)'), findsOneWidget);
      expect(find.textContaining('Pixel 9'), findsOneWidget);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.logoutButton),
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.logoutButton),
        findsOneWidget,
      );
    });

    testWidgets('revoking another device calls through and keeps the session', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [
          testSession('se-1', current: true, deviceName: 'This one'),
          testSession('se-2', deviceName: 'Pixel 9'),
        ],
      );
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-2')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('"Pixel 9" will be signed out immediately.'), findsOne);

      await tester.tap(find.byKey(const Key('device-revoke-confirm')));
      await tester.pumpAndSettle();

      expect(repo.revokedSessionIds, ['se-2']);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deviceRow('se-2')),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deviceRow('se-1')),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the confirm dialog revokes nothing', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo(sessions: [testSession('se-2')]);
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-2')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.revokedSessionIds, isEmpty);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.deviceRow('se-2')),
        findsOneWidget,
      );
    });

    testWidgets('revoking the current session signs out', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [testSession('se-1', current: true, deviceName: 'This one')],
      );
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();
      final container = _container(tester, SettingsSectionScreen);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-1')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.deviceRevoke('se-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-revoke-confirm')));
      await tester.pumpAndSettle();

      expect(repo.revokedSessionIds, ['se-1']);
      final auth = container.read(authControllerProvider).value;
      expect(auth?.authenticated, isFalse);
    });

    testWidgets('sign out logs out and drops the session', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();
      final container = _container(tester, SettingsSectionScreen);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.logoutButton),
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.logoutButton));
      await tester.pumpAndSettle();

      expect(repo.sessionState.authenticated, isFalse);
      final auth = container.read(authControllerProvider).value;
      expect(auth?.authenticated, isFalse);
    });

    testWidgets('changing a password sends the current one with it', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('password')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password')),
      );
      await tester.pumpAndSettle();

      // A refusal lands against the field it is about. The server checks
      // the new password's policy before it verifies the current one, so
      // a correct current password and a short new one is refused for a
      // reason that has nothing to do with the field above it - and
      // putting that message there tells somebody to re-type a value
      // that was already right.
      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password-save')),
      );
      await tester.pumpAndSettle();
      final policy = find.text('password must be at least 8 characters');
      expect(policy, findsOneWidget);
      // Under the new-password field, which is the whole point: the two
      // fields are adjacent and the wrong one is a wasted attempt.
      expect(
        tester
            .widgetList<WaxTextField>(find.byType(WaxTextField))
            .map((f) => f.errorText)
            .toList(),
        <String?>[null, 'password must be at least 8 characters'],
      );
      expect(repo.setUserPasswordCalls, isEmpty);

      // The wrong current password is the other refusal, and it moves to
      // the other field.
      await tester.enterText(find.byType(TextField).first, 'not-it');
      await tester.enterText(find.byType(TextField).last, 'newsecret1');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password-save')),
      );
      await tester.pumpAndSettle();
      expect(find.text('That is not your current password'), findsOneWidget);
      expect(policy, findsNothing);
      expect(repo.setUserPasswordCalls, isEmpty);

      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password-save')),
      );
      await tester.pumpAndSettle();
      expect(repo.setUserPasswordCalls, [
        (userId: _user.id, newPassword: 'newsecret1'),
      ]);
    });
  });

  group('the appearance section', () {
    testWidgets('the theme picker stores the preference', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

      await _show(tester, find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();

      expect(repo.prefs.theme, ThemePref.light);
    });

    testWidgets('density and artwork size are this device, not the account', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('density')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('density')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact').last);
      await tester.pumpAndSettle();

      // Nothing about it reached the account's document, which is the
      // whole of what makes it a per-device setting.
      expect(repo.putPrefsCalls, isEmpty);
      expect(find.text('Compact'), findsOneWidget);
    });
  });

  group('the playback section', () {
    testWidgets('the skip intervals store and read back', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.playback));
      await tester.pumpAndSettle();

      expect(find.text('15 seconds'), findsOneWidget);
      expect(find.text('30 seconds'), findsOneWidget);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('skip-back')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('skip-back')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 seconds').last);
      await tester.pumpAndSettle();

      // Both controls now read thirty, which is the point of drawing the
      // value on the control: the pair is legible without opening either.
      expect(find.text('30 seconds'), findsNWidgets(2));
      expect(repo.putPrefsCalls, isEmpty);
    });

    testWidgets('the crossfade and the leveling switch ride the account', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.playback));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('crossfade')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('crossfade')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 seconds').last);
      await tester.pumpAndSettle();
      expect(repo.prefs.crossfadeSeconds, 4);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('replay-gain')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('replay-gain')),
      );
      await tester.pumpAndSettle();
      expect(repo.prefs.replayGain, isTrue);

      // Off has to survive the round trip: zero is a value and not a
      // "keep what is stored", which is what turning a crossfade back off
      // depends on.
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('crossfade')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      expect(repo.prefs.crossfadeSeconds, 0);
    });
  });

  group('the integrations section', () {
    testWidgets('the radio switch is drawn from the opt-out, inverted', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.integrations));
      await tester.pumpAndSettle();

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.radioScrobbleSwitch),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.radioScrobbleSwitch),
      );
      await tester.pumpAndSettle();

      // The switch says "scrobble radio" and the document says "opt
      // out", so turning the switch off has to store true.
      expect(repo.prefs.radioScrobbleOptOut, isTrue);
    });
  });

  group('the server section', () {
    testWidgets('refuses a member who typed the location', (tester) async {
      _tallWindow(tester);
      final repo = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-2', username: 'sam'),
        ),
      );
      await tester.pumpWidget(_section(repo, SettingsSection.server));
      await tester.pumpAndSettle();

      expect(find.text('Administrators only'), findsOneWidget);
    });
  });
}
