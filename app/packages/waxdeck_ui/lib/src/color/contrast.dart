import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// WCAG 2.1 contrast maths.
///
/// The token set is guarded by a pair matrix in
/// `test/contrast_test.dart`, and the same functions run at runtime where
/// colour is not known ahead of time: an artwork-derived backdrop clamps
/// its scrim with [scrimAlphaFor] until the text on top clears AA.
abstract final class WaxContrast {
  /// Body text and anything below 18 px (or 14 px bold).
  static const double aaText = 4.5;

  /// Large text, icons, and non-text UI components such as borders.
  static const double aaLarge = 3.0;

  /// Relative luminance per WCAG 2.1, ignoring alpha: composite first
  /// with [flatten] if either colour is translucent.
  static double relativeLuminance(Color color) {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// The contrast ratio between two opaque colours, from 1 to 21.
  static double ratio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Composites a translucent [foreground] over an opaque [background].
  static Color flatten(Color foreground, Color background) {
    final a = foreground.a;
    return Color.from(
      alpha: 1,
      red: foreground.r * a + background.r * (1 - a),
      green: foreground.g * a + background.g * (1 - a),
      blue: foreground.b * a + background.b * (1 - a),
    );
  }

  static bool meets(Color foreground, Color background, double target) =>
      ratio(foreground, background) >= target - 0.005;

  /// The smallest scrim alpha that lets [text] clear [target] over
  /// [backdrop].
  ///
  /// Player and header backdrops are canvas, then blurred artwork, then a
  /// scrim: the artwork is arbitrary, so the scrim is computed rather
  /// than guessed. Returns 1.0 when even an opaque scrim of that colour
  /// cannot get there, which is the caller's cue to darken the scrim
  /// colour itself.
  static double scrimAlphaFor({
    required Color text,
    required Color backdrop,
    required Color scrim,
    double target = aaText,
    double step = 0.05,
  }) {
    for (double alpha = 0; alpha <= 1.0001; alpha += step) {
      final composed = flatten(scrim.withValues(alpha: alpha), backdrop);
      if (meets(text, composed, target)) return math.min(alpha, 1);
    }
    return 1;
  }
}
