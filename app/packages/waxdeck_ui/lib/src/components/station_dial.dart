import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/wax_icon.dart';
import '../l10n/wax_l10n.dart';
import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'artwork.dart';
import 'controls.dart';
import 'snap_physics.dart';
import 'view_data.dart';

/// One station on the dial.
@immutable
class DialStation {
  const DialStation({
    required this.name,
    this.artwork,
    this.nowPlaying,
    this.playing = false,
  });

  final String name;
  final WaxArtwork? artwork;

  /// The station's current in-stream title, drawn under the dial while
  /// this is the station playing.
  final String? nowPlaying;

  final bool playing;
}

/// The dial: pinned stations as circular logos on a tick-marked band,
/// under a fixed needle.
///
/// Mounted full bleed, deliberately: the band sweeping the window's full
/// width is the dial's identity, and the readout under it applies the
/// scaffold gutter itself - a padded parent would clip the band and
/// double-indent the text.
///
/// A visual shortcut and never the only path - every station on it is
/// also a row in the grid below, which is what makes the two decisions
/// here safe. The logo band is excluded from the semantics tree, because
/// a screen reader walking twelve circular logos to reach the grid is
/// worse than not having them; and under reduced motion the band draws as
/// a static row rather than a carousel that flicks and settles. What is
/// *not* excluded is the centred station's name and its one tune control:
/// that is a single control rather than twelve, and a large obvious button
/// naming what it will do is as useful to a screen reader as to anyone.
class StationDial extends StatefulWidget {
  const StationDial({
    required this.stations,
    required this.onTune,
    this.onStop,
    this.initialIndex = 0,
    this.semanticsId,
    this.tuneSemanticsId,
    this.nowPlayingSemanticsId,
    super.key,
  });

  /// Pinned stations, in the order they are dialled through. The caller
  /// caps the list; the layout system says about twelve, past which the
  /// band stops being a dial and starts being a list.
  final List<DialStation> stations;

  /// Tunes the centred station in.
  final ValueChanged<int> onTune;

  /// Stops the station that is playing. Null hides the stop affordance,
  /// which is what a dial with nothing playing on it gets.
  final VoidCallback? onStop;

  /// Which station the dial opens on: the one playing, or the first.
  final int initialIndex;

  final String? semanticsId;
  final String? tuneSemanticsId;
  final String? nowPlayingSemanticsId;

  @override
  State<StationDial> createState() => _StationDialState();
}

class _StationDialState extends State<StationDial> {
  static const double _slot = 84;
  static const double _logo = 60;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.initialIndex * _slot,
  );
  late int _centred = widget.initialIndex.clamp(
    0,
    math.max(0, widget.stations.length - 1),
  );

  @override
  void didUpdateWidget(StationDial old) {
    super.didUpdateWidget(old);
    // The list shrinks when a favourite is unpinned, and the centred index
    // has to come back inside it before the next build reads a station at
    // it.
    if (_centred < widget.stations.length) return;
    _centred = math.max(0, widget.stations.length - 1);
    // And the band has to follow, or the needle sits over a station the
    // caption below it no longer names until somebody scrolls. Posted,
    // because the new extent is not known until this build has laid out.
    final target = _centred * _slot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Which slot is under the needle, from the scroll offset.
  ///
  /// The viewport does not appear here, and that is arithmetic rather than
  /// an omission: the leading inset is half a viewport minus half a slot,
  /// so the distance from the list's start to the needle is always half a
  /// slot. Every station therefore sits under the needle at its own index
  /// times the slot width, whatever the window is doing.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    _centreOn((_scroll.offset / _slot).round(), haptic: true);
  }

  /// Moves the needle to [index], clamped, with the snap haptic the layout
  /// asks for on the platforms that have one - a dial that clicks as it
  /// passes a station is the whole reason this is a dial and not a row.
  void _centreOn(int index, {bool haptic = false}) {
    final settled = index.clamp(0, widget.stations.length - 1);
    if (settled == _centred) return;
    setState(() => _centred = settled);
    if (!haptic) return;
    if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android) {
      HapticFeedback.selectionClick();
    }
  }

  /// The inset that lets the first and last station reach the needle.
  double _padding(double viewportWidth) =>
      math.max(0, (viewportWidth - _slot) / 2);

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    if (widget.stations.isEmpty) return const SizedBox.shrink();
    final motion = WaxMotion.of(context);
    final still = !motion.animationsEnabled;
    final centred = widget.stations[_centred];

    final at = _centred + 1;
    final of = widget.stations.length;
    final l10n = context.waxL10n;

    return Semantics(
      identifier: widget.semanticsId,
      container: true,
      explicitChildNodes: true,
      // The dial itself is adjustable, which is the correction this widget
      // needed. Excluding the logo band keeps twelve circular logos out of
      // the traversal order - that part was right - but it also left the
      // one tune control stuck on whatever station the dial opened on:
      // moving the needle was a flick or a mouse tap on a logo, and neither
      // is available to a keyboard or a screen reader. Two nodes rather
      // than thirteen, and the needle moves.
      label: l10n.stationDialLabel,
      value: l10n.stationDialStation(centred.name, at, of),
      increasedValue: _centred + 1 < of
          ? l10n.stationDialStation(
              widget.stations[_centred + 1].name,
              at + 1,
              of,
            )
          : null,
      decreasedValue: _centred > 0
          ? l10n.stationDialStation(
              widget.stations[_centred - 1].name,
              at - 1,
              of,
            )
          : null,
      onIncrease: _centred + 1 < of ? () => _centre(_centred + 1) : null,
      onDecrease: _centred > 0 ? () => _centre(_centred - 1) : null,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: _slot + WaxSpace.s20,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inset = _padding(constraints.maxWidth);
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // The band the logos ride on, with its ticks.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BandPainter(
                          tick: colors.hairline,
                          strong: colors.textTertiary,
                        ),
                      ),
                    ),
                    // Decoration, and said so: the grid below has a row
                    // per station, and twelve logos in the traversal order
                    // buys nothing and costs the way out of them.
                    ExcludeSemantics(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          _onScroll();
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          // Still under reduced motion: no ballistic
                          // settle, no flick that carries.
                          physics: still
                              ? const ClampingScrollPhysics()
                              : const SnapScrollPhysics(itemExtent: _slot),
                          itemCount: widget.stations.length,
                          itemBuilder: (context, index) => _Slot(
                            station: widget.stations[index],
                            slot: _slot,
                            logo: _logo,
                            centred: index == _centred,
                            onTap: () => _centre(index),
                          ),
                        ),
                      ),
                    ),
                    // The needle: fixed, amber, over everything.
                    IgnorePointer(
                      child: Container(
                        width: 2,
                        height: _slot + WaxSpace.s12,
                        color: colors.accent,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: WaxSpace.s8),
          // The readout cluster sits on the scaffold gutter while the
          // tick band above stays full bleed: the band sweeping the full
          // width like real hardware is the dial's identity, and the
          // text under it is content like any other row. The gutter is
          // applied here because the dial is mounted full bleed for the
          // band's sake - a caller that padded it would double-indent
          // this and clip the band, so it does not get padded.
          Padding(
            padding: WaxSizeClass.of(context).gutter,
            child: Column(
              children: <Widget>[
                Text(
                  centred.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: WaxType.titleItem.copyWith(color: colors.textPrimary),
                ),
                // The ICY line, only while the centred station is the one
                // playing: a title belongs to a stream, and drawing the
                // playing station's song under a station nobody is
                // listening to would attach it to the wrong name. The
                // slot's height is reserved either way - an empty line of
                // the same style - so starting playback does not shift
                // the name, the button, and everything below them.
                if (centred.playing && centred.nowPlaying != null)
                  Semantics(
                    identifier: widget.nowPlayingSemanticsId,
                    liveRegion: true,
                    child: Text(
                      centred.nowPlaying!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: WaxType.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  ExcludeSemantics(child: Text('', style: WaxType.caption)),
                const SizedBox(height: WaxSpace.s8),
                // One control, naming what it will do. Stop rather than
                // pause, because a paused live stream resumes at the live
                // edge anyway.
                WaxButton(
                  label: centred.playing
                      ? l10n.commonStop
                      : l10n.stationDialTuneIn,
                  kind: centred.playing
                      ? WaxButtonKind.tonal
                      : WaxButtonKind.filled,
                  icon: centred.playing ? WaxIcons.stop : WaxIcons.play,
                  semanticsId: widget.tuneSemanticsId,
                  onPressed: centred.playing
                      ? widget.onStop
                      : () => widget.onTune(_centred),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Brings a tapped slot under the needle. A tap is the button
  /// equivalent of the flick, which is the rule every gesture here obeys.
  void _centre(int index) {
    _centreOn(index);
    if (!_scroll.hasClients) return;
    final target = index * _slot;
    final motion = WaxMotion.of(context);
    final settled = target.clamp(0.0, _scroll.position.maxScrollExtent);
    if (!motion.animationsEnabled) {
      _scroll.jumpTo(settled);
      return;
    }
    unawaited(
      _scroll.animateTo(
        settled,
        duration: motion.standard,
        curve: WaxMotion.emphasized,
      ),
    );
  }
}

/// One station's place on the band.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.station,
    required this.slot,
    required this.logo,
    required this.centred,
    required this.onTap,
  });

  final DialStation station;
  final double slot;
  final double logo;
  final bool centred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: slot,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            // The stack is the logo's size, and the pill is centred on
            // it: at a large text scale the pill outgrows the logo, and
            // a hard clip would truncate the word at both ends where an
            // overhang into the slot's own margin harms nothing.
            clipBehavior: Clip.none,
            children: <Widget>[
              // Dimmed off-centre, so which one the needle has is legible
              // without relying on the needle alone.
              Opacity(
                opacity: centred ? 1 : 0.45,
                child: ArtworkImage(
                  size: logo,
                  artwork: station.artwork,
                  monogram: station.name,
                  // A dial tile carries the station name under it, but
                  // the tile is what a listener aims at, and most
                  // stations arrive with no logo at all: two initials
                  // over a flat swatch is what the whole dial looks like
                  // otherwise.
                  placeholder: ArtworkPlaceholder.wordmark,
                  shape: ArtworkShape.circle,
                  domain: WaxDomain.radio,
                ),
              ),
              if (station.playing)
                // Inside the logo's own box rather than hanging below
                // it: an overhang painted outside the slot collided
                // with the band the moment playback started.
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WaxSpace.s4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.radio.container,
                      borderRadius: WaxRadius.pill,
                    ),
                    child: Text(
                      context.waxL10n.commonLiveChip,
                      style: WaxType.overline.copyWith(
                        color: colors.radio.onContainer,
                      ),
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

/// The tick-marked band the logos sit on.
class _BandPainter extends CustomPainter {
  _BandPainter({required this.tick, required this.strong});

  final Color tick;
  final Color strong;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 12.0;
    final mid = size.height / 2;
    for (var x = 0.0; x < size.width; x += spacing) {
      // Every fifth tick is taller, the way a tuning scale is marked.
      final tall = (x / spacing) % 5 == 0;
      canvas.drawLine(
        Offset(x, mid - (tall ? 14 : 8)),
        Offset(x, mid + (tall ? 14 : 8)),
        Paint()
          ..color = tall ? strong : tick
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.tick != tick || old.strong != strong;
}

/// Settles the dial on whole stations.
///
/// Its own rather than [PageScrollPhysics], for the reason the shelf's
/// snap is its own: paging by the viewport lands wherever the page falls,
/// and a dial that rests between two stations has nothing under the
/// needle.
