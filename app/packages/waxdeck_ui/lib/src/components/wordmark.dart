import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// The WaxDeck logotype: the name in Archivo Expanded with the needle
/// glyph beside it.
///
/// Drawn rather than shipped as an image, so it is crisp at any size, in
/// any theme, and at any text scale. The SVG master in
/// `assets/brand/wordmark.svg` exists for the places Flutter is not (the
/// README, packaging art); this is what the app itself uses on login,
/// setup, and about.
class WaxWordmark extends StatelessWidget {
  const WaxWordmark({
    this.size = 28,
    this.color,
    this.showMark = true,
    super.key,
  });

  /// Cap height of the logotype, in logical pixels.
  final double size;

  final Color? color;

  /// The needle mark. Dropped where the wordmark sits beside other
  /// chrome that already carries the identity.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final ink = color ?? colors.textPrimary;
    return Semantics(
      label: 'WaxDeck',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showMark) ...<Widget>[
              CustomPaint(
                size: Size(size * 1.15, size * 0.85),
                painter: _NeedleMarkPainter(
                  ink: colors.accent,
                  dial: colors.outline,
                ),
              ),
              SizedBox(width: size * 0.35),
            ],
            Text(
              'WaxDeck',
              style: WaxType.display.copyWith(fontSize: size, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedleMarkPainter extends CustomPainter {
  _NeedleMarkPainter({required this.ink, required this.dial});

  final Color ink;
  final Color dial;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height * 0.94);
    final radius = size.width * 0.44;
    const sweep = math.pi * 0.62;
    final start = -math.pi / 2 - sweep / 2;

    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: radius),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.06)
        ..strokeCap = StrokeCap.round
        ..color = dial,
    );

    final angle = start + sweep * 0.6;
    canvas.drawLine(
      pivot,
      pivot + Offset(math.cos(angle), math.sin(angle)) * radius,
      Paint()
        ..strokeWidth = math.max(1.2, size.width * 0.08)
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
    canvas.drawCircle(
      pivot,
      math.max(1.4, size.width * 0.08),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_NeedleMarkPainter old) =>
      old.ink != ink || old.dial != dial;
}

/// The wordmark centred with a tagline, for login, setup, and about.
class WaxBrandBlock extends StatelessWidget {
  const WaxBrandBlock({this.tagline, this.size = 34, super.key});

  final String? tagline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WaxWordmark(size: size),
        if (tagline != null) ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: WaxType.body.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}
