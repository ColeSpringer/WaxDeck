import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The tokens themselves: colour, type, icons, shape, spacing, motion.
///
/// Reviewing a component starts here, because every component is these
/// values arranged. Each swatch prints its own contrast ratio, so a
/// pairing that fails is visible before it reaches a screen.
class FoundationsPage extends StatelessWidget {
  const FoundationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(WaxSpace.s24),
      children: <Widget>[
        const SectionHeader(overline: 'Foundations', title: 'Surfaces'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            _Swatch('canvas', colors.canvas, colors.textPrimary),
            _Swatch('surface1', colors.surface1, colors.textPrimary),
            _Swatch('surface2', colors.surface2, colors.textPrimary),
            _Swatch('surface3', colors.surface3, colors.textPrimary),
            // Decorative: hairlines owe no ratio.
            _Swatch(
              'hairline',
              colors.hairline,
              colors.textPrimary,
              minimum: null,
            ),
            _Swatch(
              'outline',
              colors.outline,
              colors.canvas,
              minimum: WaxContrast.aaLarge,
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'Text on canvas'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            _Swatch('textPrimary', colors.canvas, colors.textPrimary),
            _Swatch('textSecondary', colors.canvas, colors.textSecondary),
            _Swatch('textTertiary', colors.canvas, colors.textTertiary),
            // The documented exemption: disabled is sub-AA by design.
            _Swatch(
              'textDisabled',
              colors.canvas,
              colors.textDisabled,
              minimum: null,
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'Accent and state'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            _Swatch('accent', colors.accent, colors.onAccent),
            _Swatch(
              'accentContainer',
              colors.accentContainer,
              colors.onAccentContainer,
            ),
            _Swatch('success', colors.success, colors.onSuccess),
            _Swatch('error', colors.error, colors.onError),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'Domain hues'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            for (final domain in WaxDomain.values) ...<Widget>[
              _Swatch(
                '${domain.name} hue',
                colors.domain(domain).hue,
                colors.canvas,
                minimum: WaxContrast.aaLarge,
              ),
              _Swatch(
                '${domain.name} container',
                colors.domain(domain).container,
                colors.domain(domain).onContainer,
              ),
            ],
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'The pair matrix'),
        const SizedBox(height: WaxSpace.s12),
        const _PairMatrix(),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'Type scale'),
        _Type('display 30/36 Archivo Expanded 640', WaxType.display),
        _Type('titleScreen 24/30', WaxType.titleScreen),
        _Type('titleEntity 21/27', WaxType.titleEntity),
        _Type('headline 18/24', WaxType.headline),
        _Type('titleItem 15.5/21 Inter 600', WaxType.titleItem),
        _Type('body 14/20 Inter 460', WaxType.body),
        _Type('bodySmall 13/18', WaxType.bodySmall),
        _Type('label 13/16 Inter 560', WaxType.label),
        _Type('caption 11.5/15', WaxType.caption),
        _Type('overline 11/14 Inter 620', WaxType.overline),
        _Type('monoTime 13/16 Spline Sans Mono 520', WaxType.monoTime),
        _Type('monoData 12/16', WaxType.monoData),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(
          overline: 'Foundations',
          title: 'Scripts the chain owns',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: WaxSpace.s24),
          child: Text(
            'Πρωί · Тихая гавань · حديقة الليل · שלום · สวัสดี',
            style: WaxType.titleEntity.copyWith(color: colors.textPrimary),
          ),
        ),
        const SectionHeader(overline: 'Foundations', title: 'Icons'),
        Wrap(
          spacing: WaxSpace.s16,
          runSpacing: WaxSpace.s16,
          children: <Widget>[
            for (final entry in WaxIcons.all.entries)
              SizedBox(
                width: 92,
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        WaxIcon(entry.value, color: colors.textSecondary),
                        const SizedBox(width: WaxSpace.s8),
                        WaxIcon(
                          entry.value,
                          active: true,
                          color: colors.accent,
                        ),
                      ],
                    ),
                    Text(
                      entry.key,
                      style: WaxType.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: WaxSpace.s24),
        const SectionHeader(overline: 'Foundations', title: 'Shape and motion'),
        Wrap(
          spacing: WaxSpace.s12,
          runSpacing: WaxSpace.s12,
          children: <Widget>[
            for (final entry in <String, double>{
              'r6': WaxRadius.r6,
              'r10': WaxRadius.r10,
              'r14': WaxRadius.r14,
              'r20': WaxRadius.r20,
              'full': WaxRadius.full,
            }.entries)
              Container(
                width: 84,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(entry.value),
                  border: Border.all(color: colors.hairline),
                ),
                alignment: Alignment.center,
                child: Text(entry.key, style: WaxType.monoData),
              ),
          ],
        ),
        const SizedBox(height: WaxSpace.s12),
        Text(
          'Motion: press ${WaxMotion.of(context).pressFeedback.inMilliseconds} ms, '
          'quick ${WaxMotion.of(context).quick.inMilliseconds} ms, '
          'standard ${WaxMotion.of(context).standard.inMilliseconds} ms, '
          'deck ${WaxMotion.of(context).deckExpand.inMilliseconds} ms'
          '${WaxMotion.of(context).animationsEnabled ? '' : ' (reduced motion)'}',
          style: WaxType.monoData.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s32),
        const WaxBrandBlock(tagline: 'Music, podcasts, and audiobooks'),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
    this.name,
    this.background,
    this.foreground, {
    this.minimum = WaxContrast.aaText,
  });

  final String name;
  final Color background;
  final Color foreground;

  /// The AA bar this pairing owes; null for pairs that owe none
  /// (hairlines, the disabled exemption).
  final double? minimum;

  @override
  Widget build(BuildContext context) {
    final ratio = WaxContrast.ratio(foreground, background);
    final bar = minimum;
    final verdict = bar == null
        ? ''
        : WaxContrast.meets(foreground, background, bar)
        ? '  AA'
        : '  FAILS $bar';
    return Container(
      width: 168,
      height: 88,
      padding: const EdgeInsets.all(WaxSpace.s8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: WaxRadius.card,
        border: Border.all(color: WaxColors.of(context).hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(name, style: WaxType.label.copyWith(color: foreground)),
          Text(
            '${ratio.toStringAsFixed(2)}:1$verdict',
            style: WaxType.monoData.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// A hand-kept mirror of the pairs `contrast_test.dart` enumerates,
/// drawn so the audit can be reviewed by eye per theme.
class _PairMatrix extends StatelessWidget {
  const _PairMatrix();

  static const double labelWidth = WaxSpace.s64 + WaxSpace.s48;

  static const double cellWidth = WaxSpace.s64 + WaxSpace.s20;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final surfaces = <({String name, Color color, bool veil})>[
      (name: 'canvas', color: colors.canvas, veil: false),
      (name: 'surface1', color: colors.surface1, veil: false),
      (name: 'surface2', color: colors.surface2, veil: false),
      (name: 'surface3', color: colors.surface3, veil: false),
      (
        name: 'veil/white',
        color: WaxContrast.flatten(colors.veil, const Color(0xFFFFFFFF)),
        veil: true,
      ),
      (
        name: 'veil/black',
        color: WaxContrast.flatten(colors.veil, const Color(0xFF000000)),
        veil: true,
      ),
    ];
    final text = <String, Color>{
      'textPrimary': colors.textPrimary,
      'textSecondary': colors.textSecondary,
      'textTertiary': colors.textTertiary,
      'accent': colors.accent,
      'success': colors.success,
      'error': colors.error,
    };
    final ui = <String, Color>{
      'outline': colors.outline,
      for (final domain in WaxDomain.values)
        '${domain.name} hue': colors.domain(domain).hue,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: _PairMatrix.labelWidth),
              for (final surface in surfaces)
                SizedBox(
                  width: _PairMatrix.cellWidth,
                  child: Text(
                    surface.name,
                    style: WaxType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: WaxSpace.s4),
          for (final fg in text.entries)
            _MatrixRow(
              name: fg.key,
              foreground: fg.value,
              surfaces: surfaces,
              minimum: WaxContrast.aaText,
            ),
          // Shape foregrounds never sit on the veil, so their veil
          // cells stay blank rather than crying wolf.
          for (final fg in ui.entries)
            _MatrixRow(
              name: fg.key,
              foreground: fg.value,
              surfaces: surfaces,
              minimum: WaxContrast.aaLarge,
              onVeil: false,
            ),
        ],
      ),
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({
    required this.name,
    required this.foreground,
    required this.surfaces,
    required this.minimum,
    this.onVeil = true,
  });

  final String name;
  final Color foreground;
  final List<({String name, Color color, bool veil})> surfaces;
  final double minimum;

  /// Whether this foreground ever lands on the veil.
  final bool onVeil;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: _PairMatrix.labelWidth,
          child: Text(
            name,
            style: WaxType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        for (final surface in surfaces)
          if (onVeil || !surface.veil)
            _MatrixCell(
              foreground: foreground,
              background: surface.color,
              minimum: minimum,
            )
          else
            const SizedBox(width: _PairMatrix.cellWidth),
      ],
    );
  }
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    required this.foreground,
    required this.background,
    required this.minimum,
  });

  final Color foreground;
  final Color background;
  final double minimum;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final ratio = WaxContrast.ratio(foreground, background);
    final passes = WaxContrast.meets(foreground, background, minimum);
    return Container(
      width: _PairMatrix.cellWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: WaxSpace.s8,
        vertical: WaxSpace.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: passes ? colors.hairline : colors.error,
          width: passes ? 0.5 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Aa', style: WaxType.bodySmall.copyWith(color: foreground)),
          Text(
            passes ? ratio.toStringAsFixed(1) : '${ratio.toStringAsFixed(1)}!',
            style: WaxType.monoData.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class _Type extends StatelessWidget {
  const _Type(this.label, this.style);

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: WaxType.monoData.copyWith(color: colors.textTertiary),
          ),
          Text(
            'Nightjar - Salt Harbour 02:41',
            style: style.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
