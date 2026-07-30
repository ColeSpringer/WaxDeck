import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/typography.dart';
import 'view_data.dart';

/// Artwork with its placeholder, its shape, and its resume ring.
///
/// Artwork is the hero surface of the whole design, so it gets one
/// component: every grid cell, row, header, and player hero draws through
/// here and inherits the same fit rules, radius, fade-in, and monogram
/// fallback.
///
/// This is also where the one thing only the widget knows is measured:
/// how many physical pixels the artwork will actually occupy. It asks
/// the caller's [WaxArtwork] for exactly that many, and what comes back
/// is the app's business - which stored size to fetch, what to decode at,
/// where the bytes are cached. A caller that animates [size] re-asks as
/// it animates, so animate the box (a scale, a hero flight), not this.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    required this.size,
    this.artwork,
    this.monogram,
    this.shape = ArtworkShape.square,
    this.domain = WaxDomain.music,
    this.progress,
    this.dimmed = false,
    this.semanticLabel,
    super.key,
  });

  /// The cross-axis extent. Portrait art is fitted inside a square of
  /// this size on a matte, so a mixed grid stays on one baseline.
  final double size;

  final WaxArtwork? artwork;

  /// Drawn when there is no artwork: the first letters of the title, over
  /// a domain-tinted tile. A missing cover is a real state, not a loading
  /// one, so it gets a designed answer rather than a spinner.
  final String? monogram;

  final ArtworkShape shape;
  final WaxDomain domain;

  /// Resume progress from 0 to 1, drawn as a ring around the artwork.
  final double? progress;

  /// Content that is not on the device while offline.
  final bool dimmed;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final radius = switch (shape) {
      ArtworkShape.circle => WaxRadius.full,
      ArtworkShape.portrait ||
      ArtworkShape.square => size >= 160 ? WaxRadius.artHero : WaxRadius.r10,
    };

    // The size the caller is asked for is the size that will be painted:
    // logical extent times this display's pixel ratio, rounded up so a
    // fractional grid extent never asks for less than it draws.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final image = artwork?.call((size * ratio).ceil());

    Widget content;
    if (image == null) {
      content = _Monogram(
        monogram: monogram,
        domain: domain,
        size: size,
        colors: colors,
      );
    } else {
      content = Image(
        image: image,
        fit: shape == ArtworkShape.portrait ? BoxFit.contain : BoxFit.cover,
        width: size,
        height: size,
        frameBuilder: (context, child, frame, wasSync) {
          // The child is always built and its opacity animates when the
          // first frame lands. Returning an opaque AnimatedOpacity only
          // once the frame arrives builds it at its target value, which
          // is a fade that never runs.
          if (wasSync) return child;
          // The matte behind this is already the container's, so the
          // fade needs no fill of its own: adding one repaints the
          // clipped corners a shade differently.
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: motion.standard,
            curve: WaxMotion.emphasized,
            child: child,
          );
        },
        errorBuilder: (context, _, _) => _Monogram(
          monogram: monogram,
          domain: domain,
          size: size,
          colors: colors,
        ),
      );
    }

    Widget art = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Portrait covers sit on a quiet matte so a tall cover and a
        // square one can share a row without either being cropped.
        color: colors.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (dimmed) {
      art = Opacity(opacity: 0.55, child: art);
    }

    if (progress != null) {
      // Shape decides the affordance: a ring belongs on a circular
      // station logo, where it traces the edge, but on a square cover it
      // reads as a hoop thrown over the artwork. Rectangles get the
      // hairline the deck bar uses, along the bottom edge.
      art = shape == ArtworkShape.circle
          ? ProgressRing(
              progress: progress!,
              size: size,
              thickness: math.max(2, size * 0.03),
              child: art,
            )
          : Stack(
              children: <Widget>[
                art,
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(radius),
                    ),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1),
                      minHeight: math.max(3, size * 0.02),
                      backgroundColor: colors.scrim.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                    ),
                  ),
                ),
              ],
            );
    }

    if (semanticLabel != null) {
      return Semantics(image: true, label: semanticLabel, child: art);
    }
    // Artwork beside a title says nothing a screen reader needs twice.
    return ExcludeSemantics(child: art);
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.monogram,
    required this.domain,
    required this.size,
    required this.colors,
  });

  final String? monogram;
  final WaxDomain domain;
  final double size;
  final WaxColors colors;

  @override
  Widget build(BuildContext context) {
    final hue = colors.domain(domain);
    final letters = (monogram ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();

    // A title of "..." or "100%" yields punctuation or nothing at all, so
    // initials are used only when they are actually letters or digits;
    // otherwise the domain's own glyph stands in, which is at least true.
    final usable = RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(letters);

    return DecoratedBox(
      decoration: BoxDecoration(color: hue.container),
      child: Center(
        child: usable
            ? Text(
                letters,
                style: WaxType.titleEntity.copyWith(
                  color: hue.onContainer,
                  fontSize: math.max(11, size * 0.3),
                ),
              )
            : WaxIcon(
                switch (domain) {
                  WaxDomain.music => WaxIcons.music,
                  WaxDomain.podcasts => WaxIcons.podcasts,
                  WaxDomain.audiobooks => WaxIcons.audiobooks,
                  WaxDomain.radio => WaxIcons.radio,
                },
                size: math.max(12, size * 0.32),
                color: hue.onContainer,
              ),
      ),
    );
  }
}

/// A thin progress arc around artwork: how far into a book, an episode, a
/// half-heard album you are.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.progress,
    required this.size,
    this.thickness = 3,
    this.child,
    super.key,
  });

  final double progress;
  final double size;
  final double thickness;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        foregroundPainter: _RingPainter(
          progress: progress.clamp(0, 1),
          thickness: thickness,
          track: colors.scrim.withValues(alpha: 0.45),
          fill: colors.accent,
        ),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.thickness,
    required this.track,
    required this.fill,
  });

  final double progress;
  final double thickness;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(thickness / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      inset,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = track,
    );
    canvas.drawArc(
      inset,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}
