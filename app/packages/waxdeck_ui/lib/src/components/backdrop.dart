import 'package:flutter/material.dart';

import '../color/contrast.dart';
import '../color/palette.dart';
import '../theme/wax_accent.dart';
import '../tokens/colors.dart';

/// The artwork-derived backdrop behind players and entity headers.
///
/// The rule the whole colour system rests on: extracted colour is
/// atmosphere, never meaning. So this draws canvas, then the artwork
/// colour, then a scrim computed to keep primary text at 4.5:1, and text
/// on top uses ordinary text tokens.
///
/// Dark renders warmth as light (a radial glow, plus grain so the deep
/// gradient does not band). Light renders it as material: the same
/// colour mixed into the canvas as a tinted paper stock, flat, no glow,
/// no grain. Both are the same identity, not a dimmed version of one
/// another.
class WaxBackdrop extends StatelessWidget {
  const WaxBackdrop({
    required this.child,
    this.palette,
    this.domain = WaxDomain.music,
    this.grain = true,
    super.key,
  });

  final Widget child;

  /// Defaults to the palette in scope, which falls back to the domain
  /// hue when artwork has no usable colour.
  final WaxPalette? palette;

  final WaxDomain domain;

  /// The tiled noise, on by default for the player backdrop: it is the
  /// one surface that carries it, where it prevents banding in the glow
  /// and reads as analogue warmth.
  final bool grain;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final resolved = palette ?? WaxAccent.of(context);

    final scrimAlpha = WaxContrast.scrimAlphaFor(
      text: colors.textPrimary,
      backdrop: WaxContrast.flatten(
        resolved.glow.withValues(alpha: colors.glowOpacity),
        colors.canvas,
      ),
      scrim: colors.scrim.withValues(alpha: 1),
    );

    // A DecoratedBox and not an AnimatedContainer: the colour arriving
    // here has already been tweened over exactly this duration by
    // whoever put the palette in scope, and an implicit animation
    // re-targets on every rebuild - so a second one over the same
    // duration chases a moving target and never lands, which is the long
    // mushy fade a track change draws in light mode. Dark never showed
    // it, its container colour being the constant canvas.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.isDark
            ? colors.canvas
            : WaxContrast.flatten(
                resolved.wash.withValues(alpha: colors.washOpacity),
                colors.canvas,
              ),
      ),
      // The content is the stack's sizing child and every wash is
      // positioned against it: an entity header sits in a scroll view
      // with unbounded height, where an expanded stack cannot lay out.
      child: Stack(
        children: <Widget>[
          if (colors.isDark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 1.1,
                    colors: <Color>[
                      resolved.glow.withValues(alpha: colors.glowOpacity),
                      resolved.glow.withValues(
                        alpha: colors.glowOpacity * 0.25,
                      ),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, 0.55, 1],
                  ),
                ),
              ),
            ),
          if (colors.isDark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // scrimAlphaFor computed this against the opaque scrim
                  // colour, so it is the alpha to draw: folding the
                  // token's own 55 percent in on top would cap the scrim
                  // below what the contrast clamp asked for, exactly in
                  // the blown-out-artwork case it exists for.
                  color: colors.scrim.withValues(alpha: scrimAlpha),
                ),
              ),
            ),
          if (grain && colors.grainOpacity > 0)
            Positioned.fill(
              child: Opacity(
                opacity: colors.grainOpacity,
                child: const _Grain(),
              ),
            ),
          // The colour tween runs a repaint of this stack per frame for
          // the length of a track change. Behind a boundary the artwork,
          // the title block and the transport are not redrawn with it -
          // only the washes above, which is all that is changing.
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}

/// One small tiled asset, never a runtime shader cost.
class _Grain extends StatelessWidget {
  const _Grain();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/brand/grain.png', package: 'waxdeck_ui'),
        repeat: ImageRepeat.repeat,
        filterQuality: FilterQuality.none,
      ),
    ),
  );
}
