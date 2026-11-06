import 'package:material_ui/material_ui.dart';

import '../icons/wax_icon.dart';
import '../tokens/colors.dart';
import '../tokens/motion.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'controls.dart';

/// A titled section that opens and closes: the title is the control, and
/// what it holds is only there while it is open.
///
/// The title is one button that says whether the section is open, which a
/// press, Enter or Space toggles. Closed, the section's children are not
/// built, so nothing in them can be tabbed to or read. Opening grows the
/// section into its room; under reduced motion nothing moves, and it
/// fades in at its full size.
class WaxDisclosure extends StatefulWidget {
  const WaxDisclosure({
    required this.title,
    required this.children,
    this.onExpansionChanged,
    this.semanticsId,
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// Told each time it opens or closes, such as to load what it holds the
  /// first time somebody asks for it.
  final ValueChanged<bool>? onExpansionChanged;

  /// The title's handle, on the node that carries the press.
  final String? semanticsId;

  @override
  State<WaxDisclosure> createState() => _WaxDisclosureState();
}

class _WaxDisclosureState extends State<WaxDisclosure>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  late final AnimationController _open = AnimationController(vsync: this);

  void _toggle() {
    final motion = WaxMotion.of(context);
    setState(() => _expanded = !_expanded);
    _open.duration = motion.animationsEnabled ? motion.standard : motion.quick;
    if (_expanded) {
      _open.forward();
    } else {
      _open.reverse();
    }
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    final header = WaxInkTappable(
      label: widget.title,
      semanticsId: widget.semanticsId,
      expanded: _expanded,
      onPressed: _toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WaxSpace.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WaxSpace.s8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  style: WaxType.headline.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: WaxSpace.s8),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: motion.animationsEnabled
                    ? motion.standard
                    : Duration.zero,
                curve: WaxMotion.emphasized,
                child: WaxIcon(
                  WaxIcons.caretDown,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final body = AnimatedBuilder(
      animation: _open,
      builder: (context, child) {
        // Closed and settled: nothing under the title for a pointer, a
        // key or a reader to find.
        if (!_expanded && _open.isDismissed) return const SizedBox.shrink();
        return motion.animationsEnabled
            ? ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  heightFactor: WaxMotion.emphasized.transform(_open.value),
                  child: child,
                ),
              )
            : Opacity(opacity: _open.value, child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[header, body],
    );
  }
}
