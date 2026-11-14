import 'package:material_ui/material_ui.dart';

import '../tokens/colors.dart';

/// Hands [builder] [duration], or zero on the build in which the theme's
/// colours changed.
///
/// An implicit animation retargets whenever its target moves, so one whose
/// target is a theme colour would ease out of the old theme while the
/// canvas around it has already landed. Through this it lands with the
/// theme, and its own state changes (hover, selection, focus, a drag)
/// still ease over [duration].
class WaxThemeLanding extends StatefulWidget {
  const WaxThemeLanding({
    required this.duration,
    required this.builder,
    super.key,
  });

  /// The motion token the animation eases its own changes over.
  final Duration duration;

  /// Builds the animation with the duration to give it: zero on the build
  /// that carries a theme switch.
  final Widget Function(BuildContext context, Duration duration) builder;

  @override
  State<WaxThemeLanding> createState() => _WaxThemeLandingState();
}

class _WaxThemeLandingState extends State<WaxThemeLanding> {
  WaxColors? _colors;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    // By value: the app builds its theme afresh, and an equal one is not a
    // switch.
    final switched = _colors != null && _colors != colors;
    _colors = colors;
    return widget.builder(context, switched ? Duration.zero : widget.duration);
  }
}
