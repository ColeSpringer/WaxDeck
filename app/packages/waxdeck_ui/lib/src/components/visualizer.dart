import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/motion.dart';
import 'artwork.dart';
import 'controls.dart';
import 'view_data.dart';

/// Which picture the visualizer is drawing.
enum WaxVisualizerMode {
  /// The whole track's peak landscape, with the playhead sweeping it.
  waveform('Waveform'),

  /// The cover as a turning disc inside a ring of the same peaks.
  platter('Platter');

  const WaxVisualizerMode(this.label);

  final String label;
}

/// The visualizer's picture: the track's own shape, drawn large.
///
/// Nothing here is invented. What moves is the playhead over peaks the
/// analyze pass measured, which is the whole reason this exists in the
/// shape it does: a fake spectrum would be theatre, and the audience
/// this is for can tell. With no peaks to draw there is no picture, and
/// the caller is expected to say so rather than hand this an empty list
/// and hope.
///
/// The position arrives as a listenable and the painters repaint from
/// it directly, so a playhead crossing a screen never rebuilds a widget.
class VisualizerStage extends StatefulWidget {
  const VisualizerStage({
    required this.position,
    required this.duration,
    required this.peaks,
    required this.mode,
    this.playing = false,
    this.artwork,
    this.monogram,
    this.shape = ArtworkShape.square,
    this.domain = WaxDomain.music,
    this.onSeek,
    this.semanticsId,
    super.key,
  });

  final ValueListenable<Duration> position;
  final Duration duration;

  /// Normalised 0 to 1 peak amplitudes, in playback order.
  final List<double> peaks;

  final WaxVisualizerMode mode;

  /// Only the platter turns, and only while there is sound.
  final bool playing;

  final WaxArtwork? artwork;
  final String? monogram;
  final ArtworkShape shape;
  final WaxDomain domain;

  /// Scrubbing anywhere on the picture. Null makes it a picture only.
  final ValueChanged<Duration>? onSeek;

  final String? semanticsId;

  @override
  State<VisualizerStage> createState() => _VisualizerStageState();
}

class _VisualizerStageState extends State<VisualizerStage>
    with SingleTickerProviderStateMixin {
  /// One turn of the platter. Slow enough to read as a record rather
  /// than as a loading spinner: 33 and a third revolutions per minute is
  /// the joke and is far too fast to watch, so this is one turn every
  /// twelve seconds.
  static const Duration _turn = Duration(seconds: 12);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _turn,
  );

  /// What the painters draw: the live position, or the finger's while a
  /// scrub is under way.
  ///
  /// Its own notifier rather than [VisualizerStage.position] passed
  /// straight through, and the reason is the same one the seek bar
  /// records: a drag previews and commits on release. Seeking on every
  /// drag frame is a seek per pointer event at the engine, which on a
  /// phone is a stutter and on a stream is a burst of range requests -
  /// and a drag that loses the arena to something else would have moved
  /// playback on its way past.
  late final ValueNotifier<Duration> _shown = ValueNotifier(
    widget.position.value,
  );

  /// Where the finger is, or null when nobody is scrubbing.
  double? _scrubbing;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applySpin();
  }

  @override
  void didUpdateWidget(covariant VisualizerStage old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing || old.mode != widget.mode) _applySpin();
    if (!identical(old.position, widget.position)) {
      old.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
      _onPosition();
    }
  }

  /// The live position reaches the painters only while nothing is being
  /// dragged: a preview that the engine's own ticks overwrote would jump
  /// back under the finger.
  void _onPosition() {
    if (_scrubbing != null) return;
    _shown.value = widget.position.value;
  }

  /// Moves the preview without touching the engine.
  void _preview(double fraction, double width) {
    if (width <= 0) return;
    _scrubbing = (fraction / width).clamp(0.0, 1.0);
    _shown.value = _at(_scrubbing!);
  }

  /// Commits wherever the finger left off, and hands the painters back
  /// to the engine.
  void _commit() {
    final at = _scrubbing;
    _scrubbing = null;
    if (at == null) return;
    widget.onSeek?.call(_at(at));
  }

  /// Drops the preview without moving anything.
  ///
  /// For a press that lost the arena, which is the seek bar's own rule
  /// and is not a corner case here: a press held long enough to be a tap
  /// and then dragged cancels the tap, and committing that would seek to
  /// wherever the finger first landed before the drag had said anything.
  void _abandon() {
    if (_scrubbing == null) return;
    _scrubbing = null;
    _shown.value = widget.position.value;
  }

  /// The disc turns while sound is coming out of it, and holds still
  /// otherwise - including under reduced motion, where a continuous
  /// rotation is exactly what the setting is asking to stop.
  void _applySpin() {
    final spinning =
        widget.mode == WaxVisualizerMode.platter &&
        widget.playing &&
        WaxMotion.of(context).animationsEnabled;
    if (spinning) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _shown.dispose();
    _spin.dispose();
    super.dispose();
  }

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.duration.inMilliseconds * fraction.clamp(0, 1))
        .round(),
  );

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final picture = widget.mode == WaxVisualizerMode.waveform
        ? _waveform(colors)
        : _platter(colors);

    final seek = widget.onSeek;
    return Semantics(
      identifier: widget.semanticsId,
      container: true,
      // The picture is decoration; the surface around it carries the
      // controls, and the seek bar under them is the addressable one.
      // A screen reader gets a named region rather than a wall of paint.
      label: 'Visualizer',
      child: seek == null
          ? picture
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  // The whole picture is the scrub surface (5.6): a
                  // visualizer you cannot seek from is a screensaver.
                  behavior: HitTestBehavior.opaque,
                  // A tap previews on press and commits on release, so a
                  // press that turns into a drag - or that loses the
                  // arena to one - never moves playback on its way past.
                  onTapDown: (d) => _preview(d.localPosition.dx, width),
                  onTapUp: (_) => _commit(),
                  onTapCancel: _abandon,
                  onHorizontalDragStart: (d) =>
                      _preview(d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) =>
                      _preview(d.localPosition.dx, width),
                  onHorizontalDragEnd: (_) => _commit(),
                  onHorizontalDragCancel: _abandon,
                  child: picture,
                );
              },
            ),
    );
  }

  // Accent rather than the artwork palette, which is the colour system's
  // own rule: what the played part of a track is drawn in carries
  // meaning, and extracted colour is atmosphere. The backdrop behind
  // this is where the artwork's own colour goes.
  Widget _waveform(WaxColors colors) => CustomPaint(
    painter: _WaveformLandscapePainter(
      position: _shown,
      duration: widget.duration,
      peaks: widget.peaks,
      played: colors.accent,
      unplayed: colors.textTertiary,
      playhead: colors.textPrimary,
    ),
    size: Size.infinite,
  );

  Widget _platter(WaxColors colors) => Center(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // The disc takes the smaller axis less the ring around it.
        final extent = math.min(constraints.maxWidth, constraints.maxHeight);
        if (!extent.isFinite || extent < 120) return const SizedBox.shrink();
        final disc = extent * 0.62;
        return SizedBox.square(
          dimension: extent,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                painter: _PeakRingPainter(
                  position: _shown,
                  duration: widget.duration,
                  peaks: widget.peaks,
                  played: colors.accent,
                  unplayed: colors.textTertiary,
                  innerRadius: disc / 2 + 12,
                ),
                size: Size.square(extent),
              ),
              RotationTransition(
                turns: _spin,
                child: ArtworkImage(
                  size: disc,
                  artwork: widget.artwork,
                  monogram: widget.monogram,
                  // A record is round whatever the cover is: the platter
                  // is the point of the mode, and a square in a ring of
                  // peaks is a thumbnail with decoration.
                  shape: ArtworkShape.circle,
                  domain: widget.domain,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The track as a landscape: peaks mirrored around the centre line, the
/// part already played in accent and the rest in a quiet tone, with the
/// playhead standing where the sound is.
class _WaveformLandscapePainter extends CustomPainter {
  _WaveformLandscapePainter({
    required this.position,
    required this.duration,
    required this.peaks,
    required this.played,
    required this.unplayed,
    required this.playhead,
  }) : super(repaint: position);

  final ValueListenable<Duration> position;
  final Duration duration;
  final List<double> peaks;
  final Color played;
  final Color unplayed;
  final Color playhead;

  /// One bar every this many logical pixels, matching the seek bar's own
  /// reading: a 3 px bar and a 2 px gap at this scale.
  static const double _pitch = 5;

  /// The peaks reduced to the bar count this width draws, held between
  /// paints: the playhead moves several times a second and the shape
  /// does not.
  ///
  /// Keyed by the peaks as well as by the count. A painter is built
  /// fresh whenever the stage rebuilds, so today nothing can reach this
  /// holding another track's shape - which makes the peaks key
  /// insurance rather than a fix, and the kind worth having: a cache
  /// whose correctness rests on where it happens to be constructed is
  /// one edit away from drawing the wrong track.
  List<double>? _bars;
  List<double>? _barsFrom;
  int _barCount = 0;

  List<double> _reduced(double width) {
    final count = math.max(1, (width / _pitch).floor());
    if (_bars == null || _barCount != count || !identical(_barsFrom, peaks)) {
      _barCount = count;
      _barsFrom = peaks;
      _bars = downsamplePeaks(peaks, count);
    }
    return _bars!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0 || size.height <= 0) return;
    final bars = _reduced(size.width);
    final mid = size.height / 2;
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.value.inMilliseconds / total).clamp(0.0, 1.0);
    final headX = size.width * fraction;

    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      final x = i * _pitch + _pitch / 2;
      if (x > size.width) break;
      // A floor under the shortest bar, so a quiet passage still reads
      // as a track rather than as a gap in the drawing.
      final extent = math.max(2.0, bars[i] * mid * 0.94);
      paint
        ..color = x <= headX ? played : unplayed.withValues(alpha: 0.55)
        ..strokeWidth = 3;
      canvas.drawLine(Offset(x, mid - extent), Offset(x, mid + extent), paint);
    }

    canvas.drawLine(
      Offset(headX, 0),
      Offset(headX, size.height),
      Paint()
        ..color = playhead.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformLandscapePainter old) =>
      !identical(old.peaks, peaks) ||
      old.duration != duration ||
      old.played != played ||
      old.unplayed != unplayed ||
      old.playhead != playhead;
}

/// The same peaks bent into a ring around the platter, one bar per
/// bucket radiating outward, with the played arc in accent.
class _PeakRingPainter extends CustomPainter {
  _PeakRingPainter({
    required this.position,
    required this.duration,
    required this.peaks,
    required this.played,
    required this.unplayed,
    required this.innerRadius,
  }) : super(repaint: position);

  final ValueListenable<Duration> position;
  final Duration duration;
  final List<double> peaks;
  final Color played;
  final Color unplayed;
  final double innerRadius;

  /// How many bars the ring carries. Fixed rather than derived from the
  /// circumference: the ring is read as a dial, and a count that changed
  /// with the window would make the same track a different picture on
  /// every screen.
  static const int _bars = 180;

  /// Held between paints, and keyed by the peaks for the reason the
  /// landscape's is.
  List<double>? _reduced;
  List<double>? _reducedFrom;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    if (_reduced == null || !identical(_reducedFrom, peaks)) {
      _reducedFrom = peaks;
      _reduced = downsamplePeaks(peaks, _bars);
    }
    final bars = _reduced!;
    final centre = size.center(Offset.zero);
    final room = math.min(size.width, size.height) / 2 - innerRadius;
    if (room <= 0) return;
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.value.inMilliseconds / total).clamp(0.0, 1.0);

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;
    for (var i = 0; i < bars.length; i++) {
      // From twelve o'clock, clockwise: the ring reads as a dial, and a
      // dial that starts at three o'clock reads as an accident.
      final angle = (i / bars.length) * 2 * math.pi - math.pi / 2;
      final extent = math.max(2.0, bars[i] * room * 0.9);
      final unit = Offset(math.cos(angle), math.sin(angle));
      paint.color = (i / bars.length) <= fraction
          ? played
          : unplayed.withValues(alpha: 0.5);
      canvas.drawLine(
        centre + unit * innerRadius,
        centre + unit * (innerRadius + extent),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PeakRingPainter old) =>
      !identical(old.peaks, peaks) ||
      old.duration != duration ||
      old.innerRadius != innerRadius ||
      old.played != played ||
      old.unplayed != unplayed;
}
