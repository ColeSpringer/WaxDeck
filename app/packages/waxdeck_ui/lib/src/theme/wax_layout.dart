import 'package:flutter/material.dart';

import '../tokens/density.dart';
import '../tokens/spacing.dart';

/// Measurements that depend on the user's density setting, reachable as
/// `WaxLayout.of(context)`.
///
/// Density scales vertical rhythm and nothing else: type sizes are the
/// OS text-scale setting's business, and touch targets hold their 44 px
/// floor on touch platforms at every density.
@immutable
class WaxLayout extends ThemeExtension<WaxLayout> {
  const WaxLayout({
    required this.density,
    required this.rowHeight,
    required this.rowHeightDense,
    required this.listPadding,
    required this.sectionGap,
    required this.cardPadding,
    required this.focusRingWidth,
    required this.focusRingInnerWidth,
    required this.focusRingOffset,
    required this.hairlineWidth,
  });

  /// One instance per density, so two themes built from the same setting
  /// compare equal by identity as well as by value.
  factory WaxLayout.forDensity(WaxDensity density) =>
      _byDensity[density] ??= WaxLayout._forDensity(density);

  static final Map<WaxDensity, WaxLayout> _byDensity =
      <WaxDensity, WaxLayout>{};

  factory WaxLayout._forDensity(WaxDensity density) => WaxLayout(
    density: density,
    rowHeight: density.vertical(64),
    rowHeightDense: density.vertical(52),
    listPadding: EdgeInsets.symmetric(vertical: density.vertical(WaxSpace.s8)),
    sectionGap: density.vertical(WaxSpace.s32),
    cardPadding: EdgeInsets.all(WaxSpace.s12),
    focusRingWidth: 2,
    focusRingInnerWidth: 1,
    focusRingOffset: 2,
    hairlineWidth: 1,
  );

  final WaxDensity density;

  /// A media list row with artwork.
  final double rowHeight;

  /// A text-only row: queue entries, settings rows, table rows.
  final double rowHeightDense;

  final EdgeInsets listPadding;

  /// Vertical space between shelves and page sections.
  final double sectionGap;

  final EdgeInsets cardPadding;

  /// The focus ring is two-tone: an inner ring in the underlying surface
  /// colour and an outer ring in accent. A plain amber ring vanishes on
  /// an active amber element, which is a WCAG 2.4.11 failure.
  final double focusRingWidth;
  final double focusRingInnerWidth;
  final double focusRingOffset;

  final double hairlineWidth;

  static WaxLayout of(BuildContext context) =>
      Theme.of(context).extension<WaxLayout>() ??
      WaxLayout.forDensity(WaxDensity.comfortable);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaxLayout &&
          other.density == density &&
          other.rowHeight == rowHeight &&
          other.rowHeightDense == rowHeightDense &&
          other.listPadding == listPadding &&
          other.sectionGap == sectionGap &&
          other.cardPadding == cardPadding &&
          other.focusRingWidth == focusRingWidth &&
          other.focusRingInnerWidth == focusRingInnerWidth &&
          other.focusRingOffset == focusRingOffset &&
          other.hairlineWidth == hairlineWidth;

  @override
  int get hashCode => Object.hash(
    density,
    rowHeight,
    rowHeightDense,
    listPadding,
    sectionGap,
    cardPadding,
    focusRingWidth,
    focusRingInnerWidth,
    focusRingOffset,
    hairlineWidth,
  );

  @override
  WaxLayout copyWith({WaxDensity? density}) =>
      WaxLayout.forDensity(density ?? this.density);

  @override
  WaxLayout lerp(covariant WaxLayout? other, double t) {
    if (other == null) return this;
    return WaxLayout(
      density: t < 0.5 ? density : other.density,
      rowHeight: lerpDouble(rowHeight, other.rowHeight, t),
      rowHeightDense: lerpDouble(rowHeightDense, other.rowHeightDense, t),
      listPadding: EdgeInsets.lerp(listPadding, other.listPadding, t)!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t),
      cardPadding: EdgeInsets.lerp(cardPadding, other.cardPadding, t)!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t),
      focusRingInnerWidth: lerpDouble(
        focusRingInnerWidth,
        other.focusRingInnerWidth,
        t,
      ),
      focusRingOffset: lerpDouble(focusRingOffset, other.focusRingOffset, t),
      hairlineWidth: lerpDouble(hairlineWidth, other.hairlineWidth, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
