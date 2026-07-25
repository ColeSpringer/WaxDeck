/// How tightly rows and paddings pack.
///
/// Density is the power-user knob from Appearance settings. It multiplies
/// list row heights and vertical paddings only: type sizes never shrink
/// (text scaling belongs to the OS accessibility setting), and touch
/// targets never drop below 44 px on touch platforms however compact the
/// setting is.
enum WaxDensity {
  comfortable(1.0),
  compact(0.85);

  const WaxDensity(this.scale);

  final double scale;

  /// Applies the multiplier to a vertical measure.
  double vertical(double value) => value * scale;
}
