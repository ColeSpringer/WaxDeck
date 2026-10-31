import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, precisionErrorTolerance;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../theme/wax_layout.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'controls.dart';
import 'edge_fade.dart';
import 'indicators.dart';
import 'info_slot.dart';
import 'info_tip.dart';
import 'keyed_rows.dart';
import 'secondary_tap.dart';
import 'sheet.dart';
import 'snap_physics.dart';
import 'tooltip.dart';
import 'view_data.dart';

/// An eyebrow, a title, and an optional action: the head of every shelf,
/// section, and grouped list.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.overline,
    this.actionLabel,
    this.spokenActionLabel,
    this.onAction,
    this.semanticsId,
    this.info,
    this.infoSemanticsId,
    super.key,
  });

  final String title;

  /// A sentence the header holds without printing it, behind a
  /// [WaxInfoTip] right after the title, on the title's line.
  final String? info;

  /// The info tip's handle; [semanticsId] is the action's.
  final String? infoSemanticsId;

  /// The kicker above the title. Rendered in caps by this component, so
  /// the string itself stays sentence case and screen readers hear
  /// words rather than letters.
  final String? overline;

  final String? actionLabel;

  /// What a screen reader hears instead of [actionLabel]. The header's
  /// title is a sibling node that never merges into the button, so an
  /// action drawn as "New" beside "App passwords" announces as "New"
  /// alone unless it says here what it is new of.
  final String? spokenActionLabel;

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
                titleWithInfo(
                  Text(
                    title,
                    style: WaxType.headline.copyWith(color: colors.textPrimary),
                  ),
                  info,
                  semanticsId: infoSemanticsId,
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            WaxButton(
              label: actionLabel!,
              spokenLabel: spokenActionLabel,
              kind: WaxButtonKind.text,
              onPressed: onAction,
              semanticsId: semanticsId,
            ),
        ],
      ),
    );
  }
}

/// One extra control in a card's corner, beside its overflow.
///
/// For state a card carries that is also a verb - a station's pin is the
/// case this exists for. Drawn in the same chip row as the overflow and
/// on the same disc, because a control the card stacked over itself is
/// what a station tile did: a hand-rolled star and menu at one corner,
/// eight pixels from the card's own hover menu at the other, two of the
/// same glyph on a pointer.
///
/// Always visible, unlike the overflow: it answers a question ("is this
/// pinned?") as well as offering an action, and there is no hover on a
/// phone to reveal it with.
@immutable
class MediaCardAction {
  const MediaCardAction({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.semanticsId,
  });

  final WaxGlyph glyph;

  /// The accessible name, and the tooltip. Says what pressing it will
  /// do, as every other stateful control here does.
  final String label;

  final VoidCallback? onPressed;

  /// Renders the fill weight and the accent, the icon system's state
  /// convention.
  final bool active;

  final String? semanticsId;
}

/// A grid or shelf cell: artwork, title, caption, and the badges that
/// belong on artwork rather than in text.
///
/// On pointer platforms, hovering reveals a play button over the artwork
/// and, where [onMore] is wired, an overflow chip, so desktop browsing
/// is never tap-to-navigate-only. A right click and a touch long press
/// open the same menu.
class MediaCard extends StatefulWidget {
  const MediaCard({
    required this.data,
    this.onTap,
    this.onPlay,
    this.playLabel,
    this.playSemanticsId,
    this.onMore,
    this.moreSemanticsId,
    this.action,
    this.width,
    this.captions,
    this.playing = false,
    super.key,
  });

  final MediaTileData data;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  /// The play affordance's name, where the verb is not "Play" plus the
  /// title. Null takes the design system's wording.
  final String? playLabel;

  /// The play affordance's own identifier. It is a node of its own beside
  /// the card's, so it does not inherit the card's.
  final String? playSemanticsId;

  final VoidCallback? onMore;

  /// The overflow chip's own identifier, as on [MediaListRow].
  final String? moreSemanticsId;

  /// A control beside the overflow, for a card that carries state worth
  /// a corner of its own.
  final MediaCardAction? action;

  /// Defaults to the size class's grid extent.
  final double? width;

  /// Defaults to the theme's, which is where the listener's setting
  /// arrives. Passed only by the catalogue and by tests, so that a
  /// screen full of cards never has to thread it.
  final WaxCaptionMode? captions;

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

  /// How many cards of at most [extent] fit across [available], and how
  /// wide each one comes out.
  ///
  /// Measured rather than assumed: a max-extent delegate divides the room
  /// evenly and hands back a cell narrower than the number it was given, so
  /// a card sized to that number draws taller than [heightFor] reserved.
  /// Deciding the count here makes the two one measurement.
  static ({int columns, double width}) gridFor(
    double available, {
    required double extent,
  }) {
    const gap = WaxShellMetrics.gridGap;
    final columns = ((available + gap) / (extent + gap)).ceil().clamp(1, 12);
    return (
      columns: columns,
      width: (available - gap * (columns - 1)) / columns,
    );
  }

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard>
    with SingleTickerProviderStateMixin {
  /// A mouse over the card or anything drawn beside it. One region around
  /// the lot, so moving between the card, the disc and the chips is never
  /// a leave, and a plain one rather than the focus detector's hover,
  /// which a touch on a touchscreen laptop switches off.
  bool _hovered = false;

  /// Focus on the card itself, on its corner chips, and on its play disc,
  /// each read from a node owned here rather than kept in a flag a
  /// callback sets: a part that unmounts while it holds the focus never
  /// reports losing it. Focus on a part counts with the card's own, or
  /// Tab onto a chip would un-reveal the card and take the chip away.
  final FocusNode _cardFocus = FocusNode(debugLabel: 'media-card');
  final FocusNode _chipsFocus = FocusNode(debugLabel: 'media-card-chips');
  late final _CardPartNode _playFocus = _CardPartNode(
    this,
    debugLabel: 'media-card-play',
  );

  /// The overflow's own, as the parts that hide are told apart by their
  /// nodes: the action chip beside it is always drawn.
  late final _CardPartNode _moreFocus = _CardPartNode(
    this,
    debugLabel: 'media-card-more',
  );

  /// Whether the disc and the overflow were drawn at the last build, for
  /// [WaxDirectionalFocusAction].
  bool _partsShown = false;

  /// The scrim and the disc are one affordance, so one fade drives both.
  /// Made with the first play there is to show, so a card with none
  /// carries no controller.
  AnimationController? _fade;

  /// The reveal [_fade] was last sent towards.
  bool? _faded;

  /// The fade for this build: none without a play, and a play that comes
  /// back starts where the card is, not from where it was left.
  AnimationController? _fadeFor(bool revealed) {
    if (widget.onPlay == null) {
      _faded = null;
      return null;
    }
    final fade = _fade ??= AnimationController(
      vsync: this,
      duration: WaxMotion.of(context).quick,
    );
    if (_faded != revealed) {
      if (_faded == null) {
        fade.value = revealed ? 1 : 0;
      } else if (revealed) {
        fade.forward();
      } else {
        fade.reverse();
      }
      _faded = revealed;
    }
    return fade;
  }

  @override
  void initState() {
    super.initState();
    for (final node in <FocusNode>[_cardFocus, _chipsFocus, _playFocus]) {
      node.addListener(_reread);
    }
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  void _reread() {
    if (mounted) setState(() {});
  }

  void _highlightChanged(FocusHighlightMode _) {
    if (_cardFocus.hasFocus) _reread();
  }

  @override
  void didUpdateWidget(MediaCard old) {
    super.didUpdateWidget(old);
    // A part taken away while focused takes the focus with it silently,
    // so the nodes are read again once it has gone. A station's tile
    // drops its play while the station plays.
    if ((old.onPlay != null && widget.onPlay == null) ||
        (old.onMore != null && widget.onMore == null) ||
        (old.action != null && widget.action == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reread());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fade?.duration = WaxMotion.of(context).quick;
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _fade?.dispose();
    _cardFocus.dispose();
    _chipsFocus.dispose();
    _playFocus.dispose();
    _moreFocus.dispose();
    super.dispose();
  }

  /// One corner control on its own disc, with the ink its press draws on
  /// top of the disc rather than under it, and wherever the card stands.
  Widget _chip(WaxColors colors, Widget child) => DecoratedBox(
    decoration: BoxDecoration(color: colors.surface1, shape: BoxShape.circle),
    child: Material(type: MaterialType.transparency, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final l10n = context.waxL10n;
    final data = widget.data;
    final width = widget.width ?? WaxSizeClass.of(context).gridExtent;
    final captionsFade =
        (widget.captions ?? WaxLayout.of(context).captions) ==
        WaxCaptionMode.onHover;
    // Keyboard focus, as a focus ring shows it: a touch focus is no
    // reveal.
    final focused =
        _cardFocus.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    // Focus counts as well as hover, or a card reached by keyboard is a
    // cover with no name on it and no way to ask for one.
    final revealed =
        _hovered || focused || _chipsFocus.hasFocus || _playFocus.hasFocus;
    _partsShown = revealed;
    final captionsVisible = !captionsFade || revealed;
    final fade = _fadeFor(revealed);

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
        // Under the badges, which stay legible over it; only the disc is
        // lifted out beside the card.
        if (fade != null)
          Positioned.fill(
            child: HoverPlayScrim(
              opacity: fade,
              radius: ArtworkImage.cornerRadius(data.shape, width),
            ),
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
              child: const PlayingIndicator(playing: true, size: 14),
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
        // Top left, the one corner nothing else claims. Opaque, on a
        // tested surface pair: the scrim is translucent, so over a dark
        // cover in light mode it composites to ink on ink.
        if (data.badge != null)
          Positioned(
            left: WaxSpace.s8,
            top: WaxSpace.s8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: WaxSpace.s8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colors.surface1,
                borderRadius: WaxRadius.chip,
                border: Border.all(color: colors.hairline),
              ),
              child: Text(
                data.badge!,
                style: WaxType.caption.copyWith(color: colors.textPrimary),
              ),
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
      ],
    );

    // The corner controls, built beside the card rather than inside it.
    //
    // The card announces one node for the whole tile and excludes
    // everything under it, which is right for the artwork and the
    // captions and wrong for a control: swallowed, a pin would have no
    // name, no state, and no handle. So the chip row is the card's
    // sibling, exactly where a station tile used to hand-roll its own -
    // except that here it is one row, aligned to the same corner as the
    // overflow, so the two cannot end up eight pixels apart.
    final chips = widget.onMore == null && widget.action == null
        ? null
        : Positioned(
            key: const ValueKey<String>('chips'),
            right: WaxSpace.s8,
            top: WaxSpace.s8,
            child: Focus(
              focusNode: _chipsFocus,
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              // One disc apiece and no gap between them, so a card
              // carrying both draws a capsule rather than two circles.
              // The overflow leads, so the always-drawn action keeps
              // the corner and nothing shifts as the pointer arrives.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Revealed like the play affordance: a pointer gets a
                  // visible way into the menu instead of having to
                  // guess at a right click. Offstage while hidden rather
                  // than faded, because a faded chip still occupies its
                  // whole 44px box - and on a phone, where nothing ever
                  // hovers, that box pushed the action a third of the
                  // way across the card with dead space beside it. Still
                  // a tab stop there, so Shift+Tab reaches it as Tab
                  // does, and its focus reveals it. Touch keeps the long
                  // press.
                  if (widget.onMore != null)
                    FocusTraversalOrder(
                      key: const ValueKey<String>('more'),
                      order: const NumericFocusOrder(2),
                      child: Focus(
                        focusNode: _moreFocus,
                        canRequestFocus: false,
                        skipTraversal: true,
                        includeSemantics: false,
                        child: Visibility(
                          visible: revealed,
                          maintainState: true,
                          maintainFocusability: true,
                          child: _chip(
                            colors,
                            WaxIconButton(
                              glyph: WaxIcons.more,
                              label: l10n.cardsMoreForItem(data.title),
                              size: 16,
                              semanticsId: widget.moreSemanticsId,
                              onPressed: widget.onMore,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.action case final action?)
                    FocusTraversalOrder(
                      key: const ValueKey<String>('action'),
                      order: const NumericFocusOrder(3),
                      child: _chip(
                        colors,
                        WaxIconButton(
                          glyph: action.glyph,
                          label: action.label,
                          size: 16,
                          active: action.active,
                          semanticsId: action.semanticsId,
                          onPressed: action.onPressed,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );

    final card = Semantics(
      identifier: data.semanticsId,
      button: widget.onTap != null,
      label: <String?>[
        if (data.unplayed) l10n.cardsUnplayed,
        data.badge,
        data.title,
        data.subtitle,
        // Drawn on the card, so announced too, as a row's is:
        // `excludeSemantics` below hides the Text itself. The spoken form
        // wins where the drawn one is abbreviated.
        data.trailingSpoken ?? data.trailingText,
        if (data.progress != null)
          l10n.cardsPercentPlayed(((data.progress ?? 0) * 100).round()),
      ].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onMore,
      child: FocusableActionDetector(
        // Owned here, so it keeps its focus through the rebuild a change
        // of what the card carries causes (see the region below).
        focusNode: _cardFocus,
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: WaxFocusRing(
          focused: focused,
          borderRadius: WaxRadius.card,
          surface: colors.canvas,
          // Only where there is a menu to raise: a card with no `onMore`
          // has nothing of its own to show, so the browser keeps its own
          // menu over it.
          child: WaxSecondaryTapRegion(
            enabled: widget.onMore != null,
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
                    // Faded rather than removed. The captions still lay
                    // out at every opacity, so [heightFor]'s reservation
                    // holds and a shelf does not resize under the pointer;
                    // and the label above is built from the data, so what
                    // a screen reader hears never changes either.
                    //
                    // The fade is built only where it can run. An
                    // AnimatedOpacity carries a controller and a ticker
                    // apiece, and a full grid is a hundred cards: in the
                    // mode that never hides a caption they would all be
                    // allocated to animate a constant.
                    _Captions(
                      fading: captionsFade,
                      visible: captionsVisible,
                      duration: motion.quick,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
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
                              // Clamped like every other line in the card,
                              // and for a load-bearing reason: [heightFor]
                              // reserves one caption line for this, so a
                              // readout that wrapped would overflow the
                              // cell by exactly one line - which is what a
                              // book's "1 hr 20 min left" did.
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WaxType.caption.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The play disc, beside the card for the chips' reason and one more:
    // on web a click over a node that excludes its subtree is that node's
    // tap, so a disc inside the card opened the card. Mounted with the
    // card and shown on reveal, so a touch on the cover still opens it.
    final onPlay = widget.onPlay;
    final play = onPlay == null || fade == null
        ? null
        : Positioned(
            key: const ValueKey<String>('play'),
            left: 0,
            top: 0,
            width: width,
            height: width,
            child: Center(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: Focus(
                  focusNode: _playFocus,
                  canRequestFocus: false,
                  skipTraversal: true,
                  // The play node stands beside the card's, with no empty
                  // node of the wrapper's between them.
                  includeSemantics: false,
                  child: HoverPlayDisc(
                    visible: revealed,
                    opacity: fade,
                    onPlay: onPlay,
                    label: widget.playLabel ?? l10n.cardsPlayItem(data.title),
                    semanticsId: widget.playSemanticsId,
                    onSecondaryTap: widget.onMore,
                  ),
                ),
              ),
            ),
          );

    final tooltip = data.tooltip;
    // Hover-only on purpose: a long press is the card's overflow
    // gesture, and a tooltip that claimed it would shadow the menu. The
    // full text is already in the semantics label above, so the tooltip
    // adds nothing a screen reader needed.
    //
    // Around the card and not the chips: the tooltip names the item, and
    // the corner controls carry names of their own.
    final named = FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: tooltip == null
          ? card
          : WaxTooltip(
              message: tooltip,
              touchTrigger: false,
              excludeFromSemantics: true,
              child: card,
            ),
    );
    final region = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Decided by what the card carries, never by the reveal: a root that
      // flipped between the card and a Stack would rebuild the card, focus
      // node and all, on every hover.
      child: play == null && chips == null
          ? named
          : Stack(
              // Sized by the card, the unpositioned child: the disc and the
              // chips ride over its artwork without changing what a grid
              // reserves. The chips stay on top of the disc.
              children: <Widget>[named, ?play, ?chips],
            ),
    );
    // Held to the card's own box. A tight cell would otherwise stretch
    // the card to the whole cell, and the region and the semantics node
    // with it, so the empty band under a short card would reveal and
    // announce what a press there cannot reach. Placed at the cell's
    // start and shrink-wrapped under loose constraints.
    return Align(
      alignment: AlignmentDirectional.topStart,
      widthFactor: 1,
      heightFactor: 1,
      // One stop after another in the card's own order, both ways: a
      // hidden overflow has no place on screen to be read off.
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: region,
      ),
    );
  }
}

/// The node around a card's part that hides, which knows its card.
class _CardPartNode extends FocusNode {
  _CardPartNode(this._card, {super.debugLabel});

  final _MediaCardState _card;

  /// The card's own node, when [node] is inside one of its parts that was
  /// hidden when focus reached it.
  static FocusNode? cardOfHidden(FocusNode? node) {
    for (var at = node; at != null; at = at.parent) {
      if (at is _CardPartNode) {
        return at._card._partsShown ? null : at._card._cardFocus;
      }
    }
    return null;
  }
}

/// Arrow-key focus moves that never stop on a card's hidden parts.
///
/// A [MediaCard]'s play disc and overflow stay focusable while hidden, so
/// that Shift+Tab mirrors Tab, and Flutter's arrow-key search ranks every
/// focusable node by the distance between centres, where a hidden disc
/// is nearer than its card. A move that lands on the disc or the overflow
/// of a card that is not revealed goes on to the card itself; every other
/// move is Flutter's own. Installed at an app's root through
/// [waxAppActions].
class WaxDirectionalFocusAction extends DirectionalFocusAction {
  @override
  void invoke(DirectionalFocusIntent intent) {
    super.invoke(intent);
    final manager = FocusManager.instance..applyFocusChangesIfNeeded();
    final card = _CardPartNode.cardOfHidden(manager.primaryFocus);
    if (card == null) return;
    // Scrolled into view as the move would have scrolled the card, not
    // the disc it found: the card reaches past the disc by its captions.
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      card,
      alignmentPolicy: switch (intent.direction) {
        TraversalDirection.up || TraversalDirection.left =>
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        TraversalDirection.down || TraversalDirection.right =>
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      },
    );
    manager.applyFocusChangesIfNeeded();
  }
}

/// A card's caption block, faded only in the mode that hides it.
///
/// The two branches lay out identically - opacity is paint, not layout -
/// which is what keeps `MediaCard.heightFor` true of both.
class _Captions extends StatelessWidget {
  const _Captions({
    required this.fading,
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool fading;
  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => fading
      ? AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          child: child,
        )
      : child;
}

/// A list row: artwork, title, caption, trailing readout, and the slot
/// where the playing indicator goes.
class MediaListRow extends StatelessWidget {
  const MediaListRow({
    required this.data,
    this.onTap,
    this.onMore,
    this.moreSemanticsId,
    this.moreLabel,
    this.onLongPress,
    this.onSelect,
    this.selectSemanticsId,
    this.leadingIndex,
    this.leadingText,
    this.actions = const <Widget>[],
    this.playing = false,
    this.selected = false,
    this.artSize = defaultArtSize,
    super.key,
  });

  /// The artwork edge a row draws at unless a caller says otherwise.
  /// Named so a caller warming covers ahead of a scroll can ask for the
  /// size rung the row will paint at rather than repeat the number.
  static const double defaultArtSize = 40;

  final MediaTileData data;
  final VoidCallback? onTap;

  /// The row's overflow: draws a button, and is what a long press and a
  /// right click open.
  final VoidCallback? onMore;

  /// The overflow button's own identifier, for rows whose overflow a
  /// test drives. The button is a control of its own beside the row's,
  /// so it does not inherit the row's identifier.
  final String? moreSemanticsId;

  /// The overflow button's accessible name, for a row whose menu is
  /// worth naming as something more specific than "More". Null takes
  /// the design system's own wording.
  final String? moreLabel;

  /// A long press with no menu behind it. Starting a multi-select is
  /// the one so far. Kept apart from [onMore] because that one draws a
  /// control, and a button announcing "More for [title]" whose only
  /// action is to start selecting is a lie about what it opens.
  /// Where a row wants both, this wins the long press: a surface keeps
  /// long-press-to-select while the kebab and a right click open the
  /// menu.
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
  /// moves - a title and a caption at 1.5x are taller than the density's
  /// row height, so an estimate made from that alone lands short by more
  /// with every row it counts.
  ///
  /// Rows carrying a resume sliver are a few pixels taller than this.
  /// Nothing measures those: the surfaces that scroll by index are the
  /// music indexes, whose rows have no position to draw.
  static double heightFor(
    BuildContext context, {
    double artSize = defaultArtSize,
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
    final l10n = context.waxL10n;

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
            ? const PlayingIndicator(playing: true, size: 14)
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
        if (playing) l10n.commonPlaying,
        if (data.unplayed) l10n.cardsUnplayed,
        data.title,
        data.subtitle,
        data.trailingSpoken ?? data.trailingText,
      ].nonNulls.join(', '),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress ?? onMore,
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
              padding: const EdgeInsetsDirectional.only(end: WaxSpace.s8),
              child: WaxIcon(
                WaxIcons.star,
                size: 14,
                active: true,
                color: colors.accent,
              ),
            ),
          if (data.downloaded)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: WaxSpace.s8),
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
            label: selected
                ? l10n.cardsDeselectItem(data.title)
                : l10n.cardsSelectItem(data.title),
            child: Checkbox(
              value: selected,
              onChanged: (value) => onSelect!(value ?? false),
            ),
          ),
        Expanded(child: content),
        // Outside the content, not inside it beside the duration: the
        // content's label is built with `excludeSemantics`, so a node
        // drawn in there would be invisible to a screen reader and to
        // the suite alike. Its own node is also the better reading -
        // "played 5 times" after the row rather than buried in its
        // name.
        if (data.trailingDetail != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: WaxSpace.s8),
            child: Semantics(
              identifier: data.trailingDetailSemanticsId,
              label: data.trailingDetailSpoken ?? data.trailingDetail,
              excludeSemantics: true,
              child: Text(
                data.trailingDetail!,
                style: WaxType.monoTime.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
        ...actions,
        if (onMore != null)
          WaxIconButton(
            glyph: WaxIcons.more,
            label: moreLabel ?? l10n.cardsMoreForItem(data.title),
            size: 18,
            semanticsId: moreSemanticsId,
            onPressed: onMore,
          ),
      ],
    );

    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      // As on the card: suppression follows the rows that answer the
      // gesture, and nothing else on the page loses the browser's menu.
      child: WaxSecondaryTapRegion(
        enabled: onMore != null,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: onMore,
          onLongPress: onLongPress ?? onMore,
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
      ),
    );
  }
}

/// The one bottom sheet every row menu shares, holding the browser's menu
/// off as [showWaxMenu] does. Rows scroll unless [scrolls] is false (a sheet
/// scrolling its own under a pinned header); answers what it closed with.
Future<T?> showWaxOptionSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrolls = true,
}) {
  final colors = WaxColors.of(context);
  const padding = EdgeInsets.fromLTRB(
    WaxSpace.s16,
    0,
    WaxSpace.s16,
    WaxSpace.s24,
  );
  return waxWithoutBrowserMenu(
    () => showWaxSheet<T>(
      context: context,
      backgroundColor: colors.surface2,
      builder: (sheetContext) => SafeArea(
        child: scrolls
            ? SingleChildScrollView(
                padding: padding,
                child: builder(sheetContext),
              )
            : Padding(padding: padding, child: builder(sheetContext)),
      ),
    ),
  );
}

/// A glyph, a name, a line under it, and something on the right.
///
/// The house row for lists that are not media: the device picker's
/// endpoints, a cast diagnostic's candidate bases, a settings list. Beside
/// [MediaListRow] rather than inside it because the leading slot is the
/// difference and it is not a small one - a media row's leading slot is
/// artwork, which means a monogram when there is none, and a speaker drawn
/// as the letter K is not a speaker.
///
/// One announcement per row, with the controls the caller puts in
/// [trailing] keeping their own nodes: the label sits on the content
/// region, for the reason [MediaListRow] records at length - excluding a
/// whole row's subtree takes its own controls out of the semantics tree
/// while leaving them perfectly visible.
class WaxOptionRow extends StatelessWidget {
  const WaxOptionRow({
    required this.title,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.glyph,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.active = false,
    this.activeLabel = houseActiveLabel,
    this.spokenSubtitle,
    this.semanticsId,
    super.key,
  });

  final String title;

  /// The line under the name: what a device is, why it cannot be used,
  /// what is playing on it.
  final String? subtitle;

  /// How far [subtitle] may run before it is cut. Two lines keeps a list
  /// of rows scannable, which is the right default for a line that
  /// describes a row - and the wrong one for a line that carries a
  /// message from somewhere else. A server's delivery error is a
  /// sentence somebody has to read to the end to act on, so the rows
  /// that put one here raise this rather than ellipsing the part that
  /// says what went wrong.
  final int subtitleMaxLines;

  /// The leading glyph. [leading] wins where a caller has a whole widget
  /// to put there (a logo, a spinner).
  final WaxGlyph? glyph;
  final Widget? leading;

  /// A control or a readout on the trailing edge. Keeps its own semantics.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// False greys the row and refuses the tap, for an option that exists
  /// and cannot be taken right now - an endpoint that has gone offline.
  /// The row still says why in [subtitle], which is the difference between
  /// disabled and hidden.
  final bool enabled;

  final bool selected;

  /// Tints the glyph and the name, and by default announces the row as
  /// playing: this is where the sound is.
  final bool active;

  /// What a screen reader hears before the title while [active]. Null for a
  /// highlight that is not about playback: the connection check's reachable
  /// addresses would otherwise all announce as playing.
  ///
  /// Defaults to [houseActiveLabel], which resolves to the design
  /// system's own word once a BuildContext is in hand.
  final String? activeLabel;

  /// Stands for "whatever this locale calls playing". It cannot be the
  /// literal it replaced, because the word is not known until a
  /// BuildContext resolves the table - and it cannot be null, because an
  /// explicit null is the opt-out above and the two have to stay
  /// tellable apart.
  static const String houseActiveLabel = 'wax.optionRow.houseActiveLabel';

  /// What a screen reader hears instead of [subtitle], where the drawn
  /// line is abbreviated for the room it has.
  final String? spokenSubtitle;

  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final announced = activeLabel == houseActiveLabel
        ? context.waxL10n.commonPlaying
        : activeLabel;
    final tappable = enabled && onTap != null;
    final titleColor = !enabled
        ? colors.textDisabled
        : (active ? colors.accent : colors.textPrimary);

    final inside = Row(
      children: <Widget>[
        if (leading != null)
          leading!
        else if (glyph != null)
          WaxIcon(
            glyph!,
            size: 22,
            active: active,
            color: !enabled
                ? colors.textDisabled
                : (active ? colors.accent : colors.textSecondary),
          ),
        if (leading != null || glyph != null)
          const SizedBox(width: WaxSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaxType.titleItem.copyWith(color: titleColor),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: WaxType.caption.copyWith(
                    color: enabled ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final announcement = <String?>[
      if (active) announced,
      title,
      spokenSubtitle ?? subtitle,
    ].nonNulls.join(', ');

    // The content is what carries the row's identity and its tap, and
    // [trailing] sits outside it. That split is the point: the wrapper
    // excludes its subtree so the row announces once, and a trailing
    // control inside that subtree would be dropped from the semantics
    // tree while looking perfectly fine - the defect MediaListRow shipped
    // and the reason it is a comment there too.
    final Widget content = tappable
        ? WaxTappable(
            label: announcement,
            onPressed: onTap,
            selected: selected ? true : null,
            semanticsId: semanticsId,
            child: InkWell(onTap: onTap, child: inside),
          )
        : Semantics(
            identifier: semanticsId,
            // A row that is not tappable is still a row: an offline
            // endpoint says what it is and that it cannot be chosen, and
            // dropping its node would make it invisible rather than
            // unavailable.
            button: onTap != null,
            enabled: enabled,
            selected: selected,
            label: announcement,
            excludeSemantics: true,
            child: inside,
          );

    return Material(
      color: selected ? colors.surface2 : Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: layout.rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s16,
            vertical: WaxSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: content),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: WaxSpace.s8),
                trailing!,
              ],
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
///
/// The header is the title alone, no eyebrow: a shelf title has to be
/// self-evident, and every overline a shelf ever carried turned out to
/// restate it ("New to the collection" over "Recently added"). Surfaces
/// that are not shelves keep [SectionHeader.overline].
///
/// Paging chevrons sit over the row's edges while there is somewhere
/// to go that way: resting visible on desktop, hover-armed on touch.
/// A page is a viewport's worth of whole cards on the flick's snap
/// grid, and the overflow side wears an [EdgeFade] at rest.
class ShelfRow extends StatefulWidget {
  const ShelfRow({
    required this.title,
    required this.items,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    this.onTapItem,
    this.onPlayItem,
    this.onMoreItem,
    this.itemHasActions,
    this.moreSemanticsIdAt,
    this.playSemanticsIdAt,
    this.backSemanticsId,
    this.forwardSemanticsId,
    this.cardWidth,
    this.padding,
    super.key,
  });

  final String title;
  final List<MediaTileData> items;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The handle for the "Show all" control. The shelf itself is not a
  /// control and has none; this is.
  final String? actionSemanticsId;
  final void Function(MediaTileData item)? onTapItem;
  final void Function(MediaTileData item)? onPlayItem;

  /// The card's own overflow: a hover chip over the artwork and a right
  /// click with a pointer, a long press on touch. The gesture is the
  /// whole affordance on touch, so a shelf that spends the long press on
  /// something else cannot also take this.
  final void Function(MediaTileData item)? onMoreItem;

  /// Which cards [onPlayItem] and [onMoreItem] reach, for a shelf whose
  /// cards differ. Null reaches every card.
  final bool Function(MediaTileData item)? itemHasActions;

  /// Each card's overflow chip identifier, by position, for cards whose
  /// own handles are positional too: a card keyed by its item carries its
  /// chip when it moves, and the chip's label would not change with it.
  final String Function(int index)? moreSemanticsIdAt;

  /// Each card's play affordance identifier, by position, for the same
  /// reason.
  final String Function(int index)? playSemanticsIdAt;

  /// Chevron handles, as plain strings: the package takes no registry
  /// dependency.
  final String? backSemanticsId;
  final String? forwardSemanticsId;

  final double? cardWidth;
  final EdgeInsets? padding;

  @override
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> {
  final _controller = ScrollController();
  final _pointerOver = ValueNotifier<bool>(false);
  final _canPage = ValueNotifier<({bool back, bool forward})>((
    back: false,
    forward: false,
  ));
  var _syncScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    _pointerOver.dispose();
    _canPage.dispose();
    super.dispose();
  }

  /// Re-reads which directions have anywhere to go, a frame late on
  /// purpose: metrics notifications can arrive during layout, where
  /// rebuilding is illegal, and a chevron appearing a frame later is
  /// invisible. Notifications rather than a controller listener, because
  /// only they fire when the viewport resizes without a scroll - the
  /// shrink that strands overflow is exactly when the forward chevron
  /// has to arm. The answer lands in a ValueNotifier rather than
  /// setState: a whole-row rebuild per scroll frame would re-run every
  /// card's builder to move two booleans nothing else reads, and a
  /// write with the same value notifies nobody.
  bool _scheduleSync() {
    if (_syncScheduled) return false;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      _canPage.value = (
        back:
            position.pixels >
            position.minScrollExtent + precisionErrorTolerance,
        forward:
            position.pixels <
            position.maxScrollExtent - precisionErrorTolerance,
      );
    });
    // Metrics changes are dispatched from a post-layout microtask, so
    // the callback above may be registered with no frame scheduled - and
    // nothing else would schedule one, leaving the guard stuck and every
    // later notification swallowed.
    SchedulerBinding.instance.scheduleFrame();
    return false;
  }

  void _page({required bool forward, required SnapScrollPhysics physics}) {
    final position = _controller.position;
    final pitch = physics.itemExtent;
    // A viewport's worth of whole cards, at least one: paging by the
    // raw viewport would land mid-card and leave the snap physics to
    // finish the move somewhere nobody chose.
    final cards = math.max(
      1,
      ((position.viewportDimension + WaxShellMetrics.gridGap) / pitch).floor(),
    );
    final raw = position.pixels + (forward ? cards : -cards) * pitch;
    // The physics' own landing grid, through the physics' own formula,
    // so a page and a flick cannot quietly disagree about where cards
    // rest.
    var target = physics.snapFor(raw, position);
    // The grid's first landing sits one inset past the true start, and
    // paging back would stop there - leading gutter scrolled away, back
    // chevron still armed, a second click needed for sixteen pixels.
    // Within a card of the start, go home.
    if (!forward && target - position.minScrollExtent < pitch) {
      target = position.minScrollExtent;
    }
    final motion = WaxMotion.of(context);
    if (!motion.animationsEnabled) {
      _controller.jumpTo(target);
      return;
    }
    unawaited(
      _controller.animateTo(
        target,
        duration: motion.standard,
        curve: WaxMotion.emphasized,
      ),
    );
  }

  /// The width of the fade the overflow side wears at rest.
  static const double _overflowFade = WaxSpace.s24;

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.waxL10n;
    final gutter = widget.padding ?? sizeClass.gutter;
    final width = widget.cardWidth ?? sizeClass.gridExtent;
    final physics = SnapScrollPhysics(
      itemExtent: width + WaxShellMetrics.gridGap,
      leadingInset: gutter.left,
    );
    final items = widget.items;
    // Each card keyed by its handle, numbered among the cards sharing it,
    // so it moves with its item, node and all, when the shelf reorders.
    final seen = <String, int>{};
    final keys = <Key?>[
      for (final item in items)
        if (item.semanticsId case final id?)
          ValueKey<(String, int)>((id, seen[id] = (seen[id] ?? -1) + 1))
        else
          null,
    ];
    // The carets are direction-fixed glyphs, so RTL swaps the pair.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: gutter,
          child: SectionHeader(
            title: widget.title,
            actionLabel: widget.actionLabel,
            onAction: widget.onAction,
            semanticsId: widget.actionSemanticsId,
          ),
        ),
        MouseRegion(
          onEnter: (_) {
            _pointerOver.value = true;
            // Fresh availability for the pointer that just arrived:
            // nothing re-reads it while the row sits still.
            _scheduleSync();
          },
          onExit: (_) => _pointerOver.value = false,
          child: SizedBox(
            height: MediaCard.heightFor(context, width: width),
            child: Stack(
              children: <Widget>[
                // The row is the builder's child: moving the mask
                // never re-runs a card's builder.
                ValueListenableBuilder<({bool back, bool forward})>(
                  valueListenable: _canPage,
                  builder: (context, can, child) => EdgeFade(
                    start: can.back ? _overflowFade : 0,
                    end: can.forward ? _overflowFade : 0,
                    child: child!,
                  ),
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) => _scheduleSync(),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) => _scheduleSync(),
                      // Mouse drag joins touch for this row alone: the
                      // app-wide setting would take click-drag text
                      // selection with it wherever prose scrolls.
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: <PointerDeviceKind>{
                            ...ScrollConfiguration.of(context).dragDevices,
                            PointerDeviceKind.mouse,
                          },
                        ),
                        child: ListView.separated(
                          controller: _controller,
                          scrollDirection: Axis.horizontal,
                          padding: gutter,
                          physics: physics,
                          itemCount: items.length,
                          findItemIndexCallback: indexByKey(keys, (key) => key),
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: WaxShellMetrics.gridGap),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final onTap = widget.onTapItem;
                            final acts =
                                widget.itemHasActions?.call(item) ?? true;
                            final onPlay = acts ? widget.onPlayItem : null;
                            final onMore = acts ? widget.onMoreItem : null;
                            return MediaCard(
                              key: keys[index],
                              data: item,
                              width: width,
                              onTap: onTap == null ? null : () => onTap(item),
                              onPlay: onPlay == null
                                  ? null
                                  : () => onPlay(item),
                              onMore: onMore == null
                                  ? null
                                  : () => onMore(item),
                              moreSemanticsId: widget.moreSemanticsIdAt?.call(
                                index,
                              ),
                              playSemanticsId: widget.playSemanticsIdAt?.call(
                                index,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                // Centred on the artwork band; the insets pull back
                // by the halo so the circle sits where it always has.
                PositionedDirectional(
                  start: WaxSpace.s8 - _ShelfChevron.halo,
                  top: width / 2 - _ShelfChevron.radius - _ShelfChevron.halo,
                  child: _ChevronSlot(
                    pointerOver: _pointerOver,
                    canPage: _canPage,
                    forward: false,
                    glyph: rtl ? WaxIcons.forward : WaxIcons.backward,
                    label: l10n.shelfPageBack,
                    semanticsId: widget.backSemanticsId,
                    onTap: () => _page(forward: false, physics: physics),
                  ),
                ),
                PositionedDirectional(
                  end: WaxSpace.s8 - _ShelfChevron.halo,
                  top: width / 2 - _ShelfChevron.radius - _ShelfChevron.halo,
                  child: _ChevronSlot(
                    pointerOver: _pointerOver,
                    canPage: _canPage,
                    forward: true,
                    glyph: rtl ? WaxIcons.backward : WaxIcons.forward,
                    label: l10n.shelfPageForward,
                    semanticsId: widget.forwardSemanticsId,
                    onTap: () => _page(forward: true, physics: physics),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One chevron's corner of the shelf: gone with nowhere to go,
/// resting dimmed on desktop, full under the pointer.
class _ChevronSlot extends StatelessWidget {
  const _ChevronSlot({
    required this.pointerOver,
    required this.canPage,
    required this.forward,
    required this.glyph,
    required this.label,
    required this.semanticsId,
    required this.onTap,
  });

  final ValueListenable<bool> pointerOver;
  final ValueListenable<({bool back, bool forward})> canPage;
  final bool forward;
  final WaxGlyph glyph;
  final String label;
  final String? semanticsId;
  final VoidCallback onTap;

  /// A desktop platform with a mouse actually connected: the platform
  /// alone lies both ways (a touch-only web tablet reports linux, a
  /// phone can pair a mouse), so the tracker answers the hardware half.
  static bool get _restsVisible {
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
    return desktop && RendererBinding.instance.mouseTracker.mouseIsConnected;
  }

  @override
  Widget build(BuildContext context) {
    final motion = WaxMotion.of(context);
    // The tracker notifies when a mouse arrives or leaves.
    return ListenableBuilder(
      listenable: RendererBinding.instance.mouseTracker,
      builder: (context, _) => ValueListenableBuilder<bool>(
        valueListenable: pointerOver,
        builder: (context, over, _) =>
            ValueListenableBuilder<({bool back, bool forward})>(
              valueListenable: canPage,
              builder: (context, can, _) {
                final armed = forward ? can.forward : can.back;
                return AnimatedSwitcher(
                  duration: motion.quick,
                  // A FadeTransition stops painting, not hit testing
                  // or semantics: ungated, a retired chevron answered
                  // taps invisibly for the length of the cross-fade.
                  transitionBuilder: (child, animation) => AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) {
                      final retiring =
                          animation.status == AnimationStatus.reverse ||
                          animation.status == AnimationStatus.dismissed;
                      return IgnorePointer(
                        ignoring: retiring,
                        child: ExcludeSemantics(
                          excluding: retiring,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                      );
                    },
                  ),
                  child: armed && (over || _restsVisible)
                      ? _ShelfChevron(
                          glyph: glyph,
                          label: label,
                          semanticsId: semanticsId,
                          dimmed: !over,
                          onTap: onTap,
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
      ),
    );
  }
}

/// One paging chevron over a shelf's edge.
///
/// A named semantics button (an excluded node has no web DOM element,
/// so its clicks fell to the card beneath), kept out of the focus tree
/// - the cards are the keyboard path. The 32px circle centres in a
/// [WaxSpace.touchTarget] box whose halo claims taps only.
class _ShelfChevron extends StatelessWidget {
  const _ShelfChevron({
    required this.glyph,
    required this.label,
    required this.semanticsId,
    required this.dimmed,
    required this.onTap,
  });

  static const double radius = WaxSpace.pointerTarget / 2;

  /// How far the hit box extends past the circle on each side.
  static const double halo =
      (WaxSpace.touchTarget - WaxSpace.pointerTarget) / 2;

  /// Resting strength: enough to survive a dark cover, with hover as
  /// the step to full.
  static const double _restOpacity = 0.75;

  /// The ring in the primary text tone: no one colour clears 3:1 over
  /// both black and white art, so over any cover the ring or the disc
  /// does. The contrast test tunes this to the weakest pairing.
  static const double _ringAlpha = 0.7;

  final WaxGlyph glyph;
  final String label;
  final String? semanticsId;

  /// Resting on desktop; full strength under the row's hover.
  final bool dimmed;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      identifier: semanticsId,
      onTap: onTap,
      // Translucent: the halo wins a tap while drag, wheel, and the
      // card's right-click fall through. Detector and InkWell share
      // one onTap; give either another handler and a click fires twice.
      child: AnimatedOpacity(
        opacity: dimmed ? _restOpacity : 1,
        duration: motion.quick,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: onTap,
          child: SizedBox.square(
            dimension: WaxSpace.touchTarget,
            child: Center(
              child: Material(
                color: colors.surface1,
                shape: CircleBorder(
                  side: BorderSide(
                    color: colors.textPrimary.withValues(alpha: _ringAlpha),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  canRequestFocus: false,
                  excludeFromSemantics: true,
                  // Here, not an outer MouseRegion: the deeper region
                  // wins, and the off-web default is the basic arrow.
                  mouseCursor: SystemMouseCursors.click,
                  child: SizedBox.square(
                    dimension: radius * 2,
                    child: Center(
                      child: WaxIcon(
                        glyph,
                        size: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Snaps a shelf to card boundaries.
///
/// `PageScrollPhysics` pages by the viewport, not by the card pitch, and
/// knows nothing about the leading gutter, so a flick rests wherever the
/// page happens to land: half a card clipped at the edge. This settles on
/// whole cards, gutter included.
