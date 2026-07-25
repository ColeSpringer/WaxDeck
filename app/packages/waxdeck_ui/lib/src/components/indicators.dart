import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Which drawn form a playing indicator takes.
enum PlayingIndicatorForm {
  /// The VU needle: the signature element, used only where it has room
  /// to breathe (the deck bar at 24 px and up, the players, the
  /// visualiser).
  needle,

  /// Three amber bars: what an active list row gets. At 16 px a needle
  /// is illegible mush, and coarse reads better small.
  bars,
}

/// Says "this is the thing that is playing".
///
/// Motion here is the app's heartbeat, so it obeys the reduced-motion
/// token without any call site having to remember: the needle parks at
/// 60 percent deflection and the bars hold a static profile.
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    required this.playing,
    this.form = PlayingIndicatorForm.needle,
    this.size = 24,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final bool playing;
  final PlayingIndicatorForm form;
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

  /// The ticker runs only while this is on screen and playing: a needle
  /// animating behind a closed sheet is a battery bug.
  void _sync() {
    final animate = widget.playing && WaxMotion.of(context).animationsEnabled;
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
    final label =
        widget.semanticLabel ?? (widget.playing ? 'Playing' : 'Paused');
    return Semantics(
      label: label,
      child: SizedBox(
        width: widget.size,
        height: widget.form == PlayingIndicatorForm.needle
            ? widget.size * 0.72
            : widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: switch (widget.form) {
              PlayingIndicatorForm.needle => _NeedlePainter(
                phase: _controller.value,
                playing: widget.playing,
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

/// The VU needle: a dial arc with a needle that settles like a real
/// meter, weighted toward the upper range rather than sweeping evenly.
class _NeedlePainter extends CustomPainter {
  _NeedlePainter({
    required this.phase,
    required this.playing,
    required this.color,
    required this.track,
  });

  final double phase;
  final bool playing;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height * 0.98);
    final radius = size.width * 0.46;
    const sweep = math.pi * 0.62;
    final start = -math.pi / 2 - sweep / 2;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.width * 0.05)
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: radius),
      start,
      sweep,
      false,
      arc,
    );

    // Parked at 60 percent when still: a frozen needle at zero reads as
    // broken equipment rather than as paused.
    final deflection = playing
        ? 0.5 +
              0.34 * math.sin(phase * math.pi * 2) +
              0.12 * math.sin(phase * math.pi * 6.3)
        : 0.6;
    final angle = start + sweep * deflection.clamp(0.04, 0.96);
    final tip = pivot + Offset(math.cos(angle), math.sin(angle)) * radius;

    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..strokeWidth = math.max(1.2, size.width * 0.06)
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(
      pivot,
      math.max(1.4, size.width * 0.07),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.phase != phase || old.playing != playing || old.color != color;
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

  static String defaultLabel(WaxDomain domain) => switch (domain) {
    WaxDomain.music => 'Music',
    WaxDomain.podcasts => 'Podcast',
    WaxDomain.audiobooks => 'Book',
    WaxDomain.radio => 'Radio',
  };

  @override
  Widget build(BuildContext context) {
    final hue = WaxColors.of(context).domain(domain);
    final text = label ?? defaultLabel(domain);
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
