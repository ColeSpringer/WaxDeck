import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// One share of a [MediaSplitBar].
///
/// Plain data, like every other view model here: the caller names the
/// domain and supplies both the magnitude the bar is drawn from and the
/// words the legend reads, already formatted in the caller's locale.
@immutable
class MediaSplitSegment {
  const MediaSplitSegment({
    required this.label,
    required this.value,
    required this.domain,
    this.valueLabel,
  });

  /// What this share is called: "Podcasts", "Music".
  final String label;

  /// The magnitude the segment is sized from. Shares are relative, so
  /// the unit is the caller's business.
  final int value;

  final WaxDomain domain;

  /// The magnitude in words ("4h 12m"). The legend draws it beside the
  /// label; without one the legend shows the label alone.
  final String? valueLabel;
}

/// How listening divides across the four media types: one stacked bar
/// over a legend naming each share.
///
/// The bar is the glance and the legend is the answer. Two domain hues
/// are within 1.7:1 of each other in every theme - they are identity
/// tints, not a categorical scale - so the segments are set apart by a
/// gap of the track rather than left to abut, and the words are never
/// only in the colour. That is also why the whole thing reads to a
/// screen reader as [summary] rather than as a row of coloured boxes.
class MediaSplitBar extends StatelessWidget {
  const MediaSplitBar({
    required this.segments,
    required this.summary,
    this.height = 10,
    super.key,
  });

  /// The shares, in the order they are drawn. Segments with no value
  /// are dropped: an empty share is not a share.
  final List<MediaSplitSegment> segments;

  /// The split in one sentence, for anybody not looking at it.
  final String summary;

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final drawn = <MediaSplitSegment>[
      for (final s in segments)
        if (s.value > 0) s,
    ];
    if (drawn.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: summary,
      readOnly: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(
                painter: _SplitBarPainter(
                  values: <int>[for (final s in drawn) s.value],
                  colors: <Color>[
                    for (final s in drawn) colors.domain(s.domain).hue,
                  ],
                  track: colors.surface2,
                  mirrored: Directionality.of(context) == TextDirection.rtl,
                ),
              ),
            ),
            const SizedBox(height: WaxSpace.s12),
            for (final segment in drawn)
              Padding(
                padding: const EdgeInsets.only(bottom: WaxSpace.s4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.domain(segment.domain).hue,
                        borderRadius: WaxRadius.pill,
                      ),
                    ),
                    const SizedBox(width: WaxSpace.s8),
                    Expanded(
                      child: Text(
                        segment.label,
                        style: WaxType.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (segment.valueLabel != null) ...<Widget>[
                      const SizedBox(width: WaxSpace.s8),
                      Text(
                        segment.valueLabel!,
                        style: WaxType.monoData.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The stacked bar itself: a rounded track with one rounded segment per
/// share, gapped so no two hues touch.
class _SplitBarPainter extends CustomPainter {
  _SplitBarPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.mirrored,
  });

  final List<int> values;
  final List<Color> colors;
  final Color track;

  /// Right-to-left, so the first share leads from the reading edge like
  /// the legend beside it.
  final bool mirrored;

  /// Wide enough to read as a break at every density, narrow enough
  /// that a thin share is still a share.
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    var total = 0;
    for (final v in values) {
      total += v;
    }
    if (total <= 0) return;
    // Both fixed costs come out of the width before any share is
    // measured: the gaps, and the floor every segment is given. A share
    // that rounds below the bar's own height would draw as a sliver
    // thinner than its own rounded ends, so a round dot is the honest
    // minimum for "some, but very little" - and taking that minimum out
    // up front is what keeps the widths summing to the bar. Floored
    // after the fact instead, the running offset overshoots and the
    // last share is clipped to a smudge or never painted at all, which
    // is the opposite of what the floor is for.
    final gaps = _gap * (values.length - 1);
    var floor = size.height;
    var drawable = size.width - gaps - floor * values.length;
    if (drawable < 0) {
      // Too narrow to give every share its floor. Proportions win: a
      // bar that overflows its box is worse than a share drawn thin.
      floor = 0;
      drawable = math.max(0.0, size.width - gaps);
    }
    var x = 0.0;
    for (var i = 0; i < values.length; i++) {
      final width = floor + drawable * values[i] / total;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            mirrored ? size.width - x - width : x,
            0,
            width,
            size.height,
          ),
          radius,
        ),
        Paint()..color = colors[i],
      );
      x += width + _gap;
    }
  }

  @override
  bool shouldRepaint(_SplitBarPainter old) =>
      !listEquals(old.values, values) ||
      !listEquals(old.colors, colors) ||
      old.track != track ||
      old.mirrored != mirrored;
}
