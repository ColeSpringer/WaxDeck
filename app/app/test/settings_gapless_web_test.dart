@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/setting_anchor.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// The web half of the registry's drawn-and-anchored assertion.
///
/// `settings_registry_test.dart` holds every entry to it on the VM and
/// skips the web-only ones, because `kIsWeb` is false there and a row
/// gated on it is simply absent. This is where those rows are checked,
/// and it is the only place they can be: a registered setting no
/// section draws is a search result that opens onto nothing, and the
/// gapless switch is registered.
void main() {
  final en = AppLocalizationsEn();

  testWidgets('every web-only setting is drawn and anchored', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final webOnly = settingsEntries(en).where((e) => e.webOnly).toList();
    expect(
      webOnly,
      isNotEmpty,
      reason: 'the registry has no web-only entries left to check here',
    );

    for (final entry in webOnly) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(
              FakeRepository(
                sessionState: const SessionState(
                  authenticated: true,
                  user: WaxDeckUser(
                    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
                    username: 'listener',
                    roles: ['user'],
                  ),
                ),
              ),
            ),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(
            SettingsSectionScreen(section: entry.section, setting: entry.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.bySemanticsIdentifier(entry.semanticsId);
      expect(
        row,
        findsWidgets,
        reason:
            '"${entry.title}" is registered and no section draws it in a '
            'browser',
      );
      expect(
        find.ancestor(
          of: row.first,
          matching: find.byWidgetPredicate(
            (w) => w is SettingAnchor && w.id == entry.id,
          ),
        ),
        findsOneWidget,
        reason:
            '"${entry.title}" has no SettingAnchor carrying its own id, so '
            'arriving with ?setting=${entry.id} lands nowhere near it',
      );
    }
  });
}
