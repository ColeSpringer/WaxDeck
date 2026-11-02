import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../player/speed_sheet.dart'
    show clampSpeed, speedMax, speedMin, speedStep;

/// A playback-rate slider over the contract's speed band, mapped onto the
/// design system's zero to one level.
class SpeedSlider extends StatelessWidget {
  const SpeedSlider({
    super.key,
    required this.speed,
    required this.label,
    required this.semanticsId,
    required this.onChanged,
  });

  final double speed;
  final String label;
  final String semanticsId;
  final ValueChanged<double> onChanged;

  static const double _span = speedMax - speedMin;

  static double _speedOf(double level) => clampSpeed(speedMin + level * _span);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) => WaxSlider(
        value: (speed - speedMin) / _span,
        label: label,
        semanticsId: semanticsId,
        step: speedStep / _span,
        trackWidth: (constraints.maxWidth - 2 * WaxSlider.defaultEndSlop).clamp(
          96,
          double.infinity,
        ),
        valueLabel: (level) => l10n.formatSpeed(_speedOf(level)),
        onChanged: (level) => onChanged(_speedOf(level)),
      ),
    );
  }
}
