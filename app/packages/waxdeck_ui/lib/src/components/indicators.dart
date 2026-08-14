import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Which drawn form a playing indicator takes.
enum PlayingIndicatorForm {
  /// The tonearm: the signature element, used only where it has room to
  /// breathe (the deck bar at 24 px and up, the players, the visualiser).
  tonearm,

  /// Three amber bars: what an active list row gets. At 16 px a tonearm
  /// is illegible mush, and coarse reads better small.
  bars,
}

/// Says "this is the thing that is playing".
///
/// Motion here is the app's heartbeat, so it obeys the reduced-motion
/// token without any call site having to remember: the bars hold a
/// static profile, and the tonearm rests wherever the track stands,
/// which is what a paused record player looks like.
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    required this.playing,
    this.form = PlayingIndicatorForm.tonearm,
    this.progress,
    this.size = 24,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final bool playing;
  final PlayingIndicatorForm form;

  /// How far into the track playback stands, 0 to 1.
  ///
  /// This is what moves the arm, and it is why the element was worth
  /// keeping rather than restyling: the form it replaces swept a VU
  /// needle on a synthetic waveform, because there is no level to meter
  /// (`AudioEnginePort` exposes output volume, not peak or RMS, and
  /// neither just_audio nor the other engines offer one). A faked meter
  /// is decoration that claims to be a reading. Position is a real
  /// signal already in hand, and an arm crossing a record is what this
  /// app's own metaphor says it means.
  ///
  /// Null where the caller has no position (live radio, an unmeasured
  /// stream): the arm rests partway in, which reads as a record playing
  /// rather than as a stuck one at the edge.
  final double? progress;

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// The ticker runs only while this is on screen, playing, and drawing
  /// something a clock has to move: an indicator animating behind a
  /// closed sheet is a battery bug, and the tonearm needs no ticker at
  /// all because the position it follows already arrives as rebuilds.
  void _sync() {
    final animate =
        widget.playing &&
        widget.form == PlayingIndicatorForm.bars &&
        WaxMotion.of(context).animationsEnabled;
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final color = widget.color ?? colors.accent;
    final l10n = context.waxL10n;
    final label =
        widget.semanticLabel ??
        (widget.playing ? l10n.commonPlaying : l10n.commonPaused);
    return Semantics(
      label: label,
      child: SizedBox(
        width: widget.size,
        height: widget.form == PlayingIndicatorForm.tonearm
            ? widget.size * _TonearmPainter.aspect
            : widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: switch (widget.form) {
              PlayingIndicatorForm.tonearm => _TonearmPainter(
                // Partway in when the caller has no position: an arm
                // parked at the outer edge reads as a record that never
                // started.
                progress: (widget.progress ?? 0.35).clamp(0.0, 1.0),
                color: color,
                track: colors.hairline,
              ),
              PlayingIndicatorForm.bars => _BarsPainter(
                phase: _controller.value,
                playing: widget.playing,
                color: color,
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// A record with the arm across it, the stylus where the track stands.
///
/// The arm is a fixed length pivoting at the corner, exactly as a real
/// one is, so the stylus travels from the outer edge in toward the
/// spindle as the track plays and the angle follows from the geometry
/// rather than being animated separately.
class _TonearmPainter extends CustomPainter {
  _TonearmPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  /// 0 at the lead-in groove, 1 at the run-out.
  final double progress;
  final Color color;
  final Color track;

  // The deck's proportions, in units of the box's width. Fixed rather
  // than derived so the arm's travel is the same shape at 24 px and at
  // 40, and chosen so the two circles below always intersect.
  static const double _discX = 0.42;
  static const double _discY = 0.42;
  static const double _discR = 0.34;
  static const double _pivotX = 0.90;
  static const double _pivotY = 0.10;
  static const double _armLength = 0.62;

  /// Where the stylus rides at each end of the record.
  static const double _leadIn = 0.34;
  static const double _runOut = 0.11;

  /// How tall the box has to be, as a fraction of its width.
  ///
  /// Derived rather than chosen, and read by the widget rather than
  /// duplicated there: the disc alone reaches `_discY + _discR` = 0.76
  /// down, and the headshell dot rides its rim. Against the 0.72 this
  /// inherited from the meter it replaced, the bottom of the record fell
  /// nearly two pixels outside the render object at deck-bar size -
  /// invisible only because nothing above it happens to clip.
  static const double aspect = 0.82;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final centre = Offset(_discX * s, _discY * s);
    final pivot = Offset(_pivotX * s, _pivotY * s);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    // The record and one groove inside it, which is what says the disc
    // is a disc rather than a ring at this size.
    canvas.drawCircle(
      centre,
      _discR * s,
      line..strokeWidth = math.max(1, s * 0.05),
    );
    canvas.drawCircle(
      centre,
      _discR * s * 0.62,
      line..strokeWidth = math.max(0.6, s * 0.025),
    );

    final stylus = _stylus(s, centre, pivot);
    canvas.drawLine(
      pivot,
      stylus,
      Paint()
        ..strokeWidth = math.max(1.2, s * 0.06)
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    // The bearing and the headshell, the two ends that make the line
    // read as an arm rather than as a stray rule across the disc.
    final solid = Paint()..color = color;
    canvas.drawCircle(pivot, math.max(1.4, s * 0.07), solid);
    canvas.drawCircle(stylus, math.max(1, s * 0.045), solid);
    // The spindle, so the centre of the record is where the arm is
    // heading rather than an empty hole.
    canvas.drawCircle(centre, math.max(0.8, s * 0.035), solid);
  }

  /// Where the stylus sits: on the record at the radius [progress] names,
  /// and an arm's length from the bearing.
  ///
  /// Those two conditions are two circles, and the intersection is the
  /// answer; the lower of the two is the one on the near side of the
  /// deck. The geometry constants keep the circles overlapping across the
  /// whole travel, so the guarded square root is for arithmetic error
  /// rather than for a case that can happen.
  Offset _stylus(double s, Offset centre, Offset pivot) {
    final grooveR = (_leadIn - progress * (_leadIn - _runOut)) * s;
    final armLen = _armLength * s;
    final span = centre - pivot;
    final d = span.distance;
    final along = (armLen * armLen - grooveR * grooveR + d * d) / (2 * d);
    final off = math.sqrt(math.max(0, armLen * armLen - along * along));
    final unit = span / d;
    final base = pivot + unit * along;
    final perp = Offset(-unit.dy, unit.dx) * off;
    final a = base + perp;
    final b = base - perp;
    return a.dy >= b.dy ? a : b;
  }

  @override
  bool shouldRepaint(_TonearmPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Three bars for list rows, where a needle would be mush.
class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.phase,
    required this.playing,
    required this.color,
  });

  final double phase;
  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 3;
    final width = size.width / (bars * 2 - 1);
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final offset = i / bars;
      final height = playing
          ? size.height *
                (0.35 +
                    0.6 *
                        (0.5 + 0.5 * math.sin((phase + offset) * math.pi * 2)))
          : size.height * (i == 1 ? 0.7 : 0.45);
      final left = i * width * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, width, height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.phase != phase || old.playing != playing || old.color != color;
}

/// A small chip naming a domain, for cross-domain surfaces such as Home
/// and search results where music, episodes, and books sit together.
class DomainBadge extends StatelessWidget {
  const DomainBadge(this.domain, {this.label, this.compact = false, super.key});

  final WaxDomain domain;

  /// Defaults to the domain's own name; pass a more specific one
  /// ("Episode", "Chapter 4") where that reads better.
  final String? label;

  final bool compact;

  static String defaultLabel(WaxLocalizations l10n, WaxDomain domain) =>
      switch (domain) {
        WaxDomain.music => l10n.domainMusic,
        WaxDomain.podcasts => l10n.domainPodcast,
        WaxDomain.audiobooks => l10n.domainBook,
        WaxDomain.radio => l10n.domainRadio,
      };

  @override
  Widget build(BuildContext context) {
    final hue = WaxColors.of(context).domain(domain);
    final text = label ?? defaultLabel(context.waxL10n, domain);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? WaxSpace.s4 : WaxSpace.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: hue.container,
        borderRadius: WaxRadius.chip,
      ),
      child: Text(
        text,
        style: WaxType.caption.copyWith(color: hue.onContainer),
      ),
    );
  }
}

/// Technical detail in the equipment-readout voice: codec, bitrate,
/// sample rate.
///
/// This is the power-user channel. It is always available one level in,
/// and the first layer never pays for it.
class CodecChip extends StatelessWidget {
  const CodecChip(this.label, {this.emphasis = false, super.key});

  final String label;

  /// Lossless, hi-res, or otherwise worth noticing.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8, vertical: 2),
      decoration: BoxDecoration(
        color: emphasis ? colors.accentContainer : colors.surface2,
        borderRadius: WaxRadius.chip,
        border: Border.all(
          color: emphasis ? Colors.transparent : colors.hairline,
        ),
      ),
      child: Text(
        label,
        style: WaxType.monoData.copyWith(
          color: emphasis ? colors.onAccentContainer : colors.textSecondary,
        ),
      ),
    );
  }
}

/// A label and its value, value set in mono. The building block of every
/// detail sheet, diagnostics panel, and "advanced" expander.
class MonoDetailRow extends StatelessWidget {
  const MonoDetailRow({
    required this.label,
    required this.value,
    this.semanticsId,
    super.key,
  });

  final String label;
  final String value;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: WaxSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: WaxSpace.s12),
          Expanded(
            child: Text(
              value,
              style: WaxType.monoData.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (semanticsId == null) return row;
    return Semantics(identifier: semanticsId, child: row);
  }
}
