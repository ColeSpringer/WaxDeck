import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Whether a route on the root navigator covers everything signed in. A
/// dialog opens there (the command palette, a confirm) and leaves every
/// route on the signed-in navigator current, so none of them can tell.
class SignedInCover extends StatelessWidget {
  const SignedInCover({required this.child, super.key});

  final Widget child;

  /// Whether something on the root navigator is over [context]'s screen.
  static bool coveredOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Covered>()?.covered ?? false;

  /// Whether [context]'s screen is what the user sees: its tickers run and
  /// no route covers it, on its own navigator or the root.
  static bool showing(BuildContext context) =>
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      !coveredOf(context);

  @override
  Widget build(BuildContext context) => _Covered(
    covered: !(ModalRoute.isCurrentOf(context) ?? true),
    child: child,
  );
}

class _Covered extends InheritedWidget {
  const _Covered({required this.covered, required super.child});

  final bool covered;

  @override
  bool updateShouldNotify(_Covered old) => covered != old.covered;
}
