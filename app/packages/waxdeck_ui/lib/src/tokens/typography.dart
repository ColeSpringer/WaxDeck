import 'package:flutter/material.dart';

import '../fonts/wax_fonts.dart';

/// The type scale.
///
/// Three faces carry three jobs: Archivo is the identity face (record
/// sleeve DNA, expanded width for titles), Inter is the workhorse for
/// everything you read or click, and Spline Sans Mono is the readout
/// voice of the app: timecodes, codec chips, ids, logs. Technical detail
/// set in mono is how the power-user channel stays legible without the
/// first layer paying for it.
///
/// The non-standard weights (460, 520, 560, 620, 640) and Archivo's width
/// axis are unreachable through [FontWeight]'s 100-step ladder, so every
/// token sets [TextStyle.fontVariations]. The nearest [FontWeight] rides
/// along for fallback faces and for any platform that ignores axes;
/// `test/typography_test.dart` proves the axes actually render rather
/// than silently snapping to the nearest static weight.
///
/// Every token sets `decoration: TextDecoration.none`: a null one
/// merges in the ambient default, which outside a Material is the
/// yellow double-underlined error style.
abstract final class WaxType {
  /// Archivo's width axis: 100 is normal, 125 is the expanded cut used
  /// for the wordmark, screen titles, and hub headers.
  static const double _expanded = 125;

  static TextStyle _archivo({
    required double size,
    required double height,
    required double weight,
    double width = 100,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: WaxFonts.display,
    fontFamilyFallback: WaxFonts.fallbacks,
    package: WaxFonts.package,
    fontSize: size,
    height: height / size,
    letterSpacing: letterSpacing,
    fontWeight: _nearest(weight),
    decoration: TextDecoration.none,
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
    ],
  );

  static TextStyle _inter({
    required double size,
    required double height,
    required double weight,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: WaxFonts.ui,
    fontFamilyFallback: WaxFonts.fallbacks,
    package: WaxFonts.package,
    fontSize: size,
    height: height / size,
    letterSpacing: letterSpacing,
    fontWeight: _nearest(weight),
    decoration: TextDecoration.none,
    fontVariations: [
      FontVariation('wght', weight),
      // Inter's optical-size axis spans 14 to 32: track the rendered
      // size so small text keeps its apertures and large text tightens.
      FontVariation('opsz', size.clamp(14, 32)),
    ],
    // Any column of numbers lines up; this is cheap here and impossible
    // to retrofit once tables and timecodes exist.
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle _mono({
    required double size,
    required double height,
    required double weight,
  }) => TextStyle(
    fontFamily: WaxFonts.mono,
    fontFamilyFallback: WaxFonts.fallbacks,
    package: WaxFonts.package,
    fontSize: size,
    height: height / size,
    fontWeight: _nearest(weight),
    decoration: TextDecoration.none,
    fontVariations: [FontVariation('wght', weight)],
    fontFeatures: const [
      FontFeature.tabularFigures(),
      // Readouts are data, not prose: ligatures would fuse "->" and
      // "01:10" glyph pairs that must stay countable.
      FontFeature.disable('liga'),
      FontFeature.disable('clig'),
    ],
  );

  static FontWeight _nearest(double weight) =>
      FontWeight.values[((weight / 100).round().clamp(1, 9)) - 1];

  /// Hub headers and year-in-review numerals.
  static final TextStyle display = _archivo(
    size: 30,
    height: 36,
    weight: 640,
    width: _expanded,
  );

  /// Screen titles.
  static final TextStyle titleScreen = _archivo(
    size: 24,
    height: 30,
    weight: 640,
    width: _expanded,
  );

  /// Screen titles at [WaxSizeClass.expanded] and wider.
  static final TextStyle titleScreenDesktop = _archivo(
    size: 26,
    height: 32,
    weight: 640,
    width: _expanded,
  );

  /// Entity names on detail headers: album, artist, book, show.
  static final TextStyle titleEntity = _archivo(
    size: 21,
    height: 27,
    weight: 600,
  );

  /// Dialog titles and large section heads.
  static final TextStyle headline = _archivo(size: 18, height: 24, weight: 600);

  /// Card and list titles.
  static final TextStyle titleItem = _inter(
    size: 15.5,
    height: 21,
    weight: 600,
  );

  /// Default text.
  static final TextStyle body = _inter(size: 14, height: 20, weight: 460);

  /// Dense lists and descriptions.
  static final TextStyle bodySmall = _inter(size: 13, height: 18, weight: 460);

  /// Buttons, tabs, chips.
  static final TextStyle label = _inter(size: 13, height: 16, weight: 560);

  /// Metadata lines and timestamps.
  static final TextStyle caption = _inter(size: 11.5, height: 15, weight: 460);

  /// Eyebrows: shelf labels and section kickers. Rendered all caps by
  /// the component, not by the token (screen readers should still hear
  /// the words, so the string itself stays sentence case).
  static final TextStyle overline = _inter(
    size: 11,
    height: 14,
    weight: 620,
    letterSpacing: 0.6,
  );

  /// Elapsed and total time.
  static final TextStyle monoTime = _mono(size: 13, height: 16, weight: 520);

  /// Codec chips, ids, logs, admin diagnostics.
  static final TextStyle monoData = _mono(size: 12, height: 16, weight: 460);

  /// The Material text theme the tokens map onto, so any stray Material
  /// widget inherits the house type instead of Roboto.
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
    displayLarge: display.copyWith(color: primary),
    displayMedium: display.copyWith(color: primary),
    displaySmall: titleScreen.copyWith(color: primary),
    headlineLarge: titleScreen.copyWith(color: primary),
    headlineMedium: titleEntity.copyWith(color: primary),
    headlineSmall: headline.copyWith(color: primary),
    titleLarge: titleEntity.copyWith(color: primary),
    titleMedium: titleItem.copyWith(color: primary),
    titleSmall: label.copyWith(color: primary),
    bodyLarge: body.copyWith(color: primary),
    bodyMedium: body.copyWith(color: primary),
    bodySmall: bodySmall.copyWith(color: secondary),
    labelLarge: label.copyWith(color: primary),
    labelMedium: label.copyWith(color: secondary),
    labelSmall: caption.copyWith(color: secondary),
  );
}
