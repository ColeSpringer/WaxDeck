import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../theme/wax_layout.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'controls.dart';
import 'indicators.dart';
import 'view_data.dart';

/// An eyebrow, a title, and an optional action: the head of every shelf,
/// section, and grouped list.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.overline,
    this.actionLabel,
    this.onAction,
    this.semanticsId,
    super.key,
  });

  final String title;

  /// The kicker above the title. Rendered in caps by this component, so
  /// the string itself stays sentence case and screen readers hear
  /// words rather than letters.
  final String? overline;

  final String? actionLabel;
  final VoidCallback? onAction;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (overline != null)
                  Semantics(
                    label: overline,
                    child: ExcludeSemantics(
                      child: Text(
                        overline!.toUpperCase(),
                        style: WaxType.overline.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: WaxType.headline.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            WaxButton(
              label: actionLabel!,
              kind: WaxButtonKind.text,
              onPressed: onAction,
              semanticsId: semanticsId,
            ),
        ],
      ),
    );
  }
}

/// A grid or shelf cell: artwork, title, caption, and the badges that
/// belong on artwork rather than in text.
///
/// On pointer platforms, hovering reveals a play button over the artwork
/// and an overflow button, so desktop browsing is never
/// tap-to-navigate-only.
class MediaCard extends StatefulWidget {
  const MediaCard({
    required this.data,
    this.onTap,
    this.onPlay,
    this.onMore,
    this.width,
    this.playing = false,
    super.key,
  });

  final MediaTileData data;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onMore;

  /// Defaults to the size class's grid extent.
  final double? width;

  final bool playing;

  /// How tall a card of [width] can get, text scaling included.
  ///
  /// A horizontal shelf has to commit to a height before it lays its
  /// cards out, and guessing one truncates captions the moment the OS
  /// text scale moves. Titles run to two lines, then a caption, then the
  /// trailing readout, so the tallest card is the sum of those.
  static double heightFor(BuildContext context, {required double width}) {
    final scaler = MediaQuery.textScalerOf(context);
    final title =
        scaler.scale(WaxType.titleItem.height! * WaxType.titleItem.fontSize!) *
        2;
    final caption = scaler.scale(
      WaxType.caption.height! * WaxType.caption.fontSize!,
    );
    return width + WaxSpace.s8 + title + caption * 2;
  }

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final data = widget.data;
    final width = widget.width ?? WaxSizeClass.of(context).gridExtent;

    final art = Stack(
      children: <Widget>[
        ArtworkImage(
          size: width,
          image: data.artwork,
          monogram: data.title,
          shape: data.shape,
          domain: data.domain,
          progress: data.progress,
          dimmed: data.unavailableOffline,
        ),
        if (widget.playing)
          Positioned(
            left: WaxSpace.s8,
            bottom: WaxSpace.s8,
            child: Container(
              padding: const EdgeInsets.all(WaxSpace.s4),
              decoration: BoxDecoration(
                color: colors.scrim,
                borderRadius: WaxRadius.chip,
              ),
              child: PlayingIndicator(
                playing: true,
                form: PlayingIndicatorForm.bars,
                size: 14,
              ),
            ),
          ),
        if (data.downloaded)
          Positioned(
            right: WaxSpace.s8,
            bottom: WaxSpace.s8,
            child: WaxIcon(
              WaxIcons.downloads,
              size: 14,
              color: colors.textPrimary,
              active: true,
            ),
          ),
        if (widget.onPlay != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_hovered,
              child: AnimatedOpacity(
                // Built either way and faded: an overlay that only exists
                // while hovered is created at full opacity and pops.
                opacity: _hovered ? 1 : 0,
                duration: motion.quick,
                child: ColoredBox(
                  color: colors.scrim.withValues(alpha: 0.35),
                  child: Center(
                    child: WaxIconButton(
                      glyph: WaxIcons.play,
                      label: 'Play ${data.title}',
                      size: 28,
                      color: colors.textPrimary,
                      onPressed: widget.onPlay,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      identifier: data.semanticsId,
      button: widget.onTap != null,
      label: <String?>[
        data.title,
        data.subtitle,
        if (data.progress != null)
          '${((data.progress ?? 0) * 100).round()} percent played',
      ].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onMore,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: _focused,
          borderRadius: WaxRadius.card,
          surface: colors.canvas,
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTap: widget.onMore,
            onLongPress: widget.onMore,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  art,
                  const SizedBox(height: WaxSpace.s8),
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WaxType.titleItem.copyWith(
                      color: data.unavailableOffline
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
                  if (data.subtitle != null)
                    Text(
                      data.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaxType.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  if (data.trailingText != null)
                    Text(
                      data.trailingText!,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row: artwork, title, caption, trailing readout, and the slot
/// where the playing indicator goes.
class MediaListRow extends StatelessWidget {
  const MediaListRow({
    required this.data,
    this.onTap,
    this.onMore,
    this.leadingIndex,
    this.playing = false,
    this.selected = false,
    this.artSize = 40,
    super.key,
  });

  final MediaTileData data;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  /// Track numbers on an album, positions in a queue.
  final int? leadingIndex;

  final bool playing;
  final bool selected;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);

    return Semantics(
      identifier: data.semanticsId,
      button: onTap != null,
      selected: selected,
      label: <String?>[
        if (playing) 'Playing',
        data.title,
        data.subtitle,
        data.trailingText,
      ].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onMore,
      child: Material(
        color: selected ? colors.surface2 : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: onMore,
          onLongPress: onMore,
          child: Container(
            constraints: BoxConstraints(minHeight: layout.rowHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s8,
              vertical: WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                if (leadingIndex != null)
                  SizedBox(
                    width: 28,
                    child: playing
                        ? PlayingIndicator(
                            playing: true,
                            form: PlayingIndicatorForm.bars,
                            size: 14,
                          )
                        : Text(
                            '$leadingIndex',
                            textAlign: TextAlign.center,
                            style: WaxType.monoData.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                  )
                else
                  ArtworkImage(
                    size: artSize,
                    image: data.artwork,
                    monogram: data.title,
                    shape: data.shape,
                    domain: data.domain,
                    dimmed: data.unavailableOffline,
                  ),
                const SizedBox(width: WaxSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WaxType.titleItem.copyWith(
                          color: playing ? colors.accent : colors.textPrimary,
                        ),
                      ),
                      if (data.subtitle != null)
                        Text(
                          data.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WaxType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (data.starred)
                  Padding(
                    padding: const EdgeInsets.only(right: WaxSpace.s8),
                    child: WaxIcon(
                      WaxIcons.star,
                      size: 14,
                      active: true,
                      color: colors.accent,
                    ),
                  ),
                if (data.trailingText != null)
                  Text(
                    data.trailingText!,
                    style: WaxType.monoTime.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                if (onMore != null)
                  WaxIconButton(
                    glyph: WaxIcons.more,
                    label: 'More for ${data.title}',
                    size: 18,
                    onPressed: onMore,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal shelf: a header and a snapping row of cards.
///
/// Shelves never animate their arrival. Staggered entrances make a fast
/// app feel slow and regress badly on keyset-paginated lists.
class ShelfRow extends StatelessWidget {
  const ShelfRow({
    required this.title,
    required this.items,
    this.overline,
    this.actionLabel,
    this.onAction,
    this.onTapItem,
    this.onPlayItem,
    this.cardWidth,
    this.padding,
    super.key,
  });

  final String title;
  final String? overline;
  final List<MediaTileData> items;
  final String? actionLabel;
  final VoidCallback? onAction;
  final void Function(MediaTileData item)? onTapItem;
  final void Function(MediaTileData item)? onPlayItem;
  final double? cardWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final gutter = padding ?? sizeClass.gutter;
    final width = cardWidth ?? sizeClass.gridExtent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: gutter,
          child: SectionHeader(
            title: title,
            overline: overline,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        ),
        SizedBox(
          height: MediaCard.heightFor(context, width: width),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: gutter,
            physics: _ShelfSnapPhysics(
              itemExtent: width + WaxShellMetrics.gridGap,
              leadingInset: gutter.left,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: WaxShellMetrics.gridGap),
            itemBuilder: (context, index) {
              final item = items[index];
              return MediaCard(
                data: item,
                width: width,
                onTap: onTapItem == null ? null : () => onTapItem!(item),
                onPlay: onPlayItem == null ? null : () => onPlayItem!(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Snaps a shelf to card boundaries.
///
/// `PageScrollPhysics` pages by the viewport, not by the card pitch, and
/// knows nothing about the leading gutter, so a flick rests wherever the
/// page happens to land: half a card clipped at the edge. This settles on
/// whole cards, gutter included.
class _ShelfSnapPhysics extends ScrollPhysics {
  const _ShelfSnapPhysics({
    required this.itemExtent,
    required this.leadingInset,
    super.parent,
  });

  final double itemExtent;
  final double leadingInset;

  @override
  _ShelfSnapPhysics applyTo(ScrollPhysics? ancestor) => _ShelfSnapPhysics(
    itemExtent: itemExtent,
    leadingInset: leadingInset,
    parent: buildParent(ancestor),
  );

  double _snap(double offset, ScrollMetrics position) {
    final target =
        ((offset - leadingInset) / itemExtent).roundToDouble() * itemExtent +
        leadingInset;
    return target.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range: let the parent's spring bring it back first.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final simulation = super.createBallisticSimulation(position, velocity);
    final landing = simulation?.x(double.infinity) ?? position.pixels;
    final target = _snap(landing, position);
    if ((target - position.pixels).abs() < precisionErrorTolerance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
