import 'package:flutter/widgets.dart';

/// The corner scale.
///
/// Radius carries hierarchy: the bigger the surface, the softer the
/// corner. Artwork keeps its own pair (thumbnails and player heroes) so
/// covers never look like buttons.
abstract final class WaxRadius {
  /// Chips and small controls.
  static const double r6 = 6;

  /// Artwork thumbnails and inputs.
  static const double r10 = 10;

  /// Cards and menus.
  static const double r14 = 14;

  /// Sheets and dialogs.
  static const double r20 = 20;

  /// Pills and circles.
  static const double full = 999;

  /// Player artwork: compact deck slot and expanded hero.
  static const double artCompact = 14;
  static const double artHero = 18;

  static const BorderRadius chip = BorderRadius.all(Radius.circular(r6));
  static const BorderRadius thumb = BorderRadius.all(Radius.circular(r10));
  static const BorderRadius card = BorderRadius.all(Radius.circular(r14));
  static const BorderRadius sheet = BorderRadius.all(Radius.circular(r20));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(artHero));

  /// Sheets open upward: only the top corners round.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(r20),
  );
}
