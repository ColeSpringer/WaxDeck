import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _light = WaxColors.light;
const _dark = WaxColors.dark;

/// Mounts [home] the way the app hosts a screen: no theme lerp and the root
/// text style a bare Text inherits. Light until the returned switch says
/// dark. Nothing sits between the root and [home], so whatever still eases
/// after a switch is the component's own.
Future<ValueNotifier<ThemeMode>> _mount(
  WidgetTester tester,
  Widget home,
) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
  addTearDown(mode.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        theme: buildWaxTheme(variant: WaxThemeVariant.light),
        darkTheme: buildWaxTheme(),
        themeMode: value,
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, app) => DefaultTextStyle(
          style: WaxType.body.copyWith(
            color: WaxColors.of(context).textPrimary,
          ),
          child: app!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return mode;
}

/// The colour a paragraph is drawn in this frame.
Color? _ink(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

/// The colour a Text with no colour of its own would draw in at [at].
Color? _inherited(WidgetTester tester, Finder at) =>
    DefaultTextStyle.of(tester.element(at.first)).style.color;

/// A Text with a style that names no colour, as the screens write them.
Widget _bare() => Text('bare', style: WaxType.label);

const _body = SizedBox(height: 2000);

final _scaffoldSlots = <String, Widget>{
  'the body': WaxScaffold(title: 'T', body: _bare()),
  'a sliver': WaxScaffold(
    title: 'T',
    slivers: <Widget>[SliverToBoxAdapter(child: _bare())],
  ),
  'the bottom bar': WaxScaffold(title: 'T', body: _body, bottom: _bare()),
  'the floating button': WaxScaffold(
    title: 'T',
    body: _body,
    floating: _bare(),
  ),
  'an action': WaxScaffold(title: 'T', body: _body, actions: <Widget>[_bare()]),
};

void main() {
  group('text that inherits its colour lands with the theme', () {
    for (final MapEntry(key: slot, value: scaffold) in _scaffoldSlots.entries) {
      testWidgets('in WaxScaffold, $slot', (tester) async {
        final mode = await _mount(tester, scaffold);
        expect(_ink(tester, 'bare'), _light.textPrimary);

        mode.value = ThemeMode.dark;
        await tester.pump();

        expect(_ink(tester, 'bare'), _dark.textPrimary);
      });
    }

    // Already plain before the fix: the app bar and its flexible space put
    // their own style over what the Scaffold's Material eases.
    for (final largeTitle in <bool>[true, false]) {
      testWidgets('in WaxScaffold, the ${largeTitle ? 'large' : 'compact'} '
          'title', (tester) async {
        final mode = await _mount(
          tester,
          WaxScaffold(title: 'T', largeTitle: largeTitle, body: _body),
        );
        expect(_inherited(tester, find.text('T')), _light.textPrimary);

        mode.value = ThemeMode.dark;
        await tester.pump();

        expect(_inherited(tester, find.text('T')), _dark.textPrimary);
      });
    }

    testWidgets('in WaxSidePanel', (tester) async {
      final mode = await _mount(
        tester,
        Center(
          child: SizedBox(
            width: 320,
            height: 400,
            child: WaxSidePanel(title: 'Panel', child: _bare()),
          ),
        ),
      );
      expect(_ink(tester, 'bare'), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_ink(tester, 'bare'), _dark.textPrimary);
    });

    // The banner and the palettes take strings, not widgets, so there is no
    // slot for a bare Text: what is read is the style a Text placed beside
    // theirs would inherit.
    testWidgets('in WaxBanner', (tester) async {
      final mode = await _mount(
        tester,
        const Align(
          alignment: Alignment.topCenter,
          child: WaxBanner(message: 'Reconnecting'),
        ),
      );
      final at = find.byType(WaxProse);
      expect(_inherited(tester, at), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_inherited(tester, at), _dark.textPrimary);
    });

    testWidgets('in WaxCommandPalette', (tester) async {
      final mode = await _mount(
        tester,
        Center(
          child: WaxCommandPalette(
            groups: const <WaxPaletteGroup>[
              WaxPaletteGroup(
                title: 'Actions',
                entries: <WaxPaletteEntry>[
                  WaxPaletteEntry(id: 'play', label: 'Play'),
                ],
              ),
            ],
            onQueryChanged: (_) {},
            onRun: (_) {},
          ),
        ),
      );
      final at = find.text('ACTIONS');
      expect(_inherited(tester, at), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_inherited(tester, at), _dark.textPrimary);
    });

    // The sheet is the framework's, and its Material eases what the
    // caller's builder puts on it.
    testWidgets('in a sheet opened with showWaxSheet', (tester) async {
      late BuildContext host;
      final mode = await _mount(
        tester,
        Builder(
          builder: (context) {
            host = context;
            return const SizedBox.expand();
          },
        ),
      );
      unawaited(showWaxSheet<void>(context: host, builder: (_) => _bare()));
      await tester.pumpAndSettle();
      expect(_ink(tester, 'bare'), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_ink(tester, 'bare'), _dark.textPrimary);
    });

    testWidgets('in WaxInkTappable', (tester) async {
      final mode = await _mount(
        tester,
        Center(
          child: WaxInkTappable(label: 'Row', onPressed: () {}, child: _bare()),
        ),
      );
      expect(_ink(tester, 'bare'), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_ink(tester, 'bare'), _dark.textPrimary);
    });

    // The rest draw their own text in their own colours, so what is read is
    // the style a Text beside theirs would inherit: each of them rebuilt
    // every Text under it on every frame of the ease.
    for (final (name, component, at) in <(String, Widget, Finder)>[
      (
        'a card corner chip',
        SizedBox(
          width: 160,
          child: MediaCard(
            data: const MediaTileData(title: 'Station'),
            onTap: () {},
            action: MediaCardAction(
              glyph: WaxIcons.star,
              label: 'Pin',
              onPressed: () {},
            ),
          ),
        ),
        find.byType(WaxIconButton),
      ),
      (
        'MediaListRow',
        SizedBox(
          width: 400,
          child: MediaListRow(
            data: const MediaTileData(title: 'Track', trailingText: '4:18'),
            onTap: () {},
          ),
        ),
        find.text('Track'),
      ),
      (
        'WaxButton',
        WaxButton(label: 'Show all', onPressed: () {}),
        find.text('Show all'),
      ),
    ]) {
      testWidgets('in $name', (tester) async {
        final mode = await _mount(tester, Center(child: component));
        expect(_inherited(tester, at), _light.textPrimary);

        mode.value = ThemeMode.dark;
        await tester.pump();

        expect(_inherited(tester, at), _dark.textPrimary);
      });
    }

    testWidgets('in WaxShortcutSheet', (tester) async {
      final mode = await _mount(
        tester,
        const Center(
          child: WaxShortcutSheet(
            groups: <WaxShortcutGroup>[
              WaxShortcutGroup(
                title: 'Playback',
                rows: <WaxShortcutRow>[
                  WaxShortcutRow(label: 'Play', keys: 'Space'),
                ],
              ),
            ],
          ),
        ),
      );
      final at = find.text('PLAYBACK');
      expect(_inherited(tester, at), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_inherited(tester, at), _dark.textPrimary);
    });
  });

  // A menu follows a theme switch while it is open, since the app's theme
  // sits above the navigator it opens on.
  group('an open menu lands with the theme', () {
    for (final (name, trigger, opener, rows) in _menus) {
      testWidgets('in $name', (tester) async {
        final mode = await _mount(tester, _host(trigger));
        await tester.tap(opener);
        await tester.pumpAndSettle();
        for (final (text, ink) in rows) {
          expect(_menuInk(tester, text), ink(_light), reason: text);
        }
        expect(_menuSurface(tester), _light.surface2);

        mode.value = ThemeMode.dark;
        await tester.pump();

        for (final (text, ink) in rows) {
          expect(_menuInk(tester, text), ink(_dark), reason: text);
        }
        expect(_menuSurface(tester), _dark.surface2);
      });
    }

    // What the rows inherit is held still, at what the menu item eases to.
    testWidgets('a row inherits the menu item\'s own style, enabled or not', (
      tester,
    ) async {
      await _mount(tester, _host(_navMenu));
      await tester.tap(find.byType(WaxIconButton));
      await tester.pumpAndSettle();

      for (final text in <String>['Settings', 'LIBRARY']) {
        final item = find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        );
        final eased = tester.widget<AnimatedDefaultTextStyle>(
          find.descendant(
            of: item,
            matching: find.byType(AnimatedDefaultTextStyle),
          ),
        );
        expect(
          DefaultTextStyle.of(tester.element(find.text(text))).style,
          eased.style,
          reason: text,
        );
      }
    });
  });
}

/// A trigger on the Material its ink needs.
Widget _host(Widget trigger) => Material(
  type: MaterialType.transparency,
  child: Center(child: trigger),
);

final _inMenu = find.byWidgetPredicate((w) => w is PopupMenuItem);

/// The colour [text] in the open menu is drawn in this frame; a glyph by
/// its [WaxGlyph]'s name.
Color? _menuInk(WidgetTester tester, String text) {
  final glyph = _glyphs[text];
  final at = find.descendant(
    of: _inMenu,
    matching: glyph == null
        ? find.text(text)
        : find.descendant(
            of: find.byWidgetPredicate((w) => w is WaxIcon && w.glyph == glyph),
            matching: find.byType(RichText),
          ),
  );
  return tester.renderObject<RenderParagraph>(at).text.style?.color;
}

/// The menu's own surface as drawn this frame.
Color _menuSurface(WidgetTester tester) => tester
    .renderObject<RenderPhysicalShape>(
      find
          .ancestor(of: _inMenu.first, matching: find.byType(PhysicalShape))
          .first,
    )
    .color;

const _glyphs = <String, WaxGlyph>{
  'check': WaxIcons.check,
  'gear': WaxIcons.settings,
  'bin': WaxIcons.delete,
};

typedef _Row = (String text, Color Function(WaxColors colors) ink);

final _navMenu = WaxNavOverflowButton(
  entries: const <WaxNavEntry>[
    WaxNavLink(
      WaxDestination(
        name: 'settings',
        label: 'Settings',
        glyph: WaxIcons.settings,
      ),
    ),
    WaxNavGroup(
      name: 'library',
      label: 'LIBRARY',
      glyph: WaxIcons.library,
      children: <WaxDestination>[
        WaxDestination(
          name: 'books',
          label: 'Books',
          glyph: WaxIcons.audiobooks,
        ),
      ],
    ),
  ],
  onSelect: (_) {},
);

/// Each menu: its trigger, what opens it, and the rows read in it with the
/// token each is drawn in.
final _menus = <(String, Widget, Finder, List<_Row>)>[
  (
    'the WaxChoice menu',
    WaxChoice<String>(
      value: 'Dark',
      options: const <String>['Light', 'Dark'],
      labelFor: (option) => option,
      onChanged: (_) {},
      label: 'Theme',
    ),
    find.byType(WaxInkTappable),
    <_Row>[('Light', (c) => c.textPrimary), ('check', (c) => c.accent)],
  ),
  (
    'the navigation overflow menu',
    _navMenu,
    find.byType(WaxIconButton),
    <_Row>[
      ('Settings', (c) => c.textPrimary),
      ('LIBRARY', (c) => c.textTertiary),
      ('Books', (c) => c.textPrimary),
    ],
  ),
  (
    'the account menu',
    WaxAccountButton(
      account: const WaxAccount(
        name: 'Ann',
        actions: <WaxAccountAction>[
          WaxAccountAction(
            name: 'settings',
            label: 'Preferences',
            glyph: WaxIcons.settings,
          ),
        ],
      ),
      onAction: (_) {},
    ),
    find.byType(WaxAccountButton),
    <_Row>[
      ('Ann', (c) => c.textPrimary),
      ('Preferences', (c) => c.textPrimary),
      ('gear', (c) => c.textSecondary),
    ],
  ),
  (
    'a WaxMenuButton menu',
    WaxMenuButton<String>(
      items: const <WaxMenuItem<String>>[
        WaxMenuItem(value: 'sort', label: 'Sort', selected: true),
        WaxMenuItem(
          value: 'delete',
          label: 'Delete',
          glyph: WaxIcons.delete,
          destructive: true,
        ),
        WaxMenuItem(
          value: 'share',
          label: 'Share',
          enabled: false,
          help: 'Nothing to share',
        ),
      ],
      onSelected: (_) {},
    ),
    find.byType(WaxIconButton),
    <_Row>[
      ('Sort', (c) => c.textPrimary),
      ('check', (c) => c.accent),
      ('Delete', (c) => c.error),
      ('bin', (c) => c.error),
      ('Share', (c) => c.textDisabled),
      ('Nothing to share', (c) => c.textDisabled),
    ],
  ),
];
