import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

WaxColors _colorsOf(ThemeData theme) => theme.extension<WaxColors>()!;

void main() {
  group('the artwork glow', () {
    test('is on by default, at each dark theme\'s own strength', () {
      // The two dark themes carry different strengths on purpose - OLED
      // is half - so a default that flattened them would be a silent
      // change to the house look rather than a setting nobody set.
      expect(_colorsOf(buildWaxTheme()).glowOpacity, 0.24);
      expect(
        _colorsOf(buildWaxTheme(variant: WaxThemeVariant.oled)).glowOpacity,
        0.12,
      );
    });

    test('is already zero in light, which is what the off state renders', () {
      expect(
        _colorsOf(buildWaxTheme(variant: WaxThemeVariant.light)).glowOpacity,
        0,
      );
    });

    test('turned off zeroes the token in every variant', () {
      for (final variant in WaxThemeVariant.values) {
        expect(
          _colorsOf(
            buildWaxTheme(variant: variant, artworkGlow: false),
          ).glowOpacity,
          0,
          reason: '${variant.name} still glows',
        );
      }
    });

    test('turning it off leaves the rest of the palette alone', () {
      final on = _colorsOf(buildWaxTheme());
      final off = _colorsOf(buildWaxTheme(artworkGlow: false));
      // The wash and the grain are the light theme's material and the
      // backdrop's anti-banding noise; neither is the glow, and a
      // copyWith that dropped one would take them with it.
      expect(off.washOpacity, on.washOpacity);
      expect(off.grainOpacity, on.grainOpacity);
      expect(off.canvas, on.canvas);
      expect(off.accent, on.accent);
      expect(off.textPrimary, on.textPrimary);
    });

    test('the two themes do not compare equal, so the theme rebuilds', () {
      expect(
        _colorsOf(buildWaxTheme()) ==
            _colorsOf(buildWaxTheme(artworkGlow: false)),
        isFalse,
      );
    });
  });

  group('a modal sheet on a wide window', () {
    // Written after a review claimed the app's eighteen sheets run edge
    // to edge on a desktop and a first reading of `bottomSheetTheme`
    // agreed - it sets a colour and a shape and no `constraints`. Both
    // were wrong: the resolution order is call site, then theme, then
    // Material 3's own defaults, and M3's default is a 640-wide centred
    // column. So the cap is already there, and what is worth holding is
    // that this theme keeps letting it through: a `constraints:` added
    // to `BottomSheetThemeData` for some other reason would silently
    // un-cap every sheet in the app.
    Future<Size> sheetSize(
      WidgetTester tester, {
      required bool scrolled,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaxTheme(),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      unawaited(
        showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: scrolled,
          builder: (_) =>
              SizedBox(key: key, width: double.infinity, height: 200),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(key));
    }

    testWidgets('stays a column rather than stretching', (tester) async {
      expect((await sheetSize(tester, scrolled: false)).width, 640);
    });

    testWidgets('stays a column when it is scroll-controlled too', (
      tester,
    ) async {
      // Ten of the eighteen pass `isScrollControlled`, which moves the
      // height ceiling and not the width.
      expect((await sheetSize(tester, scrolled: true)).width, 640);
    });
  });
}
