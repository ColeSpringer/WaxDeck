import 'dart:math' as math;
import 'dart:ui' as ui;

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

/// The window's insets as the engine reports them: [view] the view
/// padding, a keyboard [keyboard] high, and the padding what the keyboard
/// leaves of the view padding, side by side.
void _engineInsets(
  WidgetTester tester,
  FakeViewPadding view, {
  double keyboard = 0,
}) {
  tester.view
    ..viewPadding = view
    ..viewInsets = FakeViewPadding(bottom: keyboard)
    ..padding = FakeViewPadding(
      left: view.left,
      top: view.top,
      right: view.right,
      bottom: math.max(0, view.bottom - keyboard),
    );
}

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
  TextDirection direction = TextDirection.ltr,
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
        child: Directionality(textDirection: direction, child: child!),
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
      // Three rules in one place, all `monogramInitials`. The initial is
      // a grapheme cluster, not a code unit, so a combining mark
      // survives; punctuation and emoji are skipped to the first letter
      // or digit rather than drawn, because the app bundles no emoji
      // face and would draw tofu; and a name with no letter or digit
      // anywhere gets the glyph.
      for (final entry in <String, String?>{
        'sam': 'S',
        // Decomposed and spelled out: the cluster is the letter plus
        // its combining acute, and a code unit would drop the accent.
        'e\u0301lan': 'E\u0301',
        '_sam': 'S',
        '...': null,
        '': null,
        '\u{1F3B5} nightjar': 'N',
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

    for (final direction in TextDirection.values) {
      testWidgets('${direction.name}: sits inside the insets of the corner '
          'it is in', (tester) async {
        const size = Size(1000, 900);
        final semantics = tester.ensureSemantics();
        final link = find.bySemanticsLabel('Skip to content');
        await _pumpFrame(tester, size: size, direction: direction);
        final bare = tester.getRect(link);

        tester.view
          ..padding = const FakeViewPadding(top: 24, left: 40, right: 30)
          ..viewPadding = const FakeViewPadding(top: 24, left: 40, right: 30);
        await _pumpFrame(tester, size: size, direction: direction);
        final inset = tester.getRect(link);
        expect(inset.top, bare.top + 24, reason: 'the top');
        if (direction == TextDirection.ltr) {
          expect(inset.left, bare.left + 40, reason: 'the start side');
        } else {
          expect(inset.right, bare.right - 30, reason: 'the start side');
        }
        semantics.dispose();
      });
    }

    testWidgets('is not drawn where the content already comes first', (
      tester,
    ) async {
      // Compact paints the content, then the deck bar, then the tabs. A
      // link that skips forward to what is already first is noise.
      await _pumpFrame(tester, size: const Size(400, 800));
      expect(find.text('Skip to content'), findsNothing);
    });
  });

  group("banners and the window's insets", () {
    const first = 'Reconnecting to the server.';
    const second = 'The library is read-only.';
    final page = find.byKey(const Key('page body'));

    /// The frame at [size] under [padding], around a page with a compact
    /// bar, showing [banners].
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      required FakeViewPadding padding,
      List<Widget> banners = const <Widget>[],
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = padding
        ..viewPadding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: WaxShellFrame(
            destinations: _primary,
            secondary: _secondary,
            selected: 'home',
            onSelect: (_) {},
            banners: banners,
            content: const WaxScaffold(
              title: 'Page',
              largeTitle: false,
              body: SizedBox(key: Key('page body'), height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, Size>{
      'tabs': const Size(400, 800),
      'the rail': const Size(700, 900),
      'the sidebar': const Size(1000, 900),
    }.entries) {
      testWidgets('with ${entry.key}, banners take the top inset and the '
          'page bar sits under them', (tester) async {
        const top = 24.0;
        await pump(
          tester,
          entry.value,
          padding: const FakeViewPadding(top: top),
          banners: const <Widget>[
            WaxBanner(message: first),
            WaxBanner(message: second),
          ],
        );

        final text = tester.getRect(find.text(first, findRichText: true));
        expect(text.top, greaterThanOrEqualTo(top), reason: 'first banner');
        final upper = tester.getRect(find.byType(WaxBanner).first);
        final lower = tester.getRect(find.byType(WaxBanner).last);
        expect(lower.top, upper.bottom, reason: 'second banner');
        expect(
          tester.getTopLeft(page).dy,
          lower.bottom + kToolbarHeight,
          reason: 'the inset is taken once',
        );
      });

      testWidgets('with ${entry.key} and no banners, the page bar takes the '
          'top inset itself', (tester) async {
        await pump(
          tester,
          entry.value,
          padding: const FakeViewPadding(top: 24),
        );
        expect(tester.getTopLeft(page).dy, 24 + kToolbarHeight);
      });
    }

    testWidgets('a banner keeps inside the side insets', (tester) async {
      await pump(
        tester,
        const Size(400, 800),
        padding: const FakeViewPadding(top: 24, left: 60, right: 60),
        banners: const <Widget>[WaxBanner(message: first)],
      );

      final glyph = tester.getRect(
        find.descendant(
          of: find.byType(WaxBanner),
          matching: find.byType(WaxIcon),
        ),
      );
      final text = tester.getRect(find.text(first, findRichText: true));
      expect(glyph.left, greaterThanOrEqualTo(60));
      expect(text.right, lessThanOrEqualTo(400 - 60));
    });
  });

  group("the window's side insets are taken once", () {
    const inset = 40.0;
    const message = 'Reconnecting to the server.';
    final title = find.text('Page');
    final action = find.byKey(const Key('page action'));
    final panelBody = find.byKey(const Key('panel body'));
    final bannerGlyph = find.descendant(
      of: find.byType(WaxBanner),
      matching: find.byType(WaxIcon),
    );

    /// The frame at [size] in [direction] under [padding], around a page
    /// with a compact bar and one action, with a banner and a side panel
    /// when asked for.
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      required TextDirection direction,
      FakeViewPadding padding = FakeViewPadding.zero,
      bool banner = false,
      bool panel = false,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = padding
        ..viewPadding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          builder: (context, child) =>
              Directionality(textDirection: direction, child: child!),
          home: WaxShellFrame(
            destinations: _primary,
            secondary: _secondary,
            selected: 'home',
            onSelect: (_) {},
            banners: <Widget>[if (banner) const WaxBanner(message: message)],
            panel: panel
                ? const WaxSidePanel(
                    title: 'Queue',
                    child: SizedBox.expand(key: Key('panel body')),
                  )
                : null,
            content: const WaxScaffold(
              title: 'Page',
              largeTitle: false,
              actions: <Widget>[
                SizedBox(key: Key('page action'), width: 10, height: 10),
              ],
              body: SizedBox(height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// How far [inner] sits inside [outer]'s start edge (its trailing edge
    /// when [after] is true) in [direction].
    double gap(
      Rect inner,
      Rect outer,
      TextDirection direction, {
      bool after = false,
    }) {
      final ltr = direction == TextDirection.ltr;
      return ltr != after ? inner.left - outer.left : outer.right - inner.right;
    }

    /// How far [inner] sits past [edge]'s end edge in [direction].
    double past(Rect inner, Rect edge, TextDirection direction) =>
        direction == TextDirection.ltr
        ? inner.left - edge.right
        : edge.left - inner.right;

    FakeViewPadding startSide(TextDirection direction) =>
        direction == TextDirection.ltr
        ? const FakeViewPadding(left: inset)
        : const FakeViewPadding(right: inset);

    FakeViewPadding endSide(TextDirection direction) =>
        direction == TextDirection.ltr
        ? const FakeViewPadding(right: inset)
        : const FakeViewPadding(left: inset);

    for (final direction in TextDirection.values) {
      for (final entry in <String, (Size, Type)>{
        'the rail': (const Size(700, 900), WaxNavRail),
        'the sidebar': (const Size(1000, 900), WaxSidebar),
      }.entries) {
        final (size, type) = entry.value;
        final chrome = find.byType(type);
        final chromeGlyph = find
            .descendant(of: chrome, matching: find.byType(WaxIcon))
            .first;
        final window = Offset.zero & size;

        testWidgets('${direction.name}: ${entry.key} takes the start inset '
            'and the page starts at its edge', (tester) async {
          await pump(tester, size, direction: direction, banner: true);
          final titleAt = past(
            tester.getRect(title),
            tester.getRect(chrome),
            direction,
          );
          final bannerAt = past(
            tester.getRect(bannerGlyph),
            tester.getRect(chrome),
            direction,
          );
          final glyphAt = gap(tester.getRect(chromeGlyph), window, direction);

          await pump(
            tester,
            size,
            direction: direction,
            padding: startSide(direction),
            banner: true,
          );
          final edge = tester.getRect(chrome);
          expect(
            gap(tester.getRect(chromeGlyph), window, direction),
            glyphAt + inset,
            reason: 'the chrome clears the inset',
          );
          expect(
            past(tester.getRect(title), edge, direction),
            titleAt,
            reason: 'the page bar',
          );
          expect(
            past(tester.getRect(bannerGlyph), edge, direction),
            bannerAt,
            reason: 'the banner',
          );
        });
      }

      testWidgets('${direction.name}: a docked panel takes the end inset and '
          'the page is not indented by it', (tester) async {
        const size = Size(1300, 900);
        final window = Offset.zero & size;
        final panel = find.byType(WaxSidePanel);
        await pump(tester, size, direction: direction, panel: true);
        final actionAt = past(
          tester.getRect(panel),
          tester.getRect(action),
          direction,
        );
        final body = tester.getRect(panelBody);

        await pump(
          tester,
          size,
          direction: direction,
          padding: endSide(direction),
          panel: true,
        );
        expect(
          gap(tester.getRect(panelBody), window, direction, after: true),
          gap(body, window, direction, after: true) + inset,
          reason: 'the panel clears the inset',
        );
        expect(
          tester.getRect(panelBody).width,
          body.width,
          reason: 'the panel keeps its width',
        );
        expect(
          past(tester.getRect(panel), tester.getRect(action), direction),
          actionAt,
          reason: 'the page bar',
        );
      });

      testWidgets('${direction.name}: a panel over the page clears the end '
          'inset', (tester) async {
        const size = Size(1000, 900);
        final window = Offset.zero & size;
        await pump(tester, size, direction: direction, panel: true);
        final body = tester.getRect(panelBody);

        await pump(
          tester,
          size,
          direction: direction,
          padding: endSide(direction),
          panel: true,
        );
        expect(
          gap(tester.getRect(panelBody), window, direction, after: true),
          gap(body, window, direction, after: true) + inset,
        );
        expect(tester.getRect(panelBody).width, body.width);
      });
    }

    testWidgets('on a phone the page keeps both side insets', (tester) async {
      const size = Size(400, 800);
      await pump(tester, size, direction: TextDirection.ltr);
      final titleLeft = tester.getRect(title).left;
      final actionRight = tester.getRect(action).right;

      await pump(
        tester,
        size,
        direction: TextDirection.ltr,
        padding: const FakeViewPadding(left: inset, right: inset),
      );
      expect(tester.getRect(title).left, titleLeft + inset);
      expect(tester.getRect(action).right, actionRight - inset);
    });
  });

  group("the window's bottom inset is taken once", () {
    const inset = 30.0;
    final deck = find.byType(DeckBarOffer);
    final deckArt = find.descendant(
      of: deck,
      matching: find.byType(ArtworkImage),
    );
    final panelBody = find.byKey(const Key('panel body'));
    late double paneBottom;

    /// The frame at [size] under a bottom [padding], with the deck bar's
    /// offer in the bottom slot when [deckBar] and a side panel when
    /// [panel].
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      required bool deckBar,
      double padding = 0,
      bool panel = false,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = FakeViewPadding(bottom: padding)
        ..viewPadding = FakeViewPadding(bottom: padding);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: WaxShellFrame(
            destinations: _primary,
            secondary: _secondary,
            selected: 'home',
            onSelect: (_) {},
            onToggleCollapsed: () {},
            bottom: deckBar
                ? DeckBarOffer(
                    title: 'Kelp Line',
                    onResume: () {},
                    onDismiss: () {},
                  )
                : null,
            panel: panel
                ? const WaxSidePanel(
                    title: 'Queue',
                    child: SizedBox.expand(key: Key('panel body')),
                  )
                : null,
            // Read where the page is handed it: its scaffold takes it from
            // there, and its body is handed none.
            content: Builder(
              builder: (context) {
                paneBottom = MediaQuery.paddingOf(context).bottom;
                return const WaxScaffold(
                  title: 'Page',
                  body: SizedBox(height: 100),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, (Size, Type)>{
      'the rail': (const Size(700, 900), WaxNavRail),
      'the sidebar': (const Size(1000, 900), WaxSidebar),
    }.entries) {
      final (size, type) = entry.value;
      final foot = find
          .descendant(of: find.byType(type), matching: find.byType(WaxIcon))
          .last;

      testWidgets('with ${entry.key}, a deck bar takes it and the chrome and '
          'the page are not lifted', (tester) async {
        await pump(tester, size, deckBar: true);
        final artAbove = size.height - tester.getRect(deckArt).bottom;
        final footAbove =
            tester.getRect(deck).top - tester.getRect(foot).bottom;

        await pump(tester, size, deckBar: true, padding: inset);
        expect(
          tester.getRect(deck).bottom,
          size.height,
          reason: "the bar's surface reaches the window's foot",
        );
        expect(
          size.height - tester.getRect(deckArt).bottom,
          artAbove + inset,
          reason: 'the bar clears the inset',
        );
        expect(
          tester.getRect(deck).top - tester.getRect(foot).bottom,
          footAbove,
          reason: 'the chrome',
        );
        expect(paneBottom, 0, reason: 'the page');
      });

      testWidgets('with ${entry.key} and nothing in the bottom slot, the '
          'chrome and the page take it', (tester) async {
        await pump(tester, size, deckBar: false);
        final footAbove = size.height - tester.getRect(foot).bottom;

        await pump(tester, size, deckBar: false, padding: inset);
        expect(size.height - tester.getRect(foot).bottom, footAbove + inset);
        expect(paneBottom, inset);
      });
    }

    for (final entry in <String, Size>{
      'docked': const Size(1300, 900),
      'over the page': const Size(1000, 900),
    }.entries) {
      testWidgets('a panel ${entry.key} stands on the deck bar, and takes the '
          'inset with nothing there', (tester) async {
        await pump(
          tester,
          entry.value,
          deckBar: true,
          padding: inset,
          panel: true,
        );
        expect(tester.getRect(panelBody).bottom, tester.getRect(deck).top);

        await pump(
          tester,
          entry.value,
          deckBar: false,
          padding: inset,
          panel: true,
        );
        expect(tester.getRect(panelBody).bottom, entry.value.height - inset);
      });
    }

    testWidgets('on a phone the tabs take it and the deck bar does not', (
      tester,
    ) async {
      const size = Size(400, 800);
      await pump(tester, size, deckBar: true);
      final height = tester.getRect(deck).height;

      await pump(tester, size, deckBar: true, padding: inset);
      final tabs = tester.getRect(find.byType(WaxNavBar));
      expect(tabs.bottom, size.height);
      expect(tester.getRect(deck).bottom, tabs.top);
      expect(tester.getRect(deck).height, height);
      expect(paneBottom, 0, reason: 'the page: the tabs have taken it');
    });
  });

  group('the keyboard is taken once', () {
    const inset = 34.0;
    final body = find.byType(CustomScrollView);
    final deck = find.byType(DeckBarOffer);
    final tabs = find.byType(WaxNavBar);
    final floating = find.byKey(const Key('floating'));
    late double paneViewPadding;

    /// The frame at [size] over a gesture bar [inset] high with a keyboard
    /// [keyboard] high, around a page whose body its Scaffold lifts clear
    /// of the keyboard and which floats a button, with the deck bar's
    /// offer in the bottom slot when [deckBar].
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      required double keyboard,
      bool deckBar = false,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      _engineInsets(
        tester,
        const FakeViewPadding(bottom: inset),
        keyboard: keyboard,
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
            bottom: deckBar
                ? DeckBarOffer(
                    title: 'Kelp Line',
                    onResume: () {},
                    onDismiss: () {},
                  )
                : null,
            content: Builder(
              builder: (context) {
                paneViewPadding = MediaQuery.viewPaddingOf(context).bottom;
                return const WaxScaffold(
                  title: 'Page',
                  body: SizedBox(height: 100),
                  floating: SizedBox(
                    key: Key('floating'),
                    width: 40,
                    height: 40,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, (Size, bool)>{
      'on a phone with the tabs': (const Size(400, 800), false),
      'on a phone with the tabs and the deck bar': (const Size(400, 800), true),
      'beside the sidebar with the deck bar': (const Size(1000, 900), true),
    }.entries) {
      final (size, deckBar) = entry.value;

      testWidgets('${entry.key}, the page rests on the top of a keyboard '
          'taller than what is below it', (tester) async {
        await pump(tester, size, keyboard: 300, deckBar: deckBar);
        expect(tester.getRect(body).bottom, size.height - 300);
      });
    }

    testWidgets('a keyboard shorter than what is below the page leaves it '
        'where it was', (tester) async {
      const size = Size(400, 800);
      await pump(tester, size, keyboard: 0, deckBar: true);
      final foot = tester.getRect(body).bottom;
      expect(foot, tester.getRect(deck).top);

      await pump(tester, size, keyboard: 40, deckBar: true);
      expect(tester.getRect(body).bottom, foot);
    });

    testWidgets('with nothing below the page, it takes the whole keyboard', (
      tester,
    ) async {
      const size = Size(700, 900);
      await pump(tester, size, keyboard: 300);
      expect(tester.getRect(body).bottom, size.height - 300);
    });

    for (final entry in <String, Size>{
      'on a phone with the tabs and the deck bar': const Size(400, 800),
      'beside the rail with the deck bar': const Size(700, 900),
      'beside the sidebar with the deck bar': const Size(1000, 900),
    }.entries) {
      final size = entry.value;

      testWidgets('${entry.key}, the page keeps none of the bottom inset '
          'whatever the keyboard, and floats its button above the keyboard '
          'or its own foot', (tester) async {
        await pump(tester, size, keyboard: 0, deckBar: true);
        final foot = tester.getRect(deck).top;
        final below = size.height - foot;
        final keyboards = <double>[
          // Short of the gesture bar, then over it but short of the
          // tabs, then between the tabs and the deck bar on them, and
          // taller than everything.
          inset / 2,
          if (tester.any(tabs)) ...<double>[
            tester.getRect(tabs).height - 10,
            tester.getRect(tabs).height + 10,
          ] else
            below - 10,
          below + 100,
        ];
        for (final keyboard in keyboards) {
          await pump(tester, size, keyboard: keyboard, deckBar: true);
          expect(tester.getRect(deck).top, foot, reason: 'keyboard $keyboard');
          expect(paneViewPadding, 0, reason: 'keyboard $keyboard');
          expect(
            tester.getRect(floating).bottom,
            math.min(foot, size.height - keyboard) -
                kFloatingActionButtonMargin,
            reason: 'keyboard $keyboard',
          );
        }
      });
    }

    for (final entry in <String, Size>{
      'beside the rail': const Size(700, 900),
      'beside the sidebar': const Size(1000, 900),
    }.entries) {
      final size = entry.value;

      testWidgets('${entry.key} with nothing playing, a keyboard rising '
          "through the gesture bar leaves the page's foot on it, and a "
          'taller one lifts it', (tester) async {
        for (final keyboard in const <double>[0, inset / 2, inset - 1]) {
          await pump(tester, size, keyboard: keyboard);
          expect(
            tester.getRect(body).bottom,
            size.height - inset,
            reason: 'keyboard $keyboard',
          );
        }
        await pump(tester, size, keyboard: inset + 50);
        expect(tester.getRect(body).bottom, size.height - inset - 50);
      });
    }
  });

  group("the deck bar takes the window's side insets", () {
    const inset = 40.0;
    final deck = find.byType(DeckBarOffer);
    final art = find.descendant(of: deck, matching: find.byType(ArtworkImage));
    final dismiss = find
        .descendant(of: deck, matching: find.byType(WaxIconButton))
        .last;

    Future<void> pump(
      WidgetTester tester,
      Size size,
      TextDirection direction, {
      FakeViewPadding padding = FakeViewPadding.zero,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = padding
        ..viewPadding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          builder: (context, child) =>
              Directionality(textDirection: direction, child: child!),
          home: WaxShellFrame(
            destinations: _primary,
            secondary: _secondary,
            selected: 'home',
            onSelect: (_) {},
            bottom: DeckBarOffer(
              title: 'Kelp Line',
              onResume: () {},
              onDismiss: () {},
            ),
            content: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// [inner]'s distance in from the window's start edge, or its end edge
    /// when [end], in [direction].
    double inFrom(
      Rect inner,
      Size size,
      TextDirection direction, {
      bool end = false,
    }) => (direction == TextDirection.ltr) != end
        ? inner.left
        : size.width - inner.right;

    for (final direction in TextDirection.values) {
      for (final entry in <String, Size>{
        'the rail': const Size(700, 900),
        'the sidebar': const Size(1000, 900),
      }.entries) {
        final size = entry.value;
        testWidgets('${direction.name}: under ${entry.key}, its controls '
            'clear both side insets', (tester) async {
          await pump(tester, size, direction);
          final start = inFrom(tester.getRect(art), size, direction);
          final end = inFrom(
            tester.getRect(dismiss),
            size,
            direction,
            end: true,
          );

          await pump(
            tester,
            size,
            direction,
            padding: const FakeViewPadding(left: inset, right: inset),
          );
          expect(
            inFrom(tester.getRect(art), size, direction),
            start + inset,
            reason: 'the start side',
          );
          expect(
            inFrom(tester.getRect(dismiss), size, direction, end: true),
            end + inset,
            reason: 'the end side',
          );
          expect(
            tester.getRect(deck),
            Rect.fromLTRB(0, tester.getRect(deck).top, size.width, size.height),
            reason: 'its surface still spans the window',
          );
        });
      }

      testWidgets('${direction.name}: on a phone, over the tabs, its '
          'controls clear both side insets', (tester) async {
        const size = Size(400, 800);
        await pump(tester, size, direction);
        final start = inFrom(tester.getRect(art), size, direction);
        final end = inFrom(tester.getRect(dismiss), size, direction, end: true);

        await pump(
          tester,
          size,
          direction,
          padding: const FakeViewPadding(left: inset, right: inset),
        );
        expect(
          inFrom(tester.getRect(art), size, direction),
          start + inset,
          reason: 'the start side',
        );
        expect(
          inFrom(tester.getRect(dismiss), size, direction, end: true),
          end + inset,
          reason: 'the end side',
        );
        final surface = tester.getRect(deck);
        expect(
          (surface.left, surface.right, surface.bottom),
          (0.0, size.width, tester.getRect(find.byType(WaxNavBar)).top),
          reason: 'its surface still spans the window, on the tabs',
        );
      });
    }
  });

  group('the page keeps its state while the frame changes around it', () {
    testWidgets('a keyed page keeps its scroll and its typed text across '
        'every size class, banners, the deck bar and a keyboard', (
      tester,
    ) async {
      final page = GlobalKey<_StatefulPageState>();
      Widget frame({bool banner = false, bool deckBar = false}) => MaterialApp(
        theme: buildWaxTheme(),
        home: WaxShellFrame(
          destinations: _primary,
          secondary: _secondary,
          selected: 'home',
          onSelect: (_) {},
          banners: <Widget>[
            if (banner) const WaxBanner(message: 'Reconnecting.'),
          ],
          bottom: deckBar
              ? DeckBarOffer(title: 'Kelp', onResume: () {}, onDismiss: () {})
              : null,
          content: _StatefulPage(key: page),
        ),
      );

      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame());
      await tester.enterText(find.byType(TextField), 'typed');
      page.currentState!.scroll.jumpTo(120);
      await tester.pump();
      final state = page.currentState;

      void kept(String when) {
        expect(page.currentState, same(state), reason: when);
        expect(page.currentState!.inits, 1, reason: when);
        expect(page.currentState!.scroll.offset, 120, reason: when);
        expect(find.text('typed'), findsOneWidget, reason: when);
      }

      for (final size in const <Size>[
        Size(700, 900),
        Size(1000, 900),
        Size(1300, 900),
        Size(400, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        kept('at $size');
      }
      await tester.pumpWidget(frame(banner: true, deckBar: true));
      kept('with a banner and the deck bar');
      for (var keyboard = 0.0; keyboard <= 300; keyboard += 60) {
        _engineInsets(
          tester,
          const FakeViewPadding(bottom: 34),
          keyboard: keyboard,
        );
        await tester.pump();
        kept('with a keyboard $keyboard high');
      }
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpWidget(frame());
      kept('beside the sidebar again, with neither');
    });

    testWidgets('an open side panel keeps its state while a banner comes '
        'and goes', (tester) async {
      // Not keyed from outside, as the app's own panel is not: what keeps
      // it is the frame's shape above it.
      Widget frame({required bool banner}) => MaterialApp(
        theme: buildWaxTheme(),
        home: WaxShellFrame(
          destinations: _primary,
          secondary: _secondary,
          selected: 'home',
          onSelect: (_) {},
          banners: <Widget>[
            if (banner) const WaxBanner(message: 'Reconnecting.'),
          ],
          panel: const WaxSidePanel(title: 'Queue', child: _StatefulPage()),
          content: const SizedBox.expand(),
        ),
      );
      final inPanel = find.descendant(
        of: find.byType(WaxSidePanel),
        matching: find.byType(_StatefulPage),
      );

      tester.view
        ..physicalSize = const Size(1300, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(frame(banner: false));
      final state = tester.state<_StatefulPageState>(inPanel);
      state.scroll.jumpTo(120);
      await tester.pump();

      for (final banner in <bool>[true, false, true]) {
        await tester.pumpWidget(frame(banner: banner));
        final now = tester.state<_StatefulPageState>(inPanel);
        expect(now, same(state), reason: 'banner $banner');
        expect(now.inits, 1, reason: 'banner $banner');
        expect(now.scroll.offset, 120, reason: 'banner $banner');
      }
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

  group("a page's foot bar stands on the window's foot", () {
    const inset = 30.0;
    const cutout = 24.0;
    final bar = find.byType(WaxFootBar);
    final controls = find.byKey(const Key('controls'));
    final endPane = find.byKey(const Key('end pane'));
    final deck = find.byType(DeckBarOffer);
    final tabs = find.byType(WaxNavBar);

    const footed = WaxFootedPane(
      body: SizedBox.expand(),
      foot: WaxFootBar(child: SizedBox(key: Key('controls'), height: 40)),
    );

    /// The frame at [size] over a gesture bar [inset] high with a
    /// keyboard [keyboard] high and cutouts [left] and [right] wide,
    /// around a page that fills with a footed pane, the end one of two
    /// when [split], with the deck bar's offer below when [deckBar].
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      bool deckBar = false,
      bool split = false,
      double bottom = inset,
      double keyboard = 0,
      double left = 0,
      double right = cutout,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      _engineInsets(
        tester,
        FakeViewPadding(left: left, right: right, bottom: bottom),
        keyboard: keyboard,
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
            onToggleCollapsed: () {},
            bottom: deckBar
                ? DeckBarOffer(
                    title: 'Kelp Line',
                    onResume: () {},
                    onDismiss: () {},
                  )
                : null,
            content: WaxScaffold(
              title: 'Page',
              largeTitle: false,
              fill: split
                  ? const Row(
                      children: <Widget>[
                        Expanded(
                          child: WaxInsetsTaken(
                            end: true,
                            child: SafeArea(
                              top: false,
                              child: SizedBox.expand(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: WaxInsetsTaken(
                            key: Key('end pane'),
                            start: true,
                            child: footed,
                          ),
                        ),
                      ],
                    )
                  : footed,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, Size>{
      'on a phone': const Size(400, 800),
      'beside the rail': const Size(700, 900),
      'beside the sidebar': const Size(1000, 900),
    }.entries) {
      final size = entry.value;
      for (final deckBar in <bool>[false, true]) {
        for (final split in <bool>[false, true]) {
          final where =
              '${entry.key}${deckBar ? ' with the deck bar' : ''}, '
              '${split ? 'under the end pane of two' : 'across the page'}';

          testWidgets("$where, its surface reaches the window's foot or "
              'what stands on it and the end edge, and its controls keep '
              'clear of the insets', (tester) async {
            await pump(tester, size, deckBar: deckBar, split: split);
            final below = deckBar
                ? tester.getRect(deck).top
                : tester.any(tabs)
                ? tester.getRect(tabs).top
                : size.height;
            final page = tester.getRect(find.byType(WaxScaffold));
            final start = split ? tester.getRect(endPane).left : page.left;
            final box = tester.getRect(bar);
            final inner = tester.getRect(controls);
            expect(box.bottom, below, reason: 'its surface, at the foot');
            expect(box.right, size.width, reason: 'its surface, at the end');
            expect(box.left, start, reason: 'its surface, at the start');
            expect(
              inner.bottom,
              below == size.height ? size.height - inset : below,
              reason: 'its controls, at the foot',
            );
            expect(inner.right, size.width - cutout, reason: 'at the end');
            expect(inner.left, start, reason: 'at the start');
          });
        }
      }
    }

    /// The colour the window's layer holds at [at], as composited: no
    /// repaint asked for first, so a picture left stale shows.
    Future<List<int>> pixel(WidgetTester tester, Offset at) async {
      final out = await tester.runAsync(() async {
        final image = await captureImage(
          tester.element(find.byType(WaxShellFrame)),
        );
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final i = ((at.dy.floor() * image.width) + at.dx.floor()) * 4;
        return <int>[for (var k = 0; k < 4; k++) data.getUint8(i + k)];
      });
      return out!;
    }

    testWidgets('beside the rail with nothing playing, the frame after a '
        'keyboard closes through the gesture bar has the bar on the foot', (
      tester,
    ) async {
      const size = Size(700, 900);
      await pump(tester, size);
      for (final keyboard in const <double>[300, 120, 40, 18, 7, 2, 0]) {
        _engineInsets(
          tester,
          const FakeViewPadding(right: cutout, bottom: inset),
          keyboard: keyboard,
        );
        await tester.pump();
      }
      expect(tester.getRect(bar).bottom, size.height);
      expect(tester.getRect(controls).bottom, size.height - inset);
      final surface = await pixel(tester, const Offset(400, 850));
      expect(surface, isNot(await pixel(tester, const Offset(400, 400))));
      expect(
        await pixel(tester, const Offset(400, 895)),
        surface,
        reason: 'under the gesture bar',
      );
    });

    testWidgets('beside the rail, the frame after a cutout moves to the '
        'other side has the bar under the new one', (tester) async {
      const size = Size(700, 900);
      await pump(tester, size, bottom: 0, left: 40, right: 0);
      _engineInsets(tester, const FakeViewPadding(right: 40));
      await tester.pump();
      expect(tester.getRect(bar).right, size.width);
      expect(tester.getRect(controls).right, size.width - 40);
      expect(
        await pixel(tester, const Offset(690, 880)),
        await pixel(tester, const Offset(400, 880)),
        reason: 'under the end cutout',
      );
    });
  });
}

/// A page with state of its own to lose: a scroll position and a field.
class _StatefulPage extends StatefulWidget {
  const _StatefulPage({super.key});

  @override
  State<_StatefulPage> createState() => _StatefulPageState();
}

class _StatefulPageState extends State<_StatefulPage> {
  final scroll = ScrollController();
  var inits = 0;

  @override
  void initState() {
    super.initState();
    inits++;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      children: <Widget>[
        const TextField(),
        Expanded(
          child: ListView(
            controller: scroll,
            children: <Widget>[
              for (var row = 0; row < 40; row++)
                SizedBox(height: 40, child: Text('row $row')),
            ],
          ),
        ),
      ],
    ),
  );
}
