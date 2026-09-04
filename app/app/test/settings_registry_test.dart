import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/app.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/setting_anchor.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/router.dart';
import 'package:waxdeck/src/shell/routes.dart';
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

      for (final entry in entries.where(
        // Native-only settings are drawn on this platform: the widget
        // test runs on the VM, where `kIsWeb` is false. Which is also
        // why a web-only row cannot be checked from here at all - it is
        // drawn by the browser suite, where the same assertion runs.
        (e) => e.section == section && !e.webOnly,
      )) {
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

  // Drawn is not the same as reachable. A search result names the setting
  // it found and the section it opens has to take the reader to that row;
  // landing at the top of a long section reads as "search found nothing"
  // for everything past the first screenful, which is what this bug was.
  //
  // Every entry, not a sample: the anchor is per row, so a row nobody
  // wrapped is one setting that silently keeps the old behaviour.
  testWidgets('an arriving setting id scrolls its row into view', (
    tester,
  ) async {
    // Short enough that most rows start below the fold, so "it scrolled"
    // is a fact rather than an accident of a tall viewport.
    tester.view.physicalSize = const Size(1000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeRepository(
      sessionState: const SessionState(authenticated: true, user: _admin),
      sessions: [testSession('se-1', current: true)],
    );

    // Web-only rows are not drawn on the VM; the browser suite anchors
    // them.
    for (final entry in entries.where((e) => !e.webOnly)) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            credentialStoreProvider.overrideWithValue(
              InMemoryCredentialStore(),
            ),
            desktopProvider.overrideWithValue(true),
          ],
          child: routedHost(
            SettingsSectionScreen(section: entry.section, setting: entry.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.bySemanticsIdentifier(entry.semanticsId).first;
      // The wrapper by name, not just the effect: a row near the top of
      // a section is on screen whether or not anybody wrapped it, and
      // the id is spelled twice - once in the registry and once here -
      // with nothing but this to hold the two together.
      expect(
        find.ancestor(
          of: row,
          matching: find.byWidgetPredicate(
            (w) => w is SettingAnchor && w.id == entry.id,
          ),
        ),
        findsOneWidget,
        reason:
            '"${entry.title}" has no SettingAnchor carrying its own id, so '
            'arriving with ?setting=${entry.id} lands nowhere near it',
      );
      final screen =
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(row);
      expect(
        rect.top >= screen.top - 0.5 && rect.bottom <= screen.bottom + 0.5,
        isTrue,
        reason:
            '"${entry.title}" is only partly on screen after arriving with its '
            'own id (row $rect, screen $screen)',
      );
    }
  });

  // The first scroll is right about where the row was when it ran, and
  // wrong the moment anything above it fills in. Several sections draw
  // rows behind a request - sessions, app passwords, connected accounts -
  // so a reader taken to the right place and then pushed off it is back
  // to the bug the anchor exists for.
  testWidgets('a row pushed down while it is landing is followed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final filling = ValueNotifier(false);
    addTearDown(filling.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The section's own shape: one eagerly built column inside one
          // sliver, so a row scrolled out of view is still mounted and
          // still able to answer.
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: WantedSetting(
                  id: 'wanted',
                  child: Column(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: filling,
                        builder: (context, filled, child) =>
                            SizedBox(height: filled ? 2000 : 100),
                      ),
                      const SettingAnchor(
                        id: 'wanted',
                        child: SizedBox(height: 40, child: Text('the row')),
                      ),
                      const SizedBox(height: 2000),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // The landing scroll, run out.
    await tester.pump(const Duration(milliseconds: 400));
    final screen = Offset.zero & const Size(400, 300);
    expect(tester.getRect(find.text('the row')).top, lessThan(screen.bottom));

    // Now the group above it answers, and the row is 1900 pixels down.
    filling.value = true;
    await tester.pump();
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text('the row'));
    expect(
      rect.top >= screen.top && rect.bottom <= screen.bottom,
      isTrue,
      reason: 'the row was left off screen after the section filled in ($rect)',
    );
  });

  // Anchors carry no key, so a section that draws a row conditionally
  // hands one anchor's State to a different anchor by position. A latch
  // left behind from the row that used to be there would make that
  // setting the one that silently scrolls nowhere, and nothing about the
  // section would look wrong.
  testWidgets('an anchor reused for a different row lands for the new one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final wanted = ValueNotifier<String?>('first');
    final drawFirst = ValueNotifier(true);
    final scroll = ScrollController();
    addTearDown(() {
      wanted.dispose();
      drawFirst.dispose();
      scroll.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: ValueListenableBuilder<String?>(
                  valueListenable: wanted,
                  builder: (context, id, child) =>
                      WantedSetting(id: id, child: child!),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: drawFirst,
                    builder: (context, first, child) => Column(
                      children: [
                        const SizedBox(height: 2000),
                        // Both anchors sit at the same index in turn, which
                        // is the whole point: dropping the first hands its
                        // State to the second.
                        if (first)
                          const SettingAnchor(
                            id: 'first',
                            child: SizedBox(height: 40, child: Text('first')),
                          )
                        else
                          const SettingAnchor(
                            id: 'second',
                            child: SizedBox(height: 40, child: Text('second')),
                          ),
                        const SizedBox(height: 2000),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    drawFirst.value = false;
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pump();

    wanted.value = 'second';
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text('second'));
    expect(
      rect.top >= 0 && rect.bottom <= 300,
      isTrue,
      reason: 'the reused anchor never landed on the row it now holds ($rect)',
    );
  });

  // Reduced motion holds the mark flat and then drops it. The drop has
  // to survive the release path too: a row unmarked mid-hold resets the
  // controller to zero, which must read as unmarked, not full-strength.
  testWidgets('reduced motion drops the wash when the row is released', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wanted = ValueNotifier<String?>('wanted');
    addTearDown(wanted.dispose);

    bool washOn() => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(SettingAnchor),
            matching: find.byType(DecoratedBox),
          ),
        )
        .isNotEmpty;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: wanted,
                      builder: (context, id, child) =>
                          WantedSetting(id: id, child: child!),
                      child: const SettingAnchor(
                        id: 'wanted',
                        child: SizedBox(height: 40, child: Text('the row')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(washOn(), isTrue, reason: 'the mark holds while wanted');

    wanted.value = null;
    await tester.pump();
    expect(washOn(), isFalse, reason: 'released is unmarked');
  });

  // go_router keys a page by its path, and `?setting=` is neither a path
  // nor a path parameter, so a second search into the same section reuses
  // the screen that is already up - and with it every anchor's state. A
  // row that latched on the first arrival and never let go would take the
  // reader nowhere on the second.
  //
  // Driven through one router rather than three mounts: remounting builds
  // a fresh tree, which is the one thing that cannot happen here and the
  // reason this needs saying at all.
  testWidgets('the same row lands again after the location leaves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(
          FakeRepository(
            sessionState: const SessionState(authenticated: true, user: _admin),
          ),
        ),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        desktopProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaxDeckApp(),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(routerProvider);
    Future<void> goTo(String setting) async {
      router.go(
        WaxRoute.settingsSection(SettingsSection.playback, setting: setting),
      );
      await tester.pumpAndSettle();
    }

    final viewport =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    // A row far enough down the Playback section to start below the fold.
    final row = find.bySemanticsIdentifier('setting-replay-gain').first;

    await goTo('replay-gain');
    expect(tester.getRect(row).overlaps(viewport), isTrue);

    // Away, and back to the same row. One router throughout, so the
    // screen and its anchors are the same objects each time.
    await goTo('skip-back');
    await goTo('replay-gain');
    expect(
      tester.getRect(row).overlaps(viewport),
      isTrue,
      reason: 'the second arrival at the same row scrolled nowhere',
    );
  });

  // User input arriving in a URL. An id from a build that named its
  // settings differently, or one somebody typed, lands at the top of the
  // section and says nothing - the way an anchor nobody declared does on
  // the web.
  testWidgets('an unknown setting id lands at the top and refuses nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(
            FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: _admin,
              ),
            ),
          ),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          desktopProvider.overrideWithValue(true),
        ],
        child: routedHost(
          const SettingsSectionScreen(
            section: SettingsSection.playback,
            setting: 'no-such-setting',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The section is up, showing its first rows, with nothing said about
    // the id that named nothing.
    expect(find.bySemanticsIdentifier('setting-skip-back'), findsWidgets);
  });
}
