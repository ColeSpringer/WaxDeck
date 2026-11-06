import 'package:material_ui/material_ui.dart';

import '../color/palette.dart';
import '../theme/wax_accent.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'action_bar.dart';
import 'artwork.dart';
import 'backdrop.dart';
import 'controls.dart';
import 'prose.dart';
import 'view_data.dart';

/// A navigation link under an [EntityHeader]'s subtitle, as plain data:
/// a book's author or its series, not an action on the book.
@immutable
class EntityHeaderLink {
  const EntityHeaderLink({
    required this.label,
    required this.semanticsId,
    required this.onPressed,
  });

  final String label;
  final String semanticsId;
  final VoidCallback onPressed;
}

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
    this.links = const <EntityHeaderLink>[],
    this.actions = const <WaxAction>[],
    this.trailing = const <Widget>[],
    this.overflow,
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

  /// Links to where this belongs, drawn one per line under [subtitle] in
  /// the order given.
  final List<EntityHeaderLink> links;

  /// Play, shuffle, download: the pills of the header's action bar.
  final List<WaxAction> actions;

  /// Icon clusters after the pills, such as a star and a rating.
  final List<Widget> trailing;

  /// The overflow menu, last in the bar.
  final Widget? overflow;

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
                ArtworkCaption(
                  artworkCaption!,
                  align: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          );

    // Each optional row is keyed, so one coming or going above the bar
    // leaves the bar, and the focus on its pills, where it was.
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
            key: const ValueKey<String>('subtitle'),
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              subtitle!,
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              style: WaxType.body.copyWith(color: colors.textSecondary),
            ),
          ),
        for (final link in links)
          Padding(
            key: ValueKey<String>('link-${link.semanticsId}'),
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            // The button's label takes the ambient alignment, so a link
            // that wraps lines up with the text around it.
            child: DefaultTextStyle.merge(
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              child: WaxButton(
                label: link.label,
                kind: WaxButtonKind.inline,
                semanticsId: link.semanticsId,
                onPressed: link.onPressed,
              ),
            ),
          ),
        if (metadata != null)
          Padding(
            key: const ValueKey<String>('metadata'),
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              metadata!,
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          ),
        if (description != null)
          Padding(
            key: const ValueKey<String>('description'),
            padding: const EdgeInsets.only(top: WaxSpace.s12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WaxSpace.readingWidth,
              ),
              child: WaxProse(
                description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: stacked ? TextAlign.center : TextAlign.start,
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        if (actions.isNotEmpty || trailing.isNotEmpty || overflow != null)
          Padding(
            key: const ValueKey<String>('actions'),
            padding: const EdgeInsets.only(top: WaxSpace.s16),
            child: WaxActionBar(
              actions: actions,
              trailing: trailing,
              overflow: overflow,
              alignment: stacked ? WrapAlignment.center : WrapAlignment.start,
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
