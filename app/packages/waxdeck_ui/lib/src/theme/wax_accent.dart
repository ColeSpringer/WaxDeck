import 'package:flutter/material.dart';

import '../color/palette.dart';
import '../tokens/colors.dart';

/// Carries the current artwork's palette down the tree.
///
/// Players and entity headers read it for backdrops and glows. Nothing
/// reads it for text or icon colour: the brand amber marks what you can
/// do, and artwork stays atmosphere. Where no palette is in scope, the
/// domain's own hue answers instead, so a fallback is always available
/// and callers never branch on null.
class WaxAccent extends InheritedWidget {
  const WaxAccent({
    required this.palette,
    required super.child,
    this.domain = WaxDomain.music,
    super.key,
  });

  final WaxPalette palette;

  /// The domain whose hue backs this subtree when the palette is a
  /// fallback.
  final WaxDomain domain;

  static WaxPalette of(BuildContext context) {
    final accent = context.dependOnInheritedWidgetOfExactType<WaxAccent>();
    if (accent != null) return accent.palette;
    return WaxPalette.forDomain(WaxColors.of(context), WaxDomain.music);
  }

  /// The domain in scope, which tints glyphs and mode badges inside a
  /// domain's own content surfaces (never the shell chrome).
  static WaxDomain domainOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WaxAccent>()?.domain ??
      WaxDomain.music;

  @override
  bool updateShouldNotify(WaxAccent oldWidget) =>
      oldWidget.palette != palette || oldWidget.domain != domain;
}
