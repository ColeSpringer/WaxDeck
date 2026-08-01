import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../icons/wax_icon.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'backdrop.dart';
import 'controls.dart';
import 'semantics_slots.dart';
import 'view_data.dart';

/// The transport row.
///
/// Music gets previous/next; spoken word swaps them for interval seeks;
/// radio drops them entirely, because there is nowhere to skip to on a
/// live stream. Controls appear only when they mean something.
class TransportCluster extends StatelessWidget {
  const TransportCluster({
    required this.playing,
    required this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onSkipBack,
    this.onSkipForward,
    this.onShuffle,
    this.onRepeat,
    this.shuffled = false,
    this.repeat = false,
    this.live = false,
    this.skipBackSeconds = 15,
    this.skipForwardSeconds = 30,
    this.size = 64,
    this.ids = const PlayerIds(),
    super.key,
  });

  final bool playing;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSkipBack;
  final VoidCallback? onSkipForward;
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeat;
  final bool shuffled;
  final bool repeat;
  final bool live;

  final int skipBackSeconds;
  final int skipForwardSeconds;

  /// Diameter of the play button. Car mode uses a much larger one.
  final double size;

  /// The e2e handles, supplied by the caller (see [PlayerIds]).
  final PlayerIds ids;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final spoken = onSkipBack != null || onSkipForward != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (onShuffle != null)
          WaxIconButton(
            glyph: WaxIcons.shuffle,
            label: shuffled ? 'Shuffle off' : 'Shuffle',
            active: shuffled,
            onPressed: onShuffle,
            semanticsId: ids.shuffle,
          ),
        if (spoken)
          WaxIconButton(
            glyph: WaxIcons.rewind,
            label: 'Back $skipBackSeconds seconds',
            size: 28,
            onPressed: onSkipBack,
            semanticsId: ids.skipBack,
          )
        else if (onPrevious != null)
          WaxIconButton(
            glyph: WaxIcons.previous,
            label: 'Previous',
            size: 28,
            onPressed: onPrevious,
            semanticsId: ids.previous,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
          child: Semantics(
            identifier: ids.play,
            button: true,
            label: playing ? (live ? 'Stop' : 'Pause') : 'Play',
            excludeSemantics: true,
            onTap: onPlayPause,
            child: Material(
              color: colors.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPlayPause,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: WaxIcon(
                      playing
                          ? (live ? WaxIcons.stop : WaxIcons.pause)
                          : WaxIcons.play,
                      size: size * 0.44,
                      active: true,
                      color: colors.onAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (spoken)
          WaxIconButton(
            glyph: WaxIcons.fastForward,
            label: 'Forward $skipForwardSeconds seconds',
            size: 28,
            onPressed: onSkipForward,
            semanticsId: ids.skipForward,
          )
        else if (onNext != null)
          WaxIconButton(
            glyph: WaxIcons.next,
            label: 'Next',
            size: 28,
            onPressed: onNext,
            semanticsId: ids.next,
          ),
        if (onRepeat != null)
          WaxIconButton(
            glyph: repeat ? WaxIcons.repeatOne : WaxIcons.repeatAll,
            label: repeat ? 'Repeat one' : 'Repeat',
            active: repeat,
            onPressed: onRepeat,
            semanticsId: ids.repeat,
          ),
      ],
    );
  }
}

/// The seek bar with its flanking timecodes, or the live pill for radio.
class SeekCluster extends StatelessWidget {
  const SeekCluster({
    required this.now,
    this.onSeek,
    this.peaks,
    this.remainingLabel,
    this.semanticsId,
    super.key,
  });

  final NowPlayingData now;
  final ValueChanged<Duration>? onSeek;

  /// Normalised peaks; when absent the bar renders as a styled slider
  /// rather than inventing a waveform.
  final List<double>? peaks;

  /// Books add "42 percent, 6 hr 12 min left" under the bar.
  final String? remainingLabel;

  /// The e2e handle for the seek bar, supplied by the caller.
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    if (now.live) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s12,
              vertical: WaxSpace.s4,
            ),
            decoration: BoxDecoration(
              color: colors.radio.container,
              borderRadius: WaxRadius.pill,
            ),
            child: Text(
              'LIVE',
              style: WaxType.overline.copyWith(color: colors.radio.onContainer),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        WaxSeekBar(
          position: now.position,
          duration: now.duration,
          buffered: now.buffered,
          peaks: peaks,
          onSeek: onSeek,
          semanticsId: semanticsId,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              formatTimecode(now.position),
              style: WaxType.monoTime.copyWith(color: colors.textSecondary),
            ),
            Text(
              formatTimecode(now.duration),
              style: WaxType.monoTime.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        if (remainingLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s4),
            child: Text(
              remainingLabel!,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// The full player: one scaffold, four faces.
///
/// Music, podcasts, audiobooks, and radio all render through here. The
/// medium configures the slots (which clusters exist, what the bottom
/// region holds); the scaffold owns the backdrop, the hero artwork, the
/// drag-to-dismiss affordance, and the landscape arrangement, so the
/// faces cannot drift apart.
class PlayerScaffold extends StatefulWidget {
  const PlayerScaffold({
    required this.now,
    required this.transport,
    required this.seek,
    this.onCollapse,
    this.actionRow,
    this.titleTrailing,
    this.volume,
    this.bottomRegion,
    this.trailingHeaderActions,
    this.ids = const PlayerIds(),
    super.key,
  });

  final NowPlayingData now;
  final Widget transport;
  final Widget seek;

  final VoidCallback? onCollapse;

  /// Lyrics, queue, mix, overflow: the per-medium verbs.
  final Widget? actionRow;

  /// Star and rating, which sit with the title rather than in the row of
  /// verbs.
  final Widget? titleTrailing;

  /// This surface's own output level, where the platform gives it one.
  /// Its own slot rather than a verb in the action row: it is live state
  /// with a track, not a button, and the row is a row of buttons.
  final Widget? volume;

  /// Up-next peek, chapters, notes, transcript.
  final Widget? bottomRegion;

  final List<Widget>? trailingHeaderActions;

  /// The e2e handles for the scaffold's own controls.
  final PlayerIds ids;

  @override
  State<PlayerScaffold> createState() => _PlayerScaffoldState();
}

class _PlayerScaffoldState extends State<PlayerScaffold>
    with SingleTickerProviderStateMixin {
  /// How far down the finger has taken the surface, in pixels. Never
  /// negative: the player is already as far up as it goes.
  double _drag = 0;

  /// The release, as a spring rather than a duration: a drag that is let
  /// go is still moving, and the settle has to carry that speed or it
  /// reads as the surface being caught.
  ///
  /// Built here rather than lazily: a player nobody dragged would
  /// otherwise build its first controller inside `dispose`, where the
  /// ticker has no live element to find.
  late final AnimationController _settle;

  /// Downward speed, in pixels a second, that dismisses whatever the
  /// distance was. A flick is a decision; waiting for it to cross a
  /// threshold is not.
  static const double _flingVelocity = 700;

  /// How far down the surface has to be, as a fraction of its own
  /// height, for a slow release to dismiss it.
  static const double _dismissFraction = 0.28;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _drag = math.max(0, _settle.value)));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _dragStart(DragStartDetails details) => _settle.stop();

  void _dragUpdate(DragUpdateDetails details) {
    setState(() => _drag = math.max(0, _drag + details.delta.dy));
  }

  void _dragEnd(DragEndDetails details) {
    final collapse = widget.onCollapse;
    final height = context.size?.height ?? 0;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (collapse != null &&
        (velocity > _flingVelocity ||
            (height > 0 && _drag > height * _dismissFraction))) {
      // The route's own exit takes it from here; springing back first
      // would be the surface arguing with the gesture.
      collapse();
      return;
    }
    if (!WaxMotion.of(context).animationsEnabled) {
      setState(() => _drag = 0);
      return;
    }
    _settle.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 500, damping: 34),
        _drag,
        0,
        // Downward flicks are handled above, so what arrives here is a
        // release that is going nowhere or heading back up; the spring
        // takes that speed with it.
        velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final size = MediaQuery.sizeOf(context);
    // Side by side when the window is wider than it is tall and there is
    // not much tall. Compact-landscape is the case 5.3 names, and the
    // reason it gives - a stack of clusters under a hero does not fit -
    // is about height rather than about width class: a 740x360 desktop
    // window is not compact and has the same problem, and stacking there
    // overflows by the last few pixels of the action row.
    final landscape =
        size.width > size.height &&
        (sizeClass.isCompact || size.height < _shortWindow);
    final now = widget.now;

    Widget surface = SafeArea(
      child: Column(
        children: <Widget>[
          _header(context, colors),
          Expanded(
            child: landscape
                ? _landscape(context, colors)
                : _portrait(context, colors),
          ),
          ?widget.bottomRegion,
        ],
      ),
    );

    if (_drag > 0) {
      // The content moves and the backdrop stays. The player is pushed
      // over whatever was underneath and nothing paints there during the
      // gesture, so sliding the whole surface would drag a hole into
      // view; the backdrop is atmosphere and holds still while the
      // content leaves through it.
      surface = Transform.translate(
        offset: Offset(0, _drag),
        child: Opacity(
          opacity: (1 - _drag / (size.height * 1.6)).clamp(0.35, 1.0),
          child: surface,
        ),
      );
    }

    return WaxBackdrop(
      domain: now.domain,
      // Its own Material context, transparent so the backdrop shows
      // through: this is a whole surface rather than a widget inside
      // one, and the controls on it - every ink response in the design
      // system - need an ancestor to splash onto. A caller that wrapped
      // this in a Scaffold would get its canvas over the backdrop.
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          identifier: widget.ids.surface,
          container: true,
          // Direct manipulation, so it tracks the finger even under
          // reduced motion: what that setting turns off is decoration,
          // not the ability to put something back where it came from.
          // The release is where it takes effect.
          child: GestureDetector(
            // Opaque, so the gesture is the whole surface's and not only
            // its widgets': the space around the artwork is most of a
            // player, and a dismissal that only worked where something
            // was drawn would read as broken. Children are hit-tested
            // first, so the controls keep their taps, and the seek bar's
            // horizontal drag and this vertical one are told apart by
            // direction rather than by who got there first.
            behavior: HitTestBehavior.opaque,
            // A pointer gesture and nothing else. Left in the semantics
            // tree, a vertical drag publishes scrollUp and scrollDown on
            // this node, and a screen-reader scroll then synthesises a
            // drag long enough to cross the dismiss threshold: swiping
            // to read the player would close it. The way out for a
            // screen reader is the collapse button, which says what it
            // does.
            excludeFromSemantics: true,
            onVerticalDragStart: widget.onCollapse == null ? null : _dragStart,
            onVerticalDragUpdate: widget.onCollapse == null
                ? null
                : _dragUpdate,
            onVerticalDragEnd: widget.onCollapse == null ? null : _dragEnd,
            child: surface,
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WaxColors colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
    child: Row(
      children: <Widget>[
        WaxIconButton(
          glyph: WaxIcons.collapse,
          label: 'Collapse player',
          onPressed: widget.onCollapse,
          semanticsId: widget.ids.collapse,
        ),
        Expanded(
          child: Center(
            child: widget.now.provenance == null
                ? const SizedBox.shrink()
                : Text(
                    widget.now.provenance!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
          ),
        ),
        ...?widget.trailingHeaderActions,
      ],
    ),
  );

  Widget _portrait(BuildContext context, WaxColors colors) {
    return Center(
      child: ConstrainedBox(
        // Desktop centres the same face rather than stretching it: a
        // player is a fixed-width object on a wide window, and queue and
        // lyrics prefer the side panel to an overlay there.
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
          child: Column(
            children: <Widget>[
              // The hero takes what the clusters below do not want,
              // rather than a fraction of the window. Both readings were
              // in this file at once - a width clamp and a height
              // fraction, added the second time this overflowed - and
              // neither can be right while what sits under the artwork
              // varies by face: the music face carries a volume row and
              // an action row that the first sketch of this did not.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The gutter above and below the artwork is taken
                    // out of the extent rather than wrapped around it: a
                    // Padding inside this Expanded demands its 32 px
                    // even after the flex has been squeezed to nothing,
                    // which is an overflow of exactly that padding on a
                    // window with no room left.
                    final extent = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight - WaxSpace.s32,
                    );
                    // Nothing left to draw art in: a very short window
                    // gives its height to the controls, which are what
                    // the surface is for.
                    if (extent < 96) return const SizedBox.shrink();
                    return Center(child: _hero(extent.clamp(96.0, 420.0)));
                  },
                ),
              ),
              _titleBlock(colors),
              const SizedBox(height: WaxSpace.s20),
              widget.seek,
              const SizedBox(height: WaxSpace.s16),
              widget.transport,
              if (widget.volume != null) ...<Widget>[
                const SizedBox(height: WaxSpace.s8),
                widget.volume!,
              ],
              if (widget.actionRow != null) ...<Widget>[
                const SizedBox(height: WaxSpace.s16),
                widget.actionRow!,
              ],
              const SizedBox(height: WaxSpace.s16),
            ],
          ),
        ),
      ),
    );
  }

  /// The artwork, at whatever extent the layout has for it.
  ///
  /// Podcast art is smaller by design (5.3): a show's cover is the same
  /// square on every episode, so it says less the larger it gets, and
  /// the room goes to the episode title and the chapter list instead.
  Widget _hero(double extent) => Hero(
    tag: 'deck-artwork',
    child: ArtworkImage(
      size: widget.now.domain == WaxDomain.podcasts
          ? math.min(extent, 200)
          : extent,
      artwork: widget.now.artwork,
      monogram: widget.now.title,
      shape: widget.now.shape,
      domain: widget.now.domain,
    ),
  );

  /// Under this height a stacked face does not fit its own clusters, so
  /// the arrangement goes side by side whatever the width class says.
  static const double _shortWindow = 480;

  /// The narrowest the landscape control column is allowed to get.
  ///
  /// The transport is the widest thing in it and does not wrap: five
  /// controls around a 64 px play button measure 272, so a column given
  /// less than that overflows however small the artwork beside it is.
  /// The hero yields first, and disappears rather than squeezing the
  /// controls off the edge.
  static const double _landscapeControlsMin = 288;

  /// Landscape is a side-by-side arrangement of the same slots, owned
  /// here so the four faces inherit it rather than each inventing a
  /// letterboxed portrait layout.
  Widget _landscape(BuildContext context, WaxColors colors) {
    final height = MediaQuery.sizeOf(context).height;
    final width = MediaQuery.sizeOf(context).width;
    // Sized by both axes. The height it can fill is the obvious bound
    // and it was the only one here, which is how a 568x320 window ended
    // up drawing 256 px of artwork beside a column with 240 px for
    // controls that need 272.
    final room =
        width - WaxSpace.s24 * 2 - WaxSpace.s24 - _landscapeControlsMin;
    final extent = math.min(height - WaxSpace.s64, room);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (extent >= 96) ...<Widget>[
            _hero(extent.clamp(96.0, 260.0)),
            const SizedBox(width: WaxSpace.s24),
          ],
          Expanded(
            // The controls need what they need, and a short window or a
            // large text scale can leave them more than the height
            // there is. Scrolling is what gives; a drag started in here
            // belongs to the scroll rather than to the dismissal, which
            // is why the artwork side stays the drag handle.
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _titleBlock(colors, alignStart: true),
                  const SizedBox(height: WaxSpace.s16),
                  widget.seek,
                  const SizedBox(height: WaxSpace.s12),
                  widget.transport,
                  if (widget.volume != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s8),
                    widget.volume!,
                  ],
                  if (widget.actionRow != null) ...<Widget>[
                    const SizedBox(height: WaxSpace.s12),
                    widget.actionRow!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleBlock(WaxColors colors, {bool alignStart = false}) => Column(
    crossAxisAlignment: alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              widget.now.title,
              textAlign: alignStart ? TextAlign.start : TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
            ),
          ),
          if (widget.titleTrailing != null) ...<Widget>[
            const SizedBox(width: WaxSpace.s8),
            widget.titleTrailing!,
          ],
        ],
      ),
      if (widget.now.subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: WaxSpace.s4),
          child: Text(
            widget.now.subtitle!,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
        ),
    ],
  );
}
