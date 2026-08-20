import 'package:flutter/material.dart';

import '../color/palette.dart';
import '../theme/wax_accent.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'backdrop.dart';
import 'view_data.dart';

/// The head of a detail page: album, artist, show, book, playlist.
///
/// Artwork is the hero and the wash behind it comes from the artwork
/// itself, so a detail page feels like the record it is about. The chrome
/// stays quiet: titles, a metadata line, and the actions, all in ordinary
/// text tokens over a scrim that guarantees they stay readable.
class EntityHeader extends StatelessWidget {
  const EntityHeader({
    required this.title,
    this.subtitle,
    this.metadata,
    this.artwork,
    this.artworkCaption,
    this.shape = ArtworkShape.square,
    this.domain = WaxDomain.music,
    this.palette,
    this.actions = const <Widget>[],
    this.description,
    this.semanticsId,
    super.key,
  });

  final String title;

  /// Artist, author, host: the line that says whose this is.
  final String? subtitle;

  /// "1975 · 9 tracks · 41 min", set in the caption voice.
  final String? metadata;

  final WaxArtwork? artwork;

  /// A line under the artwork saying where the picture came from. Kept
  /// with the art rather than in [metadata] because it describes the
  /// image and not the release, and because the art is the thing it has
  /// to sit under to be read as its caption.
  final String? artworkCaption;

  final ArtworkShape shape;
  final WaxDomain domain;
  final WaxPalette? palette;

  /// Play, shuffle, star, download, overflow.
  final List<Widget> actions;

  final String? description;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final stacked = sizeClass.isCompact;
    final artSize = stacked ? 168.0 : 200.0;

    final cover = ArtworkImage(
      size: artSize,
      artwork: artwork,
      monogram: title,
      shape: shape,
      domain: domain,
    );
    // The caption is bounded by the artwork's own width, so a long
    // provider name wraps under the picture rather than widening the
    // column the text block is laid out against.
    final art = artworkCaption == null
        ? cover
        : SizedBox(
            width: artSize,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                cover,
                const SizedBox(height: WaxSpace.s8),
                Text(
                  artworkCaption!,
                  textAlign: TextAlign.center,
                  style: WaxType.caption.copyWith(color: colors.textTertiary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );

    final text = Column(
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          textAlign: stacked ? TextAlign.center : TextAlign.start,
          style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              subtitle!,
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              style: WaxType.body.copyWith(color: colors.textSecondary),
            ),
          ),
        if (metadata != null)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              metadata!,
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WaxSpace.readingWidth,
              ),
              child: Text(
                description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: stacked ? TextAlign.center : TextAlign.start,
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s16),
            child: Wrap(
              spacing: WaxSpace.s8,
              runSpacing: WaxSpace.s8,
              alignment: stacked ? WrapAlignment.center : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
      ],
    );

    return Semantics(
      identifier: semanticsId,
      header: true,
      container: true,
      child: WaxAccent(
        palette: palette ?? WaxPalette.forDomain(colors, domain),
        domain: domain,
        child: WaxBackdrop(
          // The wash belongs to the header; grain is the player's alone.
          grain: false,
          palette: palette ?? WaxPalette.forDomain(colors, domain),
          domain: domain,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: sizeClass.gutter.horizontal / 2,
              vertical: WaxSpace.s24,
            ),
            child: stacked
                ? Column(
                    children: <Widget>[
                      art,
                      const SizedBox(height: WaxSpace.s16),
                      text,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      art,
                      const SizedBox(width: WaxSpace.s24),
                      Expanded(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
