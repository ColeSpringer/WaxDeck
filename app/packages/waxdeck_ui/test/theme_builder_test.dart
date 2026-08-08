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
}
