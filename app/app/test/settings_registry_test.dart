import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
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
  group('the fold both searches share', () {
    test('an accent is folded whichever way it is spelled', () {
      // Precomposed and decomposed, which is the same word twice. A
      // query folded one way against a haystack folded the other
      // matches nothing.
      expect(foldForSearch('Pódcast'), 'podcast');
      expect(foldForSearch('Po\u0301dcast'), 'podcast');
      expect(foldForSearch('Reproducción'), 'reproduccion');
      expect(foldForSearch('Reproduccio\u0301n'), 'reproduccion');
      expect(foldForSearch('año'), 'ano');
    });

    test('a script it has no folding for is carried through', () {
      // Not dropped and not mangled: an unfoldable name still has to be
      // findable by typing it.
      expect(foldForSearch('Ραδιό'), 'ραδιό');
      expect(foldForSearch('東京'), '東京');
    });
  });

  late AppLocalizations en;
  late AppLocalizations es;
  late List<SettingEntry> entries;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
    entries = settingsEntries(en);
  });

  group('the registry', () {
    test('every setting has a unique id', () {
      final seen = <String, String>{};
      for (final entry in entries) {
        final previous = seen[entry.id];
        expect(
          previous,
          isNull,
          reason:
              '"${entry.id}" is registered twice ($previous, '
              '${entry.section.titleOf(en)})',
        );
        seen[entry.id] = entry.section.titleOf(en);
      }
    });

    test('every section has at least one setting behind it', () {
      for (final section in SettingsSection.values) {
        expect(
          entries.any((e) => e.section == section),
          isTrue,
          reason:
              '${section.titleOf(en)} is listed on the settings home and search '
              'can find nothing in it',
        );
      }
    });

    test('a setting in an admin-only section is admin-only itself', () {
      for (final entry in entries) {
        if (!entry.section.adminOnly) continue;
        expect(
          entry.adminOnly,
          isTrue,
          reason:
              '${entry.id} is in ${entry.section.titleOf(en)} and would be offered '
              'to a member by search',
        );
      }
    });
  });

  group('search', () {
    test('a title match outranks a keyword match', () {
      final hits = searchSettings(
        'speed',
        l10n: en,
        isAdmin: true,
        isNative: true,
        isDesktop: true,
      );
      expect(hits.first.title, contains('speed'));
    });

    test('an empty query answers nothing rather than everything', () {
      expect(
        searchSettings(
          '  ',
          l10n: en,
          isAdmin: true,
          isNative: true,
          isDesktop: true,
        ),
        isEmpty,
      );
    });

    test('a member is offered nothing they cannot open', () {
      final hits = searchSettings(
        'server',
        l10n: en,
        isAdmin: false,
        isNative: true,
        isDesktop: true,
      );
      expect(hits.every((e) => !e.adminOnly && !e.section.adminOnly), isTrue);
    });

    test('the web build is offered nothing it does not have', () {
      final hits = searchSettings(
        'wifi',
        l10n: en,
        isAdmin: true,
        isNative: false,
        isDesktop: true,
      );
      expect(hits, isEmpty);
      expect(
        searchSettings(
          'wifi',
          l10n: en,
          isAdmin: true,
          isNative: true,
          isDesktop: true,
        ),
        isNotEmpty,
      );
    });

    test('a phone is offered nothing only a desktop can do', () {
      expect(
        searchSettings(
          'idle',
          l10n: en,
          isAdmin: true,
          isNative: true,
          isDesktop: false,
        ),
        isEmpty,
      );
      expect(
        searchSettings(
          'idle',
          l10n: en,
          isAdmin: true,
          isNative: true,
          isDesktop: true,
        ).map((e) => e.id),
        contains('visualizer-idle'),
      );
    });

    test('an accent is not something the listener has to type', () {
      // The Spanish copy spells it "pódcast", and the accent is the
      // language's rather than the searcher's: a settings search that
      // answers only the accented spelling is one a Spanish reader
      // gives up on. Title and keyword both, since either can carry it.
      final hits = searchSettings(
        'podcast',
        l10n: es,
        isAdmin: true,
        isNative: true,
        isDesktop: true,
      ).map((e) => e.id);
      expect(hits, contains('podcast-speed'));
      expect(hits, contains('skip-back'));

      // And the accented spelling still finds them, which is the half a
      // fold done in one direction only would lose.
      expect(
        searchSettings(
          'pódcast',
          l10n: es,
          isAdmin: true,
          isNative: true,
          isDesktop: true,
        ).map((e) => e.id),
        contains('podcast-speed'),
      );
    });

    test('the match is case-insensitive in both directions', () {
      expect(
        searchSettings(
          'CROSSFADE',
          l10n: en,
          isAdmin: true,
          isNative: true,
          isDesktop: true,
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
            // The harness pins the target platform to Android, so a
            // desktop-only row would be absent and this check would
            // read that as a registered setting nothing draws. Standing
            // on a desktop is what makes the assertion cover every
            // entry rather than most of them.
            desktopProvider.overrideWithValue(true),
          ],
          child: routedHost(SettingsSectionScreen(section: section)),
        ),
      );
      await tester.pumpAndSettle();

      for (final entry in entries.where((e) => e.section == section)) {
        // Native-only settings are drawn on this platform: the widget
        // test runs on the VM, where `kIsWeb` is false.
        expect(
          find.bySemanticsIdentifier(entry.semanticsId),
          findsWidgets,
          reason:
              '"${entry.title}" is registered under ${section.titleOf(en)} and '
              'that section draws no control for it',
        );
      }
    }
  });
}
