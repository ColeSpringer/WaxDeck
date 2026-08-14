import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'controls.dart';
import 'indicators.dart';
import 'semantics_slots.dart';
import 'view_data.dart';

/// What the deck bar can do, wired by the shell.
///
/// Gestures are all optional and every one has a button equivalent: the
/// bar is tappable, but nothing is only swipeable.
class DeckBarActions {
  const DeckBarActions({
    this.onPlayPause,
    this.onShuffle,
    this.onRepeat,
    this.onNext,
    this.onPrevious,
    this.onSkipBack,
    this.onSkipForward,
    this.skipBackBy = const Duration(seconds: 15),
    this.skipForwardBy = const Duration(seconds: 30),
    this.onExpand,
    this.onLongPress,
    this.onQueue,
    this.onLyrics,
    this.onCast,
    this.onVolume,
    this.onMute,
    this.onMore,
    this.onStar,
    this.onSaveSong,
    this.onSeek,
  });

  final VoidCallback? onPlayPause;

  /// Shuffle and repeat cycle the queue's modes. Null hides the control,
  /// which is what radio gets: there is nothing to shuffle in a stream.
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeat;

  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  /// Spoken word swaps track skips for interval seeks.
  final VoidCallback? onSkipBack;
  final VoidCallback? onSkipForward;

  /// How far those two jump, as data rather than as prose: the control
  /// names its own interval, and a caller that changes one without the
  /// other would have the screen reader announce a distance the button
  /// does not travel.
  final Duration skipBackBy;
  final Duration skipForwardBy;

  final VoidCallback? onExpand;

  /// The item's context menu, reached by holding the bar. Everything in
  /// it is also reachable from the overflow control, so a gesture is
  /// never the only way to any of it.
  final VoidCallback? onLongPress;

  final VoidCallback? onQueue;
  final VoidCallback? onLyrics;
  final VoidCallback? onCast;

  /// Sets the output level. Wired together with [NowPlayingData.volume]:
  /// the level says what to draw and this says whether it can be moved,
  /// and the slider appears only when both are present. A level with no
  /// setter would be a readout, which is not a thing the bar has room to
  /// be.
  final ValueChanged<double>? onVolume;

  /// Silences the output and puts it back. Optional beside [onVolume]:
  /// where a caller has nowhere to remember the level it silenced, the
  /// glyph stays a label rather than becoming a control that cannot undo
  /// itself.
  final VoidCallback? onMute;

  final VoidCallback? onMore;
  final ValueChanged<bool>? onStar;

  /// Keeps the song a live stream just named, or drops the one already
  /// kept. Null hides the heart, which is the ordinary case: only radio
  /// has an announcement to keep. It is drawn in the left zone beside
  /// [onStar], so it exists only on the three-zone desktop bar - the
  /// compact one has no slot for it, and the host wires this at sidebar
  /// width for that reason.
  final ValueChanged<bool>? onSaveSong;

  final ValueChanged<Duration>? onSeek;
}

/// The persistent now-playing surface, docked at the bottom of every
/// layout.
///
/// This is the app's anchor and its namesake: playback never disappears,
/// and tapping the bar expands it into the full player. It adapts to the
/// medium (spoken word gets interval seeks and a speed chip, radio gets
/// a live pill and stop instead of pause) and to the size class (a
/// 64 px compact bar, an 88 px three-zone desktop bar).
class DeckBar extends StatelessWidget {
  const DeckBar({
    required this.now,
    this.actions = const DeckBarActions(),
    this.ids = const DeckBarIds(),
    this.sizeClass,
    this.positionTicker,
    this.autoplayBlocked = false,
    super.key,
  });

  final NowPlayingData now;
  final DeckBarActions actions;

  /// The live position, when the caller has one to feed.
  ///
  /// The bar is on screen for the whole session and the position moves
  /// several times a second, so the ticking part is a leaf of its own:
  /// only the progress hairline and the seek cluster listen here, inside
  /// a repaint boundary, and the rest of the bar rebuilds when the track
  /// or the transport changes and not otherwise. Without one the bar
  /// draws [NowPlayingData.position] and redraws when its caller does,
  /// which is what a catalogue or a golden wants.
  final ValueListenable<Duration>? positionTicker;

  /// The e2e handles for this bar's controls, supplied by the shell.
  final DeckBarIds ids;

  /// Defaults to the class of the current window.
  final WaxSizeClass? sizeClass;

  /// The browser refused a programmatic resume (a Connect handoff, a
  /// session restore). The bar says "Tap to resume" rather than failing
  /// silently.
  final bool autoplayBlocked;

  bool get _spokenWord =>
      now.domain == WaxDomain.podcasts || now.domain == WaxDomain.audiobooks;

  @override
  Widget build(BuildContext context) {
    final sizeClass = this.sizeClass ?? WaxSizeClass.of(context);
    // The three-zone bar is the desktop bar. Below a sidebar's worth of
    // width its zones cannot hold their contents: at 600 px the right
    // cluster alone wants more than its third. Medium windows get the
    // compact bar stretched, which is what the layout system's own
    // diagram shows there.
    final compact = !sizeClass.hasSidebar;
    final colors = WaxColors.of(context);
    final l10n = context.waxL10n;

    return Semantics(
      identifier: ids.bar,
      container: true,
      // Every control keeps a node of its own, and the loose text in the
      // bar keeps none: without this the title, the artist, and both
      // timecodes fold into this node's label, so the bar announced its
      // own elapsed time and re-announced it at every tick.
      explicitChildNodes: true,
      label: l10n.deckBarLabel,
      // What is playing and whether it is, but not where it stands: the
      // position moves several times a second, and a container value
      // that moved with it would both re-announce itself at every tick
      // and rebuild the bar this widget is careful not to rebuild. The
      // seek bar is the control that owns the position, and it announces
      // it as a spoken time.
      value: <String?>[
        autoplayBlocked
            ? l10n.deckBarPausedByBrowser
            : (now.playing ? l10n.commonPlaying : l10n.commonPaused),
        if (now.live) l10n.deckBarLive,
        now.title,
        now.subtitle,
        if (now.remoteEndpoint != null)
          l10n.deckBarOnEndpoint(now.remoteEndpoint!),
      ].nonNulls.join(', '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: SizedBox(
          height: compact
              ? WaxShellMetrics.deckBarCompactHeight
              : WaxShellMetrics.deckBarExpandedHeight,
          // Its own Material, inside the surface rather than around it:
          // the bar is mounted straight into the shell's frame, where
          // there is none, and the ink under the house controls has to
          // land on top of the bar's own background rather than behind
          // it.
          child: Material(
            type: MaterialType.transparency,
            child: compact
                ? _compact(context, colors)
                : _expanded(context, colors),
          ),
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, WaxColors colors) {
    return Column(
      children: <Widget>[
        // A 2 px amber hairline along the top edge is the whole progress
        // affordance at this size: a seek bar in a 64 px bar is a
        // mis-tap generator.
        if (!now.live)
          _Ticking(
            ticker: positionTicker,
            fallback: now.position,
            builder: (context, position) => LinearProgressIndicator(
              value: now.fractionAt(position),
              minHeight: 2,
              backgroundColor: colors.hairline,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            ),
          ),
        Expanded(
          child: GestureDetector(
            // Opaque, exactly as WaxPlayerScaffold's collapse detector
            // is and for the same reason: with deferToChild the padding,
            // the gutter between artwork and title, and the vertical
            // slack around a shrink-wrapped title block all fall
            // through, so the bar expands from some of its surface and
            // not the rest. Children are hit-tested first, so the
            // transport keeps its own taps.
            behavior: HitTestBehavior.opaque,
            // A pointer gesture and nothing else: the expand affordance
            // a screen reader uses is the button in the row, which says
            // what it does. Left in the tree this detector publishes a
            // tap on a bar-sized node, which is the merge the bar's
            // explicitChildNodes exists to prevent.
            excludeFromSemantics: true,
            onTap: actions.onExpand,
            onLongPress: actions.onLongPress,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -100) {
                actions.onExpand?.call();
              }
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -100) {
                (_spokenWord ? actions.onSkipForward : actions.onNext)?.call();
              } else if (velocity > 100) {
                (_spokenWord ? actions.onSkipBack : actions.onPrevious)?.call();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
              child: Row(
                children: <Widget>[
                  _artwork(context, 48),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: _titleBlock(context, colors, compact: true),
                    ),
                  ),
                  ..._transport(context, colors, compact: true),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _expanded(BuildContext context, WaxColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _zones(context, colors, constraints.maxWidth),
    );
  }

  /// The end slop this bar can afford its volume slider. Half the
  /// primitive's default: the slop rides inside the cluster's measured
  /// budget - the drawn track gives it up rather than the cluster
  /// growing back into the left zone - and twelve a side would halve
  /// the track.
  static const double _volumeSlop = 8;

  /// How wide the volume track is drawn, given the room the bar has.
  ///
  /// The right cluster is sized to its contents and the other two zones
  /// share what is left, so the newest thing in the cluster is the thing
  /// that has to give: at 840 px a full-width track took the left zone
  /// below what its artwork, star, and needle need, and five pixels came
  /// out the side. Measured from the bar's own width rather than the
  /// window's, because the bar sits in a shell slot beside a sidebar.
  static double _volumeTrack(double available) =>
      (available >= 1000 ? 80 : 52) - 2 * _volumeSlop;

  /// The layout slot the old centred column reserved for the drawn seek
  /// line. The transport centres in the band above it, and the seek
  /// surface's full touch target overlaps up from the bar's bottom edge,
  /// so the drawn track keeps the centre line this slot gave it.
  static const double _seekSlot = 24;

  Widget _zones(BuildContext context, WaxColors colors, double available) {
    final l10n = context.waxL10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
      child: Row(
        children: <Widget>[
          // Left zone: what is playing. Flexible, and every text in it
          // clips, so the zone yields before anything overflows.
          Expanded(
            child: GestureDetector(
              // Same opaque surface and the same semantics exclusion as
              // the compact bar's, so the desktop zone expands from its
              // whole rect rather than only where something is drawn.
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: actions.onExpand,
              onLongPress: actions.onLongPress,
              // The compact bar has had this since it shipped, and there
              // is no reason a mouse-and-trackpad window should not: a
              // trackpad swipe up over the bar is the same gesture.
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -100) {
                  actions.onExpand?.call();
                }
              },
              child: Row(
                children: <Widget>[
                  _artwork(context, 56),
                  const SizedBox(width: WaxSpace.s12),
                  Flexible(
                    child: ExcludeSemantics(
                      child: _titleBlock(context, colors, compact: false),
                    ),
                  ),
                  // Only where the caller wired it, which is the rule the
                  // right cluster already follows: a permanently greyed
                  // control reads as broken rather than as absent. Live
                  // radio is the case that proves it - a station has no
                  // per-user state to star, so the bar drew a disabled
                  // star over every stream.
                  if (actions.onStar != null) ...<Widget>[
                    const SizedBox(width: WaxSpace.s8),
                    StarButton(
                      starred: now.starred,
                      size: 16,
                      onChanged: actions.onStar,
                      semanticsId: ids.star,
                    ),
                  ],
                  // Radio's half of the same slot, beside the star and
                  // under the same rule: a stream has no item to star,
                  // and what it has instead is the song it just named.
                  // The label says song, never favourite - the face's
                  // star already means "pin this station".
                  if (actions.onSaveSong != null) ...<Widget>[
                    const SizedBox(width: WaxSpace.s8),
                    WaxIconButton(
                      glyph: WaxIcons.heart,
                      label: now.songSaved
                          ? l10n.deckBarForgetSong
                          : l10n.deckBarSaveSong,
                      size: 16,
                      active: now.songSaved,
                      semanticsId: ids.saveSong,
                      onPressed: () => actions.onSaveSong!(!now.songSaved),
                    ),
                  ],
                  if (now.playing) ...<Widget>[
                    const SizedBox(width: WaxSpace.s8),
                    // The same ticker the progress hairline reads, so the
                    // arm crosses the record at the rate the track plays
                    // rather than on a clock of its own. Live radio has no
                    // end to be a fraction of, so it passes none and the
                    // arm rests partway in.
                    _Ticking(
                      ticker: positionTicker,
                      fallback: now.position,
                      builder: (context, position) => PlayingIndicator(
                        playing: now.playing,
                        progress: now.live ? null : now.fractionAt(position),
                        size: 26,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Centre zone: transport over the seek bar. The seek bar's box
          // is the full touch target, which the fixed-height bar has no
          // room to stack under the transport - so the two are layered,
          // the seek surface beneath and bottom-anchored, its extra
          // height overlapping the padding under the buttons, and the
          // transport centred in the band above the seek's visual slot.
          // The buttons are hit-tested first and keep their taps.
          Expanded(
            flex: 2,
            child: now.live
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _transport(context, colors, compact: false),
                  )
                : Stack(
                    children: <Widget>[
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: WaxSpace.touchTarget,
                        child: _Ticking(
                          ticker: positionTicker,
                          fallback: now.position,
                          builder: (context, position) => Row(
                            children: <Widget>[
                              ExcludeSemantics(
                                child: Text(
                                  formatTimecode(position),
                                  style: WaxType.monoTime.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: WaxSpace.s8),
                              Expanded(
                                child: WaxSeekBar(
                                  position: position,
                                  duration: now.duration,
                                  buffered: now.buffered,
                                  onSeek: actions.onSeek,
                                  semanticsId: ids.seek,
                                ),
                              ),
                              const SizedBox(width: WaxSpace.s8),
                              ExcludeSemantics(
                                child: Text(
                                  formatTimecode(now.duration),
                                  style: WaxType.monoTime.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height:
                            WaxShellMetrics.deckBarExpandedHeight - _seekSlot,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _transport(
                              context,
                              colors,
                              compact: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          // Right zone: where playback goes and what it shows. Sized to
          // its contents rather than to a share of the width: four icon
          // buttons and a speed chip do not fit in a quarter of an
          // 840 px window, and a flex would have them overflow instead
          // of taking the space they need.
          // Each of these is drawn only where the caller wired it. A
          // surface the app has not built yet would otherwise sit here
          // as a permanently greyed button, which reads as broken rather
          // than as absent; the transport is the opposite case and keeps
          // its controls disabled, because a bar that loses its next
          // button on the last track is a bar that moves under the hand.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (now.speed != null) _speedChip(context, colors),
              if (actions.onQueue != null)
                WaxIconButton(
                  glyph: WaxIcons.queue,
                  label: l10n.deckBarQueue,
                  size: 18,
                  onPressed: actions.onQueue,
                  semanticsId: ids.queue,
                ),
              if (actions.onLyrics != null)
                WaxIconButton(
                  glyph: WaxIcons.lyrics,
                  label: l10n.deckBarLyrics,
                  size: 18,
                  onPressed: actions.onLyrics,
                  semanticsId: ids.lyrics,
                ),
              if (actions.onCast != null)
                WaxIconButton(
                  glyph: WaxIcons.cast,
                  label: l10n.deckBarCast,
                  size: 18,
                  active: now.remoteEndpoint != null,
                  onPressed: actions.onCast,
                  semanticsId: ids.cast,
                ),
              // Both halves or neither: a level with nothing to set it is
              // a readout, and a setter with no level has nothing to draw.
              if (now.volume != null && actions.onVolume != null)
                WaxSlider(
                  value: now.volume!,
                  onChanged: actions.onVolume,
                  label: l10n.deckBarVolume,
                  glyph: WaxIcons.volume,
                  mutedGlyph: WaxIcons.volumeMuted,
                  onMute: actions.onMute,
                  trackWidth: _volumeTrack(available),
                  endSlop: _volumeSlop,
                  semanticsId: ids.volume,
                  muteSemanticsId: ids.mute,
                ),
              if (actions.onMore != null)
                WaxIconButton(
                  glyph: WaxIcons.more,
                  label: l10n.commonMore,
                  size: 18,
                  onPressed: actions.onMore,
                  semanticsId: ids.more,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The cover, and the visible way into the full player.
  ///
  /// The bar has always been tappable and swipeable and neither said so,
  /// which is the whole of the bug: the gesture was discoverable only by
  /// trying it, and it is the one thing a listener does with this bar
  /// that had no control. It is also the only expand affordance a screen
  /// reader or a spec can reach, since both gesture surfaces are excluded
  /// from the semantics tree.
  ///
  /// On the cover rather than beside it, because a 44 px button in the
  /// left zone is width this bar has not got: at 1000 px the zone is
  /// already tight enough that adding one overflowed it by four pixels.
  /// The cover is 48 to 56 px of target that was doing nothing, and a
  /// caret in its corner says what pressing it does.
  Widget _artwork(BuildContext context, double size) => WaxTappable(
    label: context.waxL10n.deckBarExpand,
    semanticsId: ids.expand,
    onPressed: actions.onExpand,
    borderRadius: WaxRadius.thumb,
    // WaxTappable contributes the semantics, the focus, and the ring, and
    // says in its own doc that it adds no gesture: the child keeps its
    // own. Without this one the cover would only be pressable by falling
    // through to the zone detector behind it, so the control would be
    // real to a screen reader and to the keyboard and an accident to
    // everyone else.
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: actions.onExpand,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ArtworkImage(
            size: size,
            artwork: now.artwork,
            monogram: now.title,
            // Declared the same way the face and the dial declare it, so
            // one rule about radio's terminal state lives in one place.
            // The bar's thumbnail is below the wordmark's legibility
            // floor, so what this actually draws here is the initials -
            // which is the right answer at 48 logical pixels and is the
            // component's call to make rather than this call site's.
            placeholder: now.domain == WaxDomain.radio
                ? ArtworkPlaceholder.wordmark
                : ArtworkPlaceholder.initials,
            shape: now.shape,
            domain: now.domain,
          ),
          // Only where the caller wired it, the rule the right cluster
          // already follows: a caret over a cover that opens nothing
          // advertises an affordance the node beside it reports as
          // disabled. Opposite corner from the cast badge, so a routed
          // session shows both marks rather than one over the other.
          if (actions.onExpand != null)
            Positioned(
              left: -2,
              bottom: -2,
              child: WaxIcon(WaxIcons.expand, size: 14, active: true),
            ),
          if (now.remoteEndpoint != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: WaxIcon(WaxIcons.cast, size: 14, active: true),
            ),
        ],
      ),
    ),
  );

  Widget _titleBlock(
    BuildContext context,
    WaxColors colors, {
    required bool compact,
  }) {
    final l10n = context.waxL10n;
    // One line, fade-clipped. No marquee anywhere: it is motion and an
    // accessibility liability, and the full text is always reachable
    // through the player or a tooltip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          now.title,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: WaxType.titleItem.copyWith(color: colors.textPrimary),
        ),
        Row(
          // Sized to its content: at max this row stretched the whole
          // title block to the zone's width, which pushed the star and
          // the needle beside it to the middle of the bar instead of
          // beside the text.
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (now.live) ...<Widget>[
              _livePill(context, colors),
              const SizedBox(width: WaxSpace.s8),
            ],
            Flexible(
              child: Text(
                // Composed from whole sentences rather than joined from
                // fragments: where the sound comes out goes before what
                // is playing in plenty of languages.
                switch ((now.subtitle, now.remoteEndpoint)) {
                  (final subtitle?, final endpoint?) =>
                    l10n.deckBarSubtitleOnEndpoint(subtitle, endpoint),
                  (null, final endpoint?) => l10n.deckBarOnEndpoint(endpoint),
                  (final subtitle?, null) => subtitle,
                  _ => '',
                },
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: WaxType.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _livePill(BuildContext context, WaxColors colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s4, vertical: 1),
    decoration: BoxDecoration(
      color: colors.radio.container,
      borderRadius: WaxRadius.pill,
    ),
    child: Text(
      context.waxL10n.commonLiveChip,
      style: WaxType.overline.copyWith(color: colors.radio.onContainer),
    ),
  );

  Widget _speedChip(BuildContext context, WaxColors colors) => Container(
    margin: const EdgeInsetsDirectional.only(end: WaxSpace.s8),
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8, vertical: 2),
    decoration: BoxDecoration(
      color: colors.surface2,
      borderRadius: WaxRadius.pill,
    ),
    child: Text(
      // Two decimals unless the rate is whole, and the separator is
      // the locale's: 1,5x is how half again reads in most of Europe.
      context.waxL10n.deckBarSpeed(
        NumberFormat.decimalPatternDigits(
          locale: context.waxL10n.localeName,
          decimalDigits: now.speed! % 1 == 0 ? 0 : 2,
        ).format(now.speed),
      ),
      style: WaxType.monoData.copyWith(color: colors.textSecondary),
    ),
  );

  List<Widget> _transport(
    BuildContext context,
    WaxColors colors, {
    required bool compact,
  }) {
    final playGlyph = autoplayBlocked
        ? WaxIcons.play
        : (now.playing
              ? (now.live ? WaxIcons.stop : WaxIcons.pause)
              : WaxIcons.play);
    final l10n = context.waxL10n;
    final playLabel = autoplayBlocked
        ? l10n.deckBarTapToResume
        : (now.playing
              ? (now.live ? l10n.commonStop : l10n.commonPause)
              : l10n.commonPlay);

    return <Widget>[
      if (!compact)
        WaxIconButton(
          glyph: WaxIcons.shuffle,
          // A control that cycles says which state it is in, in its own
          // name as well as its tint: greyscale and a screen reader both
          // have to be able to tell.
          label: now.shuffled ? l10n.deckBarShuffleOn : l10n.deckBarShuffleOff,
          size: 18,
          active: now.shuffled,
          onPressed: now.live ? null : actions.onShuffle,
          semanticsId: ids.shuffle,
        ),
      if (_spokenWord)
        WaxIconButton(
          glyph: WaxIcons.rewind,
          label: l10n.deckBarSkipBack(l10n.spellDuration(actions.skipBackBy)),
          size: compact ? 20 : 22,
          onPressed: actions.onSkipBack,
          semanticsId: ids.skipBack,
        )
      else if (!compact)
        WaxIconButton(
          glyph: WaxIcons.previous,
          label: l10n.commonPrevious,
          size: 22,
          onPressed: now.live ? null : actions.onPrevious,
          semanticsId: ids.previous,
        ),
      _playButton(colors, playGlyph, playLabel, compact: compact),
      if (_spokenWord)
        WaxIconButton(
          glyph: WaxIcons.fastForward,
          label: l10n.deckBarSkipForward(
            l10n.spellDuration(actions.skipForwardBy),
          ),
          size: compact ? 20 : 22,
          onPressed: actions.onSkipForward,
          semanticsId: ids.skipForward,
        )
      else
        WaxIconButton(
          glyph: WaxIcons.next,
          label: l10n.commonNext,
          size: compact ? 20 : 22,
          onPressed: now.live ? null : actions.onNext,
          semanticsId: ids.next,
        ),
      if (!compact)
        WaxIconButton(
          glyph: now.repeat == WaxRepeat.one
              ? WaxIcons.repeatOne
              : WaxIcons.repeatAll,
          label: switch (now.repeat) {
            WaxRepeat.off => l10n.deckBarRepeatOff,
            WaxRepeat.all => l10n.deckBarRepeatAll,
            WaxRepeat.one => l10n.deckBarRepeatOne,
          },
          size: 18,
          active: now.repeat != WaxRepeat.off,
          onPressed: now.live ? null : actions.onRepeat,
          semanticsId: ids.repeat,
        ),
    ];
  }

  Widget _playButton(
    WaxColors colors,
    WaxGlyph glyph,
    String label, {
    required bool compact,
  }) {
    if (compact) {
      return WaxIconButton(
        glyph: glyph,
        label: label,
        size: 24,
        active: true,
        color: colors.textPrimary,
        onPressed: actions.onPlayPause,
        semanticsId: ids.play,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s4),
      child: Semantics(
        identifier: ids.play,
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: actions.onPlayPause,
        child: Material(
          color: colors.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: actions.onPlayPause,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: WaxIcon(
                  glyph,
                  size: 20,
                  active: true,
                  color: colors.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The deck bar's other face: a queue found at launch, offered back.
///
/// It stands in the same slot at the same height, because it is the same
/// promise - this is where what you are listening to lives - and because
/// the bar appearing under the content on launch and then jumping as
/// playback starts would move the page twice. The offer names what would
/// come back, so accepting it is a decision rather than a guess, and it
/// can be turned down: an offer that cannot be declined is a nag.
class DeckBarOffer extends StatelessWidget {
  const DeckBarOffer({
    required this.title,
    required this.onResume,
    required this.onDismiss,
    this.subtitle,
    this.artwork,
    this.domain = WaxDomain.music,
    this.shape = ArtworkShape.square,
    this.resumeLabel,
    this.semanticsId,
    this.resumeSemanticsId,
    this.dismissSemanticsId,
    super.key,
  });

  /// What would come back: the item the queue stands on, or a plain
  /// count when the catalogue cannot name it (offline, never synced).
  final String title;
  final String? subtitle;
  final WaxArtwork? artwork;
  final WaxDomain domain;
  final ArtworkShape shape;

  /// What the resume button says. Null takes the design system's own.
  final String? resumeLabel;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  final String? semanticsId;
  final String? resumeSemanticsId;
  final String? dismissSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.waxL10n;
    return Semantics(
      identifier: semanticsId,
      container: true,
      explicitChildNodes: true,
      label: <String?>[
        l10n.deckBarOfferTitle,
        title,
        subtitle,
      ].nonNulls.join(', '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: Border(top: BorderSide(color: colors.hairline)),
        ),
        child: SizedBox(
          height: WaxShellMetrics.deckBarCompactHeight,
          // See [DeckBar]: the offer stands in the same slot, with the
          // same lack of a Material around it.
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
              child: Row(
                children: <Widget>[
                  ArtworkImage(
                    size: 48,
                    artwork: artwork,
                    monogram: title,
                    placeholder: domain == WaxDomain.radio
                        ? ArtworkPlaceholder.wordmark
                        : ArtworkPlaceholder.initials,
                    shape: shape,
                    domain: domain,
                  ),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: WaxType.titleItem.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            subtitle ?? l10n.deckBarOfferTitle,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: WaxType.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s8),
                  WaxButton(
                    label: resumeLabel ?? l10n.deckBarResume,
                    kind: WaxButtonKind.tonal,
                    icon: WaxIcons.play,
                    onPressed: onResume,
                    semanticsId: resumeSemanticsId,
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.close,
                    label: l10n.deckBarNotNow,
                    size: 18,
                    onPressed: onDismiss,
                    semanticsId: dismissSemanticsId,
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

/// The one part of the deck bar that moves while a track plays.
///
/// The bar outlives every screen, so its rebuilds are the app's most
/// repeated frame work. Fed a ticker, the position lives in this leaf
/// behind a repaint boundary and nothing above it rebuilds; fed none, it
/// draws the caller's snapshot and rebuilds only when the caller does.
class _Ticking extends StatelessWidget {
  const _Ticking({
    required this.ticker,
    required this.fallback,
    required this.builder,
  });

  final ValueListenable<Duration>? ticker;
  final Duration fallback;
  final Widget Function(BuildContext context, Duration position) builder;

  @override
  Widget build(BuildContext context) {
    final ticker = this.ticker;
    if (ticker == null) return builder(context, fallback);
    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: ticker,
        builder: (context, position, _) => builder(context, position),
      ),
    );
  }
}
