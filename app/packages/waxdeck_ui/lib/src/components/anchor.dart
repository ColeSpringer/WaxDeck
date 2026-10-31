import 'package:material_ui/material_ui.dart';

/// Where a floating label hangs from: the middle of [context]'s box, in
/// the coordinates of the overlay it will be laid out in, and half the
/// box's height.
///
/// Measured against that overlay rather than the window, since the two
/// are only the same when the overlay fills it, and the app's do not: a
/// screen inside the shell sits in a branch navigator whose overlay
/// begins after the nav rail. Null while the box has not been laid out.
({Offset target, double halfHeight})? measureAnchor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final overlay = Overlay.of(
    context,
    rootOverlay: false,
  ).context.findRenderObject();
  if (overlay is! RenderBox) return null;
  return (
    target: box.localToGlobal(box.size.center(Offset.zero), ancestor: overlay),
    halfHeight: box.size.height / 2,
  );
}

/// Below the target where the overlay has room for the child, above it
/// where it does not, and never off an edge. The same rule Material's
/// tooltip follows, through the same helper.
class AnchorLayout extends SingleChildLayoutDelegate {
  const AnchorLayout({
    required this.target,
    required this.verticalOffset,
    this.preferBelow = true,
  });

  final Offset target;
  final double verticalOffset;
  final bool preferBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: target,
    verticalOffset: verticalOffset,
    preferBelow: preferBelow,
  );

  @override
  bool shouldRelayout(AnchorLayout old) =>
      target != old.target ||
      verticalOffset != old.verticalOffset ||
      preferBelow != old.preferBelow;
}
