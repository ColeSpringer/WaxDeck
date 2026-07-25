import 'package:flutter/material.dart';

/// Duration and curve tokens, with reduced motion handled once here
/// rather than by per-callsite discipline.
///
/// Motion is purposeful, quick, and mostly spatial: one orchestrated hero
/// (the deck expanding into the full player) and everything else in
/// support. Read the set for the current context with [WaxMotion.of];
/// when the platform asks for reduced motion, every duration collapses to
/// a short fade, the VU needle and row bars freeze, and spins stop.
@immutable
class WaxMotion {
  const WaxMotion({
    required this.pressFeedback,
    required this.quick,
    required this.standard,
    required this.container,
    required this.screen,
    required this.deckExpand,
    required this.artworkCrossfade,
    required this.animationsEnabled,
  });

  /// Press and hover states, needle ticks.
  final Duration pressFeedback;

  /// Chips, toggles, icon weight flips.
  final Duration quick;

  /// Card changes, crossfades, star pops.
  final Duration standard;

  /// Sheets, side panels, dialogs.
  final Duration container;

  /// Route transitions.
  final Duration screen;

  /// Deck bar expanding into the full player. Tap only: a drag tracks the
  /// finger 1:1 and releases into a velocity-carrying spring, which is
  /// physics, not a duration.
  final Duration deckExpand;

  /// Backdrop glow crossfade when the track changes. Never a snap.
  final Duration artworkCrossfade;

  /// False when the platform asks for reduced motion. Widgets that
  /// animate continuously (the needle, the platter ring, marquees that
  /// do not exist) check this and hold a static pose instead.
  final bool animationsEnabled;

  /// Emphasized: the house curve for anything spatial.
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve decelerate = Curves.easeOutCubic;
  static const Curve easeOut = Curves.easeOut;

  static const WaxMotion full = WaxMotion(
    pressFeedback: Duration(milliseconds: 80),
    quick: Duration(milliseconds: 140),
    standard: Duration(milliseconds: 220),
    container: Duration(milliseconds: 320),
    screen: Duration(milliseconds: 360),
    deckExpand: Duration(milliseconds: 420),
    artworkCrossfade: Duration(milliseconds: 350),
    animationsEnabled: true,
  );

  /// Everything clamps to one short fade; nothing moves through space.
  static const WaxMotion reduced = WaxMotion(
    pressFeedback: Duration(milliseconds: 80),
    quick: Duration(milliseconds: 80),
    standard: Duration(milliseconds: 80),
    container: Duration(milliseconds: 80),
    screen: Duration(milliseconds: 80),
    deckExpand: Duration(milliseconds: 80),
    artworkCrossfade: Duration(milliseconds: 80),
    animationsEnabled: false,
  );

  static WaxMotion of(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? reduced : full;
}
