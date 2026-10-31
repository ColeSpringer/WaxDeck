import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/wax_layout.dart';
import '../tokens/colors.dart';

/// A rule between two things: one hairline in [WaxColors.hairline] across
/// the room it is given.
///
/// Horizontal between rows and sections, [WaxHairline.vertical] between
/// panes. With no room to fill along it, it takes none.
class WaxHairline extends StatelessWidget {
  const WaxHairline({this.extent, super.key}) : axis = Axis.horizontal;

  const WaxHairline.vertical({this.extent, super.key}) : axis = Axis.vertical;

  /// Which way the line runs.
  final Axis axis;

  /// The band the line is centred in, across it: a rule between rows
  /// takes a little air, one between panes none. Null is the line alone.
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final thickness = WaxLayout.of(context).hairlineWidth;
    final color = WaxColors.of(context).hairline;
    final across = math.max(extent ?? 0, thickness);
    return switch (axis) {
      Axis.horizontal => SizedBox(
        height: across,
        child: Center(
          child: Container(height: thickness, color: color),
        ),
      ),
      Axis.vertical => SizedBox(
        width: across,
        child: Center(
          child: Container(width: thickness, color: color),
        ),
      ),
    };
  }
}
