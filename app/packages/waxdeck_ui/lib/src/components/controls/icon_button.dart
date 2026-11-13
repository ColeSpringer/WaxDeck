import 'package:material_ui/material_ui.dart';

import '../../icons/wax_icon.dart';
import '../../tokens/colors.dart';
import '../../tokens/radii.dart';
import '../../tokens/spacing.dart';
import '../../tokens/typography.dart';
import '../indicators.dart';
import '../tooltip.dart';
import 'tappable.dart';

/// An icon-only control. Always has an accessible name, and a tooltip on
/// pointer platforms, because the glyph is the whole meaning.
class WaxIconButton extends StatelessWidget {
  const WaxIconButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size = 20,
    this.color,
    this.semanticsId,
    this.badge,
    this.busy = false,
    this.status = false,
    this.detail,
    super.key,
  }) : assert(!(busy && status), 'busy and status are one state at a time');

  final WaxGlyph glyph;

  /// The accessible name, and the hover label. Stateful controls say what
  /// they will do: "Play" when paused, "Pause" when playing.
  final String label;

  /// Null disables it, drawn in the disabled tint whatever [active] says.
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;
  final String? semanticsId;

  /// A count or a countdown drawn on the glyph, such as the sleep
  /// timer's remaining minutes.
  final String? badge;

  /// Work this control started is in flight: it takes no press and draws
  /// a [WaxSpinner] where its glyph was.
  final bool busy;

  /// A state to read, not an action to take, such as a finished
  /// download: no press whatever [onPressed] says, no button to a screen
  /// reader, and drawn lit, in [color] or accent while [active] and in
  /// secondary ink while not.
  final bool status;

  /// What the label leaves out, such as why the action failed: the
  /// tooltip's second line, on hover, focus or long press, and read after
  /// the name.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final enabled = onPressed != null && !busy && !status;
    final tint = status
        ? (active ? color ?? colors.accent : colors.textSecondary)
        : onPressed == null && !busy
        ? colors.textDisabled
        : color ?? (active ? colors.accent : colors.textSecondary);

    Widget icon = busy
        ? WaxSpinner(size: size, color: tint)
        : WaxIcon(glyph, size: size, color: tint, active: active);
    if (badge != null && !busy) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          icon,
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: WaxRadius.pill,
              ),
              child: Text(
                badge!,
                style: WaxType.caption.copyWith(
                  color: colors.onAccent,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final pad = InkResponse(
      onTap: enabled ? onPressed : null,
      radius: WaxSpace.touchTarget / 2,
      child: SizedBox(
        width: WaxSpace.touchTarget,
        height: WaxSpace.touchTarget,
        child: Center(child: icon),
      ),
    );

    return WaxTappable(
      label: label,
      onPressed: status ? null : onPressed,
      busy: busy,
      inert: status,
      hint: detail,
      // With a detail the tappable's own tooltip carries both lines and
      // opens on focus too, as a pill's detail does.
      tooltip: detail == null ? null : '$label\n$detail',
      tooltipOnLongPress: true,
      semanticsId: semanticsId,
      borderRadius: WaxRadius.pill,
      child: detail == null ? WaxTooltip(message: label, child: pad) : pad,
    );
  }
}
