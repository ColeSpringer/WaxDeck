import 'package:flutter/widgets.dart';

/// [child] in a box at least the size of [reserve], which is laid out but
/// never drawn or read: a label whose text changes keeps one size.
class ReservedSize extends StatelessWidget {
  const ReservedSize({
    required this.reserve,
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget reserve;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: alignment,
    children: <Widget>[
      Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: reserve,
      ),
      child,
    ],
  );
}
