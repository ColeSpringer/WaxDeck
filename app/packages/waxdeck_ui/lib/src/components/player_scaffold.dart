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
    this.marks,
    this.remainingLabel,
    this.semanticsId,
    super.key,
  });

  final NowPlayingData now;
  final ValueChanged<Duration>? onSeek;

  /// Normalised peaks; when absent the bar renders as a styled slider
  /// rather than inventing a waveform.
  final List<double>? peaks;

  /// Divisions to tick along the bar: a book's chapters under a
  /// whole-book envelope.
  final List<Duration>? marks;

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
          marks: marks,
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
    this.heroOverlay,
    this.titleOverline,
    this.subtitleOverride,
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

  /// Drawn over the artwork at its own extent: radio's platter ring.
  /// Decoration rather than a control, so it is expected to ignore
  /// pointers and the hero keeps its own gestures.
  final Widget? heroOverlay;

  /// What the title belongs to, above it: the show an episode is from.
  /// Its own slot because it is a link rather than a caption, and
  /// because the line under the title is already spoken for (an
  /// artist, a chapter).
  final Widget? titleOverline;

  /// The line under the title, when it is live rather than fixed: a
  /// book's chapter changes while the title does not, and the face that
  /// draws it must be able to tick without rebuilding the hero. Takes
  /// the place of [NowPlayingData.subtitle].
  final Widget? subtitleOverride;

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
          if (widget.bottomRegion != null)
            _ContentIsland(child: widget.bottomRegion!),
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
          // A handle on the surface, not a description of it. Without
          // this the title, the artist, and both timecodes fold into
          // this node's label: the player is one string that counts up
          // once a second, and its text is addressable nowhere else.
          // Same guard, same reason, as the deck bar.
          explicitChildNodes: true,
          // Direct manipulation, so it tracks the finger even under
          // reduced motion: what that setting turns off is decoration,
          // not the ability to put something back where it came from.
          // The release is where it takes effect.
          child: MouseRegion(
            // The one hover affordance: over the space that dismisses,
            // the pointer says so. The content islands below put it back
            // to an arrow, because over them nothing happens.
            cursor: widget.onCollapse == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
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
              // to read the player would close it. The same exclusion is
              // what keeps the tap below from publishing an action, which
              // matters more on web: a tappable node is drawn as a rect
              // with pointer-events over the whole surface, and a screen
              // reader would find a nameless control the size of the
              // window. The way out for a screen reader is the collapse
              // button, which says what it does.
              excludeFromSemantics: true,
              // Pointers have no pull-down. Tapping off the content is
              // how a modal surface is dismissed with a mouse, and the
              // gesture rides the detector that already owns the drag so
              // the two cannot disagree about where the surface ends:
              // one policy, and a null onCollapse turns off both.
              onTap: widget.onCollapse,
              onVerticalDragStart: widget.onCollapse == null
                  ? null
                  : _dragStart,
              onVerticalDragUpdate: widget.onCollapse == null
                  ? null
                  : _dragUpdate,
              onVerticalDragEnd: widget.onCollapse == null ? null : _dragEnd,
              child: surface,
            ),
          ),
        ),
      ),
    );
  }

  /// The gutter each header control keeps around itself.
  ///
  /// Taken out of the header's own padding rather than added to it, so
  /// the controls sit exactly where they always did and the pixels
  /// beside them change hands instead: they belong to the control's
  /// island now, not to the dismissing surface. Without a buffer a thumb
  /// a few pixels off the overflow menu lands on the centre stretch and
  /// shuts the player, and islanding the buttons alone cannot fix that -
  /// an island wraps its child exactly, so it adds no room to miss into.
  static const EdgeInsets _headerControlGutter = EdgeInsets.symmetric(
    horizontal: WaxSpace.s8,
  );

  Widget _header(BuildContext context, WaxColors colors) => Row(
    children: <Widget>[
      // The controls are islands, the stretch between them is not. The
      // centre stays dismissing on purpose: on a phone the content box
      // is the full width, and this stretch is the only region a tap
      // can land in.
      _ContentIsland(
        child: Padding(
          padding: _headerControlGutter,
          child: WaxIconButton(
            glyph: WaxIcons.collapse,
            label: 'Collapse player',
            onPressed: widget.onCollapse,
            semanticsId: widget.ids.collapse,
          ),
        ),
      ),
      Expanded(
        child: Center(
          child: widget.now.provenance == null
              ? const SizedBox.shrink()
              : Text(
                  widget.now.provenance!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WaxType.caption.copyWith(color: colors.textSecondary),
                ),
        ),
      ),
      if (widget.trailingHeaderActions != null)
        _ContentIsland(
          child: Padding(
            padding: _headerControlGutter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.trailingHeaderActions!,
            ),
          ),
        ),
    ],
  );

  Widget _portrait(BuildContext context, WaxColors colors) {
    return Center(
      child: _ContentIsland(
        child: ConstrainedBox(
          // Desktop centres the same face rather than stretching it: a
          // player is a fixed-width object on a wide window, and queue
          // and lyrics prefer the side panel to an overlay there. On a
          // wide window the gutters either side of this box are what a
          // pointer clicks to leave; on a phone the box is the width and
          // the header's stretch is the whole of that region.
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
            child: LayoutBuilder(
              builder: (context, outer) => Column(
                children: <Widget>[
                  // The hero takes what the clusters below do not want,
                  // rather than a fraction of the window. Both readings
                  // were in this file at once - a width clamp and a height
                  // fraction, added the second time this overflowed - and
                  // neither can be right while what sits under the artwork
                  // varies by face: the music face carries a volume row
                  // and an action row that the first sketch of this did
                  // not.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // The gutter above and below the artwork is taken
                        // out of the extent rather than wrapped around it:
                        // a Padding inside this Expanded demands its 32 px
                        // even after the flex has been squeezed to
                        // nothing, which is an overflow of exactly that
                        // padding on a window with no room left.
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
                  // Bounded to the whole slot and scrollable inside it,
                  // which is what keeps the flex above honest. As a
                  // free-height child the clusters simply took what they
                  // wanted, and a face whose action row wrapped to a
                  // second line - or a large text scale, or a short
                  // window - overflowed by whatever it wanted past the
                  // end. Under the cap they take their natural height
                  // while there is room, and the hero yields first;
                  // past it they scroll and the hero is gone.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: outer.maxHeight),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
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
                ],
              ),
            ),
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
  Widget _hero(double extent) {
    final size = widget.now.domain == WaxDomain.podcasts
        ? math.min(extent, 200.0)
        : extent;
    final art = Hero(
      tag: 'deck-artwork',
      child: ArtworkImage(
        size: size,
        artwork: widget.now.artwork,
        monogram: widget.now.title,
        // The face is the one surface where the artwork *is* the
        // identification: a station with no logo and no matched track
        // gets its name, set, rather than two letters on a swatch.
        placeholder: widget.now.domain == WaxDomain.radio
            ? ArtworkPlaceholder.wordmark
            : ArtworkPlaceholder.initials,
        shape: widget.now.shape,
        domain: widget.now.domain,
      ),
    );
    if (widget.heroOverlay == null) return art;
    // Sized to the artwork rather than to the slot: the overlay is a
    // ring around the cover, and a stack that filled the extent would
    // draw it around the gutter on a podcast, whose art is smaller than
    // the room it is given.
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[art, widget.heroOverlay!],
      ),
    );
  }

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
    return LayoutBuilder(
      builder: (context, constraints) =>
          _landscapeRow(context, colors, constraints),
    );
  }

  Widget _landscapeRow(
    BuildContext context,
    WaxColors colors,
    BoxConstraints constraints,
  ) {
    // Both axes of the slot this is drawn in, not of the window. The
    // window was what this measured, and the slot is the window less the
    // header, the system insets, and the bottom region - which was
    // nothing until the spoken-word faces gained one, and is a third of
    // the difference now. A hero sized from the window overflowed a
    // short landscape window by whatever the region took.
    final height = constraints.maxHeight;
    final width = constraints.maxWidth;
    // Sized by both axes. The height it can fill is the obvious bound
    // and it was the only one here, which is how a 568x320 window ended
    // up drawing 256 px of artwork beside a column with 240 px for
    // controls that need 272.
    final room =
        width - WaxSpace.s24 * 2 - WaxSpace.s24 - _landscapeControlsMin;
    final extent = math.min(height - WaxSpace.s64, room);
    return Padding(
      // Inside the padding rather than around it, so the gutters this
      // leaves are still surface: landscape puts the content edge to
      // edge, and these two strips plus the header are the whole of what
      // a pointer has to click on.
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
      child: _ContentIsland(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (extent >= 96) ...<Widget>[
              _hero(extent.clamp(96.0, 260.0)),
              const SizedBox(width: WaxSpace.s24),
            ],
            Expanded(
              // The controls need what they need, and a short window or
              // a large text scale can leave them more than the height
              // there is. Scrolling is what gives; a drag started in
              // here belongs to the scroll rather than to the dismissal,
              // which is why the artwork side stays the drag handle.
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
      ),
    );
  }

  Widget _titleBlock(WaxColors colors, {bool alignStart = false}) => Column(
    crossAxisAlignment: alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: <Widget>[
      if (widget.titleOverline != null)
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s4),
          child: widget.titleOverline!,
        ),
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
      if (widget.subtitleOverride != null)
        Padding(
          padding: const EdgeInsets.only(top: WaxSpace.s4),
          child: widget.subtitleOverride!,
        )
      else if (widget.now.subtitle != null)
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

/// A region of the player a tap must not dismiss.
///
/// A no-op tap rather than an [AbsorbPointer]: absorbing would take the
/// surface's vertical drag with it, and a pull started on the artwork or
/// the title is how the player has come down since before there was a
/// tap to compete with. Claiming only the tap leaves the drag arena
/// exactly as it was - this detector enters no drag recognizer, so the
/// surface's still wins one - while a tap that lands here is spent here.
///
/// It publishes nothing: the island is a hit-test fact, and a semantics
/// node for it would be a control with no name wrapped around the
/// controls that do have names.
class _ContentIsland extends StatelessWidget {
  const _ContentIsland({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Undoes the surface's click cursor. The buttons inside set their
    // own and sit deeper still, so this only ever paints the gaps
    // between them.
    cursor: SystemMouseCursors.basic,
    child: GestureDetector(
      // The whole box, not only where something is drawn: the slack
      // between the transport and the action row is content the same way
      // the buttons are, and a thumb that lands a few pixels off a
      // control has not asked to leave.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      excludeFromSemantics: true,
      child: child,
    ),
  );
}
