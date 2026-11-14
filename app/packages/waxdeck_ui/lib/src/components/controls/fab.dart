import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../theme/theme_landing.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../tooltip.dart';
import 'tappable.dart';

/// The floating primary action: one accented disc over the content.
///
/// A page gets at most one, and only where the action is what the page is
/// for. It sits above the deck bar's slot rather than over it, which the
/// scaffold arranges by handing this to `Scaffold.floatingActionButton`
/// inside its own column.
class WaxFab extends StatelessWidget {
  const WaxFab({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.semanticsId,
    super.key,
  });

  final WaxGlyph glyph;

  /// The accessible name and the tooltip. A fab draws no text, so this is
  /// the only name it has.
  final String label;

  final VoidCallback? onPressed;
  final String? semanticsId;

  /// The disc's diameter. Larger than a touch target on purpose: it is
  /// the one control on the page that should be hittable without looking.
  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onPressed != null;
    return WaxTappable(
      label: label,
      onPressed: onPressed,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      child: WaxTooltip(
        message: label,
        // The lift eases when the button is enabled or not, and lands with
        // the theme, which would otherwise ease its shadow.
        child: WaxThemeLanding(
          duration: kThemeChangeDuration,
          builder: (context, duration) => Material(
            color: enabled ? colors.accent : colors.surface2,
            shape: const CircleBorder(),
            elevation: enabled ? 3 : 0,
            animationDuration: duration,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: WaxIcon(
                    glyph,
                    size: 24,
                    color: enabled ? colors.onAccent : colors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
