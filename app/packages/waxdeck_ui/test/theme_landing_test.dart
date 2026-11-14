import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

const _light = WaxColors.light;
const _dark = WaxColors.dark;

const _destinations = <WaxDestination>[
  WaxDestination(
    name: 'home',
    label: 'Home',
    glyph: WaxIcons.home,
    semanticsId: 'nav-home',
  ),
  WaxDestination(
    name: 'podcasts',
    label: 'Podcasts',
    glyph: WaxIcons.podcasts,
    semanticsId: 'nav-podcasts',
  ),
];

/// Mounts [child] the way the app hosts it, with no theme lerp, light until
/// the returned switch says dark. The host's own Material lands its default
/// text style at once, so whatever still ticks after a switch is the
/// child's.
///
/// The themes are built again on every build, as the app builds them, so an
/// equal theme must not read as a new one: [artworkGlow] off makes a new
/// [WaxColors] each time, and [rebuilds] rebuilds the app on demand.
/// [darkShadow] gives the dark theme its own shadow colour, which the
/// shipped themes do not have.
Future<ValueNotifier<ThemeMode>> _mount(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  bool artworkGlow = true,
  Listenable? rebuilds,
  Color? darkShadow,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
  addTearDown(mode.dispose);
  await tester.pumpWidget(
    ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[mode, rebuilds]),
      builder: (context, _) => MaterialApp(
        theme: buildWaxTheme(
          variant: WaxThemeVariant.light,
          artworkGlow: artworkGlow,
        ),
        darkTheme: _shadowed(
          buildWaxTheme(artworkGlow: artworkGlow),
          darkShadow,
        ),
        themeMode: mode.value,
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: app!,
        ),
        home: Material(
          type: MaterialType.transparency,
          animationDuration: Duration.zero,
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return mode;
}

ThemeData _shadowed(ThemeData theme, Color? shadow) => shadow == null
    ? theme
    : theme.copyWith(colorScheme: theme.colorScheme.copyWith(shadow: shadow));

Finder _id(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

/// The box a component fills or outlines, as drawn this frame.
BoxDecoration _drawn(WidgetTester tester, Finder component) =>
    tester
            .renderObject<RenderDecoratedBox>(
              find
                  .descendant(
                    of: component,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Color? _outline(BoxDecoration decoration) =>
    (decoration.border as Border?)?.top.color;

Widget _sidebar(String selected) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[
    WaxSidebar(
      destinations: _destinations,
      selected: selected,
      onSelect: (_) {},
    ),
    const Expanded(child: SizedBox.shrink()),
  ],
);

/// A component, where its themed box is, and what that box is drawn in
/// under a theme's colours.
typedef _Case = ({
  Widget widget,
  Finder box,
  Color Function(WaxColors colors) fill,
  Color Function(WaxColors colors)? outline,
});

final _cases = <String, _Case>{
  'the selected tab': (
    widget: Column(
      children: <Widget>[
        const Spacer(),
        WaxNavBar(
          destinations: _destinations,
          selected: 'home',
          onSelect: (_) {},
        ),
      ],
    ),
    box: _id('nav-home'),
    fill: (colors) => colors.accentContainer,
    outline: null,
  ),
  'the selected rail item': (
    widget: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WaxNavRail(
          destinations: _destinations,
          selected: 'home',
          onSelect: (_) {},
        ),
        const Expanded(child: SizedBox.shrink()),
      ],
    ),
    box: _id('nav-home'),
    fill: (colors) => colors.accentContainer,
    outline: null,
  ),
  'the selected sidebar row': (
    widget: _sidebar('home'),
    box: _id('nav-home'),
    fill: (colors) => colors.accentContainer,
    outline: null,
  ),
  'the search pill': (
    widget: const Center(child: SizedBox(width: 320, child: SearchField())),
    box: find.byType(SearchField),
    fill: (colors) => colors.surface2,
    outline: (colors) => colors.hairline,
  ),
  'the selected segment': (
    widget: Center(
      child: WaxSegmented(
        segments: const <WaxSegment>[
          WaxSegment(name: 'a', label: 'Album', semanticsId: 'seg-a'),
          WaxSegment(name: 'b', label: 'Track', semanticsId: 'seg-b'),
        ],
        selected: 'a',
        onSelect: (_) {},
      ),
    ),
    box: _id('seg-a'),
    fill: (colors) => colors.accentContainer,
    outline: null,
  ),
  'the selected filter chip': (
    widget: Center(
      child: FilterChipRow(
        chips: const <WaxFilterChip>[
          WaxFilterChip(name: 'all', label: 'All', semanticsId: 'chip-all'),
          WaxFilterChip(name: 'new', label: 'New', semanticsId: 'chip-new'),
        ],
        selected: 'all',
        onSelect: (_) {},
      ),
    ),
    box: _id('chip-all'),
    fill: (colors) => colors.accentContainer,
    outline: (colors) => colors.accent,
  ),
  'the splitter seam': (
    widget: Row(
      children: <Widget>[
        const SizedBox(width: 300),
        WaxSplitter(position: 300, min: 100, max: 600, onChanged: (_) {}),
        const Expanded(child: SizedBox.shrink()),
      ],
    ),
    box: find.byType(WaxSplitter),
    fill: (colors) => colors.hairline,
    outline: null,
  ),
};

/// What a Material under [of] paints this frame: its lift, shadow and the
/// outline of its shape.
({double elevation, Color shadow, Color? ring}) _painted(
  WidgetTester tester,
  Finder of,
) {
  final material = find.ancestor(of: of, matching: find.byType(Material));
  final shape = tester.renderObject<RenderPhysicalShape>(
    find
        .descendant(of: material.first, matching: find.byType(PhysicalShape))
        .first,
  );
  final border = (shape.clipper! as ShapeBorderClipper).shape;
  return (
    elevation: shape.elevation,
    shadow: shape.shadowColor,
    ring: border is OutlinedBorder ? border.side.color : null,
  );
}

Color _opaque(Color color) => color.withValues(alpha: 1);

/// The colour a Text with none of its own would draw in at [at].
Color? _inherited(WidgetTester tester, Finder at) =>
    DefaultTextStyle.of(tester.element(at.first)).style.color;

final _forward = find.byWidgetPredicate(
  (widget) => widget is WaxIcon && widget.glyph == WaxIcons.forward,
);

Widget _fab({bool enabled = true}) => Center(
  child: WaxFab(
    glyph: WaxIcons.play,
    label: 'Play',
    onPressed: enabled ? () {} : null,
  ),
);

void main() {
  group('a theme switch lands at once', () {
    for (final MapEntry(key: name, value: subject) in _cases.entries) {
      testWidgets('on $name', (tester) async {
        final mode = await _mount(tester, subject.widget);
        final before = _drawn(tester, subject.box);
        expect(before.color, subject.fill(_light));
        expect(subject.fill(_dark), isNot(subject.fill(_light)));
        if (subject.outline case final outline?) {
          expect(_outline(before), outline(_light));
        }

        mode.value = ThemeMode.dark;
        await tester.pump();

        final after = _drawn(tester, subject.box);
        expect(after.color, subject.fill(_dark));
        if (subject.outline case final outline?) {
          expect(_outline(after), outline(_dark));
        }
      });

      // Its own test, so it can fail on its own: an implicit animation
      // that eased into the new theme keeps asking for frames. Semantics
      // off, because a scroll view takes a new position when the theme
      // changes and a live semantics tree republishes it a frame later,
      // drawing nothing.
      testWidgets(
        'and leaves no frame scheduled on $name',
        semanticsEnabled: false,
        (tester) async {
          final mode = await _mount(tester, subject.widget);

          mode.value = ThemeMode.dark;
          await tester.pump();

          expect(
            tester.binding.hasScheduledFrame,
            isFalse,
            reason: 'nothing eases into the new theme',
          );
        },
      );
    }

    testWidgets('under reduced motion too', semanticsEnabled: false, (
      tester,
    ) async {
      final mode = await _mount(tester, _sidebar('home'), reduceMotion: true);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_drawn(tester, _id('nav-home')).color, _dark.accentContainer);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('a Material that draws a theme colour lands with it', () {
    testWidgets('the ring of a hovered shelf chevron', (tester) async {
      final mode = await _mount(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            child: ShelfRow(
              title: 'Recently added',
              cardWidth: 120,
              items: <MediaTileData>[
                for (var i = 0; i < 12; i++)
                  MediaTileData(title: 'Card $i', subtitle: 'Nightjar'),
              ],
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 7,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(ListView)));
      await tester.pumpAndSettle();
      expect(_forward, findsOneWidget);
      expect(_opaque(_painted(tester, _forward).ring!), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_opaque(_painted(tester, _forward).ring!), _dark.textPrimary);
    });

    testWidgets('the shadow of the floating action button', (tester) async {
      const shadow = Color(0xFF123456);
      const black = Color(0xFF000000);
      final mode = await _mount(tester, _fab(), darkShadow: shadow);
      expect(_painted(tester, find.byType(WaxIcon)).shadow, black);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_painted(tester, find.byType(WaxIcon)).shadow, shadow);
    });

    testWidgets('the text style the floating action button hands down', (
      tester,
    ) async {
      final mode = await _mount(tester, _fab());
      expect(_inherited(tester, find.byType(WaxIcon)), _light.textPrimary);

      mode.value = ThemeMode.dark;
      await tester.pump();

      expect(_inherited(tester, find.byType(WaxIcon)), _dark.textPrimary);
    });
  });

  group('the floating action button\'s lift still eases', () {
    /// Mounts the fab enabled, turns it off, and answers its lift [into]
    /// the change, after a switch to dark when [dark].
    Future<double> disableAndWait(
      WidgetTester tester, {
      required Duration into,
      bool dark = false,
    }) async {
      final enabled = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);
      final mode = await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, value, _) => _fab(enabled: value),
        ),
      );
      if (dark) {
        mode.value = ThemeMode.dark;
        await tester.pump();
      }
      enabled.value = false;
      await tester.pump();
      await tester.pump(into);
      return _painted(tester, find.byType(WaxIcon)).elevation;
    }

    testWidgets('is mid-way after half its duration', (tester) async {
      final lift = await disableAndWait(
        tester,
        into: kThemeChangeDuration ~/ 2,
      );

      expect(lift, inExclusiveRange(0, 3));
      await tester.pumpAndSettle();
      expect(_painted(tester, find.byType(WaxIcon)).elevation, 0);
    });

    testWidgets('on the first change after a theme switch', (tester) async {
      final lift = await disableAndWait(
        tester,
        into: kThemeChangeDuration ~/ 2,
        dark: true,
      );

      expect(lift, inExclusiveRange(0, 3));
    });
  });

  group('a state change still eases', () {
    /// Mounts the sidebar on home, moves the selection to podcasts, and
    /// answers the podcasts row's fill [into] the change.
    Future<Color?> selectAndWait(
      WidgetTester tester, {
      required Duration into,
      bool dark = false,
      bool reduceMotion = false,
    }) async {
      final selected = ValueNotifier<String>('home');
      addTearDown(selected.dispose);
      final mode = await _mount(
        tester,
        ValueListenableBuilder<String>(
          valueListenable: selected,
          builder: (context, value, _) => _sidebar(value),
        ),
        reduceMotion: reduceMotion,
      );
      if (dark) {
        mode.value = ThemeMode.dark;
        await tester.pump();
      }
      selected.value = 'podcasts';
      await tester.pump();
      await tester.pump(into);
      return _drawn(tester, _id('nav-podcasts')).color;
    }

    testWidgets('selecting a row is mid-way after half its duration', (
      tester,
    ) async {
      final fill = await selectAndWait(tester, into: WaxMotion.full.quick ~/ 2);

      expect(fill, isNot(anyOf(Colors.transparent, _light.accentContainer)));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(_drawn(tester, _id('nav-podcasts')).color, _light.accentContainer);
    });

    testWidgets('on the first change after a theme switch', (tester) async {
      final fill = await selectAndWait(
        tester,
        into: WaxMotion.full.quick ~/ 2,
        dark: true,
      );

      expect(fill, isNot(anyOf(Colors.transparent, _dark.accentContainer)));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    // With the glow off the app's theme is a new WaxColors on every build,
    // equal by value to the last: comparing them by identity would read a
    // selection that moves in the same pass as a rebuild as a theme switch,
    // and land it at once.
    testWidgets('in the pass that rebuilds an equal theme', (tester) async {
      final selected = ValueNotifier<String>('home');
      addTearDown(selected.dispose);
      final rebuilds = ValueNotifier<int>(0);
      addTearDown(rebuilds.dispose);
      await _mount(
        tester,
        ValueListenableBuilder<String>(
          valueListenable: selected,
          builder: (context, value, _) => _sidebar(value),
        ),
        artworkGlow: false,
        rebuilds: rebuilds,
      );
      final before = WaxColors.of(tester.element(find.byType(WaxSidebar)));

      selected.value = 'podcasts';
      rebuilds.value++;
      await tester.pump();
      await tester.pump(WaxMotion.full.quick ~/ 2);

      final after = WaxColors.of(tester.element(find.byType(WaxSidebar)));
      expect(after, before, reason: 'an equal theme');
      expect(after, isNot(same(before)), reason: 'built afresh');
      final fill = _drawn(tester, _id('nav-podcasts')).color;
      expect(fill, isNot(anyOf(Colors.transparent, _light.accentContainer)));
    });

    testWidgets('over reduced motion\'s shorter fade', (tester) async {
      final fill = await selectAndWait(
        tester,
        into: WaxMotion.reduced.quick ~/ 2,
        reduceMotion: true,
      );

      expect(fill, isNot(anyOf(Colors.transparent, _light.accentContainer)));
      await tester.pump(WaxMotion.reduced.quick ~/ 2);
      expect(_drawn(tester, _id('nav-podcasts')).color, _light.accentContainer);
    });
  });
}
