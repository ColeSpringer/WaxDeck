import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'wax_layout.dart';

/// Which of the three themes to build.
enum WaxThemeVariant {
  dark,
  light,

  /// True black for OLED panels: a substitution variant of dark, not a
  /// third hand-maintained palette.
  oled;

  WaxColors get colors => switch (this) {
    WaxThemeVariant.dark => WaxColors.dark,
    WaxThemeVariant.light => WaxColors.light,
    WaxThemeVariant.oled => WaxColors.oled,
  };

  Brightness get brightness =>
      this == WaxThemeVariant.light ? Brightness.light : Brightness.dark;
}

/// Builds the app theme from the tokens.
///
/// Material still renders the primitives underneath WaxDeck's components,
/// so the token set is mapped onto [ColorScheme] and the component themes
/// as well as onto the [WaxColors] and [WaxLayout] extensions. A stray
/// Material widget then inherits the house look instead of Roboto on
/// purple, and the components on top read their tokens directly.
ThemeData buildWaxTheme({
  WaxThemeVariant variant = WaxThemeVariant.dark,
  WaxDensity density = WaxDensity.comfortable,
}) {
  final colors = variant.colors;
  final layout = WaxLayout.forDensity(density);
  final text = WaxType.textTheme(colors.textPrimary, colors.textSecondary);

  final scheme = ColorScheme(
    brightness: variant.brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.accentContainer,
    onPrimaryContainer: colors.onAccentContainer,
    secondary: colors.accent,
    onSecondary: colors.onAccent,
    secondaryContainer: colors.accentContainer,
    onSecondaryContainer: colors.onAccentContainer,
    tertiary: colors.podcasts.hue,
    onTertiary: colors.onAccent,
    tertiaryContainer: colors.podcasts.container,
    onTertiaryContainer: colors.podcasts.onContainer,
    error: colors.error,
    onError: colors.onError,
    errorContainer: colors.error.withValues(alpha: 0.16),
    onErrorContainer: colors.error,
    surface: colors.canvas,
    onSurface: colors.textPrimary,
    surfaceContainerLowest: colors.canvas,
    surfaceContainerLow: colors.surface1,
    surfaceContainer: colors.surface1,
    surfaceContainerHigh: colors.surface2,
    surfaceContainerHighest: colors.surface3,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.outline,
    outlineVariant: colors.hairline,
    shadow: const Color(0xFF000000),
    scrim: colors.scrim,
    inverseSurface: colors.textPrimary,
    onInverseSurface: colors.canvas,
    inversePrimary: colors.accentContainer,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: variant.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.canvas,
    canvasColor: colors.canvas,
    dividerColor: colors.hairline,
    textTheme: text,
    primaryTextTheme: text,
    extensions: <ThemeExtension<dynamic>>[colors, layout],
    // Density is WaxDeck's own setting; Material's visual density stays
    // standard so its metrics do not compound with ours.
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: IconThemeData(color: colors.textSecondary, size: 20),
    primaryIconTheme: IconThemeData(color: colors.textPrimary, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: WaxType.titleScreen.copyWith(color: colors.textPrimary),
      iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
    ),
    cardTheme: CardThemeData(
      color: colors.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.card),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface3,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.sheet),
      titleTextStyle: WaxType.headline.copyWith(color: colors.textPrimary),
      contentTextStyle: WaxType.body.copyWith(color: colors.textSecondary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface2,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: colors.scrim,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.sheetTop),
      showDragHandle: true,
      dragHandleColor: colors.textTertiary,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.card),
      textStyle: WaxType.body.copyWith(color: colors.textPrimary),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(colors.surface2),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: WaxRadius.card),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surface3,
        borderRadius: WaxRadius.chip,
        border: Border.all(color: colors.hairline),
      ),
      textStyle: WaxType.caption.copyWith(color: colors.textPrimary),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: DividerThemeData(
      color: colors.hairline,
      space: 1,
      thickness: layout.hairlineWidth,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.textSecondary,
      textColor: colors.textPrimary,
      titleTextStyle: WaxType.titleItem.copyWith(color: colors.textPrimary),
      subtitleTextStyle: WaxType.caption.copyWith(color: colors.textSecondary),
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.thumb),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface2,
      selectedColor: colors.accentContainer,
      disabledColor: colors.surface2,
      labelStyle: WaxType.label.copyWith(color: colors.textPrimary),
      secondaryLabelStyle: WaxType.label.copyWith(
        color: colors.onAccentContainer,
      ),
      side: BorderSide(color: colors.hairline),
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.chip),
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s8,
        vertical: WaxSpace.s4,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.hairline,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.hairline,
      circularTrackColor: colors.hairline,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onAccent
            : colors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.surface3,
      ),
      trackOutlineColor: WidgetStatePropertyAll<Color>(colors.outline),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll<Color>(colors.onAccent),
      side: BorderSide(color: colors.outline, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.outline,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface2,
      hintStyle: WaxType.body.copyWith(color: colors.textTertiary),
      labelStyle: WaxType.label.copyWith(color: colors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s12,
        vertical: WaxSpace.s12,
      ),
      border: OutlineInputBorder(
        borderRadius: WaxRadius.thumb,
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: WaxRadius.thumb,
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: WaxRadius.thumb,
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: WaxRadius.thumb,
        borderSide: BorderSide(color: colors.error),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface3,
      contentTextStyle: WaxType.body.copyWith(color: colors.textPrimary),
      actionTextColor: colors.accent,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: WaxRadius.card),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        colors.textTertiary.withValues(alpha: 0.5),
      ),
      radius: const Radius.circular(WaxRadius.r6),
      thickness: const WidgetStatePropertyAll<double>(8),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: 0.32),
      selectionHandleColor: colors.accent,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
