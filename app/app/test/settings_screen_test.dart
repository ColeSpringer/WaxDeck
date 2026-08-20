import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart'
    show WaxButton, WaxCaptionMode, WaxChoice, WaxTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
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

/// [locale] reaches `routedHost`, which installs the delegates; pass it
/// only where the copy is what the test is about, since every other
/// assertion in this file reads English.
Widget _host(
  FakeRepository repo,
  Widget screen, {
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
  ],
  child: routedHost(screen, locale: locale),
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
      await tester.pumpWidget(
        _host(
          _signedInRepo(),
          const SettingsScreen(),
          locale: const Locale('es'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Apariencia'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(tester.takeException(), isNull);
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

    testWidgets('renaming a device sends the trimmed name', (tester) async {
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

    testWidgets('an empty name cannot be saved', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo(
        sessions: [testSession('se-2', deviceName: 'Pixel 9')],
      );
      await tester.pumpWidget(_section(repo, SettingsSection.account));
      await tester.pumpAndSettle();

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
    test('an unset theme follows the system', () async {
      final repo = _signedInRepo();
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // Before the document loads, and after it loads with nothing
      // stored, the platform decides. Only a stored choice departs.
      expect(container.read(themeModeProvider), ThemeMode.system);
      await container.read(prefsControllerProvider.future);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('an unset theme shows System in the picker', (tester) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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

    testWidgets('the row says the choice stays on this device', (tester) async {
      _tallWindow(tester);
      await tester.pumpWidget(
        _section(_signedInRepo(), SettingsSection.appearance),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Set on this device; your other devices keep their own'),
        findsOneWidget,
      );
    });

    testWidgets('a theme chosen before the move is adopted, once', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo()..prefs = const Prefs(theme: ThemePref.oled);
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      for (final locale in waxSupportedLocales) {
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

    testWidgets('the artwork glow starts on and reaches the theme spec', (
      tester,
    ) async {
      _tallWindow(tester);
      final repo = _signedInRepo();
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

      final container = _container(tester, SettingsSectionScreen);
      WaxChoice<WaxCaptionMode> picker() => tester.widget(
        find.byWidgetPredicate((w) => w is WaxChoice<WaxCaptionMode>),
      );

      // No mouse: the choice is refused outright rather than stored and
      // then ignored, which is the only honest answer on a screen with
      // no way to bring a hidden caption back.
      expect(picker().onChanged, isNull);
      expect(
        find.text(
          'Always shown: hiding them needs a pointer to bring '
          'them back',
        ),
        findsOneWidget,
      );

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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
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
      expect(find.text('The lines under a cover in a grid'), findsOneWidget);
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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_section(repo, SettingsSection.playback));
      await tester.pumpAndSettle();

      final leveling = find.bySemanticsIdentifier(
        SemanticsIds.setting('replay-gain'),
      );
      await _show(tester, leveling);
      await tester.tap(leveling);
      await tester.pumpAndSettle();

      // The client's own sentence for the code, not the server's line.
      expect(
        find.text(
          'The library is read-only right now, so nothing can be changed.',
        ),
        findsOneWidget,
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
      await tester.pumpWidget(_section(repo, SettingsSection.appearance));
      await tester.pumpAndSettle();

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
        find.text(
          'The library is read-only right now, so nothing can be changed.',
        ),
        findsOneWidget,
      );
      expect(repo.prefs.locale, isNull);
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
