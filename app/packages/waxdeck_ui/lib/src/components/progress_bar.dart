import 'package:material_ui/material_ui.dart';

import '../l10n/wax_l10n.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/radii.dart';

/// A linear progress bar: how far some work has got, or that it is
/// working at all.
///
/// [value] is a fraction from zero to one and reads aloud the way every
/// other proportion in the design system does; null is a bar of unknown
/// length, which sweeps a segment across the track and holds it still
/// under reduced motion. It is a page's bar: a button's own progress and
/// a control's spinner are drawn by those controls.
class WaxProgressBar extends StatefulWidget {
  const WaxProgressBar({this.value, this.semanticsLabel, this.tone, super.key});

  /// How far along, from zero to one (held to that range). Null is
  /// indeterminate, and so is any value that is not finite (NaN from 0
  /// of 0, or infinity).
  final double? value;

  /// What the bar is measuring, such as "Scanning". Without one the bar
  /// reports only its value.
  final String? semanticsLabel;

  /// The fill's colour where it carries a verdict, such as a quota at or
  /// over its cap. Null draws it in the accent, which is what most bars
  /// want.
  final Color? tone;

  /// The bar's height.
  static const double height = 4;

  @override
  State<WaxProgressBar> createState() => _WaxProgressBarState();
}

class _WaxProgressBarState extends State<WaxProgressBar>
    with SingleTickerProviderStateMixin {
  /// The share of the track the indeterminate segment covers.
  static const double _segment = 0.4;

  /// Where the segment rests when motion is off, inside the track.
  static const double _held = 0.3;

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// The value held to the track, or null where there is none to draw.
  double? get _fraction {
    final value = widget.value;
    return value == null || !value.isFinite ? null : value.clamp(0.0, 1.0);
  }

  /// Driven from here and from `didUpdateWidget` alike: a bar can gain or
  /// lose its value in place, and a sweep must not outlive it.
  void _sync() {
    final sweeping =
        _fraction == null && WaxMotion.of(context).animationsEnabled;
    if (sweeping && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!sweeping && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WaxProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final value = _fraction;
    final animated = WaxMotion.of(context).animationsEnabled;
    final fill = ColoredBox(color: widget.tone ?? colors.accent);
    final Widget bar;
    if (value == null) {
      bar = AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) {
          // Off the start edge to off the end edge, so the segment enters
          // and leaves rather than popping in at either.
          final t = animated ? _sweep.value : _held;
          final left = -_segment + t * (1 + _segment);
          return FractionallySizedBox(
            alignment: AlignmentDirectional(2 * left / (1 - _segment) - 1, 0),
            widthFactor: _segment,
            child: child,
          );
        },
        child: fill,
      );
    } else {
      bar = FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: value,
        child: fill,
      );
    }
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      value: value == null ? null : context.waxL10n.spellPercent(value),
      excludeSemantics: true,
      child: SizedBox(
        height: WaxProgressBar.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WaxRadius.r6),
          child: ColoredBox(
            color: colors.hairline,
            child: SizedBox.expand(child: bar),
          ),
        ),
      ),
    );
  }
}
