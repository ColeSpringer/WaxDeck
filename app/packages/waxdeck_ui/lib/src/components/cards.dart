import 'dart:math' as math;

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
          artwork: data.artwork,
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
        if (data.unplayed)
          Positioned(
            right: WaxSpace.s8,
            top: WaxSpace.s8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: colors.scrim, width: 2),
              ),
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
        if (data.unplayed) 'Unplayed',
        data.title,
        data.subtitle,
        // Drawn on the card, so announced too, as a row's is:
        // `excludeSemantics` below hides the Text itself.
        data.trailingText,
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
    this.onLongPress,
    this.onSelect,
    this.selectSemanticsId,
    this.leadingIndex,
    this.leadingText,
    this.actions = const <Widget>[],
    this.playing = false,
    this.selected = false,
    this.artSize = 40,
    super.key,
  });

  final MediaTileData data;
  final VoidCallback? onTap;

  /// The row's overflow: draws a button, and is what a long press and a
  /// right click open.
  final VoidCallback? onMore;

  /// A long press with no menu behind it. Starting a multi-select is
  /// the one so far. Kept apart from [onMore] because that one draws a
  /// control, and a button announcing "More for [title]" whose only
  /// action is to start selecting is a lie about what it opens.
  /// [onMore] wins where a row wants both.
  final VoidCallback? onLongPress;

  /// Set on rows that can join a multi-select. A checkbox takes the
  /// leading slot and reports the state the row is moving to; the row's
  /// own [onTap] stays whatever the screen made it, so a selection mode
  /// is the screen's business rather than this component's.
  final ValueChanged<bool>? onSelect;

  /// The checkbox's own handle. It is a control of its own, beside the
  /// row rather than inside it, so it gets an identifier of its own.
  final String? selectSemanticsId;

  /// Track numbers on an album, positions in a queue.
  final int? leadingIndex;

  /// A short leading readout where an index would be a lie: a publication
  /// date on an episode, which is what orders the list it is in. Mutually
  /// exclusive with [leadingIndex] and drawn in the same slot.
  final String? leadingText;

  /// Per-row controls before the overflow: fetch, remove, the things a
  /// row can do without opening.
  final List<Widget> actions;

  final bool playing;
  final bool selected;
  final double artSize;

  /// How tall a row of [artSize] comes out, text scaling included.
  ///
  /// The same reason [MediaCard.heightFor] exists, from the other end: a
  /// screen that scrolls to a row by index has to know the pitch before
  /// the rows are built, and a guess drifts the moment the OS text scale
  /// moves — a title and a caption at 1.5x are taller than the density's
  /// row height, so an estimate made from that alone lands short by more
  /// with every row it counts.
  ///
  /// Rows carrying a resume sliver are a few pixels taller than this.
  /// Nothing measures those: the surfaces that scroll by index are the
  /// music indexes, whose rows have no position to draw.
  static double heightFor(
    BuildContext context, {
    double artSize = 40,
    bool subtitle = true,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    // Rounded up per line, the way the text painter lays one out: a
    // fractional line height becomes a whole pixel on screen, and the
    // difference compounds once a caller multiplies this by a row index.
    double line(TextStyle style) =>
        scaler.scale(style.height! * style.fontSize!).ceilToDouble();
    final text =
        line(WaxType.titleItem) + (subtitle ? line(WaxType.caption) : 0);
    return math.max(
      WaxLayout.of(context).rowHeight,
      math.max(artSize, text) + WaxSpace.s8 * 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);

    final title = Text(
      data.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WaxType.titleItem.copyWith(
        color: playing ? colors.accent : colors.textPrimary,
      ),
    );

    final leading = switch (leadingIndex ?? leadingText) {
      null => null,
      // A number needs a column of digits; a date needs the room for
      // one, and neither should push the title around as the rows
      // scroll. Scaled with the text, because the slot is holding text:
      // a fixed one clips "Jul 12" to "Jul..." the moment the OS setting
      // moves, which is the whole readout gone.
      final Object value => SizedBox(
        width: MediaQuery.textScalerOf(
          context,
        ).scale(leadingIndex != null ? 28 : 52).ceilToDouble(),
        child: playing
            ? PlayingIndicator(
                playing: true,
                form: PlayingIndicatorForm.bars,
                size: 14,
              )
            : Text(
                '$value',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaxType.monoData.copyWith(color: colors.textTertiary),
              ),
      ),
    };

    // The row's own identity goes on the content region rather than on
    // the whole row, and that placement is load-bearing: the label is
    // built with `excludeSemantics`, which drops every node beneath it,
    // and a row that hosts controls of its own (a fetch button, a
    // checkbox) would take them down with it: reachable by neither a
    // screen reader nor the suite, while looking perfectly fine.
    final content = Semantics(
      identifier: data.semanticsId,
      button: onTap != null,
      selected: selected,
      label: <String?>[
        if (playing) 'Playing',
        if (data.unplayed) 'Unplayed',
        data.title,
        data.subtitle,
        data.trailingText,
      ].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onMore ?? onLongPress,
      child: Row(
        children: <Widget>[
          if (leading != null)
            leading
          else if (onSelect == null)
            ArtworkImage(
              size: artSize,
              artwork: data.artwork,
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
                // The dot rides beside the title, and only where there
                // is one: an Expanded title inside a Row lays out to the
                // full width rather than to its own, which every row in
                // the app would then be measured at.
                if (data.unplayed)
                  Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: WaxSpace.s8),
                      Expanded(child: title),
                    ],
                  )
                else
                  title,
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
          if (data.downloaded)
            Padding(
              padding: const EdgeInsets.only(right: WaxSpace.s8),
              child: WaxIcon(
                WaxIcons.downloads,
                size: 14,
                active: true,
                color: colors.textSecondary,
              ),
            ),
          if (data.trailingText != null)
            Text(
              data.trailingText!,
              style: WaxType.monoTime.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );

    final row = Row(
      children: <Widget>[
        if (onSelect != null)
          Semantics(
            identifier: selectSemanticsId,
            label: selected ? 'Deselect ${data.title}' : 'Select ${data.title}',
            child: Checkbox(
              value: selected,
              onChanged: (value) => onSelect!(value ?? false),
            ),
          ),
        Expanded(child: content),
        ...actions,
        if (onMore != null)
          WaxIconButton(
            glyph: WaxIcons.more,
            label: 'More for ${data.title}',
            size: 18,
            onPressed: onMore,
          ),
      ],
    );

    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onSecondaryTap: onMore,
        onLongPress: onMore ?? onLongPress,
        child: Container(
          constraints: BoxConstraints(minHeight: layout.rowHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s8,
            vertical: WaxSpace.s8,
          ),
          // The row is the child on its own wherever there is no
          // position to draw, so a surface that never had one lays out
          // exactly as it did: a Column around it would take the row's
          // vertical centring in the min-height box away from every list
          // in the app to serve the one that resumes.
          child: data.progress == null
              ? row
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    row,
                    // The resume sliver: how far in this row is, drawn
                    // under it rather than as a ring, because a list row
                    // has width and no artwork corner to spare.
                    Padding(
                      padding: const EdgeInsets.only(top: WaxSpace.s4),
                      child: ClipRRect(
                        borderRadius: WaxRadius.chip,
                        child: LinearProgressIndicator(
                          value: data.progress!.clamp(0.0, 1.0),
                          minHeight: 2,
                          backgroundColor: colors.surface2,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ],
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
