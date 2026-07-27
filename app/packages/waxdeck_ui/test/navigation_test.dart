import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _primary = <WaxDestination>[
  WaxDestination(name: 'home', label: 'Home', glyph: WaxIcons.home),
  WaxDestination(name: 'music', label: 'Music', glyph: WaxIcons.music),
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

/// Pumps the frame at [size], which is what picks the chrome: every
/// adaptive decision keys off the window's own width.
Future<List<String>> _pumpFrame(
  WidgetTester tester, {
  required Size size,
  String selected = 'home',
  double textScale = 1,
  bool collapsed = false,
  VoidCallback? onToggleCollapsed,
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
        content: const Center(child: Text('content pane')),
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
          ),
        );
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
    // before it in the same container — the sidebar and the rail, both
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

      // No labels are drawn at rail width, so every entry — group
      // children included — has to be reachable as an icon, or it is
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
