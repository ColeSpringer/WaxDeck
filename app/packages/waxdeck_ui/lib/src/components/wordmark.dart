import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// The WaxDeck logotype: the name in Archivo Expanded with the mark
/// beside it.
///
/// The mark is the emblem, as a rounded chip of its own paper - the same
/// shape every app icon this project ships is, derived from the same
/// master by `tools/generate-brand.py`. A chip rather than a keyed
/// silhouette because this sits on both themes: the emblem's ink is
/// dark, and dark ink on a dark surface is a hole where the identity
/// should be.
///
/// The name is still live text, so it stays crisp at any size and any
/// text scale, and `color` tints it. The chip is artwork and keeps its
/// own colours; a tinted photograph is not a logo.
///
/// Used on login, setup, about, the sidebar header, and the share card.
class WaxWordmark extends StatelessWidget {
  const WaxWordmark({
    this.size = 28,
    this.color,
    this.showMark = true,
    super.key,
  });

  /// The chip's image, exposed so a caller capturing a single frame
  /// (the share card export) can `precacheImage` it first. Everywhere
  /// else the async decode is fine: the widget repaints when it lands.
  static const ImageProvider markImage = AssetImage(
    'assets/brand/emblem-256.png',
    package: 'waxdeck_ui',
  );

  /// Cap height of the logotype, in logical pixels.
  final double size;

  final Color? color;

  /// The mark. Dropped where the wordmark sits beside other chrome that
  /// already carries the identity.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final ink = color ?? colors.textPrimary;
    return Semantics(
      label: 'WaxDeck',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showMark) ...<Widget>[
              // No clip: the asset's corners are already keyed
              // transparent at the chip radius by the brand pipeline,
              // and a ClipRRect here would be a saveLayer per paint
              // that cuts nothing.
              Image(
                image: markImage,
                width: size * 1.05,
                height: size * 1.05,
                filterQuality: FilterQuality.medium,
              ),
              SizedBox(width: size * 0.32),
            ],
            Text(
              'WaxDeck',
              style: WaxType.display.copyWith(fontSize: size, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wordmark centred with a tagline, for login, setup, and about.
class WaxBrandBlock extends StatelessWidget {
  const WaxBrandBlock({this.tagline, this.size = 34, super.key});

  final String? tagline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WaxWordmark(size: size),
        if (tagline != null) ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}
