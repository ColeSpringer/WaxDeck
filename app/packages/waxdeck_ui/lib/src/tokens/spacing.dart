import 'package:flutter/widgets.dart';

/// The spacing scale.
///
/// Everything measurable steps through these values. Screen gutters and
/// the reading-column cap are size-class decisions and live on
/// `WaxLayout`; this is the raw ladder components build from.
abstract final class WaxSpace {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  /// Single-column reading contexts (settings, episode notes) never run
  /// wider than this, however wide the window is.
  static const double readingWidth = 720;

  /// Minimum interactive size on touch. Density never reduces it.
  static const double touchTarget = 44;

  /// Minimum interactive size on pointer-dense surfaces (desktop lists).
  static const double pointerTarget = 32;

  static const EdgeInsets gutterCompact = EdgeInsets.symmetric(horizontal: s16);
  static const EdgeInsets gutterMedium = EdgeInsets.symmetric(horizontal: s24);
  static const EdgeInsets gutterExpanded = EdgeInsets.symmetric(
    horizontal: s32,
  );
}
