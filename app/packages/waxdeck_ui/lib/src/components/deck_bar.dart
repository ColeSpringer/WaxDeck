import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
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
    this.onMore,
    this.onStar,
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
  final VoidCallback? onMore;
  final ValueChanged<bool>? onStar;
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

    return Semantics(
      identifier: ids.bar,
      container: true,
      // Every control keeps a node of its own, and the loose text in the
      // bar keeps none: without this the title, the artist, and both
      // timecodes fold into this node's label, so the bar announced its
      // own elapsed time and re-announced it at every tick.
      explicitChildNodes: true,
      label: 'Now playing bar',
      // What is playing and whether it is, but not where it stands: the
      // position moves several times a second, and a container value
      // that moved with it would both re-announce itself at every tick
      // and rebuild the bar this widget is careful not to rebuild. The
      // seek bar is the control that owns the position, and it announces
      // it as a spoken time.
      value: <String?>[
        autoplayBlocked
            ? 'Paused by the browser'
            : (now.playing ? 'Playing' : 'Paused'),
        if (now.live) 'Live',
        now.title,
        now.subtitle,
        if (now.remoteEndpoint != null) 'on ${now.remoteEndpoint}',
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
                  _artwork(48),
                  const SizedBox(width: WaxSpace.s12),
                  Expanded(
                    child: ExcludeSemantics(
                      child: _titleBlock(colors, compact: true),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
      child: Row(
        children: <Widget>[
          // Left zone: what is playing. Flexible, and every text in it
          // clips, so the zone yields before anything overflows.
          Expanded(
            child: GestureDetector(
              onTap: actions.onExpand,
              onLongPress: actions.onLongPress,
              child: Row(
                children: <Widget>[
                  _artwork(56),
                  const SizedBox(width: WaxSpace.s12),
                  Flexible(
                    child: ExcludeSemantics(
                      child: _titleBlock(colors, compact: false),
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s8),
                  StarButton(
                    starred: now.starred,
                    size: 16,
                    onChanged: actions.onStar,
                    semanticsId: ids.star,
                  ),
                  if (now.playing) ...<Widget>[
                    const SizedBox(width: WaxSpace.s8),
                    PlayingIndicator(playing: now.playing, size: 26),
                  ],
                ],
              ),
            ),
          ),
          // Centre zone: transport over the seek bar.
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _transport(context, colors, compact: false),
                ),
                if (!now.live)
                  _Ticking(
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
              if (now.speed != null) _speedChip(colors),
              if (actions.onQueue != null)
                WaxIconButton(
                  glyph: WaxIcons.queue,
                  label: 'Queue',
                  size: 18,
                  onPressed: actions.onQueue,
                  semanticsId: ids.queue,
                ),
              if (actions.onLyrics != null)
                WaxIconButton(
                  glyph: WaxIcons.lyrics,
                  label: 'Lyrics',
                  size: 18,
                  onPressed: actions.onLyrics,
                  semanticsId: ids.lyrics,
                ),
              if (actions.onCast != null)
                WaxIconButton(
                  glyph: WaxIcons.cast,
                  label: 'Play on another device',
                  size: 18,
                  active: now.remoteEndpoint != null,
                  onPressed: actions.onCast,
                  semanticsId: ids.cast,
                ),
              if (actions.onMore != null)
                WaxIconButton(
                  glyph: WaxIcons.more,
                  label: 'More',
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

  Widget _artwork(double size) => Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      ArtworkImage(
        size: size,
        image: now.artwork,
        monogram: now.title,
        shape: now.shape,
        domain: now.domain,
      ),
      if (now.remoteEndpoint != null)
        Positioned(
          right: -2,
          bottom: -2,
          child: WaxIcon(WaxIcons.cast, size: 14, active: true),
        ),
    ],
  );

  Widget _titleBlock(WaxColors colors, {required bool compact}) {
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
          children: <Widget>[
            if (now.live) ...<Widget>[
              _livePill(colors),
              const SizedBox(width: WaxSpace.s8),
            ],
            Flexible(
              child: Text(
                <String?>[
                  now.subtitle,
                  if (now.remoteEndpoint != null) 'on ${now.remoteEndpoint}',
                ].nonNulls.join(' '),
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

  Widget _livePill(WaxColors colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s4, vertical: 1),
    decoration: BoxDecoration(
      color: colors.radio.container,
      borderRadius: WaxRadius.pill,
    ),
    child: Text(
      'LIVE',
      style: WaxType.overline.copyWith(color: colors.radio.onContainer),
    ),
  );

  Widget _speedChip(WaxColors colors) => Container(
    margin: const EdgeInsets.only(right: WaxSpace.s8),
    padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8, vertical: 2),
    decoration: BoxDecoration(
      color: colors.surface2,
      borderRadius: WaxRadius.pill,
    ),
    child: Text(
      '${now.speed!.toStringAsFixed(now.speed! % 1 == 0 ? 0 : 2)}x',
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
    final playLabel = autoplayBlocked
        ? 'Tap to resume'
        : (now.playing ? (now.live ? 'Stop' : 'Pause') : 'Play');

    return <Widget>[
      if (!compact)
        WaxIconButton(
          glyph: WaxIcons.shuffle,
          // A control that cycles says which state it is in, in its own
          // name as well as its tint: greyscale and a screen reader both
          // have to be able to tell.
          label: now.shuffled ? 'Shuffle on' : 'Shuffle off',
          size: 18,
          active: now.shuffled,
          onPressed: now.live ? null : actions.onShuffle,
          semanticsId: ids.shuffle,
        ),
      if (_spokenWord)
        WaxIconButton(
          glyph: WaxIcons.rewind,
          label: 'Back ${spellDuration(actions.skipBackBy)}',
          size: compact ? 20 : 22,
          onPressed: actions.onSkipBack,
          semanticsId: ids.skipBack,
        )
      else if (!compact)
        WaxIconButton(
          glyph: WaxIcons.previous,
          label: 'Previous',
          size: 22,
          onPressed: now.live ? null : actions.onPrevious,
          semanticsId: ids.previous,
        ),
      _playButton(colors, playGlyph, playLabel, compact: compact),
      if (_spokenWord)
        WaxIconButton(
          glyph: WaxIcons.fastForward,
          label: 'Forward ${spellDuration(actions.skipForwardBy)}',
          size: compact ? 20 : 22,
          onPressed: actions.onSkipForward,
          semanticsId: ids.skipForward,
        )
      else
        WaxIconButton(
          glyph: WaxIcons.next,
          label: 'Next',
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
            WaxRepeat.off => 'Repeat off',
            WaxRepeat.all => 'Repeat all',
            WaxRepeat.one => 'Repeat one',
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
/// promise — this is where what you are listening to lives — and because
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
    this.resumeLabel = 'Resume',
    this.semanticsId,
    this.resumeSemanticsId,
    this.dismissSemanticsId,
    super.key,
  });

  /// What would come back: the item the queue stands on, or a plain
  /// count when the catalogue cannot name it (offline, never synced).
  final String title;
  final String? subtitle;
  final ImageProvider? artwork;
  final WaxDomain domain;
  final ArtworkShape shape;

  final String resumeLabel;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  final String? semanticsId;
  final String? resumeSemanticsId;
  final String? dismissSemanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Semantics(
      identifier: semanticsId,
      container: true,
      explicitChildNodes: true,
      label: <String?>[
        'Pick up where you left off',
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
                    image: artwork,
                    monogram: title,
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
                            subtitle ?? 'Pick up where you left off',
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
                    label: resumeLabel,
                    kind: WaxButtonKind.tonal,
                    icon: WaxIcons.play,
                    onPressed: onResume,
                    semanticsId: resumeSemanticsId,
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.close,
                    label: 'Not now',
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
