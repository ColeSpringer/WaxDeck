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

  /// Value equality, and it is load-bearing rather than tidy.
  ///
  /// A surface with no artwork colour builds its fallback fresh on every
  /// rebuild, and the animation that carries a palette change compares
  /// its target against the one it is already heading for. Without this
  /// every rebuild is a different object, so a play/pause - or anything
  /// else that touches the player - restarts a 350 ms crossfade between
  /// two identical colours.
  @override
  bool operator ==(Object other) =>
      other is WaxPalette &&
      other.glow == glow &&
      other.wash == wash &&
      other.isFallback == isFallback;

  @override
  int get hashCode => Object.hash(glow, wash, isFallback);

  static WaxPalette? lerp(WaxPalette? a, WaxPalette? b, double t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    return WaxPalette(
      glow: Color.lerp(a.glow, b.glow, t)!,
      wash: Color.lerp(a.wash, b.wash, t)!,
      isFallback: t < 0.5 ? a.isFallback : b.isFallback,
    );
  }
}

/// Drives a palette change as a crossfade rather than a cut.
///
/// The colour under a player is the loudest thing on the screen, and a
/// track change that snapped it would read as a flash. For
/// `TweenAnimationBuilder`, which is what an artwork accent is animated
/// with: the surface asks for the new palette and this gets it there.
class WaxPaletteTween extends Tween<WaxPalette> {
  WaxPaletteTween({super.begin, super.end});

  @override
  WaxPalette lerp(double t) => WaxPalette.lerp(begin, end, t)!;
}
