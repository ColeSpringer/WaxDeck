import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _primary = <WaxDestination>[
  WaxDestination(name: 'home', label: 'Home', glyph: WaxIcons.home),
  WaxDestination(
    name: 'music',
    label: 'Music',
    glyph: WaxIcons.music,
    children: <WaxDestination>[
      WaxDestination(
        name: 'artists',
        label: 'Artists',
        glyph: WaxIcons.artists,
      ),
      WaxDestination(name: 'albums', label: 'Albums', glyph: WaxIcons.albums),
    ],
  ),
  WaxDestination(name: 'podcasts', label: 'Podcasts', glyph: WaxIcons.podcasts),
  WaxDestination(name: 'radio', label: 'Radio', glyph: WaxIcons.radio),
];

const _settings = WaxDestination(
  name: 'settings',
  label: 'Settings',
  glyph: WaxIcons.settings,
);

const _secondary = <WaxNavEntry>[
  WaxNavLink(_settings),
  WaxNavGroup(
    name: 'curation',
    label: 'Curation',
    glyph: WaxIcons.admin,
    children: <WaxDestination>[
      WaxDestination(
        name: 'review',
        label: 'Review queue',
        glyph: WaxIcons.admin,
      ),
      WaxDestination(name: 'users', label: 'Users', glyph: WaxIcons.admin),
    ],
  ),
];

const _account = WaxAccount(
  name: 'sam',
  actions: <WaxAccountAction>[
    WaxAccountAction(name: 'signOut', label: 'Sign out', glyph: WaxIcons.close),
  ],
);

/// Pumps the frame at [size], which is what picks the chrome: every
/// adaptive decision keys off the window's own width.
Future<List<String>> _pumpFrame(
  WidgetTester tester, {
  required Size size,
  String selected = 'home',
  double textScale = 1,
  bool collapsed = false,
  VoidCallback? onToggleCollapsed,
  WaxAccount? account,
  ValueChanged<String>? onAccountAction,
  Widget content = const Center(child: Text('content pane')),
}) async {
  final selections = <String>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: WaxShellFrame(
        destinations: _primary,
        secondary: _secondary,
        selected: selected,
        collapsed: collapsed,
        onToggleCollapsed: onToggleCollapsed,
        onSelect: selections.add,
        account: account,
        onAccountAction: onAccountAction ?? (account == null ? null : (_) {}),
        content: content,
      ),
    ),
  );
  return selections;
}

/// Mounts the account control on its own, which is where it lives below
/// rail width: in a screen's top app bar rather than in the shell's
/// chrome. Returns the destinations it reported.
Future<List<String>> _pumpButton(
  WidgetTester tester, {
  WaxAccount account = _account,
  List<WaxNavEntry> entries = const <WaxNavEntry>[],
  ValueChanged<String>? onAction,
}) async {
  final selections = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            WaxAccountButton(
              account: account,
              onAction: onAction ?? (_) {},
              entries: entries,
              onSelect: selections.add,
            ),
          ],
        ),
      ),
    ),
  );
  return selections;
}

void main() {
  group('shell frame', () {
    // The four size classes, and the one piece of chrome each is
    // supposed to show. A window that shows two of them (or none) is the
    // failure this pins.
    const cases = <String, (Size, Type)>{
      'compact': (Size(400, 800), WaxNavBar),
      'medium': (Size(700, 900), WaxNavRail),
      'expanded': (Size(1000, 900), WaxSidebar),
      'wide': (Size(1400, 900), WaxSidebar),
    };

    for (final entry in cases.entries) {
      final (size, chrome) = entry.value;
      testWidgets('${entry.key} shows ${chrome.toString()} and nothing else', (
        tester,
      ) async {
        await _pumpFrame(tester, size: size);

        expect(find.byType(chrome), findsOneWidget);
        for (final other in <Type>{WaxNavBar, WaxNavRail, WaxSidebar}) {
          if (other == chrome) continue;
          expect(find.byType(other), findsNothing, reason: '$other at $size');
        }
        expect(find.text('content pane'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'the panel docks where it fits and overlays where it does not',
      (tester) async {
        // Wide seats the panel beside the content; expanded lays it over
        // the content's trailing edge, which still leaves a usable page
        // underneath; narrower than that there is no room for either, and
        // the frame drops it rather than squeezing the content to nothing.
        for (final size in <Size>[
          const Size(400, 800),
          const Size(700, 900),
          const Size(1000, 900),
          const Size(1400, 900),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildWaxTheme(),
              home: WaxShellFrame(
                destinations: _primary,
                selected: 'home',
                onSelect: (_) {},
                panel: const Text('queue panel'),
                content: const SizedBox.expand(
                  key: Key('pane'),
                  child: Text('content pane'),
                ),
              ),
            ),
          );
          expect(
            find.text('queue panel'),
            size.width >= 840 ? findsOneWidget : findsNothing,
            reason: 'the panel needs a sidebar-width window, not ${size.width}',
          );
          if (size.width < 840) continue;
          // Docked, the content pane stops where the panel starts; laid
          // over, the pane still runs to the window's edge and the panel
          // is on top of its last 360 px.
          expect(
            tester.getRect(find.byKey(const Key('pane'))).right,
            size.width >= 1200 ? size.width - 360 : size.width,
            reason: 'the pane is the wrong width at ${size.width}',
          );
        }
      },
    );
  });

  group('destinations', () {
    for (final entry in <String, Size>{
      'tabs': const Size(400, 800),
      'the rail': const Size(700, 900),
      'the sidebar': const Size(1000, 900),
    }.entries) {
      testWidgets('${entry.key} report the destination that was tapped', (
        tester,
      ) async {
        final selections = await _pumpFrame(tester, size: entry.value);

        await tester.tap(find.bySemanticsLabel('Podcasts'));
        await tester.pump();

        expect(selections, <String>['podcasts']);
      });

      testWidgets('${entry.key} announce which destination is active', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pumpFrame(tester, size: entry.value, selected: 'radio');

        expect(
          tester.getSemantics(find.bySemanticsLabel('Radio')),
          matchesSemantics(
            label: 'Radio',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
            // The chrome is keyboard-reachable, and on web this flag is
            // what becomes a tabindex.
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Home')),
          matchesSemantics(
            label: 'Home',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasSelectedState: true,
            hasTapAction: true,
            // The chrome is keyboard-reachable, and on web this flag is
            // what becomes a tabindex.
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
        semantics.dispose();
      });

      testWidgets('${entry.key} take focus from the platform and activate', (
        tester,
      ) async {
        // Web turns the node's `focusable` flag into a `tabindex` and
        // asks the framework to focus it when the browser does; without
        // the flag the whole chrome had no tabindex and no keyboard
        // could reach it at all. Focus that does not lead to activation
        // is only half of that, so both halves are pinned here.
        final semantics = tester.ensureSemantics();
        final selections = await _pumpFrame(tester, size: entry.value);

        final node = tester.getSemantics(find.bySemanticsLabel('Radio'));
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.focus),
          isTrue,
        );
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.focus,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(selections, <String>['radio']);
        semantics.dispose();
      });

      testWidgets('${entry.key} answer a screen reader tap', (tester) async {
        // The suite clicks the semantics node and assistive tech sends it
        // a tap action, so a node that announces "button" and handles
        // nothing is a dead control on both.
        final semantics = tester.ensureSemantics();
        final selections = await _pumpFrame(tester, size: entry.value);

        final node = tester.getSemantics(find.bySemanticsLabel('Music'));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pump();

        expect(selections, <String>['music']);
        semantics.dispose();
      });
    }

    testWidgets('the navigation region is named for assistive tech', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpFrame(tester, size: const Size(1000, 900));
      expect(find.bySemanticsLabel('Main navigation'), findsOneWidget);
      semantics.dispose();
    });

    // The chrome renders on every size class; whether it is *exposed*
    // depends on what the content pane contains. A routed pane carries a
    // ModalBarrier per route, and a barrier wraps itself in
    // BlockSemantics, which drops the semantics of everything painted
    // before it in the same container - the sidebar and the rail, both
    // painted ahead of the pane. The frame gives the content a boundary
    // of its own so that walk stops there; without it the chrome renders
    // and announces nothing, which is invisible to a golden and to every
    // test that pumps a bare pane.
    for (final entry in <String, Size>{
      'tabs': const Size(400, 800),
      'the rail': const Size(700, 900),
      'the sidebar': const Size(1000, 900),
    }.entries) {
      testWidgets('${entry.key} stay exposed behind a routed pane', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildWaxTheme(),
            home: WaxShellFrame(
              destinations: _primary,
              secondary: _secondary,
              selected: 'home',
              onSelect: (_) {},
              banners: const <Widget>[
                WaxBanner(message: 'Reconnecting to the server.'),
              ],
              bottom: const Text('deck bar'),
              content: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('content pane')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('content pane'), findsOneWidget);
        for (final destination in _primary) {
          expect(
            find.bySemanticsLabel(destination.label),
            findsOneWidget,
            reason: '${destination.label} on ${entry.key}',
          );
        }
        // Everything else the frame holds is in the same walk: a banner
        // is painted before the pane, and it is the pane's own boundary
        // that keeps the barriers inside it from erasing the banner.
        expect(
          find.bySemanticsLabel('Reconnecting to the server.'),
          findsOneWidget,
          reason: 'the banner on ${entry.key}',
        );
        expect(
          find.bySemanticsLabel('deck bar'),
          findsOneWidget,
          reason: 'the deck bar slot on ${entry.key}',
        );
        semantics.dispose();
      });
    }
  });

  group('bottom tabs', () {
    testWidgets('drop their labels past 1.5 but keep their names', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(400, 800));
      expect(find.text('Podcasts'), findsOneWidget);

      await _pumpFrame(tester, size: const Size(400, 800), textScale: 2);

      // The label is gone from the paint, and the destination is still
      // reachable by its accessible name: reflow, not truncation.
      expect(find.text('Podcasts'), findsNothing);
      expect(find.bySemanticsLabel('Podcasts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hold their touch targets at every text scale', (tester) async {
      for (final scale in <double>[1, 1.5, 2]) {
        await _pumpFrame(tester, size: const Size(400, 800), textScale: scale);
        final tab = tester.getRect(find.bySemanticsLabel('Home'));
        expect(
          tab.height,
          greaterThanOrEqualTo(WaxSpace.touchTarget),
          reason: 'tab height at scale $scale',
        );
        expect(tester.takeException(), isNull, reason: 'overflow at $scale');
      }
    });
  });

  group('a hub holds the selection for its indexes', () {
    // Every form but an open sidebar section draws the hub and not its
    // indexes, so an index has to light the hub or the chrome lights
    // nothing at all - which is what a phone standing on Artists did.
    for (final entry in <String, Size>{
      'tabs': const Size(400, 800),
      'the rail': const Size(700, 900),
    }.entries) {
      testWidgets('${entry.key} light the hub', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpFrame(tester, size: entry.value, selected: 'artists');

        expect(
          tester.getSemantics(find.bySemanticsLabel('Music')),
          isSemantics(isSelected: true),
        );
        // And nothing else does.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Home')),
          isSemantics(isSelected: false),
        );
        semantics.dispose();
      });
    }

    testWidgets('a collapsed sidebar lights the hub', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        selected: 'artists',
        collapsed: true,
        onToggleCollapsed: () {},
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Music')),
        isSemantics(isSelected: true),
      );
      semantics.dispose();
    });
  });

  group('sidebar', () {
    testWidgets('opens the group holding the active destination', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(1000, 900), selected: 'users');

      // Arriving at a grouped location by URL must never hide where you
      // are: the group discloses itself.
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('keeps a closed group closed until it is opened', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(1000, 900));
      expect(find.text('Users'), findsNothing);

      await tester.tap(find.text('Curation'));
      await tester.pumpAndSettle();

      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('closes a group from inside the group', (tester) async {
      // The auto-open is a default, not a floor: a visitor standing in a
      // curation area must still be able to fold the section away.
      await _pumpFrame(tester, size: const Size(1000, 900), selected: 'users');
      expect(find.text('Users'), findsOneWidget);

      await tester.tap(find.text('Curation'));
      await tester.pumpAndSettle();
      expect(find.text('Users'), findsNothing);

      await tester.tap(find.text('Curation'));
      await tester.pumpAndSettle();
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('collapses to a rail and flattens its groups', (tester) async {
      var toggled = 0;
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        collapsed: true,
        onToggleCollapsed: () => toggled++,
      );

      // No labels are drawn at rail width, so every entry - group
      // children included - has to be reachable as an icon, or it is
      // reachable nowhere.
      expect(find.text('Podcasts'), findsNothing);
      for (final name in <String>['Home', 'Podcasts', 'Settings', 'Users']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }

      await tester.tap(find.bySemanticsLabel('Expand sidebar'));
      await tester.pump();
      expect(toggled, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers no collapse control without a handler', (tester) async {
      await _pumpFrame(tester, size: const Size(1000, 900));
      expect(find.bySemanticsLabel('Collapse sidebar'), findsNothing);
    });

    testWidgets('an open section lights the index, not the hub', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(1000, 900), selected: 'albums');

      expect(
        tester.getSemantics(find.bySemanticsLabel('Albums')),
        isSemantics(isSelected: true),
      );
      // Two lit rows for one location would read as two places.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Music')),
        isSemantics(isSelected: false),
      );
    });

    testWidgets('a domain hub discloses its indexes and still navigates', (
      tester,
    ) async {
      final selections = await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        selected: 'home',
      );
      expect(find.text('Artists'), findsNothing);

      // The two controls do different things and are found separately:
      // the chevron opens the section, the row goes to the hub.
      await tester.tap(find.bySemanticsLabel('Expand Music'));
      await tester.pumpAndSettle();
      expect(find.text('Artists'), findsOneWidget);
      expect(selections, isEmpty);

      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      expect(selections, <String>['music']);

      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(selections, <String>['music', 'artists']);
    });

    testWidgets('a hub opens itself when it or an index is where you are', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(1000, 900), selected: 'albums');
      // Arriving at an index by URL must not hide it inside a closed
      // section.
      expect(find.text('Albums'), findsOneWidget);

      // And the auto-open is a default, not a floor.
      await tester.tap(find.bySemanticsLabel('Collapse Music'));
      await tester.pumpAndSettle();
      expect(find.text('Albums'), findsNothing);
    });

    testWidgets('drops sub-destinations at rail width, not the hub', (
      tester,
    ) async {
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        collapsed: true,
        onToggleCollapsed: () {},
      );

      // Unlike a group's children, these are reachable one tap further
      // on - the hub they belong to lists them - so the rail spends its
      // icons on destinations that are reachable nowhere else.
      expect(find.bySemanticsLabel('Music'), findsOneWidget);
      expect(find.bySemanticsLabel('Artists'), findsNothing);
      expect(find.bySemanticsLabel('Expand Music'), findsNothing);
    });
  });

  group('account menu', () {
    testWidgets('the compact frame draws none: the app bar has it', (
      tester,
    ) async {
      // The tab bar carries the domains and nothing else. The avatar is
      // in the screen's own top app bar at this width, which is where
      // the layout system puts it and which the frame owns none of - so
      // a frame handed an account below rail width simply does not draw
      // one, and its `secondary` travels with the caller's control.
      await _pumpFrame(tester, size: const Size(400, 800), account: _account);
      expect(find.bySemanticsLabel('Account'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('carries the destinations it is handed', (tester) async {
      // What the app-bar control does at compact, where this menu is the
      // only route to everything that is not a domain.
      final selections = await _pumpButton(tester, entries: _secondary);
      expect(find.text('Settings'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();

      expect(find.text('sam'), findsOneWidget, reason: 'who is signed in');
      expect(find.text('Users'), findsOneWidget, reason: 'a grouped area');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(selections, <String>['settings']);
    });

    testWidgets('reports an action apart from a destination', (tester) async {
      final actions = <String>[];
      final selections = await _pumpButton(
        tester,
        entries: _secondary,
        onAction: actions.add,
      );

      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(actions, <String>['signOut']);
      expect(selections, isEmpty, reason: 'signing out is not a place');
    });

    for (final entry in <String, Size>{
      'the rail': const Size(700, 900),
      'the sidebar': const Size(1000, 900),
    }.entries) {
      // The count is what makes this real: naming a menu row by its
      // widget type cannot work, because the entries are generic over a
      // private type that no test can spell. So the assertion is that
      // opening the menu adds no second copy of a destination the chrome
      // is already responsible for - which fails the moment the frame
      // starts handing it `secondary` at these widths.
      final onChrome = entry.key == 'the sidebar' ? 1 : 0;
      testWidgets('lists no destination beside ${entry.key}', (tester) async {
        await _pumpFrame(tester, size: entry.value, account: _account);
        expect(find.text('Settings'), findsExactly(onChrome));

        await tester.tap(find.bySemanticsLabel('Account'));
        await tester.pumpAndSettle();

        expect(find.text('sam'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
        expect(
          find.text('Settings'),
          findsExactly(onChrome),
          reason: 'the menu repeated a destination the chrome lists',
        );
        expect(find.text('Users'), findsNothing);
      });
    }

    testWidgets('is absent from the chrome when nobody is signed in', (
      tester,
    ) async {
      await _pumpFrame(tester, size: const Size(700, 900));
      expect(find.bySemanticsLabel('Account'), findsNothing);
    });

    testWidgets('draws a whole grapheme, and only a usable one', (
      tester,
    ) async {
      // Three rules in one place. The initial is a grapheme cluster, not
      // a code unit, so a combining mark survives; it is drawn only when
      // it is a letter or a digit, the rule `ArtworkImage` already uses,
      // so punctuation does not end up on the disc; and an emoji is not
      // a letter, which matters twice over here because the app bundles
      // no emoji face and would draw tofu.
      for (final entry in <String, String?>{
        'sam': 'S',
        // Decomposed and spelled out: the cluster is the letter plus
        // its combining acute, and a code unit would drop the accent.
        'e\u0301lan': 'E\u0301',
        '_sam': null,
        '...': null,
        '': null,
        '\u{1F3B5} nightjar': null,
      }.entries) {
        await _pumpButton(tester, account: WaxAccount(name: entry.key));

        // The control carries its own "Account" label besides, so the
        // glyph is what tells the two branches apart rather than the
        // absence of text.
        final glyph = find.descendant(
          of: find.bySemanticsLabel('Account'),
          matching: find.byType(WaxIcon),
        );
        final initial = entry.value;
        if (initial == null) {
          expect(
            glyph,
            findsOneWidget,
            reason: '"${entry.key}" should fall back to the glyph',
          );
        } else {
          expect(find.text(initial), findsOneWidget, reason: entry.key);
          expect(glyph, findsNothing, reason: entry.key);
        }
        expect(tester.takeException(), isNull, reason: entry.key);
      }
    });

    testWidgets('stays inside the system insets on a short window', (
      tester,
    ) async {
      // At rail width the trigger sits at the very foot of the rail, so
      // the menu has to open upward and clear the gesture bar. Flutter's
      // own layout deflates by MediaQuery.padding; this pins that the
      // frame hands it a padding to work with rather than swallowing it.
      const inset = EdgeInsets.only(top: 24, bottom: 48);
      tester.view.physicalSize = const Size(700, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = FakeViewPadding(
        top: inset.top,
        bottom: inset.bottom,
      );
      tester.view.padding = FakeViewPadding(
        top: inset.top,
        bottom: inset.bottom,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: WaxShellFrame(
            destinations: _primary,
            secondary: _secondary,
            selected: 'home',
            onSelect: (_) {},
            account: _account,
            onAccountAction: (_) {},
            content: const Center(child: Text('content pane')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(menu.top, greaterThanOrEqualTo(inset.top));
      expect(menu.bottom, lessThanOrEqualTo(640 - inset.bottom));
      // And the last row is still reachable inside what is left.
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks with the collapse toggle at rail width', (
      tester,
    ) async {
      // The footer pairs them side by side at full width and has one
      // column to work with when collapsed.
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        collapsed: true,
        onToggleCollapsed: () {},
        account: _account,
      );

      expect(find.bySemanticsLabel('Account'), findsOneWidget);
      expect(find.bySemanticsLabel('Expand sidebar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('skip link', () {
    testWidgets('comes before the navigation for a screen reader', (
      tester,
    ) async {
      // The point of the control: the chrome is painted first at these
      // widths, so a screen reader walks every sidebar row before it
      // reaches the page. Traversal order is what the browser's own tab
      // order follows on web, and it is decided by geometry unless both
      // siblings carry a sort key.
      final semantics = tester.ensureSemantics();
      await _pumpFrame(tester, size: const Size(1000, 900));

      final tree = tester
          .getSemantics(find.byType(WaxShellFrame))
          .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder);
      expect(
        tree.indexOf('Skip to content'),
        lessThan(tree.indexOf('Main navigation')),
        reason: 'the link has to be the first thing on the page',
      );
      semantics.dispose();
    });

    testWidgets('hands focus to the content', (tester) async {
      final semantics = tester.ensureSemantics();
      final inContent = FocusNode(debugLabel: 'in-content');
      addTearDown(inContent.dispose);
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        content: Center(
          child: Focus(
            focusNode: inContent,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      expect(inContent.hasFocus, isFalse);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Skip to content'),
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();

      expect(inContent.hasFocus, isTrue);
      semantics.dispose();
    });

    testWidgets('lets the content take a tap under its unfocused box', (
      tester,
    ) async {
      // The link is painted last and is roughly 140 by 48, which at rail
      // width overhangs the content pane by half its width - exactly
      // where a screen's back button sits. Ignoring pointers from inside
      // the detector was not enough: its outermost render object is an
      // opaque `MouseRegion`, which answers the hit test for the whole
      // box whatever sits beneath it.
      var backs = 0;
      await _pumpFrame(
        tester,
        size: const Size(700, 900),
        content: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => backs++,
            ),
            title: const Text('a screen'),
          ),
          body: const Text('content pane'),
        ),
      );

      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final link = tester.getRect(find.byType(WaxShellFrame));
      expect(back.left, lessThan(142), reason: 'the overlap under test');
      expect(link.left, 0);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(backs, 1);
    });

    testWidgets('reports one pixel while it is collapsed', (tester) async {
      // The half of that problem Flutter's own hit test cannot answer.
      // On web the semantics tree is real DOM, and an element carrying a
      // tap action takes the browser's click for its whole rect whatever
      // an IgnorePointer above it says - so the rect is what has to
      // shrink. At the leading corner the old full-size box sat over the
      // sidebar header, where the search field is: visible, and
      // unclickable with a mouse.
      final semantics = tester.ensureSemantics();
      await _pumpFrame(tester, size: const Size(1000, 900));

      final collapsed = tester.getRect(
        find.bySemanticsLabel('Skip to content'),
      );
      expect(collapsed.size, const Size(1, 1));
      // Not zero: a zero-size render object leaves the semantics tree,
      // which takes the link out of the tab order.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Skip to content')).rect,
        isNot(Rect.zero),
      );

      // Tabbed to, it is a real control again, at a size somebody can
      // read and click. This is the whole trade: the link is a pixel
      // until a keyboard asks for it, and a pill from then on.
      for (var press = 0; press < 12; press++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (tester.getRect(find.bySemanticsLabel('Skip to content')).width >
            100) {
          break;
        }
      }
      expect(
        tester.getRect(find.bySemanticsLabel('Skip to content')).width,
        greaterThan(100),
      );
      semantics.dispose();
    });

    testWidgets('lands on the content region when the page has no controls', (
      tester,
    ) async {
      // A page still loading its skeleton has nothing to focus. Focus
      // goes to the region itself rather than nowhere, which is what a
      // `<main tabindex="-1">` does on the web: the visitor is inside the
      // content and the next tab starts there.
      final semantics = tester.ensureSemantics();
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        content: const Center(child: Text('loading')),
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel('Skip to content'),
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'shell-content');
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('leaves the chrome reachable by tab from the content', (
      tester,
    ) async {
      // The content pane is a focus scope of its own so the link has
      // somewhere to send focus, and a scope's default is a closed loop:
      // left that way it would trap tab traversal inside the page and put
      // the whole sidebar out of a keyboard's reach.
      await _pumpFrame(
        tester,
        size: const Size(1000, 900),
        content: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: TextButton(onPressed: () {}, child: const Text('in page')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var reachedChrome = false;
      for (var press = 0; press < 8 && !reachedChrome; press++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          reachedChrome = element.widget is WaxSidebar;
          return !reachedChrome;
        });
      }
      expect(reachedChrome, isTrue, reason: 'tab never left the page');
    });

    testWidgets('is not drawn where the content already comes first', (
      tester,
    ) async {
      // Compact paints the content, then the deck bar, then the tabs. A
      // link that skips forward to what is already first is noise.
      await _pumpFrame(tester, size: const Size(400, 800));
      expect(find.text('Skip to content'), findsNothing);
    });
  });

  group('rail overflow', () {
    testWidgets('lists the secondary entries under their group', (
      tester,
    ) async {
      final selections = await _pumpFrame(tester, size: const Size(700, 900));

      // The rail has room for the domains and nothing else, so the
      // secondary entries have to be behind this control.
      expect(find.text('Settings'), findsNothing);
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();

      final settings = tester.getRect(find.text('Settings'));
      final header = tester.getRect(find.text('Curation'));
      final users = tester.getRect(find.text('Users'));
      expect(settings.top, lessThan(header.top));
      expect(
        header.top,
        lessThan(users.top),
        reason: 'children follow their group',
      );

      await tester.tap(find.text('Users'));
      await tester.pumpAndSettle();
      expect(selections, <String>['users']);
    });
  });
}
