import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'marquee.dart';

/// Three amber bars beside the row or the card that is sounding.
///
/// Small on purpose, and every caller is a list row or a card corner:
/// coarse is what reads at this size. A picture of a record belongs
/// where there is room for one, which is the visualizer's platter mode
/// and the radio face's `PlatterRing`.
///
/// It obeys the reduced-motion token without any call site having to
/// remember, holding a static profile rather than freezing mid-stride.
class PlayingIndicator extends StatefulWidget {
  const PlayingIndicator({
    required this.playing,
    this.size = 16,
    this.color,
    this.semanticLabel,
    super.key,
  });

  final bool playing;
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

  /// The ticker runs only while this is on screen and playing: an
  /// indicator animating behind a closed sheet is a battery bug.
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
    final l10n = context.waxL10n;
    final label =
        widget.semanticLabel ??
        (widget.playing ? l10n.commonPlaying : l10n.commonPaused);
    return Semantics(
      label: label,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _BarsPainter(
              phase: _controller.value,
              playing: widget.playing,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bars, sized off the box so one painter serves every caller.
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

/// An indeterminate ring for work a control started, still in flight. A
/// control's glyph, never a page's, which draws the shape of what is
/// coming instead. Still under reduced motion.
class WaxSpinner extends StatefulWidget {
  const WaxSpinner({this.size = 16, this.color, super.key});

  final double size;

  /// Defaults to the accent.
  final Color? color;

  @override
  State<WaxSpinner> createState() => _WaxSpinnerState();
}

class _WaxSpinnerState extends State<WaxSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!WaxMotion.of(context).animationsEnabled) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? WaxColors.of(context).accent;
    // Decoration: the control it sits in carries the name.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: RotationTransition(
            turns: _turn,
            // Its own layer, so a turn moves the arcs rather than repainting.
            child: RepaintBoundary(
              child: CustomPaint(painter: _SpinnerPainter(color)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint track and a quarter of it drawn solid.
class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = math.max(1.5, size.shortestSide / 8);
    final rect = (Offset.zero & size).deflate(thickness / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      paint..color = color.withValues(alpha: 0.25),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi / 2,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.color != color;
}

/// How much room a [LivePill] takes.
enum LivePillSize {
  /// Beside a caption line or on a logo: the deck bar, the dial.
  compact,

  /// Beside a body line: the full-screen radio face.
  regular,
}

/// The LIVE marker a stream carries where an item would have a position,
/// one widget so the deck bar, the dial and the face cannot drift apart.
class LivePill extends StatelessWidget {
  const LivePill({this.size = LivePillSize.compact, super.key});

  final LivePillSize size;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      padding: switch (size) {
        LivePillSize.compact => const EdgeInsets.symmetric(
          horizontal: WaxSpace.s4,
          vertical: 1,
        ),
        LivePillSize.regular => const EdgeInsets.symmetric(
          horizontal: WaxSpace.s8,
          vertical: 2,
        ),
      },
      decoration: BoxDecoration(
        color: colors.radio.container,
        borderRadius: WaxRadius.pill,
      ),
      child: Text(
        context.waxL10n.commonLiveChip,
        style: WaxType.overline.copyWith(color: colors.radio.onContainer),
      ),
    );
  }
}

/// A live face's line under its name: the pill, then the song the stream
/// last named, scrolling where it does not fit.
class LiveLine extends StatelessWidget {
  const LiveLine(this.song, {super.key});

  final String? song;

  @override
  Widget build(BuildContext context) {
    final song = this.song;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const LivePill(size: LivePillSize.regular),
        if (song != null) ...<Widget>[
          const SizedBox(width: WaxSpace.s8),
          Flexible(
            child: WaxMarqueeText(
              song,
              style: WaxType.body.copyWith(
                color: WaxColors.of(context).textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
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
