import 'package:flutter/material.dart';

/// Elevation, expressed differently per brightness.
///
/// In dark, the surface ladder does the work and shadows are nearly
/// absent: a glow-free charcoal stack reads its own depth. In light,
/// depth is print: soft shadows plus hairline strokes. Shadows are never
/// coloured.
abstract final class WaxElevation {
  static const List<BoxShadow> none = <BoxShadow>[];

  /// Cards in light mode. Dark mode cards get [none] and rely on the
  /// surface step instead.
  static const List<BoxShadow> cardLight = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 4),
  ];

  static const List<BoxShadow> menuDark = <BoxShadow>[
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
  ];

  static const List<BoxShadow> sheetLight = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 8), blurRadius: 28),
  ];

  /// The shadow a card carries at this brightness.
  static List<BoxShadow> card(Brightness brightness) =>
      brightness == Brightness.light ? cardLight : none;

  /// The shadow a menu, dialog, or sheet carries at this brightness.
  static List<BoxShadow> overlay(Brightness brightness) =>
      brightness == Brightness.light ? sheetLight : menuDark;
}
