import 'package:flutter/material.dart';

import '../icons/wax_icon.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
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
class PlayerScaffold extends StatelessWidget {
  const PlayerScaffold({
    required this.now,
    required this.transport,
    required this.seek,
    this.onCollapse,
    this.actionRow,
    this.titleTrailing,
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

  /// Up-next peek, chapters, notes, transcript.
  final Widget? bottomRegion;

  final List<Widget>? trailingHeaderActions;

  /// The e2e handles for the scaffold's own controls.
  final PlayerIds ids;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && sizeClass.isCompact;

    return WaxBackdrop(
      domain: now.domain,
      child: Semantics(
        identifier: ids.surface,
        container: true,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _header(context, colors),
              Expanded(
                child: landscape
                    ? _landscape(context, colors)
                    : _portrait(context, colors, sizeClass),
              ),
              ?bottomRegion,
            ],
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
          onPressed: onCollapse,
          semanticsId: ids.collapse,
        ),
        Expanded(
          child: Center(
            child: now.provenance == null
                ? const SizedBox.shrink()
                : Text(
                    now.provenance!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
          ),
        ),
        ...?trailingHeaderActions,
      ],
    ),
  );

  Widget _portrait(
    BuildContext context,
    WaxColors colors,
    WaxSizeClass sizeClass,
  ) {
    final size = MediaQuery.sizeOf(context);
    // The hero has to fit the height it is given, not just the width: a
    // short, wide window (a resized desktop player) would otherwise ask
    // for 420 px of art inside 570 px of column that also holds the
    // title block, the seek cluster, and the transport.
    final artSize = (size.width - WaxSpace.s48 * 2)
        .clamp(120.0, 420.0)
        .clamp(120.0, (size.height * 0.42).clamp(120.0, 420.0));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Hero(
                tag: 'deck-artwork',
                child: ArtworkImage(
                  size: now.domain == WaxDomain.podcasts ? 200 : artSize,
                  artwork: now.artwork,
                  monogram: now.title,
                  shape: now.shape,
                  domain: now.domain,
                ),
              ),
              const SizedBox(height: WaxSpace.s32),
              _titleBlock(colors),
              const SizedBox(height: WaxSpace.s20),
              seek,
              const SizedBox(height: WaxSpace.s16),
              transport,
              if (actionRow != null) ...<Widget>[
                const SizedBox(height: WaxSpace.s16),
                actionRow!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Landscape is a side-by-side arrangement of the same slots, owned
  /// here so the four faces inherit it rather than each inventing a
  /// letterboxed portrait layout.
  Widget _landscape(BuildContext context, WaxColors colors) {
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Hero(
            tag: 'deck-artwork',
            child: ArtworkImage(
              size: (height - WaxSpace.s64).clamp(100.0, 260.0),
              artwork: now.artwork,
              monogram: now.title,
              shape: now.shape,
              domain: now.domain,
            ),
          ),
          const SizedBox(width: WaxSpace.s24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _titleBlock(colors, alignStart: true),
                const SizedBox(height: WaxSpace.s16),
                seek,
                const SizedBox(height: WaxSpace.s12),
                transport,
                if (actionRow != null) ...<Widget>[
                  const SizedBox(height: WaxSpace.s12),
                  actionRow!,
                ],
              ],
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
              now.title,
              textAlign: alignStart ? TextAlign.start : TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
            ),
          ),
          if (titleTrailing != null) ...<Widget>[
            const SizedBox(width: WaxSpace.s8),
            titleTrailing!,
          ],
        ],
      ),
      if (now.subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: WaxSpace.s4),
          child: Text(
            now.subtitle!,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
        ),
    ],
  );
}
