import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// A single-series bar chart drawn with a painter: thin bars in one hue
/// with rounded data ends, a recessive baseline, and sparse labels
/// under the axis. Values are milliseconds (or any magnitude); identity
/// comes from the surrounding section title, so there is no legend.
class ListeningBarChart extends StatelessWidget {
  const ListeningBarChart({
    super.key,
    required this.values,
    this.labels = const {},
    this.height = 140,
  });

  /// One magnitude per bar, in axis order.
  final List<int> values;

  /// Sparse axis labels by bar index.
  final Map<int, String> labels;

  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: BarChartPainter(
          values: values,
          labels: labels,
          barColor: colorScheme.primary,
          axisColor: colorScheme.outlineVariant,
          labelStyle: labelStyle,
        ),
      ),
    );
  }
}

class BarChartPainter extends CustomPainter {
  BarChartPainter({
    required this.values,
    required this.labels,
    required this.barColor,
    required this.axisColor,
    this.labelStyle,
  });

  final List<int> values;
  final Map<int, String> labels;
  final Color barColor;
  final Color axisColor;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final labelHeight = labels.isEmpty ? 0.0 : 16.0;
    final chartHeight = size.height - labelHeight - 1;
    final axisY = chartHeight + 0.5;
    canvas.drawLine(
      Offset(0, axisY),
      Offset(size.width, axisY),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );
    if (values.isEmpty) return;
    final maxValue = values.fold(0, math.max);
    final slot = size.width / values.length;
    final gap = math.min(2.0, slot * 0.2);
    final barWidth = math.max(1.0, slot - gap);
    final radius = Radius.circular(math.min(4.0, barWidth / 2));
    final paint = Paint()..color = barColor;
    for (var i = 0; i < values.length; i++) {
      if (maxValue > 0 && values[i] > 0) {
        final h = math.max(2.0, chartHeight * values[i] / maxValue);
        final left = i * slot + gap / 2;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, chartHeight - h, barWidth, h),
            topLeft: radius,
            topRight: radius,
          ),
          paint,
        );
      }
      final label = labels[i];
      if (label != null) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        var x = i * slot + slot / 2 - painter.width / 2;
        final maxX = math.max(0.0, size.width - painter.width);
        if (x < 0) x = 0;
        if (x > maxX) x = maxX;
        painter.paint(canvas, Offset(x, chartHeight + 3));
      }
    }
  }

  @override
  bool shouldRepaint(BarChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.barColor != barColor ||
      oldDelegate.axisColor != axisColor;
}

/// A calendar-year listening heatmap: weeks as columns, Monday through
/// Sunday as rows, cell intensity by listening-time quartile. A single
/// hue stepping light to dark carries the magnitude; empty days stay on
/// the neutral surface tint.
class YearHeatmap extends StatelessWidget {
  const YearHeatmap({super.key, required this.heatmap});

  final ListeningHeatmap heatmap;

  /// Per-day quartile levels (1 to 4) keyed by day-of-year index; days
  /// without listening are absent. Quartiles are computed over the
  /// year's nonzero days so one heavy day cannot flatten the rest.
  static Map<int, int> quartileLevels(ListeningHeatmap heatmap) {
    final start = DateTime.utc(heatmap.year, 1, 1);
    final nonzero = [
      for (final day in heatmap.days)
        if (day.ms > 0) day.ms,
    ]..sort();
    if (nonzero.isEmpty) return const {};
    int threshold(double fraction) =>
        nonzero[((nonzero.length - 1) * fraction).round()];
    final q1 = threshold(0.25);
    final q2 = threshold(0.5);
    final q3 = threshold(0.75);
    final levels = <int, int>{};
    for (final day in heatmap.days) {
      if (day.ms <= 0) continue;
      final index = day.date.difference(start).inDays;
      if (index < 0) continue;
      levels[index] = day.ms <= q1
          ? 1
          : day.ms <= q2
          ? 2
          : day.ms <= q3
          ? 3
          : 4;
    }
    return levels;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final start = DateTime.utc(heatmap.year, 1, 1);
        final days = DateTime.utc(
          heatmap.year + 1,
          1,
          1,
        ).difference(start).inDays;
        final offset = start.weekday - 1;
        final weeks = (offset + days + 6) ~/ 7;
        final cell = constraints.maxWidth / weeks;
        return SizedBox(
          width: constraints.maxWidth,
          height: cell * 7,
          child: CustomPaint(
            painter: HeatmapPainter(
              dayCount: days,
              weekdayOffset: offset,
              levels: quartileLevels(heatmap),
              emptyColor: colorScheme.surfaceContainerHighest,
              fillColor: colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class HeatmapPainter extends CustomPainter {
  HeatmapPainter({
    required this.dayCount,
    required this.weekdayOffset,
    required this.levels,
    required this.emptyColor,
    required this.fillColor,
  });

  final int dayCount;

  /// Row of January 1st: 0 for Monday through 6 for Sunday.
  final int weekdayOffset;

  /// Quartile level (1 to 4) by day-of-year index; absent means empty.
  final Map<int, int> levels;

  final Color emptyColor;
  final Color fillColor;

  static const _alphaByLevel = [0.3, 0.55, 0.8, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final weeks = (weekdayOffset + dayCount + 6) ~/ 7;
    final cell = size.width / weeks;
    final gap = math.max(1.0, cell * 0.15);
    final side = math.max(1.0, cell - gap);
    final radius = Radius.circular(math.min(2.0, side / 2));
    final paint = Paint();
    for (var i = 0; i < dayCount; i++) {
      final column = (weekdayOffset + i) ~/ 7;
      final row = (weekdayOffset + i) % 7;
      final level = levels[i];
      paint.color = level == null
          ? emptyColor
          : fillColor.withValues(alpha: _alphaByLevel[level - 1]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(column * cell, row * cell, side, side),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HeatmapPainter oldDelegate) =>
      oldDelegate.dayCount != dayCount ||
      oldDelegate.weekdayOffset != weekdayOffset ||
      oldDelegate.levels != levels ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.fillColor != fillColor;
}
