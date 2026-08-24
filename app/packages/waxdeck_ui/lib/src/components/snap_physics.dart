import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';

/// Scroll physics that settle on item boundaries.
///
/// Shared: a shelf and the station dial want the same behaviour off a
/// flick, and had a copy each. Not exported from the barrel.
class SnapScrollPhysics extends ScrollPhysics {
  const SnapScrollPhysics({
    required this.itemExtent,
    this.leadingInset = 0,
    super.parent,
  });

  /// One item plus the gap after it: the distance between two landings.
  final double itemExtent;

  /// The padding before the first item. Landings are measured from it, so
  /// the first item settles against the gutter rather than under it.
  final double leadingInset;

  @override
  SnapScrollPhysics applyTo(ScrollPhysics? ancestor) => SnapScrollPhysics(
    itemExtent: itemExtent,
    leadingInset: leadingInset,
    parent: buildParent(ancestor),
  );

  /// The landing nearest [offset], clamped to the scrollable range: the
  /// grid a flick settles on. Public so the shelf's paging chevrons aim
  /// at the same grid through the same formula, rather than through a
  /// copy that only a comment keeps in agreement.
  double snapFor(double offset, ScrollMetrics position) {
    final target =
        ((offset - leadingInset) / itemExtent).roundToDouble() * itemExtent +
        leadingInset;
    return target.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range: let the parent's spring bring it back first.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final simulation = super.createBallisticSimulation(position, velocity);
    final landing = simulation?.x(double.infinity) ?? position.pixels;
    final target = snapFor(landing, position);
    if ((target - position.pixels).abs() < precisionErrorTolerance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
