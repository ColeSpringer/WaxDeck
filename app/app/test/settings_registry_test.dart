import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

const _admin = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  username: 'admin',
  roles: ['admin'],
);

void main() {
  group('the registry', () {
    test('every setting has a unique id', () {
      final seen = <String, String>{};
      for (final entry in settingsRegistry) {
        final previous = seen[entry.id];
        expect(
          previous,
          isNull,
          reason:
              '"${entry.id}" is registered twice ($previous, '
              '${entry.section.title})',
        );
        seen[entry.id] = entry.section.title;
      }
    });

    test('every section has at least one setting behind it', () {
      for (final section in SettingsSection.values) {
        expect(
          settingsRegistry.any((e) => e.section == section),
          isTrue,
          reason:
              '${section.title} is listed on the settings home and search '
              'can find nothing in it',
        );
      }
    });

    test('keywords are lower case, since the query is folded and they '
        'are not', () {
      for (final entry in settingsRegistry) {
        for (final keyword in entry.keywords) {
          expect(
            keyword,
            keyword.toLowerCase(),
            reason: '${entry.id} carries "$keyword", which no query matches',
          );
        }
      }
    });

    test('a setting in an admin-only section is admin-only itself', () {
      for (final entry in settingsRegistry) {
        if (!entry.section.adminOnly) continue;
        expect(
          entry.adminOnly,
          isTrue,
          reason:
              '${entry.id} is in ${entry.section.title} and would be offered '
              'to a member by search',
        );
      }
    });
  });

  group('search', () {
    test('a title match outranks a keyword match', () {
      final hits = searchSettings('speed', isAdmin: true, isNative: true);
      expect(hits.first.title, contains('speed'));
    });

    test('an empty query answers nothing rather than everything', () {
      expect(searchSettings('  ', isAdmin: true, isNative: true), isEmpty);
    });

    test('a member is offered nothing they cannot open', () {
      final hits = searchSettings('server', isAdmin: false, isNative: true);
      expect(hits.every((e) => !e.adminOnly && !e.section.adminOnly), isTrue);
    });

    test('the web build is offered nothing it does not have', () {
      final hits = searchSettings('wifi', isAdmin: true, isNative: false);
      expect(hits, isEmpty);
      expect(searchSettings('wifi', isAdmin: true, isNative: true), isNotEmpty);
    });

    test('the match is case-insensitive in both directions', () {
      expect(
        searchSettings(
          'CROSSFADE',
          isAdmin: true,
          isNative: true,
        ).map((e) => e.id),
        contains('crossfade'),
      );
    });
  });

  // The half a registry cannot check itself: that every entry names a
  // control some section actually draws. Registered-and-undrawn is the
  // failure mode that matters, because search offers a row, the row opens
  // a section, and the setting is not in it.
  testWidgets('every registered setting is drawn by its section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      sessions: [testSession('se-1', current: true)],
    );

    for (final section in SettingsSection.values) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
          ],
          child: routedHost(SettingsSectionScreen(section: section)),
        ),
      );
      await tester.pumpAndSettle();

      for (final entry in settingsRegistry.where((e) => e.section == section)) {
        // Native-only settings are drawn on this platform: the widget
        // test runs on the VM, where `kIsWeb` is false.
        expect(
          find.bySemanticsIdentifier(entry.semanticsId),
          findsWidgets,
          reason:
              '"${entry.title}" is registered under ${section.title} and '
              'that section draws no control for it',
        );
      }
    }
  });
}
