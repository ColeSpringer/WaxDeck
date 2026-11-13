import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../l10n/wax_l10n.dart';
import '../../tokens/colors.dart';
import '../../tokens/motion.dart';
import 'icon_button.dart';

/// The star toggle, with the pop the design language asks for.
///
/// Optimistic state belongs to the app's controllers; this draws whatever
/// it is given and reports the action it will perform, which is the
/// vocabulary the accessibility audit freezes ("Star" / "Unstar").
class StarButton extends StatelessWidget {
  const StarButton({
    required this.starred,
    required this.onChanged,
    this.size = 20,
    this.semanticsId,
    super.key,
  });

  final bool starred;
  final ValueChanged<bool>? onChanged;
  final double size;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final motion = WaxMotion.of(context);
    return AnimatedScale(
      // The star pops on the way in and holds still under reduced
      // motion, which the duration token handles for us.
      scale: starred ? 1.08 : 1,
      duration: motion.standard,
      curve: WaxMotion.emphasized,
      child: WaxIconButton(
        glyph: WaxIcons.star,
        label: starred
            ? context.waxL10n.controlsUnstar
            : context.waxL10n.controlsStar,
        semanticsId: semanticsId,
        active: starred,
        size: size,
        color: starred ? colors.accent : colors.textSecondary,
        onPressed: onChanged == null ? null : () => onChanged!(!starred),
      ),
    );
  }
}
