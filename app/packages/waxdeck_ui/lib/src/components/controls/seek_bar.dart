part of 'track_controls.dart';

/// The seek bar.
///
/// One component covers every medium: a plain track for music, a buffered
/// track for streams, an optional waveform for tracks with peaks, and a
/// live pill instead of a track for radio (the players hide it there).
/// It is a semantic slider, so a screen reader can scrub it: increase and
/// decrease step by [step], and the announced value is a spoken time
/// rather than a percentage.
class WaxSeekBar extends StatefulWidget {
  const WaxSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffered,
    this.peaks,
    this.marks,
    this.step = const Duration(seconds: 5),
    this.semanticsId,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;
  final Duration? buffered;

  /// Normalised 0 to 1 peak amplitudes. When present the track renders as
  /// a waveform; when absent it is a styled bar. Nothing here invents
  /// data: no peaks, no waveform.
  final List<double>? peaks;

  /// Positions to tick, for a bar that spans something with divisions in
  /// it: a book's chapters across a whole-book envelope.
  ///
  /// Decoration, and deliberately not semantics. The slider already
  /// announces one position and one span; a screen reader hearing
  /// forty tick marks would be told about the shape of a picture it
  /// cannot see, and the chapter list is where a chapter is chosen.
  final List<Duration>? marks;

  final Duration step;
  final String? semanticsId;

  @override
  State<WaxSeekBar> createState() => _WaxSeekBarState();
}

/// One waveform bar every this many logical pixels: a 2 px bar and a
/// 1 px gap, which is the coarsest reading that still shows a track's
/// shape and the finest that still reads as bars rather than as a smear.
const double _barPitch = 3;

class _WaxSeekBarState extends State<WaxSeekBar> {
  double? _dragFraction;

  /// Latched on abandon so the raw glide events a winning scroll keeps
  /// sending stop moving the scrub preview; reset by the next press.
  bool _dead = false;

  /// A pointer is over the bar, so the playhead draws a size up. Only a
  /// device that hovers ever sets it.
  ///
  /// A notifier, for the reason [WaxSlider]'s is one.
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  /// The peaks reduced to the number of bars this width draws.
  ///
  /// Held rather than recomputed in `paint`: the playhead moves several
  /// times a second and the peaks do not, so reducing a thousand buckets
  /// per frame would be a thousand comparisons and a fresh list to draw
  /// a shape that has not changed since the track started.
  List<double>? _heights;
  List<double>? _heightsFrom;
  int _heightsBars = 0;

  List<double>? _resolvedHeights(double width) {
    final peaks = widget.peaks;
    if (peaks == null || peaks.isEmpty) return null;
    // An unbounded width has no bar count to derive; a fixed reading is
    // better than none, and the constrained case is every real one.
    final bars = width.isFinite
        ? math.max(1, (width / _barPitch).floor())
        : 120;
    if (!identical(_heightsFrom, peaks) || _heightsBars != bars) {
      _heightsFrom = peaks;
      _heightsBars = bars;
      _heights = downsamplePeaks(peaks, bars);
    }
    return _heights;
  }

  @override
  void didUpdateWidget(WaxSeekBar old) {
    super.didUpdateWidget(old);
    // Disabling mid-scrub disposes the recognisers during the rebuild,
    // and their cancel callbacks land mid-build where setState must not.
    // A frame arriving with no duration lets go of the scrub here,
    // before the build, so the late cancels find nothing to do.
    if (widget.onSeek == null || widget.duration <= Duration.zero) {
      _dragFraction = null;
    }
  }

  double get _fraction {
    if (_dragFraction != null) return _dragFraction!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0, 1);
  }

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.duration.inMilliseconds * fraction).round(),
  );

  /// The ticks as fractions of the span.
  ///
  /// Held like the heights are, for the same reason: the playhead moves
  /// several times a second and the divisions do not, and the painter
  /// compares this list by identity.
  List<double>? _markFractions;
  List<Duration>? _marksFrom;
  Duration? _marksSpan;

  List<double>? _resolvedMarks() {
    if (!identical(_marksFrom, widget.marks) || _marksSpan != widget.duration) {
      _marksFrom = widget.marks;
      _marksSpan = widget.duration;
      _markFractions = markFractions(widget.marks, widget.duration);
    }
    return _markFractions;
  }

  Duration _offsetBy(Duration delta) {
    final target = widget.position + delta;
    if (target < Duration.zero) return Duration.zero;
    return target > widget.duration ? widget.duration : target;
  }

  void _seekBy(Duration delta) {
    if (widget.duration <= Duration.zero) return;
    widget.onSeek?.call(_offsetBy(delta));
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    // Every position here is a fraction of the duration, so at zero a
    // scrub or a keyboard step seeks to the start. Callers reach that
    // without meaning to (an unresolved duration, a session frame carrying
    // none), so the guard is here rather than in each of them.
    final enabled = widget.onSeek != null && widget.duration > Duration.zero;
    final l10n = context.waxL10n;

    return Semantics(
      identifier: widget.semanticsId,
      slider: true,
      enabled: enabled,
      label: l10n.controlsSeekLabel,
      value: l10n.controlsSeekValue(
        l10n.spellDuration(widget.position),
        l10n.spellDuration(widget.duration),
      ),
      // Position is announced as a spoken time rather than a percentage,
      // and the step values ride along: a slider that offers increase
      // without saying where increasing lands is a half-built control
      // (and an assertion failure).
      increasedValue: l10n.spellDuration(_offsetBy(widget.step)),
      decreasedValue: l10n.spellDuration(_offsetBy(-widget.step)),
      // Offered while disabled too, and inert then: the web build swaps a
      // node's element when it gains or loses its steps, which would drop
      // the identifier and a screen reader's place on every load.
      onIncrease: () => _seekBy(widget.step),
      onDecrease: () => _seekBy(-widget.step),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The scrub is a preview until release, deliberately: a live
            // seek per drag frame would spam stream loads, so the drag
            // paints and only the commit seeks.
            void preview(double fraction) =>
                setState(() => _dragFraction = fraction);

            void commit() {
              widget.onSeek!(_at(_fraction));
              setState(() => _dragFraction = null);
            }

            // A press that loses the arena to a scroll never ends, and
            // a scrub position left behind would pin the playhead
            // there for good. No-ops when nothing is held: a disable's
            // late cancel arrives mid-build, after didUpdateWidget
            // already let go, where setState must not run.
            void abandon() {
              _dead = true;
              if (_dragFraction == null) return;
              setState(() => _dragFraction = null);
            }

            return _TrackGestures(
              enabled: enabled,
              width: constraints.maxWidth,
              inset: 0,
              // A seek is destructive where a level is not, so a press
              // previews from every device and commits on release.
              onPress: (fraction, _) {
                _dead = false;
                preview(fraction);
              },
              onGlide: (fraction) {
                if (_dead) return;
                preview(fraction);
              },
              onDrag: (fraction) {
                _dead = false;
                preview(fraction);
              },
              onCommit: commit,
              onAbandon: abandon,
              onHover: (over) {
                _hovered.value = over;
              },
              child: SizedBox(
                // Width has to be claimed explicitly: inside a centred
                // Column the constraints are loose, and a CustomPaint
                // with no size collapses to nothing. The height is the
                // touch target whatever is drawn: a 24 px box over a
                // 4 px track demanded the accuracy the bug report
                // named.
                width: double.infinity,
                height: WaxSpace.touchTarget,
                child: CustomPaint(
                  painter: _SeekPainter(
                    fraction: _fraction,
                    buffered: widget.duration.inMilliseconds <= 0
                        ? 0
                        : ((widget.buffered ?? Duration.zero).inMilliseconds /
                                  widget.duration.inMilliseconds)
                              .clamp(0, 1),
                    // Resolved against the width the bar was given
                    // rather than handed over raw: the reduction is a
                    // property of this layout, and it outlives every
                    // frame the playhead moves through.
                    heights: _resolvedHeights(constraints.maxWidth),
                    marks: _resolvedMarks(),
                    track: colors.hairline,
                    bufferTint: colors.textTertiary.withValues(alpha: 0.4),
                    fill: colors.accent,
                    knob: enabled ? colors.accent : colors.textDisabled,
                    mark: colors.textTertiary.withValues(alpha: 0.5),
                    hovered: _hovered,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [marks] as fractions of [span], with anything outside it dropped.
///
/// Dropped rather than clamped, and both edges excluded. These come out
/// of file metadata through a third-party reader, so a chapter list and
/// a duration disagreeing is ordinary rather than exceptional - and a
/// tick pinned to the end would sit on the knob's rail claiming a
/// division starts where the bar stops. Null where there is nothing to
/// draw, which is what the painter takes to mean "no ticks".
List<double>? markFractions(List<Duration>? marks, Duration span) {
  final total = span.inMilliseconds;
  if (marks == null || marks.isEmpty || total <= 0) return null;
  final out = <double>[
    for (final at in marks)
      if (at > Duration.zero && at < span) at.inMilliseconds / total,
  ];
  return out.isEmpty ? null : out;
}

/// [peaks] reduced to [bars] values, each the loudest of the range it
/// covers.
///
/// The catalog stores a fixed thousand buckets and a seek bar is
/// whatever width it was given, so the two are reconciled at paint time.
/// Loudest rather than mean, because an averaged envelope loses exactly
/// the transients that make a track recognisable: the shape a listener
/// aims a scrub at is its peaks, not its energy. Fewer peaks than bars
/// is fine and repeats values rather than inventing them.
List<double> downsamplePeaks(List<double> peaks, int bars) {
  if (peaks.isEmpty || bars <= 0) return const <double>[];
  return List<double>.generate(bars, (i) {
    final from = (i * peaks.length) ~/ bars;
    final to = math.max(from + 1, ((i + 1) * peaks.length) ~/ bars);
    var peak = 0.0;
    for (var j = from; j < to && j < peaks.length; j++) {
      if (peaks[j] > peak) peak = peaks[j];
    }
    return peak.clamp(0.0, 1.0);
  }, growable: false);
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.fraction,
    required this.buffered,
    required this.heights,
    required this.marks,
    required this.track,
    required this.bufferTint,
    required this.fill,
    required this.knob,
    required this.mark,
    required this.hovered,
  }) : super(repaint: hovered);

  final double fraction;
  final double buffered;

  /// One value per bar, already reduced to this bar's width by the
  /// state that owns it. Null draws the plain track.
  final List<double>? heights;

  /// Fractions of the span to tick, already bounded by the state.
  final List<double>? marks;

  final Color track;
  final Color bufferTint;
  final Color fill;
  final Color knob;
  final Color mark;

  /// A pointer is over the bar. The playhead grows; nothing else
  /// changes, because a track that lights up under the cursor reads as
  /// having moved rather than as being reachable.
  ///
  /// A listenable, for the reason [_LevelPainter.hovered] is one.
  final ValueListenable<bool> hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final heights = this.heights;
    if (heights != null && heights.isNotEmpty) {
      final bars = heights.length;
      final barWidth = size.width / bars;
      final mid = size.height / 2;
      for (var i = 0; i < bars; i++) {
        final centre = (i + 0.5) / bars;
        final height = math.max(2.0, heights[i] * size.height * 0.92);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              i * barWidth,
              mid - height / 2,
              math.max(1, barWidth - 1),
              height,
            ),
            const Radius.circular(1),
          ),
          Paint()
            ..color = centre <= fraction
                ? fill
                : (centre <= buffered ? bufferTint : track),
        );
      }
      _paintMarks(canvas, size, size.height * 0.92);
      return;
    }

    const height = 4.0;
    final top = (size.height - height) / 2;
    final radius = const Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, height),
        radius,
      ),
      Paint()..color = track,
    );
    if (buffered > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, size.width * buffered, height),
          radius,
        ),
        Paint()..color = bufferTint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width * fraction, height),
        radius,
      ),
      Paint()..color = fill,
    );
    // Between the fill and the knob: a tick under the playhead would be
    // a division the knob is hiding, and one over it would look like
    // part of the control.
    _paintMarks(canvas, size, height * 2.5);
    canvas.drawCircle(
      Offset(size.width * fraction, size.height / 2),
      hovered.value ? 8 : 6,
      Paint()..color = knob,
    );
  }

  /// The division ticks, centred on the bar and one logical pixel wide.
  void _paintMarks(Canvas canvas, Size size, double height) {
    final marks = this.marks;
    if (marks == null || marks.isEmpty) return;
    final mid = size.height / 2;
    final paint = Paint()..color = mark;
    for (final at in marks) {
      canvas.drawRect(
        Rect.fromLTWH(size.width * at, mid - height / 2, 1, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      // Identity, because the state hands back the same list until the
      // peaks or the width change; comparing a few hundred doubles
      // every frame is the cost this reduction exists to avoid.
      !identical(old.heights, heights) ||
      !identical(old.marks, marks) ||
      old.fill != fill ||
      // The rest of the palette moves on a theme flip, which changes no
      // other field here: without them the bar keeps the dark set's
      // track and knob on a light canvas.
      old.track != track ||
      old.bufferTint != bufferTint ||
      old.mark != mark ||
      old.knob != knob;
  // `hovered` is absent, as in [_LevelPainter].
}
