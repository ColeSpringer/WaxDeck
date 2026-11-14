import 'package:material_ui/material_ui.dart';

/// The style a bare Text inherits, held still across a theme switch.
///
/// A framework `Material` wraps its child in an animated default text style
/// that eases into the new theme over its animation duration, and the
/// framework's `Scaffold` has one that takes no duration. Text that
/// inherits its colour from under it draws the old theme's ink first. A
/// plain style between the Material and the content changes once, with the
/// theme.
class WaxPlainTextStyle extends StatelessWidget {
  const WaxPlainTextStyle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: Theme.of(context).textTheme.bodyMedium!,
    child: child,
  );
}
