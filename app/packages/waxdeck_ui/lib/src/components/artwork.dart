import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';
import 'prose.dart';
import 'secondary_tap.dart';
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
    this.placeholder = ArtworkPlaceholder.initials,
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

  /// Drawn when there is no artwork: the title the placeholder is built
  /// from. A missing cover is a real state, not a loading one, so it gets
  /// a designed answer rather than a spinner.
  final String? monogram;

  /// How that answer is drawn. See [ArtworkPlaceholder].
  final ArtworkPlaceholder placeholder;

  final ArtworkShape shape;
  final WaxDomain domain;

  /// Resume progress from 0 to 1, drawn as a ring around the artwork.
  final double? progress;

  /// Content that is not on the device while offline.
  final bool dimmed;

  final String? semanticLabel;

  /// The corner a picture of [size] is drawn with, for what outlines one.
  static double cornerRadius(ArtworkShape shape, double size) =>
      switch (shape) {
        ArtworkShape.circle => WaxRadius.full,
        ArtworkShape.portrait ||
        ArtworkShape.square => size >= 160 ? WaxRadius.artHero : WaxRadius.r10,
      };

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final radius = cornerRadius(shape, size);

    // The size the caller is asked for is the size that will be painted:
    // logical extent times this display's pixel ratio, rounded up so a
    // fractional grid extent never asks for less than it draws.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final image = artwork?.call((size * ratio).ceil());

    Widget fallback() => _Placeholder(
      monogram: monogram,
      kind: placeholder,
      domain: domain,
      size: size,
      colors: colors,
    );

    Widget content;
    if (image == null) {
      content = fallback();
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
        errorBuilder: (context, _, _) => fallback(),
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

    return semanticLabel != null
        ? Semantics(image: true, label: semanticLabel, child: art)
        // Artwork beside a title says nothing a screen reader needs twice.
        : ExcludeSemantics(child: art);
  }
}

/// The shade a cover takes while it offers to play: paint only, so every
/// press goes through it to whatever holds the cover.
///
/// Mounted either way and faded, rather than created on hover, which pops.
class HoverPlayScrim extends StatelessWidget {
  const HoverPlayScrim({
    required this.opacity,
    required this.radius,
    super.key,
  });

  /// The one fade its holder runs for it and the [HoverPlayDisc] alike,
  /// so the two cannot drift.
  final Animation<double> opacity;

  /// The cover's corner.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return IgnorePointer(
      child: FadeTransition(
        opacity: opacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          // Not overly intrusive: enough to say the cover is a control,
          // and little enough that the artwork is still the thing being
          // looked at.
          child: ColoredBox(color: colors.scrim.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

/// The play disc over a cover: the disc is the button, so what is drawn,
/// what takes the press and the semantics node are one 60 px square
/// around one circle.
///
/// Mounted either way and faded. While hidden it takes no pointer and
/// has no node, so a press on the cover reaches the cover's holder; it
/// stays a tab stop, so the keyboard reaches it from either side, and
/// its holder reveals it on that focus.
class HoverPlayDisc extends StatelessWidget {
  const HoverPlayDisc({
    required this.visible,
    required this.opacity,
    required this.onPlay,
    required this.label,
    this.semanticsId,
    this.onSecondaryTap,
    super.key,
  });

  /// The disc's edge: a touch target and the chip's breathing room
  /// around the glyph.
  static const double size = WaxSpace.touchTarget + 2 * WaxSpace.s8;

  /// Whether it is shown: a hidden disc takes no pointer and has no node,
  /// even while it is still fading out.
  final bool visible;

  /// The fade its holder runs for it and the [HoverPlayScrim] alike.
  final Animation<double> opacity;

  final VoidCallback onPlay;

  /// The control's spoken name, and its tooltip.
  final String label;

  /// The disc's own identifier.
  final String? semanticsId;

  /// A right click on the disc, for a host whose cover answers one: the
  /// disc sits over that cover and would otherwise take the click away.
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    Widget disc = WaxTappable(
      label: label,
      tooltip: label,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      onPressed: onPlay,
      child: DecoratedBox(
        // On an opaque chip, on a tested surface pair, for the reason the
        // card's badge is: the scrim is translucent, so a glyph in the text
        // colour composites to ink on ink over a dark cover in light mode
        // and disappears.
        decoration: BoxDecoration(
          color: colors.surface1,
          shape: BoxShape.circle,
        ),
        // The disc's own ink, drawn over its ground rather than under it,
        // wherever the disc stands.
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onPlay,
            // The whole square presses, corners too: its semantics node is
            // that square, and a web click there is the node's tap. The ink
            // keeps to the circle.
            highlightShape: BoxShape.circle,
            customBorder: const CircleBorder(),
            containedInkWell: true,
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: WaxIcon(
                  WaxIcons.play,
                  size: 24,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (onSecondaryTap case final secondary?) {
      disc = WaxSecondaryTapRegion(
        child: GestureDetector(
          excludeFromSemantics: true,
          onSecondaryTap: secondary,
          child: disc,
        ),
      );
    }
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: FadeTransition(opacity: opacity, child: disc),
      ),
    );
  }
}

/// How [ArtworkImage] draws the state where there is no picture.
enum ArtworkPlaceholder {
  /// Up to two initials over the domain hue. The default, and right
  /// wherever the title is already written beside the artwork: a card
  /// caption, a row's own label, a header under the cover.
  initials,

  /// The whole name, set over the domain hue with the grain the player
  /// backdrop uses. For the surfaces where the artwork *is* the
  /// identification and nothing beside it says what is playing - a
  /// full-screen radio face, a dial tile - two initials name nothing,
  /// and a station with no logo is the common case rather than a corner
  /// of one.
  wordmark,
}

/// Up to [max] initials for [name], each the first letter or digit of a
/// word, so "2morrow (Remix)" gives "2R" rather than "2(". Null when no
/// word has one, where a caller draws a glyph instead.
String? monogramInitials(String name, {int max = 2}) {
  final initials = <String>[];
  for (final word in name.trim().split(RegExp(r'\s+'))) {
    if (initials.length >= max) break;
    for (final grapheme in word.characters) {
      if (_initialStart.hasMatch(grapheme)) {
        initials.add(grapheme.toUpperCase());
        break;
      }
    }
  }
  return initials.isEmpty ? null : initials.join();
}

final RegExp _initialStart = RegExp(r'^[\p{L}\p{N}]', unicode: true);
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.monogram,
    required this.kind,
    required this.domain,
    required this.size,
    required this.colors,
  });

  final String? monogram;
  final ArtworkPlaceholder kind;
  final WaxDomain domain;
  final double size;
  final WaxColors colors;

  /// Below this a wordmark has no room to be one, whatever the caller
  /// asked for: two lines of legible type do not fit in a list row's
  /// thumbnail, so it falls back to initials there.
  static const double _wordmarkFloor = 96;

  @override
  Widget build(BuildContext context) {
    final hue = colors.domain(domain);
    final name = (monogram ?? '').trim();
    final hasName = _letterOrDigit.hasMatch(name);

    // Decided once: everything below keys off it, including the grain,
    // which belongs to the station mark alone. An initials tile is the
    // placeholder every coverless album, queue row, and search hit
    // draws, and texturing those was never the intent - it is a tiled
    // decoration plus an Opacity-induced saveLayer on the surfaces that
    // draw the most placeholders.
    final wordmark =
        kind == ArtworkPlaceholder.wordmark &&
        size >= _wordmarkFloor &&
        hasName;

    Widget mark;
    if (wordmark) {
      mark = Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: Center(
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: WaxType.titleEntity.copyWith(
              color: hue.onContainer,
              // Scaled off the box rather than fixed, and clamped at both
              // ends: this is drawn at everything from a dial tile to a
              // full-screen face, and one size would be unreadable at one
              // end and a billboard at the other.
              fontSize: math.min(34, math.max(13, size * 0.13)),
              height: 1.15,
            ),
          ),
        ),
      );
    } else {
      // A title of "..." has no initials to give, so the domain's own
      // glyph stands in, which is at least true.
      final letters = monogramInitials(name);
      mark = Center(
        child: letters != null
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
      );
    }

    // The grain is the station mark's, not every placeholder's: it is
    // what makes a wordmark read as WaxDeck's own surface rather than as
    // a flat swatch, and an initials tile wants to stay the plain tile
    // it has always been. Skipped in light too, where the token is zero
    // and the layer would be a repaint for nothing.
    if (!wordmark || colors.grainOpacity <= 0) {
      return DecoratedBox(
        decoration: BoxDecoration(color: hue.container),
        child: mark,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: hue.container),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Opacity(
            opacity: colors.grainOpacity,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                    'assets/brand/grain.png',
                    package: 'waxdeck_ui',
                  ),
                  repeat: ImageRepeat.repeat,
                ),
              ),
            ),
          ),
          mark,
        ],
      ),
    );
  }
}

/// The line under a picture: what is in the slot, or where the picture
/// came from.
///
/// Takes a worded string rather than anything it could word itself. The
/// vocabulary a cover's provenance is drawn from is the app's - source
/// tokens, provider ids, the borrowed note - and this package has no
/// translation table to turn one into a sentence. What it owns is how
/// that sentence sits under artwork: the type ramp, the tertiary tone,
/// the ellipsis, so four surfaces cannot drift into four answers.
///
/// [maxLines] is the caller's, not a policy: a header caption under a
/// 200-pixel cover has room for two, and a player hero reserves exactly
/// one line of vertical allowance before it sizes itself.
class ArtworkCaption extends StatelessWidget {
  const ArtworkCaption(
    this.text, {
    this.align = TextAlign.start,
    this.maxLines = 1,
    this.emphasis = false,
    this.fallback,
    super.key,
  });

  final String text;

  /// Drawn instead of [text] where that does not fit on one line: the
  /// part of it that has to survive a narrow picture.
  final String? fallback;
  final TextAlign align;
  final int maxLines;

  /// Whether this line describes the picture that is there rather than
  /// the absence of one or the place it came from. One step up the text
  /// ramp, which is the difference between "1400 x 1400" and "Empty".
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final style = WaxType.caption.copyWith(
      color: emphasis ? colors.textSecondary : colors.textTertiary,
    );
    Widget prose(String line) => WaxProse(
      line,
      textAlign: align,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
    final fallback = this.fallback;
    if (fallback == null) return prose(text);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: maxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        return prose(fits ? text : fallback);
      },
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
