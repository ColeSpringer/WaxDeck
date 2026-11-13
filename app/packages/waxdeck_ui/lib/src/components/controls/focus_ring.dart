import 'package:material_ui/material_ui.dart';

import '../../theme/wax_layout.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';

/// The two-tone focus ring.
///
/// An inner ring in the underlying surface colour and an outer ring in
/// accent, so focus stays visible on every background including an
/// active amber element. A single amber ring disappears exactly where it
/// matters most (a focused active tab), which is a WCAG 2.4.11 failure.
class WaxFocusRing extends StatelessWidget {
  const WaxFocusRing({
    required this.focused,
    required this.child,
    this.borderRadius = WaxRadius.thumb,
    this.surface,
    super.key,
  });

  final bool focused;
  final Widget child;
  final BorderRadius borderRadius;

  /// The colour immediately under the ring. Defaults to the card surface.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final inner = surface ?? colors.surface1;
    // The CustomPaint is always here and only its painter comes and goes.
    // Returning the bare child while unfocused would change the shape of
    // the element tree the moment focus arrived, and a child whose parent
    // changes type is rebuilt from scratch - which for a text field means
    // losing its state and its input connection on the way in.
    return CustomPaint(
      foregroundPainter: focused
          ? _FocusRingPainter(
              radius: borderRadius,
              inner: inner,
              outer: colors.accent,
              innerWidth: layout.focusRingInnerWidth,
              outerWidth: layout.focusRingWidth,
              offset: layout.focusRingOffset,
            )
          : null,
      child: child,
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.radius,
    required this.inner,
    required this.outer,
    required this.innerWidth,
    required this.outerWidth,
    required this.offset,
  });

  final BorderRadius radius;
  final Color inner;
  final Color outer;
  final double innerWidth;
  final double outerWidth;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final innerRect = radius.toRRect(rect.inflate(offset));
    final outerRect = radius.toRRect(rect.inflate(offset + innerWidth));
    canvas.drawRRect(
      innerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerWidth
        ..color = inner,
    );
    canvas.drawRRect(
      outerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerWidth
        ..color = outer,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) =>
      old.inner != inner || old.outer != outer;
}
