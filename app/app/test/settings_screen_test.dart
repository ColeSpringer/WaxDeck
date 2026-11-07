import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_screen.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'row_nodes.dart';
import 'wax_finders.dart';

const _user = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  displayName: 'The Admin',
  roles: ['admin'],
);

/// [locale] only where the copy is what the test is about: every other
/// assertion in this file reads English.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeRepository repo,
  Widget screen, {
  Locale locale = const Locale('en'),
}) => pumpApp(
  tester,
  screen,
  container: appContainer(repo: repo),
  locale: locale,
);

Future<ProviderContainer> _pumpSection(
  WidgetTester tester,
  FakeRepository repo,
  SettingsSection section,
) => _pump(tester, repo, SettingsSectionScreen(section: section));

/// Mounted and not settled, for a test that pumps on its own clock.
Future<void> _mountSection(
  WidgetTester tester,
  FakeRepository repo,
  SettingsSection section,
) => mountApp(
  tester,
  SettingsSectionScreen(section: section),
  container: appContainer(repo: repo),
);

/// A write lost to a dropped connection, worded the way the client's
/// transport words it: in English, whatever the app's language.
const _dropped = WaxDeckApiException(
  code: 'transport',
  message: 'DioException [connection error]',
);

/// A password change that never reaches the server.
class _PasswordUnreachable extends FakeRepository {
  _PasswordUnreachable()
    : super(sessionState: const SessionState(authenticated: true, user: _user));

  @override
  Future<void> setUserPassword(
    String userId,
    String newPassword, {
    String? currentPassword,
  }) async => throw _dropped;
}

/// A device list the server fails to read while [down] is set.
class _SessionsDown extends FakeRepository {
  _SessionsDown()
    : super(
        sessionState: const SessionState(authenticated: true, user: _user),
        sessions: [testSession('se-2', deviceName: 'Pixel 9')],
      );

  var down = true;

  @override
  Future<List<DeviceSession>> listSessions() async {
    if (down) {
      throw const WaxDeckApiException(
        code: 'internal',
        message: 'boom',
        statusCode: 500,
      );
    }
    return super.listSessions();
  }
}

FakeRepository _signedInRepo({List<DeviceSession> sessions = const []}) =>
    FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _user),
      sessions: sessions,
    );

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

Future<void> _show(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);

/// Puts the session in the input mode where hovering means something.
///
/// A test binding starts in touch mode - the mode a phone is in, and a
/// tablet whose keyboard case is off - which is exactly the state the
/// caption setting is not honoured in.
void _withPointerHighlight() =>
    _highlight(FocusHighlightStrategy.alwaysTraditional);

/// Puts it in the mode a tap leaves it in, which is where a hybrid
/// machine spends every moment between reaching for the mouse.
void _withTouchHighlight() => _highlight(FocusHighlightStrategy.alwaysTouch);

void _highlight(FocusHighlightStrategy strategy) {
  FocusManager.instance.highlightStrategy = strategy;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
}

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
      await _pump(tester, repo, const SettingsScreen());

      // A section is its title and glyph; no sentence under the name.
      expect(
        find.text('Theme, density, and how large artwork is drawn'),
        findsNothing,
      );
      expect(
        find.text('Speeds, skips, casting, and what plays next'),
        findsNothing,
      );
      for (final section in SettingsSection.values) {
        final row = find.bySemanticsIdentifier(
          SemanticsIds.settingsSection(section.segment),
        );
        // Server is the administrator's alone, and absent rather than
        // present and refusing.
        expect(
          row,
          section.adminOnly ? findsNothing : findsOneWidget,
          reason: section.segment,
        );
      }
    });

    testWidgets('renders in Spanish when Spanish is the resolved locale', (
      tester,
    ) async {
      // The one proof a locale other than the template actually draws:
      // the delegates resolve and the es bundle is compiled in. It says
      // nothing about date symbols - this screen formats none.
      _tallWindow(tester);
      await _pump(
        tester,
        _signedInRepo(),
        const SettingsScreen(),
        locale: const Locale('es'),
      );

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Apariencia'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an administrator also gets the server section', (
      tester,
    ) async {
      _tallWindow(tester);
      await _pump(tester, _signedInRepo(), const SettingsScreen());

      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSection('server')),
        findsOneWidget,
      );
    });

    testWidgets('search finds a setting by a word that is not in its name', (
      tester,
    ) async {
      _tallWindow(tester);
      await _pump(tester, _signedInRepo(), const SettingsScreen());

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
      await _pump(tester, _signedInRepo(), const SettingsScreen());

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        'zzzz',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No setting matches'), findsOneWidget);
      // A show's or a book's own settings are on it, which holds for
      // every account; the server's are in the admin console, which only
      // an administrator can open, so only an administrator is offered
      // the way there.
      expect(emptyStateTitled('No setting matches "zzzz"'), findsOneWidget);
      expect(
        tester
            .widget<EmptyState>(emptyStateTitled('No setting matches "zzzz"'))
            .message,
        'Shows and books keep their own settings',
      );
      await tester.tap(find.text('Open the admin console'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier(SemanticsIds.adminConsole), findsOne);
    });

    testWidgets('a member who matches nothing is not sent to the console', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = FakeRepository(
        sessionState: const SessionState(
          authenticated: true,
          user: WaxDeckUser(id: 'us-2', username: 'sam'),
        ),
      );
      await _pump(tester, repo, const SettingsScreen());

      await tester.enterText(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        'zzzz',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Shows and books keep their own settings'),
        findsOneWidget,
      );
      expect(find.textContaining('admin console'), findsNothing);
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
      await _pumpSection(tester, repo, SettingsSection.account);

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
      await _pumpSection(tester, repo, SettingsSection.account);

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

    testWidgets('signing a device out leaves the next one its own controls', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [
          testSession('se-1', current: true, deviceName: 'This one'),
          testSession('se-2', deviceName: 'Pixel 9'),
          testSession('se-3', deviceName: 'Kitchen radio'),
        ],
      );
      await _pumpSection(tester, repo, SettingsSection.account);
      final revoke = find.bySemanticsIdentifier(
        SemanticsIds.deviceRevoke('se-2'),
      );
      await _show(tester, revoke);

      await expectRowsKeepTheirNodes(
        tester,
        [SemanticsIds.deviceRow('se-3'), SemanticsIds.deviceRevoke('se-3')],
        () async {
          await tester.tap(revoke);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('device-revoke-confirm')));
          await tester.pumpAndSettle();
        },
      );
      expect(repo.revokedSessionIds, ['se-2']);
    });

    testWidgets('renaming a device sends the trimmed name', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [
          testSession('se-1', current: true, deviceName: 'This one'),
          testSession('se-2', deviceName: 'Pixel 9'),
        ],
      );
      await _pumpSection(tester, repo, SettingsSection.account);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.deviceRename('se-2')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.deviceRename('se-2')),
      );
      await tester.pumpAndSettle();

      // The dialog opens on the name the row already carries, so a
      // rename is an edit rather than a retype.
      expect(find.widgetWithText(TextField, 'Pixel 9'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Kitchen radio  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-rename-confirm')));
      await tester.pumpAndSettle();

      expect(repo.renamedSessions, [(id: 'se-2', deviceName: 'Kitchen radio')]);
      // Redrawn from the reloaded list, not from what was typed.
      expect(find.textContaining('Kitchen radio'), findsOneWidget);
      expect(find.textContaining('Pixel 9'), findsNothing);
    });

    testWidgets('a rename in flight spins on its Save', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [testSession('se-2', deviceName: 'Pixel 9')],
      );
      await _pumpSection(tester, repo, SettingsSection.account);
      final rename = find.bySemanticsIdentifier(
        SemanticsIds.deviceRename('se-2'),
      );
      await _show(tester, rename);
      await tester.tap(rename);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kitchen radio');
      await tester.pumpAndSettle();
      final gate = repo.renameGate = Completer<void>();
      final save = find.byKey(const Key('device-rename-confirm'));
      await tester.tap(save);
      await tester.pump();

      expect(tester.widget<WaxButton>(save).busy, isTrue);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('an empty name cannot be saved', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [testSession('se-2', deviceName: 'Pixel 9')],
      );
      await _pumpSection(tester, repo, SettingsSection.account);

      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.deviceRename('se-2')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.deviceRename('se-2')),
      );
      await tester.pumpAndSettle();

      // The server refuses a blank name, so the button refuses it here
      // rather than spending a round trip on a certain 400.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      final save = tester.widget<WaxButton>(
        find.byKey(const Key('device-rename-confirm')),
      );
      expect(save.onPressed, isNull);

      // A refusal is about the name that was submitted, so editing the
      // field clears it: the dialog must never show "invalid" beside an
      // enabled Save.
      repo.renameError = const WaxDeckApiException(
        code: 'invalid-request',
        message: 'deviceName must be 1 to 128 characters after trimming',
      );
      await tester.enterText(find.byType(TextField), 'Nope');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-rename-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 to 128 characters'), findsOneWidget);

      repo.renameError = null;
      await tester.enterText(find.byType(TextField), 'Kitchen radio');
      await tester.pumpAndSettle();
      expect(find.textContaining('1 to 128 characters'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.renamedSessions, isEmpty);
    });

    testWidgets("a rename lost to a dropped connection is said in the app's "
        'words', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [testSession('se-2', deviceName: 'Pixel 9')],
      )..renameError = _dropped;
      await _pumpSection(tester, repo, SettingsSection.account);
      final rename = find.bySemanticsIdentifier(
        SemanticsIds.deviceRename('se-2'),
      );
      await _show(tester, rename);
      await tester.tap(rename);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kitchen radio');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-rename-confirm')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<WaxTextField>(find.byType(WaxTextField)).errorText,
        AppLocalizationsEn().errorNetwork,
      );
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets('a device list that fails says why, and asking again once '
        'it gives up reads it', (tester) async {
      _tallWindow(tester);
      final repo = _SessionsDown();
      await _mountSection(tester, repo, SettingsSection.account);
      // Past the default ladder's ten attempts: the failure is final.
      await tester.pump(const Duration(seconds: 40));
      await tester.pump();

      final en = AppLocalizationsEn();
      expect(find.text(en.settingsDevicesErrorTitle), findsOneWidget);
      expect(find.text(en.errorInternal), findsOneWidget);
      final retry = find.widgetWithText(WaxButton, 'Try again');
      expect(tester.widget<WaxButton>(retry).busy, isFalse);

      repo.down = false;
      await _show(tester, retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Pixel 9'), findsOneWidget);
    });

    testWidgets('cancelling the confirm dialog revokes nothing', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo(sessions: [testSession('se-2')]);
      await _pumpSection(tester, repo, SettingsSection.account);

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
      await _pumpSection(tester, repo, SettingsSection.account);
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
      await _pumpSection(tester, repo, SettingsSection.account);
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
      await _pumpSection(tester, repo, SettingsSection.account);

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

    testWidgets("a password change lost to a dropped connection is said in "
        "the app's words, under the new password", (tester) async {
      _tallWindow(tester);
      await _pumpSection(
        tester,
        _PasswordUnreachable(),
        SettingsSection.account,
      );
      await _show(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.setting('password')),
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.enterText(find.byType(TextField).last, 'newsecret1');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('password-save')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<WaxTextField>(find.byType(WaxTextField))
            .map((f) => f.errorText)
            .toList(),
        <String?>[null, AppLocalizationsEn().errorNetwork],
      );
      expect(find.textContaining('DioException'), findsNothing);
    });
  });

  group('the appearance section', () {
    test('an unset theme follows the system', () async {
      final repo = _signedInRepo();
      final container = appContainer(repo: repo);
      // Before the document loads, and after it loads with nothing
      // stored, the platform decides. Only a stored choice departs.
      expect(container.read(themeModeProvider), ThemeMode.system);
      await container.read(prefsControllerProvider.future);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('an unset theme shows System in the picker', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      final choice = tester.widget<WaxChoice<ThemePref>>(
        find.byWidgetPredicate((w) => w is WaxChoice<ThemePref>),
      );
      expect(choice.value, ThemePref.system);
    });

    testWidgets('the theme picker stores the preference on this device', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      await _show(tester, find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();

      final container = _container(tester, SettingsSectionScreen);
      expect(container.read(themeSettingProvider), ThemePref.light);
      // And not on the account: a light picked on the web used to follow
      // the phone carried outdoors.
      expect(repo.prefs.theme, isNull);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('the theme sits under the This device heading', (tester) async {
      _tallWindow(tester);
      await _pumpSection(tester, _signedInRepo(), SettingsSection.appearance);
      final thisDevice = find
          .ancestor(
            of: find.byWidgetPredicate(
              (w) => w is SectionHeader && w.title == 'This device',
            ),
            matching: find.byType(Column),
          )
          .first;
      final theme = find.bySemanticsIdentifier(SemanticsIds.themeSelect);
      expect(find.descendant(of: thisDevice, matching: theme), findsOneWidget);
      // The heading says the scope, so the row neither prints it nor
      // holds it in a tip.
      expect(
        find.descendant(
          of: find.ancestor(of: theme, matching: find.byType(WaxSettingRow)),
          matching: find.byType(WaxInfoTip),
        ),
        findsNothing,
      );
      expect(find.textContaining('your other devices keep'), findsNothing);
    });

    testWidgets('the language row says the choice follows the account', (
      tester,
    ) async {
      _tallWindow(tester);
      await _pumpSection(tester, _signedInRepo(), SettingsSection.appearance);
      expect(infoTipHolding('Follows your account'), findsOneWidget);
    });

    testWidgets('theme and language are rows, not groups heading one row of '
        'the same name', (tester) async {
      _tallWindow(tester);
      await _pumpSection(tester, _signedInRepo(), SettingsSection.appearance);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SectionHeader &&
              (w.title == 'Theme' || w.title == 'Language'),
        ),
        findsNothing,
      );
    });

    testWidgets('a theme chosen before the move is adopted, once', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()..prefs = const Prefs(theme: ThemePref.oled);
      await _pumpSection(tester, repo, SettingsSection.appearance);

      // Without this, everybody who deliberately chose dark or OLED is
      // silently flipped to follow-the-system by the upgrade.
      final container = _container(tester, SettingsSectionScreen);
      expect(container.read(themeSettingProvider), ThemePref.oled);
      expect(container.read(waxThemeSpecProvider).oled, isTrue);

      // Once: a device that has since chosen for itself keeps its own
      // answer whatever the account still holds.
      await _show(tester, find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.themeSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      expect(container.read(themeSettingProvider), ThemePref.light);

      container.invalidate(prefsControllerProvider);
      await container.read(prefsControllerProvider.future);
      await tester.pumpAndSettle();
      expect(container.read(themeSettingProvider), ThemePref.light);
    });

    testWidgets('the language picker stores a tag and clears it again', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      final picker = find.bySemanticsIdentifier(
        SemanticsIds.setting('language'),
      );
      WaxChoice<String> language() =>
          tester.widget(find.byWidgetPredicate((w) => w is WaxChoice<String>));
      await _show(tester, picker);
      // Nothing stored reads as the system, which is what the interface
      // is doing: a null option is not offered, because the menu answers
      // null when it is dismissed and the two would be one answer.
      expect(language().value, 'system');

      await tester.tap(picker);
      await tester.pumpAndSettle();
      // By its endonym, not by a translation: somebody looking for
      // Spanish on an English screen is looking for "Espanol".
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.settingOption('language', 'es'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.prefs.locale, 'es');
      expect(language().value, 'es');

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.settingOption('language', 'system'),
        ),
      );
      await tester.pumpAndSettle();
      // Cleared rather than stored as a word: the document carries no
      // locale at all when the system decides.
      expect(repo.prefs.locale, isNull);
      expect(repo.putPrefsCalls.last.locale, isNull);
    });

    testWidgets('a stored regional tag reads as the language it resolves '
        'to', (tester) async {
      _tallWindow(tester);
      // `es-MX` is a legal tag another client can write, and this app
      // answers it with Spanish - so the row must say Spanish rather
      // than claim the system is deciding.
      final repo = _signedInRepo()..prefs = const Prefs(locale: 'es-MX');
      await _pumpSection(tester, repo, SettingsSection.appearance);

      expect(
        tester
            .widget<WaxChoice<String>>(
              find.byWidgetPredicate((w) => w is WaxChoice<String>),
            )
            .value,
        'es',
      );
    });

    testWidgets('a stored language the build does not have follows the '
        'system', (tester) async {
      _tallWindow(tester);
      // French resolves only by falling back, so the interface is
      // English and no option stands for what is stored.
      final repo = _signedInRepo()..prefs = const Prefs(locale: 'fr');
      await _pumpSection(tester, repo, SettingsSection.appearance);

      expect(
        tester
            .widget<WaxChoice<String>>(
              find.byWidgetPredicate((w) => w is WaxChoice<String>),
            )
            .value,
        'system',
      );
    });

    test('every locale the app offers names itself', () {
      // The picker falls back to the raw tag for a language it has no
      // endonym for, which is a row reading "es". This is what keeps
      // that fallback unreachable.
      for (final locale in appSupportedLocales) {
        expect(
          languageEndonyms[locale.toLanguageTag()],
          isNotNull,
          reason:
              '${locale.toLanguageTag()} is offered by the picker and would '
              'be drawn as its own tag',
        );
      }
    });

    testWidgets('density and artwork size are this device, not the account', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

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

    testWidgets('the artwork glow starts on and reaches the theme spec', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      final container = _container(tester, SettingsSectionScreen);
      expect(container.read(waxThemeSpecProvider).artworkGlow, isTrue);

      final glow = find.bySemanticsIdentifier(
        SemanticsIds.setting('artwork-glow'),
      );
      await _show(tester, glow);
      await tester.tap(glow);
      await tester.pumpAndSettle();

      // The spec is what the theme is built from, so this is the whole
      // chain: a switch that flipped a provider nothing read would look
      // identical on screen.
      expect(container.read(waxThemeSpecProvider).artworkGlow, isFalse);
      expect(repo.putPrefsCalls, isEmpty);
    });

    testWidgets('card captions are only offered where a pointer can ask for '
        'them back', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      final container = _container(tester, SettingsSectionScreen);
      WaxChoice<WaxCaptionMode> picker() => tester.widget(
        find.byWidgetPredicate((w) => w is WaxChoice<WaxCaptionMode>),
      );

      // No mouse: the choice is refused outright rather than stored and
      // then ignored, which is the only honest answer on a screen with
      // no way to bring a hidden caption back.
      expect(picker().onChanged, isNull);
      expect(find.text('Always shown: hiding needs a pointer'), findsOneWidget);

      // A mouse is what makes the choice offerable at all.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      _withPointerHighlight();
      await tester.pumpAndSettle();
      expect(picker().onChanged, isNotNull);

      final captions = find.bySemanticsIdentifier(
        SemanticsIds.setting('card-captions'),
      );
      await _show(tester, captions);
      await tester.tap(captions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('On hover').last);
      await tester.pumpAndSettle();

      // Stored on the device, and reaching the theme the cards are
      // built from - the whole chain, not just the provider.
      expect(container.read(cardCaptionsProvider), WaxCaptionMode.onHover);
      expect(
        container.read(waxThemeSpecProvider).captions,
        WaxCaptionMode.onHover,
      );
      expect(repo.putPrefsCalls, isEmpty);
    });

    testWidgets('a tap on a touchscreen laptop does not deny its mouse', (
      tester,
    ) async {
      // Two questions, two answers. `mouseIsConnected` says whether the
      // machine has a pointer, and the highlight mode says whether
      // hovering is live this second; a touch-down flips the second and
      // not the first. Answering the first with the second greyed the
      // row and told a machine with a mouse on it that it had none.
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _mountSection(tester, repo, SettingsSection.appearance);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      _withTouchHighlight();
      await tester.pumpAndSettle();

      final container = _container(tester, SettingsSectionScreen);
      container.read(cardCaptionsProvider.notifier).set(WaxCaptionMode.onHover);
      await tester.pumpAndSettle();

      WaxChoice<WaxCaptionMode> picker() => tester.widget(
        find.byWidgetPredicate((w) => w is WaxChoice<WaxCaptionMode>),
      );
      // Touch mode, which is where a tap leaves a hybrid machine.
      expect(picker().onChanged, isNotNull);
      expect(find.text('The lines under a cover in a grid'), findsNothing);
      // The cards still show their names, because a finger cannot hover.
      expect(
        container.read(waxThemeSpecProvider).captions,
        WaxCaptionMode.always,
      );

      _withPointerHighlight();
      await tester.pumpAndSettle();
      expect(
        container.read(waxThemeSpecProvider).captions,
        WaxCaptionMode.onHover,
      );
    });

    testWidgets('a stored hover choice is still ignored without a pointer', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.appearance);

      // The device that stored it grew a mouse and lost it again, which
      // the picker cannot prevent. What the cards are built from is
      // resolved every time rather than trusted to the stored value.
      _withTouchHighlight();
      final container = _container(tester, SettingsSectionScreen);
      container.read(cardCaptionsProvider.notifier).set(WaxCaptionMode.onHover);
      await tester.pumpAndSettle();

      expect(container.read(cardCaptionsProvider), WaxCaptionMode.onHover);
      expect(
        container.read(waxThemeSpecProvider).captions,
        WaxCaptionMode.always,
      );
    });
  });

  group('a preference that will not save', () {
    // The controls here are drawn from the stored document and hold
    // nothing of their own, so a refused write moves nothing on screen.
    // Without a sentence that is a tap that did nothing.
    testWidgets('says so instead of doing nothing quietly', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo()
        ..putPrefsError = const WaxDeckApiException(
          code: 'read-only',
          message: 'the library is read-only',
        );
      await _pumpSection(tester, repo, SettingsSection.playback);

      final leveling = find.bySemanticsIdentifier(
        SemanticsIds.setting('replay-gain'),
      );
      await _show(tester, leveling);
      await tester.tap(leveling);
      await tester.pumpAndSettle();

      // The client's own sentence for the code, not the server's line.
      expect(
        shellMessageText(raisedMessage(tester)),
        'The server or this library is read-only right now, so nothing can be changed.',
      );
      // Nothing was stored, and nothing on the row moved either: the
      // sentence is the only thing that happened.
      expect(repo.prefs.replayGain, isNull);
      expect(repo.putPrefsCalls, isEmpty);
    });

    testWidgets('reports a refused language the same way', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo()
        ..putPrefsError = const WaxDeckApiException(
          code: 'read-only',
          message: 'the library is read-only',
        );
      await _pumpSection(tester, repo, SettingsSection.appearance);

      final picker = find.bySemanticsIdentifier(
        SemanticsIds.setting('language'),
      );
      await _show(tester, picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.settingOption('language', 'es'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        shellMessageText(raisedMessage(tester)),
        'The server or this library is read-only right now, so nothing can be changed.',
      );
      expect(repo.prefs.locale, isNull);
    });
  });

  group('the playback section', () {
    testWidgets('the skip intervals store and read back', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await _pumpSection(tester, repo, SettingsSection.playback);

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
      await _pumpSection(tester, repo, SettingsSection.playback);

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
      await _pumpSection(tester, repo, SettingsSection.integrations);

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

  group('the library and accessibility sections', () {
    UserAccount account(LibraryAccess access) => UserAccount(
      id: _user.id,
      username: _user.username,
      roles: const ['user'],
      createdAt: DateTime.utc(2026, 7, 15),
      libraryAccess: access,
    );

    testWidgets('an account that sees everything says so in a label', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()
        ..usersById[_user.id] = account(const LibraryAccess(mode: 'all'));
      await _pumpSection(tester, repo, SettingsSection.library);
      expect(find.text('What I can see'), findsOneWidget);
      expect(find.text('All libraries'), findsOneWidget);
      expect(find.textContaining('You can see'), findsNothing);
    });

    testWidgets('the Access group holds its place while the grant loads', (
      tester,
    ) async {
      _tallWindow(tester);
      final gate = Completer<void>();
      final repo = _signedInRepo()
        ..usersById[_user.id] = account(const LibraryAccess(mode: 'all'))
        ..getUserGate = gate;
      await _pumpSection(tester, repo, SettingsSection.library);
      // Loading: the row is drawn, its answer is not yet.
      expect(find.text('What I can see'), findsOneWidget);
      expect(find.text('All libraries'), findsNothing);
      expect(find.text('Could not read your access'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('All libraries'), findsOneWidget);
    });

    // An administrator changing this very grant re-reads the session,
    // which re-reads the account: the last answer stands meanwhile, and
    // stands through a re-read that fails.
    testWidgets('the Access row keeps its answer through a re-read', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()
        ..usersById[_user.id] = account(const LibraryAccess(mode: 'all'));
      final container = await _pumpSection(
        tester,
        repo,
        SettingsSection.library,
      );
      expect(find.text('All libraries'), findsOneWidget);

      final gate = Completer<void>();
      repo
        ..getUserGate = gate
        ..sessionState = SessionState(authenticated: true, user: _user);
      final auth = container.read(authControllerProvider.notifier);
      await auth.refreshSession();
      await tester.pump();
      expect(find.text('All libraries'), findsOneWidget);
      expect(find.text('Could not read your access'), findsNothing);

      // The account read now fails: not-found.
      repo.usersById.remove(_user.id);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('All libraries'), findsOneWidget);
      expect(find.text('Could not read your access'), findsNothing);
    });

    testWidgets('identify-uploads says who it asks under the switch', (
      tester,
    ) async {
      _tallWindow(tester);
      await _pumpSection(tester, _signedInRepo(), SettingsSection.library);
      // A third party contacted is a consequence the title hides, so it
      // is printed rather than held behind a tip.
      const sentence = 'Asks MusicBrainz; off files uploads unreviewed';
      expect(find.text(sentence), findsOneWidget);
      expect(infoTipHolding(sentence), findsNothing);
    });

    testWidgets('a restricted account is told how many libraries', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()
        ..usersById[_user.id] = account(
          const LibraryAccess(mode: 'some', libraryPids: ['lb-1', 'lb-2']),
        );
      await _pumpSection(tester, repo, SettingsSection.library);
      expect(find.text('What I can see'), findsOneWidget);
      // The answer sits where the all-access one does: the row's value.
      expect(find.text('2 libraries'), findsOneWidget);
      expect(find.textContaining('You can see'), findsNothing);
    });

    testWidgets('an access read that fails says so under the row', (
      tester,
    ) async {
      _tallWindow(tester);
      // No such account in the fake: the read fails with not-found.
      await _pumpSection(tester, _signedInRepo(), SettingsSection.library);
      expect(find.text('What I can see'), findsOneWidget);
      expect(find.text('Could not read your access'), findsOneWidget);
      expect(find.text('All libraries'), findsNothing);
    });

    testWidgets('accessibility is the motion row alone', (tester) async {
      _tallWindow(tester);
      await _pumpSection(
        tester,
        _signedInRepo(),
        SettingsSection.accessibility,
      );
      expect(find.text('Reduce motion'), findsOneWidget);
      expect(find.text('Screen readers'), findsNothing);
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
      await _pumpSection(tester, repo, SettingsSection.server);

      expect(find.text('Administrators only'), findsOneWidget);
    });

    testWidgets('waits for the session before it refuses anyone', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()..getSessionGate = Completer<void>();
      await _mountSection(tester, repo, SettingsSection.server);
      await tester.pump();

      expect(find.text('Administrators only'), findsNothing);
      expect(find.byType(SkeletonShapes), findsOneWidget);

      repo.getSessionGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Administrators only'), findsNothing);
      expect(find.byType(SkeletonShapes), findsNothing);
    });
  });
}
