import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// A colour reading of one piece of artwork.
///
/// Extracted colour is atmosphere only: blurred backdrop washes, radial
/// glows behind artwork, a seek bar's buffer tint. It never becomes text,
/// icons, or any colour that carries meaning, which is why this type
/// exposes no "on" colours to be misused as foregrounds.
///
/// The extraction itself (bytes to palette, off the UI thread, LRU
/// cached) rides the artwork pipeline; this is the value it produces and
/// the fallback every surface uses until it arrives.
@immutable
class WaxPalette {
  const WaxPalette({
    required this.glow,
    required this.wash,
    required this.isFallback,
  });

  /// The radial glow behind a player hero, used at the theme's
  /// `glowOpacity`.
  final Color glow;

  /// The flat tint an entity header or a light-mode player backdrop mixes
  /// into the canvas, used at the theme's `washOpacity`.
  final Color wash;

  /// True when this came from a domain hue rather than from artwork: no
  /// art, or no usable palette in it.
  final bool isFallback;

  /// The fallback every surface starts from: the domain's own hue.
  factory WaxPalette.forDomain(WaxColors colors, WaxDomain domain) {
    final hue = colors.domain(domain).hue;
    return WaxPalette(glow: hue, wash: hue, isFallback: true);
  }

  static WaxPalette? lerp(WaxPalette? a, WaxPalette? b, double t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    return WaxPalette(
      glow: Color.lerp(a.glow, b.glow, t)!,
      wash: Color.lerp(a.wash, b.wash, t)!,
      isFallback: t < 0.5 ? a.isFallback : b.isFallback,
    );
  }
}
