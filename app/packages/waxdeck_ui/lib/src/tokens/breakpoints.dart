import 'package:flutter/widgets.dart';

import 'spacing.dart';

/// Window width classes. Every adaptive decision keys off the class, not
/// off a raw pixel check buried in a widget.
///
/// The measure is the app window, not the device: a narrow desktop window
/// is compact, and it should behave like one.
enum WaxSizeClass {
  /// Under 600: bottom tabs, deck bar above them, details push.
  compact,

  /// 600 to 839: icon rail, full-width deck bar, details push.
  medium,

  /// 840 to 1199: sidebar, details swap the content pane, panels overlay.
  expanded,

  /// 1200 and up: sidebar plus a docked right panel.
  wide;

  static WaxSizeClass fromWidth(double width) {
    if (width < 600) return WaxSizeClass.compact;
    if (width < 840) return WaxSizeClass.medium;
    if (width < 1200) return WaxSizeClass.expanded;
    return WaxSizeClass.wide;
  }

  /// Reads the class from the nearest [MediaQuery]. The app also exposes
  /// this through a provider so controllers can key off it without a
  /// build context.
  static WaxSizeClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WaxSizeClass.compact;

  /// Whether the shell shows a sidebar with text labels rather than
  /// bottom tabs or an icon rail.
  bool get hasSidebar => index >= WaxSizeClass.expanded.index;

  /// Whether details replace the content pane instead of pushing a route.
  bool get swapsPane => hasSidebar;

  /// Whether the right panel can dock beside the content.
  bool get docksPanel => this == WaxSizeClass.wide;

  EdgeInsets get gutter => switch (this) {
    WaxSizeClass.compact => WaxSpace.gutterCompact,
    WaxSizeClass.medium => WaxSpace.gutterMedium,
    WaxSizeClass.expanded || WaxSizeClass.wide => WaxSpace.gutterExpanded,
  };

  /// Base max cross-axis extent for artwork grids, before the user's
  /// grid-size setting scales it.
  double get gridExtent => switch (this) {
    WaxSizeClass.compact => 168,
    WaxSizeClass.medium => 176,
    WaxSizeClass.expanded || WaxSizeClass.wide => 184,
  };
}

/// Shell metrics that are fixed by the layout system rather than by
/// density or theme.
abstract final class WaxShellMetrics {
  static const double sidebarWidth = 248;
  static const double railWidth = 72;
  static const double rightPanelWidth = 360;
  static const double deckBarCompactHeight = 64;
  static const double deckBarExpandedHeight = 88;

  /// Artwork grids keep fixed cell extents for scroll performance.
  static const double gridGap = 12;
}
